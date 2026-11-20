// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

@MainActor
final class FakeHost: SessionHost {
    var visible: BufferID?
    var notable: [ChatLine] = []
    var bouncerNetworks: [BouncerNetwork] = []
    var configChanges = 0
    var behavior = SessionBehavior()
    var factory: MockTransportFactory?

    func clientConfig(for session: NetworkSession) -> IRCClientConfig {
        var config = IRCClientConfig(host: "irc.test", port: 6667, useTLS: false, nick: session.config.nick)
        config.pingInterval = .zero
        config.pingTimeout = .zero
        config.floodPolicy = .disabled
        return config
    }

    func isBufferVisible(_ id: BufferID) -> Bool { visible == id }
    func activeBuffer(in session: NetworkSession) -> BufferModel? { visible.flatMap { session.buffer(id: $0) } }
    func session(_ session: NetworkSession, didReceiveNotable line: ChatLine, in buffer: BufferModel) { notable.append(line) }
    func session(_ session: NetworkSession, didUpdateBouncerNetworks networks: [BouncerNetwork]) { bouncerNetworks = networks }
    func sessionDidChangeConfig(_ session: NetworkSession) { configChanges += 1 }
    func sessionDidChangeUnreadCounts(_ session: NetworkSession) {}
}

@MainActor
private func makeSession(host: FakeHost = FakeHost(), autoJoin: [String] = []) -> (NetworkSession, FakeHost) {
    let config = NetworkConfig(name: "Test", host: "irc.test", nick: "doug", autoJoin: autoJoin.map { AutoJoinChannel(name: $0) })
    let session = NetworkSession(config: config, database: nil, transportFactory: host.factory?.makeTransport)
    session.host = host
    session.nick = "doug"
    session.connectionState = .connected
    var support = ISupport()
    support.apply(["PREFIX=(ov)@+", "CHANTYPES=#", "CASEMAPPING=rfc1459"])
    session.isupport = support
    return (session, host)
}

@MainActor
private func feed(_ session: NetworkSession, _ lines: String..., batch: IRCBatch? = nil) {
    for line in lines {
        session.handle(.message(IRCMessage(line: line)!, batch: batch))
    }
}

@MainActor
@Suite("NetworkSession")
struct SessionTests {
    @Test func selfJoinCreatesJoinedChannelAndNamesPopulateMembers() {
        let (session, _) = makeSession()
        feed(session,
             ":doug!d@host JOIN #vela",
             ":irc.test 353 doug = #vela :@alice +bob doug",
             ":irc.test 366 doug #vela :End of /NAMES list.")
        let buffer = try! #require(session.buffer(named: "#VELA"))
        #expect(buffer.isJoined)
        #expect(buffer.kind == .channel)
        #expect(buffer.members.map(\.nick) == ["alice", "bob", "doug"])
        #expect(buffer.members.first?.prefixes == "@")
    }

    @Test func messagesMentioningNickAreHighlightsAndCountUnread() {
        let (session, host) = makeSession()
        feed(session, ":doug!d@host JOIN #vela")
        feed(session, ":alice!a@host PRIVMSG #vela :hey doug, look at this", ":bob!b@host PRIVMSG #vela :doughnuts are great")
        let buffer = try! #require(session.buffer(named: "#vela"))
        let chat = buffer.lines.filter { $0.kind == .message }
        #expect(chat.count == 2)
        #expect(chat[0].isHighlight)
        #expect(!chat[1].isHighlight)
        #expect(buffer.unreadCount == 2)
        #expect(buffer.highlightCount == 1)
        #expect(host.notable.count == 1)
    }

    @Test func visibleBufferDoesNotAccumulateUnread() {
        let (session, host) = makeSession()
        feed(session, ":doug!d@host JOIN #vela")
        host.visible = session.buffer(named: "#vela")?.id
        feed(session, ":alice!a@host PRIVMSG #vela :hi")
        #expect(session.buffer(named: "#vela")?.unreadCount == 0)
    }

    @Test func privateMessageOpensQueryAndNotifies() {
        let (session, host) = makeSession()
        feed(session, ":Alice!a@host PRIVMSG doug :psst")
        let query = try! #require(session.buffer(named: "alice"))
        #expect(query.kind == .query)
        #expect(query.lines.last?.text == "psst")
        #expect(query.highlightCount == 1)
        #expect(host.notable.count == 1)
    }

    @Test func actionsAndCTCP() {
        let (session, _) = makeSession()
        feed(session, ":doug!d@host JOIN #vela", ":alice!a@host PRIVMSG #vela :\u{1}ACTION waves\u{1}")
        let line = try! #require(session.buffer(named: "#vela")?.lines.last)
        #expect(line.kind == .action)
        #expect(line.text == "waves")
    }

