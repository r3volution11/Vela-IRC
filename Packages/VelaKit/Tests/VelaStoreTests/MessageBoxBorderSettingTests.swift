// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite("Message box border setting")
struct MessageBoxBorderSettingTests {
    let key = SettingKey.appearanceMessageBoxBorder

    @Test func defaultsToSubtle() {
        #expect(key.key == "appearance.messageBoxBorder")
        #expect(key.defaultValue == .subtle)
        #expect(key.value(from: nil) == .subtle)
        #expect(key.defaultJSONValue == .string("subtle"))
    }

    @Test func decodesEveryStyleAndFallsBackOnBadValues() {
        #expect(key.value(from: .string("none")) == MessageBoxBorder.none)
        #expect(key.value(from: .string("subtle")) == .subtle)
        #expect(key.value(from: .string("accent")) == .accent)
        // Wrong values fall back to the default.
        #expect(key.value(from: .string("Accent")) == .subtle)
        #expect(key.value(from: .string("thick")) == .subtle)
        #expect(key.value(from: .bool(false)) == .subtle)
        #expect(key.value(from: .number(0)) == .subtle)
        for style in MessageBoxBorder.allCases {
            #expect(key.value(from: key.jsonValue(for: style)) == style)
        }
    }

    @Test func isDocumentedUnderAppearance() throws {
        let descriptor = try #require(SettingsCatalog.descriptor(forKey: "appearance.messageBoxBorder"))
        #expect(descriptor.defaultValue == .string("subtle"))
        #expect(descriptor.enumValues == ["none", "subtle", "accent"])
        #expect(descriptor.settingsCategory == .appearance)
        #expect(descriptor.title == "Appearance: Message Box Border")
        #expect(!descriptor.summary.isEmpty)
        // The settings editor's labels match Settings → Appearance.
        #expect(descriptor.enumValues?.map(SettingsMetadata.enumLabel) == ["None", "Subtle", "Accent when typing"])
        // Listed right after the color customizations it works with.
        let keys = SettingsCatalog.all.map(\.key)
        let index = try #require(keys.firstIndex(of: "appearance.messageBoxBorder"))
        #expect(keys[index - 1] == "appearance.colorCustomizations")
        #expect(SettingsCatalog.jsonSchema()["properties"]?["appearance.messageBoxBorder"]?["enum"]
            == .array(["none", "subtle", "accent"]))
    }

    @MainActor
    @Test func readsAndWritesThroughTheStore() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        #expect(store[.appearanceMessageBoxBorder] == .subtle)
        store[.appearanceMessageBoxBorder] = .none
        #expect(store.value(forKey: "appearance.messageBoxBorder") == .string("none"))
        #expect(store[.appearanceMessageBoxBorder] == MessageBoxBorder.none)
        store.setValue(.string("accent"), forKey: "appearance.messageBoxBorder")
        #expect(store[.appearanceMessageBoxBorder] == .accent)
    }
}
