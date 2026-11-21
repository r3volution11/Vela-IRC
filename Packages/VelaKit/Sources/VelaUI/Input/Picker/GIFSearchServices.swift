// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import VelaMedia
import VelaStore

/// The KLIPY key built into release builds.
///
/// It's never in the repository: the release build passes it in as the
/// `VELA_KLIPY_API_KEY` build setting, which Info.plist's
/// `VelaKLIPYAPIKey` carries into the app. Development builds get it from a
/// git-ignored xcconfig, or go without (the GIFs tab then says so).
enum BuiltInGIFKeys {
    static let infoPlistKey = "VelaKLIPYAPIKey"

    static func klipy(in bundle: Bundle = .main) -> String? {
        klipy(from: bundle.object(forInfoDictionaryKey: infoPlistKey))
    }

    /// The key from an Info.plist value: nil when it's missing, blank, or a
    /// build setting that was never filled in (`$(VELA_KLIPY_API_KEY)`).
    static func klipy(from value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }
}

/// Keys entered in Settings → Media, kept in the Keychain (never
/// settings.json).
@MainActor
final class GIFKeyStore {
    private let keychain: Keychain
    /// Read once each, on first use: the Keychain isn't touched until the
    /// GIFs tab or the settings ask.
    private var loaded: [GIFService: String?] = [:]

    init(keychain: Keychain) {
        self.keychain = keychain
    }

    func key(for service: GIFService) -> String? {
        if let cached = loaded[service] { return cached }
        let key = keychain.secret(account: Keychain.gifServiceKeyAccount(service)).flatMap(Self.cleaned)
        loaded[service] = .some(key)
        return key
    }

    /// Saves `key` (or removes the saved one, for nil or blank).
    func setKey(_ key: String?, for service: GIFService) throws {
        let account = Keychain.gifServiceKeyAccount(service)
        if let key = key.flatMap(Self.cleaned) {
            try keychain.setSecret(key, account: account)
            loaded[service] = .some(key)
        } else {
            keychain.deleteSecret(account: account)
            loaded[service] = .some(nil)
        }
    }

