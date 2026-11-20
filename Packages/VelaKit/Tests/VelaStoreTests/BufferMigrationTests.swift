// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SQLite3
import Testing
import VelaStore

/// Saved buffers from before Vela knew detached, hidden and left channels.
@Suite("Buffer state migration")
struct BufferMigrationTests {
    @Test func oldBufferRowsGainTheNewColumns() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VelaBuffers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vela.sqlite")
        let network = UUID()

        // A database from before: the columns dropped again, a row written
        // the old way, and the migration marked as not yet run.
        do { _ = try VelaDatabase(url: url) }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        for column in ["is_detached", "is_hidden", "left_auto_join_name", "left_auto_join_has_key", "left_auto_join_index"] {
            #expect(sqlite3_exec(db, "ALTER TABLE buffers DROP COLUMN \(column)", nil, nil, nil) == SQLITE_OK)
        }
        let insert = """
            INSERT INTO buffers (network_id, folded_name, name, kind, sort_order, auto_rejoin)
            VALUES ('\(network.uuidString)', '#vela', '#vela', 'channel', 3, 0);
            """
        #expect(sqlite3_exec(db, insert, nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "DELETE FROM grdb_migrations WHERE identifier = 'v3-detached-hidden-left-channels'", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let migrated = try VelaDatabase(url: url)
        let record = try #require(try await migrated.buffers(networkID: network).first)
        #expect(record.foldedName == "#vela")
        #expect(record.sortOrder == 3)
        #expect(!record.autoRejoin)
        #expect(!record.isDetached)
        #expect(!record.isHidden)
        #expect(record.leftAutoJoin == nil)

        var detached = record
        detached.isDetached = true
        try await migrated.upsertBuffer(detached)
        #expect(try await migrated.buffers(networkID: network) == [detached])
    }
}
