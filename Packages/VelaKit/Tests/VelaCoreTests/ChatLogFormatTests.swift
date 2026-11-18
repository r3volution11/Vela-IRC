// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore

/// Logs written in UTC so the expected text doesn't depend on the Mac.
let utcLogClock = ChatLogClock(timeZone: TimeZone(identifier: "UTC")!)

func logDate(_ text: String) -> Date {
    utcLogClock.date(from: text)!
}

@Suite("Chat log format")
struct ChatLogFormatTests {
    private let time = logDate("2026-11-17 21:04:05")

    private func line(_ kind: ChatLineKind, _ nick: String?, _ text: String, isSelf: Bool = false) -> String {
        ChatLogFormat.line(.line(kind: kind, nick: nick, text: text, isSelf: isSelf), at: time, clock: utcLogClock)
    }

    @Test func messagesActionsAndNotices() {
        #expect(line(.message, "alice", "hi there") == "[2026-11-17 21:04:05] <alice> hi there")
        #expect(line(.message, "doug", "my own line", isSelf: true) == "[2026-11-17 21:04:05] <doug> my own line")
        #expect(line(.action, "doug", "waves") == "[2026-11-17 21:04:05] * doug waves")
        #expect(line(.notice, "ChanServ", "Welcome") == "[2026-11-17 21:04:05] -ChanServ- Welcome")
        #expect(line(.notice, nil, "*** Looking up your hostname") == "[2026-11-17 21:04:05] -!- *** Looking up your hostname")
    }

    @Test func eventsArePlainLines() {
        #expect(line(.join, "alice", "alice (a@example.org) joined #vela") == "[2026-11-17 21:04:05] -!- alice (a@example.org) joined #vela")
        #expect(line(.part, "alice", "alice left #vela (bye)") == "[2026-11-17 21:04:05] -!- alice left #vela (bye)")
        #expect(line(.quit, "alice", "alice quit (Ping timeout)") == "[2026-11-17 21:04:05] -!- alice quit (Ping timeout)")
        #expect(line(.kick, "bob", "bob kicked alice from #vela (spam)") == "[2026-11-17 21:04:05] -!- bob kicked alice from #vela (spam)")
        #expect(line(.nick, "alice", "alice is now known as alice_") == "[2026-11-17 21:04:05] -!- alice is now known as alice_")
        #expect(line(.topic, "bob", "bob changed the topic to: Vela 1.0") == "[2026-11-17 21:04:05] -!- bob changed the topic to: Vela 1.0")
        #expect(line(.topic, nil, "Topic: Vela 1.0") == "[2026-11-17 21:04:05] -!- Topic: Vela 1.0")
        #expect(line(.mode, "bob", "bob sets mode +o alice") == "[2026-11-17 21:04:05] -!- bob sets mode +o alice")
    }

    @Test func serverLines() {
        #expect(line(.info, nil, "Connected as doug") == "[2026-11-17 21:04:05] -!- Connected as doug")
        #expect(line(.motd, nil, "- Welcome -") == "[2026-11-17 21:04:05] -!- - Welcome -")
        #expect(line(.error, nil, "Disconnected: Ping timeout") == "[2026-11-17 21:04:05] -!- Error: Disconnected: Ping timeout")
    }

    @Test func yourOwnNickChangeNamesYou() {
        #expect(line(.nick, "doug", "You are now known as doug_", isSelf: true) == "[2026-11-17 21:04:05] -!- doug is now known as doug_")
    }

    @Test func formattingIsStrippedAndLinksKept() {
        let text = "\u{02}bold\u{02} \u{03}04,01red\u{03} \u{1D}it\u{1D} see https://velairc.app/guide?x=1"
        #expect(line(.message, "alice", text) == "[2026-11-17 21:04:05] <alice> bold red it see https://velairc.app/guide?x=1")
    }

