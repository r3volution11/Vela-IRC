// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

/// Kicks, bans, quiets, rank changes and CTCP requests, against a scripted
/// server: what goes out, in what order, and what shows.
@MainActor
@Suite("Moderation over a mock transport")
struct ModerationSessionTests {
    @MainActor
    private struct Connected {
        let session: NetworkSession
        let host: FakeHost
        let transport: MockTransport
        var vela: BufferModel { session.buffer(named: "#vela")! }

        func sent(_ prefix: String) -> [String] {
            transport.sentLines.filter { $0.hasPrefix(prefix) }
        }
    }

    /// Connects as `doug`, joined to #vela (`names`) and #swift, with
    /// `isupport` tokens; `respond` scripts anything else.
    private func connect(
        isupport: String = "PREFIX=(ov)@+ CHANMODES=eIbq,k,flj,CFLMPQSTcgimnprstuz MODES=3",
        names: String = "@doug wren +ada kenji",
        behavior: SessionBehavior = SessionBehavior(),
        respond: @escaping @Sendable (String) -> [String] = { _ in [] }
    ) async throws -> Connected {
        let factory = MockTransportFactory { transport, _ in
            transport.setResponder { line in
                if line.hasPrefix("CAP LS") { return [":irc.test CAP * LS :server-time"] }
                if line.hasPrefix("CAP REQ") { return [":irc.test CAP * ACK :server-time"] }
                if line == "CAP END" {
                    return [":irc.test 001 doug :Welcome", ":irc.test 005 doug CHANTYPES=# \(isupport) :are supported"]
                }
                if line.hasPrefix("JOIN ") {
                    let channel = String(line.dropFirst(5))
                    let members = channel == "#vela" ? names : "doug"
                    return [":doug!d@host JOIN \(channel)", ":irc.test 353 doug = \(channel) :\(members)", ":irc.test 366 doug \(channel) :End"]
                }
                return respond(line)
            }
        }
        let host = FakeHost()
        host.factory = factory
        host.behavior = behavior
        let config = NetworkConfig(name: "Test", host: "irc.test", nick: "doug", autoJoin: [AutoJoinChannel(name: "#vela"), AutoJoinChannel(name: "#swift")])
        let session = NetworkSession(config: config, database: nil, transportFactory: factory.makeTransport)
        session.host = host
        session.userHostTimeout = .milliseconds(300)
        session.connect()
        try await waitUntil { session.buffer(named: "#vela")?.memberCount ?? 0 > 1 && session.buffer(named: "#swift")?.isJoined == true }
        let transport = try #require(factory.latest)
        return Connected(session: session, host: host, transport: transport)
    }

    // MARK: Kick and ban

    @Test func kickBanLooksUpTheHostThenBansThenKicks() async throws {
        let connected = try await connect { line in
            line == "USERHOST wren" ? [":irc.test 302 doug :wren=+~wren@cloak/wren"] : []
        }
        connected.session.submit("/kb wren spamming links", in: connected.vela)
        try await waitUntil { !connected.sent("KICK").isEmpty }
        let lines = connected.transport.sentLines
        let userhost = try #require(lines.firstIndex(of: "USERHOST wren"))
        let ban = try #require(lines.firstIndex(of: "MODE #vela +b *!*@cloak/wren"))
        let kick = try #require(lines.firstIndex(of: "KICK #vela wren :spamming links"))
        #expect(userhost < ban && ban < kick)
        // The lookup's answer isn't shown, but it's remembered.
        #expect(!connected.session.serverBuffer.lines.contains { $0.text.contains("wren=") })
        #expect(connected.vela.member(named: "wren")?.userHost == "~wren@cloak/wren")
    }

    @Test func withNoAnswerItBansTheNick() async throws {
        let connected = try await connect()
        connected.session.submit("/ban wren", in: connected.vela)
        try await waitUntil { !connected.sent("MODE #vela +b").isEmpty }
        #expect(connected.sent("MODE #vela +b") == ["MODE #vela +b wren!*@*"])
    }

