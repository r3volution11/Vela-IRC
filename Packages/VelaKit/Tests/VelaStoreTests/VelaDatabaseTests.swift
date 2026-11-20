// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaStore

@Suite struct VelaDatabaseTests {
    let network = UUID()
    let base = Date(timeIntervalSince1970: 1_700_000_000.123_456)

    var channel: BufferKey { BufferKey(networkID: network, foldedName: "#vela") }
    var query: BufferKey { BufferKey(networkID: network, foldedName: "alice") }

    private func message(
        _ text: String,
        at offset: TimeInterval,
        in buffer: BufferKey? = nil,
        msgid: String? = nil,
        nick: String = "alice"
    ) -> MessageRecord {
        let buffer = buffer ?? channel
        return MessageRecord(
            networkID: buffer.networkID,
            bufferName: buffer.foldedName,
            msgid: msgid,
            time: base.addingTimeInterval(offset),
            kind: "privmsg",
            nick: nick,
            text: text
        )
    }

    @Test func appendRoundTripsEveryField() async throws {
        let db = try VelaDatabase.inMemory()
        let original = MessageRecord(
            networkID: network,
            bufferName: "#vela",
            msgid: "abc123",
            time: base,
            kind: "action",
            nick: "alice",
            userHost: "alice@example.org",
            account: "alice",
            text: "waves 👋",
            isSelf: true,
            isHighlight: true,
            replyTo: "parent-msgid",
            tags: ["+draft/channel-context": "#vela", "label": "x/y"],
            isRedacted: false
        )
        let inserted = try await db.append([original])
        #expect(inserted == [original])
        let stored = try await db.latestMessages(in: channel, limit: 10)
        #expect(stored == [original])
        #expect(try await db.message(msgid: "abc123", in: channel) == original)
        #expect(try await db.message(msgid: "nope", in: channel) == nil)
    }

    @Test func appendDeduplicatesByMsgid() async throws {
        let db = try VelaDatabase.inMemory()
        let first = message("hello", at: 0, msgid: "m1")
        try await db.append([first])

        // Same msgid again (e.g. CHATHISTORY replay) with a new local UUID.
        let replay = message("hello", at: 0, msgid: "m1")
        let inserted = try await db.append([replay, message("world", at: 1, msgid: "m2")])
        #expect(inserted.map(\.msgid) == ["m2"])

        // Same msgid in a different buffer is a different message.
        try await db.append([message("hi", at: 2, in: query, msgid: "m1")])

        // No msgid: never de-duplicated by content; same UUID is ignored.
        let plain = message("plain", at: 3)
        try await db.append([plain, message("plain", at: 3)])
        try await db.append([plain])

        let channelMessages = try await db.latestMessages(in: channel, limit: 100)
        #expect(channelMessages.map(\.text) == ["hello", "world", "plain", "plain"])
        #expect(channelMessages.first?.id == first.id)
        #expect(try await db.latestMessages(in: query, limit: 100).count == 1)
        #expect(try await db.messageCount() == 5)
    }

    @Test func pagingReturnsAscendingOrder() async throws {
        let db = try VelaDatabase.inMemory()
        let messages = (0..<10).map { message("m\($0)", at: TimeInterval($0)) }
        try await db.append(messages.shuffled())

        let latest = try await db.latestMessages(in: channel, limit: 3)
        #expect(latest.map(\.text) == ["m7", "m8", "m9"])

        let earlier = try await db.messages(in: channel, before: latest[0].time, limit: 3)
        #expect(earlier.map(\.text) == ["m4", "m5", "m6"])

        let earliest = try await db.messages(in: channel, before: earlier[0].time, limit: 10)
        #expect(earliest.map(\.text) == ["m0", "m1", "m2", "m3"])

        let after = try await db.messages(in: channel, after: messages[5].time, limit: 2)
        #expect(after.map(\.text) == ["m6", "m7"])

        #expect(try await db.latestMessages(in: query, limit: 10).isEmpty)
    }

