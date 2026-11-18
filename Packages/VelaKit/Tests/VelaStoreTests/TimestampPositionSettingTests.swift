// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite("Timestamp position settings")
struct TimestampPositionSettingTests {
    @Test func eachLayoutHasItsOwnKeyAndKeepsTodaysLook() {
        #expect(SettingKey.chatTimestampPositionClassic.key == "chat.timestampPosition.classic")
        #expect(SettingKey.chatTimestampPositionGrouped.key == "chat.timestampPosition.grouped")
        #expect(SettingKey.chatTimestampPositionColumns.key == "chat.timestampPosition.columns")
        // Classic and columns have a time column on the left; grouped puts
        // the time beside the name.
        #expect(SettingKey.chatTimestampPositionClassic.defaultValue == .left)
        #expect(SettingKey.chatTimestampPositionGrouped.defaultValue == .top)
        #expect(SettingKey.chatTimestampPositionColumns.defaultValue == .left)
        for layout in ChatLayout.allCases {
            #expect(SettingKey<TimestampPosition>.chatTimestampPosition(for: layout).key == "chat.timestampPosition.\(layout.rawValue)")
        }
    }

    @Test func decodesEveryPositionAndFallsBackOnBadValues() {
        let key = SettingKey.chatTimestampPositionGrouped
        #expect(key.value(from: nil) == .top)
        #expect(key.value(from: .string("left")) == .left)
        #expect(key.value(from: .string("right")) == .right)
        #expect(key.value(from: .string("top")) == .top)
        #expect(key.value(from: .string("bottom")) == .bottom)
        #expect(key.value(from: .string("Left")) == .top)
        #expect(key.value(from: .string("middle")) == .top)
        #expect(key.value(from: .bool(true)) == .top)
        #expect(key.value(from: .number(1)) == .top)
        for position in TimestampPosition.allCases {
            #expect(key.value(from: key.jsonValue(for: position)) == position)
        }
    }

    @Test func areDocumentedAfterTheTimestampFormat() throws {
        let keys = SettingsCatalog.all.map(\.key)
        let format = try #require(keys.firstIndex(of: "chat.timestampFormat"))
        #expect(Array(keys[(format + 1)...(format + 3)]) == [
            "chat.timestampPosition.classic", "chat.timestampPosition.grouped", "chat.timestampPosition.columns",
        ])
        let descriptor = try #require(SettingsCatalog.descriptor(forKey: "chat.timestampPosition.grouped"))
        #expect(descriptor.defaultValue == .string("top"))
        #expect(descriptor.enumValues == ["left", "right", "top", "bottom"])
        #expect(descriptor.settingsCategory == .chat)
        #expect(descriptor.title == "Chat: Timestamp Position in Modern")
        #expect(descriptor.enumValues?.map(SettingsMetadata.enumLabel) == ["Left", "Right", "Top", "Bottom"])
        #expect(SettingsCatalog.descriptor(forKey: "chat.timestampPosition.classic")?.defaultValue == .string("left"))
        #expect(SettingsCatalog.descriptor(forKey: "chat.timestampPosition.columns")?.defaultValue == .string("left"))
        #expect(SettingsCatalog.jsonSchema()["properties"]?["chat.timestampPosition.columns"]?["enum"]
            == .array(["left", "right", "top", "bottom"]))
    }

    @MainActor
    @Test func layoutsRememberTheirOwnPosition() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        store[.chatTimestampPositionClassic] = .right
        store.setValue(.string("bottom"), forKey: "chat.timestampPosition.grouped")
        #expect(store[.chatTimestampPositionClassic] == .right)
        #expect(store[.chatTimestampPositionGrouped] == .bottom)
        #expect(store[.chatTimestampPositionColumns] == .left)
        #expect(store.value(forKey: "chat.timestampPosition.classic") == .string("right"))
        // Switching layouts leaves every position alone.
        store[.chatLayout] = .classic
        store[.chatLayout] = .grouped
        #expect(store[.chatTimestampPositionClassic] == .right)
        #expect(store[.chatTimestampPositionGrouped] == .bottom)
    }
}