    @Test func aKnownHostNeedsNoLookup() async throws {
        let connected = try await connect(names: "@doug wren!w@known.example +ada")
        connected.session.submit("/ban wren", in: connected.vela)
        try await waitUntil { !connected.sent("MODE #vela +b").isEmpty }
        #expect(connected.sent("MODE #vela +b") == ["MODE #vela +b *!*@known.example"])
        #expect(connected.sent("USERHOST").isEmpty)
    }

    @Test func theBanMaskSettingIsUsed() async throws {
        var behavior = SessionBehavior()
        behavior.banMaskStyle = .userHost
        let connected = try await connect(names: "@doug wren!~w@known.example", behavior: behavior)
        connected.session.submit("/ban wren", in: connected.vela)
        try await waitUntil { !connected.sent("MODE #vela +b").isEmpty }
        #expect(connected.sent("MODE #vela +b") == ["MODE #vela +b *!~w@known.example"])
    }

    @Test func kicksUseTheDefaultReason() async throws {
        var behavior = SessionBehavior()
        behavior.defaultKickReason = "Please read the rules"
        let connected = try await connect(behavior: behavior)
        connected.session.submit("/kick wren", in: connected.vela)
        connected.session.submit("/kick ada be nice", in: connected.vela)
        connected.session.execute(.kick(nick: "kenji", reason: ""), in: connected.vela)
        try await waitUntil { connected.sent("KICK").count == 3 }
        #expect(connected.sent("KICK") == ["KICK #vela wren :Please read the rules", "KICK #vela ada :be nice", "KICK #vela kenji"])
    }

    // MARK: Ranks and quiets

    @Test func rankChangesFollowModes() async throws {
        let connected = try await connect(isupport: "PREFIX=(ov)@+ MODES=2")
        connected.session.submit("/voice wren ada kenji", in: connected.vela)
        try await waitUntil { connected.sent("MODE #vela +v").count == 2 }
        #expect(connected.sent("MODE #vela +v") == ["MODE #vela +vv wren ada", "MODE #vela +v kenji"])
    }

    @Test func quietUsesTheListModeOrTheExtban() async throws {
        let libera = try await connect(names: "@doug wren!w@known.example")
        libera.session.submit("/quiet wren", in: libera.vela)
        try await waitUntil { !libera.sent("MODE #vela +q").isEmpty }
        #expect(libera.sent("MODE #vela +q") == ["MODE #vela +q *!*@known.example"])

        let insp = try await connect(
            isupport: "PREFIX=(qaohv)~&@%+ CHANMODES=IXbegw,k,FHJLfjl,BCDMNOPRSTcimnprstz EXTBAN=,ACNOQRSTUcjmprsz",
            names: "@doug wren!w@known.example"
        )
        insp.session.submit("/unquiet wren", in: insp.vela)
        try await waitUntil { !insp.sent("MODE #vela -b").isEmpty }
        #expect(insp.sent("MODE #vela -b") == ["MODE #vela -b m:*!*@known.example"])
    }

    @Test func quietWithoutSupportSaysSo() async throws {
        let connected = try await connect(isupport: "PREFIX=(ov)@+ CHANMODES=beI,k,l,imnpst")
        connected.session.submit("/quiet wren", in: connected.vela)
        #expect(connected.vela.lines.last?.kind == .error)
        #expect(connected.vela.lines.last?.text.contains("quiet") == true)
    }

    // MARK: The user menu's actions

    @Test func menuActionsTakeTheCommandPaths() async throws {
        let connected = try await connect(names: "@doug wren!w@known.example +ada!a@ada.example kenji")
        let session = connected.session
        let vela = connected.vela
        let targets = ["wren", "ada", "kenji"].map { session.userMenuTarget(nick: $0, in: vela) }
        // Op only those who aren't; devoice only those who are.
        session.perform(.mode(sign: "+", mode: "o"), on: targets, in: vela)
        session.perform(.mode(sign: "-", mode: "v"), on: targets, in: vela)
        session.perform(.ban, on: Array(targets.prefix(2)), in: vela)
        try await waitUntil { !connected.sent("MODE #vela +b").isEmpty }
        #expect(connected.sent("MODE #vela +o") == ["MODE #vela +ooo wren ada kenji"])
        #expect(connected.sent("MODE #vela -v") == ["MODE #vela -v ada"])
        #expect(connected.sent("MODE #vela +b") == ["MODE #vela +bb *!*@known.example *!*@ada.example"])
    }

