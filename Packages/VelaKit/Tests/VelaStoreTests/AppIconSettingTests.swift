// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite("App icon setting")
struct AppIconSettingTests {
    let key = SettingKey.appearanceAppIcon

    @Test func defaultsToTheStandardIcon() {
        #expect(key.key == "appearance.appIcon")
        #expect(key.defaultValue == .vela)
        #expect(key.value(from: nil) == .vela)
        #expect(key.defaultJSONValue == .string("vela"))
    }

    @Test func decodesEveryIconAndFallsBackOnBadValues() {
        #expect(AppIcon.allCases.map(\.rawValue) == ["vela", "midnight", "graphite", "sunrise", "paper", "vivid"])
        for icon in AppIcon.allCases {
            #expect(key.value(from: .string(icon.rawValue)) == icon)
            #expect(key.value(from: key.jsonValue(for: icon)) == icon)
        }
        // Wrong values fall back to the standard icon.
        #expect(key.value(from: .string("Midnight")) == .vela)
        #expect(key.value(from: .string("neon")) == .vela)
        #expect(key.value(from: .string("")) == .vela)
        #expect(key.value(from: .bool(true)) == .vela)
        #expect(key.value(from: .number(2)) == .vela)
    }

    @Test func isDocumentedUnderAppearance() throws {
        let descriptor = try #require(SettingsCatalog.descriptor(forKey: "appearance.appIcon"))
        #expect(descriptor.defaultValue == .string("vela"))
        #expect(descriptor.enumValues == ["vela", "midnight", "graphite", "sunrise", "paper", "vivid"])
        #expect(descriptor.settingsCategory == .appearance)
        #expect(descriptor.title == "Appearance: App Icon")
        #expect(descriptor.summary.contains("Dock"))
        #expect(descriptor.enumValues?.map(SettingsMetadata.enumLabel) == ["Vela", "Midnight", "Graphite", "Sunrise", "Paper", "Vivid"])
        #expect(SettingsCatalog.jsonSchema()["properties"]?["appearance.appIcon"]?["enum"]
            == .array(["vela", "midnight", "graphite", "sunrise", "paper", "vivid"]))
        #expect(SettingsCatalog.defaultSettingsDocument().contains("\"appearance.appIcon\": \"vela\""))
    }

    @MainActor
    @Test func readsAndWritesThroughTheStore() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        #expect(store[.appearanceAppIcon] == .vela)
        #expect(!store.isSet(.appearanceAppIcon))
        store[.appearanceAppIcon] = .sunrise
        #expect(store.value(forKey: "appearance.appIcon") == .string("sunrise"))
        store.setValue(.string("paper"), forKey: "appearance.appIcon")
        #expect(store[.appearanceAppIcon] == .paper)
        store.reset(.appearanceAppIcon)
        #expect(store[.appearanceAppIcon] == .vela)
    }
}
