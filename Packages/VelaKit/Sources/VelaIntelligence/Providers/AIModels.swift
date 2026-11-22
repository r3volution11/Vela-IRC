// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaStore

/// Where one summary goes, decided from the settings (and any model asked
/// for on the card or in the palette).
nonisolated enum AIRoute: Sendable {
    /// Apple's model: on this Mac, or with Private Cloud Compute.
    case apple(AppleModel)
    case provider(AIProviderRoute)
    /// The chosen model can't be used, and why. Never another provider in
    /// its place.
    case unavailable(AIProviderFailure)
}

/// A provider's model, ready to run once its key is read.
nonisolated struct AIProviderRoute: Sendable {
    let entry: AIProviderEntry
    let model: AIModelInfo
    /// The context the engine plans for.
    let context: Int
    let factory: AIProviderFactory
    let keys: AIKeyStore

    var label: AIModelLabel {
        AIModelLabel(providerID: entry.id, providerName: entry.name, modelID: model.id, modelName: model.name)
    }

    var identity: AIProviderIdentity {
        AIProviderIdentity(id: entry.id, name: entry.name, isCustomServer: entry.kind == .openAICompatible)
    }

    /// The model with its key, read from the Keychain: call it off the
    /// main actor. Throws a provider failure when there's no key (or no
    /// usable address).
    func languageModel() throws -> ProviderLanguageModel {
        let key = keys.key(for: entry.id)
        if entry.kind.requiresKey, key == nil { throw identity.failure(.missingKey) }
        guard let api = factory.api(for: entry, key: key) else { throw identity.failure(.unreachable) }
        return ProviderLanguageModel(api: api, model: model, context: context)
    }

    /// The model for planning, which counts and sends nothing: no key.
    func planningModel() -> ProviderLanguageModel? {
        factory.api(for: entry, key: nil).map { ProviderLanguageModel(api: $0, model: model, context: context) }
    }
}

/// A model as menus list it.
nonisolated public struct AIModelMenuItem: Identifiable, Hashable, Sendable {
    public var choice: AIModelChoice
    /// "Claude Opus 5.5", "Automatic (Apple)".
    public var title: String
    /// Vela's pick for its provider.
    public var isRecommended: Bool
    /// One of Apple's models.
    public var isApple: Bool { choice.isApple }

    public var id: String { choice.settingValue }
}

/// A group in a model menu: Apple's models, or one provider's.
nonisolated public struct AIModelMenuSection: Identifiable, Hashable, Sendable {
    /// `"apple"` or the provider's id.
    public var id: String
    public var title: String
    public var items: [AIModelMenuItem]
}

/// Your own AI models: the providers in `intelligence.providers` (keys in
/// the Keychain), their model lists, the model each feature uses, and
/// consent. Decides where each Catch me up and Recap goes
/// (``ModelRoutingSummarizer``). With no provider set up, everything is
/// Apple's, and nothing here reads the Keychain or the network.
///
/// The order everywhere: Apple's model on this Mac (Automatic first),
/// Private Cloud Compute where it's offered, then your providers.
@Observable
public final class AIModels {
    @ObservationIgnored public private(set) weak var settings: SettingsStore?
    @ObservationIgnored public let keys: AIKeyStore
    public let catalog: AIModelCatalog
    @ObservationIgnored private let availability: IntelligenceAvailability
    @ObservationIgnored private let offersPrivateCloudComputeNow: () -> Bool
    @ObservationIgnored private let makeFactory: () -> AIProviderFactory
    @ObservationIgnored private var madeFactory: AIProviderFactory?

    /// - Parameters:
    ///   - settings: Where providers and model choices are; nil (demo
    ///     mode) means Apple's model for everything.
    ///   - offersPrivateCloudCompute: Whether Private Cloud Compute can be
    ///     chosen now: built in, macOS 27+, and `intelligence.privateCloudCompute` on.
    ///   - factory: Makes the providers' APIs, on first use (tests stub the network).
    public init(
        settings: SettingsStore?,
        keys: AIKeyStore,
        catalog: AIModelCatalog = AIModelCatalog(),
        availability: IntelligenceAvailability,
        offersPrivateCloudCompute: @escaping () -> Bool = { false },
        factory: @escaping () -> AIProviderFactory = AIProviderFactory.live
    ) {
        self.settings = settings
        self.keys = keys
        self.catalog = catalog
        self.availability = availability
        self.offersPrivateCloudComputeNow = offersPrivateCloudCompute
        self.makeFactory = factory
    }

    /// Apple's models only, for demo mode and tests that don't need providers.
    public static func appleOnly(availability: IntelligenceAvailability) -> AIModels {
        AIModels(settings: nil, keys: AIKeyStore(keychain: .inMemory()), availability: availability)
    }

    var factory: AIProviderFactory {
        if let madeFactory { return madeFactory }
        let made = makeFactory()
        madeFactory = made
        return made
    }

