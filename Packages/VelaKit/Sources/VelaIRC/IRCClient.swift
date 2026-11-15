// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Outbound rate limiting: a token bucket holding `burst` messages that
/// refills one token every `interval`.
public struct IRCFloodPolicy: Sendable, Hashable {
    public var burst: Int
    public var interval: Duration

    public init(burst: Int = 5, interval: Duration = .milliseconds(500)) {
        self.burst = max(1, burst)
        self.interval = interval
    }

    public static let `default` = IRCFloodPolicy()
    /// No throttling (tests, trusted bouncers).
    public static let disabled = IRCFloodPolicy(burst: 1, interval: .zero)

    var isDisabled: Bool { interval <= .zero }
}

/// Everything needed to connect and register with one server.
public struct IRCClientConfig: Sendable, Hashable {
    public var host: String
    public var port: UInt16
    public var useTLS: Bool
    public var allowInvalidCertificates: Bool
    public var nick: String
    /// Tried in order when `nick` is taken during registration, before
    /// falling back to `nick_`, `nick__`, … variants.
    public var alternateNicks: [String]
    public var username: String
    public var realname: String
    public var serverPassword: String?
    public var sasl: SASLMechanism?
    /// Disconnect when SASL is configured but fails or is unavailable.
    public var saslRequired: Bool
    public var clientIdentity: ClientIdentity?
    public var requestedCapabilities: Set<String>
    /// soju: `BOUNCER BIND <id>` is sent before `CAP END` when set and
    /// `soju.im/bouncer-networks` is enabled.
    public var bouncerNetworkID: String?
    /// CTCP VERSION reply text.
    public var versionReply: String
    /// Automatically answer CTCP VERSION/PING/TIME/CLIENTINFO.
    public var respondsToCTCP: Bool
    /// Silence after which the client sends its own PING. Zero disables
    /// keepalive.
    public var pingInterval: Duration
    /// How long to wait for any traffic after our PING before giving up.
    public var pingTimeout: Duration
    /// Covers TCP/TLS setup *and* registration (until 001). Zero disables it.
    public var connectTimeout: Duration
    public var floodPolicy: IRCFloodPolicy

    public init(
        host: String,
        port: UInt16 = 6697,
        useTLS: Bool = true,
        nick: String,
        alternateNicks: [String] = [],
        username: String? = nil,
        realname: String? = nil,
        serverPassword: String? = nil,
        sasl: SASLMechanism? = nil,
        saslRequired: Bool = false,
        allowInvalidCertificates: Bool = false,
        clientIdentity: ClientIdentity? = nil,
        requestedCapabilities: Set<String> = IRCClient.defaultCapabilities,
        bouncerNetworkID: String? = nil,
        versionReply: String = "Vela IRC (macOS)",
        respondsToCTCP: Bool = true,
        pingInterval: Duration = .seconds(90),
        pingTimeout: Duration = .seconds(60),
        connectTimeout: Duration = .seconds(30),
        floodPolicy: IRCFloodPolicy = .default
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.allowInvalidCertificates = allowInvalidCertificates
        self.nick = nick
        self.alternateNicks = alternateNicks
        self.username = username.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultUsername(for: nick)
        self.realname = realname.flatMap { $0.isEmpty ? nil : $0 } ?? nick
        self.serverPassword = serverPassword
        self.sasl = sasl
        self.saslRequired = saslRequired
        self.clientIdentity = clientIdentity
        self.requestedCapabilities = requestedCapabilities
        self.bouncerNetworkID = bouncerNetworkID
        self.versionReply = versionReply
        self.respondsToCTCP = respondsToCTCP
        self.pingInterval = pingInterval
        self.pingTimeout = pingTimeout
        self.connectTimeout = connectTimeout
        self.floodPolicy = floodPolicy
    }

    /// A username derived from the nick: ASCII alphanumerics only, at most
    /// 10 characters, never empty.
    static func defaultUsername(for nick: String) -> String {
        let filtered = nick.unicodeScalars.filter { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))
        }
        let name = String(String.UnicodeScalarView(filtered.prefix(10))).lowercased()
        return name.isEmpty ? "vela" : name
    }
}

public enum IRCConnectionState: Sendable, Hashable {
    case disconnected
    /// Opening the TCP/TLS connection.
    case connecting
    /// Connected; CAP negotiation / SASL / NICK+USER in progress.
    case registering
    /// Registered (001 received).
    case connected
}

