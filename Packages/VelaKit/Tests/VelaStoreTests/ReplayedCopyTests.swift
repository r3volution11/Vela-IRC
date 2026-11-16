// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SQLite3
import Testing
import VelaStore

/// ZNC replays its buffer on every connect without msgids; those copies of
/// lines already stored must not be stored again.
@Suite("Replayed copies")
struct ReplayedCopyTests {
    private let network = UUID()
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(
        _ text: String, nick: String? = "xmn", at seconds: TimeInterval, kind: String = "message",
        msgid: String? = nil, buffer: String = "#dn"
    ) -> MessageRecord {
        MessageRecord(networkID: network, bufferName: buffer, msgid: msgid, time: base.addingTimeInterval(seconds), kind: kind, nick: nick, text: text)
    }

    @Test func copiesOfStoredLinesAreSkipped() async throws {
        let database = try VelaDatabase.inMemory()
        try await database.append([line("nice", at: 0)])

        let inserted = try await database.append([
            line("nice", at: 1.5),                       // ZNC's replay: skipped
            line("nice", at: -2.9),                      // either side of it
            line("nice", at: 10),                        // said again later
            line("nice", nick: "Templarian", at: 0),     // someone else
            line("nicer", at: 0),                        // different text
            line("nice", at: 0, kind: "action"),         // different kind
            line("nice", at: 0, buffer: "#other"),       // different buffer
            line("nice", at: 0, msgid: "abc"),           // has a msgid
            line("", nick: "xmn", at: 0, kind: "join"),  // events aren't copies…
            line("", nick: "xmn", at: 1, kind: "join"),  // …even when they repeat
        ])
        #expect(inserted.map(\.text) == ["nice", "nice", "nicer", "nice", "nice", "nice", "", ""])
        #expect(try await database.messageCount() == 9)

        // Copies within one batch are caught too.
        let batch = try await database.append([line("again", at: 100), line("again", at: 100.2)])
        #expect(batch.count == 1)
    }

    @Test func migrationRemovesStoredCopies() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VelaCopies-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vela.sqlite")

        // A database from before the fix: create it, then write duplicate
        // rows directly and mark the cleanup migration as not yet run.
        do { _ = try VelaDatabase(url: url) }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        let rows: [(String?, Double, String, String?, String)] = [
            (nil, 0, "message", "xmn", "nice"),
            (nil, 0.4, "message", "xmn", "nice"),           // replay
            (nil, 0.8, "message", "xmn", "nice"),           // another replay
            (nil, 60, "message", "xmn", "nice"),            // said again later
            (nil, 0, "message", "r3volution11", "nice"),    // someone else
            ("m1", 0, "message", "xmn", "nice"),            // has a msgid
            (nil, 5, "join", "xmn", ""),
            (nil, 5.5, "join", "xmn", ""),                  // events stay
        ]
        for row in rows {
            let msgid = row.0.map { "'\($0)'" } ?? "NULL"
            let nick = row.3.map { "'\($0)'" } ?? "NULL"
            let sql = """
                INSERT INTO messages (id, network_id, buffer_name, msgid, time, kind, nick, text)
                VALUES ('\(UUID().uuidString)', '\(network.uuidString)', '#dn', \(msgid),
                        \(base.timeIntervalSince1970 + row.1), '\(row.2)', \(nick), '\(row.4)');
                """
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        #expect(sqlite3_exec(db, "DELETE FROM grdb_migrations WHERE identifier = 'v2-remove-replayed-copies'", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let migrated = try VelaDatabase(url: url)
        #expect(try await migrated.messageCount() == 6)
        let kept = try await migrated.latestMessages(in: BufferKey(networkID: network, foldedName: "#dn"), limit: 10)
        #expect(kept.map { $0.time.timeIntervalSince(base) } == [0, 0, 0, 5, 5.5, 60])
    }
}