    /// The model settings now.
    public var modelSettings: AIModelSettings {
        settings?.aiModelSettings ?? AIModelSettings()
    }

    public var providers: [AIProviderEntry] {
        settings?[.intelligenceProviders] ?? []
    }

    /// Providers that are on.
    public var enabledProviders: [AIProviderEntry] {
        providers.filter(\.enabled)
    }

    public var offersPrivateCloudCompute: Bool { offersPrivateCloudComputeNow() }

    /// Providers can be added: not in demo mode, which never goes online.
    public var canAddProviders: Bool { settings != nil }

    /// Apple's on-device model can run.
    public var isAppleAvailable: Bool { availability.status.isAvailable }

    // MARK: Routing

    /// Where `feature`'s next summary goes: `override` (the card's Change
    /// menu, the palette) or the settings.
    func route(for feature: AIFeature, override: AIModelChoice?) -> AIRoute {
        let settings = modelSettings
        return route(override ?? settings.choice(for: feature), settings: settings)
    }

    func route(_ choice: AIModelChoice, settings: AIModelSettings) -> AIRoute {
        switch choice {
        case .apple(.privateCloudCompute) where !offersPrivateCloudCompute:
            // Chosen while it was on; it's off now.
            return .apple(.automatic)
        case .apple(let model):
            return .apple(model)
        case .provider(let providerID, let modelID):
            guard let entry = settings.provider(providerID) else {
                return .unavailable(AIProviderFailure(providerID: providerID, providerName: providerID, reason: .providerMissing, modelID: modelID))
            }
            guard entry.enabled else {
                return .unavailable(AIProviderFailure(providerID: entry.id, providerName: entry.name, reason: .providerOff, modelID: modelID))
            }
            guard entry.consented else {
                return .unavailable(AIProviderFailure(providerID: entry.id, providerName: entry.name, reason: .needsConsent, modelID: modelID))
            }
            let model = catalog.info(for: entry, modelID: modelID) ?? AIModelInfo(id: modelID)
            let context = entry.kind == .openAICompatible
                ? (entry.contextTokens ?? AIProviderEntry.defaultCustomContextTokens)
                : (model.contextTokens ?? entry.kind.fallbackContextTokens)
            return .provider(AIProviderRoute(entry: entry, model: model, context: context, factory: factory, keys: keys))
        }
    }

    /// Whether `feature` can be offered: Apple's status for Apple's
    /// models; available for a provider's model that's set up and on
    /// (anything still missing, such as consent or a key, is asked for or
    /// explained on the card). Cheap for the usual case, Apple's model,
    /// which reads two settings and nothing else.
    public func status(for feature: AIFeature) -> IntelligenceStatus {
        guard let settings, !settings.usesAppleModel(for: feature) else { return availability.status }
        // Without building a route: no API is made just to answer this.
        let models = modelSettings
        guard let providerID = models.choice(for: feature).providerID,
              let entry = models.provider(providerID), entry.enabled
        else { return availability.status }
        return .available
    }

    // MARK: Menus

    /// Every model that can be chosen, grouped: Apple's (Automatic, this
    /// Mac, and Private Cloud Compute where it's offered), then each
    /// provider that's on, recommended models first.
    public func menuSections() -> [AIModelMenuSection] {
        var apple = [
            AIModelMenuItem(choice: .automatic, title: Self.title(for: .automatic), isRecommended: false),
            AIModelMenuItem(choice: .apple(.onDevice), title: Self.title(for: .apple(.onDevice)), isRecommended: false),
        ]
        if offersPrivateCloudCompute {
            apple.append(AIModelMenuItem(choice: .apple(.privateCloudCompute), title: Self.title(for: .apple(.privateCloudCompute)), isRecommended: false))
        }
        var sections = [AIModelMenuSection(id: AIModelChoice.appleProviderID, title: "Apple", items: apple)]
        for entry in enabledProviders {
            let items = catalog.models(for: entry).map { model in
                AIModelMenuItem(choice: .provider(providerID: entry.id, modelID: model.id), title: model.name, isRecommended: model.isRecommended)
            }
            sections.append(AIModelMenuSection(id: entry.id, title: entry.name, items: items))
        }
        return sections
    }

    /// Whether there's a choice to make beyond Apple's Automatic: a
    /// provider that's on, or Private Cloud Compute.
    public var hasChoices: Bool {
        !enabledProviders.isEmpty || offersPrivateCloudCompute
    }

    /// "Automatic (Apple)", "Claude Opus 5.5 (Anthropic)".
    public func title(for choice: AIModelChoice) -> String {
        guard case .provider(let providerID, let modelID) = choice else { return Self.title(for: choice) }
        guard let entry = providers.first(where: { $0.id == providerID }) else { return "\(modelID) (not set up)" }
        let name = catalog.info(for: entry, modelID: modelID)?.name ?? modelID
        return "\(name) (\(entry.name))"
    }