/// An open IRCv3 `BATCH`.
public struct IRCBatch: Sendable, Hashable {
    public var id: String
    public var type: String
    public var params: [String]
    /// The enclosing batch, for nested batches.
    public var parentID: String?
    /// Tags of the `BATCH +id` line (e.g. `label` for labeled-response).
    public var tags: [String: String]

    public init(id: String, type: String, params: [String] = [], parentID: String? = nil, tags: [String: String] = [:]) {
        self.id = id
        self.type = type
        self.params = params
        self.parentID = parentID
        self.tags = tags
    }
}

public enum IRCClientEvent: Sendable, Equatable {
    case stateChanged(IRCConnectionState)
    /// The connection ended: an error/server reason, or nil after a
    /// `disconnect(reason:)` initiated by the client.
    case disconnected(reason: String?)
    /// Registration completed (001).
    case registered(nick: String)
    /// Our own nick changed.
    case nickChanged(String)
    case isupportChanged(ISupport)
    /// The set of currently enabled capabilities.
    case capabilitiesChanged(Set<String>)
    case saslFinished(success: Bool, account: String?, message: String)
    /// The server advertised an STS policy. On a plaintext connection
    /// `port` is the secure port to reconnect to; on a TLS connection `port`
    /// is the current port and `duration` (seconds) is how long to remember
    /// that the host requires TLS.
    case stsPolicy(port: UInt16, duration: Int?)
    case batchStarted(IRCBatch)
    case batchEnded(IRCBatch)
    /// Every inbound message not consumed internally (PING, our PONGs, CAP,
    /// AUTHENTICATE and BATCH are consumed). `batch` is the outermost open
    /// batch the message belongs to.
    case message(IRCMessage, batch: IRCBatch?)
    /// Every outbound message, after it was written. Secrets (PASS,
    /// AUTHENTICATE payloads, OPER passwords) are redacted.
    case sent(IRCMessage)
}