    @Test func controlCharactersAndLineBreaks() {
        #expect(ChatLogFormat.plainText("one\r\ntwo\nthree") == "one two three")
        #expect(ChatLogFormat.plainText("tab\there\u{07}\u{7F}") == "tab\there")
        #expect(ChatLogFormat.plainText("emoji 🎉 und Umlaute ä") == "emoji 🎉 und Umlaute ä")
    }

    @Test func redactionsNoteTheDeletedLine() {
        let sent = logDate("2026-11-17 21:00:00")
        let byOther = ChatLogFormat.line(.redaction(by: "bob", originalNick: "alice", originalTime: sent, reason: "spam"), at: time, clock: utcLogClock)
        #expect(byOther == "[2026-11-17 21:04:05] -!- bob deleted a message from alice sent at 2026-11-17 21:00:00 (spam)")
        let own = ChatLogFormat.line(.redaction(by: "alice", originalNick: "alice", originalTime: sent, reason: nil), at: time, clock: utcLogClock)
        #expect(own == "[2026-11-17 21:04:05] -!- alice deleted their message sent at 2026-11-17 21:00:00")
    }

    @Test func markers() {
        #expect(ChatLogFormat.openedMarker(at: time, clock: utcLogClock) == "--- Log opened 2026-11-17 21:04:05 ---")
        #expect(ChatLogFormat.closedMarker(at: time, clock: utcLogClock) == "--- Log closed 2026-11-17 21:04:05 ---")
    }

    @Test func timestampsRoundTrip() {
        #expect(utcLogClock.string(from: time) == "2026-11-17 21:04:05")
        #expect(utcLogClock.day(from: time) == "2026-11-17")
        #expect(utcLogClock.date(from: "2026-11-17 21:04:05") == time)
        #expect(utcLogClock.date(from: "2026-11-17 21:04") == nil)
        #expect(utcLogClock.date(from: "not a timestamp at all") == nil)
    }

    @Test func readsTimesBackOutOfALog() {
        let log = """
        --- Log opened 2026-11-01 08:00:00 ---
        [2026-11-01 08:00:01] <alice> first
        [2026-11-17 21:04:05] <bob> last
        --- Log closed 2026-11-17 23:00:00 ---

        """
        #expect(ChatLogFormat.lastLineTime(in: log[...], clock: utcLogClock) == time)
        #expect(ChatLogFormat.firstTime(in: log[...], clock: utcLogClock) == logDate("2026-11-01 08:00:01"))
        #expect(ChatLogFormat.firstTime(in: "--- Log opened 2026-11-01 08:00:00 ---\n", clock: utcLogClock) == logDate("2026-11-01 08:00:00"))
        #expect(ChatLogFormat.lastLineTime(in: "--- Log opened 2026-11-01 08:00:00 ---\n", clock: utcLogClock) == nil)
        // A tail that starts mid-line skips the broken first line.
        #expect(ChatLogFormat.lastLineTime(in: "05] <x> cut\n[2026-11-17 21:04:05] <bob> ok\n", clock: utcLogClock) == time)
    }

    @Test func whichLinesAreLogged() {
        for kind in [ChatLineKind.message, .action, .notice] {
            #expect(ChatLogPolicy.includes(kind, in: .channel, events: false))
            #expect(ChatLogPolicy.includes(kind, in: .query, events: false))
        }
        for kind in [ChatLineKind.join, .part, .quit, .nick, .kick, .topic, .mode] {
            #expect(ChatLogPolicy.includes(kind, in: .channel, events: true))
            #expect(!ChatLogPolicy.includes(kind, in: .channel, events: false))
        }
        for kind in [ChatLineKind.info, .error, .motd, .ctcp, .invite, .dayChange] {
            #expect(!ChatLogPolicy.includes(kind, in: .channel, events: true))
        }
        #expect(ChatLogPolicy.includes(.motd, in: .server, events: false))
        #expect(ChatLogPolicy.includes(.info, in: .server, events: false))
        #expect(!ChatLogPolicy.includes(.dayChange, in: .server, events: true))
    }
}
