// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

/// History a bouncer replays (ZNC's playback, chathistory) counts as unread
/// when it's newer than where you last read, so badges, the New line and
/// Catch me up show what you missed. It never notifies.
@MainActor
@Suite("Replayed history and unread counts")
struct ReplayedUnreadTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeSession(database: VelaDatabase? = nil) -> (NetworkSession, FakeHost) {
        let host = FakeHost()
        let config = NetworkConfig(name: "Test", host: "irc.test", nick: "doug")
        let session = NetworkSession(config: config, database: database)
        session.host = host
        session.nick = "doug"
        session.connectionState = .connected
        var support = ISupport()
        support.apply(["PREFIX=(ov)@+", "CHANTYPES=#", "CASEMAPPING=rfc1459"])
        session.isupport = support
        return (session, host)
    }

    private func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func feed(_ session: NetworkSession, _ lines: [String], batch: IRCBatch? = nil) {
        for line in lines {
            session.handle(.message(IRCMessage(line: line)!, batch: batch))
        }
    }

    /// A chathistory batch for `target` with `lines`, as `(seconds after base, nick, text)`.
    private func replay(_ session: NetworkSession, _ target: String, id: String = "b1", _ lines: [(Double, String, String)]) {
        let batch = IRCBatch(id: id, type: "chathistory", params: [target], parentID: nil)
        session.handle(.batchStarted(batch))
        feed(session, lines.enumerated().map { index, line in
            "@time=\(stamp(base.addingTimeInterval(line.0)));msgid=\(id)-\(index);batch=\(id) :\(line.1)!u@host PRIVMSG \(target) :\(line.2)"
        }, batch: batch)
        session.handle(.batchEnded(batch))
    }

    @Test func replayedMessagesAfterTheReadPositionCountAsUnread() throws {
        let (session, host) = makeSession()
        feed(session, [":doug!d@host JOIN #vela"])
        let vela = try #require(session.buffer(named: "#vela"))
        vela.lastReadAt = base.addingTimeInterval(10)

        replay(session, "#vela", [
            (5, "carol", "seen before you left"),
            (20, "carol", "missed one"),
            (30, "alice", "missed two"),
            (40, "doug", "your own, from another client"),
        ])

        #expect(vela.unreadCount == 2)
        #expect(vela.highlightCount == 0)
        // The New line goes where you stopped reading.
        #expect(vela.unreadMarkerAfter == base.addingTimeInterval(10))
        #expect(host.notable.isEmpty)
        #expect(vela.lines.filter(\.isHistory).count == 4)
    }

    @Test func replayedMentionsCountWithoutNotifying() throws {
        let (session, host) = makeSession()
        feed(session, [":doug!d@host JOIN #vela"])
        let vela = try #require(session.buffer(named: "#vela"))
        vela.lastReadAt = base

        replay(session, "#vela", [
            (20, "wren", "doug: can you review the PR?"),
            (30, "ada", "doughnuts later"),
        ])

        #expect(vela.unreadCount == 2)
        #expect(vela.highlightCount == 1)
        #expect(vela.lines.last { $0.text.hasPrefix("doug:") }?.isHighlight == true)
        // No banner, sound or Dock bounce for old news.
        #expect(host.notable.isEmpty)
    }

    /// ZNC replays its buffer as plain lines stamped before the connection.
    @Test func bouncerPlaybackCountsToo() throws {
        let (session, host) = makeSession()
        feed(session, [":doug!d@host JOIN #vela"])
        let vela = try #require(session.buffer(named: "#vela"))
        let now = Date()
        vela.lastReadAt = now.addingTimeInterval(-7200)
        session.handle(.registered(nick: "doug"))

        feed(session, [
            "@time=\(stamp(now.addingTimeInterval(-9000))) :carol!c@host PRIVMSG #vela :read already",
            "@time=\(stamp(now.addingTimeInterval(-3600))) :carol!c@host PRIVMSG #vela :doug: you there?",
            "@time=\(stamp(now.addingTimeInterval(-1800))) :alice!a@host PRIVMSG #vela :anyone?",
            // Someone messaged you while you were away.
            "@time=\(stamp(now.addingTimeInterval(-900))) :erin!e@host PRIVMSG doug :hey, got a minute?",
        ])

        #expect(vela.lines.filter(\.isHistory).count == 3)
        #expect(vela.unreadCount == 2)
        #expect(vela.highlightCount == 1)
        // A conversation a replayed message opens is all news.
        let erin = try #require(session.buffer(named: "erin"))
        #expect(erin.unreadCount == 1)
        #expect(erin.highlightCount == 1)
        #expect(host.notable.isEmpty)

        // Live lines still notify as before.
        feed(session, [":erin!e@host PRIVMSG doug :ping"])
        #expect(host.notable.count == 1)
    }

    /// The read position lasts across a reconnect, so what the bouncer
    /// replays after it counts again.
    @Test func reconnectingKeepsTheReadPosition() throws {
        let (session, host) = makeSession()
        feed(session, [":doug!d@host JOIN #vela"])
        let vela = try #require(session.buffer(named: "#vela"))
        let now = Date()
        session.handle(.registered(nick: "doug"))
        vela.lastReadAt = now.addingTimeInterval(-600)

        // Registered again, as after a reconnect.
        session.handle(.registered(nick: "doug"))
        #expect(vela.lastReadAt == now.addingTimeInterval(-600))
        feed(session, [
            "@time=\(stamp(now.addingTimeInterval(-900))) :carol!c@host PRIVMSG #vela :read before",
            "@time=\(stamp(now.addingTimeInterval(-300))) :carol!c@host PRIVMSG #vela :while you were reconnecting",
        ])
        #expect(vela.lines.filter(\.isHistory).count == 2)
        #expect(vela.unreadCount == 1)
        #expect(host.notable.isEmpty)
    }

    /// On launch, the read position comes back from the database before
    /// anything connects, so the first replay counts against it.
    @Test func theSavedReadPositionCountsTheFirstReplay() async throws {
        let database = try VelaDatabase.inMemory()
        let (session, host) = makeSession(database: database)
        try await database.upsertBuffer(BufferRecord(
            networkID: session.id, name: "#vela", foldedName: "#vela", kind: "channel", lastReadAt: base.addingTimeInterval(10)
        ))
        await session.restoreBuffers()
        let vela = try #require(session.buffer(named: "#vela"))
        #expect(vela.lastReadAt == base.addingTimeInterval(10))

        // The bouncer rejoins (a live JOIN keeps the saved position) and replays.
        feed(session, [":doug!d@host JOIN #vela"])
        #expect(vela.lastReadAt == base.addingTimeInterval(10))
        replay(session, "#vela", [(5, "carol", "old"), (20, "carol", "new")])
        #expect(vela.unreadCount == 1)
        #expect(host.notable.isEmpty)
    }

    /// Lines loaded by scrolling up are older history, never unread, even
    /// when they're after the read position.
    @Test func olderHistoryFromScrollingUpStaysRead() throws {
        let (session, _) = makeSession()
        feed(session, [":doug!d@host JOIN #vela"])
        let vela = try #require(session.buffer(named: "#vela"))
        vela.lastReadAt = base

        session.requestOlderHistory(for: vela, before: base.addingTimeInterval(100))
        replay(session, "#vela", [(20, "carol", "older"), (30, "carol", "older still")])
        #expect(vela.lines.filter(\.isHistory).count == 2)
        #expect(vela.unreadCount == 0)

        // A later batch for missed lines counts again.
        replay(session, "#vela", id: "b2", [(200, "carol", "missed")])
        #expect(vela.unreadCount == 1)
    }

    /// In the buffer on screen nothing is counted, but the New line goes
    /// above what was replayed, below what was already seen.
    @Test func replayInTheOpenBufferPlacesTheNewLine() throws {
        let (session, host) = makeSession()
        feed(session, [":doug!d@host JOIN #vela"])
        let vela = try #require(session.buffer(named: "#vela"))
        vela.lastReadAt = base
        host.visible = vela.id
        feed(session, ["@time=\(stamp(base.addingTimeInterval(5))) :alice!a@host PRIVMSG #vela :seen on screen"])
        #expect(vela.unreadMarkerAfter == nil)

        replay(session, "#vela", [(10, "carol", "missed one"), (11, "carol", "missed two")])
        #expect(vela.unreadCount == 0)
        #expect(vela.unreadMarkerAfter == base.addingTimeInterval(5))
        #expect(host.notable.isEmpty)
    }

    /// A first join starts the read position, so the history that comes
    /// with it stays read, and what's replayed after it next time counts.
    @Test func aFirstJoinStartsReading() throws {
        let (session, _) = makeSession()
        let joined = base.addingTimeInterval(100)
        feed(session, ["@time=\(stamp(joined)) :doug!d@host JOIN #new"])
        let new = try #require(session.buffer(named: "#new"))
        #expect(new.lastReadAt == joined)
        replay(session, "#new", [(20, "carol", "before you joined"), (50, "alice", "also before")])
        #expect(new.unreadCount == 0)
        replay(session, "#new", id: "b2", [(200, "carol", "after you joined")])
        #expect(new.unreadCount == 1)
    }

    /// Marking read up to one message recounts the replayed lines after it.
    @Test func readingUpToAMessageRecountsReplayedLines() throws {
        let (session, _) = makeSession()
        feed(session, [":doug!d@host JOIN #vela"])
        let vela = try #require(session.buffer(named: "#vela"))
        vela.lastReadAt = base
        replay(session, "#vela", [(10, "carol", "one"), (20, "carol", "two"), (30, "carol", "three")])
        #expect(vela.unreadCount == 3)

        session.markRead(vela, upTo: base.addingTimeInterval(10))
        #expect(vela.unreadCount == 2)
        #expect(vela.lastReadAt == base.addingTimeInterval(10))
    }
}
