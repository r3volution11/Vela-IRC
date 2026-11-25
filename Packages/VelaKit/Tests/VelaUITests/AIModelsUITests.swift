// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntelligence
import VelaStore
@testable import VelaUI

/// Your own AI models in the interface: the palette's model list and
/// commands, the consent sheet's words, the card's footer and Settings.
@MainActor
@Suite("Your own AI models in the interface", .serialized)
struct AIModelsUITests {
    private func demo() async throws -> (AppModel, IntelligenceServices) {
        let app = AppModel.demo()
        await app.ready()
        let availability = IntelligenceAvailability.fixed(.available)
        let models = AIModels(settings: app.settings, keys: AIKeyStore(keychain: .inMemory()), availability: availability)
        let intelligence = IntelligenceServices(availability: availability, summarizer: CannedSummarizer(stepDelay: .zero), models: models)
        return (app, intelligence)
    }

    // MARK: Palette

    @Test func theModelListGroupsByProviderAndChecksTheCurrentOne() async throws {
        let (app, intelligence) = try await demo()
        intelligence.models.addProvider(.anthropic)
        intelligence.models.addProvider(.openAICompatible, name: "Ollama", baseURL: "http://localhost:11434/v1")
        let current = AIModelChoice.provider(providerID: "anthropic", modelID: "claude-sonnet-5-5")
        let items = PaletteSource.modelItems(intelligence.models.menuSections(), current: current, appleAvailable: true)
        #expect(items.first?.label.text == "Automatic (Apple)")
        #expect(items.first { $0.isCurrent }?.id == "model:anthropic/claude-sonnet-5-5")
        #expect(items.first { $0.id == "model:anthropic/claude-opus-5-5" }?.detail == "Anthropic")
        // Ollama's list isn't fetched yet: no models to offer.
        #expect(!items.contains { $0.detail == "Ollama" })

        let rows = PaletteRanker.rows(for: items, query: "", list: .models)
        #expect(rows.compactMap(\.sectionLabel) == ["apple", "anthropic"])
        #expect(rows[PaletteRanker.initialSelection(in: rows, list: .models, query: "")].item.isCurrent)
        #expect(PaletteRanker.rows(for: items, query: "haiku", list: .models).first?.id == "model:anthropic/claude-haiku-5-5")

        // Without Apple Intelligence, only providers' models.
        let withoutApple = PaletteSource.modelItems(intelligence.models.menuSections(), current: nil, appleAvailable: false)
        #expect(withoutApple.allSatisfy { $0.detail == "Anthropic" })
        _ = app
    }

    @Test func aiCommands() async throws {
        let (app, intelligence) = try await demo()
        var opened: [AIModelPickerPurpose] = []
        var managed = 0
        func commands() -> [VelaCommand] {
            VelaCommandCatalog.aiModelCommands(app: app, intelligence: intelligence, openPalette: { opened.append($0) }, manageProviders: { managed += 1 })
        }
        // Without providers: the default and providers, no "…With".
        #expect(commands().map(\.paletteTitle) == ["AI: Set Default Model…", "AI: Manage Providers…"])
        #expect(commands().first?.detail == "Automatic (Apple)")

        intelligence.models.addProvider(.gemini)
        let buffer = try #require(app.selectedBuffer)
        let all = commands()
        #expect(all.map(\.paletteTitle) == ["AI: Set Default Model…", "AI: Manage Providers…", "Buffer: Catch Me Up With…", "Buffer: Recap With…"])
        for command in all { command.perform() }
        #expect(managed == 1)
        #expect(opened.count == 3)
        #expect(opened[0] == .defaultModel)
        #expect(opened[1] == .catchUp(buffer.id))
        if case .recap(let scope) = opened[2] {
            #expect(scope.place == .buffer(buffer.id))
            #expect(scope.output == .summary)
        } else {
            Issue.record("expected a Recap")
        }
        // Catch me up off: no "Catch Me Up With…".
        app.settings[.intelligenceCatchUp] = false
        defer { app.settings[.intelligenceCatchUp] = true }
        #expect(!commands().map(\.title).contains("Catch Me Up With…"))
    }

    // MARK: Consent