    @Test func idCursorHandlesIdenticalTimestamps() async throws {
        let db = try VelaDatabase.inMemory()
        // A batch where every message shares one timestamp.
        let batch = (0..<5).map { message("same\($0)", at: 0) }
        try await db.append(batch)
        try await db.append([message("later", at: 1)])

        let latest = try await db.latestMessages(in: channel, limit: 3)
        #expect(latest.map(\.text) == ["same3", "same4", "later"])

        let older = try await db.messages(in: channel, olderThan: latest[0].id, limit: 10)
        #expect(older.map(\.text) == ["same0", "same1", "same2"])

        #expect(try await db.messages(in: channel, olderThan: UUID(), limit: 10).isEmpty)
    }

    @Test func newestMessageTimes() async throws {
        let db = try VelaDatabase.inMemory()
        #expect(try await db.newestMessageTime(in: channel) == nil)
        #expect(try await db.newestMessageTime(networkID: network) == nil)

        try await db.append([message("a", at: 5), message("b", at: 9, in: query), message("c", at: 2)])
        #expect(try await db.newestMessageTime(in: channel) == base.addingTimeInterval(5))
        #expect(try await db.newestMessageTime(in: query) == base.addingTimeInterval(9))
        #expect(try await db.newestMessageTime(networkID: network) == base.addingTimeInterval(9))
        #expect(try await db.newestMessageTime(networkID: UUID()) == nil)
    }

    @Test func redaction() async throws {
        let db = try VelaDatabase.inMemory()
        try await db.append([message("secret plans", at: 0, msgid: "r1"), message("public plans", at: 1, msgid: "r2")])
        #expect(try await db.search("plans", networkID: network, limit: 10).count == 2)

        try await db.markRedacted(msgid: "r1", in: channel)
        let stored = try await db.latestMessages(in: channel, limit: 10)
        #expect(stored.map(\.isRedacted) == [true, false])
        #expect(try await db.search("plans", networkID: network, limit: 10).map(\.msgid) == ["r2"])

        // Unknown msgid / other buffer: no effect.
        try await db.markRedacted(msgid: "r2", in: query)
        #expect(try await db.message(msgid: "r2", in: channel)?.isRedacted == false)
    }

    @Test func reactionsAddAndRemove() async throws {
        let db = try VelaDatabase.inMemory()
        let thumbs = ReactionRecord(msgid: "m1", nick: "bob", emoji: "👍")
        let heart = ReactionRecord(msgid: "m1", nick: "carol", emoji: "❤️")
        let other = ReactionRecord(msgid: "m2", nick: "bob", emoji: "🎉")

        try await db.setReaction(thumbs, in: channel, active: true)
        try await db.setReaction(thumbs, in: channel, active: true)  // idempotent
        try await db.setReaction(heart, in: channel, active: true)
        try await db.setReaction(other, in: channel, active: true)
        try await db.setReaction(thumbs, in: query, active: true)

        let m1 = try await db.reactions(in: channel, msgids: ["m1"])
        #expect(Set(m1) == [thumbs, heart])
        #expect(m1.count == 2)
        #expect(Set(try await db.reactions(in: channel, msgids: ["m1", "m2", "unknown"])) == [thumbs, heart, other])
        #expect(try await db.reactions(in: channel, msgids: []).isEmpty)

        try await db.setReaction(thumbs, in: channel, active: false)
        #expect(try await db.reactions(in: channel, msgids: ["m1"]) == [heart])
        #expect(try await db.reactions(in: query, msgids: ["m1"]) == [thumbs])
    }