    @Test func userMenuFromTheSession() async throws {
        let connected = try await connect(names: "@doug wren!w@known.example +ada")
        let session = connected.session
        let vela = connected.vela
        let wren = session.userMenuTarget(nick: "WREN", in: vela)
        #expect(wren.nick == "wren")
        #expect(wren.isMember)
        #expect(wren.userHost == "w@known.example")
        #expect(session.userMenuTarget(nick: "ada", in: vela).modes == ["v"])
        #expect(session.userMenuTarget(nick: "doug", in: vela).isSelf)
        let menu = session.userMenu(for: [wren], in: vela)
        #expect(menu.titles.contains("Kick"))
        // wren isn't in #swift, so they can be invited there.
        #expect(menu.submenu("Invite to")?.count == 1)
        #expect(menu.item(.invite(channel: "#swift")) != nil)
        #expect(menu.titles.contains("Quiet"))
        // Ignoring and unignoring.
        session.perform(.ignore, on: [wren], in: vela)
        #expect(session.userMenuTarget(nick: "wren", in: vela).isIgnored)
        session.perform(.unignore, on: [session.userMenuTarget(nick: "wren", in: vela)], in: vela)
        #expect(!session.userMenuTarget(nick: "wren", in: vela).isIgnored)
        #expect(session.config.ignoreMasks.isEmpty)
        // Message opens the conversation, through the app.
        var selected: BufferModel?
        session.requestSelection = { selected = $0 }
        session.perform(.message, on: [wren], in: vela)
        #expect(selected?.name == "wren")
        #expect(selected?.kind == .query)
    }

    // MARK: CTCP

    @Test func pingShowsTheRoundTripWhereYouAsked() async throws {
        let connected = try await connect { line in
            guard line.hasPrefix("PRIVMSG wren :\u{1}PING ") else { return [] }
            let token = line.dropFirst("PRIVMSG wren :\u{1}PING ".count).dropLast()
            return [":wren!w@host NOTICE doug :\u{1}PING \(token)\u{1}"]
        }
        let swift = try #require(connected.session.buffer(named: "#swift"))
        // Somewhere else is on screen.
        connected.host.visible = connected.vela.id
        connected.session.submit("/ping wren", in: swift)
        try await waitUntil { swift.lines.contains { $0.text.hasPrefix("Ping reply from wren: ") } }
        let reply = try #require(swift.lines.last)
        #expect(reply.kind == .ctcp)
        #expect(reply.text.hasSuffix(" ms"))
        #expect(swift.lines.contains { $0.text == "Pinging wren…" })
        #expect(!connected.vela.lines.contains { $0.kind == .ctcp })
    }

    @Test func versionRepliesAreReadable() async throws {
        let connected = try await connect { line in
            // (No colon before a last parameter without spaces.)
            line.hasPrefix("PRIVMSG wren ") && line.hasSuffix("\u{1}VERSION\u{1}")
                ? [":wren!w@host NOTICE doug :\u{1}VERSION HexChat 2.16.2\u{1}"]
                : []
        }
        connected.session.submit("/version wren", in: connected.vela)
        try await waitUntil { connected.vela.lines.contains { $0.text == "wren is using HexChat 2.16.2" } }
    }

    @Test func unaskedRepliesStillShow() async throws {
        let connected = try await connect()
        connected.host.visible = connected.vela.id
        connected.transport.receive(":wren!w@host NOTICE doug :\u{1}VERSION Something\u{1}")
        try await waitUntil { connected.vela.lines.contains { $0.text == "CTCP VERSION reply from wren: Something" } }
    }

    @Test func yourOwnEchoedRequestsArentShown() async throws {
        let connected = try await connect()
        connected.host.visible = connected.vela.id
        connected.transport.receive(":doug!d@host PRIVMSG wren :\u{1}VERSION\u{1}")
        connected.transport.receive(":kenji!k@host PRIVMSG doug :\u{1}TIME\u{1}")
        try await waitUntil { connected.vela.lines.contains { $0.text == "kenji requested CTCP TIME" } }
        #expect(!connected.vela.lines.contains { $0.text.contains("doug requested") })
    }
}
