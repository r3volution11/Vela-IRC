// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Network
import Observation
import VelaFoundation
import VelaIRC
import VelaMedia
import VelaStore

/// Secrets entered in the network editor. Stored in the Keychain, never in files.
nonisolated public struct NetworkSecrets: Sendable, Equatable {
    public var serverPassword: String?
    public var saslPassword: String?
    public var nickServPassword: String?

    public init(serverPassword: String? = nil, saslPassword: String? = nil, nickServPassword: String? = nil) {
        self.serverPassword = serverPassword
        self.saslPassword = saslPassword
        self.nickServPassword = nickServPassword
    }
}

/// The root model: networks, selection and app-wide services.
@Observable
public final class AppModel: SessionHost {
    public let settings: SettingsStore
    public let networkStore: NetworkConfigStore
    public let database: VelaDatabase?
    public let previewService: LinkPreviewService
    public let keychain: Keychain
    public let isDemo: Bool

    public private(set) var sessions: [NetworkSession] = []
    public private(set) var selectedBufferID: BufferID?
    public private(set) var lastError: String?

    /// Whether the main window is key; drives unread counting.
    public var isWindowActive = true {
        didSet {
            guard isWindowActive, !oldValue, let buffer = selectedBuffer, let session = selectedSession else { return }
            prepareUnreadMarker(buffer)
            session.markRead(buffer)
        }
    }

    @ObservationIgnored private let notifier: Notifier
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var sessionsConnectedBeforeSleep: Set<UUID> = []
    @ObservationIgnored private var started = false

    public init(
        settings: SettingsStore,
        networkStore: NetworkConfigStore,
        database: VelaDatabase?,
        keychain: Keychain = .shared,
        previewService: LinkPreviewService? = nil,
        notifier: Notifier? = nil,
        isDemo: Bool = false
    ) {
        self.settings = settings
        self.networkStore = networkStore
        self.database = database
        self.keychain = keychain
        self.isDemo = isDemo
        self.previewService = previewService ?? LinkPreviewService(cache: database.map(DatabasePreviewCache.init))
        self.notifier = notifier ?? (isDemo ? SilentNotifier() : UserNotificationNotifier())
    }

    /// The production configuration rooted in Application Support.
    public static func live() -> AppModel {
        let database: VelaDatabase?
        var startupError: String?
        do {
            database = try VelaDatabase(url: AppPaths.databaseURL)
        } catch {
            database = nil
            startupError = "Couldn't open the message database: \(error.localizedDescription)"
        }
        let networkStore = NetworkConfigStore(fileURL: AppPaths.networksURL)
        do { try networkStore.load() } catch { startupError = "Couldn't read networks.json: \(error.localizedDescription)" }
        let model = AppModel(
            settings: SettingsStore(fileURL: AppPaths.settingsURL),
            networkStore: networkStore,
            database: database
        )
        model.lastError = startupError
        return model
    }

