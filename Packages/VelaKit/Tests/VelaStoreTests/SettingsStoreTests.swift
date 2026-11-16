// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@MainActor
@Suite struct SettingsStoreTests {
    @Test func missingFileUsesDefaults() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        #expect(store.values.isEmpty)
        #expect(store.lastError == nil)
        #expect(store[.appearanceTheme] == "Palenight")
        #expect(store[.appearancePreferredDarkTheme] == "Palenight")
        #expect(store[.appearancePreferredLightTheme] == "Lighter")
        #expect(store[.chatLayout] == .grouped)
        #expect(store[.chatFontSize] == 13)
        #expect(store[.chatShowJoinPart] == .collapse)
        #expect(store[.chatScrollbackInMemory] == 1000)
        #expect(store[.highlightWords].isEmpty)
        #expect(store[.appearanceColorCustomizations].isEmpty)
        #expect(!store.isSet(.chatFontSize))
    }

    @Test func loadsJSONCWithTypedAccess() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("""
            // Vela settings
            {
              /* block comment */
              "chat.fontSize": 15, // trailing comment
              "chat.layout": "columns",
              "chat.showJoinPart": "nonsense",
              "chat.scrollbackInMemory": 2500,
              "history.retentionDays": 1.5,
              "highlight.words": ["vela", 42, "release",],
              "appearance.colorCustomizations": {"chat.background": "#000000"},
              "chat.showTimestamps": "false",
              "url.withSlashes": "https://example.com/a//b",
            }
            """, to: url)

        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store.lastError == nil)
        #expect(store[.chatFontSize] == 15)
        #expect(store[.chatLayout] == .columns)
        #expect(store[.chatShowJoinPart] == .collapse)  // invalid enum value -> default
        #expect(store[.chatScrollbackInMemory] == 2500)
        #expect(store[.historyRetentionDays] == 0)  // non-integer -> default
        #expect(store[.highlightWords] == ["vela", "release"])
        #expect(store[.appearanceColorCustomizations]["chat.background"] == .string("#000000"))
        #expect(store[.chatShowTimestamps])  // wrong type -> default
        #expect(store.value(forKey: "url.withSlashes") == .string("https://example.com/a//b"))
        #expect(store.isSet(.chatFontSize))
    }

    @Test func setWritesOnlyExplicitValuesAndPreservesUnknownKeys() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString(#"{"future.setting": {"nested": [1, 2]}, "chat.fontSize": 14}"#, to: url)

        let store = SettingsStore(fileURL: url, watchForChanges: false)
        store[.chatLayout] = .classic
        store[.sidebarWidth] = 240
        store[.highlightWords] = ["vela"]
        store.setValue(nil, forKey: "chat.fontSize")
        #expect(store[.chatFontSize] == 13)
        store.flush()

        let saved = try JSONC.value(from: Data(contentsOf: url))
        #expect(saved.objectValue?.keys.sorted() == ["chat.layout", "future.setting", "highlight.words", "sidebar.width"])
        #expect(saved["future.setting"] == .object(["nested": .array([.number(1), .number(2)])]))
        #expect(saved["chat.layout"] == .string("classic"))
        #expect(saved["sidebar.width"] == .number(240))

        // Pretty-printed with sorted keys and a trailing newline.
        let text = try readString(url)
        #expect(text.hasSuffix("}\n"))
        #expect(text.contains("\n  \"chat.layout\" : \"classic\""))
        let chatIndex = try #require(text.range(of: "chat.layout")).lowerBound
        let sidebarIndex = try #require(text.range(of: "sidebar.width")).lowerBound
        #expect(chatIndex < sidebarIndex)

        // Explicitly setting the default value keeps the key.
        store[.chatLayout] = .grouped
        store.flush()
        #expect(try JSONC.value(from: Data(contentsOf: url))["chat.layout"] == .string("grouped"))

        store.reset(.chatLayout)
        store.flush()
        #expect(try JSONC.value(from: Data(contentsOf: url))["chat.layout"] == nil)

        let reopened = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(reopened[.sidebarWidth] == 240)
        #expect(reopened[.highlightWords] == ["vela"])
    }

    @Test func writesAreDebounced() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        store.saveDelay = .milliseconds(300)

        store[.chatFontSize] = 16
        store[.chatFontSize] = 17
        store[.chatColorNicks] = false
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        let written = await waitUntil(timeout: .seconds(5)) {
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }
        #expect(written)
        let saved = try JSONC.value(from: Data(contentsOf: url))
        #expect(saved["chat.fontSize"] == .number(17))
        #expect(saved["chat.colorNicks"] == .bool(false))
    }

    @Test func reloadsExternalEdits() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString(#"{"chat.fontSize": 14}"#, to: url)

        let store = SettingsStore(fileURL: url)
        store.saveDelay = .milliseconds(50)
        #expect(store[.chatFontSize] == 14)

        // Our own write must not cause a spurious reload or error.
        store[.sidebarFontSize] = 11
        store.flush()
        try await Task.sleep(for: .milliseconds(400))
        #expect(store[.sidebarFontSize] == 11)
        #expect(store.lastError == nil)

        // Give FSEvents a moment so the external write isn't coalesced away.
        try await Task.sleep(for: .milliseconds(300))
        try writeString("""
            {
              // edited in a text editor
              "chat.fontSize": 18,
              "sidebar.fontSize": 11,
            }
            """, to: url)
        let reloaded = await waitUntil(timeout: .seconds(15)) { store[.chatFontSize] == 18 }
        #expect(reloaded)
        #expect(store[.sidebarFontSize] == 11)
        #expect(store.lastError == nil)

        // An invalid edit keeps the last good values and reports an error.
        try await Task.sleep(for: .milliseconds(300))
        try writeString(#"{"chat.fontSize": 20, "#, to: url)
        let failed = await waitUntil(timeout: .seconds(15)) { store.lastError != nil }
        #expect(failed)
        #expect(store[.chatFontSize] == 18)

        // App-side changes made meanwhile don't overwrite the broken file...
        store[.chatLineSpacing] = 4
        store.flush()
        #expect(try readString(url) == #"{"chat.fontSize": 20, "#)

        // ...and are applied once the file is fixed.
        try await Task.sleep(for: .milliseconds(300))
        try writeString(#"{"chat.fontSize": 20}"#, to: url)
        let recovered = await waitUntil(timeout: .seconds(15)) {
            store.lastError == nil && store[.chatFontSize] == 20
        }
        #expect(recovered)
        #expect(store[.chatLineSpacing] == 4)
        let merged = await waitUntil(timeout: .seconds(5)) {
            (try? JSONC.value(from: Data(contentsOf: url)))?["chat.lineSpacing"] == .number(4)
        }
        #expect(merged)
        #expect(try JSONC.value(from: Data(contentsOf: url))["chat.fontSize"] == .number(20))
    }

    @Test func invalidFileAtLaunchKeepsDefaults() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("[1, 2, 3]", to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store.lastError != nil)
        #expect(store[.chatFontSize] == 13)
    }

    @Test func blankOrCommentOnlyFileIsEmpty() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("// nothing here yet\n", to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store.lastError == nil)
        #expect(store.values.isEmpty)
    }

    @Test func settingKeysAreHashableByName() {
        #expect(SettingKey<Double>.chatFontSize == SettingKey<Double>.chatFontSize)
        #expect(SettingKey<Double>.chatFontSize != SettingKey<Double>.sidebarWidth)
        #expect(Set([SettingKey<Bool>.chatColorNicks, .chatColorNicks]).count == 1)
    }
}

