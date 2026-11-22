// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
import VelaFoundation
import VelaStore
@testable import VelaIntelligence

/// Apple's summarizer as the router sees it: records what it's asked,
/// answers at once.
final class RecordingAppleSummarizer: ConversationSummarizer, RecapSummarizer {
    private(set) var catchUpModels: [AIModelChoice?] = []
    private(set) var recapModels: [AIModelChoice?] = []
    private(set) var detailModels: [AIModelChoice?] = []

    func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error> {
        catchUpModels.append(request.model)
        return AsyncThrowingStream { continuation in
            continuation.yield(CatchUpSummary(overview: "Apple's.", topics: [], addressedToYou: [], messageCount: request.lines.count, isComplete: true))
            continuation.finish()
        }
    }

    func plan(_ input: RecapInput) async -> RecapPlan {
        RecapPlan(passes: 1, transcriptTokens: 1, estimatedSeconds: 1)
    }

    func recap(_ input: RecapInput) -> AsyncThrowingStream<RecapSummary, Error> {
        recapModels.append(input.model)
        return AsyncThrowingStream { continuation in
            continuation.yield(RecapSummary(overview: ["Apple's."], isComplete: true))
            continuation.finish()
        }
    }

    func detail(_ request: RecapDetailRequest) -> AsyncThrowingStream<RecapDetail, Error> {
        detailModels.append(request.model)
        return AsyncThrowingStream { continuation in
            continuation.yield(RecapDetail(points: ["Apple's."], isComplete: true))
            continuation.finish()
        }
    }

    var calls: Int { catchUpModels.count + recapModels.count + detailModels.count }
}

/// Settings, keys, a stub server per provider and the router, wired
/// together; nothing touches the real Keychain or network.
@MainActor
final class RoutingHarness {
    let directory: URL
    let settings: SettingsStore
    let keys = AIKeyStore(keychain: .inMemory())
    let apple = RecordingAppleSummarizer()
    let models: AIModels
    let summarizer: ModelRoutingSummarizer
    var servers: [AIProviderKind: StubServer]
    var offersPrivateCloudCompute = false