    static func title(for choice: AIModelChoice) -> String {
        switch choice {
        case .apple(.automatic): "Automatic (Apple)"
        case .apple(.onDevice): "Apple Intelligence on this Mac"
        case .apple(.privateCloudCompute): "Private Cloud Compute"
        case .provider(let provider, let model): "\(model) (\(provider))"
        }
    }

    // MARK: Consent

    /// You agreed, on the consent sheet, to send `providerID` messages.
    public func grantConsent(_ providerID: String) {
        update(providerID) { $0.consented = true }
    }

    /// Settings → Intelligence: ask again before sending it anything.
    public func withdrawConsent(_ providerID: String) {
        update(providerID) { $0.consented = false }
    }

    // MARK: Providers

    /// Adds a provider of `kind` (a custom server with its address) and
    /// returns it. It needs your OK before it's sent anything.
    @discardableResult
    public func addProvider(_ kind: AIProviderKind, name: String? = nil, baseURL: String? = nil) -> AIProviderEntry? {
        guard let settings else { return nil }
        var entries = settings[.intelligenceProviders]
        if !kind.allowsSeveral, entries.contains(where: { $0.kind == kind }) { return nil }
        let title = (name?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? kind.defaultName
        let entry = AIProviderEntry(
            id: AIProviderEntry.newID(kind: kind, name: title, existing: entries),
            kind: kind,
            name: title,
            baseURL: kind == .openAICompatible ? baseURL?.trimmingCharacters(in: .whitespaces) : nil
        )
        entries.append(entry)
        settings[.intelligenceProviders] = entries
        return entry
    }

    /// Saves changes to a provider (its name, address, context, on or off).
    /// A new address forgets its model list.
    public func updateProvider(_ entry: AIProviderEntry) {
        guard let old = providers.first(where: { $0.id == entry.id }), old != entry else { return }
        update(entry.id) { $0 = entry }
        if old.baseURL != entry.baseURL { catalog.forget(entry.id) }
    }

    /// Removes a provider: its key from the Keychain, its model list, and
    /// any model setting that chose it (back to the default).
    public func removeProvider(_ providerID: String) {
        guard let settings else { return }
        settings[.intelligenceProviders] = settings[.intelligenceProviders].filter { $0.id != providerID }
        try? keys.setKey(nil, for: providerID)
        catalog.forget(providerID)
        for key in [SettingKey<String>.intelligenceModel, .intelligenceCatchUpModel, .intelligenceRecapModel] {
            if AIModelChoice(settingValue: settings[key])?.providerID == providerID { settings.reset(key) }
        }
    }

    /// Saves (or, for nil, removes) a provider's key, and fetches its
    /// model list afresh with it.
    public func setKey(_ key: String?, for providerID: String) throws {
        try keys.setKey(key, for: providerID)
        catalog.forget(providerID)
    }

    /// Fetches the provider's model list now (Test, Refresh, a new key).
    @discardableResult
    public func refreshModels(_ providerID: String) async -> Result<[AIModelInfo], AIProviderFailure> {
        guard let entry = providers.first(where: { $0.id == providerID }) else {
            return .failure(AIProviderFailure(providerID: providerID, providerName: providerID, reason: .providerMissing))
        }
        switch await Self.api(for: entry, keys: keys, factory: factory) {
        case .ready(let api):
            return await catalog.refresh(entry, api: api)
        case .missingKey:
            return .failure(AIProviderFailure(providerID: entry.id, providerName: entry.name, reason: .missingKey))
        case .badAddress:
            return await catalog.refresh(entry, api: nil)
        }
    }

    /// Fetches the lists of providers that are on and ready (a key where
    /// one's needed) when they're missing or old: Settings → Intelligence
    /// showing.
    public func refreshStaleModels() {
        for entry in enabledProviders where catalog.isStale(entry) {
            if entry.kind.requiresKey, !keys.hasKey(for: entry.id) { continue }
            Task { await refreshModels(entry.id) }
        }
    }

    private enum APIReadiness: Sendable {
        case ready(any AIProviderAPI)
        case missingKey
        case badAddress
    }

    /// The provider's API with its key, read off the main actor.
    @concurrent
    private nonisolated static func api(for entry: AIProviderEntry, keys: AIKeyStore, factory: AIProviderFactory) async -> APIReadiness {
        let key = keys.key(for: entry.id)
        if entry.kind.requiresKey, key == nil { return .missingKey }
        guard let api = factory.api(for: entry, key: key) else { return .badAddress }
        return .ready(api)
    }

    private func update(_ providerID: String, _ change: (inout AIProviderEntry) -> Void) {
        guard let settings else { return }
        var entries = settings[.intelligenceProviders]
        guard let index = entries.firstIndex(where: { $0.id == providerID }) else { return }
        change(&entries[index])
        settings[.intelligenceProviders] = entries
    }
}
