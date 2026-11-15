// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
import VelaStore  // deliberately not @testable: only the public contract

/// Compiles the API the app layer codes against, through a plain import.
@MainActor
@Suite struct PublicAPITests {
    @Test func settingsContract() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let settings = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        settings[.chatLayout] = .columns
        let layout: ChatLayout = settings[.chatLayout]
        let joins: JoinPartDisplay = settings[.chatShowJoinPart]
        let customizations: [String: JSONValue] = settings[.appearanceColorCustomizations]
        #expect(layout == .columns)
        #expect(joins == .collapse)
        #expect(customizations.isEmpty)
        settings.setValue(.string("x"), forKey: "custom.key")
        #expect(settings.value(forKey: "custom.key") == .string("x"))
        settings.flush()
        #expect(settings.lastError == nil)

        // Keys work as key-path subscript indices (for @Bindable bindings).
        let keyPath = \SettingsStore.[SettingKey<Double>.chatFontSize]
        #expect(settings[keyPath: keyPath] == 13)

        let custom = SettingKey<Int>("custom.count", default: 3, summary: "A custom key.")
        #expect(settings[custom] == 3)
        #expect(SettingKey.allKnownKeys.contains { $0.key == "chat.layout" })
    }

    @Test func networkContract() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = NetworkConfigStore(fileURL: directory.file("networks.json"))
        try store.load()
        var config = NetworkConfig(name: "Libera", host: "irc.libera.chat", nick: "vela")
        config.saslKind = .plain
        config.bouncerKind = .soju
        config.autoJoin = [AutoJoinChannel(name: "#vela", hasKey: false)]
        store.upsert(config)
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 1)
        store.remove(id: config.id)
        #expect(store.networks.isEmpty)
        #expect(Keychain.account(networkID: config.id, purpose: .nickServPassword).hasSuffix("/nickServPassword"))
    }

    @Test func databaseContract() async throws {
        let db = try VelaDatabase.inMemory()
        let key = BufferKey(networkID: UUID(), foldedName: "#vela")
        let record = MessageRecord(
            networkID: key.networkID, bufferName: key.foldedName, msgid: "1",
            time: Date(), kind: "privmsg", nick: "a", text: "hi"
        )
        try await db.append([record])
        _ = try await db.latestMessages(in: key, limit: 50)
        _ = try await db.messages(in: key, before: Date(), limit: 50)
        _ = try await db.newestMessageTime(in: key)
        _ = try await db.newestMessageTime(networkID: key.networkID)
        try await db.markRedacted(msgid: "1", in: key)
        try await db.setReaction(ReactionRecord(msgid: "1", nick: "b", emoji: "👍"), in: key, active: true)
        _ = try await db.reactions(in: key, msgids: ["1"])
        _ = try await db.search("hi", networkID: nil, limit: 10)
        try await db.upsertBuffer(BufferRecord(
            networkID: key.networkID, name: "#vela", foldedName: "#vela", kind: "channel", autoRejoin: false
        ))
        _ = try await db.buffers(networkID: key.networkID)
        try await db.deleteBuffer(key)
        try await db.deleteBuffer(key, keepMessages: false)
        try await db.deleteNetwork(key.networkID)
        try await db.storePreviewJSON(Data("{}".utf8), url: "https://example.com")
        _ = try await db.cachedPreviewJSON(url: "https://example.com")
        try await db.pruneMessages(olderThan: Date())
    }
}
