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
        #expect(AIConsentText.destination(local) == "They go to the server at localhost:11434, on this Mac.")
        let lan = AIProviderEntry(id: "lan", kind: .openAICompatible, name: "Studio", baseURL: "http://studio.local:1234/v1")
        #expect(AIConsentText.destination(lan).contains("on your network"))
        #expect(!AIConsentText.destination(lan).contains("billed"))
        #expect(AIConsentText.footer(local).contains("Settings → Intelligence"))
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
        #expect(message(.badKey) == "OpenAI didn't accept your API key. Check it in Settings → Intelligence.")
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
}
