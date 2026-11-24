// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaIRC
import VelaStore

/// What a session needs from its owner (the `AppModel` in the app, a fake in tests).
@MainActor
public protocol SessionHost: AnyObject {
    func clientConfig(for session: NetworkSession) -> IRCClientConfig
    func isBufferVisible(_ id: BufferID) -> Bool
    func activeBuffer(in session: NetworkSession) -> BufferModel?
    func session(_ session: NetworkSession, didReceiveNotable line: ChatLine, in buffer: BufferModel)
    func session(_ session: NetworkSession, didUpdateBouncerNetworks networks: [BouncerNetwork])
    func sessionDidChangeConfig(_ session: NetworkSession)
    func sessionDidChangeUnreadCounts(_ session: NetworkSession)
    /// The connection changed: its state, or whether Vela means to be
    /// connected (``NetworkSession/expectsConnection``). Optional.
    func sessionDidChangeConnection(_ session: NetworkSession)
    /// A channel or conversation was opened: joined, messaged, reopened or
    /// restored at launch. Optional.
    func session(_ session: NetworkSession, didOpen buffer: BufferModel)
    /// You sent a message from the composer (not a command). Optional.
    func session(_ session: NetworkSession, didSendComposerMessageIn buffer: BufferModel)
    /// A line was added to `buffer` (live or replayed, never one loaded
    /// from the database), for chat logs. Optional.
    func session(_ session: NetworkSession, didAdd line: ChatLine, to buffer: BufferModel)
    /// `line` was deleted (IRCv3 `REDACT`) by `nick`, for chat logs. Optional.
    func session(_ session: NetworkSession, didRedact line: ChatLine, by nick: String?, reason: String?, at time: Date, isHistory: Bool, in buffer: BufferModel)
    var behavior: SessionBehavior { get }
    /// Whether messages are saved to and loaded from the database
    /// (`history.save`). Read for every line, so keep it cheap. Optional:
    /// hosts that don't say save and load, as Vela always used to.
    var historyStorage: HistoryStorage { get }
    /// Where messages just written to the database go (Spotlight's index
    /// of messages), read once per batch written. Optional: nil.
    var savedMessagesSink: (any SavedMessagesSink)? { get }
    /// A channel was removed or a conversation closed (``NetworkSession/close(_:)``).
    /// Optional.
    func session(_ session: NetworkSession, didClose buffer: BufferModel)
}

/// User preferences that influence protocol behavior.
nonisolated public struct SessionBehavior: Sendable, Equatable {
    public var autoReconnect = true
    public var sendTypingIndicators = true
    public var highlightWords: [String] = []
    public var scrollbackInMemory = 1000
    public var historyFetchLimit = 100
    /// How bans and quiets mask a nick (`moderation.banMask`).
    public var banMaskStyle: BanMaskStyle = .host
    /// The reason kicks give when none is typed (`moderation.kickReason`).
    public var defaultKickReason = ""

    public init() {}
}

/// A network advertised by a soju bouncer (`soju.im/bouncer-networks`).
nonisolated public struct BouncerNetwork: Identifiable, Hashable, Sendable {
    public var id: String
    public var attributes: [String: String]
    public var name: String { attributes["name"] ?? attributes["host"] ?? id }
    public var state: String? { attributes["state"] }
}

/// One IRC connection and all of its buffers.
@Observable
public final class NetworkSession: Identifiable {
    public nonisolated let id: UUID
    public internal(set) var config: NetworkConfig
    public internal(set) var connectionState: IRCConnectionState = .disconnected
    public internal(set) var nick: String
    public internal(set) var isupport = ISupport()
    public internal(set) var capabilities: Set<String> = []
    public private(set) var account: String?
    public private(set) var isAway = false
    public private(set) var lastError: String?
    public let serverBuffer: BufferModel
    /// Channels, then queries, each in display order (see `sortOrder`).
    public internal(set) var buffers: [BufferModel] = []
    public private(set) var bouncerNetworks: [BouncerNetwork] = []

    @ObservationIgnored public weak var host: SessionHost?
    @ObservationIgnored private let database: VelaDatabase?
    @ObservationIgnored private let transportFactory: (@Sendable (IRCClientConfig) -> any IRCTransport)?
    @ObservationIgnored private var client: IRCClient?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var typingSweepTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectAttempt = 0
    @ObservationIgnored private var userRequestedDisconnect = false
    /// A connection was asked for (by you or by auto-connect) and you
    /// haven't disconnected since.
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var connectedAt: Date?
    /// The name the server gave itself when you connected (the source of
    /// its welcome), such as `tantalum.libera.chat`. Kept across
    /// reconnects; see ``serverNames``.
    @ObservationIgnored public private(set) var serverName: String?
    @ObservationIgnored var bufferIndex: [String: BufferModel] = [:]
    @ObservationIgnored private var pendingNames: [String: [String: Member]] = [:]
    @ObservationIgnored private var historyBatches: [String: HistoryBatch] = [:]
    /// The message being handled came in a batch of older history, asked
    /// for by scrolling up: it never counts as unread.
    @ObservationIgnored private var handlingOlderHistory = false
    /// The Dock badge and other unread totals are due an update (replayed
    /// history updates them a few times a second, not once a line).
    @ObservationIgnored private var unreadCountsChangeScheduled = false
    @ObservationIgnored private var bouncerBatchIDs: Set<String> = []
    @ObservationIgnored private var lastTypingSent: [BufferID: (state: TypingState, at: Date)] = [:]
    @ObservationIgnored private var pendingRecords: [MessageRecord] = []
    /// The latest database write; each waits for the one before (see
    /// `writeBuffer`).
    @ObservationIgnored private var bufferWrites: Task<Void, Never>?
    /// The newest line received since launch that history would save, in
    /// any buffer (see ``catchUpPoint(for:received:)``).
    @ObservationIgnored private var newestReceivedAt: Date?
    /// Channels Vela sent PART for (removed, or parted on a bouncer after
    /// connecting) whose PART the server hasn't confirmed yet (folded
    /// names). A bouncer's join into one meanwhile is ignored, and what was
    /// said in a removed one is dropped, so neither can open it again.
    @ObservationIgnored var partingChannels: Set<String> = []
    /// Channels you rejoined or reopened while disconnected from a bouncer
    /// (folded names), joined after connecting: Vela doesn't send JOINs to
    /// bouncers otherwise, and the bouncer may have left them.
    @ObservationIgnored var pendingJoins: Set<String> = []
    /// Detaches sent to the bouncer and not yet confirmed, by folded name
    /// (see NetworkSession+Bouncer.swift).
    @ObservationIgnored var detachRequests: [String: DetachRequest] = [:]
    /// How long a detach waits for the bouncer to confirm it before Vela
    /// says it didn't work.
    @ObservationIgnored var detachTimeout: Duration = .seconds(10)
    /// Until when the bouncer's service (`*status`, `BouncerServ`) is
    /// answering a detach: its replies go to the server console instead of
    /// opening a conversation.
    @ObservationIgnored var serviceRepliesUntil: Date?
    /// The auto-join entries of channels you left on a network without a
    /// bouncer, and where they were (folded names). Joining puts each back.
    @ObservationIgnored var leftAutoJoin: [String: LeftAutoJoin] = [:]
    /// Detached channels taken out of the list (Hide Channel), in the order
    /// they were hidden. They're still on the bouncer; showing one (or
    /// opening it any other way) puts it back where it was.
    public internal(set) var hiddenChannels: [HiddenChannel] = []
    /// Where channel keys are read from. The app sets its own.
    @ObservationIgnored var keychain: Keychain = .shared
    @ObservationIgnored private var highlightMatcher = HighlightMatcher(nick: "", words: [])
    @ObservationIgnored var ignoreMatcher = IgnoreMatcher(masks: [])
    /// CTCP requests you sent that haven't been answered yet.
    @ObservationIgnored var pendingCTCP: [PendingCTCPRequest] = []
    /// Lookups of someone's `user@host` (for a ban) waiting for USERHOST.
    @ObservationIgnored var userHostWaiters: [String: [CheckedContinuation<String?, Never>]] = [:]
    /// The folded nicks USERHOST was sent for, in order.
    @ObservationIgnored var userHostQueue: [String] = []
    /// How long a USERHOST lookup waits for its answer.
    @ObservationIgnored var userHostTimeout: Duration = .seconds(4)

    public init(
        config: NetworkConfig,
        database: VelaDatabase?,
        transportFactory: (@Sendable (IRCClientConfig) -> any IRCTransport)? = nil
    ) {
        self.id = config.id
        self.config = config
        self.nick = config.nick
        self.database = database
        self.transportFactory = transportFactory
        self.serverBuffer = BufferModel(
            id: BufferID(networkID: config.id, foldedName: BufferID.serverBufferName),
            name: config.name,
            kind: .server
        )
        serverBuffer.selfNick = { [unowned self] in self.nick }
        rebuildMatchers()
    }

    // MARK: Derived state

    public var displayName: String {
        if !config.name.isEmpty { return config.name }
        return isupport.network ?? config.host
    }

    /// The names this network and its server go by, folded as the network
    /// compares nicks: the address you connect to, the server's own name,
    /// the network's name (yours for it, and the one it announces), and a
    /// bouncer's service (`*status`, BouncerServ). A line "from" one of
    /// these is the server or network talking, never a person: Catch me up
    /// and Recap leave such lines out of what they send to an AI model,
    /// which is never told a server's or network's name.
    public var serverNames: Set<String> {
        let names = [config.host, serverName, config.name, isupport.network, bouncerServiceNick]
        return Set(names.compactMap { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            return fold(name)
        })
    }

    public var isConnected: Bool { connectionState == .connected }

    /// Not connected, but a connection is on its way: connecting or
    /// registering, or disconnected with one due on its own (an auto-connect
    /// network Vela was just launched with, or a retry after a drop).
    public var isAwaitingConnection: Bool {
        switch connectionState {
        case .connecting, .registering: true
        case .connected: false
        case .disconnected: !userRequestedDisconnect && (config.autoConnect || reconnectTask != nil)
        }
    }

    /// Whether Vela means to be connected to this network: it connects
    /// automatically, or it was connected (or asked to connect) since Vela
    /// started, and you haven't disconnected it since. Disconnecting for
    /// sleep or when Vela quits counts as disconnecting. Waiting to
    /// reconnect after a dropped connection doesn't.
    public var expectsConnection: Bool {
        !userRequestedDisconnect && (config.autoConnect || wantsConnection)
    }

    /// Soju "control" connection that lists bouncer networks rather than chatting.
    public var isBouncerControl: Bool {
        config.bouncerKind == .soju && config.parentNetworkID == nil && config.bouncerNetworkID == nil
    }

    public var allBuffers: [BufferModel] { [serverBuffer] + buffers }

    public var channels: [BufferModel] { buffers.filter { $0.kind == .channel } }
    public var queries: [BufferModel] { buffers.filter { $0.kind == .query } }