    @Test func partQuitNickAndModeUpdateMembers() {
        let (session, _) = makeSession()
        feed(session,
             ":doug!d@host JOIN #vela",
             ":irc.test 353 doug = #vela :alice bob carol doug",
             ":irc.test 366 doug #vela :End",
             ":alice!a@host PART #vela :bye",
             ":bob!b@host QUIT :gone",
             ":carol!c@host NICK caroline",
             ":op!o@host MODE #vela +o caroline")
        let buffer = try! #require(session.buffer(named: "#vela"))
        #expect(buffer.members.map(\.nick) == ["caroline", "doug"])
        #expect(buffer.member(named: "caroline")?.prefixes == "@")
        #expect(buffer.lines.map(\.kind).suffix(4) == [.part, .quit, .nick, .mode])
    }

    @Test func selfPartMarksChannelNotJoined() {
        let (session, _) = makeSession()
        feed(session, ":doug!d@host JOIN #vela", ":doug!d@host PART #vela")
        #expect(session.buffer(named: "#vela")?.isJoined == false)
    }

    @Test func topicNumericsAndTopicChanges() {
        let (session, _) = makeSession()
        feed(session,
             ":doug!d@host JOIN #vela",
             ":irc.test 332 doug #vela :Welcome to Vela",
             ":irc.test 333 doug #vela alice!a@host 1700000000")
        let buffer = try! #require(session.buffer(named: "#vela"))
        #expect(buffer.topic == "Welcome to Vela")
        #expect(buffer.topicSetBy == "alice")
        feed(session, ":bob!b@host TOPIC #vela :New topic")
        #expect(buffer.topic == "New topic")
    }

    @Test func typingIndicatorsAndReactions() {
        let (session, _) = makeSession()
        feed(session,
             ":doug!d@host JOIN #vela",
             "@msgid=m1 :alice!a@host PRIVMSG #vela :ship it",
             "@+typing=active :bob!b@host TAGMSG #vela",
             "@+draft/react=🚀;+draft/reply=m1 :bob!b@host TAGMSG #vela",
             "@+draft/react=🚀;+draft/reply=m1 :doug!d@host TAGMSG #vela")
        let buffer = try! #require(session.buffer(named: "#vela"))
        #expect(buffer.typingNicks == ["bob"])
        let reactions = buffer.reactions(for: "m1")
        #expect(reactions.count == 1)
        #expect(reactions.first?.nicks == ["bob", "doug"])
        #expect(reactions.first?.includesSelf == true)

        feed(session, "@+draft/unreact=🚀;+draft/reply=m1 :bob!b@host TAGMSG #vela")
        #expect(buffer.reactions(for: "m1").first?.nicks == ["doug"])

        // A message from the typer clears their typing state.
        feed(session, ":bob!b@host PRIVMSG #vela :done")
        #expect(buffer.typingNicks.isEmpty)
    }

    @Test func redactionMarksLine() {
        let (session, _) = makeSession()
        feed(session, ":doug!d@host JOIN #vela", "@msgid=m9 :alice!a@host PRIVMSG #vela :oops", ":alice!a@host REDACT #vela m9")
        #expect(session.buffer(named: "#vela")?.lines.last?.isRedacted == true)
    }

    /// History is inserted in time order. What's older than the read
    /// position (here, joining started it) stays read, and so does history
    /// in a buffer with no read position at all. Newer history counts as
    /// unread; see ReplayedUnreadTests.
    @Test func historyFromBeforeTheReadPositionStaysRead() {
        let (session, host) = makeSession()
        feed(session, ":doug!d@host JOIN #vela", ":alice!a@host PRIVMSG #vela :live message")
        let buffer = try! #require(session.buffer(named: "#vela"))
        #expect(buffer.lastReadAt != nil)
        let unreadBefore = buffer.unreadCount
        let batch = IRCBatch(id: "b1", type: "chathistory", params: ["#vela"], parentID: nil)
        session.handle(.batchStarted(batch))
        feed(session,
             "@time=2020-01-01T00:00:01.000Z;msgid=h1;batch=b1 :carol!c@host PRIVMSG #vela :old one doug",
             "@time=2020-01-01T00:00:02.000Z;msgid=h2;batch=b1 :carol!c@host PRIVMSG #vela :old two",
             batch: batch)
        session.handle(.batchEnded(batch))
        let texts = buffer.lines.filter { $0.kind == .message }.map(\.text)
        #expect(texts == ["old one doug", "old two", "live message"])
        #expect(buffer.unreadCount == unreadBefore)
        #expect(buffer.highlightCount == 0)
        #expect(host.notable.isEmpty)
        #expect(buffer.lines.first(where: { $0.msgid == "h1" })?.isHistory == true)

        // No read position: everything replayed stays read.
        let fresh = IRCBatch(id: "b2", type: "chathistory", params: ["#fresh"], parentID: nil)
        session.handle(.batchStarted(fresh))
        feed(session, "@time=2030-01-01T00:00:01.000Z;msgid=f1;batch=b2 :carol!c@host PRIVMSG #fresh :hi doug", batch: fresh)
        session.handle(.batchEnded(fresh))
        let channel = try! #require(session.buffer(named: "#fresh"))
        #expect(channel.lastReadAt == nil)
        #expect(channel.lines.count == 1)
        #expect(channel.unreadCount == 0)
        #expect(channel.highlightCount == 0)
        #expect(host.notable.isEmpty)
    }

