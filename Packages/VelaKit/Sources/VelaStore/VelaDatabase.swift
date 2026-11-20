// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
internal import GRDB

/// SQLite storage for scrollback, buffer state, reactions and the link
/// preview cache. Configuration lives in plain JSON files instead (see
/// ``NetworkConfigStore`` and ``SettingsStore``) so it can sync as files.
///
/// All methods are `async` and safe to call from any isolation domain; GRDB
/// serializes writes and runs reads concurrently (WAL mode).
///
/// Conventions: UUIDs are stored as uppercase strings, dates as `REAL`
/// seconds since 1970 (exact round-trip), booleans as 0/1.
public final class VelaDatabase: Sendable {
    private let writer: any DatabaseWriter

    /// Opens (creating if needed) the database at `url` as a WAL-mode
    /// `DatabasePool` and runs pending migrations.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.label = "VelaDatabase"
        configuration.busyMode = .timeout(5)
        writer = try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration)
        try Self.migrator.migrate(writer)
    }

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// A private in-memory database (`DatabaseQueue`), for tests and previews.
    public static func inMemory() throws -> VelaDatabase {
        var configuration = Configuration()
        configuration.label = "VelaDatabase.inMemory"
        return try VelaDatabase(writer: DatabaseQueue(configuration: configuration))
    }

    // MARK: Messages

    /// How far apart two stored copies of one message without a msgid can
    /// be stamped: a bouncer's replay of a line seen live carries the
    /// bouncer's timestamp.
    public static let copyWindow: TimeInterval = 3

    /// Inserts messages, skipping any whose `msgid` already exists in the
    /// same buffer (or whose `id` already exists), and copies of stored
    /// lines without a msgid: the same kind, nick and text in the same
    /// buffer within `copyWindow` (ZNC replays its buffer on every connect
    /// without msgids). Returns the records that were actually inserted,
    /// in input order.
    @discardableResult
    public func append(_ messages: [MessageRecord]) async throws -> [MessageRecord] {
        guard !messages.isEmpty else { return [] }
        return try await writer.write { db in
            let statement = try db.cachedStatement(sql: Self.insertMessageSQL)
            let copyStatement = try db.cachedStatement(sql: Self.storedCopySQL)
            var inserted: [MessageRecord] = []
            inserted.reserveCapacity(messages.count)
            for message in messages {
                if message.msgid == nil, Self.copyKinds.contains(message.kind) {
                    let time = message.time.timeIntervalSince1970
                    let arguments: StatementArguments = [
                        message.networkID.uuidString, message.bufferName,
                        time - Self.copyWindow, time + Self.copyWindow,
                        message.kind, message.nick, message.text,
                    ]
                    if try Bool.fetchOne(copyStatement, arguments: arguments) == true { continue }
                }
                try statement.execute(arguments: Self.arguments(for: message))
                if db.changesCount > 0 {
                    inserted.append(message)
                }
            }
            return inserted
        }
    }

    /// The newest `limit` messages of a buffer, in ascending time order.
    public func latestMessages(in buffer: BufferKey, limit: Int) async throws -> [MessageRecord] {
        try await fetchMessages(
            sql: """
                SELECT \(Self.messageColumns) FROM messages
                WHERE network_id = ? AND buffer_name = ?
                ORDER BY time DESC, seq DESC LIMIT ?
                """,
            arguments: [buffer.networkID.uuidString, buffer.foldedName, limit],
            reverse: true
        )
    }

    /// Up to `limit` messages strictly older than `before`, in ascending
    /// time order (for "load earlier" paging).
    public func messages(in buffer: BufferKey, before: Date, limit: Int) async throws -> [MessageRecord] {
        try await fetchMessages(
            sql: """
                SELECT \(Self.messageColumns) FROM messages
                WHERE network_id = ? AND buffer_name = ? AND time < ?
                ORDER BY time DESC, seq DESC LIMIT ?
                """,
            arguments: [buffer.networkID.uuidString, buffer.foldedName, before.timeIntervalSince1970, limit],
            reverse: true
        )
    }

    /// Up to `limit` messages that sort before the message with `id`
    /// (by time, then insertion order), ascending. Unlike the `Date`
    /// variant this never skips messages sharing the boundary timestamp.
    /// Returns an empty array if `id` is unknown.
    public func messages(in buffer: BufferKey, olderThan id: UUID, limit: Int) async throws -> [MessageRecord] {
        try await fetchMessages(
            sql: """
                SELECT \(Self.messageColumns) FROM messages
                WHERE network_id = ? AND buffer_name = ?
                  AND (time, seq) < (SELECT time, seq FROM messages WHERE id = ?)
                ORDER BY time DESC, seq DESC LIMIT ?
                """,
            arguments: [buffer.networkID.uuidString, buffer.foldedName, id.uuidString, limit],
            reverse: true
        )
    }

    /// Up to `limit` messages strictly newer than `after`, ascending.
    public func messages(in buffer: BufferKey, after: Date, limit: Int) async throws -> [MessageRecord] {
        try await fetchMessages(
            sql: """
                SELECT \(Self.messageColumns) FROM messages
                WHERE network_id = ? AND buffer_name = ? AND time > ?
                ORDER BY time ASC, seq ASC LIMIT ?
                """,
            arguments: [buffer.networkID.uuidString, buffer.foldedName, after.timeIntervalSince1970, limit],
            reverse: false
        )
    }

    /// The message with the given IRCv3 `msgid` in a buffer (e.g. to render
    /// reply context), if stored.
    public func message(msgid: String, in buffer: BufferKey) async throws -> MessageRecord? {
        try await fetchMessages(
            sql: """
                SELECT \(Self.messageColumns) FROM messages
                WHERE network_id = ? AND buffer_name = ? AND msgid = ?
                LIMIT 1
                """,
            arguments: [buffer.networkID.uuidString, buffer.foldedName, msgid],
            reverse: false
        ).first
    }

    public func newestMessageTime(in buffer: BufferKey) async throws -> Date? {
        try await writer.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT MAX(time) FROM messages WHERE network_id = ? AND buffer_name = ?",
                arguments: [buffer.networkID.uuidString, buffer.foldedName]
            ).map(Date.init(timeIntervalSince1970:))
        }
    }

    /// The newest message time across all of a network's buffers (the
    /// `CHATHISTORY` catch-up point after reconnecting).
    public func newestMessageTime(networkID: UUID) async throws -> Date? {
        try await writer.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT MAX(time) FROM messages WHERE network_id = ?",
                arguments: [networkID.uuidString]
            ).map(Date.init(timeIntervalSince1970:))
        }
    }

    /// Flags a message as redacted. The text is kept (the UI decides whether
    /// to reveal it) but redacted messages are excluded from search.
    public func markRedacted(msgid: String, in buffer: BufferKey) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE messages SET is_redacted = 1 WHERE network_id = ? AND buffer_name = ? AND msgid = ?",
                arguments: [buffer.networkID.uuidString, buffer.foldedName, msgid]
            )
        }
    }

    // MARK: Reactions

    /// Adds (`active == true`) or removes a reaction. Adding is idempotent.
    public func setReaction(_ reaction: ReactionRecord, in buffer: BufferKey, active: Bool) async throws {
        try await writer.write { db in
            if active {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO reactions (network_id, buffer_name, msgid, nick, emoji, time)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        buffer.networkID.uuidString, buffer.foldedName, reaction.msgid,
                        reaction.nick, reaction.emoji, Date().timeIntervalSince1970,
                    ]
                )
            } else {
                try db.execute(
                    sql: """
                        DELETE FROM reactions
                        WHERE network_id = ? AND buffer_name = ? AND msgid = ? AND nick = ? AND emoji = ?
                        """,
                    arguments: [
                        buffer.networkID.uuidString, buffer.foldedName, reaction.msgid,
                        reaction.nick, reaction.emoji,
                    ]
                )
            }
        }
    }

    /// Reactions to any of `msgids`, oldest first.
    public func reactions(in buffer: BufferKey, msgids: [String]) async throws -> [ReactionRecord] {
        let unique = Array(Set(msgids))
        guard !unique.isEmpty else { return [] }
        return try await writer.read { db in
            var timed: [(record: ReactionRecord, time: Double)] = []
            // Stay well below SQLite's bound-parameter limit.
            for start in stride(from: 0, to: unique.count, by: 500) {
                let chunk = Array(unique[start..<min(start + 500, unique.count)])
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                var arguments: StatementArguments = [buffer.networkID.uuidString, buffer.foldedName]
                arguments += StatementArguments(chunk)
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT msgid, nick, emoji, time FROM reactions
                        WHERE network_id = ? AND buffer_name = ? AND msgid IN (\(placeholders))
                        """,
                    arguments: arguments
                )
                for row in rows {
                    let record = ReactionRecord(msgid: row["msgid"], nick: row["nick"], emoji: row["emoji"])
                    timed.append((record, row["time"]))
                }
            }
            return timed
                .sorted { lhs, rhs in
                    if lhs.time != rhs.time { return lhs.time < rhs.time }
                    return (lhs.record.msgid, lhs.record.nick, lhs.record.emoji)
                        < (rhs.record.msgid, rhs.record.nick, rhs.record.emoji)
                }
                .map(\.record)
        }
    }

    // MARK: Search

    /// Full-text search (FTS5, `unicode61 remove_diacritics 2`) over message
    /// text, newest first. Every whitespace-separated word of `query` must
    /// match (as a prefix); FTS syntax characters are treated literally.
    /// Redacted messages are excluded.
    public func search(_ query: String, networkID: UUID?, limit: Int) async throws -> [MessageRecord] {
        try await search(query, networkID: networkID, bufferName: nil, limit: limit)
    }

    /// Full-text search restricted to one buffer, newest first.
    public func search(_ query: String, in buffer: BufferKey, limit: Int) async throws -> [MessageRecord] {
        try await search(query, networkID: buffer.networkID, bufferName: buffer.foldedName, limit: limit)
    }

    private func search(
        _ query: String,
        networkID: UUID?,
        bufferName: String?,
        limit: Int
    ) async throws -> [MessageRecord] {
        guard let pattern = Self.ftsPattern(for: query), limit > 0 else { return [] }
        var sql = """
            SELECT \(Self.messageColumns(prefix: "m.")) FROM messages_fts
            JOIN messages m ON m.seq = messages_fts.rowid
            WHERE messages_fts MATCH ? AND m.is_redacted = 0
            """
        var arguments: StatementArguments = [pattern]
        if let networkID {
            sql += " AND m.network_id = ?"
            arguments += [networkID.uuidString]
        }
        if let bufferName {
            sql += " AND m.buffer_name = ?"
            arguments += [bufferName]
        }
        sql += " ORDER BY m.time DESC, m.seq DESC LIMIT ?"
        arguments += [limit]
        return try await fetchMessages(sql: sql, arguments: arguments, reverse: false)
    }

    /// Turns free text into a safe FTS5 query: each word becomes a quoted
    /// prefix phrase, all of which must match.
    static func ftsPattern(for query: String) -> String? {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
        return terms.isEmpty ? nil : terms.joined(separator: " ")
    }

    // MARK: Buffers

    /// Saved buffers of a network, ordered by `sortOrder` then name.
    public func buffers(networkID: UUID) async throws -> [BufferRecord] {
        try await writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT network_id, folded_name, name, kind, last_read_at, is_pinned, is_muted, sort_order,
                           auto_rejoin, is_detached, is_hidden,
                           left_auto_join_name, left_auto_join_has_key, left_auto_join_index
                    FROM buffers WHERE network_id = ?
                    ORDER BY sort_order, folded_name
                    """,
                arguments: [networkID.uuidString]
            ).compactMap(Self.buffer(from:))
        }
    }

    public func upsertBuffer(_ buffer: BufferRecord) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO buffers
                        (network_id, folded_name, name, kind, last_read_at, is_pinned, is_muted, sort_order,
                         auto_rejoin, is_detached, is_hidden,
                         left_auto_join_name, left_auto_join_has_key, left_auto_join_index)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (network_id, folded_name) DO UPDATE SET
                        name = excluded.name,
                        kind = excluded.kind,
                        last_read_at = excluded.last_read_at,
                        is_pinned = excluded.is_pinned,
                        is_muted = excluded.is_muted,
                        sort_order = excluded.sort_order,
                        auto_rejoin = excluded.auto_rejoin,
                        is_detached = excluded.is_detached,
                        is_hidden = excluded.is_hidden,
                        left_auto_join_name = excluded.left_auto_join_name,
                        left_auto_join_has_key = excluded.left_auto_join_has_key,
                        left_auto_join_index = excluded.left_auto_join_index
                    """,
                arguments: [
                    buffer.networkID.uuidString, buffer.foldedName, buffer.name, buffer.kind,
                    buffer.lastReadAt?.timeIntervalSince1970, buffer.isPinned, buffer.isMuted, buffer.sortOrder,
                    buffer.autoRejoin, buffer.isDetached, buffer.isHidden,
                    buffer.leftAutoJoin?.entry.name, buffer.leftAutoJoin?.entry.hasKey ?? false,
                    buffer.leftAutoJoin?.index ?? 0,
                ]
            )
        }
    }

    /// Removes a buffer's saved state (closing it in the UI). By default its
    /// message history (and the reactions on it) is kept as a log; with
    /// `keepMessages: false` messages and reactions are deleted too.
    public func deleteBuffer(_ buffer: BufferKey, keepMessages: Bool = true) async throws {
        try await writer.write { db in
            let arguments: StatementArguments = [buffer.networkID.uuidString, buffer.foldedName]
            if !keepMessages {
                try db.execute(sql: "DELETE FROM messages WHERE network_id = ? AND buffer_name = ?", arguments: arguments)
                try db.execute(sql: "DELETE FROM reactions WHERE network_id = ? AND buffer_name = ?", arguments: arguments)
            }
            try db.execute(sql: "DELETE FROM buffers WHERE network_id = ? AND folded_name = ?", arguments: arguments)
        }
    }

    /// Deletes everything stored for a network: buffers, messages, reactions.
    public func deleteNetwork(_ networkID: UUID) async throws {
        try await writer.write { db in
            let arguments: StatementArguments = [networkID.uuidString]
            try db.execute(sql: "DELETE FROM messages WHERE network_id = ?", arguments: arguments)
            try db.execute(sql: "DELETE FROM reactions WHERE network_id = ?", arguments: arguments)
            try db.execute(sql: "DELETE FROM buffers WHERE network_id = ?", arguments: arguments)
        }
    }

    // MARK: Link previews

    /// The cached preview blob for `url` (VelaMedia's `LinkPreview` as JSON).
    public func cachedPreviewJSON(url: String) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(db, sql: "SELECT json FROM link_previews WHERE url = ?", arguments: [url])
        }
    }

    public func storePreviewJSON(_ data: Data, url: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO link_previews (url, json, fetched_at) VALUES (?, ?, ?)
                    ON CONFLICT (url) DO UPDATE SET json = excluded.json, fetched_at = excluded.fetched_at
                    """,
                arguments: [url, data, Date().timeIntervalSince1970]
            )
        }
    }

    /// Drops cached previews fetched before `date`.
    public func prunePreviews(olderThan date: Date) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM link_previews WHERE fetched_at < ?",
                arguments: [date.timeIntervalSince1970]
            )
        }
    }

    // MARK: Maintenance

    /// Deletes messages older than `date` (history retention), plus
    /// reactions that no longer point at a stored message and were
    /// recorded before `date`.
    public func pruneMessages(olderThan date: Date) async throws {
        try await writer.write { db in
            let cutoff = date.timeIntervalSince1970
            try db.execute(sql: "DELETE FROM messages WHERE time < ?", arguments: [cutoff])
            try db.execute(
                sql: """
                    DELETE FROM reactions WHERE time < ? AND NOT EXISTS (
                        SELECT 1 FROM messages m
                        WHERE m.network_id = reactions.network_id
                          AND m.buffer_name = reactions.buffer_name
                          AND m.msgid = reactions.msgid
                    )
                    """,
                arguments: [cutoff]
            )
        }
    }

    /// Total number of stored messages (diagnostics, tests).
    public func messageCount() async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages") ?? 0
        }
    }

    // MARK: Row mapping

    private static let messageColumnNames = [
        "id", "network_id", "buffer_name", "msgid", "time", "kind", "nick", "user_host", "account",
        "text", "is_self", "is_highlight", "reply_to", "tags", "is_redacted",
    ]

    private static let messageColumns = messageColumns(prefix: "")

    private static func messageColumns(prefix: String) -> String {
        messageColumnNames.map { prefix + $0 }.joined(separator: ", ")
    }

    /// Kinds of lines that can be replayed copies (what people say).
    private static let copyKinds: Set<String> = ["message", "action", "notice"]

    private static let storedCopySQL = """
        SELECT EXISTS (
            SELECT 1 FROM messages
            WHERE network_id = ? AND buffer_name = ? AND time BETWEEN ? AND ?
              AND kind = ? AND nick IS ? AND text = ?
        )
        """

    private static let insertMessageSQL = """
        INSERT OR IGNORE INTO messages (\(messageColumns))
        VALUES (\(Array(repeating: "?", count: messageColumnNames.count).joined(separator: ", ")))
        """

    private static func arguments(for message: MessageRecord) -> StatementArguments {
        [
            message.id.uuidString,
            message.networkID.uuidString,
            message.bufferName,
            message.msgid,
            message.time.timeIntervalSince1970,
            message.kind,
            message.nick,
            message.userHost,
            message.account,
            message.text,
            message.isSelf,
            message.isHighlight,
            message.replyTo,
            encodeTags(message.tags),
            message.isRedacted,
        ]
    }

    private func fetchMessages(
        sql: String,
        arguments: StatementArguments,
        reverse: Bool
    ) async throws -> [MessageRecord] {
        let records = try await writer.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap(Self.message(from:))
        }
        return reverse ? records.reversed() : records
    }

    private static func message(from row: Row) -> MessageRecord? {
        guard let id = UUID(uuidString: row["id"]),
              let networkID = UUID(uuidString: row["network_id"])
        else { return nil }
        return MessageRecord(
            id: id,
            networkID: networkID,
            bufferName: row["buffer_name"],
            msgid: row["msgid"],
            time: Date(timeIntervalSince1970: row["time"]),
            kind: row["kind"],
            nick: row["nick"],
            userHost: row["user_host"],
            account: row["account"],
            text: row["text"],
            isSelf: row["is_self"],
            isHighlight: row["is_highlight"],
            replyTo: row["reply_to"],
            tags: decodeTags(row["tags"]),
            isRedacted: row["is_redacted"]
        )
    }

    private static func buffer(from row: Row) -> BufferRecord? {
        guard let networkID = UUID(uuidString: row["network_id"]) else { return nil }
        let lastRead: Double? = row["last_read_at"]
        let leftName: String? = row["left_auto_join_name"]
        let leftAutoJoin = leftName.map { name in
            LeftAutoJoin(
                entry: AutoJoinChannel(name: name, hasKey: row["left_auto_join_has_key"]),
                index: row["left_auto_join_index"]
            )
        }
        return BufferRecord(
            networkID: networkID,
            name: row["name"],
            foldedName: row["folded_name"],
            kind: row["kind"],
            lastReadAt: lastRead.map(Date.init(timeIntervalSince1970:)),
            isPinned: row["is_pinned"],
            isMuted: row["is_muted"],
            sortOrder: row["sort_order"],
            autoRejoin: row["auto_rejoin"],
            isDetached: row["is_detached"],
            isHidden: row["is_hidden"],
            leftAutoJoin: leftAutoJoin
        )
    }

    private static func encodeTags(_ tags: [String: String]) -> String {
        guard !tags.isEmpty else { return "{}" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(tags) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeTags(_ string: String?) -> [String: String] {
        guard let string, string != "{}", !string.isEmpty else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: Data(string.utf8))) ?? [:]
    }
}