    public var totalUnread: Int { allBuffers.reduce(0) { $0 + ($1.isMuted ? 0 : $1.unreadCount) } }
    public var totalHighlights: Int { allBuffers.reduce(0) { $0 + $1.highlightCount } }

    public func buffer(named name: String) -> BufferModel? {
        bufferIndex[fold(name)]
    }

    public func buffer(id: BufferID) -> BufferModel? {
        if id == serverBuffer.id { return serverBuffer }
        return bufferIndex[id.foldedName]
    }

    public func supports(_ capability: String) -> Bool { capabilities.contains(capability) }

    public var supportsChatHistory: Bool {
        supports("draft/chathistory") || supports("chathistory")
    }

    public var supportsClientTags: Bool {
        guard supports("message-tags") else { return false }
        return true
    }

    public func allowsClientTag(_ tag: String) -> Bool {
        guard supportsClientTags else { return false }
        guard let deny = isupport.tokens["CLIENTTAGDENY"] else { return true }
        let rules = deny.split(separator: ",").map(String.init)
        let bare = tag.hasPrefix("+") ? String(tag.dropFirst()) : tag
        var allowed = true
        for rule in rules {
            if rule == "*" { allowed = false }
            else if rule == "-\(bare)" { allowed = true }
            else if rule == bare { allowed = false }
        }
        return allowed
    }

    public var supportsReactions: Bool { allowsClientTag("+draft/react") }
    public var supportsReplies: Bool { allowsClientTag("+draft/reply") }
    public var supportsTyping: Bool { allowsClientTag("+typing") }
    public var supportsRedaction: Bool { supports("draft/message-redaction") }

    // MARK: Lifecycle

    /// Restores buffers known from previous runs (offline, unjoined).
    /// Detached channels come back detached, and hidden ones stay out of
    /// the list (``hiddenChannels``).
    public func restoreBuffers() async {
        guard let database else { return }
        guard let records = try? await database.buffers(networkID: id) else { return }
        for record in records where record.kind != BufferKind.server.rawValue {
            let folded = fold(record.name)
            autoRejoin[folded] = record.autoRejoin
            if record.isHidden {
                hiddenChannels.append(HiddenChannel(record: record, id: BufferID(networkID: id, foldedName: folded)))
                continue
            }
            let kind = BufferKind(rawValue: record.kind) ?? .channel
            let buffer = ensureBuffer(name: record.name, kind: kind, persist: false)
            buffer.isMuted = record.isMuted
            buffer.lastReadAt = record.lastReadAt
            buffer.sortOrder = record.sortOrder
            buffer.isDetached = kind == .channel && record.isDetached
            if let left = record.leftAutoJoin { leftAutoJoin[folded] = left }
        }
        sortBuffers()
    }

    @ObservationIgnored var autoRejoin: [String: Bool] = [:]
    /// Recent lines still loading from the store (``recentHistoryLoaded()``).
    private let historyLoads = PendingWork()

    public func connect() {
        userRequestedDisconnect = false
        wantsConnection = true
        reconnectTask?.cancel()
        reconnectTask = nil
        host?.sessionDidChangeConnection(self)
        guard connectionState == .disconnected, let host else { return }
        let clientConfig = host.clientConfig(for: self)
        lastError = nil
        if let client {
            Task {
                await client.updateConfig(clientConfig)
                await client.connect()
            }
        } else {
            let client = transportFactory.map { IRCClient(config: clientConfig, transportFactory: $0) }
                ?? IRCClient(config: clientConfig)
            self.client = client
            startEventLoop(client)
            Task { await client.connect() }
        }
    }

    public func disconnect(reason: String? = nil) {
        userRequestedDisconnect = true
        wantsConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        host?.sessionDidChangeConnection(self)
        guard let client else { return }
        Task { await client.disconnect(reason: reason ?? "Vela — https://github.com/r3volution11/Vela-IRC") }
    }

    public func reconnect() {
        guard let client else {
            connect()
            return
        }
        userRequestedDisconnect = false
        wantsConnection = true
        reconnectTask?.cancel()
        host?.sessionDidChangeConnection(self)
        reconnectTask = Task { [weak self] in
            await client.disconnect(reason: "Reconnecting")
            try? await Task.sleep(for: .milliseconds(300))
            self?.userRequestedDisconnect = false
            self?.connect()
        }
    }

    /// Stops everything (used when a network is removed or the app quits).
    public func shutdown() {
        disconnect(reason: nil)
        flushPendingRecords()
        eventTask?.cancel()
        typingSweepTask?.cancel()
    }

    /// Network reachability changed or the Mac woke up.
    public func networkPathBecameAvailable() {
        guard connectionState == .disconnected, !userRequestedDisconnect, config.autoConnect || reconnectTask != nil else { return }
        reconnectAttempt = 0
        connect()
    }

    public func updateConfig(_ newConfig: NetworkConfig) {
        let needsReconnect = newConfig.host != config.host || newConfig.port != config.port
            || newConfig.useTLS != config.useTLS || newConfig.nick != config.nick
            || newConfig.saslKind != config.saslKind || newConfig.saslAccount != config.saslAccount
        config = newConfig
        serverBuffer.name = displayName
        rebuildMatchers()
        if needsReconnect && connectionState != .disconnected { reconnect() }
    }

    // MARK: Event loop

    private func startEventLoop(_ client: IRCClient) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in client.events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    func handle(_ event: IRCClientEvent) {
        switch event {
        case .stateChanged(let state):
            connectionState = state
            if state == .connecting {
                info("Connecting to \(config.host):\(config.port)\(config.useTLS ? " (TLS)" : "")…", in: serverBuffer)
            }
            host?.sessionDidChangeConnection(self)
        case .disconnected(let reason):
            connectionState = .disconnected
            connectedAt = nil
            for buffer in buffers where buffer.kind == .channel {
                buffer.isJoined = false
                buffer.removeAllMembers()
            }
            historyBatches.values.forEach { $0.buffer.isLoadingHistory = false }
            historyBatches = [:]
            partingChannels = []
            requeueUnconfirmedDetaches()
            if let reason {
                lastError = reason
                error("Disconnected: \(reason)", in: serverBuffer)
            } else {
                info("Disconnected", in: serverBuffer)
            }
            for buffer in channels { info("Disconnected", in: buffer) }
            scheduleReconnectIfNeeded()
            host?.sessionDidChangeConnection(self)
        case .registered(let nick):
            self.nick = nick
            connectedAt = Date()
            reconnectAttempt = 0
            rebuildMatchers()
            info("Connected as \(nick)", in: serverBuffer)
            afterRegistration()
        case .nickChanged(let newNick):
            nick = newNick
            rebuildMatchers()
        case .isupportChanged(let support):
            isupport = support
            if let network = support.network, config.name.isEmpty { serverBuffer.name = network }
            let rankFunction: (Member) -> Int = { [support] member in support.rank(ofSymbol: member.topPrefix) }
            for buffer in channels { buffer.memberRank = rankFunction }
        case .capabilitiesChanged(let caps):
            capabilities = caps
        case .saslFinished(let success, let account, let message):
            if success {
                self.account = account
                info("Authenticated\(account.map { " as \($0)" } ?? "") — \(message)", in: serverBuffer)
            } else {
                error("SASL authentication failed: \(message)", in: serverBuffer)
            }
        case .stsPolicy(let port, _):
            guard !config.useTLS else { break }
            info("Server requires a secure connection (STS); upgrading to TLS on port \(port).", in: serverBuffer)
            config.useTLS = true
            config.port = port
            host?.sessionDidChangeConfig(self)
            reconnect()
        case .batchStarted(let batch):
            handleBatchStart(batch)
        case .batchEnded(let batch):
            handleBatchEnd(batch)
        case .message(let message, let batch):
            handle(message, batch: batch)
        case .sent(let message):
            handleSent(message)
        }
    }