    static func cleaned(_ key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Which GIF service the picker uses and with what key, as settings and
/// keys stand.
struct GIFSearchSetup {
    enum Problem: Equatable {
        /// KLIPY with neither a built-in key nor your own.
        case noBuiltInKey
        /// GIPHY without your own key.
        case needsOwnKey
    }

    var service: GIFService
    var provider: any GIFSearchProvider
    var apiKey: String?
    /// Your own key, rather than the one built into Vela.
    var usesOwnKey: Bool

    var problem: Problem? {
        guard apiKey == nil else { return nil }
        return service == .klipy ? .noBuiltInKey : .needsOwnKey
    }
}

/// Everything GIF search needs, made on first use: nothing here exists
/// until the GIFs tab is shown (or Settings asks about keys).
///
/// It keeps one ``GIFSearchClient`` per service and key for the session,
/// so trending and recent searches are answered from memory when the
/// picker opens again, and the preview loader, whose images stay in
/// memory only (never on disk), within a budget.
@MainActor
final class GIFSearchServices {
    /// The app's, made the first time it's asked for.
    static var shared: GIFSearchServices {
        if let made { return made }
        let services = GIFSearchServices(keys: GIFKeyStore(keychain: .shared), builtInKLIPYKey: BuiltInGIFKeys.klipy())
        made = services
        return services
    }

    /// The app's, if anything asked for them yet.
    static private(set) var made: GIFSearchServices?

    let keys: GIFKeyStore
    let builtInKLIPYKey: String?
    private let makeProvider: (GIFService) -> any GIFSearchProvider
    private let transport: any GIFSearchTransport
    private let previewSession: () -> URLSession
    private var clients: [ClientKey: GIFSearchClient] = [:]
    private var loader: ImageLoader?

    private struct ClientKey: Hashable {
        var service: GIFService
        var apiKey: String
    }

    /// Preview images kept in memory: halved on 8 GB Macs. Encoded images
    /// and decoded stills get this much each.
    static let previewMemoryBudget = MemoryBudget.scaled(12 * 1024 * 1024)
    /// The largest preview loaded (a small WebP is well under).
    static let maxPreviewBytes = 3 * 1024 * 1024
    /// Decoded frames a playing cell keeps, so its later loops cost no
    /// decoding: a 15-frame preview at 216 px is about 2.8 MB. Only cells in
    /// view play, so about a dozen at once. Longer previews decode as they go.
    static var keptFramesPerPreview = 3 * 1024 * 1024

    init(
        keys: GIFKeyStore,
        builtInKLIPYKey: String?,
        makeProvider: @escaping (GIFService) -> any GIFSearchProvider = GIFSearchServices.provider(for:),
        transport: any GIFSearchTransport = URLSessionGIFTransport(),
        previewSession: @escaping () -> URLSession = URLSessionGIFTransport.makeSession
    ) {
        self.keys = keys
        self.builtInKLIPYKey = builtInKLIPYKey
        self.makeProvider = makeProvider
        self.transport = transport
        self.previewSession = previewSession
        MemoryPressureMonitor.shared.register(self) { services, level in
            services.trim(keeping: level.keptFraction)
        }
    }

    nonisolated static func provider(for service: GIFService) -> any GIFSearchProvider {
        switch service {
        case .klipy: KLIPYProvider()
        case .giphy: GIPHYProvider()
        }
    }

    /// The service and key to use for `service`.
    func setup(for service: GIFService) -> GIFSearchSetup {
        let own = keys.key(for: service)
        let key = own ?? (service == .klipy ? builtInKLIPYKey : nil)
        return GIFSearchSetup(service: service, provider: makeProvider(service), apiKey: key, usesOwnKey: own != nil)
    }

    /// The session's client for a setup with a key.
    func client(for setup: GIFSearchSetup) -> GIFSearchClient? {
        guard let apiKey = setup.apiKey else { return nil }
        let key = ClientKey(service: setup.service, apiKey: apiKey)
        if let client = clients[key] { return client }
        let client = GIFSearchClient(provider: setup.provider, apiKey: apiKey, transport: transport)
        clients[key] = client
        return client
    }

    /// Loads the grid's previews (and the message box's GIF chip): an
    /// ephemeral session, so nothing is written to disk.
    var previewLoader: ImageLoader {
        if let loader { return loader }
        let made = ImageLoader(session: previewSession(), memoryLimit: Self.previewMemoryBudget)
        loader = made
        return made
    }

    /// The grid's playing previews, held weakly: stopped and let go when
    /// the picker closes, whatever SwiftUI keeps of its views.
    private let players = NSHashTable<AnimatedImagePlayer>.weakObjects()

    func previewStarted(_ player: AnimatedImagePlayer) {
        players.add(player)
    }

    /// Previews playing now (for tests and the benchmark).
    var playingPreviews: Int { players.allObjects.count(where: \.isPlaying) }

    /// The GIFs tab's model, while a picker has one: stopped when the
    /// picker closes, so a search waiting for its pause isn't sent after.
    private weak var activeModel: GIFPickerModel?

    func modelStarted(_ model: GIFPickerModel) {
        activeModel = model
    }

    /// The picker closed (the message box says so, as SwiftUI may keep the
    /// popover's views): searches stop, every preview stops and lets go of
    /// its frames, and the preview cache shrinks to a quarter. Previews
    /// from a service whose terms forbid keeping them (GIPHY) all go.
    func pickerClosed() {
        let provider = activeModel?.provider
        activeModel?.stop()
        activeModel = nil
        for player in players.allObjects { player.unload() }
        players.removeAllObjects()
        guard let loader else { return }
        let keepsThumbnails = provider?.allowsThumbnailCaching ?? true
        Task {
            if keepsThumbnails { await loader.trimCaches(keeping: 0.25) } else { await loader.removeAllCachedImages() }
        }
    }

    /// Memory pressure: previews are the first to go.
    func trim(keeping fraction: Double) {
        guard let loader else { return }
        Task {
            if fraction <= 0 { await loader.removeAllCachedImages() } else { await loader.trimCaches(keeping: fraction) }
        }
    }
}

extension EnvironmentValues {
    /// GIF search for the picker: tests put in their own (fake services,
    /// no network). Nil uses ``GIFSearchServices/shared``.
    @Entry var gifSearchServices: GIFSearchServices?
}