    @Test func localEchoWithoutEchoMessage() {
        let (session, _) = makeSession()
        feed(session, ":doug!d@host JOIN #vela")
        session.handle(.sent(IRCMessage(command: "PRIVMSG", params: ["#vela", "hello"])))
        let line = try! #require(session.buffer(named: "#vela")?.lines.last)
        #expect(line.isSelf)
        #expect(line.text == "hello")
    }

    @Test func noLocalEchoWhenEchoMessageEnabled() {
        let (session, _) = makeSession()
        session.capabilities = ["echo-message"]
        feed(session, ":doug!d@host JOIN #vela")
        let count = session.buffer(named: "#vela")!.lines.count
        session.handle(.sent(IRCMessage(command: "PRIVMSG", params: ["#vela", "hello"])))
        #expect(session.buffer(named: "#vela")!.lines.count == count)
    }

    @Test func ignoredUsersAreDropped() {
        let (session, _) = makeSession()
        session.config.ignoreMasks = ["spammer"]
        session.behaviorDidChange()
        feed(session, ":doug!d@host JOIN #vela", ":spammer!s@bad PRIVMSG #vela :buy now", ":alice!a@host PRIVMSG #vela :hi")
        let texts = session.buffer(named: "#vela")!.lines.filter { $0.kind == .message }.map(\.text)
        #expect(texts == ["hi"])
    }

    @Test func soujBouncerNetworksAreReported() {
        let (session, host) = makeSession()
        let batch = IRCBatch(id: "n1", type: "soju.im/bouncer-networks", params: [], parentID: nil)
        session.handle(.batchStarted(batch))
        feed(session,
             "@batch=n1 :irc.test BOUNCER NETWORK 1 name=Libera;host=irc.libera.chat;state=connected",
             "@batch=n1 :irc.test BOUNCER NETWORK 2 name=OFTC;host=irc.oftc.net",
             batch: batch)
        #expect(host.bouncerNetworks.isEmpty)   // reported once, at batch end
        session.handle(.batchEnded(batch))
        #expect(host.bouncerNetworks.map(\.name) == ["Libera", "OFTC"])
        #expect(host.bouncerNetworks.first?.state == "connected")
    }

    @Test func serverNoticesGoToServerBuffer() {
        let (session, _) = makeSession()
        feed(session, ":NickServ!s@services NOTICE doug :This nickname is registered")
        #expect(session.buffer(named: "NickServ") == nil)
        #expect(session.serverBuffer.lines.last?.text == "This nickname is registered")
    }

    @Test func sortsChannelsBeforeQueries() {
        let (session, _) = makeSession()
        feed(session, ":zed!z@h PRIVMSG doug :hi", ":doug!d@host JOIN #beta", ":doug!d@host JOIN #alpha")
        // Channels first; each group in the order buffers were opened.
        #expect(session.buffers.map(\.name) == ["#beta", "#alpha", "zed"])
    }
}

@MainActor
@Suite("NetworkSession over a mock transport")
struct SessionTransportTests {
    @Test func registersAndAutoJoins() async throws {
        let factory = MockTransportFactory { transport, _ in
            transport.setResponder { line in
                if line.hasPrefix("CAP LS") { return [":irc.test CAP * LS :server-time message-tags"] }
                if line.hasPrefix("CAP REQ") {
                    let caps = line.components(separatedBy: ":").last ?? ""
                    return [":irc.test CAP * ACK :\(caps)"]
                }
                if line == "CAP END" {
                    return [":irc.test 001 doug :Welcome", ":irc.test 005 doug CHANTYPES=# PREFIX=(ov)@+ NETWORK=TestNet :are supported"]
                }
                if line.hasPrefix("JOIN ") {
                    let channel = String(line.dropFirst(5))
                    return [":doug!d@host JOIN \(channel)", ":irc.test 353 doug = \(channel) :doug @alice", ":irc.test 366 doug \(channel) :End"]
                }
                return []
            }
        }
        let host = FakeHost()
        host.factory = factory
        let config = NetworkConfig(name: "", host: "irc.test", nick: "doug", autoJoin: [AutoJoinChannel(name: "#vela")])
        let session = NetworkSession(config: config, database: nil, transportFactory: factory.makeTransport)
        session.host = host
        session.connect()

        try await waitUntil { session.buffer(named: "#vela")?.memberCount == 2 }
        #expect(session.connectionState == .connected)
        #expect(session.capabilities.contains("server-time"))
        #expect(session.isupport.network == "TestNet")
        #expect(session.displayName == "TestNet")
        #expect(session.buffer(named: "#vela")?.isJoined == true)

        session.submit("hello world", in: session.buffer(named: "#vela")!)
        let transport = try #require(factory.latest)
        let sent = await transport.nextSentLine(timeout: .seconds(2)) { $0.hasPrefix("PRIVMSG") }
        #expect(sent == "PRIVMSG #vela :hello world")
    }
}

@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { throw WaitTimeout() }
        try await Task.sleep(for: .milliseconds(20))
    }
}

struct WaitTimeout: Error {}