    @Test func fullTextSearch() async throws {
        let db = try VelaDatabase.inMemory()
        let otherNetwork = BufferKey(networkID: UUID(), foldedName: "#vela")
        try await db.append([
            message("Meet me at the café tomorrow", at: 0),
            message("Crème brûlée is great", at: 1),
            message("The cafeteria is closed", at: 2, in: query),
            message("café on another network", at: 3, in: otherNetwork),
            message("nothing relevant", at: 4),
        ])

        // Diacritics are folded in both directions; results are newest first.
        let cafe = try await db.search("cafe", networkID: network, limit: 10)
        #expect(cafe.map(\.text) == ["The cafeteria is closed", "Meet me at the café tomorrow"])
        let accented = try await db.search("CAFÉ", networkID: network, limit: 10)
        #expect(accented.map(\.text) == cafe.map(\.text))
        #expect(try await db.search("creme brulee", networkID: network, limit: 10).count == 1)

        // All networks.
        #expect(try await db.search("café", networkID: nil, limit: 10).count == 3)
        #expect(try await db.search("café", networkID: nil, limit: 1).count == 1)

        // One buffer.
        #expect(try await db.search("caf", in: channel, limit: 10).map(\.text) == ["Meet me at the café tomorrow"])

        // FTS syntax is treated literally and never throws.
        #expect(try await db.search("\"café AND OR NOT ( * :", networkID: network, limit: 10).isEmpty)
        #expect(try await db.search("   ", networkID: nil, limit: 10).isEmpty)
        #expect(try await db.search("-", networkID: nil, limit: 10).isEmpty)
        #expect(try await db.search("brûlée\"", networkID: nil, limit: 10).count == 1)
    }

    @Test func buffersUpsertAndDelete() async throws {
        let db = try VelaDatabase.inMemory()
        var vela = BufferRecord(networkID: network, name: "#Vela", foldedName: "#vela", kind: "channel", sortOrder: 1)
        let alice = BufferRecord(networkID: network, name: "Alice", foldedName: "alice", kind: "query", sortOrder: 2)
        let server = BufferRecord(networkID: network, name: "Libera", foldedName: "", kind: "server", sortOrder: 0)
        #expect(vela.autoRejoin)
        try await db.upsertBuffer(vela)
        try await db.upsertBuffer(alice)
        try await db.upsertBuffer(server)
        #expect(try await db.buffers(networkID: network).map(\.foldedName) == ["", "#vela", "alice"])
        #expect(try await db.buffers(networkID: UUID()).isEmpty)

        vela.lastReadAt = base
        vela.isPinned = true
        vela.isMuted = true
        vela.name = "#VELA"
        vela.autoRejoin = false  // user /parted
        try await db.upsertBuffer(vela)
        let reloaded = try await db.buffers(networkID: network)
        #expect(reloaded.count == 3)
        #expect(reloaded.first { $0.foldedName == "#vela" } == vela)
        #expect(reloaded.first { $0.foldedName == "alice" }?.autoRejoin == true)
    }

    @Test func deleteBufferKeepsHistoryByDefault() async throws {
        let db = try VelaDatabase.inMemory()
        try await db.upsertBuffer(BufferRecord(networkID: network, name: "#vela", foldedName: "#vela", kind: "channel"))
        try await db.upsertBuffer(BufferRecord(networkID: network, name: "alice", foldedName: "alice", kind: "query"))
        try await db.append([message("in channel", at: 0, msgid: "c1"), message("in query", at: 1, in: query)])
        let reaction = ReactionRecord(msgid: "c1", nick: "bob", emoji: "👍")
        try await db.setReaction(reaction, in: channel, active: true)

        // Closing the buffer keeps its log.
        try await db.deleteBuffer(channel)
        #expect(try await db.buffers(networkID: network).map(\.foldedName) == ["alice"])
        #expect(try await db.latestMessages(in: channel, limit: 10).map(\.text) == ["in channel"])
        #expect(try await db.reactions(in: channel, msgids: ["c1"]) == [reaction])
        #expect(try await db.search("channel", networkID: nil, limit: 10).count == 1)

        // Explicitly discarding history cascades to messages, reactions, FTS.
        try await db.deleteBuffer(channel, keepMessages: false)
        #expect(try await db.latestMessages(in: channel, limit: 10).isEmpty)
        #expect(try await db.reactions(in: channel, msgids: ["c1"]).isEmpty)
        #expect(try await db.search("channel", networkID: nil, limit: 10).isEmpty)
        #expect(try await db.latestMessages(in: query, limit: 10).count == 1)

        try await db.deleteBuffer(query, keepMessages: false)
        #expect(try await db.buffers(networkID: network).isEmpty)
        #expect(try await db.messageCount() == 0)
    }