    @Test func theConsentSheetSaysExactlyWhatIsSent() {
        let anthropic = AIProviderEntry(id: "anthropic", kind: .anthropic, name: "Anthropic")
        #expect(AIConsentText.title(anthropic) == "Send messages to Anthropic?")
        #expect(AIConsentText.sent.contains("text and nicks"))
        #expect(AIConsentText.sent.contains("your own nick"))
        #expect(AIConsentText.neverSent.contains("channels, networks or servers"))
        #expect(AIConsentText.neverSent.contains("account"))
        #expect(AIConsentText.destination(anthropic).contains("data policy"))
        #expect(AIConsentText.destination(anthropic).contains("billed to your API key"))
        #expect(AIProviderKind.anthropic.dataPolicyURL != nil)

        let gemini = AIProviderEntry(id: "gemini", kind: .gemini, name: "Gemini")
        #expect(AIConsentText.destination(gemini).contains("free tier"))

        let local = AIProviderEntry(id: "ollama", kind: .openAICompatible, name: "Ollama", baseURL: "http://localhost:11434/v1")
        #expect(AIConsentText.destination(local) == "They stay on this Mac, with the server at localhost:11434.")
        let lan = AIProviderEntry(id: "lan", kind: .openAICompatible, name: "Studio", baseURL: "http://studio.local:1234/v1")
        #expect(AIConsentText.destination(lan).contains("on your network"))
        #expect(!AIConsentText.destination(lan).contains("billed"))
        #expect(AIConsentText.footer(local).contains("Settings → AI Privacy"))
    }

    // MARK: The card and Settings

    @Test func theCardSaysWhichModelWroteIt() {
        let label = AIModelLabel(providerID: "anthropic", providerName: "Anthropic", modelID: "claude-opus-5-5", modelName: "Claude Opus 5.5")
        var summary = CatchUpSummary(overview: "Talk.", topics: [], addressedToYou: [], messageCount: 200, isComplete: true, venue: .provider(label))
        #expect(CatchUpCardView.footerText(summary, messageCount: 200) == "Summarized by Claude Opus 5.5 (Anthropic). May contain mistakes.")
        summary.skippedMessages = 12
        #expect(CatchUpCardView.footerText(summary, messageCount: 200).hasPrefix("Skipped 12 messages that Anthropic wouldn't summarize."))
    }

    @Test func providerFailuresReadPlainly() {
        func message(_ reason: AIProviderFailure.Reason) -> String {
            CatchUpError.provider(AIProviderFailure(providerID: "openai", providerName: "OpenAI", reason: reason)).errorDescription ?? ""
        }
        #expect(message(.badKey) == "OpenAI didn't accept your API key. Check it in Settings → AI Providers.")
        #expect(message(.quota).contains("out of credit"))
        #expect(message(.offline).contains("internet connection"))
        #expect(message(.needsConsent) == "Vela needs your OK before it sends messages to OpenAI.")
        #expect(CatchUpError.provider(AIProviderFailure(providerID: "o", providerName: "O", reason: .needsConsent)).needsConsent)
        #expect(AIProviderFailure(providerID: "o", providerName: "O", reason: .missingKey).isFixedInSettings)
        #expect(!AIProviderFailure(providerID: "o", providerName: "O", reason: .rateLimited).isFixedInSettings)
    }

    @Test func theProvidersSettingIsEditedAsJSON() {
        let descriptor = SettingsCatalog.descriptor(forKey: "intelligence.providers")!
        let entry = SettingsEditorEntry(key: descriptor.key, descriptor: descriptor, value: nil)
        #expect(SettingControlKind(entry) == .object)
        #expect(SettingsPane.intelligence.title == "Intelligence")
    }

    @Test func thePaneSaysWhereSummariesAreMade() {
        #expect(IntelligencePane.subtitle(privateCloudCompute: false).hasSuffix("Summaries and translation run on this Mac."))
        let withModel = IntelligencePane.subtitle(privateCloudCompute: false, providerModels: ["Claude Opus 5.5 (Anthropic)"])
        #expect(withModel.contains("Claude Opus 5.5 (Anthropic)"))
        #expect(withModel.contains("translation runs on this Mac"))
    }

    // MARK: The three panes

    @Test func theAIPanesComeInOrderBeforeIntegrations() {
        let panes = SettingsPane.allCases
        let intelligence = panes.firstIndex(of: .intelligence)!
        #expect(Array(panes[intelligence...].prefix(4)) == [.intelligence, .aiProviders, .aiPrivacy, .integrations])
        #expect(SettingsPane.aiProviders.title == "AI Providers")
        #expect(SettingsPane.aiPrivacy.title == "AI Privacy")
        #expect(SettingsPane.groups.flatMap { $0 } == SettingsPane.allCases)
        // Every pane id is one the snapshot tool and @pane: filter know.
        #expect(SettingsPane(rawValue: SettingsCategory.aiProviders.paneID) == .aiProviders)
        // Manage Providers… and Open Settings on a card go to AI Providers' list.
        #expect(SettingsReveal.aiModels == SettingsReveal(pane: .aiProviders, section: "models"))
    }