    /// Offline sample content for screenshots, SwiftUI previews and UI work.
    public static func demo() -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaDemo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = AppModel(
            settings: SettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            networkStore: NetworkConfigStore(fileURL: root.appendingPathComponent("networks.json")),
            database: nil,
            isDemo: true
        )
        DemoContent.populate(model)
        return model
    }

    /// Starts sessions and system observers. Safe to call more than once.
    public func start() {
        guard !started else { return }
        started = true
        guard !isDemo else { return }

        for config in networkStore.networks {
            let session = makeSession(for: config)
            sessions.append(session)
        }
        Task {
            for session in sessions { await session.restoreBuffers() }
            restoreSelection()
            for session in sessions where session.config.autoConnect && !isOrphanedChild(session) {
                session.connect()
            }
        }
        observeSystem()
        pruneHistoryIfNeeded()
    }

    // MARK: SessionHost

    public var behavior: SessionBehavior {
        var behavior = SessionBehavior()
        behavior.autoReconnect = settings[.connectionAutoReconnect]
        behavior.sendTypingIndicators = settings[.inputSendTypingIndicators]
        behavior.highlightWords = settings[.highlightWords]
        behavior.scrollbackInMemory = max(200, settings[.chatScrollbackInMemory])
        return behavior
    }

    public func clientConfig(for session: NetworkSession) -> IRCClientConfig {
        // Bouncer child networks borrow the parent's connection details and credentials.
        let base = session.config.parentNetworkID.flatMap { id in networkStore.networks.first { $0.id == id } } ?? session.config
        var config = IRCClientConfig(
            host: base.host,
            port: base.port,
            useTLS: base.useTLS,
            nick: base.nick
        )
        config.allowInvalidCertificates = base.allowInvalidCertificates
        config.alternateNicks = base.alternateNicks
        config.username = base.username.isEmpty ? base.nick : base.username
        config.realname = base.realname.isEmpty ? base.nick : base.realname
        if base.hasServerPassword {
            config.serverPassword = keychain.secret(account: Keychain.account(networkID: base.id, purpose: .serverPassword))
        }
        switch base.saslKind {
        case .plain:
            if let password = keychain.secret(account: Keychain.account(networkID: base.id, purpose: .saslPassword)) {
                config.sasl = .plain(account: base.saslAccount ?? base.nick, password: password)
            }
        case .external:
            config.sasl = .external
        case .none:
            break
        }
        if let ref = base.clientCertificateRef, let identity = keychain.identity(persistentRef: ref) {
            config.clientIdentity = ClientIdentity(identity: identity)
        }
        config.bouncerNetworkID = session.config.bouncerNetworkID
        config.versionReply = "Vela \(Self.appVersion) on macOS — https://github.com/r3volution11/Vela-IRC"
        return config
    }

    public func isBufferVisible(_ id: BufferID) -> Bool {
        isWindowActive && selectedBufferID == id
    }

    public func activeBuffer(in session: NetworkSession) -> BufferModel? {
        guard let id = selectedBufferID, id.networkID == session.id else { return nil }
        return session.buffer(id: id)
    }

    public func session(_ session: NetworkSession, didReceiveNotable line: ChatLine, in buffer: BufferModel) {
        guard !isBufferVisible(buffer.id) || !NSApp.isActive else { return }
        let isQuery = buffer.kind == .query
        if line.isHighlight && !settings[.notifyHighlights] { return }
        if isQuery && !line.isHighlight && !settings[.notifyPrivateMessages] { return }
        let title = isQuery ? (line.nick ?? buffer.name) : "\(line.nick ?? "") in \(buffer.name)"
        let body = line.kind == .action ? "• \(line.nick ?? "") \(line.text)" : line.text
        notifier.post(
            title: title,
            subtitle: session.displayName,
            body: IRCFormatting.strip(body),
            bufferID: buffer.id,
            playSound: settings[.notifySound]
        )
    }

    public func session(_ session: NetworkSession, didUpdateBouncerNetworks networks: [BouncerNetwork]) {
        let existing = networkStore.networks.filter { $0.parentNetworkID == session.id }
        // Add or update children.
        for network in networks {
            if var child = existing.first(where: { $0.bouncerNetworkID == network.id }) {
                if child.name != network.name {
                    child.name = network.name
                    networkStore.upsert(child)
                    self.session(for: child.id)?.updateConfig(child)
                }
                continue
            }
            var child = session.config
            child.id = UUID()
            child.name = network.name
            child.parentNetworkID = session.id
            child.bouncerNetworkID = network.id
            child.autoJoin = []
            child.performCommands = []
            child.sortOrder = session.config.sortOrder
            child.createdAt = Date()
            child.modifiedAt = Date()
            networkStore.upsert(child)
            let childSession = makeSession(for: child)
            sessions.append(childSession)
            childSession.connect()
        }
        // Remove children the bouncer no longer has.
        let liveIDs = Set(networks.map(\.id))
        for child in existing where !liveIDs.contains(child.bouncerNetworkID ?? "") {
            removeNetwork(id: child.id)
        }
        sortSessions()
    }

    public func sessionDidChangeConfig(_ session: NetworkSession) {
        networkStore.upsert(session.config)
    }

    public func sessionDidChangeUnreadCounts(_ session: NetworkSession) {
        updateDockBadge()
    }

    // MARK: Selection

    public var selectedSession: NetworkSession? {
        guard let id = selectedBufferID else { return nil }
        return session(for: id.networkID)
    }

    public var selectedBuffer: BufferModel? {
        guard let id = selectedBufferID else { return nil }
        return session(for: id.networkID)?.buffer(id: id)
    }

    public func session(for id: UUID) -> NetworkSession? {
        sessions.first { $0.id == id }
    }

    public func select(_ buffer: BufferModel) {
        guard selectedBufferID != buffer.id else { return }
        selectedBufferID = buffer.id
        prepareUnreadMarker(buffer)
        session(for: buffer.id.networkID)?.markRead(buffer)
        UserDefaults.standard.set(buffer.id.description, forKey: "Vela.lastSelectedBuffer")
    }

    public func select(bufferID: BufferID) {
        guard let buffer = session(for: bufferID.networkID)?.buffer(id: bufferID) else { return }
        select(buffer)
    }

    /// Every selectable buffer, in sidebar order.
    public var orderedBuffers: [BufferModel] {
        sessions.flatMap { $0.isBouncerControl ? [$0.serverBuffer] : $0.allBuffers }
    }

    public func selectAdjacentBuffer(forward: Bool, unreadOnly: Bool = false) {
        let all = orderedBuffers
        guard !all.isEmpty else { return }
        let start = all.firstIndex { $0.id == selectedBufferID } ?? (forward ? -1 : all.count)
        var index = start
        for _ in 0..<all.count {
            index = (index + (forward ? 1 : -1) + all.count) % all.count
            let candidate = all[index]
            if !unreadOnly || candidate.unreadCount > 0 || candidate.highlightCount > 0 {
                select(candidate)
                return
            }
        }
    }

    private func prepareUnreadMarker(_ buffer: BufferModel) {
        buffer.unreadMarkerAfter = buffer.unreadCount > 0 ? (buffer.lastReadAt ?? .distantPast) : nil
    }

    private func restoreSelection() {
        if let saved = UserDefaults.standard.string(forKey: "Vela.lastSelectedBuffer"),
           let buffer = orderedBuffers.first(where: { $0.id.description == saved })
        {
            select(buffer)
        } else if let first = orderedBuffers.first {
            select(first)
        }
    }

    // MARK: Networks

    public func addNetwork(_ config: NetworkConfig, secrets: NetworkSecrets) {
        var config = config
        config.sortOrder = (networkStore.networks.map(\.sortOrder).max() ?? 0) + 1
        storeSecrets(secrets, for: &config)
        networkStore.upsert(config)
        let session = makeSession(for: config)
        sessions.append(session)
        sortSessions()
        select(session.serverBuffer)
        if config.autoConnect { session.connect() }
    }

    public func updateNetwork(_ config: NetworkConfig, secrets: NetworkSecrets?) {
        var config = config
        if let secrets { storeSecrets(secrets, for: &config) }
        networkStore.upsert(config)
        session(for: config.id)?.updateConfig(config)
        sortSessions()
    }

    public func removeNetwork(id: UUID) {
        for child in networkStore.networks where child.parentNetworkID == id {
            removeNetwork(id: child.id)
        }
        if let session = session(for: id) {
            session.shutdown()
            sessions.removeAll { $0.id == id }
        }
        if selectedBufferID?.networkID == id { selectedBufferID = nil }
        for purpose in [Keychain.SecretPurpose.serverPassword, .saslPassword, .nickServPassword] {
            keychain.deleteSecret(account: Keychain.account(networkID: id, purpose: purpose))
        }
        networkStore.remove(id: id)
        if let database { Task { try? await database.deleteNetwork(id) } }
        if selectedBufferID == nil, let first = orderedBuffers.first { select(first) }
        updateDockBadge()
    }

    public func secrets(for networkID: UUID) -> NetworkSecrets {
        NetworkSecrets(
            serverPassword: keychain.secret(account: Keychain.account(networkID: networkID, purpose: .serverPassword)),
            saslPassword: keychain.secret(account: Keychain.account(networkID: networkID, purpose: .saslPassword)),
            nickServPassword: keychain.secret(account: Keychain.account(networkID: networkID, purpose: .nickServPassword))
        )
    }

    private func storeSecrets(_ secrets: NetworkSecrets, for config: inout NetworkConfig) {
        func store(_ value: String?, _ purpose: Keychain.SecretPurpose) {
            let account = Keychain.account(networkID: config.id, purpose: purpose)
            if let value, !value.isEmpty {
                try? keychain.setSecret(value, account: account)
            } else {
                keychain.deleteSecret(account: account)
            }
        }
        store(secrets.serverPassword, .serverPassword)
        store(secrets.saslPassword, .saslPassword)
        store(secrets.nickServPassword, .nickServPassword)
        config.hasServerPassword = !(secrets.serverPassword ?? "").isEmpty
    }

    private func makeSession(for config: NetworkConfig) -> NetworkSession {
        let session = NetworkSession(config: config, database: database)
        session.host = self
        session.requestSelection = { [weak self] buffer in self?.select(buffer) }
        return session
    }

    private func sortSessions() {
        let order = Dictionary(uniqueKeysWithValues: networkStore.networks.enumerated().map { ($1.id, $0) })
        sessions.sort { lhs, rhs in
            // Keep bouncer children right after their parent.
            let l = lhs.config.parentNetworkID.flatMap { order[$0] } ?? order[lhs.id] ?? 0
            let r = rhs.config.parentNetworkID.flatMap { order[$0] } ?? order[rhs.id] ?? 0
            if l != r { return l < r }
            if (lhs.config.parentNetworkID == nil) != (rhs.config.parentNetworkID == nil) { return lhs.config.parentNetworkID == nil }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func isOrphanedChild(_ session: NetworkSession) -> Bool {
        guard let parent = session.config.parentNetworkID else { return false }
        return networkStore.networks.first { $0.id == parent } == nil
    }

    // MARK: Media policy

    public func mediaPolicy(for bufferID: BufferID?) -> MediaPolicy {
        var policy = MediaPolicy()
        policy.autoLoad = settings[.mediaAutoLoad]
        policy.showLinkCards = settings[.mediaShowLinkCards]
        policy.loadVideoEmbeds = settings[.mediaLoadVideoEmbeds]
        policy.blockedDomains = settings[.mediaBlockedDomains]
        policy.allowedDomains = settings[.mediaAllowedDomains]
        policy.restrictToAllowedDomains = settings[.mediaRestrictToAllowed]
        policy.maxImageBytes = Int(settings[.mediaMaxImageSizeMB] * 1024 * 1024)
        if let bufferID, !isMediaEnabled(for: bufferID) { policy.autoLoad = false }
        return policy
    }

    public func isMediaEnabled(for bufferID: BufferID) -> Bool {
        let disabled = Set(settings[.mediaDisabledBuffers])
        return !disabled.contains(bufferID.description) && !disabled.contains("\(bufferID.networkID.uuidString)/*")
    }

    public func setMediaEnabled(_ enabled: Bool, for bufferID: BufferID) {
        var disabled = settings[.mediaDisabledBuffers]
        disabled.removeAll { $0 == bufferID.description }
        if !enabled { disabled.append(bufferID.description) }
        settings[.mediaDisabledBuffers] = disabled
    }

    // MARK: System integration

    public var totalHighlights: Int { sessions.reduce(0) { $0 + $1.totalHighlights } }

    private func updateDockBadge() {
        guard !isDemo else { return }
        let count = totalHighlights
        NSApp?.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemWillSleep() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        })

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                self?.sessions.forEach { $0.networkPathBecameAvailable() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "vela.path-monitor"))
        pathMonitor = monitor

        (notifier as? UserNotificationNotifier)?.onActivate = { [weak self] bufferID in
            self?.select(bufferID: bufferID)
            NSApp.activate()
        }
    }

    private func systemWillSleep() {
        sessionsConnectedBeforeSleep = Set(sessions.filter { $0.connectionState != .disconnected }.map(\.id))
        for session in sessions where sessionsConnectedBeforeSleep.contains(session.id) {
            session.disconnect(reason: "Computer going to sleep")
        }
    }

    private func systemDidWake() {
        let toReconnect = sessionsConnectedBeforeSleep
        sessionsConnectedBeforeSleep = []
        Task {
            try? await Task.sleep(for: .seconds(2))
            for session in sessions where toReconnect.contains(session.id) { session.connect() }
        }
    }

    /// Flush pending writes and quit politely.
    public func prepareForTermination() {
        settings.flush()
        for session in sessions { session.shutdown() }
    }

    private func pruneHistoryIfNeeded() {
        let days = settings[.historyRetentionDays]
        guard days > 0, let database else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        Task { try? await database.pruneMessages(olderThan: cutoff) }
    }

    public static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    // MARK: Demo support

    func installDemoSessions(_ demoSessions: [NetworkSession]) {
        for session in demoSessions { session.host = self }
        sessions = demoSessions
        if let buffer = demoSessions.first?.buffer(named: "#vela") ?? demoSessions.first?.channels.first { select(buffer) }
    }
}

/// Stores LinkPreview values in the SQLite cache.
nonisolated struct DatabasePreviewCache: LinkPreviewCache {
    let database: VelaDatabase

    func cachedPreview(for url: URL) async -> LinkPreview? {
        guard let data = try? await database.cachedPreviewJSON(url: url.absoluteString) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let preview = try? decoder.decode(LinkPreview.self, from: data) else { return nil }
        // Re-fetch page previews after a week.
        if preview.kind == .page, preview.fetchedAt < Date().addingTimeInterval(-7 * 86_400) { return nil }
        return preview
    }

    func storePreview(_ preview: LinkPreview) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(preview) else { return }
        try? await database.storePreviewJSON(data, url: preview.url.absoluteString)
    }
}