    @Test func deleteNetworkRemovesEverything() async throws {
        let db = try VelaDatabase.inMemory()
        let otherNetwork = BufferKey(networkID: UUID(), foldedName: "#vela")
        try await db.upsertBuffer(BufferRecord(networkID: network, name: "#vela", foldedName: "#vela", kind: "channel"))
        try await db.append([
            message("one", at: 0, msgid: "x1"),
            message("two", at: 1, in: query),
            message("three", at: 2, in: otherNetwork),
        ])
        try await db.setReaction(ReactionRecord(msgid: "x1", nick: "bob", emoji: "👍"), in: channel, active: true)

        try await db.deleteNetwork(network)
        #expect(try await db.buffers(networkID: network).isEmpty)
        #expect(try await db.latestMessages(in: channel, limit: 10).isEmpty)
        #expect(try await db.latestMessages(in: query, limit: 10).isEmpty)
        #expect(try await db.reactions(in: channel, msgids: ["x1"]).isEmpty)
        #expect(try await db.search("one two", networkID: nil, limit: 10).isEmpty)
        #expect(try await db.latestMessages(in: otherNetwork, limit: 10).map(\.text) == ["three"])
        #expect(try await db.messageCount() == 1)
    }

    /// Detached, hidden and left channels keep that across a relaunch.
    @Test func detachedHiddenAndLeftChannels() async throws {
        let db = try VelaDatabase.inMemory()
        let detached = BufferRecord(networkID: network, name: "#quiet", foldedName: "#quiet", kind: "channel", sortOrder: 0, isDetached: true)
        let hidden = BufferRecord(networkID: network, name: "#busy", foldedName: "#busy", kind: "channel", sortOrder: 1, isDetached: true, isHidden: true)
        let left = BufferRecord(
            networkID: network, name: "#Secret", foldedName: "#secret", kind: "channel", sortOrder: 2, autoRejoin: false,
            leftAutoJoin: LeftAutoJoin(entry: AutoJoinChannel(name: "#Secret", hasKey: true), index: 3)
        )
        for record in [detached, hidden, left] { try await db.upsertBuffer(record) }
        #expect(try await db.buffers(networkID: network) == [detached, hidden, left])

        // Joined again: all three cleared.
        var rejoined = left
        rejoined.leftAutoJoin = nil
        rejoined.autoRejoin = true
        try await db.upsertBuffer(rejoined)
        var shown = hidden
        shown.isHidden = false
        try await db.upsertBuffer(shown)
        let reloaded = try await db.buffers(networkID: network)
        #expect(reloaded.first { $0.foldedName == "#secret" }?.leftAutoJoin == nil)
        #expect(reloaded.first { $0.foldedName == "#busy" }?.isHidden == false)
        #expect(reloaded.first { $0.foldedName == "#busy" }?.isDetached == true)
    }

    @Test func bufferRecordDecodingToleratesMissingKeys() throws {
        let id = UUID()
        let json = ##"{"networkID": "\##(id.uuidString)", "foldedName": "#vela", "name": "#Vela", "kind": "channel"}"##
        let record = try JSONDecoder().decode(BufferRecord.self, from: Data(json.utf8))
        #expect(record.autoRejoin)
        #expect(!record.isPinned)
        #expect(record.sortOrder == 0)
        #expect(record.lastReadAt == nil)
        #expect(!record.isDetached)
        #expect(!record.isHidden)
        #expect(record.leftAutoJoin == nil)

        var parted = record
        parted.autoRejoin = false
        parted.isDetached = true
        parted.leftAutoJoin = LeftAutoJoin(entry: AutoJoinChannel(name: "#Vela"), index: 2)
        let roundTripped = try JSONDecoder().decode(BufferRecord.self, from: JSONEncoder().encode(parted))
        #expect(roundTripped == parted)
    }