    @Test func showInSettingsEditorFiltersToEachPane() {
        // AI Providers' settings: the providers and the default model.
        let providers = SettingsQuery("@pane:\(SettingsPane.aiProviders.rawValue)")
        let entry = { (key: String) in
            SettingsEditorEntry(key: key, descriptor: SettingsCatalog.descriptor(forKey: key), value: nil)
        }
        #expect(providers.matches(entry("intelligence.providers")))
        #expect(providers.matches(entry("intelligence.model")))
        #expect(!providers.matches(entry("intelligence.catchUpModel")))
        let intelligence = SettingsQuery("@pane:intelligence")
        #expect(intelligence.matches(entry("intelligence.catchUpModel")))
        #expect(intelligence.matches(entry("translation.language")))
        #expect(!intelligence.matches(entry("intelligence.providers")))
        // AI Privacy has no settings of its own (consent is in providers).
        #expect(SettingsCategory.categories(forPane: SettingsPane.aiPrivacy.rawValue).isEmpty)
    }

    @Test func paletteOpensEachAIPane() {
        var shown: [SettingsPane] = []
        let commands = VelaCommandCatalog.aiSettingsCommands { shown.append($0) }
        #expect(commands.map(\.paletteTitle) == ["Settings: Intelligence", "Settings: AI Providers", "Settings: AI Privacy"])
        for command in commands { command.perform() }
        #expect(shown == [.intelligence, .aiProviders, .aiPrivacy])
        #expect(commands[1].keywords.contains("ollama"))
        #expect(commands[2].keywords.contains("consent"))
    }

    // MARK: AI Privacy

    @Test func privacyShowsEachProvidersPermission() {
        var entry = AIProviderEntry(id: "openai", kind: .openAI, name: "OpenAI")
        #expect(AIPrivacyPane.status(entry) == "Asks first")
        entry.consented = true
        #expect(AIPrivacyPane.status(entry) == "Allowed")
        entry.enabled = false
        #expect(AIPrivacyPane.status(entry) == "Off · allowed")
        #expect(AIPrivacyPane.appleSummaries(privateCloudCompute: false).contains("never a channel's or network's name"))
        #expect(AIPrivacyPane.providersFooter.contains("ask again"))
    }

    @Test func withdrawingInPrivacyMeansAskingAgain() async throws {
        let (app, intelligence) = try await demo()
        let entry = try #require(intelligence.models.addProvider(.openAICompatible, name: "Ollama", baseURL: "http://localhost:11434/v1"))
        intelligence.models.grantConsent(entry.id)
        app.settings[.intelligenceModel] = "ollama/llama3.2"
        defer { app.settings[.intelligenceModel] = "apple" }
        intelligence.models.withdrawConsent(entry.id)
        #expect(intelligence.models.providers.first { $0.id == entry.id }?.consented == false)
        let request = AIConsentRequest(providerID: entry.id, allowTitle: "Allow") {}
        #expect(request.allowTitle == "Allow")
        #expect(AIConsentRequest(providerID: entry.id) {}.allowTitle == "Allow and Continue")
    }

    // MARK: The setup sheet

    @Test func theSetupSheetSaysWhatHappened() {
        #expect(AIProviderSetupText.connected(0) == "Connected. The key works.")
        #expect(AIProviderSetupText.connected(1) == "Connected. 1 model is available.")
        #expect(AIProviderSetupText.connected(42) == "Connected. 42 models are available.")
        func failure(_ reason: AIProviderFailure.Reason) -> AIProviderFailure {
            AIProviderFailure(providerID: "openai", providerName: "OpenAI", reason: reason)
        }
        #expect(AIProviderSetupText.problem(failure(.badKey), kind: .openAI).hasPrefix("OpenAI didn't accept this key."))
        #expect(AIProviderSetupText.problem(failure(.quota), kind: .openAI).contains("out of credit"))
        #expect(AIProviderSetupText.problem(failure(.offline), kind: .openAI).contains("internet connection"))
        #expect(AIProviderSetupText.problem(failure(.other("Project not allowed.")), kind: .openAI) == "OpenAI said: Project not allowed.")
        #expect(AIProviderSetupText.isTransient(failure(.offline)))
        #expect(AIProviderSetupText.isTransient(failure(.overloaded)))
        #expect(!AIProviderSetupText.isTransient(failure(.badKey)))
        #expect(!AIProviderSetupText.isTransient(failure(.quota)))
        #expect(AIProviderSetupRequest.hostedKinds == [.openAI, .anthropic, .gemini])
    }

