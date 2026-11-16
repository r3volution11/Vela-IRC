// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaFoundation
import VelaIRC
import VelaStore

/// Nick colors per conversation: the people talking in a channel get
/// different colors.
@MainActor
@Suite("Conversation nick colors")
struct ConversationNickColorTests {
    private let wheel = NickPaletteGeometry(distances: (0..<12).map { i in
        (0..<12).map { j in Double(min(abs(i - j), 12 - abs(i - j))) }
    })

    private func makeChannel() -> (NetworkSession, BufferModel) {
        let session = NetworkSession(config: NetworkConfig(name: "Libera", host: "irc.test", nick: "r3volution11"), database: nil)
        session.host = FakeHost()
        session.nick = "r3volution11"
        session.connectionState = .connected
        session.handle(.message(IRCMessage(line: ":r3volution11!u@host JOIN ##politicalfun")!, batch: nil))
        return (session, session.buffer(named: "##politicalfun")!)
    }

    private func say(_ nick: String, _ text: String, in session: NetworkSession) {
        session.handle(.message(IRCMessage(line: ":\(nick)!u@host PRIVMSG ##politicalfun :\(text)")!, batch: nil))
    }

    @Test func clashingNicksGetDifferentColorsInOneChannel() {
        let (session, channel) = makeChannel()
        say("jeebz", "someone picked up our free washer", in: session)
        say("tomf", "whaaaa! what kind was it?", in: session)
        let jeebz = channel.nickColorIndex(for: "jeebz", palette: wheel)
        let tomf = channel.nickColorIndex(for: "tomf", palette: wheel)
        #expect(jeebz != tomf)

        // Later lines keep the assignment current and don't change it.
        say("xmn", "nice", in: session)
        say("tomf", "nice!", in: session)
        #expect(channel.nickColorIndex(for: "tomf", palette: wheel) == tomf)
        #expect(channel.nickColorIndex(for: "TOMF", palette: wheel) == tomf)
    }

    @Test func assignmentFollowsTheConversationNotTheOrderViewsAsk() {
        let (session, channel) = makeChannel()
        say("jeebz", "a", in: session)
        say("tomf", "b", in: session)
        // Asking about tomf first still gives jeebz (who spoke first) the
        // usual color.
        _ = channel.nickColorIndex(for: "tomf", palette: wheel)
        #expect(channel.nickColorIndex(for: "jeebz", palette: wheel) == NickColorAssigner.preferredIndex(for: "jeebz", paletteSize: 12))
    }

    @Test func aNewPaletteReplaysTheConversation() {
        let (session, channel) = makeChannel()
        say("jeebz", "a", in: session)
        say("tomf", "b", in: session)
        let small = NickPaletteGeometry(distances: (0..<5).map { i in (0..<5).map { j in Double(abs(i - j)) } })
        let jeebz = channel.nickColorIndex(for: "jeebz", palette: small)
        let tomf = channel.nickColorIndex(for: "tomf", palette: small)
        #expect(jeebz < 5 && tomf < 5)
        #expect(jeebz != tomf)
    }

    @Test func ownNickAndLurkersDoNotTakeColors() {
        let (session, channel) = makeChannel()
        session.handle(.message(IRCMessage(line: ":r3volution11!u@host PRIVMSG ##politicalfun :hi")!, batch: nil))
        say("jeebz", "a", in: session)
        // Your own lines don't hold a color, so jeebz keeps its usual one.
        #expect(channel.nickColorIndex(for: "jeebz", palette: wheel) == NickColorAssigner.preferredIndex(for: "jeebz", paletteSize: 12))
        #expect(channel.nickColorIndex(for: "lurker", palette: wheel) == NickColorAssigner.preferredIndex(for: "lurker", paletteSize: 12))
    }
}
