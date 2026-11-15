// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization
import Testing
@testable import VelaIRC

// MARK: - Helpers

/// Collects client events so tests can wait for them in order.
final class EventRecorder: Sendable {
    private let storage = Mutex<(events: [IRCClientEvent], cursor: Int)>(([], 0))

    init(_ stream: AsyncStream<IRCClientEvent>) {
        Task { [self] in
            for await event in stream {
                storage.withLock { $0.events.append(event) }
            }
        }
    }

    var all: [IRCClientEvent] { storage.withLock { $0.events } }

    /// Waits for the next event (after the previously matched one) for which
    /// `match` returns non-nil.
    func next<T: Sendable>(timeout: Duration = .seconds(5), _ match: (IRCClientEvent) -> T?) async -> T? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let found: T? = storage.withLock { state in
                var index = state.cursor
                while index < state.events.count {
                    if let value = match(state.events[index]) {
                        state.cursor = index + 1
                        return value
                    }
                    index += 1
                }
                return nil
            }
            if let found { return found }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }

    /// All `.message` events received so far.
    var messages: [(IRCMessage, IRCBatch?)] {
        all.compactMap { if case .message(let message, let batch) = $0 { (message, batch) } else { nil } }
    }
}

private struct Harness {
    let client: IRCClient
    let mock: MockTransport
    let events: EventRecorder

    init(_ config: IRCClientConfig) {
        let mock = MockTransport()
        self.mock = mock
        client = IRCClient(config: config) { _ in mock }
        events = EventRecorder(client.events)
    }

    /// Expects the next sent lines to be exactly `lines`.
    func expectSent(_ lines: String..., sourceLocation: SourceLocation = #_sourceLocation) async {
        for line in lines {
            let sent = await mock.nextSentLine()
            #expect(sent == line, sourceLocation: sourceLocation)
        }
    }

    /// Connects and completes registration without any capabilities.
    func connectAndRegister(nick: String = "vela", caps: String = "") async {
        await client.connect()
        await expectSent("CAP LS 302", "NICK \(nick)", "USER \(nick) 0 * \(nick)")
        mock.receive(":irc.test CAP * LS :\(caps)")
        if !caps.isEmpty, let request = await mock.nextSentLine(where: { $0.hasPrefix("CAP REQ") }) {
            let list = request.dropFirst("CAP REQ ".count).drop(while: { $0 == ":" })
            mock.receive(":irc.test CAP \(nick) ACK :\(list)")
        }
        _ = await mock.nextSentLine(where: { $0 == "CAP END" })
        mock.receive(":irc.test 001 \(nick) :Welcome to the test network")
        _ = await events.next { if case .registered = $0 { true } else { nil } }
    }
}

/// Polls `condition` until it holds or `timeout` elapses.
private func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}

private func config(
    nick: String = "vela",
    useTLS: Bool = true,
    sasl: SASLMechanism? = nil,
    saslRequired: Bool = false,
    alternateNicks: [String] = [],
    bouncerNetworkID: String? = nil,
    serverPassword: String? = nil,
    pingInterval: Duration = .seconds(60),
    pingTimeout: Duration = .seconds(60),
    connectTimeout: Duration = .seconds(10),
    floodPolicy: IRCFloodPolicy = .disabled
) -> IRCClientConfig {
    IRCClientConfig(
        host: "irc.test",
        port: useTLS ? 6697 : 6667,
        useTLS: useTLS,
        nick: nick,
        alternateNicks: alternateNicks,
        serverPassword: serverPassword,
        sasl: sasl,
        saslRequired: saslRequired,
        bouncerNetworkID: bouncerNetworkID,
        versionReply: "Vela test",
        pingInterval: pingInterval,
        pingTimeout: pingTimeout,
        connectTimeout: connectTimeout,
        floodPolicy: floodPolicy
    )
}

// MARK: - Registration

