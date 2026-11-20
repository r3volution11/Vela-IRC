// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
internal import GRDB

extension VelaDatabase {
    /// Schema migrations. Never edit a shipped migration; append a new one.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // Scrollback. `seq` is the rowid alias used by FTS and as the
            // insertion-order tie breaker for identical timestamps.
            try db.execute(sql: """
                CREATE TABLE messages (
                    seq          INTEGER PRIMARY KEY,
                    id           TEXT    NOT NULL UNIQUE,
                    network_id   TEXT    NOT NULL,
                    buffer_name  TEXT    NOT NULL,
                    msgid        TEXT,
                    time         REAL    NOT NULL,
                    kind         TEXT    NOT NULL,
                    nick         TEXT,
                    user_host    TEXT,
                    account      TEXT,
                    text         TEXT    NOT NULL,
                    is_self      INTEGER NOT NULL DEFAULT 0,
                    is_highlight INTEGER NOT NULL DEFAULT 0,
                    reply_to     TEXT,
                    tags         TEXT    NOT NULL DEFAULT '{}',
                    is_redacted  INTEGER NOT NULL DEFAULT 0
                );

                CREATE UNIQUE INDEX messages_msgid
                    ON messages (network_id, buffer_name, msgid) WHERE msgid IS NOT NULL;
                CREATE INDEX messages_buffer_time ON messages (network_id, buffer_name, time, seq);
                CREATE INDEX messages_network_time ON messages (network_id, time);

                -- External-content FTS5 index over message text.
                CREATE VIRTUAL TABLE messages_fts USING fts5(
                    text,
                    content = 'messages',
                    content_rowid = 'seq',
                    tokenize = 'unicode61 remove_diacritics 2'
                );

                CREATE TRIGGER messages_fts_insert AFTER INSERT ON messages BEGIN
                    INSERT INTO messages_fts (rowid, text) VALUES (new.seq, new.text);
                END;
                CREATE TRIGGER messages_fts_delete AFTER DELETE ON messages BEGIN
                    INSERT INTO messages_fts (messages_fts, rowid, text) VALUES ('delete', old.seq, old.text);
                END;
                CREATE TRIGGER messages_fts_update AFTER UPDATE OF text ON messages BEGIN
                    INSERT INTO messages_fts (messages_fts, rowid, text) VALUES ('delete', old.seq, old.text);
                    INSERT INTO messages_fts (rowid, text) VALUES (new.seq, new.text);
                END;

                -- +draft/react state, keyed by the target msgid (the message
                -- itself may be outside stored history).
                CREATE TABLE reactions (
                    network_id  TEXT NOT NULL,
                    buffer_name TEXT NOT NULL,
                    msgid       TEXT NOT NULL,
                    nick        TEXT NOT NULL,
                    emoji       TEXT NOT NULL,
                    time        REAL NOT NULL,
                    PRIMARY KEY (network_id, buffer_name, msgid, nick, emoji)
                ) WITHOUT ROWID;

                -- Per-buffer UI state.
                CREATE TABLE buffers (
                    network_id   TEXT    NOT NULL,
                    folded_name  TEXT    NOT NULL,
                    name         TEXT    NOT NULL,
                    kind         TEXT    NOT NULL,
                    last_read_at REAL,
                    is_pinned    INTEGER NOT NULL DEFAULT 0,
                    is_muted     INTEGER NOT NULL DEFAULT 0,
                    sort_order   INTEGER NOT NULL DEFAULT 0,
                    auto_rejoin  INTEGER NOT NULL DEFAULT 1,
                    PRIMARY KEY (network_id, folded_name)
                ) WITHOUT ROWID;

                -- Link preview cache (VelaMedia's LinkPreview as a JSON blob).
                CREATE TABLE link_previews (
                    url        TEXT NOT NULL PRIMARY KEY,
                    json       BLOB NOT NULL,
                    fetched_at REAL NOT NULL
                ) WITHOUT ROWID;
                """)
        }

        // ZNC replays its buffer on every connect without msgids, and those
        // copies used to be stored alongside the lines seen live. Keep the
        // first of each: same buffer, kind, nick and text within 3 seconds
        // (`VelaDatabase.copyWindow`).
        migrator.registerMigration("v2-remove-replayed-copies") { db in
            try db.execute(sql: """
                DELETE FROM messages
                WHERE msgid IS NULL
                  AND kind IN ('message', 'action', 'notice')
                  AND EXISTS (
                      SELECT 1 FROM messages AS earlier
                      WHERE earlier.network_id = messages.network_id
                        AND earlier.buffer_name = messages.buffer_name
                        AND earlier.time BETWEEN messages.time - 3 AND messages.time + 3
                        AND earlier.seq < messages.seq
                        AND earlier.kind = messages.kind
                        AND earlier.nick IS messages.nick
                        AND earlier.text = messages.text
                  );
                """)
        }

        // Channels detached on a bouncer, hidden from the list, or left
        // with the auto-join entry they had (`BufferRecord`).
        migrator.registerMigration("v3-detached-hidden-left-channels") { db in
            try db.execute(sql: """
                ALTER TABLE buffers ADD COLUMN is_detached INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE buffers ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE buffers ADD COLUMN left_auto_join_name TEXT;
                ALTER TABLE buffers ADD COLUMN left_auto_join_has_key INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE buffers ADD COLUMN left_auto_join_index INTEGER NOT NULL DEFAULT 0;
                """)
        }

        return migrator
    }
}
