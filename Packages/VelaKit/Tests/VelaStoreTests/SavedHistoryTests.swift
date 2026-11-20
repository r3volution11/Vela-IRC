// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

/// What's saved (`history.save`), deleting it, and the upgrade that keeps
/// saving it on Macs that already had history.
@Suite struct SavedHistoryTests {
    let network = UUID()
    var channel: BufferKey { BufferKey(networkID: network, foldedName: "#vela") }

    private func message(_ text: String, at offset: TimeInterval, msgid: String? = nil) -> MessageRecord {
        MessageRecord(
            networkID: network, bufferName: "#vela", msgid: msgid,
            time: Date(timeIntervalSince1970: 1_700_000_000 + offset), kind: "message", nick: "ada", text: text
        )
    }

    private func fill(_ db: VelaDatabase) async throws {
        try await db.append((0..<50).map { message("saved line \($0)", at: TimeInterval($0), msgid: "m\($0)") })
        try await db.setReaction(ReactionRecord(msgid: "m1", nick: "wren", emoji: "👍"), in: channel, active: true)
        try await db.storePreviewJSON(Data("{}".utf8), url: "https://example.com/")
        try await db.upsertBuffer(BufferRecord(
            networkID: network, name: "#vela", foldedName: "#vela", kind: "channel",
            lastReadAt: Date(timeIntervalSince1970: 1_700_000_040), isMuted: true, sortOrder: 3
        ))
    }

    // MARK: What's saved

    @Test func savedHistoryReportsEachKind() async throws {
        let db = try VelaDatabase.inMemory()
        #expect(try await db.savedHistory() == SavedHistory())
        #expect(try await db.savedHistory().isEmpty)

        try await db.upsertBuffer(BufferRecord(networkID: network, name: "#vela", foldedName: "#vela", kind: "channel"))
        // Buffer state isn't history.
        #expect(try db.savedHistoryNow().isEmpty)

        try await db.storePreviewJSON(Data("{}".utf8), url: "https://example.com/")
        #expect(try await db.savedHistory() == SavedHistory(hasLinkPreviews: true))
        try await db.append([message("hi", at: 0)])
        try await db.setReaction(ReactionRecord(msgid: "x", nick: "wren", emoji: "👍"), in: channel, active: true)
        let saved = try db.savedHistoryNow()
        #expect(saved == SavedHistory(hasMessages: true, hasReactions: true, hasLinkPreviews: true))
        #expect(!saved.isEmpty)
    }

    // MARK: Deleting

    @Test func deleteSavedHistoryKeepsBufferState() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("vela.sqlite")
        let db = try VelaDatabase(url: url)
        try await fill(db)
        let before = try await db.storageCounts()
        #expect(before == StorageCounts(messages: 50, fullTextEntries: 50, reactions: 1, linkPreviews: 1, buffers: 1))

        try await db.deleteSavedHistory()

        #expect(try await db.storageCounts() == StorageCounts(messages: 0, fullTextEntries: 0, reactions: 0, linkPreviews: 0, buffers: 1))
        #expect(try await db.savedHistory().isEmpty)
        #expect(try await db.search("saved", networkID: nil, limit: 10).isEmpty)
        let buffer = try #require(try await db.buffers(networkID: network).first)
        #expect(buffer.isMuted)
        #expect(buffer.sortOrder == 3)
        #expect(buffer.lastReadAt == Date(timeIntervalSince1970: 1_700_000_040))

        // The deleted text is gone from the file and its write-ahead log.
        for suffix in ["", "-wal"] {
            let data = (try? Data(contentsOf: URL(fileURLWithPath: url.path(percentEncoded: false) + suffix))) ?? Data()
            #expect(data.range(of: Data("saved line".utf8)) == nil, "vela.sqlite\(suffix)")
        }

