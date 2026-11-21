// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

/// Vela 1.0's Modern Chat spacing (2 and 6) moving to 1.1's (4 and 12),
/// once, and only when it's still exactly that.
@MainActor
@Suite("Modern Chat spacing migration")
struct ModernChatSpacingMigrationTests {
    private func settings(_ text: String?, in directory: TemporaryDirectory) throws -> (SettingsStore, URL) {
        let url = directory.file("settings.json")
        if let text { try writeString(text, to: url) }
        return (SettingsStore(fileURL: url, watchForChanges: false), url)
    }

    /// Modern Chat as Vela 1.0 wrote it when you applied it.
    private var modernChatFromVela1: String {
        var values = SettingsPreset.modern.values
        values["chat.lineSpacing"] = 2
        values["chat.messageSpacing"] = 6
        let lines = values.keys.sorted().map { key in
            let value = String(decoding: try! JSONEncoder().encode(values[key]!), as: UTF8.self)
            return "  \"\(key)\": \(value)"
        }
        return "{\n  // mine\n  \"appearance.theme\": \"Nord\",\n" + lines.joined(separator: ",\n") + "\n}\n"
    }

    @Test func oldModernChatSpacingMoves() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let (settings, url) = try settings(modernChatFromVela1, in: directory)
        #expect(settings.matchingPreset() == nil, "1.0's Modern Chat shows as Custom in 1.1")
        let record = LaunchRecord.inMemory()

        #expect(ModernChatSpacingMigration.run(settings: settings, record: record, version: "1.1.0"))

        #expect(settings[.chatLineSpacing] == 4)
        #expect(settings[.chatMessageSpacing] == 12)
        #expect(settings.matchingPreset()?.id == "modern")
        // Written to settings.json at once, explicitly, as applying the
        // preset writes them, keeping the rest of the file.
        let text = try readString(url)
        #expect(text.contains("\"chat.lineSpacing\": 4"))
        #expect(text.contains("\"chat.messageSpacing\": 12"))
        #expect(text.contains("// mine"))
        #expect(text.contains("\"appearance.theme\": \"Nord\""))
        #expect(record.event(ModernChatSpacingMigration.movedEvent) == "1.1.0")
        #expect(record.hasRun(ModernChatSpacingMigration.id))
    }

    @Test(arguments: [
        #"{"chat.lineSpacing": 2, "chat.messageSpacing": 8}"#,
        #"{"chat.lineSpacing": 3, "chat.messageSpacing": 6}"#,
        #"{"chat.lineSpacing": 2}"#,
        #"{"chat.messageSpacing": 6}"#,
        #"{"chat.lineSpacing": 2.5, "chat.messageSpacing": 6}"#,
        #"{"chat.lineSpacing": "2", "chat.messageSpacing": "6"}"#,
        #"{"chat.lineSpacing": 1, "chat.messageSpacing": 2}"#,
    ])
    func otherSpacingIsLeftAlone(_ text: String) throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let (settings, url) = try settings(text, in: directory)
        let before = settings.values
        let record = LaunchRecord.inMemory()

        #expect(!ModernChatSpacingMigration.run(settings: settings, record: record, version: "1.1.0"))

        #expect(settings.values == before)
        #expect(try readString(url) == text)
        #expect(record.event(ModernChatSpacingMigration.movedEvent) == nil)
        #expect(record.hasRun(ModernChatSpacingMigration.id))
    }

    /// Without the keys, the new defaults already apply: nothing is written.
    @Test func newInstallIsLeftAlone() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let (settings, url) = try settings(nil, in: directory)
        let record = LaunchRecord.inMemory()

        #expect(!ModernChatSpacingMigration.run(settings: settings, record: record, version: "1.1.0"))

        #expect(settings.values.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(settings[.chatLineSpacing] == 4)
        #expect(settings[.chatMessageSpacing] == 12)
        #expect(record.hasRun(ModernChatSpacingMigration.id))
    }

    /// Spacing set back to 2 and 6 by hand after the migration stays.
    @Test func runsOnce() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let (settings, _) = try settings(#"{"chat.lineSpacing": 2, "chat.messageSpacing": 6}"#, in: directory)
        let record = LaunchRecord.inMemory()
        #expect(ModernChatSpacingMigration.run(settings: settings, record: record, version: "1.1.0"))

        settings[.chatLineSpacing] = 2
        settings[.chatMessageSpacing] = 6
        settings.flush()
        #expect(!ModernChatSpacingMigration.run(settings: settings, record: record, version: "1.1.0"))
        #expect(!ModernChatSpacingMigration.run(settings: settings, record: record, version: "1.2.0"))
        #expect(settings[.chatLineSpacing] == 2)
        #expect(settings[.chatMessageSpacing] == 6)
        #expect(record.event(ModernChatSpacingMigration.movedEvent) == "1.1.0")
    }

    /// A settings.json that can't be read reads as all defaults, so the
    /// migration waits for a launch where it can.
    @Test func waitsForAReadableSettingsFile() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let (settings, url) = try settings(#"{"chat.lineSpacing": 2, "chat.messageSpacing": 6"#, in: directory)
        let record = LaunchRecord.inMemory()
        #expect(settings.lastError != nil)

        #expect(!ModernChatSpacingMigration.run(settings: settings, record: record, version: "1.1.0"))
        #expect(!record.hasRun(ModernChatSpacingMigration.id))

        try writeString(#"{"chat.lineSpacing": 2, "chat.messageSpacing": 6}"#, to: url)
        let fixed = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(ModernChatSpacingMigration.run(settings: fixed, record: record, version: "1.1.0"))
        #expect(fixed[.chatLineSpacing] == 4)
        #expect(fixed[.chatMessageSpacing] == 12)
    }
}