@Suite struct SettingsCatalogTests {
    @Test func catalogIsCompleteAndUnique() {
        let keys = SettingKey.allKnownKeys.map(\.key)
        #expect(keys.count == 59)
        #expect(Set(keys).count == keys.count)
        #expect(keys.allSatisfy { $0.contains(".") })
        #expect(SettingKey.allKnownKeys.allSatisfy { !$0.summary.isEmpty })

        let theme = SettingsCatalog.descriptor(forKey: "appearance.theme")
        #expect(theme?.defaultValue == .string("Palenight"))
        #expect(theme?.category == "appearance")
        #expect(SettingsCatalog.descriptor(forKey: "appearance.preferredLightTheme")?.defaultValue == .string("Lighter"))
        #expect(SettingsCatalog.descriptor(forKey: "chat.layout")?.schema["enum"]
            == .array([.string("classic"), .string("grouped"), .string("columns")]))
        #expect(SettingsCatalog.descriptor(forKey: "history.retentionDays")?.schema["type"] == .string("integer"))
        #expect(SettingsCatalog.descriptor(forKey: "highlight.words")?.schema["items"]?["type"] == .string("string"))
        // Migrated keys are no longer documented.
        #expect(SettingsCatalog.descriptor(forKey: "media.blockedDomains") == nil)
        #expect(SettingsCatalog.descriptor(forKey: "media.allowedDomains") == nil)
        #expect(SettingsCatalog.descriptor(forKey: "media.presentation") == nil)
        #expect(SettingsCatalog.descriptor(forKey: "media.loadVideoEmbeds") == nil)
    }

    @Test func previewSizeKeysAreDocumented() {
        let expected: [(key: String, default: JSONValue, cases: [JSONValue])] = [
            ("media.linkPreviewSize", "standard", ["minimal", "standard", "large"]),
            ("media.videos", "player", ["player", "compact", "off"]),
            ("media.imageSize", "full", ["full", "thumbnail"]),
        ]
        for (key, defaultValue, cases) in expected {
            let descriptor = SettingsCatalog.descriptor(forKey: key)
            #expect(descriptor?.defaultValue == defaultValue, "\(key)")
            #expect(descriptor?.schema["enum"] == .array(cases), "\(key)")
            #expect(descriptor?.category == "media")
        }
    }

    @Test func jsonSchemaDescribesEveryKey() throws {
        let schema = SettingsCatalog.jsonSchema()
        let properties = try #require(schema["properties"]?.objectValue)
        #expect(properties.count == SettingsCatalog.all.count)
        #expect(properties["chat.fontSize"]?["default"] == .number(13))
        #expect(properties["chat.fontSize"]?["type"] == .string("number"))
        #expect(properties["chat.fontSize"]?["description"] != nil)

        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.schema.json")
        try SettingsCatalog.writeJSONSchema(to: url)
        #expect(try JSONC.value(from: Data(contentsOf: url)) == schema)
    }

    @Test func defaultSettingsDocumentIsValidJSONC() throws {
        let document = SettingsCatalog.defaultSettingsDocument()
        let parsed = try JSONC.value(from: Data(document.utf8))
        let object = try #require(parsed.objectValue)
        #expect(object.count == SettingsCatalog.all.count)
        for descriptor in SettingsCatalog.all {
            #expect(object[descriptor.key] == descriptor.defaultValue)
        }
        #expect(document.contains("// chat"))
    }
}

