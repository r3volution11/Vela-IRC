// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaStore

/// A bouncer's replay of lines already shown (ZNC sends no msgids) must not
/// show them twice.
@MainActor
@Suite("Replayed copies in buffers")
struct BufferReplayTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(
        _ text: String, nick: String = "xmn", at seconds: TimeInterval,
        kind: ChatLineKind = .message, msgid: String? = nil, history: Bool = true
    ) -> ChatLine {
        ChatLine(msgid: msgid, time: base.addingTimeInterval(seconds), kind: kind, nick: nick, text: text, isHistory: history)
    }

    private func makeSession() -> (NetworkSession, BufferModel) {
        let session = NetworkSession(config: NetworkConfig(name: "ZNC", host: "znc.test", nick: "r3volution11"), database: nil)
        session.host = FakeHost()
        return (session, session.ensureBuffer(name: "#DN", kind: .channel, persist: false))
    }

    @Test func replayedLinesAreNotShownAgain() {
        let (session, buffer) = makeSession()
        session.add(line("nice", at: 0, history: false), to: buffer)
        session.add(line("Haha nah, that's cool.", nick: "r3volution11", at: 5, history: false), to: buffer)

        // The bouncer replays both, stamped by its own clock.
        session.add(line("nice", at: 0.3), to: buffer)
        session.add(line("Haha nah, that's cool.", nick: "r3volution11", at: 4.2), to: buffer)
        #expect(buffer.lines.map(\.text) == ["nice", "Haha nah, that's cool."])

        // Saying it again for real is kept, live or replayed later on.
        session.add(line("nice", at: 1, history: false), to: buffer)
        session.add(line("nice", at: 30), to: buffer)
        #expect(buffer.lines.filter { $0.text == "nice" }.count == 3)
    }

    @Test func historyLoadsDropCopiesAmongThemselves() {
        let (_, buffer) = makeSession()
        buffer.insertSorted([line("b", at: 10), line("a", at: 0), line("a", at: 0.5), line("b", at: 14)])
        #expect(buffer.lines.map(\.text) == ["a", "b", "b"])
        // Then a replay of what's already loaded.
        buffer.insertSorted([line("a", at: 1), line("c", at: 20)])
        #expect(buffer.lines.map(\.text) == ["a", "b", "b", "c"])
    }

    @Test func eventsAndMsgidLinesAreLeftAlone() {
        let (session, buffer) = makeSession()
        session.add(line("", at: 0, kind: .join), to: buffer)
        session.add(line("", at: 1, kind: .join), to: buffer)
        // Different msgids are different messages, however alike.
        session.add(line("+1", at: 2, msgid: "a"), to: buffer)
        session.add(line("+1", at: 2.5, msgid: "b"), to: buffer)
        #expect(buffer.lines.count == 4)
    }
}