@Suite(.timeLimit(.minutes(1))) struct IRCClientRegistrationTests {
    @Test func registrationWithSASLSuccess() async throws {
        let harness = Harness(config(sasl: .plain(account: "vela", password: "hunter2")))
        let (client, mock, events) = (harness.client, harness.mock, harness.events)

        await client.connect()
        #expect(await client.state == .registering)
        await harness.expectSent("CAP LS 302", "NICK vela", "USER vela 0 * vela")

        mock.receive(":irc.test CAP * LS * :multi-prefix sasl=PLAIN,EXTERNAL server-time unknown-cap")
        mock.receive(":irc.test CAP * LS :message-tags batch")
        await harness.expectSent("CAP REQ :batch message-tags multi-prefix sasl server-time")

        mock.receive(":irc.test CAP vela ACK :batch message-tags multi-prefix sasl server-time")
        await harness.expectSent("AUTHENTICATE PLAIN")
        mock.receive("AUTHENTICATE +")
        let payload = Data("vela\0vela\0hunter2".utf8).base64EncodedString()
        await harness.expectSent("AUTHENTICATE \(payload)")

        mock.receive(":irc.test 900 vela vela!vela@host vela :You are now logged in as vela")
        mock.receive(":irc.test 903 vela :SASL authentication successful")
        await harness.expectSent("CAP END")

        mock.receive(":irc.test 001 vela :Welcome")
        mock.receive(":irc.test 005 vela CASEMAPPING=ascii PREFIX=(ov)@+ NETWORK=Test :are supported by this server")

        let sasl = await events.next { event -> (Bool, String?)? in
            if case .saslFinished(let success, let account, _) = event { (success, account) } else { nil }
        }
        #expect(sasl?.0 == true)
        #expect(sasl?.1 == "vela")
        #expect(await events.next { if case .registered(let nick) = $0 { nick } else { nil } } == "vela")
        let isupport = await events.next { if case .isupportChanged(let isupport) = $0 { isupport } else { nil } }
        #expect(isupport?.network == "Test")
        #expect(isupport?.caseMapping == .ascii)

        #expect(await client.state == .connected)
        #expect(await client.account == "vela")
        #expect(await client.enabledCapabilities == ["batch", "message-tags", "multi-prefix", "sasl", "server-time"])
        #expect(await client.isupport.network == "Test")

        // The credential payload is redacted in `.sent` events.
        let sentAuth = events.all.compactMap { event -> IRCMessage? in
            if case .sent(let message) = event, message.command == "AUTHENTICATE" { message } else { nil }
        }
        #expect(sentAuth.map { $0.params[0] } == ["PLAIN", "********"])
        // CAP and AUTHENTICATE are consumed; numerics are emitted.
        let commands = events.messages.map(\.0.command)
        #expect(!commands.contains("CAP"))
        #expect(!commands.contains("AUTHENTICATE"))
        #expect(commands.contains("900"))
        #expect(commands.contains("001"))

        let states = events.all.compactMap { if case .stateChanged(let state) = $0 { state } else { nil } }
        #expect(states == [.connecting, .registering, .connected])
    }

    @Test func registrationWithSASLFailureContinues() async {
        let harness = Harness(config(sasl: .plain(account: "vela", password: "wrong")))
        let (client, mock, events) = (harness.client, harness.mock, harness.events)

        await client.connect()
        await harness.expectSent("CAP LS 302", "NICK vela", "USER vela 0 * vela")
        mock.receive(":irc.test CAP * LS :sasl")
        await harness.expectSent("CAP REQ sasl")
        mock.receive(":irc.test CAP * ACK sasl")
        await harness.expectSent("AUTHENTICATE PLAIN")
        mock.receive("AUTHENTICATE +")
        _ = await mock.nextSentLine()
        mock.receive(":irc.test 904 vela :SASL authentication failed")
        await harness.expectSent("CAP END")

        let result = await events.next { event -> (Bool, String?, String)? in
            if case .saslFinished(let success, let account, let message) = event { (success, account, message) } else { nil }
        }
        #expect(result?.0 == false)
        #expect(result?.1 == nil)
        #expect(result?.2 == "SASL authentication failed")

        mock.receive(":irc.test 001 vela :Welcome")
        #expect(await events.next { if case .registered(let nick) = $0 { nick } else { nil } } == "vela")
        #expect(await client.account == nil)
    }

    @Test func requiredSASLFailureDisconnects() async {
        let harness = Harness(config(sasl: .external, saslRequired: true))
        let (client, mock, events) = (harness.client, harness.mock, harness.events)

        await client.connect()
        await harness.expectSent("CAP LS 302", "NICK vela", "USER vela 0 * vela")
        mock.receive(":irc.test CAP * LS :sasl=PLAIN")  // EXTERNAL not offered
        await harness.expectSent("CAP REQ sasl")
        mock.receive(":irc.test CAP * ACK sasl")

        let reason = await events.next { if case .disconnected(let reason) = $0 { reason } else { nil } }
        #expect(reason?.contains("SASL") == true)
        #expect(await client.state == .disconnected)
        #expect(await eventually { mock.isClosed })
        #expect(!mock.sentLines.contains("CAP END"))
    }

    @Test func saslUnavailableIsReported() async {
        let harness = Harness(config(sasl: .plain(account: "a", password: "b")))
        await harness.client.connect()
        await harness.expectSent("CAP LS 302", "NICK vela", "USER vela 0 * vela")
        harness.mock.receive(":irc.test CAP * LS :batch")
        await harness.expectSent("CAP REQ batch")
        harness.mock.receive(":irc.test CAP * ACK batch")
        await harness.expectSent("CAP END")
        let success = await harness.events.next { if case .saslFinished(let success, _, _) = $0 { success } else { nil } }
        #expect(success == false)
    }

    @Test func serverPasswordIsSentAndRedacted() async {
        let harness = Harness(config(serverPassword: "letmein"))
        await harness.client.connect()
        await harness.expectSent("CAP LS 302", "PASS letmein", "NICK vela", "USER vela 0 * vela")
        let pass = await harness.events.next { event -> IRCMessage? in
            if case .sent(let message) = event, message.command == "PASS" { message } else { nil }
        }
        #expect(pass?.params == ["********"])
    }

    @Test func serverWithoutCAPStillRegisters() async {
        let harness = Harness(config(sasl: .plain(account: "a", password: "b")))
        await harness.client.connect()
        await harness.expectSent("CAP LS 302", "NICK vela", "USER vela 0 * vela")
        harness.mock.receive(":old.server 421 * CAP :Unknown command")
        harness.mock.receive(":old.server 001 vela :Welcome")
        #expect(await harness.events.next { if case .registered(let nick) = $0 { nick } else { nil } } == "vela")
        #expect(await harness.client.state == .connected)
        #expect(!harness.mock.sentLines.contains("CAP END"))
    }

    @Test func nickCollisionFallsBack() async {
        let harness = Harness(config(alternateNicks: ["vela2"]))
        let (client, mock, events) = (harness.client, harness.mock, harness.events)
        await client.connect()
        await harness.expectSent("CAP LS 302", "NICK vela", "USER vela 0 * vela")

        mock.receive(":irc.test 433 * vela :Nickname is already in use")
        await harness.expectSent("NICK vela2")
        mock.receive(":irc.test 433 * vela2 :Nickname is already in use")
        await harness.expectSent("NICK vela_")
        // A stale reply about a nick we no longer use is ignored.
        mock.receive(":irc.test 433 * vela2 :Nickname is already in use")
        mock.receive(":irc.test 432 * vela_ :Erroneous nickname")
        await harness.expectSent("NICK vela__")
        #expect(await client.currentNick == "vela__")

        mock.receive(":irc.test CAP * LS :")
        await harness.expectSent("CAP END")
        mock.receive(":irc.test 001 vela__ :Welcome")
        #expect(await events.next { if case .registered(let nick) = $0 { nick } else { nil } } == "vela__")
        #expect(await client.currentNick == "vela__")

        // After registration a 433 is just reported, not acted upon.
        mock.receive(":irc.test 433 vela__ vela :Nickname is already in use")
        _ = await events.next { if case .message(let m, _) = $0, m.command == "433", m.params[0] == "vela__" { true } else { nil } }
        #expect(await mock.nextSentLine(timeout: .milliseconds(50)) == nil)
    }

    @Test func nickFallbackIsBounded() async {
        let harness = Harness(config())
        await harness.client.connect()
        await harness.expectSent("CAP LS 302", "NICK vela", "USER vela 0 * vela")
        var nick = "vela"
        var attempts = 0
        while attempts < 20 {
            harness.mock.receive(":irc.test 433 * \(nick) :Nickname is already in use")
            guard let line = await harness.mock.nextSentLine(timeout: .milliseconds(500)), line.hasPrefix("NICK ") else { break }
            nick = String(line.dropFirst(5))
            attempts += 1
        }
        // nick_, nick__, nick___ and two random numeric suffixes.
        #expect(attempts == 5)
        let reason = await harness.events.next { if case .disconnected(let reason) = $0 { reason } else { nil } }
        #expect(reason?.contains("No available nickname") == true)
    }

    @Test func bouncerBindBeforeCapEnd() async {
        let harness = Harness(config(bouncerNetworkID: "42"))
        await harness.client.connect()
        await harness.expectSent("CAP LS 302", "NICK vela", "USER vela 0 * vela")
        harness.mock.receive(":soju CAP * LS :soju.im/bouncer-networks soju.im/bouncer-networks-notify")
        await harness.expectSent("CAP REQ :soju.im/bouncer-networks soju.im/bouncer-networks-notify")
        harness.mock.receive(":soju CAP * ACK :soju.im/bouncer-networks soju.im/bouncer-networks-notify")
        await harness.expectSent("BOUNCER BIND 42", "CAP END")
    }

    @Test func stsOnPlaintextIsReported() async {
        let harness = Harness(config(useTLS: false))
        await harness.client.connect()
        await harness.expectSent("CAP LS 302", "NICK vela", "USER vela 0 * vela")
        harness.mock.receive(":irc.test CAP * LS :sts=port=6697,duration=300 batch")
        let policy = await harness.events.next { event -> (UInt16, Int?)? in
            if case .stsPolicy(let port, let duration) = event { (port, duration) } else { nil }
        }
        #expect(policy?.0 == 6697)
        // `sts` itself is never requested.
        await harness.expectSent("CAP REQ batch")
    }

    @Test func stsOnTLSReportsDuration() async {
        let harness = Harness(config(useTLS: true))
        await harness.client.connect()
        harness.mock.receive(":irc.test CAP * LS :sts=duration=86400")
        let policy = await harness.events.next { event -> (UInt16, Int?)? in
            if case .stsPolicy(let port, let duration) = event { (port, duration) } else { nil }
        }
        #expect(policy?.0 == 6697)
        #expect(policy?.1 == 86400)
    }

    @Test func connectFailureIsReported() async {
        let mock = MockTransport(openError: IRCTransportError.connectionFailed("Connection refused"))
        let client = IRCClient(config: config()) { _ in mock }
        let events = EventRecorder(client.events)
        await client.connect()
        #expect(await events.next { if case .disconnected(let reason) = $0 { reason } else { nil } } == "Connection refused")
        #expect(await client.state == .disconnected)
    }

    @Test func connectTimeoutCoversRegistration() async {
        let harness = Harness(config(connectTimeout: .milliseconds(80)))
        await harness.client.connect()
        let reason = await harness.events.next { if case .disconnected(let reason) = $0 { reason } else { nil } }
        #expect(reason == "Connection timed out")
        #expect(await eventually { harness.mock.isClosed })
    }
}