    /// - Parameter failing: Providers whose servers turn the key down.
    init(
        appleStatus: IntelligenceStatus = .available,
        failing: Set<AIProviderKind> = [],
        reply: @escaping @Sendable (String) -> String = { _ in CatchUpReply.render(CatchUpDraft(overview: "A provider's summary.")) }
    ) {
        directory = FileManager.default.temporaryDirectory.appending(path: "vela-routing-\(UUID().uuidString)")
        settings = SettingsStore(fileURL: directory.appending(path: "settings.json"), watchForChanges: false)
        var servers: [AIProviderKind: StubServer] = [:]
        for kind in AIProviderKind.allCases {
            servers[kind] = failing.contains(kind)
                ? StubServer([.json(401, #"{"error":{"message":"bad key","type":"authentication_error"}}"#)])
                : StubServer(handler: ProviderFixtures.handler(kind, reply: reply))
        }
        self.servers = servers
        let baseURLs = servers.compactMapValues { $0.baseURL }
        var offers: () -> Bool = { false }
        let availability = IntelligenceAvailability.fixed(appleStatus)
        models = AIModels(
            settings: settings,
            keys: keys,
            availability: availability,
            offersPrivateCloudCompute: { offers() },
            factory: { AIProviderFactory.stubbed(configuration: StubServer.configuration, baseURLs: baseURLs) }
        )
        summarizer = ModelRoutingSummarizer(apple: apple, models: models)
        offers = { [weak self] in self?.offersPrivateCloudCompute ?? false }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Adds a provider of `kind`, consented and with a key unless told
    /// otherwise; a custom server points at its stub.
    @discardableResult
    func add(_ kind: AIProviderKind, consented: Bool = true, key: String? = "key-123", context: Int? = nil) -> AIProviderEntry {
        let baseURL = kind == .openAICompatible ? servers[kind]!.baseURL.absoluteString : nil
        var entry = models.addProvider(kind, baseURL: baseURL)!
        entry.consented = consented
        entry.contextTokens = context
        models.updateProvider(entry)
        if let key { try! models.setKey(key, for: entry.id) }
        return entry
    }

    func requests(_ kind: AIProviderKind) -> [StubServer.Request] {
        servers[kind]!.requests
    }

    var allRequests: [StubServer.Request] {
        servers.values.flatMap(\.requests)
    }
}

nonisolated extension ProviderFixtures {
    /// The prompt in a request to `kind`.
    static func prompt(_ kind: AIProviderKind, in request: StubServer.Request) -> String {
        let body = request.json
        switch kind {
        case .anthropic: return body?["messages"]?.arrayValue?.first?["content"]?.stringValue ?? ""
        case .openAI: return body?["input"]?.stringValue ?? ""
        case .gemini: return body?["contents"]?.arrayValue?.first?["parts"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        case .openAICompatible: return body?["messages"]?.arrayValue?.last?["content"]?.stringValue ?? ""
        }
    }

    /// Answers `kind`'s requests in its stream format with `reply(prompt)`;
    /// model lists with the recommended models.
    static func handler(_ kind: AIProviderKind, reply: @escaping @Sendable (String) -> String) -> @Sendable (StubServer.Request) -> StubServer.Reply {
        { request in
            if request.method == "GET" {
                return .json(200, #"{"data":[{"id":"m1","type":"model"}],"models":[],"has_more":false}"#)
            }
            let text = reply(prompt(kind, in: request))
            switch kind {
            case .anthropic: return anthropicEvents([text])
            case .openAI: return openAIEvents([text])
            case .gemini: return geminiEvents([text])
            case .openAICompatible: return chatEvents([text])
            }
        }
    }
}

@Suite("Routing to your own models")
@MainActor
struct ModelRoutingTests {
    typealias F = CatchUpFixtures

    func summary(_ harness: RoutingHarness, _ request: CatchUpRequest) async throws -> CatchUpSummary {
        try await harness.summarizer.summary(for: request)
    }

    func error(_ harness: RoutingHarness, _ request: CatchUpRequest) async -> CatchUpError? {
        do {
            _ = try await harness.summarizer.summary(for: request)
            return nil
        } catch {
            return error as? CatchUpError
        }
    }

    // MARK: Apple

    @Test func appleIsTheDefaultAndNothingElseIsTouched() async throws {
        let harness = RoutingHarness()
        let result = try await summary(harness, F.request(F.chatter(5)))
        #expect(result.overview == "Apple's.")
        #expect(harness.apple.catchUpModels == [.automatic])
        #expect(harness.allRequests.isEmpty)
        #expect(harness.models.status(for: .catchUp) == .available)
    }

    @Test func appleModelChoicesArePassedOn() async throws {
        let harness = RoutingHarness()
        harness.settings[.intelligenceCatchUpModel] = "apple/on-device"
        _ = try await summary(harness, F.request(F.chatter(5)))
        // Private Cloud Compute chosen while it isn't offered: Automatic.
        harness.settings[.intelligenceCatchUpModel] = "apple/private-cloud-compute"
        _ = try await summary(harness, F.request(F.chatter(6)))
        harness.offersPrivateCloudCompute = true
        _ = try await summary(harness, F.request(F.chatter(7)))
        #expect(harness.apple.catchUpModels == [.apple(.onDevice), .automatic, .apple(.privateCloudCompute)])
    }

    @Test func aRequestsModelBeatsTheFeaturesWhichBeatsTheDefault() async throws {
        let harness = RoutingHarness()
        let anthropic = harness.add(.anthropic)
        harness.settings[.intelligenceModel] = "\(anthropic.id)/claude-opus-5-5"
        harness.settings[.intelligenceRecapModel] = "apple/on-device"
        let settings = harness.models.modelSettings
        #expect(settings.choice(for: .catchUp) == .provider(providerID: "anthropic", modelID: "claude-opus-5-5"))
        #expect(settings.choice(for: .recap) == .apple(.onDevice))
        var request = F.request(F.chatter(5))
        request.model = .apple(.onDevice)
        _ = try await summary(harness, request)
        #expect(harness.apple.catchUpModels == [.apple(.onDevice)])
        #expect(harness.requests(.anthropic).isEmpty)
    }

    // MARK: Gates

    @Test func nothingIsSentBeforeConsent() async {
        let harness = RoutingHarness()
        let entry = harness.add(.anthropic, consented: false)
        harness.settings[.intelligenceCatchUpModel] = "\(entry.id)/claude-opus-5-5"
        let error = await error(harness, F.request(F.chatter(5)))
        #expect(error?.needsConsent == true)
        #expect(error?.providerFailure?.providerID == entry.id)
        #expect(harness.allRequests.isEmpty)
        #expect(harness.apple.calls == 0)
        // Offered all the same, so the card can ask.
        #expect(harness.models.status(for: .catchUp) == .available)

        harness.models.grantConsent(entry.id)
        _ = try? await summary(harness, F.request(F.chatter(5)))
        #expect(harness.requests(.anthropic).count == 1)

        harness.models.withdrawConsent(entry.id)
        #expect(await self.error(harness, F.request(F.chatter(6)))?.needsConsent == true)
        #expect(harness.requests(.anthropic).count == 1)
    }

    @Test func aMissingKeySendsNothing() async {
        let harness = RoutingHarness()
        let entry = harness.add(.openAI, key: nil)
        harness.settings[.intelligenceCatchUpModel] = "\(entry.id)/gpt-6.2-sol"
        #expect(await error(harness, F.request(F.chatter(5)))?.providerFailure?.reason == .missingKey)
        #expect(harness.allRequests.isEmpty)
    }

    @Test func aProviderThatsOffOrGoneNeverFallsBack() async {
        let harness = RoutingHarness()
        var entry = harness.add(.gemini)
        harness.settings[.intelligenceCatchUpModel] = "\(entry.id)/gemini-3.8-flash"
        entry.enabled = false
        harness.models.updateProvider(entry)
        #expect(await error(harness, F.request(F.chatter(5)))?.providerFailure?.reason == .providerOff)
        // Apple's status decides, since the provider can't be used.
        harness.settings[.intelligenceCatchUpModel] = "nowhere/some-model"
        #expect(await error(harness, F.request(F.chatter(5)))?.providerFailure?.reason == .providerMissing)
        #expect(harness.apple.calls == 0)
        #expect(harness.allRequests.isEmpty)
    }

    @Test func aFailingProviderDoesntFallBackToAnother() async {
        let harness = RoutingHarness(failing: [.anthropic])
        let entry = harness.add(.anthropic)
        harness.add(.openAI)
        harness.add(.gemini)
        harness.settings[.intelligenceCatchUpModel] = "\(entry.id)/claude-opus-5-5"
        let error = await error(harness, F.request(F.chatter(5)))
        #expect(error?.providerFailure?.providerID == entry.id)
        #expect(error?.providerFailure?.reason == .badKey)
        #expect(harness.requests(.anthropic).count == 1)
        #expect(harness.requests(.openAI).isEmpty)
        #expect(harness.requests(.gemini).isEmpty)
        #expect(harness.apple.calls == 0)
    }

    // MARK: Running

    @Test func aProvidersSummaryNamesItsModel() async throws {
        let harness = RoutingHarness()
        let entry = harness.add(.anthropic)
        harness.settings[.intelligenceCatchUpModel] = "\(entry.id)/claude-opus-5-5"
        let result = try await summary(harness, F.request(F.chatter(30)))
        #expect(result.overview == "A provider's summary.")
        #expect(result.venue == .provider(AIModelLabel(providerID: "anthropic", providerName: "Anthropic", modelID: "claude-opus-5-5", modelName: "Claude Opus 5.5")))
        #expect(result.provenance == "Summarized by Claude Opus 5.5 (Anthropic).")
        // One pass, thanks to the large context.
        #expect(harness.requests(.anthropic).count == 1)
        #expect(harness.apple.calls == 0)
    }

    @Test func aRefusalIsTheProvidersDecline() async {
        let harness = RoutingHarness(reply: { _ in "I'm not able to help with that." })
        let entry = harness.add(.openAI)
        harness.settings[.intelligenceCatchUpModel] = "\(entry.id)/gpt-6.2-sol"
        let error = await error(harness, F.request([F.line("alice", "hello")]))
        #expect(error?.providerFailure?.reason == .declined)
        #expect(error?.errorDescription == "OpenAI declined to summarize this conversation.")
    }

    @Test func theRealContextMeansFewerPasses() async {
        let harness = RoutingHarness()
        let small = harness.add(.openAICompatible, context: 2_048)
        let request = F.request(F.chatter(240))
        harness.settings[.intelligenceCatchUpModel] = "\(small.id)/llama3"
        let smallPlan = await harness.summarizer.plan(request)
        #expect(smallPlan.passes > 1)
        let big = harness.add(.anthropic)
        harness.settings[.intelligenceCatchUpModel] = "\(big.id)/claude-opus-5-5"
        let bigPlan = await harness.summarizer.plan(request)
        #expect(bigPlan.passes == 1)
        #expect(bigPlan.venue.providerModel?.providerID == "anthropic")
        // Planning sends nothing.
        #expect(harness.allRequests.isEmpty)
    }

    @Test func recapAndMoreDetailUseTheChosenModel() async throws {
        let harness = RoutingHarness(reply: { prompt in
            prompt.contains("POINT") || prompt.lowercased().contains("closer") ? "POINT: Talk." : "OVERVIEW: Talk.\nTOPIC: [1-3] | Plans | Talked. | alice"
        })
        let entry = harness.add(.gemini)
        harness.settings[.intelligenceRecapModel] = "\(entry.id)/gemini-3.8-flash"
        let input = RecapFixtures.input([RecapFixtures.conversation("#vela", RecapFixtures.chatter(3))])
        var last: RecapSummary?
        for try await snapshot in harness.summarizer.recap(input) { last = snapshot }
        #expect(last?.venue.providerModel?.modelID == "gemini-3.8-flash")
        #expect(harness.requests(.gemini).count == 1)
        let detail = RecapDetailRequest(lines: input.conversations[0].lines, ownNick: "doug", focus: "Plans", model: last?.venue.providerModel?.choice)
        for try await _ in harness.summarizer.detail(detail) {}
        #expect(harness.requests(.gemini).count == 2)
        #expect(harness.apple.calls == 0)
    }

    // MARK: Menus and settings

    @Test func menusListAppleFirstThenProvidersRecommendedFirst() {
        let harness = RoutingHarness()
        #expect(!harness.models.hasChoices)
        harness.add(.openAI)
        harness.add(.anthropic)
        var off = harness.add(.gemini)
        off.enabled = false
        harness.models.updateProvider(off)
        let sections = harness.models.menuSections()
        #expect(sections.map(\.id) == ["apple", "openai", "anthropic"])
        #expect(sections[0].items.map(\.choice) == [.automatic, .apple(.onDevice)])
        #expect(sections[2].items.first?.choice == .provider(providerID: "anthropic", modelID: "claude-opus-5-5"))
        #expect(sections[2].items.first?.isRecommended == true)
        #expect(sections[2].items.map(\.choice.settingValue).contains("anthropic/claude-haiku-5-5"))
        harness.offersPrivateCloudCompute = true
        #expect(harness.models.menuSections()[0].items.map(\.choice) == [.automatic, .apple(.onDevice), .apple(.privateCloudCompute)])
        #expect(harness.models.hasChoices)
        #expect(harness.models.title(for: .provider(providerID: "anthropic", modelID: "claude-sonnet-5-5")) == "Claude Sonnet 5.5 (Anthropic)")
        #expect(harness.models.title(for: .automatic) == "Automatic (Apple)")
    }

    @Test func statusFollowsTheFeaturesModel() {
        let harness = RoutingHarness(appleStatus: .deviceNotEligible)
        #expect(harness.models.status(for: .catchUp) == .deviceNotEligible)
        let entry = harness.add(.anthropic)
        harness.settings[.intelligenceCatchUpModel] = "\(entry.id)/claude-opus-5-5"
        #expect(harness.models.status(for: .catchUp) == .available)
        #expect(harness.models.status(for: .recap) == .deviceNotEligible)
    }

    @Test func removingAProviderForgetsItsKeyAndChoices() {
        let harness = RoutingHarness()
        let entry = harness.add(.anthropic)
        harness.settings[.intelligenceModel] = "\(entry.id)/claude-opus-5-5"
        harness.settings[.intelligenceRecapModel] = "\(entry.id)/claude-haiku-5-5"
        harness.settings[.intelligenceCatchUpModel] = "apple/on-device"
        #expect(harness.keys.hasKey(for: entry.id))
        harness.models.removeProvider(entry.id)
        #expect(harness.models.providers.isEmpty)
        #expect(!harness.keys.hasKey(for: entry.id))
        #expect(harness.settings[.intelligenceModel] == "apple")
        #expect(harness.settings[.intelligenceRecapModel] == "")
        #expect(harness.settings[.intelligenceCatchUpModel] == "apple/on-device")
    }

    @Test func onlyOneOfEachHostedProviderButManyServers() {
        let harness = RoutingHarness()
        #expect(harness.models.addProvider(.openAI) != nil)
        #expect(harness.models.addProvider(.openAI) == nil)
        let first = harness.models.addProvider(.openAICompatible, name: "LM Studio", baseURL: "http://localhost:1234/v1")
        let second = harness.models.addProvider(.openAICompatible, name: "LM Studio", baseURL: "http://studio.local:1234/v1")
        #expect(first?.id == "lm-studio")
        #expect(second?.id == "lm-studio-2")
        #expect(harness.models.providers.allSatisfy { !$0.consented })
    }

    @Test func keysStayOutOfSettings() throws {
        let harness = RoutingHarness()
        let entry = harness.add(.anthropic, key: "sk-ant-very-secret")
        harness.settings.flush()
        let text = try String(contentsOf: harness.settings.fileURL, encoding: .utf8)
        #expect(text.contains("\"anthropic\""))
        #expect(!text.contains("sk-ant-very-secret"))
        #expect(harness.keys.key(for: entry.id) == "sk-ant-very-secret")
    }

    @Test func modelListsAreFetchedAndCached() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "vela-catalog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appending(path: "ai-models.json")
        let server = StubServer([.json(200, #"{"object":"list","data":[{"id":"llama3.2"},{"id":"qwen3:8b"}]}"#)])
        let entry = AIProviderEntry(id: "ollama", kind: .openAICompatible, name: "Ollama", baseURL: server.baseURL.absoluteString)
        let api = OpenAICompatibleAPI(identity: AIProviderIdentity(id: "ollama", name: "Ollama"), client: ProviderFixtures.client(), key: nil, baseURL: server.baseURL)
        let catalog = AIModelCatalog(cacheURL: cacheURL)
        #expect(catalog.models(for: entry).isEmpty)
        #expect(catalog.isStale(entry))
        let result = await catalog.refresh(entry, api: api)
        #expect((try? result.get())?.map(\.id) == ["llama3.2", "qwen3:8b"])
        #expect(catalog.state(for: "ollama") == .loaded)
        #expect(!catalog.isStale(entry))
        // Written in the background; a new catalog reads it.
        #expect(await eventually { FileManager.default.fileExists(atPath: cacheURL.path()) })
        let reopened = AIModelCatalog(cacheURL: cacheURL)
        #expect(reopened.models(for: entry).map(\.id) == ["llama3.2", "qwen3:8b"])
        // Another address: stale.
        var moved = entry
        moved.baseURL = "http://elsewhere.local:11434/v1"
        #expect(reopened.isStale(moved))
        #expect(reopened.models(for: moved).isEmpty)
        catalog.forget("ollama")
        #expect(catalog.lists["ollama"] == nil)
    }
}
