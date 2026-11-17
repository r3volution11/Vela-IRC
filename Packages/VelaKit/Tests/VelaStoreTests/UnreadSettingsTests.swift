// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite("Unread settings: where channels open and the New line")
struct UnreadSettingsTests {
    @Test func defaultsKeepTodaysBehavior() {
        #expect(SettingKey.chatOpenAt.key == "chat.openAt")
        #expect(SettingKey.chatOpenAt.defaultValue == .firstUnread)
        #expect(SettingKey.chatOpenAt.defaultJSONValue == .string("firstUnread"))
        #expect(SettingKey.chatShowUnreadMarker.key == "chat.showUnreadMarker")
        #expect(SettingKey.chatShowUnreadMarker.defaultValue == true)
        #expect(SettingKey.chatShowUnreadMarker.value(from: nil) == true)
    }

    @Test func decodesValuesAndFallsBackOnBadOnes() {
        let key = SettingKey.chatOpenAt
        #expect(ChatOpenPosition.allCases.map(\.rawValue) == ["firstUnread", "newest"])
        #expect(key.value(from: .string("newest")) == .newest)
        #expect(key.value(from: .string("firstUnread")) == .firstUnread)
        #expect(key.value(from: key.jsonValue(for: .newest)) == .newest)
        #expect(key.value(from: .string("Newest")) == .firstUnread)
        #expect(key.value(from: .string("bottom")) == .firstUnread)
        #expect(key.value(from: .bool(true)) == .firstUnread)

        let marker = SettingKey.chatShowUnreadMarker
        #expect(marker.value(from: .bool(false)) == false)
        #expect(marker.value(from: .string("no")) == true)
    }

    @Test func areDocumentedUnderMessages() throws {
        let openAt = try #require(SettingsCatalog.descriptor(forKey: "chat.openAt"))
        #expect(openAt.defaultValue == .string("firstUnread"))
        #expect(openAt.enumValues == ["firstUnread", "newest"])
        #expect(openAt.enumValues?.map(SettingsMetadata.enumLabel) == ["First unread", "Newest"])
        #expect(openAt.title == "Chat: Open Channels At")
        #expect(openAt.settingsCategory == .chat)
        #expect(openAt.summary.contains("New line"))

        let marker = try #require(SettingsCatalog.descriptor(forKey: "chat.showUnreadMarker"))
        #expect(marker.defaultValue == .bool(true))
        #expect(marker.title == "Chat: Show New Line")
        #expect(marker.settingsCategory == .chat)
        #expect(marker.summary.contains("Catch me up"))

        let document = SettingsCatalog.defaultSettingsDocument()
        #expect(document.contains("\"chat.openAt\": \"firstUnread\""))
        #expect(document.contains("\"chat.showUnreadMarker\": true"))
    }

    @MainActor
    @Test func readAndWriteThroughTheStore() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        #expect(store[.chatOpenAt] == .firstUnread)
        #expect(store[.chatShowUnreadMarker])
        store[.chatOpenAt] = .newest
        store[.chatShowUnreadMarker] = false
        #expect(store.value(forKey: "chat.openAt") == .string("newest"))
        #expect(store.value(forKey: "chat.showUnreadMarker") == .bool(false))
        store.reset(.chatOpenAt)
        store.reset(.chatShowUnreadMarker)
        #expect(store[.chatOpenAt] == .firstUnread)
        #expect(store[.chatShowUnreadMarker])
    }
}