        // The search index still follows new messages, and deletes.
        try await db.append([message("after the delete", at: 100, msgid: "n1")])
        #expect(try await db.search("delete", networkID: network, limit: 10).map(\.text) == ["after the delete"])
        try await db.deleteBuffer(channel, keepMessages: false)
        #expect(try await db.storageCounts().fullTextEntries == 0)
    }

    @Test func deleteSavedHistoryOnAnEmptyDatabase() async throws {
        let db = try VelaDatabase.inMemory()
        try await db.deleteSavedHistory()
        #expect(try await db.storageCounts() == StorageCounts())
    }

    // MARK: Upgrading

    @MainActor
    @Test func upgradeWithSavedMessagesKeepsSaving() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        try writeString("{\n  // mine\n  \"chat.fontSize\": 14\n}\n", to: url)
        let settings = SettingsStore(fileURL: url, watchForChanges: false)
        let record = LaunchRecord.inMemory()

        let kept = HistorySaveMigration.run(
            settings: settings, savedHistory: SavedHistory(hasMessages: true), record: record, version: "1.1.0"
        )

        #expect(kept)
        #expect(settings[.historySave])
        // Written to settings.json at once, explicitly, keeping the rest.
        let text = try readString(url)
        #expect(text.contains("\"history.save\": true"))
        #expect(text.contains("// mine"))
        #expect(record.event(HistorySaveMigration.keptHistoryEvent) == "1.1.0")
        #expect(record.hasRun(HistorySaveMigration.id))
    }

    @MainActor
    @Test func newInstallStaysOff() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("settings.json")
        let settings = SettingsStore(fileURL: url, watchForChanges: false)
        let record = LaunchRecord.inMemory()

        // An empty database, or one with only buffer state or previews.
        let kept = HistorySaveMigration.run(
            settings: settings, savedHistory: SavedHistory(hasLinkPreviews: true), record: record, version: "1.1.0"
        )

        #expect(!kept)
        #expect(!settings[.historySave])
        #expect(!settings.isSet(.historySave))
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(record.event(HistorySaveMigration.keptHistoryEvent) == nil)
        #expect(record.hasRun(HistorySaveMigration.id))
    }

    @MainActor
    @Test func migrationRunsOnceAndRespectsAnExplicitChoice() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let settings = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        settings.saveDelay = .zero

        // Already chosen (another Mac's settings.json, or by hand): left alone.
        settings[.historySave] = false
        settings.flush()
        let record = LaunchRecord.inMemory()
        #expect(!HistorySaveMigration.run(settings: settings, savedHistory: SavedHistory(hasMessages: true), record: record, version: "1.1.0"))
        #expect(settings.isSet(.historySave) && !settings[.historySave])

        // Resetting to the default later isn't undone at the next launch.
        settings.reset(.historySave)
        settings.flush()
        #expect(!HistorySaveMigration.run(settings: settings, savedHistory: SavedHistory(hasMessages: true), record: record, version: "1.1.0"))
        #expect(!settings.isSet(.historySave))
    }

    @MainActor
    @Test func unreadableDatabaseWaitsForTheNextLaunch() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let settings = SettingsStore(fileURL: directory.file("settings.json"), watchForChanges: false)
        let record = LaunchRecord.inMemory()

        #expect(!HistorySaveMigration.run(settings: settings, savedHistory: nil, record: record, version: "1.1.0"))
        #expect(!record.hasRun(HistorySaveMigration.id))
        #expect(HistorySaveMigration.run(settings: settings, savedHistory: SavedHistory(hasMessages: true), record: record, version: "1.1.0"))
    }

    @MainActor
    @Test func launchRecordKeys() {
        var stored: [String: String] = [:]
        let record = LaunchRecord(read: { stored[$0] }, write: { stored[$0] = $1 })
        record.lastWhatsNewVersion = "1.1.0"
        record.markRun("example", version: "1.1.0")
        record.recordEvent("something", version: "1.1.0")
        #expect(stored == [
            "Vela.whatsNew.lastVersion": "1.1.0",
            "Vela.migrations.example": "1.1.0",
            "Vela.events.something": "1.1.0",
        ])
        record.lastWhatsNewVersion = nil
        #expect(stored["Vela.whatsNew.lastVersion"] == nil)
    }

    @Test func historySaveIsDocumentedAndOffByDefault() {
        let descriptor = SettingsCatalog.descriptor(forKey: "history.save")
        #expect(descriptor?.defaultValue == .bool(false))
        #expect(descriptor?.schema["type"] == .string("boolean"))
        #expect(descriptor?.settingsCategory == .history)
        #expect(descriptor?.name == "Save Message History")
        // Listed just before the retention it governs.
        let keys = SettingsCatalog.all.map(\.key)
        #expect(keys.firstIndex(of: "history.save").map { $0 + 1 } == keys.firstIndex(of: "history.retentionDays"))
    }
}