    @Test func previewCache() async throws {
        let db = try VelaDatabase.inMemory()
        let url = "https://example.com/article"
        #expect(try await db.cachedPreviewJSON(url: url) == nil)

        try await db.storePreviewJSON(Data(#"{"title":"One"}"#.utf8), url: url)
        #expect(try await db.cachedPreviewJSON(url: url) == Data(#"{"title":"One"}"#.utf8))

        try await db.storePreviewJSON(Data(#"{"title":"Two"}"#.utf8), url: url)
        #expect(try await db.cachedPreviewJSON(url: url) == Data(#"{"title":"Two"}"#.utf8))

        try await db.prunePreviews(olderThan: Date().addingTimeInterval(-60))
        #expect(try await db.cachedPreviewJSON(url: url) != nil)
        try await db.prunePreviews(olderThan: Date().addingTimeInterval(60))
        #expect(try await db.cachedPreviewJSON(url: url) == nil)
    }

    @Test func pruneMessages() async throws {
        let db = try VelaDatabase.inMemory()
        try await db.append([
            message("old", at: 0, msgid: "old"),
            message("older", at: -100, in: query),
            message("new", at: 1000, msgid: "new"),
        ])
        try await db.setReaction(ReactionRecord(msgid: "old", nick: "bob", emoji: "👍"), in: channel, active: true)
        try await db.setReaction(ReactionRecord(msgid: "new", nick: "bob", emoji: "👍"), in: channel, active: true)

        try await db.pruneMessages(olderThan: base.addingTimeInterval(500))
        #expect(try await db.latestMessages(in: channel, limit: 10).map(\.text) == ["new"])
        #expect(try await db.latestMessages(in: query, limit: 10).isEmpty)
        #expect(try await db.search("old", networkID: nil, limit: 10).isEmpty)
        // Reactions recorded after the cutoff survive even when orphaned...
        #expect(Set(try await db.reactions(in: channel, msgids: ["old", "new"]).map(\.msgid)) == ["old", "new"])
        // ...until a prune whose cutoff passes them (both messages go too).
        try await db.pruneMessages(olderThan: Date().addingTimeInterval(60))
        #expect(try await db.messageCount() == 0)
        #expect(try await db.reactions(in: channel, msgids: ["old", "new"]).isEmpty)
    }

    @Test func orphanedReactionsArePrunedButLiveOnesKept() async throws {
        let db = try VelaDatabase.inMemory()
        let future = Date().addingTimeInterval(365 * 86_400)
        let keep = MessageRecord(
            networkID: network, bufferName: "#vela", msgid: "keep", time: future, kind: "privmsg", text: "future"
        )
        try await db.append([keep, message("gone", at: 0, msgid: "gone")])
        try await db.setReaction(ReactionRecord(msgid: "keep", nick: "bob", emoji: "👍"), in: channel, active: true)
        try await db.setReaction(ReactionRecord(msgid: "gone", nick: "bob", emoji: "👍"), in: channel, active: true)

        try await db.pruneMessages(olderThan: Date().addingTimeInterval(60))
        #expect(try await db.reactions(in: channel, msgids: ["keep", "gone"]).map(\.msgid) == ["keep"])
    }

    @Test func fileBackedDatabaseReopens() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.url.appending(path: "nested/vela.sqlite")
        do {
            let db = try VelaDatabase(url: url)
            try await db.append([message("persisted café", at: 0, msgid: "p1")])
            try await db.upsertBuffer(BufferRecord(networkID: network, name: "#vela", foldedName: "#vela", kind: "channel"))
        }
        let reopened = try VelaDatabase(url: url)
        #expect(try await reopened.latestMessages(in: channel, limit: 10).map(\.text) == ["persisted café"])
        #expect(try await reopened.search("cafe", networkID: network, limit: 10).count == 1)
        #expect(try await reopened.buffers(networkID: network).count == 1)
    }

    @Test func ftsPatternQuotesTerms() {
        #expect(VelaDatabase.ftsPattern(for: "hello world") == #""hello"* "world"*"#)
        #expect(VelaDatabase.ftsPattern(for: #"say "hi""#) == #""say"* """hi"""*"#)
        #expect(VelaDatabase.ftsPattern(for: " - * ") == nil)
    }
}