// MARK: - Runtime behavior

@Suite(.timeLimit(.minutes(1))) struct IRCClientRuntimeTests {
    @Test func pingIsAnsweredAndNotEmitted() async {
        let harness = Harness(config())
        await harness.connectAndRegister()
        harness.mock.receive("PING :irc.test")
        await harness.expectSent("PONG irc.test")
        harness.mock.receive("PING :two words")
        await harness.expectSent("PONG :two words")
        harness.mock.receive(":irc.test NOTICE vela :marker")
        _ = await harness.events.next { if case .message(let m, _) = $0, m.command == "NOTICE" { true } else { nil } }
        #expect(!harness.events.messages.contains { $0.0.command == "PING" })
    }

    @Test func keepalivePingAndTimeout() async {
        let harness = Harness(config(pingInterval: .milliseconds(60), pingTimeout: .milliseconds(80)))
        await harness.connectAndRegister()

        // Silence → our PING; answering it keeps the connection alive and the
        // PONG is consumed.
        let ping = await harness.mock.nextSentLine(where: { $0.hasPrefix("PING ") })
        let token = ping.map { String($0.dropFirst(5)) } ?? ""
        #expect(token.hasPrefix("vela-ping-"))
        harness.mock.receive(":irc.test PONG irc.test :\(token)")

        // Silence again → second PING; no answer → timeout.
        _ = await harness.mock.nextSentLine(where: { $0.hasPrefix("PING ") })
        let reason = await harness.events.next { if case .disconnected(let reason) = $0 { reason } else { nil } }
        #expect(reason?.hasPrefix("Ping timeout") == true)
        #expect(!harness.events.messages.contains { $0.0.command == "PONG" })
    }

    @Test func batchTracking() async {
        let harness = Harness(config())
        let (mock, events) = (harness.mock, harness.events)
        await harness.connectAndRegister(caps: "batch")

        mock.receive(":irc.test BATCH +outer chathistory #vela")
        mock.receive("@batch=outer :irc.test BATCH +inner netsplit irc.a irc.b")
        mock.receive("@batch=inner :alice!a@h QUIT :irc.a irc.b")
        mock.receive("@batch=outer :bob!b@h PRIVMSG #vela :history")
        mock.receive(":irc.test BATCH -inner")
        mock.receive(":irc.test BATCH -outer")
        mock.receive(":carol!c@h PRIVMSG #vela :live")

        let outer = await events.next { if case .batchStarted(let b) = $0 { b } else { nil } }
        #expect(outer == IRCBatch(id: "outer", type: "chathistory", params: ["#vela"]))
        let inner = await events.next { if case .batchStarted(let b) = $0 { b } else { nil } }
        #expect(inner?.parentID == "outer")
        #expect(inner?.type == "netsplit")
        #expect(inner?.params == ["irc.a", "irc.b"])

        let quit = await events.next { if case .message(let m, let b) = $0, m.command == "QUIT" { b?.id ?? "none" } else { nil } }
        #expect(quit == "outer")
        let history = await events.next { if case .message(let m, let b) = $0, m.params.last == "history" { b?.id ?? "none" } else { nil } }
        #expect(history == "outer")
        #expect(await events.next { if case .batchEnded(let b) = $0 { b.id } else { nil } } == "inner")
        #expect(await events.next { if case .batchEnded(let b) = $0 { b.id } else { nil } } == "outer")
        let live = await events.next { if case .message(let m, let b) = $0, m.params.last == "live" { (m, b) } else { nil } }
        #expect(live != nil)
        #expect(live?.1 == nil)
        #expect(!events.messages.contains { $0.0.command == "BATCH" })
    }

    @Test func danglingBatchesEndOnDisconnect() async {
        let harness = Harness(config())
        await harness.connectAndRegister(caps: "batch")
        harness.mock.receive(":irc.test BATCH +b1 chathistory #vela")
        _ = await harness.events.next { if case .batchStarted = $0 { true } else { nil } }
        harness.mock.finish()
        #expect(await harness.events.next { if case .batchEnded(let b) = $0 { b.id } else { nil } } == "b1")
        #expect(await harness.events.next { if case .disconnected(let r) = $0 { r } else { nil } } == "Connection closed by server")
    }

    @Test func ctcpVersionReply() async {
        let harness = Harness(config())
        await harness.connectAndRegister()
        harness.mock.receive(":alice!a@host PRIVMSG vela :\u{01}VERSION\u{01}")
        await harness.expectSent("NOTICE alice :\u{01}VERSION Vela test\u{01}")
        harness.mock.receive(":alice!a@host PRIVMSG vela :\u{01}PING 1234567\u{01}")
        await harness.expectSent("NOTICE alice :\u{01}PING 1234567\u{01}")
        harness.mock.receive(":alice!a@host PRIVMSG vela :\u{01}CLIENTINFO\u{01}")
        await harness.expectSent("NOTICE alice :\u{01}CLIENTINFO ACTION CLIENTINFO PING TIME VERSION\u{01}")
        // The requests are still emitted for the UI.
        for _ in 0..<3 {
            let ctcp = await harness.events.next { event -> Bool? in
                if case .message(let m, _) = event, m.command == "PRIVMSG", CTCP.parse(m.params.last ?? "") != nil { true } else { nil }
            }
            #expect(ctcp == true)
        }
    }

    @Test func ctcpIsNotAnsweredForHistoryActionsOrSelf() async {
        let harness = Harness(config())
        await harness.connectAndRegister(caps: "batch")
        harness.mock.receive(":irc.test BATCH +h chathistory vela")
        harness.mock.receive("@batch=h :alice!a@host PRIVMSG vela :\u{01}VERSION\u{01}")
        harness.mock.receive(":irc.test BATCH -h")
        harness.mock.receive("@time=2001-01-01T00:00:00.000Z :alice!a@host PRIVMSG vela :\u{01}VERSION\u{01}")
        harness.mock.receive(":alice!a@host PRIVMSG vela :\u{01}ACTION waves\u{01}")
        harness.mock.receive(":vela!v@host PRIVMSG alice :\u{01}VERSION\u{01}")
        harness.mock.receive(":alice!a@host PRIVMSG vela :\u{01}TIME\u{01}")
        let reply = await harness.mock.nextSentLine()
        #expect(reply?.hasPrefix("NOTICE alice :\u{01}TIME ") == true)
    }

    @Test func ctcpRepliesAreRateLimited() async {
        let harness = Harness(config())
        await harness.connectAndRegister()
        for _ in 0..<10 {
            harness.mock.receive(":flooder!f@h PRIVMSG vela :\u{01}VERSION\u{01}")
        }
        harness.mock.receive(":irc.test NOTICE vela :marker")
        _ = await harness.events.next { if case .message(let m, _) = $0, m.params.last == "marker" { true } else { nil } }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(harness.mock.sentLines.filter { $0.hasPrefix("NOTICE flooder") }.count == 3)
    }

    @Test func capNewAndDelAfterRegistration() async {
        let harness = Harness(config())
        let (mock, events) = (harness.mock, harness.events)
        await harness.connectAndRegister()

        mock.receive(":irc.test CAP vela NEW :away-notify some-other-cap")
        await harness.expectSent("CAP REQ away-notify")
        mock.receive(":irc.test CAP vela ACK :away-notify")
        #expect(await events.next { if case .capabilitiesChanged(let caps) = $0 { caps } else { nil } } == Set(["away-notify"]))
        #expect(await harness.client.enabledCapabilities == ["away-notify"])

        mock.receive(":irc.test CAP vela DEL :away-notify")
        #expect(await events.next { if case .capabilitiesChanged(let caps) = $0 { caps } else { nil } } == Set<String>())
        // No CAP END after registration.
        #expect(!mock.sentLines.dropFirst(4).contains("CAP END"))
    }

    @Test func tracksOwnNickAndAccount() async {
        let harness = Harness(config())
        await harness.connectAndRegister()
        harness.mock.receive(":Vela!v@h NICK newvela")  // case-insensitive match
        #expect(await harness.events.next { if case .nickChanged(let nick) = $0 { nick } else { nil } } == "newvela")
        #expect(await harness.client.currentNick == "newvela")
        harness.mock.receive(":someone!s@h NICK other")
        harness.mock.receive(":newvela!v@h ACCOUNT acct")
        harness.mock.receive(":irc.test NOTICE newvela :marker")
        _ = await harness.events.next { if case .message(let m, _) = $0, m.params.last == "marker" { true } else { nil } }
        #expect(await harness.client.currentNick == "newvela")
        #expect(await harness.client.account == "acct")
        harness.mock.receive(":newvela!v@h ACCOUNT *")
        harness.mock.receive(":irc.test NOTICE newvela :marker2")
        _ = await harness.events.next { if case .message(let m, _) = $0, m.params.last == "marker2" { true } else { nil } }
        #expect(await harness.client.account == nil)
    }

    @Test func messagesAreHeldUntilRegistered() async {
        let harness = Harness(config())
        await harness.client.connect()
        await harness.expectSent("CAP LS 302", "NICK vela", "USER vela 0 * vela")
        let sendTask = Task { await harness.client.send(IRCMessage("JOIN", "#vela")) }
        try? await Task.sleep(for: .milliseconds(30))
        harness.mock.receive(":irc.test CAP * LS :")
        await harness.expectSent("CAP END")
        harness.mock.receive(":irc.test 001 vela :Welcome")
        await harness.expectSent("JOIN #vela")
        await sendTask.value
    }

    @Test func clientTagsStrippedWithoutMessageTags() async {
        let harness = Harness(config())
        await harness.connectAndRegister()
        await harness.client.send(IRCMessage(tags: ["+draft/reply": "abc", "label": "x"], command: "PRIVMSG", params: ["#c", "hi"]))
        await harness.expectSent("PRIVMSG #c hi")
        await harness.client.send(IRCMessage(tags: ["+typing": "active"], command: "TAGMSG", params: ["#c"]))
        await harness.client.send(IRCMessage("PRIVMSG", "#c", "after"))
        await harness.expectSent("PRIVMSG #c after")
    }

    @Test func clientTagsKeptWithMessageTags() async {
        let harness = Harness(config())
        await harness.connectAndRegister(caps: "message-tags")
        await harness.client.send(IRCMessage(tags: ["+typing": "active"], command: "TAGMSG", params: ["#c"]))
        await harness.expectSent("@+typing=active TAGMSG #c")
    }

    @Test func floodControlSpacesMessages() async {
        let policy = IRCFloodPolicy(burst: 2, interval: .milliseconds(100))
        let harness = Harness(config(floodPolicy: policy))
        await harness.connectAndRegister()
        let start = ContinuousClock.now
        for index in 0..<4 {
            await harness.client.send(IRCMessage("PRIVMSG", "#c", "m\(index)"))
        }
        let elapsed = ContinuousClock.now - start
        // Two go out immediately, the next two wait ~100 ms each.
        #expect(elapsed >= .milliseconds(170))
        #expect(harness.mock.sentLines.suffix(4) == ["PRIVMSG #c m0", "PRIVMSG #c m1", "PRIVMSG #c m2", "PRIVMSG #c m3"])
    }

    @Test func sendRawSplitsLines() async {
        let harness = Harness(config())
        await harness.connectAndRegister()
        await harness.client.sendRaw("JOIN #a\r\nJOIN #b\n\nMODE #a +n")
        await harness.expectSent("JOIN #a", "JOIN #b", "MODE #a +n")
    }

    @Test func disconnectSendsQuit() async {
        let harness = Harness(config())
        await harness.connectAndRegister()
        await harness.client.disconnect(reason: "See you later")
        await harness.expectSent("QUIT :See you later")
        let clean = await harness.events.next { if case .disconnected(let reason) = $0 { reason == nil } else { nil } }
        #expect(clean == true)
        #expect(await harness.client.state == .disconnected)
        #expect(await eventually { harness.mock.isClosed })
        // Sending while disconnected is a no-op.
        await harness.client.send(IRCMessage("PRIVMSG", "#c", "nope"))
        #expect(!harness.mock.sentLines.contains("PRIVMSG #c nope"))
    }

    @Test func userDisconnectIsCleanEvenIfServerClosesFirst() async {
        let harness = Harness(config())
        await harness.connectAndRegister()
        let mock = harness.mock
        mock.setResponder { line in
            if line.hasPrefix("QUIT") { mock.finish() }
            return []
        }
        mock.receive("ERROR :Closing Link: vela (Quit: bye)")
        await harness.client.disconnect(reason: "bye")
        let clean = await harness.events.next { if case .disconnected(let reason) = $0 { reason == nil } else { nil } }
        #expect(clean == true)
    }

    @Test func serverErrorBecomesDisconnectReason() async {
        let harness = Harness(config())
        await harness.connectAndRegister()
        harness.mock.receive("ERROR :Closing Link: vela (K-Lined)")
        harness.mock.finish()
        let reason = await harness.events.next { if case .disconnected(let reason) = $0 { reason } else { nil } }
        #expect(reason == "Closing Link: vela (K-Lined)")
    }

    @Test func reconnectUsesFreshTransportAndState() async {
        let factory = MockTransportFactory()
        let client = IRCClient(config: config(), transportFactory: factory.makeTransport)
        let events = EventRecorder(client.events)

        await client.connect()
        let first = await factory.waitForTransport(count: 1)
        first?.receive(":irc.test CAP * LS :batch")
        first?.receive(":irc.test CAP * ACK :batch")
        first?.receive(":irc.test 001 vela :Welcome")
        _ = await events.next { if case .registered = $0 { true } else { nil } }
        #expect(await client.enabledCapabilities == ["batch"])
        first?.finish(throwing: IRCTransportError.connectionFailed("Connection reset by peer"))
        #expect(await events.next { if case .disconnected(let r) = $0 { r } else { nil } } == "Connection reset by peer")

        await client.connect()
        let second = await factory.waitForTransport(count: 2)
        #expect(second !== first)
        #expect(await client.enabledCapabilities.isEmpty)
        #expect(await second?.nextSentLine() == "CAP LS 302")
        second?.receive(":irc.test 001 vela :Welcome back")
        #expect(await events.next { if case .registered(let nick) = $0 { nick } else { nil } } == "vela")
        #expect(await client.state == .connected)
    }

    @Test func connectIsIgnoredWhileConnected() async {
        let factory = MockTransportFactory()
        let client = IRCClient(config: config(), transportFactory: factory.makeTransport)
        await client.connect()
        await client.connect()
        #expect(factory.transports.count == 1)
    }

    @Test func defaultCapabilitiesAndConfigDefaults() {
        #expect(IRCClient.defaultCapabilities.contains("draft/chathistory"))
        #expect(IRCClient.defaultCapabilities.contains("soju.im/bouncer-networks"))
        #expect(!IRCClient.defaultCapabilities.contains("draft/typing"))
        let config = IRCClientConfig(host: "h", nick: "Véla[away]")
        #expect(config.port == 6697)
        #expect(config.useTLS)
        #expect(config.username == "vlaaway")
        #expect(config.realname == "Véla[away]")
        #expect(config.requestedCapabilities == IRCClient.defaultCapabilities)
    }

    @Test func redaction() {
        #expect(IRCClient.redacted(IRCMessage("OPER", "admin", "secret")).params == ["admin", "********"])
        #expect(IRCClient.redacted(IRCMessage("AUTHENTICATE", "+")).params == ["+"])
        #expect(IRCClient.redacted(IRCMessage("PRIVMSG", "#c", "hi")).params == ["#c", "hi"])
    }
}