@MainActor
@Suite struct SettingsPresetTests {
    @Test func presetKeysAreKnownSettings() {
        for preset in SettingsPreset.all {
            for key in preset.values.keys {
                #expect(SettingsCatalog.descriptor(forKey: key) != nil, "\(preset.id) sets unknown key \(key)")
            }
        }
    }

    @Test func presetsSetEveryPreviewSize() {
        let expected: [String: [String: JSONValue]] = [
            "classic": ["media.linkPreviewSize": "minimal", "media.videos": "compact", "media.imageSize": "thumbnail"],
            "modern": ["media.linkPreviewSize": "standard", "media.videos": "player", "media.imageSize": "full"],
            "tabbed": ["media.linkPreviewSize": "standard", "media.videos": "player", "media.imageSize": "full"],
            "focus": ["media.linkPreviewSize": "minimal", "media.videos": "player", "media.imageSize": "thumbnail"],
        ]
        #expect(Set(SettingsPreset.all.map(\.id)) == Set(expected.keys))
        for preset in SettingsPreset.all {
            let media = preset.values.filter { $0.key.hasPrefix("media.") }
            #expect(media == expected[preset.id], "\(preset.id)")
            #expect(preset.values["media.presentation"] == nil)
            #expect(preset.values["media.loadVideoEmbeds"] == nil)
        }
    }

    @Test func defaultsMatchModern() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        #expect(store.matchingPreset()?.id == "modern")
        // Modern's new media values are the defaults, so a reset still matches.
        store[.mediaVideos] = .compact
        #expect(store.matchingPreset() == nil)
        store.reset(.mediaVideos)
        #expect(store.matchingPreset()?.id == "modern")
    }

    @Test(arguments: SettingsPreset.all.map(\.id))
    func everyPresetIsDetectedAfterApplying(_ id: String) throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        store.apply(try #require(SettingsPreset.all.first { $0.id == id }))
        #expect(store.matchingPreset()?.id == id)
    }

    @Test func numbersMatchLoosely() {
        #expect(SettingsPreset.valuesMatch(["a": 12]) { _ in .number(12.00001) })
        #expect(!SettingsPreset.valuesMatch(["a": 12]) { _ in .number(12.1) })
        #expect(!SettingsPreset.valuesMatch(["a": 12]) { _ in nil })
        #expect(!SettingsPreset.valuesMatch(["a": "12"]) { _ in .number(12) })
    }

    @Test func applyingPresetIsDetectedAndCustomizationBreaksMatch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json"), watchForChanges: false)
        store.apply(.focus)
        #expect(store.matchingPreset()?.id == "focus")
        #expect(store[.navigationStyle] == .tabs)
        #expect(store[.tabsPlacement] == .titleBar)
        #expect(store[.tabsRoundness] == 1)
        store[.chatFontSize] = 17
        #expect(store.matchingPreset() == nil)
        store.apply(.classic)
        #expect(store.matchingPreset()?.id == "classic")
        #expect(store[.chatMonospace])
    }
}