/// One IRC connection: transport, registration, capability negotiation,
/// SASL, keepalive, flood control and batch tracking. Higher layers observe
/// `events` and drive it with `send(_:)`.
public actor IRCClient {
    public static let defaultCapabilities: Set<String> = [
        "server-time",
        "message-tags",
        "echo-message",
        "batch",
        "labeled-response",
        "draft/chathistory",
        "chathistory",
        "away-notify",
        "account-notify",
        "account-tag",
        "extended-join",
        "multi-prefix",
        "userhost-in-names",
        "setname",
        "chghost",
        "invite-notify",
        "cap-notify",
        "sasl",
        "sts",  // understood but never requested (informational)
        "draft/message-redaction",
        "draft/read-marker",
        "soju.im/bouncer-networks",
        "soju.im/bouncer-networks-notify",
        "znc.in/playback",
        "znc.in/self-message",
        "znc.in/server-time-iso",
        "standard-replies",
    ]

    /// Prefix of the tokens used for our keepalive PINGs; matching PONGs are
    /// consumed and not emitted.
    static let pingTokenPrefix = "vela-ping-"

    /// Events for the lifetime of the client (across reconnects). Single
    /// consumer.
    public nonisolated let events: AsyncStream<IRCClientEvent>
    private nonisolated let eventSink: AsyncStream<IRCClientEvent>.Continuation

    private var config: IRCClientConfig
    private let transportFactory: @Sendable (IRCClientConfig) -> any IRCTransport

    public private(set) var state: IRCConnectionState = .disconnected
    public private(set) var currentNick: String
    public private(set) var isupport = ISupport()
    public private(set) var account: String?
    private var caps: CapNegotiator

    public var enabledCapabilities: Set<String> { caps.enabled }
    /// Capabilities advertised by the server, with their values.
    public var availableCapabilities: [String: String] { caps.available }
    public var configuration: IRCClientConfig { config }
    /// Batches currently open, by reference tag.
    public var openBatches: [String: IRCBatch] { batches }

    // Connection
    private var generation = 0
    private var transport: (any IRCTransport)?
    private var readTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var pumpTask: Task<Void, Never>?

    // Registration
    private var registered = false
    private var capEndSent = false
    private var sasl: SASLAuthenticator?
    private var saslDone = false
    private var nickCandidates: [String] = []
    private var nickCandidateIndex = 0
    private var serverError: String?
    /// Set by `disconnect(reason:)` so the teardown reports a clean quit even
    /// if the server closes first.
    private var quitting = false
    private var batches: [String: IRCBatch] = [:]

    // Keepalive
    private var lastReceived = ContinuousClock.now
    private var pingSentAt: ContinuousClock.Instant?
    private var pingCounter = 0

    // Flood control
    private struct Outbound {
        var message: IRCMessage
        var completion: CheckedContinuation<Void, Never>?
    }
    private var outbox: [Outbound] = []
    private var floodTokens: Double = 0
    private var floodLastRefill = ContinuousClock.now
    private var ctcpReplyTimes: [ContinuousClock.Instant] = []

    public init(
        config: IRCClientConfig,
        transportFactory: @escaping @Sendable (IRCClientConfig) -> any IRCTransport = { NetworkTransport(config: $0) }
    ) {
        self.config = config
        self.transportFactory = transportFactory
        currentNick = config.nick
        caps = CapNegotiator(desired: config.requestedCapabilities)
        (events, eventSink) = AsyncStream<IRCClientEvent>.makeStream()
    }

    deinit {
        eventSink.finish()
        readTask?.cancel()
        pingTask?.cancel()
        connectTimeoutTask?.cancel()
        pumpTask?.cancel()
    }

    // MARK: Public API

    /// Connects and registers. Never throws; progress and failures are
    /// reported through `events`. Does nothing unless disconnected.
    public func connect() async {
        guard state == .disconnected else { return }
        generation &+= 1
        let gen = generation
        resetConnectionState()
        setState(.connecting)

        let transport = transportFactory(config)
        self.transport = transport
        startConnectTimeout(gen)

        let stream: AsyncThrowingStream<String, Error>
        do {
            stream = try await transport.open()
        } catch {
            if gen == generation {
                await teardown(gen, reason: Self.describe(error))
            } else {
                await transport.close()
            }
            return
        }
        guard gen == generation, state == .connecting else {
            await transport.close()
            return
        }

        setState(.registering)
        lastReceived = .now
        startReader(stream, gen)
        await beginRegistration(gen)
    }

    /// Sends QUIT (when registered) and closes the connection. Emits
    /// `.disconnected(reason: nil)`.
    public func disconnect(reason: String? = nil) async {
        guard state != .disconnected else { return }
        let gen = generation
        quitting = true
        if registered {
            let quit = IRCMessage(command: "QUIT", params: reason.map { [$0] } ?? [])
            await write(quit, gen)
        }
        await teardown(gen, reason: nil)
    }

    /// Queues `message` behind flood control and returns once it has been
    /// written (or dropped because the connection ended). Messages sent
    /// before registration completes are held until 001. Messages sent while
    /// disconnected are dropped.
    public func send(_ message: IRCMessage) async {
        guard state != .disconnected else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            outbox.append(Outbound(message: message, completion: continuation))
            startPumpIfNeeded()
        }
    }

    /// Parses and sends a raw line. Embedded newlines split it into several
    /// lines; unparsable lines are ignored.
    public func sendRaw(_ line: String) async {
        for part in line.split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == "\r\n" }) {
            guard let message = IRCMessage(line: String(part)) else { continue }
            await send(message)
        }
    }

    /// Replaces the configuration used by the next `connect()` (e.g. an STS
    /// upgrade). Flood policy changes apply immediately.
    public func updateConfig(_ config: IRCClientConfig) {
        self.config = config
        if !registered {
            caps.desired = config.requestedCapabilities
        }
    }

    // MARK: Connection lifecycle

    private func resetConnectionState() {
        caps = CapNegotiator(desired: config.requestedCapabilities)
        isupport = ISupport()
        account = nil
        sasl = nil
        saslDone = false
        capEndSent = false
        registered = false
        currentNick = config.nick
        nickCandidates = Self.nickCandidates(for: config)
        nickCandidateIndex = 0
        serverError = nil
        quitting = false
        batches = [:]
        pingSentAt = nil
        floodTokens = Double(config.floodPolicy.burst)
        floodLastRefill = .now
        ctcpReplyTimes = []
    }

    private func setState(_ newState: IRCConnectionState) {
        guard state != newState else { return }
        state = newState
        emit(.stateChanged(newState))
    }

    private func emit(_ event: IRCClientEvent) {
        eventSink.yield(event)
    }

    /// Ends connection `gen` (idempotent): cancels timers, drops queued
    /// messages, closes open batches and the transport, and reports.
    private func teardown(_ gen: Int, reason: String?) async {
        guard gen == generation, state != .disconnected else { return }
        generation &+= 1

        readTask?.cancel()
        pingTask?.cancel()
        connectTimeoutTask?.cancel()
        pumpTask?.cancel()
        readTask = nil
        pingTask = nil
        connectTimeoutTask = nil
        pumpTask = nil

        let pending = outbox
        outbox = []
        for item in pending { item.completion?.resume() }

        // Close dangling batches innermost-first so consumers can flush.
        let dangling = batches.values.sorted { depth(of: $0) > depth(of: $1) }
        batches = [:]
        for batch in dangling { emit(.batchEnded(batch)) }

        registered = false
        let closing = transport
        transport = nil
        setState(.disconnected)
        emit(.disconnected(reason: quitting ? nil : reason))
        await closing?.close()
    }

    private func startReader(_ stream: AsyncThrowingStream<String, Error>, _ gen: Int) {
        readTask = Task { [weak self] in
            do {
                for try await line in stream {
                    guard let self else { return }
                    await self.handleLine(line, gen)
                }
                await self?.connectionEnded(gen, error: nil)
            } catch {
                await self?.connectionEnded(gen, error: error)
            }
        }
    }

    private func connectionEnded(_ gen: Int, error: (any Error)?) async {
        let reason = serverError ?? error.map(Self.describe) ?? "Connection closed by server"
        await teardown(gen, reason: reason)
    }

    private func startConnectTimeout(_ gen: Int) {
        let timeout = config.connectTimeout
        guard timeout > .zero else { return }
        connectTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            await self?.connectTimedOut(gen)
        }
    }

    private func connectTimedOut(_ gen: Int) async {
        guard gen == generation, !registered else { return }
        await teardown(gen, reason: "Connection timed out")
    }

    // MARK: Registration

    private func beginRegistration(_ gen: Int) async {
        await write(IRCMessage(command: "CAP", params: ["LS", "302"]), gen)
        if let password = config.serverPassword, !password.isEmpty {
            await write(IRCMessage(command: "PASS", params: [password]), gen)
        }
        await write(IRCMessage(command: "NICK", params: [currentNick]), gen)
        await write(IRCMessage(command: "USER", params: [config.username, "0", "*", config.realname]), gen)
    }

    static func nickCandidates(for config: IRCClientConfig) -> [String] {
        var seen: Set<String> = [config.nick.lowercased()]
        var candidates: [String] = []
        func add(_ nick: String) {
            guard !nick.isEmpty, seen.insert(nick.lowercased()).inserted else { return }
            candidates.append(nick)
        }
        config.alternateNicks.forEach(add)
        for count in 1...3 { add(config.nick + String(repeating: "_", count: count)) }
        for _ in 0..<2 { add(config.nick + String(Int.random(in: 100...999))) }
        return candidates
    }

    private func tryNextNick(_ message: IRCMessage, _ gen: Int) async {
        // `<client> <nick> :reason` — ignore replies about a nick we're no
        // longer trying (437 can also be about a channel).
        if message.params.count >= 3, !isupport.caseMapping.equal(message.params[1], currentNick) { return }
        guard nickCandidateIndex < nickCandidates.count else {
            await teardown(gen, reason: "No available nickname (\(message.params.last ?? message.command))")
            return
        }
        currentNick = nickCandidates[nickCandidateIndex]
        nickCandidateIndex += 1
        await write(IRCMessage(command: "NICK", params: [currentNick]), gen)
    }

    private func handleWelcome(_ message: IRCMessage, _ gen: Int) {
        registered = true
        capEndSent = true
        if let nick = message.params.first, !nick.isEmpty, nick != "*" { currentNick = nick }
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        setState(.connected)
        emit(.registered(nick: currentNick))
        startPingTimer(gen)
        startPumpIfNeeded()
    }

    // MARK: Capability negotiation

    private func handleCap(_ message: IRCMessage, _ gen: Int) async {
        let event = caps.handle(message)
        switch event {
        case .lsPartial, .listPartial, .ignored:
            return
        case .lsComplete:
            reportSTS()
            await requestCapabilities(gen)
        case .acknowledged:
            emit(.capabilitiesChanged(caps.enabled))
        case .rejected:
            await requestCapabilities(gen)
        case .added(let added):
            if added["sts"] != nil { reportSTS() }
            await requestCapabilities(gen)
        case .removed, .list:
            emit(.capabilitiesChanged(caps.enabled))
        }
        await finishNegotiationIfReady(gen)
    }

    private func requestCapabilities(_ gen: Int) async {
        for line in caps.nextRequests() {
            await write(line, gen)
        }
    }

    private func reportSTS() {
        guard let policy = caps.stsPolicy else { return }
        if config.useTLS {
            if let duration = policy.duration {
                emit(.stsPolicy(port: config.port, duration: duration))
            }
        } else if let port = policy.port {
            emit(.stsPolicy(port: port, duration: policy.duration))
        }
    }

    /// Runs SASL and `BOUNCER BIND` as needed, then sends `CAP END` once.
    private func finishNegotiationIfReady(_ gen: Int) async {
        guard gen == generation, !registered, !capEndSent, caps.canEnd else { return }

        if let mechanism = config.sasl, !saslDone {
            if sasl != nil { return }  // exchange in progress
            if caps.isEnabled("sasl") {
                if let offered = caps.saslMechanisms, !offered.contains(mechanism.name) {
                    let text = "The server does not support SASL \(mechanism.name) (offers \(offered.joined(separator: ", ")))"
                    guard await saslCompleted(success: false, message: text, gen) else { return }
                } else {
                    var authenticator = SASLAuthenticator(mechanism: mechanism)
                    let start = authenticator.start()
                    sasl = authenticator
                    await write(start, gen)
                    return
                }
            } else {
                guard await saslCompleted(success: false, message: "The server does not support SASL", gen) else { return }
            }
        }

        guard gen == generation, !capEndSent else { return }
        capEndSent = true
        if let networkID = config.bouncerNetworkID, caps.isEnabled("soju.im/bouncer-networks") {
            await write(IRCMessage(command: "BOUNCER", params: ["BIND", networkID]), gen)
        }
        await write(IRCMessage(command: "CAP", params: ["END"]), gen)
    }

    /// Records the SASL result. Returns false when the connection was torn
    /// down because SASL is required.
    private func saslCompleted(success: Bool, message: String, _ gen: Int) async -> Bool {
        saslDone = true
        emit(.saslFinished(success: success, account: success ? account : nil, message: message))
        if !success && config.saslRequired {
            await teardown(gen, reason: "SASL authentication failed: \(message)")
            return false
        }
        return true
    }

    private func handleSASL(_ message: IRCMessage, _ gen: Int) async {
        guard var authenticator = sasl, !saslDone else {
            // Outside an exchange we still track the account.
            if message.command == IRCNumeric.loggedIn, message.params.count >= 3 {
                account = message.params[2]
            } else if message.command == IRCNumeric.loggedOut {
                account = nil
            }
            return
        }
        let outcome = authenticator.handle(message)
        sasl = authenticator
        switch outcome {
        case .send(let lines):
            // If this was an abort (`AUTHENTICATE *`), the server answers 906.
            for line in lines { await write(line, gen) }
        case .loggedIn(let name):
            account = name
        case .loggedOut:
            account = nil
        case .mechanisms, .none:
            break
        case .succeeded(let text):
            guard await saslCompleted(success: true, message: text, gen) else { return }
            await finishNegotiationIfReady(gen)
        case .failed(let text):
            guard await saslCompleted(success: false, message: text, gen) else { return }
            await finishNegotiationIfReady(gen)
        }
    }

    // MARK: Inbound

    private func handleLine(_ line: String, _ gen: Int) async {
        guard gen == generation else { return }
        lastReceived = .now
        pingSentAt = nil
        guard let message = IRCMessage(line: line) else { return }
        await process(message, gen)
    }

    private func process(_ message: IRCMessage, _ gen: Int) async {
        switch message.command {
        case "PING":
            await write(IRCMessage(command: "PONG", params: message.params), gen)
            return
        case "PONG":
            if message.params.last?.hasPrefix(Self.pingTokenPrefix) == true { return }
        case "CAP":
            await handleCap(message, gen)
            return
        case "AUTHENTICATE":
            await handleSASL(message, gen)
            return
        case "BATCH":
            handleBatch(message)
            return
        case "ERROR":
            serverError = message.params.last ?? "Closing link"
        case IRCNumeric.welcome:
            handleWelcome(message, gen)
        case IRCNumeric.isupport:
            if message.params.count >= 2 {
                let tokens = message.params.dropFirst().dropLast(message.params.count > 2 ? 1 : 0)
                isupport.apply(tokens)
                emit(.isupportChanged(isupport))
            }
        case IRCNumeric.nicknameInUse, IRCNumeric.erroneousNickname,
             IRCNumeric.nickCollision, IRCNumeric.unavailableResource:
            if !registered {
                await tryNextNick(message, gen)
            }
        case IRCNumeric.loggedIn, IRCNumeric.loggedOut, IRCNumeric.nickLocked,
             IRCNumeric.saslSuccess, IRCNumeric.saslFail, IRCNumeric.saslTooLong,
             IRCNumeric.saslAborted, IRCNumeric.saslAlready, IRCNumeric.saslMechanisms:
            await handleSASL(message, gen)
        case "NICK":
            if let source = message.source, let newNick = message.params.first,
               isupport.caseMapping.equal(source.nick, currentNick)
            {
                currentNick = newNick
                emit(.nickChanged(newNick))
            }
        case "ACCOUNT":
            if let source = message.source, isupport.caseMapping.equal(source.nick, currentNick),
               let name = message.params.first
            {
                account = name == "*" ? nil : name
            }
        default:
            break
        }
        guard gen == generation else { return }

        let batch = outermostBatch(for: message)
        if message.command == "PRIVMSG" {
            replyToCTCP(message, batch: batch)
        }
        emit(.message(message, batch: batch))
    }

    // MARK: Batches

    private func handleBatch(_ message: IRCMessage) {
        guard let reference = message.params.first, reference.count > 1 else { return }
        let id = String(reference.dropFirst())
        if reference.hasPrefix("+") {
            let batch = IRCBatch(
                id: id,
                type: message.param(1) ?? "",
                params: Array(message.params.dropFirst(2)),
                parentID: message.batchID,
                tags: message.tags
            )
            batches[id] = batch
            emit(.batchStarted(batch))
        } else if reference.hasPrefix("-"), let batch = batches.removeValue(forKey: id) {
            emit(.batchEnded(batch))
        }
    }

    private func outermostBatch(for message: IRCMessage) -> IRCBatch? {
        guard let id = message.batchID, var batch = batches[id] else { return nil }
        var hops = 0
        while let parentID = batch.parentID, let parent = batches[parentID], hops < 32 {
            batch = parent
            hops += 1
        }
        return batch
    }

    private func depth(of batch: IRCBatch) -> Int {
        var depth = 0
        var current = batch
        while let parentID = current.parentID, let parent = batches[parentID], depth < 32 {
            current = parent
            depth += 1
        }
        return depth
    }

    // MARK: CTCP

    private func replyToCTCP(_ message: IRCMessage, batch: IRCBatch?) {
        guard config.respondsToCTCP,
              batch == nil,
              message.params.count >= 2,
              let ctcp = CTCP.parse(message.params[1]),
              ctcp.command != "ACTION",
              let source = message.source,
              !source.nick.isEmpty,
              !isupport.caseMapping.equal(source.nick, currentNick)
        else { return }
        // Don't answer replayed history (bouncer playback without batches).
        if let time = message.serverTime, Date().timeIntervalSince(time) > 60 { return }

        let reply: String?
        switch ctcp.command {
        case "VERSION": reply = config.versionReply
        case "PING": reply = ctcp.argument
        case "TIME": reply = Self.ctcpTime()
        case "CLIENTINFO": reply = "ACTION CLIENTINFO PING TIME VERSION"
        default: return
        }

        // At most 3 automatic replies per 10 seconds.
        let now = ContinuousClock.now
        ctcpReplyTimes.removeAll { now - $0 > .seconds(10) }
        guard ctcpReplyTimes.count < 3 else { return }
        ctcpReplyTimes.append(now)

        enqueue(IRCMessage(command: "NOTICE", params: [source.nick, CTCP.encode(ctcp.command, reply)]))
    }

    private static func ctcpTime() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: Date())
    }

    // MARK: Keepalive

    private func startPingTimer(_ gen: Int) {
        pingTask?.cancel()
        pingTask = nil
        guard config.pingInterval > .zero, config.pingTimeout > .zero else { return }
        pingTask = Task { [weak self] in
            while true {
                guard let deadline = await self?.pingDeadline(gen) else { return }
                do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
                await self?.pingTick(gen)
            }
        }
    }

    private func pingDeadline(_ gen: Int) -> ContinuousClock.Instant? {
        guard gen == generation, registered else { return nil }
        if let sent = pingSentAt { return sent + config.pingTimeout }
        return lastReceived + config.pingInterval
    }

    private func pingTick(_ gen: Int) async {
        guard gen == generation else { return }
        let now = ContinuousClock.now
        if let sent = pingSentAt {
            if now - sent >= config.pingTimeout {
                let seconds = Int((config.pingTimeout + config.pingInterval).components.seconds)
                await teardown(gen, reason: "Ping timeout (\(seconds) seconds)")
            }
        } else if now - lastReceived >= config.pingInterval {
            pingSentAt = now
            pingCounter += 1
            await write(IRCMessage(command: "PING", params: ["\(Self.pingTokenPrefix)\(pingCounter)"]), gen)
        }
    }

    // MARK: Outbound

    /// Queues without waiting for the write (used from the read loop).
    private func enqueue(_ message: IRCMessage) {
        outbox.append(Outbound(message: message, completion: nil))
        startPumpIfNeeded()
    }

    private func startPumpIfNeeded() {
        guard pumpTask == nil, registered, !outbox.isEmpty else { return }
        let gen = generation
        pumpTask = Task { [weak self] in
            await self?.runPump(gen)
        }
    }

    private func runPump(_ gen: Int) async {
        while gen == generation, registered, !outbox.isEmpty {
            if let wait = takeFloodToken() {
                do { try await Task.sleep(for: wait) } catch { break }
                continue
            }
            guard gen == generation, !outbox.isEmpty else { break }
            let item = outbox.removeFirst()
            await write(item.message, gen, queued: true)
            item.completion?.resume()
        }
        if gen == generation {
            pumpTask = nil
        }
    }

    /// Takes a token, or returns how long to wait for one.
    private func takeFloodToken() -> Duration? {
        let policy = config.floodPolicy
        guard !policy.isDisabled else { return nil }
        let now = ContinuousClock.now
        let elapsed = now - floodLastRefill
        floodTokens = min(Double(policy.burst), floodTokens + elapsed / policy.interval)
        floodLastRefill = now
        if floodTokens >= 1 {
            floodTokens -= 1
            return nil
        }
        return policy.interval * (1 - floodTokens)
    }

    /// Writes immediately (protocol traffic bypasses flood control). On
    /// failure the connection is torn down.
    private func write(_ message: IRCMessage, _ gen: Int, queued: Bool = false) async {
        guard gen == generation, let transport else { return }
        guard let prepared = queued ? prepareForWire(message) : message else { return }
        do {
            try await transport.send(prepared.serialized)
            emit(.sent(Self.redacted(prepared)))
        } catch {
            await teardown(gen, reason: Self.describe(error))
        }
    }

    /// Drops tags the server can't accept given the enabled capabilities.
    private func prepareForWire(_ message: IRCMessage) -> IRCMessage? {
        var message = message
        if !caps.isEnabled("message-tags") {
            if message.command == "TAGMSG" { return nil }
            message.tags = message.tags.filter { !$0.key.hasPrefix("+") }
        }
        if !caps.isEnabled("labeled-response") {
            message.tags.removeValue(forKey: "label")
        }
        return message
    }

    static func redacted(_ message: IRCMessage) -> IRCMessage {
        var copy = message
        switch message.command {
        case "PASS":
            copy.params = message.params.map { _ in "********" }
        case "AUTHENTICATE":
            if let first = message.params.first,
               !["+", "*", "PLAIN", "EXTERNAL"].contains(first.uppercased())
            {
                copy.params = ["********"]
            }
        case "OPER":
            if message.params.count >= 2 {
                copy.params[1] = "********"
            }
        default:
            break
        }
        return copy
    }

    static func describe(_ error: any Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