    // MARK: Models on this Mac

    @Test func localServersAreOfferedByWhatWasFound() {
        let models = [AIModelInfo(id: "llama3.2"), AIModelInfo(id: "qwen3:8b"), AIModelInfo(id: "gemma3")]
        let connected = AIProviderEntry(id: "ollama", kind: .openAICompatible, name: "Ollama", baseURL: "http://127.0.0.1:11434/v1")
        #expect(LocalModelsFinder.offer(state: .running(models: models), installed: true, connected: nil) == .connect(models: models))
        #expect(LocalModelsFinder.offer(state: .running(models: models), installed: false, connected: nil) == .connect(models: models))
        #expect(LocalModelsFinder.offer(state: .running(models: models), installed: true, connected: connected) == .connected(connected, running: true, models: 3))
        #expect(LocalModelsFinder.offer(state: .notRunning, installed: true, connected: connected) == .connected(connected, running: false, models: 0))
        #expect(LocalModelsFinder.offer(state: .notRunning, installed: true, connected: nil) == .open)
        #expect(LocalModelsFinder.offer(state: .notRunning, installed: false, connected: nil) == LocalModelOffer.none)
        #expect(LocalModelsFinder.offer(state: nil, installed: false, connected: nil) == LocalModelOffer.none)

        #expect(LocalModelsSection.title(.ollama, .connect(models: models)) == "Ollama is running on this Mac, with 3 models.")
        #expect(LocalModelsSection.title(.lmStudio, .connect(models: [])) == "LM Studio is running on this Mac, with no models yet.")
        #expect(LocalModelsSection.title(.ollama, .open) == "Ollama is installed, but isn't running.")
        #expect(LocalModelsSection.detail(.lmStudio, .open)?.contains("Developer tab") == true)
        #expect(LocalModelsSection.detail(.ollama, .connect(models: models))?.contains("No key") == true)
    }

    /// Looking finds what's installed (asked of Launch Services) and what's
    /// running (asked of the server); a server that isn't answering is
    /// offered to Open when its app is installed.
    @Test func theFinderLooksWhenAsked() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "vela-finder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsStore(fileURL: directory.appending(path: "settings.json"), watchForChanges: false)
        // Port 9 on the loopback address: nothing listens, so it's refused at once.
        let nowhere = URL(string: "http://127.0.0.1:9/v1")!
        let models = AIModels(
            settings: settings,
            keys: AIKeyStore(keychain: .inMemory()),
            availability: .fixed(.available),
            localServers: {
                LocalModelDetector(
                    session: AIHTTPClient.makeSession(requestTimeout: 1, resourceTimeout: 2),
                    baseURLs: [.ollama: nowhere, .lmStudio: nowhere]
                )
            }
        )
        var asked: [String] = []
        let ollamaApp = InstalledApp(url: URL(fileURLWithPath: "/Applications/Ollama.app"), version: "0.12.0")
        let finder = LocalModelsFinder { bundleID in
            asked.append(bundleID)
            return bundleID == LocalModelServer.ollama.bundleIdentifier ? ollamaApp : nil
        }
        #expect(asked.isEmpty)
        finder.look(with: models)
        #expect(finder.isLooking)
        #expect(asked == ["com.electron.ollama", "ai.elementlabs.lmstudio"])
        #expect(await RunningDeadline.wait(timeout: .seconds(5)) { finder.hasLooked })
        #expect(!finder.isLooking)
        #expect(finder.states[.ollama] == .notRunning)
        #expect(finder.installed[.ollama] == ollamaApp)
        #expect(finder.installed[.lmStudio] == nil)
        #expect(LocalModelsFinder.offer(state: finder.states[.ollama], installed: true, connected: models.provider(for: .ollama)) == .open)

        // Demo mode never looks.
        let demo = LocalModelsFinder { _ in
            Issue.record("looked in demo mode")
            return nil
        }
        demo.look(with: AIModels.appleOnly(availability: .fixed(.available)))
        #expect(!demo.isLooking)
    }
}
