// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import Testing
@testable import VelaCore
import VelaFoundation
import VelaIRC
import VelaStore

/// What a buffer tells the message list about nicks in its text: who came
/// and went (and who got another color), so only the lines mentioning them
/// render again.
@MainActor
@Suite("Nick changes for message text")
struct NickChangeTests {
    private func makeChannel(names: String = "@doug alice bob") -> (NetworkSession, BufferModel) {
        let session = NetworkSession(config: NetworkConfig(name: "Test", host: "irc.test", nick: "doug"), database: nil)
        session.host = FakeHost()
        session.nick = "doug"
        session.connectionState = .connected
        var support = ISupport()
        support.apply(["PREFIX=(ov)@+", "CHANTYPES=#", "CASEMAPPING=rfc1459"])
        session.isupport = support
        feed(session, ":doug!d@host JOIN #vela", ":irc.test 353 doug = #vela :\(names)", ":irc.test 366 doug #vela :End")
        return (session, session.buffer(named: "#vela")!)
    }

    private func feed(_ session: NetworkSession, _ lines: String...) {
        for line in lines { session.handle(.message(IRCMessage(line: line)!, batch: nil)) }
    }

    @Test func joinsPartsQuitsAndKicksAreNoted() {
        let (session, channel) = makeChannel()
        var seen = channel.nickChangeCount

        func changes() -> [String]? {
            defer { seen = channel.nickChangeCount }
            return channel.nickChanges(since: seen)
        }

        feed(session, ":carol!c@host JOIN #vela")
        #expect(changes() == ["carol"])
        feed(session, ":carol!c@host PART #vela :bye")
        #expect(changes() == ["carol"])
        feed(session, ":alice!a@host QUIT :gone")
        #expect(changes() == ["alice"])
        feed(session, ":doug!d@host KICK #vela bob :out")
        #expect(changes() == ["bob"])
        #expect(changes() == [])
    }

    @Test func aNickChangeNotesBothNicks() {
        let (session, channel) = makeChannel()
        let seen = channel.nickChangeCount
        feed(session, ":alice!a@host NICK :alicia")
        #expect(channel.nickChanges(since: seen) == ["alice", "alicia"])
        #expect(channel.member(foldedNick: "alicia")?.nick == "alicia")
        #expect(channel.member(foldedNick: "alice") == nil)
    }

    @Test func modesAndAwayChangeNobody() {
        let (session, channel) = makeChannel()
        let seen = channel.nickChangeCount
        feed(session, ":doug!d@host MODE #vela +o alice", ":alice!a@host AWAY :lunch", ":carol!c@host JOIN #elsewhere")
        #expect(channel.nickChangeCount == seen)
        #expect(channel.member(named: "alice")?.prefixes == "@")
    }

    @Test func aNamesRefreshNotesOnlyWhoCameOrWent() {
        let (session, channel) = makeChannel()
        let seen = channel.nickChangeCount
        feed(session, ":irc.test 353 doug = #vela :@doug alice carol", ":irc.test 366 doug #vela :End")
        #expect(Set(channel.nickChanges(since: seen) ?? []) == ["bob", "carol"])
    }

    /// Joining a big channel, leaving, or a reconnect replaces everyone at
    /// once: the list starts over rather than sort it out.
    @Test func everyoneAtOnceCannotBeToldApart() {
        let (session, channel) = makeChannel()
        var seen = channel.nickChangeCount
        feed(session, ":doug!d@host PART #vela")
        #expect(channel.nickChanges(since: seen) == nil)

        seen = channel.nickChangeCount
        let crowd = (0..<200).map { "user\($0)" }.joined(separator: " ")
        feed(session, ":doug!d@host JOIN #vela", ":irc.test 353 doug = #vela :@doug \(crowd)", ":irc.test 366 doug #vela :End")
        #expect(channel.nickChanges(since: seen) == nil)
        #expect(channel.memberCount == 201)

        // From then on, single changes again.
        seen = channel.nickChangeCount
        feed(session, ":user7!u@host PART #vela")
        #expect(channel.nickChanges(since: seen) == ["user7"])
    }

    @Test func tooFarBehindCannotBeToldApart() {
        let (session, channel) = makeChannel()
        let seen = channel.nickChangeCount
        for index in 0..<600 { feed(session, ":u\(index)!u@host JOIN #vela") }
        #expect(channel.nickChanges(since: seen) == nil)
        #expect(channel.nickChanges(since: channel.nickChangeCount - 3) == ["u597", "u598", "u599"])
    }

    @Test func aSpeakerMovedOffTheirUsualColorIsNoted() {
        let (session, channel) = makeChannel(names: "@doug jeebz tomf")
        let wheel = NickPaletteGeometry(distances: (0..<12).map { i in
            (0..<12).map { j in Double(min(abs(i - j), 12 - abs(i - j))) }
        }, similar: 2)
        // The conversation's colors are made on first use.
        _ = channel.nickColorIndex(for: "jeebz", palette: wheel)
        feed(session, ":jeebz!j@host PRIVMSG #vela :hi")
        let seen = channel.nickChangeCount
        // tomf hashes onto jeebz's color, so speaking gives them another.
        feed(session, ":tomf!t@host PRIVMSG #vela :hello")
        #expect(channel.nickChanges(since: seen) == ["tomf"])
        // Speaking again changes nothing.
        let after = channel.nickChangeCount
        feed(session, ":tomf!t@host PRIVMSG #vela :again", ":jeebz!j@host PRIVMSG #vela :yes")
        #expect(channel.nickChangeCount == after)
    }

    /// The message list reads the count in its body and must update when it
    /// changes; rows look members up without watching them.
    @Test func theCountIsObservedAndMemberLookupsAreNot() {
        let (session, channel) = makeChannel()
        let counted = Flag(), looked = Flag()
        withObservationTracking { _ = channel.nickChangeCount } onChange: { counted.isSet = true }
        withObservationTracking { _ = channel.member(foldedNick: "alice") } onChange: { looked.isSet = true }
        feed(session, ":carol!c@host JOIN #vela")
        #expect(counted.isSet)
        #expect(!looked.isSet)
    }
}

private final class Flag: @unchecked Sendable {
    var isSet = false
}