    private func scheduleReconnectIfNeeded() {
        guard !userRequestedDisconnect, host?.behavior.autoReconnect ?? true else { return }
        reconnectAttempt += 1
        let base = min(120.0, pow(2.0, Double(min(reconnectAttempt, 7))))
        let delay = base * Double.random(in: 0.8...1.2)
        info("Reconnecting in \(Int(delay.rounded())) seconds…", in: serverBuffer)
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.connectionState == .disconnected else { return }
            self.connect()
        }
    }

    private func afterRegistration() {
        if isBouncerControl, supports("soju.im/bouncer-networks") {
            sendRaw("BOUNCER LISTNETWORKS")
        }
        // Channels to (re)join: configured auto-join plus restored/open
        // channels. Detached and hidden channels wait to be joined by hand.
        var toJoin: [(String, String?)] = []
        var seen = Set<String>(channels.filter(\.isDetached).map(\.id.foldedName) + hiddenChannels.map(\.id.foldedName))
        for channel in config.autoJoin {
            let folded = fold(channel.name)
            guard seen.insert(folded).inserted else { continue }
            let key = channel.hasKey ? keychain.secret(account: Keychain.channelKeyAccount(networkID: id, channel: folded)) : nil
            toJoin.append((channel.name, key))
        }
        for buffer in channels where autoRejoin[buffer.id.foldedName] ?? true {
            if seen.insert(buffer.id.foldedName).inserted { toJoin.append((buffer.name, nil)) }
        }
        // What you did on a bouncer while disconnected goes to it now: parts
        // of channels you removed and detaches of channels you left.
        sendPendingBouncerChanges()
        if config.bouncerKind == .none {
            for (channel, key) in toJoin {
                send(IRCMessage(command: "JOIN", params: key.map { [channel, $0] } ?? [channel]))
            }
        } else {
            // Bouncers rejoin channels themselves. Only channels you rejoined
            // while disconnected need a JOIN (one the bouncer is still in
            // ignores it).
            for folded in pendingJoins.sorted() {
                if let buffer = bufferIndex[folded] { sendJoin(buffer) }
            }
        }
        pendingJoins = []
        for command in config.performCommands {
            if let parsed = InputCommand.parse(command) { perform(parsed, in: serverBuffer, replyTo: nil) }
        }
        if supports("znc.in/playback") {
            let received = newestReceivedAt
            Task { [weak self] in
                guard let self, self.database != nil else { return }
                let since = await self.catchUpPoint(for: nil, received: received) ?? .distantPast
                let stamp = since == .distantPast ? "0" : String(Int(since.timeIntervalSince1970))
                self.sendRaw("PRIVMSG *playback :PLAY * \(stamp)")
            }
        }
        if supportsChatHistory {
            for query in queries { fetchLatestHistory(for: query) }
        }
    }

    // MARK: Inbound messages

    private func handle(_ message: IRCMessage, batch: IRCBatch?) {
        let historyBatch = batch.flatMap { historyBatches[$0.id] }
        let isHistory = historyBatch != nil || isPlayback(message)
        if let batch, historyBatch != nil { historyBatches[batch.id]?.count += 1 }
        handlingOlderHistory = historyBatch?.isOlder ?? false
        defer { handlingOlderHistory = false }

        switch message.command {
        case "PRIVMSG", "NOTICE": handleChat(message, isHistory: isHistory)
        case "TAGMSG": handleTagMessage(message, isHistory: isHistory)
        case "JOIN": handleJoin(message, isHistory: isHistory)
        case "PART": handlePart(message, isHistory: isHistory)
        case "KICK": handleKick(message, isHistory: isHistory)
        case "QUIT": handleQuit(message, isHistory: isHistory)
        case "NICK": handleNick(message, isHistory: isHistory)
        case "TOPIC": handleTopic(message, isHistory: isHistory)
        case "MODE": handleMode(message, isHistory: isHistory)
        case "INVITE":
            let channel = message.param(1) ?? ""
            info("\(message.source?.nick ?? "Someone") invited \(message.param(0) ?? "you") to \(channel)", in: host?.activeBuffer(in: self) ?? serverBuffer, kind: .invite)
        case "AWAY":
            guard let nick = message.source?.nick else { break }
            updateMember(nick) { $0.isAway = message.param(0) != nil }
        case "ACCOUNT":
            guard let nick = message.source?.nick else { break }
            let account = message.param(0).flatMap { $0 == "*" ? nil : $0 }
            updateMember(nick) { $0.account = account }
        case "CHGHOST":
            guard let nick = message.source?.nick, let user = message.param(0), let host = message.param(1) else { break }
            updateMember(nick) { $0.userHost = "\(user)@\(host)" }
        case "SETNAME":
            guard let nick = message.source?.nick else { break }
            updateMember(nick) { $0.realname = message.param(0) }
        case "REDACT":
            handleRedact(message, isHistory: isHistory)
        case "ERROR":
            error(message.param(0) ?? "Server error", in: serverBuffer)
        case "FAIL", "WARN", "NOTE":
            let description = message.params.last ?? ""
            let code = message.param(1).map { " [\($0)]" } ?? ""
            let text = "\(message.param(0) ?? "")\(code): \(description)"
            if message.command == "FAIL" { error(text, in: host?.activeBuffer(in: self) ?? serverBuffer) }
            else { info(text, in: serverBuffer) }
        case "BOUNCER":
            handleBouncer(message)
        case "PONG", "CAP", "AUTHENTICATE", "BATCH", "PING":
            break
        default:
            if message.command.count == 3, message.command.allSatisfy(\.isNumber) {
                handleNumeric(message)
            } else {
                info(message.params.dropFirst().joined(separator: " "), in: serverBuffer)
            }
        }
    }

    /// ZNC playback and soju backlog arrive with old server-time stamps.
    private func isPlayback(_ message: IRCMessage) -> Bool {
        guard let time = message.serverTime, let connectedAt else { return false }
        return time < connectedAt.addingTimeInterval(-5)
    }

    private func handleChat(_ message: IRCMessage, isHistory: Bool) {
        guard let source = message.source, let rawTarget = message.param(0), var text = message.param(1) else { return }
        let fromSelf = isSelf(source.nick)
        if !fromSelf, !ignoreMatcher.isEmpty, ignoreMatcher.matches(source.raw) { return }

        var kind: ChatLineKind = message.command == "NOTICE" ? .notice : .message
        if let ctcp = CTCP.parse(text) {
            if ctcp.command == "ACTION" {
                kind = .action
                text = ctcp.argument ?? ""
            } else {
                // Your own requests and automatic replies, echoed back:
                // sending one already said so.
                guard !isHistory, !fromSelf else { return }
                if message.command == "PRIVMSG" {
                    info("\(source.nick) requested CTCP \(ctcp.command)", in: host?.activeBuffer(in: self) ?? serverBuffer, kind: .ctcp)
                } else {
                    showCTCPReply(ctcp.command, argument: ctcp.argument, from: source.nick)
                }
                return
            }
        }

        // STATUSMSG targets like "@#channel".
        let statusPrefixes = Set(isupport.tokens["STATUSMSG"] ?? "")
        let target = String(rawTarget.drop(while: { statusPrefixes.contains($0) }))

        let destination: BufferModel?
        if isupport.isChannel(target) {
            if isParting(target) { return }
            // A bouncer can relay what's said in a channel you hid: it's
            // kept on disk for when the channel's shown again, but it never
            // brings the channel back by itself.
            destination = isHidden(target) ? nil : ensureBuffer(name: target, kind: .channel)
        } else if fromSelf {
            // Your detach command, echoed back by the bouncer.
            if isOwnBouncerCommand(to: target, text: text) { return }
            destination = ensureBuffer(name: target, kind: .query)
        } else if source.isServer || connectionState != .connected || source.nick == "*" || target == "*" {
            destination = serverBuffer
        } else if routesToConsole(source.nick) {
            // The bouncer answering a detach: no conversation for that.
            destination = serverBuffer
        } else if kind == .notice, self.buffer(named: source.nick) == nil {
            // Notices from services and the like go to the server buffer unless a query is open.
            destination = serverBuffer
        } else {
            let opens = self.buffer(named: source.nick) == nil
            let query = ensureBuffer(name: source.nick, kind: .query)
            // A private message sent while you were away, replayed by a
            // bouncer: a conversation it opens is all news to you.
            if opens, isHistory { query.lastReadAt = .distantPast }
            destination = query
        }

        if let destination { typingStopped(nick: source.nick, in: destination) }

        let isHighlight = !fromSelf && (destination?.kind ?? .channel) == .channel && highlightMatcher.matches(text)
        let line = ChatLine(
            msgid: message.msgid,
            time: message.serverTime ?? Date(),
            kind: kind,
            nick: source.nick,
            userHost: source.userHost,
            account: message.account,
            text: text,
            isSelf: fromSelf,
            isHighlight: isHighlight,
            replyTo: message.replyTo,
            tags: message.tags.filter { $0.key.hasPrefix("+") },
            isHistory: isHistory
        )
        guard let destination else {
            enqueue(line.record(networkID: id, bufferName: fold(target)))
            return
        }
        add(line, to: destination)
    }

    private func handleTagMessage(_ message: IRCMessage, isHistory: Bool) {
        guard let source = message.source, let target = message.param(0) else { return }
        let fromSelf = isSelf(source.nick)
        let bufferName = isupport.isChannel(target) ? target : (fromSelf ? target : source.nick)
        guard let buffer = self.buffer(named: bufferName) ?? (isupport.isChannel(target) ? nil : ensureBuffer(name: bufferName, kind: .query)) else { return }

        if let typing = message.tags["+typing"], !fromSelf, !isHistory {
            buffer.updateTyping(nick: source.nick, state: TypingState(rawValue: typing) ?? .done)
            startTypingSweep()
        }
        if let msgid = message.replyTo {
            if let emoji = message.tags["+draft/react"] ?? message.tags["+react"] {
                applyReaction(emoji: emoji, msgid: msgid, nick: source.nick, active: true, in: buffer)
            }
            if let emoji = message.tags["+draft/unreact"] {
                applyReaction(emoji: emoji, msgid: msgid, nick: source.nick, active: false, in: buffer)
            }
        }
    }

    private func handleJoin(_ message: IRCMessage, isHistory: Bool) {
        guard let source = message.source, let channel = message.param(0) else { return }
        let folded = fold(channel)
        let fromSelf = isSelf(source.nick)
        // A bouncer joins you into its channels as you connect, including
        // one Vela is parting (you removed or parted it while disconnected):
        // it stays closed, or left.
        if fromSelf, !isHistory, isBouncer, partingChannels.contains(folded) { return }
        if !fromSelf, isParting(channel) { return }
        // A hidden channel comes back only when the bouncer attaches it for
        // real: not on its join as you connect, before the detach Vela sent
        // reaches it.
        if isHidden(channel), !fromSelf || isHistory || detachRequests[folded] != nil { return }
        let buffer = ensureBuffer(name: channel, kind: .channel)
        let account = message.param(1).flatMap { $0 == "*" ? nil : $0 }
        let realname = message.param(2)
        if fromSelf, !isHistory {
            buffer.isJoined = true
            buffer.removeAllMembers()
            buffer.memberRank = { [isupport] in isupport.rank(ofSymbol: $0.topPrefix) }
            autoRejoin[buffer.id.foldedName] = true
            // Never read before (a first join): start reading here. History
            // from before it stays read, and what a bouncer replays after
            // it next time counts as unread, even if you never open it.
            if buffer.lastReadAt == nil { buffer.lastReadAt = message.serverTime ?? Date() }
            // The bouncer attached a detached channel (you joined it again,
            // or the bouncer or another client did).
            let reattached = buffer.isDetached && detachRequests[folded] == nil
            if reattached { buffer.isDetached = false }
            persistBuffer(buffer)
            if supportsChatHistory {
                fetchLatestHistory(for: buffer)
            } else if reattached {
                requestPlayback(for: buffer)
            }
        } else if !isHistory {
            buffer.setMember(Member(nick: source.nick, userHost: source.userHost, account: account ?? message.account, realname: realname), forKey: fold(source.nick))
        }
        let line = ChatLine(
            msgid: message.msgid, time: message.serverTime ?? Date(), kind: .join, nick: source.nick,
            userHost: source.userHost, account: account,
            text: "\(source.nick)\(source.userHost.map { " (\($0))" } ?? "") joined \(buffer.name)",
            isSelf: isSelf(source.nick), isHistory: isHistory
        )
        add(line, to: buffer)
    }

    private func handlePart(_ message: IRCMessage, isHistory: Bool) {
        guard let source = message.source, let channel = message.param(0) else { return }
        let fromSelf = isSelf(source.nick)
        let reason = message.param(1)
        // The bouncer leaving you in a channel it stays in (a detach), or
        // the server confirming a part Vela sent.
        let isDetach = fromSelf && !isHistory && confirmsDetach(of: channel, reason: reason)
        if fromSelf, !isHistory { partingChannels.remove(fold(channel)) }
        guard let buffer = buffer(named: channel) else { return }
        if fromSelf, !isHistory {
            buffer.isJoined = false
            buffer.removeAllMembers()
            buffer.typingExpiry = [:]
            buffer.refreshTyping()
            if isDetach {
                buffer.isDetached = true
                persistBuffer(buffer)
                info("You left \(buffer.name) here. \(bouncerName) stays in it and keeps its history; join it again to catch up.", in: buffer)
                return
            }
        } else if !isHistory {
            buffer.removeMember(forKey: fold(source.nick))
            buffer.clearTyping(nick: source.nick)
        }
        add(ChatLine(
            msgid: message.msgid, time: message.serverTime ?? Date(), kind: .part, nick: source.nick, userHost: source.userHost,
            text: "\(source.nick) left \(buffer.name)\(reason.map { " (\($0))" } ?? "")",
            isSelf: isSelf(source.nick), isHistory: isHistory
        ), to: buffer)
    }

    private func handleKick(_ message: IRCMessage, isHistory: Bool) {
        guard let channel = message.param(0), let kicked = message.param(1), let buffer = buffer(named: channel) else { return }
        let by = message.source?.nick ?? "Server"
        let reason = message.param(2)
        if !isHistory {
            if isSelf(kicked) {
                buffer.isJoined = false
                buffer.removeAllMembers()
            } else {
                buffer.removeMember(forKey: fold(kicked))
            }
        }
        add(ChatLine(
            msgid: message.msgid, time: message.serverTime ?? Date(), kind: .kick, nick: by,
            text: "\(by) kicked \(kicked) from \(buffer.name)\(reason.map { " (\($0))" } ?? "")",
            isSelf: isSelf(kicked), isHighlight: isSelf(kicked) && !isHistory, isHistory: isHistory
        ), to: buffer)
    }

    private func handleQuit(_ message: IRCMessage, isHistory: Bool) {
        guard let source = message.source else { return }
        let key = fold(source.nick)
        let reason = message.param(0)
        let text = "\(source.nick) quit\(reason.map { " (\($0))" } ?? "")"
        for buffer in buffers {
            let affected = buffer.kind == .channel ? buffer.memberMap[key] != nil : buffer.id.foldedName == key
            guard affected else { continue }
            if !isHistory { buffer.removeMember(forKey: key) }
            buffer.clearTyping(nick: source.nick)
            add(ChatLine(
                msgid: message.msgid, time: message.serverTime ?? Date(), kind: .quit, nick: source.nick,
                userHost: source.userHost, text: text, isHistory: isHistory
            ), to: buffer)
        }
    }

    private func handleNick(_ message: IRCMessage, isHistory: Bool) {
        guard let source = message.source, let newNick = message.param(0) else { return }
        let oldKey = fold(source.nick)
        let wasSelf = isSelf(source.nick)
        if wasSelf {
            nick = newNick
            rebuildMatchers()
        }
        let text = wasSelf ? "You are now known as \(newNick)" : "\(source.nick) is now known as \(newNick)"
        for buffer in buffers {
            let affected = buffer.kind == .channel ? buffer.memberMap[oldKey] != nil : buffer.id.foldedName == oldKey
            guard affected || wasSelf else { continue }
            buffer.renameMember(from: oldKey, to: fold(newNick), nick: newNick)
            buffer.clearTyping(nick: source.nick)
            add(ChatLine(
                msgid: message.msgid, time: message.serverTime ?? Date(), kind: .nick, nick: source.nick,
                text: text, isSelf: wasSelf, isHistory: isHistory
            ), to: buffer)
        }
        if wasSelf { info(text, in: serverBuffer, kind: .nick) }
    }

    private func handleTopic(_ message: IRCMessage, isHistory: Bool) {
        guard let channel = message.param(0), let buffer = buffer(named: channel) else { return }
        let topic = message.param(1) ?? ""
        let by = message.source?.nick ?? "Someone"
        if !isHistory {
            buffer.topic = topic.isEmpty ? nil : topic
            buffer.topicSetBy = by
        }
        add(ChatLine(
            msgid: message.msgid, time: message.serverTime ?? Date(), kind: .topic, nick: by,
            text: topic.isEmpty ? "\(by) cleared the topic" : "\(by) changed the topic to: \(topic)",
            isSelf: isSelf(by), isHistory: isHistory
        ), to: buffer)
    }

    private func handleMode(_ message: IRCMessage, isHistory: Bool) {
        guard let target = message.param(0), message.params.count >= 2 else { return }
        let by = message.source?.nick ?? "Server"
        let modeText = message.params.dropFirst().joined(separator: " ")
        guard isupport.isChannel(target), let buffer = buffer(named: target) else {
            info("\(by) set mode \(modeText) on \(target)", in: serverBuffer, kind: .mode)
            return
        }
        if !isHistory { applyChannelModes(Array(message.params.dropFirst()), to: buffer) }
        add(ChatLine(
            msgid: message.msgid, time: message.serverTime ?? Date(), kind: .mode, nick: by,
            text: "\(by) sets mode \(modeText)", isSelf: isSelf(by), isHistory: isHistory
        ), to: buffer)
    }

    private func applyChannelModes(_ params: [String], to buffer: BufferModel) {
        guard let modeString = params.first else { return }
        var args = params.dropFirst().makeIterator()
        let modes = isupport.channelModes
        let prefixModes = Set(isupport.prefixModes)
        var adding = true
        for char in modeString {
            switch char {
            case "+": adding = true
            case "-": adding = false
            default:
                if prefixModes.contains(char) {
                    guard let nick = args.next(), let symbol = isupport.symbol(forMode: char) else { continue }
                    let prefixSymbols = isupport.prefixSymbols
                    buffer.updateMember(forKey: fold(nick)) { member in
                        var symbols = Set(member.prefixes)
                        if adding { symbols.insert(symbol) } else { symbols.remove(symbol) }
                        member.prefixes = String(prefixSymbols.filter { symbols.contains($0) })
                    }
                } else if modes.list.contains(char) || modes.always.contains(char) || (adding && modes.whenSet.contains(char)) {
                    _ = args.next()
                }
            }
        }
    }

    private func handleRedact(_ message: IRCMessage, isHistory: Bool) {
        guard let target = message.param(0), let msgid = message.param(1) else { return }
        let name = isupport.isChannel(target) || !(message.source.map { !isSelf($0.nick) } ?? false) ? target : (message.source?.nick ?? target)
        guard let buffer = buffer(named: name), let index = buffer.lines.lastIndex(where: { $0.msgid == msgid }) else { return }
        let wasRedacted = buffer.lines[index].isRedacted
        buffer.lines[index].isRedacted = true
        if !wasRedacted {
            host?.session(
                self, didRedact: buffer.lines[index], by: message.source?.nick, reason: message.param(2),
                at: message.serverTime ?? Date(), isHistory: isHistory, in: buffer
            )
        }
        // Only saved messages have a row to flag (none when nothing loads).
        let key = buffer.id.storeKey
        if historyStorage.loads { writeBuffer { try await $0.markRedacted(msgid: msgid, in: key) } }
    }

    private func handleBouncer(_ message: IRCMessage) {
        guard message.param(0) == "NETWORK", let netid = message.param(1), let attrs = message.param(2) else { return }
        var networks = bouncerNetworks
        if attrs == "*" {
            networks.removeAll { $0.id == netid }
        } else {
            var parsed: [String: String] = [:]
            if let synthetic = IRCMessage(line: "@\(attrs) X") { parsed = synthetic.tags }
            if let index = networks.firstIndex(where: { $0.id == netid }) {
                networks[index].attributes.merge(parsed) { _, new in new }
            } else {
                networks.append(BouncerNetwork(id: netid, attributes: parsed))
            }
        }
        bouncerNetworks = networks
        if message.batchID == nil || !bouncerBatchIDs.contains(message.batchID!) {
            host?.session(self, didUpdateBouncerNetworks: networks)
        }
    }

    private func handleNumeric(_ message: IRCMessage) {
        let params = Array(message.params.dropFirst())   // drop our nick
        let text = params.joined(separator: " ")
        let active = host?.activeBuffer(in: self) ?? serverBuffer

        switch message.command {
        case "001", "002", "003", "004", "251", "252", "253", "254", "255", "265", "266", "250", "042", "396":
            if message.command == "001", let source = message.source?.nick, !source.isEmpty { serverName = source }
            info(text, in: serverBuffer)
        case "005":
            break
        case "375", "372", "376":
            info(message.params.last ?? "", in: serverBuffer, kind: .motd)
        case "422":
            info(message.params.last ?? "No MOTD", in: serverBuffer, kind: .motd)
        case "302":   // RPL_USERHOST
            let entries = UserHostReply.parse(message.params.last ?? "")
            for entry in entries { updateMember(entry.nick) { $0.userHost = entry.userHost } }
            // An answer to a lookup for a ban isn't shown.
            if !answerUserHostLookup(entries) { info(text, in: serverBuffer) }
        case "301":   // RPL_AWAY
            guard let nick = params.first else { break }
            let target = buffer(named: nick) ?? active
            info("\(nick) is away: \(params.last ?? "")", in: target)
        case "305":
            isAway = false
            info(message.params.last ?? "You are no longer marked as away", in: serverBuffer)
        case "306":
            isAway = true
            info(message.params.last ?? "You have been marked as away", in: serverBuffer)
        case "311", "312", "313", "317", "318", "319", "320", "330", "338", "378", "379", "671", "276", "314", "369":
            info(whoisText(message.command, params), in: active)
        case "324":   // RPL_CHANNELMODEIS
            if let channel = params.first, let buffer = buffer(named: channel) {
                buffer.modes = params.dropFirst().joined(separator: " ")
            }
        case "329":
            break
        case "331":
            if let channel = params.first, let buffer = buffer(named: channel) { buffer.topic = nil }
        case "332":   // RPL_TOPIC
            if params.count >= 2, let buffer = buffer(named: params[0]) {
                buffer.topic = params[1]
                info("Topic: \(params[1])", in: buffer, kind: .topic)
            }
        case "333":
            if params.count >= 2, let buffer = buffer(named: params[0]) {
                buffer.topicSetBy = IRCSource(raw: params[1]).nick
            }
        case "353":   // RPL_NAMREPLY: = #chan :names
            guard params.count >= 3 else { break }
            let key = fold(params[1])
            var members = pendingNames[key] ?? [:]
            for entry in params[2].split(separator: " ") {
                let (prefixes, rest) = isupport.splitPrefixes(String(entry))
                let source = IRCSource(raw: rest)
                members[fold(source.nick)] = Member(nick: source.nick, prefixes: prefixes, userHost: source.userHost)
            }
            pendingNames[key] = members
        case "366":   // RPL_ENDOFNAMES
            guard let channel = params.first else { break }
            let key = fold(channel)
            if let buffer = buffer(named: channel) {
                let fresh = pendingNames[key] ?? [:]
                // Preserve away/account info already known.
                buffer.replaceMembers(fresh.mapValues { member in
                    var member = member
                    if let old = buffer.memberMap[fold(member.nick)] {
                        member.isAway = old.isAway
                        member.account = member.account ?? old.account
                        member.realname = member.realname ?? old.realname
                    }
                    return member
                })
            }
            pendingNames.removeValue(forKey: key)
        case "433":
            if connectionState == .connected { error("Nickname \(params.first ?? "") is already in use", in: active) }
        case "442":   // ERR_NOTONCHANNEL
            // Parting a removed channel the bouncer had already left: done.
            if let channel = params.first, partingChannels.remove(fold(channel)) != nil { break }
            error(text, in: active)
        case "900":
            account = params.count >= 2 ? params[1] : account
        case "903", "904", "905", "906", "907", "908", "902":
            break
        default:
            if let code = Int(message.command), code >= 400 && code < 600 {
                error(text, in: active)
            } else {
                info(text, in: serverBuffer)
            }
        }
    }

    private func whoisText(_ numeric: String, _ params: [String]) -> String {
        let nick = params.first ?? ""
        let rest = Array(params.dropFirst())
        switch numeric {
        case "311": return "\(nick) is \(rest.prefix(2).joined(separator: "@")) (\(rest.last ?? ""))"
        case "312": return "\(nick) is connected to \(rest.first ?? "") (\(rest.last ?? ""))"
        case "317":
            if let idle = rest.first.flatMap(Int.init) {
                let formatter = DateComponentsFormatter()
                formatter.unitsStyle = .abbreviated
                return "\(nick) has been idle \(formatter.string(from: TimeInterval(idle)) ?? "\(idle)s")"
            }
            return "\(nick) \(rest.joined(separator: " "))"
        case "318": return "End of WHOIS for \(nick)"
        case "319": return "\(nick) is in \(rest.last ?? "")"
        case "330": return "\(nick) is logged in as \(rest.first ?? "")"
        default: return ([nick] + rest).joined(separator: " ")
        }
    }

    // MARK: Batches & history

    /// An open `chathistory` batch.
    private struct HistoryBatch {
        let buffer: BufferModel
        /// Lines it has brought so far.
        var count = 0
        /// It answers CHATHISTORY BEFORE (scrolling up): older lines, never
        /// unread, rather than ones missed while away.
        let isOlder: Bool
    }

    private func handleBatchStart(_ batch: IRCBatch) {
        switch batch.type {
        case "chathistory":
            guard let target = batch.params.first else { return }
            let kind: BufferKind = isupport.isChannel(target) ? .channel : .query
            let buffer = self.buffer(named: target) ?? ensureBuffer(name: target, kind: kind)
            historyBatches[batch.id] = HistoryBatch(buffer: buffer, isOlder: pendingBeforeRequests.contains(buffer.id))
        case "soju.im/bouncer-networks":
            bouncerBatchIDs.insert(batch.id)
        default:
            break
        }
    }

    private func handleBatchEnd(_ batch: IRCBatch) {
        if let entry = historyBatches.removeValue(forKey: batch.id) {
            entry.buffer.isLoadingHistory = false
            if entry.count == 0 && pendingBeforeRequests.remove(entry.buffer.id) != nil {
                entry.buffer.hasMoreHistory = false
            }
            pendingBeforeRequests.remove(entry.buffer.id)
        }
        if bouncerBatchIDs.remove(batch.id) != nil {
            host?.session(self, didUpdateBouncerNetworks: bouncerNetworks)
        }
    }

    @ObservationIgnored private var pendingBeforeRequests: Set<BufferID> = []

    private func fetchLatestHistory(for buffer: BufferModel) {
        guard supportsChatHistory, buffer.kind != .server else { return }
        let limit = historyLimit
        let target = buffer.name
        // Read before your own JOIN line is added (see catchUpPoint(for:received:)).
        let received = buffer.newestReceivedAt
        Task { [weak self] in
            guard let self else { return }
            if let newest = await self.catchUpPoint(for: buffer, received: received) {
                self.sendRaw("CHATHISTORY AFTER \(target) timestamp=\(IRCTime.format(newest)) \(limit)")
            } else {
                self.sendRaw("CHATHISTORY LATEST \(target) * \(limit)")
            }
        }
    }

    /// Asks ZNC's playback module for what was said in `channel` after the
    /// newest line Vela has from it (see ``catchUpPoint(for:received:)``).
    /// ZNC doesn't play a channel back by itself when it reattaches one for
    /// a client with `znc.in/playback`.
    private func requestPlayback(for channel: BufferModel) {
        guard supports("znc.in/playback") else { return }
        let target = channel.name
        // Read before your own JOIN line is added.
        let received = channel.newestReceivedAt
        Task { [weak self] in
            guard let self else { return }
            let newest = await self.catchUpPoint(for: channel, received: received)
            let stamp = newest.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            self.sendRaw("PRIVMSG *playback :PLAY \(target) \(stamp)")
        }
    }

    /// Where to fetch missed messages from after connecting: the newest line
    /// of `buffer` (of the whole network when nil) that Vela saved or
    /// received. While history isn't saved, only lines received since
    /// launch count, so a relaunch asks for the latest messages rather than
    /// for those after what was saved long ago. Nil asks for the latest.
    ///
    /// `received` is the buffer's (or network's) `newestReceivedAt`, read
    /// before adding the line that prompted the fetch: your own JOIN mustn't
    /// count, or the messages you missed while away would be skipped.
    private func catchUpPoint(for buffer: BufferModel?, received: Date?) async -> Date? {
        guard historyStorage.saves, let database else { return received }
        let saved: Date?
        if let buffer {
            saved = try? await database.newestMessageTime(in: buffer.id.storeKey)
        } else {
            saved = try? await database.newestMessageTime(networkID: id)
        }
        return [saved, received].compactMap { $0 }.max()
    }

    private var historyLimit: Int {
        let preferred = host?.behavior.historyFetchLimit ?? 100
        if let max = isupport.chatHistoryLimit, max > 0 { return min(preferred, max) }
        return preferred
    }

    /// Loads older scrollback: first from the local database, then from the
    /// server via CHATHISTORY BEFORE when supported.
    public func loadOlderHistory(for buffer: BufferModel) async {
        guard !buffer.isLoadingHistory, buffer.hasMoreHistory else { return }
        buffer.isLoadingHistory = true
        let oldest = buffer.lines.first?.time ?? Date()
        let pageSize = 150
        if let database = historyReader, let records = try? await database.messages(in: buffer.id.storeKey, before: oldest, limit: pageSize), !records.isEmpty {
            buffer.insertSorted(records.map(ChatLine.init(record:)))
            await loadReactions(for: records.compactMap(\.msgid), in: buffer)
            if records.count >= pageSize {
                buffer.isLoadingHistory = false
                return
            }
        }
        if supportsChatHistory, isConnected, client != nil, buffer.kind != .server {
            requestOlderHistory(for: buffer, before: buffer.lines.first?.time ?? oldest)
            // `isLoadingHistory` is cleared when the batch ends.
        } else {
            buffer.isLoadingHistory = false
            buffer.hasMoreHistory = false
        }
    }

    /// Asks the server for the lines before `time` (CHATHISTORY BEFORE).
    /// The batch that answers is older history: it never counts as unread.
    func requestOlderHistory(for buffer: BufferModel, before time: Date) {
        pendingBeforeRequests.insert(buffer.id)
        sendRaw("CHATHISTORY BEFORE \(buffer.name) timestamp=\(IRCTime.format(time)) \(historyLimit)")
    }

    private func loadReactions(for msgids: [String], in buffer: BufferModel) async {
        guard let database = historyReader, !msgids.isEmpty,
              let reactions = try? await database.reactions(in: buffer.id.storeKey, msgids: msgids) else { return }
        for reaction in reactions {
            buffer.setReaction(msgid: reaction.msgid, nick: reaction.nick, emoji: reaction.emoji, active: true)
        }
    }

    // MARK: Outbound

    private func handleSent(_ message: IRCMessage) {
        // Parts and detaches waiting for the bouncer are done once sent.
        noteSentToBouncer(message)
        guard !supports("echo-message"), let target = message.param(0) else { return }
        switch message.command {
        case "PRIVMSG", "NOTICE":
            guard var text = message.param(1) else { return }
            var kind: ChatLineKind = message.command == "NOTICE" ? .notice : .message
            if let ctcp = CTCP.parse(text) {
                guard ctcp.command == "ACTION" else { return }
                kind = .action
                text = ctcp.argument ?? ""
            }
            if target.hasPrefix("*") { return }   // bouncer control messages
            if isOwnBouncerCommand(to: target, text: text) { return }
            let buffer = isupport.isChannel(target) ? ensureBuffer(name: target, kind: .channel) : ensureBuffer(name: target, kind: .query)
            add(ChatLine(kind: kind, nick: nick, text: text, isSelf: true, replyTo: message.replyTo, tags: message.tags.filter { $0.key.hasPrefix("+") }), to: buffer)
        case "TAGMSG":
            guard let msgid = message.replyTo, let buffer = buffer(named: target) else { return }
            if let emoji = message.tags["+draft/react"] { applyReaction(emoji: emoji, msgid: msgid, nick: nick, active: true, in: buffer) }
            if let emoji = message.tags["+draft/unreact"] { applyReaction(emoji: emoji, msgid: msgid, nick: nick, active: false, in: buffer) }
        default:
            break
        }
    }

    public func send(_ message: IRCMessage) {
        guard let client else {
            if echoesWithoutServer { echoAsServer(message) }
            return
        }
        Task { await client.send(message) }
    }

    /// Demo networks (`DemoContent`) have no server, so what you send would
    /// go nowhere: with this on, chat comes back as a server echoes it
    /// (echo-message), so sent messages, GIFs and replies show in the
    /// conversation. Off for real networks.
    @ObservationIgnored public var echoesWithoutServer = false

    private func echoAsServer(_ message: IRCMessage) {
        guard ["PRIVMSG", "NOTICE", "TAGMSG"].contains(message.command) else { return }
        var tags = message.tags
        tags["msgid"] = "demo-\(UUID().uuidString)"
        tags["time"] = ISO8601DateFormatter().string(from: Date())
        let echoed = IRCMessage(tags: tags, source: IRCSource(nick: nick, user: nick, host: "vela.demo"), command: message.command, params: message.params)
        // On the next turn, as a reply from a server would come.
        Task { [weak self] in self?.handle(.message(echoed, batch: nil)) }
    }

    public func sendRaw(_ line: String) {
        guard let client else { return }
        Task { await client.sendRaw(line) }
    }

    /// Handles a line typed into the input bar of `buffer`.
    public func submit(_ input: String, in buffer: BufferModel, replyTo: ChatLine? = nil) {
        guard let command = InputCommand.parse(input) else { return }
        perform(command, in: buffer, replyTo: replyTo)
        if case .say = command, buffer.kind != .server, isConnected {
            host?.session(self, didSendComposerMessageIn: buffer)
        }
    }

    func perform(_ command: InputCommand, in buffer: BufferModel, replyTo: ChatLine?) {
        let needsConnection: Bool = {
            switch command {
            case .connect, .reconnect, .disconnect, .close, .clear, .ignore, .unignore, .usage, .quit: return false
            default: return true
            }
        }()
        if needsConnection && !isConnected {
            error("Not connected. Use /connect to connect to \(displayName).", in: buffer)
            return
        }

        switch command {
        case .say(let text):
            guard buffer.kind != .server else {
                error("You can't chat in the server buffer. Join a channel with /join #channel, or send raw commands with /raw.", in: buffer)
                return
            }
            sendChat(text, to: buffer, replyTo: replyTo)
        case .action(let text):
            guard buffer.kind != .server else { return }
            let tags = replyTo?.msgid.flatMap { supportsReplies ? ["+draft/reply": $0] : nil } ?? [:]
            send(IRCMessage(tags: tags, command: "PRIVMSG", params: [buffer.name, CTCP.encode("ACTION", text)]))
            typingFinished(in: buffer)
        case .message(let target, let text):
            let destination = isupport.isChannel(target) ? (self.buffer(named: target) ?? buffer) : ensureBuffer(name: target, kind: .query)
            sendChat(text, to: destination, replyTo: nil, explicitTarget: target)
        case .notice(let target, let text):
            for line in IRCMessage.chatLines(command: "NOTICE", target: target, text: text) { send(line) }
        case .query(let nick, let text):
            let query = ensureBuffer(name: nick, kind: .query)
            requestSelection?(query)
            if let text { sendChat(text, to: query, replyTo: nil) }
        case .join(let channels, var keys):
            // A channel you left goes back on the auto-join list, with its
            // key, and anything still waiting for a bouncer (a part or a
            // detach) is off.
            if keys.isEmpty, channels.count == 1, let key = joinKey(forChannel: fold(channels[0])) { keys = [key] }
            for channel in channels { prepareToJoin(fold(channel)) }
            var params = [channels.joined(separator: ",")]
            if !keys.isEmpty { params.append(keys.joined(separator: ",")) }
            send(IRCMessage(command: "JOIN", params: params))
            if let first = channels.first {
                let target = ensureBuffer(name: first, kind: .channel)
                requestSelection?(target)
            }
        case .part(let channel, let reason):
            guard let name = channel ?? (buffer.kind == .channel ? buffer.name : nil) else {
                error("/part must be used in a channel or with a channel name", in: buffer)
                return
            }
            if let channel = self.buffer(named: name), channel.kind == .channel {
                if let requestLeave { requestLeave(channel, reason) } else { leave(channel, reason: reason) }
            } else {
                send(IRCMessage(command: "PART", params: reason.map { [name, $0] } ?? [name]))
                // A hidden channel, parted by name: the bouncer forgets it,
                // and so does Vela.
                forgetHiddenChannel(fold(name))
            }
        case .nick(let newNick):
            send(IRCMessage(command: "NICK", params: [newNick]))
        case .topic(let channel, let text):
            guard let name = channel ?? (buffer.kind == .channel ? buffer.name : nil) else { return }
            send(IRCMessage(command: "TOPIC", params: text.map { [name, $0] } ?? [name]))
        case .away(let message):
            send(IRCMessage(command: "AWAY", params: [message ?? "Away"]))
        case .back:
            send(IRCMessage(command: "AWAY"))
        case .whois(let nick):
            send(IRCMessage(command: "WHOIS", params: [nick]))
        case .mode(let target, let args):
            let name = target ?? (buffer.kind == .server ? nick : buffer.name)
            send(IRCMessage(command: "MODE", params: [name] + args))
        case .kick(let nick, let reason):
            guard buffer.kind == .channel else { return }
            sendKick(nick, reason: reason, in: buffer)
        case .kickBan(let nicks, let reason):
            guard buffer.kind == .channel else { return }
            Task { await self.kickBan(nicks, reason: reason, in: buffer) }
        case .ban(let masks), .unban(let masks):
            guard buffer.kind == .channel else { return }
            let sign: Character = if case .ban = command { "+" } else { "-" }
            Task { await self.setBans(sign: sign, targets: masks, in: buffer) }
        case .quiet(let masks), .unquiet(let masks):
            guard buffer.kind == .channel else { return }
            guard let method = isupport.quietMethod else {
                error("\(displayName) doesn't say how to quiet someone. Ban them instead, or set the mode with /mode.", in: buffer)
                return
            }
            let sign: Character = if case .quiet = command { "+" } else { "-" }
            Task { await self.setQuiets(sign: sign, targets: masks, method: method, in: buffer) }
        case .memberMode(let sign, let mode, let nicks):
            guard buffer.kind == .channel else { return }
            sendModes(sign: sign, mode: mode, arguments: nicks, in: buffer)
        case .invite(let nick, let channel):
            guard let name = channel ?? (buffer.kind == .channel ? buffer.name : nil) else { return }
            send(IRCMessage(command: "INVITE", params: [nick, name]))
        case .ctcp(let target, let ctcpCommand, let argument):
            sendCTCP(ctcpCommand, argument: argument, to: target, from: buffer)
        case .raw(let line):
            sendRaw(line)
        case .quit(let reason):
            disconnect(reason: reason)
        case .connect:
            connect()
        case .disconnect(let reason):
            disconnect(reason: reason)
        case .reconnect:
            reconnect()
        case .close:
            if let requestClose { requestClose(buffer) } else { close(buffer) }
        case .clear:
            buffer.lines.removeAll()
        case .ignore(let mask):
            if !config.ignoreMasks.contains(mask) {
                config.ignoreMasks.append(mask)
                rebuildMatchers()
                host?.sessionDidChangeConfig(self)
            }
            info("Ignoring \(mask)", in: buffer)
        case .unignore(let mask):
            config.ignoreMasks.removeAll { $0.caseInsensitiveCompare(mask) == .orderedSame }
            rebuildMatchers()
            host?.sessionDidChangeConfig(self)
            info("No longer ignoring \(mask)", in: buffer)
        case .usage(let usage):
            error("Usage: \(usage)", in: buffer)
        case .unknown(let command, let args):
            sendRaw(args.isEmpty ? command.uppercased() : "\(command.uppercased()) \(args)")
        }
    }

    /// Set by the app so `/join` and `/query` can focus the new buffer.
    @ObservationIgnored public var requestSelection: ((BufferModel) -> Void)?
    /// Set by the app so `/close` removes a channel (or closes a
    /// conversation) the way the window does (see
    /// `AppModel.close(_:reopenable:)`): the selection moves on, and it can
    /// be undone and reopened. Without it, `/close` just closes.
    @ObservationIgnored public var requestClose: ((BufferModel) -> Void)?
    /// Set by the app so `/part` leaves the way Leave Channel does, and can
    /// be undone. Without it, `/part` just leaves.
    @ObservationIgnored public var requestLeave: ((BufferModel, String?) -> Void)?

    private func sendChat(_ text: String, to buffer: BufferModel, replyTo: ChatLine?, explicitTarget: String? = nil) {
        var tags: [String: String] = [:]
        if let msgid = replyTo?.msgid, supportsReplies { tags["+draft/reply"] = msgid }
        let target = explicitTarget ?? buffer.name
        for line in IRCMessage.chatLines(target: target, text: text, tags: tags) {
            send(line)
        }
        typingFinished(in: buffer)
    }

    // MARK: Reactions, replies, redaction

    public func toggleReaction(_ emoji: String, on line: ChatLine, in buffer: BufferModel) {
        guard let msgid = line.msgid, supportsReactions, buffer.kind != .server else { return }
        let alreadyReacted = buffer.reactions(for: msgid).first { $0.emoji == emoji }?.includesSelf ?? false
        let tag = alreadyReacted ? "+draft/unreact" : "+draft/react"
        send(IRCMessage(tags: [tag: emoji, "+draft/reply": msgid], command: "TAGMSG", params: [buffer.name]))
    }

    public func redact(_ line: ChatLine, in buffer: BufferModel, reason: String? = nil) {
        guard let msgid = line.msgid, supportsRedaction else { return }
        send(IRCMessage(command: "REDACT", params: [buffer.name, msgid] + (reason.map { [$0] } ?? [])))
    }

    private func applyReaction(emoji: String, msgid: String, nick: String, active: Bool, in buffer: BufferModel) {
        buffer.setReaction(msgid: msgid, nick: nick, emoji: emoji, active: active)
        // New reactions are saved only with history; a removed one also
        // leaves history saved earlier.
        let storage = historyStorage
        guard storage.saves || (!active && storage.loads) else { return }
        let key = buffer.id.storeKey
        let reaction = ReactionRecord(msgid: msgid, nick: nick, emoji: emoji)
        writeBuffer { try await $0.setReaction(reaction, in: key, active: active) }
    }

    // MARK: Typing

    /// Call on every edit of the input text for `buffer`.
    public func inputChanged(_ text: String, in buffer: BufferModel) {
        guard buffer.kind != .server, isConnected, host?.behavior.sendTypingIndicators ?? true, supportsTyping else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("/") {
            typingFinished(in: buffer)
            return
        }
        let now = Date()
        if let last = lastTypingSent[buffer.id], last.state == .active, now.timeIntervalSince(last.at) < 3 { return }
        lastTypingSent[buffer.id] = (.active, now)
        send(IRCMessage(tags: ["+typing": "active"], command: "TAGMSG", params: [buffer.name]))
    }

    private func typingFinished(in buffer: BufferModel) {
        guard let last = lastTypingSent[buffer.id], last.state == .active else { return }
        lastTypingSent[buffer.id] = (.done, Date())
        if supportsTyping, isConnected {
            send(IRCMessage(tags: ["+typing": "done"], command: "TAGMSG", params: [buffer.name]))
        }
    }

    private func typingStopped(nick: String, in buffer: BufferModel) {
        buffer.clearTyping(nick: nick)
    }

    private func startTypingSweep() {
        guard typingSweepTask == nil else { return }
        typingSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                var anyTyping = false
                for buffer in self.buffers where !buffer.typingNicks.isEmpty {
                    buffer.refreshTyping()
                    anyTyping = anyTyping || !buffer.typingNicks.isEmpty
                }
                if !anyTyping {
                    self.typingSweepTask = nil
                    return
                }
            }
        }
    }

    // MARK: Buffers

    @discardableResult
    public func ensureBuffer(name: String, kind: BufferKind, persist: Bool = true) -> BufferModel {
        let key = fold(name)
        if let existing = bufferIndex[key] { return existing }
        // A hidden channel opened again (shown, joined, messaged) comes back
        // as it was, detached, in its old place.
        let hidden = kind == .channel ? takeHiddenChannel(key) : nil
        let buffer = BufferModel(id: BufferID(networkID: id, foldedName: key), name: name, kind: kind)
        // New buffers go after the others of their kind, like a new tab.
        buffer.sortOrder = (buffers.filter { $0.kind == kind }.map(\.sortOrder).max() ?? -1) + 1
        buffer.selfNick = { [unowned self] in self.nick }
        buffer.memberRank = { [isupport] in isupport.rank(ofSymbol: $0.topPrefix) }
        if let hidden {
            buffer.isMuted = hidden.isMuted
            buffer.lastReadAt = hidden.lastReadAt
            buffer.isDetached = true
        }
        bufferIndex[key] = buffer
        buffers.append(buffer)
        // Opened again on purpose (joined, reopened): no longer leaving it.
        partingChannels.remove(key)
        sortBuffers()
        if let hidden { moveBuffer(buffer, toIndex: hidden.index) }
        if persist || hidden != nil { persistBuffer(buffer) }
        loadRecentScrollback(for: buffer)
        host?.session(self, didOpen: buffer)
        return buffer
    }

    /// Removes a channel or closes a conversation: leaves a joined channel,
    /// takes the buffer out of the list and forgets its saved state. Its
    /// messages stay on disk. The app goes through
    /// `AppModel.close(_:reopenable:)`, which also moves the selection,
    /// takes the channel off the auto-join list and remembers it for
    /// reopening.
    ///
    /// On a bouncer, Vela parts the channel even when it isn't in it here
    /// (detached, or kicked), so the bouncer forgets it too. Disconnected,
    /// the PART waits in networks.json for the next connection.
    public func close(_ buffer: BufferModel) {
        guard buffer.kind != .server else { return }
        let folded = buffer.id.foldedName
        if buffer.kind == .channel {
            let bouncerHasIt = isBouncer && (buffer.isJoined || buffer.isDetached || rejoins(buffer))
            cancelDetach(folded)
            pendingJoins.remove(folded)
            if isConnected, buffer.isJoined || bouncerHasIt {
                send(IRCMessage(command: "PART", params: [buffer.name]))
                partingChannels.insert(folded)
            } else if !isConnected, bouncerHasIt {
                // The bouncer is still in it, and joins Vela into it as Vela
                // connects: part it then.
                addPendingPart(buffer.name)
            }
            leftAutoJoin.removeValue(forKey: folded)
        }
        bufferIndex.removeValue(forKey: folded)
        buffers.removeAll { $0.id == buffer.id }
        autoRejoin.removeValue(forKey: folded)
        let key = buffer.id.storeKey
        writeBuffer { try await $0.deleteBuffer(key, keepMessages: true) }
        host?.sessionDidChangeUnreadCounts(self)
        host?.session(self, didClose: buffer)
    }

    /// Leaves a channel but keeps it in the list, not joined, with its
    /// history (`/part`, and Leave Channel on a network without a bouncer).
    /// It comes off the network's auto-join list, so it stays left when you
    /// reconnect; joining it again puts its entry back where it was, with
    /// its key (which stays in the Keychain meanwhile).
    ///
    /// It really parts, even through a bouncer, which then forgets the
    /// channel. Disconnected from a bouncer, the PART waits for the next
    /// connection. Leave Channel on a bouncer detaches instead (`detach`).
    func leave(_ channel: BufferModel, reason: String? = nil) {
        guard channel.kind == .channel else { return }
        let folded = channel.id.foldedName
        let bouncerHasIt = isBouncer && (isIn(channel) || channel.isDetached)
        autoRejoin[folded] = false
        pendingJoins.remove(folded)
        cancelDetach(folded)
        if let removed = removeAutoJoin(folded) {
            leftAutoJoin[folded] = LeftAutoJoin(entry: removed.entry, index: removed.index)
        }
        // Parted, the bouncer forgets it.
        channel.isDetached = false
        persistBuffer(channel)
        if isConnected {
            send(IRCMessage(command: "PART", params: reason.map { [channel.name, $0] } ?? [channel.name]))
        } else if bouncerHasIt {
            addPendingPart(channel.name)
        }
    }

    /// Joins a channel you left or detached again (Join Channel, undoing
    /// Leave): now when connected, with its key if it has one, or on the
    /// next connect. A channel you left goes back on the auto-join list
    /// where it was. On a bouncer, the JOIN reattaches a detached channel
    /// and the bouncer plays back what you missed.
    public func rejoin(_ channel: BufferModel) {
        guard channel.kind == .channel else { return }
        let folded = channel.id.foldedName
        autoRejoin[folded] = true
        let droppedUnsentDetach = prepareToJoin(folded)
        if isConnected {
            sendJoin(channel)
        } else if droppedUnsentDetach {
            // The bouncer never heard of the detach: it's still in the
            // channel and joins Vela into it as Vela connects.
            channel.isDetached = false
        } else if isBouncer {
            pendingJoins.insert(folded)
        }
        persistBuffer(channel)
    }

    /// Whether you're in `channel`, or will be once connected: what Leave
    /// leaves. A channel you're not in (left, kicked, detached, or not
    /// joined yet while connected) shows dimmed.
    public func isIn(_ channel: BufferModel) -> Bool {
        guard channel.kind == .channel else { return false }
        if channel.isJoined { return true }
        guard !isConnected else { return false }
        return pendingJoins.contains(channel.id.foldedName) || (!channel.isDetached && rejoins(channel))
    }

    /// Whether `buffer` is joined again on the next connect (`/part` says no).
    func rejoins(_ buffer: BufferModel) -> Bool {
        autoRejoin[buffer.id.foldedName] ?? true
    }

    /// Whether `channel` was closed while joined and the server hasn't
    /// confirmed the PART yet.
    private func isParting(_ channel: String) -> Bool {
        !partingChannels.isEmpty && partingChannels.contains(fold(channel)) && buffer(named: channel) == nil
    }

    /// Sends JOIN for `channel`, with its auto-join key if it has one.
    func sendJoin(_ channel: BufferModel) {
        let key = joinKey(forChannel: channel.id.foldedName)
        send(IRCMessage(command: "JOIN", params: [channel.name] + (key.map { [$0] } ?? [])))
    }

    /// The key of `channel`'s auto-join entry (folded name), or of the entry
    /// it had before you left it, if it has one stored.
    func joinKey(forChannel folded: String) -> String? {
        let hasKey = config.autoJoin.contains { $0.hasKey && fold($0.name) == folded }
            || leftAutoJoin[folded]?.entry.hasKey == true
        guard hasKey else { return nil }
        return keychain.secret(account: Keychain.channelKeyAccount(networkID: id, channel: folded))
    }

    /// Takes `folded`'s auto-join entry away (removing a channel): the one
    /// on the list, or the one remembered since you left it. Returns it and
    /// where it was.
    func takeAutoJoin(_ folded: String) -> LeftAutoJoin? {
        if let removed = removeAutoJoin(folded) {
            leftAutoJoin.removeValue(forKey: folded)
            return LeftAutoJoin(entry: removed.entry, index: removed.index)
        }
        return leftAutoJoin.removeValue(forKey: folded)
    }

    /// Remembers the auto-join entry of a channel you left (reopening a
    /// removed channel you'd left), to go back on the list when it's joined.
    func rememberLeftAutoJoin(_ left: LeftAutoJoin, for folded: String) {
        leftAutoJoin[folded] = left
    }

    /// Takes `folded` off the auto-join list (removing a channel) and saves
    /// networks.json. Returns where its entry was, to put it back.
    func removeAutoJoin(_ folded: String) -> (index: Int, entry: AutoJoinChannel)? {
        guard let index = config.autoJoin.firstIndex(where: { fold($0.name) == folded }) else { return nil }
        let entry = config.autoJoin.remove(at: index)
        // A second entry for it would join it again.
        config.autoJoin.removeAll { fold($0.name) == folded }
        host?.sessionDidChangeConfig(self)
        return (index, entry)
    }

    /// Puts an auto-join entry back at `index` (reopening a removed channel)
    /// and saves networks.json.
    func restoreAutoJoin(_ entry: AutoJoinChannel, at index: Int) {
        let folded = fold(entry.name)
        guard !config.autoJoin.contains(where: { fold($0.name) == folded }) else { return }
        config.autoJoin.insert(entry, at: min(max(0, index), config.autoJoin.count))
        host?.sessionDidChangeConfig(self)
    }

    /// Puts back a channel or conversation that `close(_:)` removed, the way
    /// `closed` describes it: in its old place among its siblings, muted or
    /// not, read up to the same point and with the unread count it had. A
    /// channel you were in is joined again now when connected (with its
    /// auto-join key, if it has one), or on the next connect. Returns the
    /// buffer that's already open instead, if the channel or conversation
    /// was opened again meanwhile.
    func reopen(_ closed: ClosedBuffer) -> BufferModel {
        if let existing = buffer(named: closed.name) { return existing }
        let buffer = ensureBuffer(name: closed.name, kind: closed.kind, persist: false)
        buffer.isMuted = closed.isMuted
        buffer.lastReadAt = closed.lastReadAt
        buffer.unreadCount = closed.unreadCount
        buffer.highlightCount = closed.highlightCount
        if closed.unreadCount > 0 { buffer.unreadMarkerAfter = closed.lastReadAt ?? .distantPast }
        if closed.kind == .channel {
            let folded = buffer.id.foldedName
            autoRejoin[folded] = closed.autoRejoin
            let partWasWaiting = removePendingPart(folded)
            if closed.wasHidden {
                // Still on the bouncer, detached: back as it was.
                buffer.isDetached = true
            } else if closed.wasDetached && partWasWaiting {
                // Removed while disconnected, before the part reached the
                // bouncer: detached again, making sure the bouncer has it so.
                buffer.isDetached = true
                addPendingDetach(buffer.name)
            } else if closed.autoRejoin {
                if isConnected {
                    sendJoin(buffer)
                } else if isBouncer {
                    pendingJoins.insert(folded)
                }
            }
        }
        moveBuffer(buffer, toIndex: closed.index)
        persistBuffer(buffer)
        host?.sessionDidChangeUnreadCounts(self)
        return buffer
    }

    /// Clears the unread counts and moves the read position to the newest
    /// line, including lines that arrived while the buffer was on screen.
    public func markRead(_ buffer: BufferModel) {
        let readTo = [buffer.lastReadAt, buffer.lines.last?.time].compactMap { $0 }.max() ?? Date()
        guard buffer.unreadCount > 0 || buffer.highlightCount > 0 || buffer.lastReadAt != readTo else { return }
        buffer.unreadCount = 0
        buffer.highlightCount = 0
        buffer.lastReadAt = readTo
        persistBuffer(buffer)
        host?.sessionDidChangeUnreadCounts(self)
    }

    /// Moves the read position up to `time` (never back) and recounts what's
    /// still unread after it: ``markRead(_:)`` for everything up to one
    /// message, as Siri's "mark as read" asks. Lines after it that were
    /// never counted (seen on screen, your own, history in a buffer never
    /// read before) stay uncounted.
    public func markRead(_ buffer: BufferModel, upTo time: Date) {
        let readTo = max(buffer.lastReadAt ?? .distantPast, time)
        // Replayed lines after the read position counted once there was one.
        let countsHistory = buffer.lastReadAt != nil
        var unread = 0
        var highlights = 0
        // Lines are in time order: count back to the read position.
        for line in buffer.lines.reversed() {
            guard line.time > readTo else { break }
            guard !line.isHistory || countsHistory, !line.isSelf, line.kind.isConversation else { continue }
            unread += 1
            if line.isHighlight || (buffer.kind == .query && line.kind != .notice) { highlights += 1 }
        }
        unread = min(unread, buffer.unreadCount)
        highlights = min(highlights, buffer.highlightCount)
        guard unread != buffer.unreadCount || highlights != buffer.highlightCount || buffer.lastReadAt != readTo else { return }
        buffer.unreadCount = unread
        buffer.highlightCount = highlights
        buffer.lastReadAt = readTo
        persistBuffer(buffer)
        host?.sessionDidChangeUnreadCounts(self)
    }

    public func setMuted(_ muted: Bool, for buffer: BufferModel) {
        buffer.isMuted = muted
        persistBuffer(buffer)
        host?.sessionDidChangeUnreadCounts(self)
    }

    func sortBuffers() {
        buffers.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .channel }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: Buffer order

    /// The buffers `buffer` can be moved among: the network's channels, or
    /// its queries, in display order.
    public func bufferSiblings(of buffer: BufferModel) -> [BufferModel] {
        buffers.filter { $0.kind == buffer.kind }
    }

    /// Moves `buffer` to `index` among its siblings (see `bufferSiblings(of:)`).
    /// Moving a channel also reorders the auto-join list to match.
    public func moveBuffer(_ buffer: BufferModel, toIndex index: Int) {
        var group = bufferSiblings(of: buffer)
        guard let from = group.firstIndex(where: { $0.id == buffer.id }) else { return }
        let to = min(max(0, index), group.count - 1)
        guard from != to else { return }
        group.remove(at: from)
        group.insert(buffer, at: to)
        applyOrder(group)
    }

    /// Moves `buffer` `offset` places among its siblings (negative is up/left).
    public func moveBuffer(_ buffer: BufferModel, by offset: Int) {
        guard let index = bufferSiblings(of: buffer).firstIndex(where: { $0.id == buffer.id }) else { return }
        moveBuffer(buffer, toIndex: index + offset)
    }

    /// Whether channels and queries are each in alphabetical order.
    public var isBufferOrderAlphabetical: Bool {
        [channels, queries].allSatisfy { group in
            zip(group, group.dropFirst()).allSatisfy { $0.name.localizedCaseInsensitiveCompare($1.name) != .orderedDescending }
        }
    }

    /// Sorts channels and queries alphabetically again.
    public func sortBuffersAlphabetically() {
        for group in [channels, queries] {
            applyOrder(group.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    /// Numbers `group` (buffers of one kind) in its order and saves it.
    private func applyOrder(_ group: [BufferModel]) {
        var changed = false
        for (index, buffer) in group.enumerated() where buffer.sortOrder != index {
            buffer.sortOrder = index
            persistBuffer(buffer)
            changed = true
        }
        guard changed else { return }
        sortBuffers()
        if group.first?.kind == .channel { syncAutoJoinOrder() }
    }

    /// Reorders the auto-join list to follow the channels' display order.
    /// Entries for channels that aren't open keep their places.
    private func syncAutoJoinOrder() {
        let position = Dictionary(channels.enumerated().map { ($1.id.foldedName, $0) }, uniquingKeysWith: { first, _ in first })
        let slots = config.autoJoin.indices.filter { position[fold(config.autoJoin[$0].name)] != nil }
        guard slots.count > 1 else { return }
        let ordered = slots.map { config.autoJoin[$0] }
            .sorted { (position[fold($0.name)] ?? 0) < (position[fold($1.name)] ?? 0) }
        var autoJoin = config.autoJoin
        for (slot, entry) in zip(slots, ordered) { autoJoin[slot] = entry }
        guard autoJoin != config.autoJoin else { return }
        config.autoJoin = autoJoin
        host?.sessionDidChangeConfig(self)
    }

    func persistBuffer(_ buffer: BufferModel) {
        guard database != nil, buffer.kind != .server else { return }
        let record = BufferRecord(
            networkID: id,
            name: buffer.name,
            foldedName: buffer.id.foldedName,
            kind: buffer.kind.rawValue,
            lastReadAt: buffer.lastReadAt,
            isPinned: false,
            isMuted: buffer.isMuted,
            sortOrder: buffer.sortOrder,
            autoRejoin: autoRejoin[buffer.id.foldedName] ?? true,
            isDetached: buffer.isDetached,
            leftAutoJoin: leftAutoJoin[buffer.id.foldedName]
        )
        writeBuffer { try await $0.upsertBuffer(record) }
    }

    /// Writes to the database in the order the session makes its writes:
    /// each waits for the one before. Buffer state is saved whole, so a mute
    /// saved after a read position must land after it, and closing a channel
    /// and reopening it straight away (⌘Z) can't save the reopened channel
    /// before deleting the closed one. Saved messages, reactions and
    /// redactions go through it too.
    func writeBuffer(_ write: @escaping @Sendable (VelaDatabase) async throws -> Void) {
        guard let database else { return }
        let previous = bufferWrites
        bufferWrites = Task {
            await previous?.value
            try? await write(database)
        }
    }

    /// Waits for every write made so far (tests).
    func bufferWritesFinished() async {
        await bufferWrites?.value
    }

    /// Loads a new buffer's newest saved lines. Nothing is read while
    /// history isn't saved (unless history saved earlier was kept).
    private func loadRecentScrollback(for buffer: BufferModel) {
        guard let database = historyReader else { return }
        let key = buffer.id.storeKey
        historyLoads.begin()
        Task { [weak self] in
            defer { self?.historyLoads.end() }
            guard let records = try? await database.latestMessages(in: key, limit: 200) else { return }
            buffer.insertSorted(records.map(ChatLine.init(record:)))
            buffer.hasMoreHistory = true
            await self?.loadReactions(for: records.compactMap(\.msgid), in: buffer)
        }
    }

    /// Returns once the recent lines of every buffer restored or opened
    /// so far have loaded from the message store (`AppModel.ready()`
    /// waits for this, so Siri counts unread lines from them).
    public func recentHistoryLoaded() async {
        await historyLoads.wait()
    }

    func updateMember(_ nick: String, _ update: (inout Member) -> Void) {
        let key = fold(nick)
        for buffer in channels {
            buffer.updateMember(forKey: key, update)
        }
    }

    // MARK: Lines

    func add(_ line: ChatLine, to buffer: BufferModel) {
        // A copy of a line already shown (a bouncer replaying what we saw
        // live) is neither shown nor stored again.
        guard buffer.append(line, limit: host?.behavior.scrollbackInMemory ?? 1000) else { return }
        host?.session(self, didAdd: line, to: buffer)
        if buffer.kind != .server || line.kind.isConversation {
            noteReceived(line, in: buffer)
            enqueue(line.record(networkID: id, bufferName: buffer.id.foldedName))
        }
        guard !line.isSelf else { return }
        if line.isHistory {
            countReplayed(line, in: buffer)
            return
        }

        let visible = host?.isBufferVisible(buffer.id) ?? false
        if !visible && line.kind.isConversation {
            countUnread(line, in: buffer)
            host?.sessionDidChangeUnreadCounts(self)
        }
        if line.isHighlight || (buffer.kind == .query && line.kind.isConversation) {
            if !buffer.isMuted || line.isHighlight {
                host?.session(self, didReceiveNotable: line, in: buffer)
            }
        }
    }

    /// Counts `line` as unread (and as a mention when it is one). The New
    /// marker goes where the new lines start as soon as the first arrives,
    /// so a channel left open in an unfocused window shows it without
    /// waiting for focus.
    private func countUnread(_ line: ChatLine, in buffer: BufferModel) {
        if buffer.unreadCount == 0 {
            buffer.unreadMarkerAfter = buffer.lastReadAt ?? .distantPast
        }
        buffer.unreadCount += 1
        if line.isHighlight || (buffer.kind == .query && line.kind != .notice) {
            buffer.highlightCount += 1
        }
    }

    /// A line a bouncer replayed, or chathistory brought. One from after
    /// you last read the buffer is something you missed, so it counts like
    /// a live one: badges, mentions, the New line, the Dock badge and Catch
    /// me up all see it. It never notifies, though: no banners, sounds or
    /// Dock bounces for old news. Lines from before the read position, older
    /// history loaded by scrolling up, and history in a buffer never read
    /// (no read position yet) stay read.
    private func countReplayed(_ line: ChatLine, in buffer: BufferModel) {
        guard line.kind.isConversation, !handlingOlderHistory,
              let lastRead = buffer.lastReadAt, line.time > lastRead else { return }
        if host?.isBufferVisible(buffer.id) ?? false {
            // On screen, so nothing to count, but the New line goes above
            // what was replayed, below what the reader has already seen.
            if buffer.unreadMarkerAfter == nil {
                buffer.unreadMarkerAfter = max(lastRead, timeOfLine(before: line, in: buffer) ?? lastRead)
            }
            return
        }
        countUnread(line, in: buffer)
        scheduleUnreadCountsChange()
    }

    /// The time of the line just before `line` in `buffer`. Replayed lines
    /// land at or near the end, so the search from there is short.
    private func timeOfLine(before line: ChatLine, in buffer: BufferModel) -> Date? {
        let lines = buffer.lines
        guard let index = lines.lastIndex(where: { $0.id == line.id }), index > lines.startIndex else { return nil }
        return lines[index - 1].time
    }

    /// Tells the host the unread totals changed, a few times a second at
    /// most: a bouncer can replay thousands of lines at once, and the Dock
    /// badge needn't be worked out again for each.
    private func scheduleUnreadCountsChange() {
        guard !unreadCountsChangeScheduled else { return }
        unreadCountsChangeScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }
            self.unreadCountsChangeScheduled = false
            self.host?.sessionDidChangeUnreadCounts(self)
        }
    }

    func info(_ text: String, in buffer: BufferModel, kind: ChatLineKind = .info) {
        add(ChatLine(kind: kind, text: text), to: buffer)
    }

    func error(_ text: String, in buffer: BufferModel) {
        add(ChatLine(kind: .error, text: text), to: buffer)
    }

    // MARK: Persistence batching

    /// `history.save`, as the host has it.
    private var historyStorage: HistoryStorage { host?.historyStorage ?? .saveAndLoad }

    /// The database, while saved history may be read from it.
    private var historyReader: VelaDatabase? { historyStorage.loads ? database : nil }

    /// Remembers the newest line that would be saved (see ``catchUpPoint(for:received:)``).
    private func noteReceived(_ line: ChatLine, in buffer: BufferModel) {
        if buffer.newestReceivedAt.map({ line.time > $0 }) ?? true { buffer.newestReceivedAt = line.time }
        if newestReceivedAt.map({ line.time > $0 }) ?? true { newestReceivedAt = line.time }
    }

    private func enqueue(_ record: MessageRecord) {
        guard database != nil, historyStorage.saves else { return }
        pendingRecords.append(record)
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.flushPendingRecords()
        }
    }

    private func flushPendingRecords() {
        flushTask = nil
        let records = pendingRecords
        pendingRecords = []
        // Saving may have been turned off while these waited.
        guard historyStorage.saves, !records.isEmpty else { return }
        // Spotlight's index of messages, when it's on, hears about the ones
        // that were new once they're written (off the main actor).
        guard let sink = host?.savedMessagesSink else {
            writeBuffer { _ = try await $0.append(records) }
            return
        }
        let context = savedMessagesContext(for: records)
        writeBuffer { database in
            let inserted = try await database.append(records)
            if !inserted.isEmpty { sink.didSave(inserted, context: context) }
        }
    }

    /// Writes lines still waiting for the next batch, and waits until every
    /// write made so far is done (tests).
    func flushPendingRecordsNow() async {
        flushTask?.cancel()
        flushPendingRecords()
        await bufferWritesFinished()
    }

    // MARK: Helpers

    func fold(_ name: String) -> String { isupport.caseMapping.fold(name) }

    /// Whether `nick` is ours, by the network's case mapping.
    public func isSelf(_ nick: String) -> Bool { fold(nick) == fold(self.nick) }

    private func rebuildMatchers() {
        let words = config.highlightWords + (host?.behavior.highlightWords ?? [])
        highlightMatcher = HighlightMatcher(nick: nick, words: words)
        ignoreMatcher = IgnoreMatcher(masks: config.ignoreMasks)
    }

    /// Re-reads behavior-dependent state (call when settings change).
    public func behaviorDidChange() {
        rebuildMatchers()
    }
}
