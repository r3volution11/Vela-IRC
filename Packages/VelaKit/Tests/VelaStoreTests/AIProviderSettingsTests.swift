// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite("AI provider settings")
@MainActor
struct AIProviderSettingsTests {
    func temporaryStore() -> (SettingsStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "vela-ai-settings-\(UUID().uuidString)")
        return (SettingsStore(fileURL: directory.appending(path: "settings.json"), watchForChanges: false), directory)
    }

    @Test func modelChoicesReadAndWrite() {
        let cases: [(String, AIModelChoice?)] = [
            ("apple", .automatic),
            ("apple/on-device", .apple(.onDevice)),
            ("apple/private-cloud-compute", .apple(.privateCloudCompute)),
            ("anthropic/claude-opus-5-5", .provider(providerID: "anthropic", modelID: "claude-opus-5-5")),
            ("lm-studio/lmstudio-community/Meta-Llama-3-8B", .provider(providerID: "lm-studio", modelID: "lmstudio-community/Meta-Llama-3-8B")),
            ("ollama/qwen3:8b", .provider(providerID: "ollama", modelID: "qwen3:8b")),
            ("", nil),
            ("  ", nil),
            ("claude", nil),
            ("apple/automatic", nil),
            ("apple/unknown", nil),
            ("/model", nil),
            ("provider/", nil),
        ]
        for (value, expected) in cases {
            #expect(AIModelChoice(settingValue: value) == expected, "\(value)")
            if let expected { #expect(AIModelChoice(settingValue: expected.settingValue) == expected) }
        }
        #expect(AIModelChoice.automatic.settingValue == "apple")
    }

    @Test func providerEntriesRoundTripAndBadOnesAreDropped() throws {
        let entry = AIProviderEntry(id: "ollama", kind: .openAICompatible, name: "Ollama", baseURL: "http://localhost:11434/v1", consented: true, contextTokens: 8_192)
        #expect(AIProviderEntry(settingJSON: entry.settingJSON) == entry)
        let json = try #require(entry.settingJSON.objectValue)
        #expect(json["consent"]?.boolValue == true)
        #expect(json["key"] == nil)

        let list = [AIProviderEntry](settingJSON: .array([
            entry.settingJSON,
            .object(["id": "anthropic", "kind": "anthropic"]),
            .object(["id": "nope", "kind": "skynet"]),
            .object(["id": "apple", "kind": "openai"]),
            .object(["id": "a/b", "kind": "openai"]),
            .string("junk"),
        ]))
        #expect(list?.map(\.id) == ["ollama", "anthropic"])
        // Lenient defaults: the name is the id, on, no consent.
        let anthropic = try #require(list?.last)
        #expect(anthropic.name == "anthropic")
        #expect(anthropic.enabled)
        #expect(!anthropic.consented)
    }

    @Test func settingsRoundTripThroughTheFile() throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let providers = [
            AIProviderEntry(id: "anthropic", kind: .anthropic, name: "Anthropic", consented: true),
            AIProviderEntry(id: "lm-studio", kind: .openAICompatible, name: "LM Studio", baseURL: "http://localhost:1234/v1", enabled: false),
        ]
        store[.intelligenceProviders] = providers
        store[.intelligenceModel] = "anthropic/claude-opus-5-5"
        store[.intelligenceRecapModel] = "apple/on-device"
        store.flush()

        let reopened = SettingsStore(fileURL: store.fileURL, watchForChanges: false)
        #expect(reopened[.intelligenceProviders] == providers)
        let settings = reopened.aiModelSettings
        #expect(settings.defaultModel == .provider(providerID: "anthropic", modelID: "claude-opus-5-5"))
        #expect(settings.choice(for: .catchUp) == settings.defaultModel)
        #expect(settings.choice(for: .recap) == .apple(.onDevice))
        #expect(settings.provider("lm-studio")?.enabled == false)
        #expect(!reopened.usesAppleModel(for: .catchUp))
        #expect(reopened.usesAppleModel(for: .recap))
    }

    @Test func defaultsAreApple() {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store[.intelligenceModel] == "apple")
        #expect(store[.intelligenceCatchUpModel] == "")
        #expect(store[.intelligenceProviders].isEmpty)
        #expect(store.aiModelSettings.choice(for: .catchUp) == .automatic)
        #expect(store.usesAppleModel(for: .catchUp))
    }

    @Test func newIDs() {
        let existing = [
            AIProviderEntry(id: "ollama", kind: .openAICompatible, name: "Ollama"),
            AIProviderEntry(id: "openai", kind: .openAI, name: "OpenAI"),
        ]
        #expect(AIProviderEntry.newID(kind: .anthropic, name: "Anthropic", existing: existing) == "anthropic")
        #expect(AIProviderEntry.newID(kind: .openAICompatible, name: "Ollama", existing: existing) == "ollama-2")
        #expect(AIProviderEntry.newID(kind: .openAICompatible, name: "LM Studio (desk)", existing: existing) == "lm-studio-desk")
        #expect(AIProviderEntry.newID(kind: .openAICompatible, name: "Apple", existing: existing) == "apple-2")
        #expect(AIProviderEntry.newID(kind: .openAICompatible, name: "!!!", existing: existing) == "custom")
    }

    @Test func catalogDescribesTheNewKeys() throws {
        let keys = SettingsCatalog.all.map(\.key)
        for key in ["intelligence.model", "intelligence.catchUpModel", "intelligence.recapModel", "intelligence.providers"] {
            #expect(keys.contains(key), "\(key)")
        }
        let providers = try #require(SettingsCatalog.descriptor(forKey: "intelligence.providers"))
        #expect(providers.schema["type"]?.stringValue == "array")
        #expect(providers.schema["items"]?["type"]?.stringValue == "object")
        #expect(providers.summary.contains("Keychain"))
        #expect(providers.title == "Intelligence: AI Providers")
        // Valid settings pass the validator.
        let text = #"{"intelligence.providers": [{"id": "anthropic", "kind": "anthropic", "consent": true}], "intelligence.model": "anthropic/claude-opus-5-5"}"#
        #expect(SettingsValidator.diagnostics(for: text).filter { $0.severity == .error }.isEmpty)
    }
}
