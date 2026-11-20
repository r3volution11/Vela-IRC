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
    public private(set) var buffers: [BufferModel] = []
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
    @ObservationIgnored private var bufferIndex: [String: BufferModel] = [:]
    @ObservationIgnored private var pendingNames: [String: [String: Member]] = [:]
    @ObservationIgnored private var historyBatches: [String: (buffer: BufferModel, count: Int)] = [:]
    @ObservationIgnored private var bouncerBatchIDs: Set<String> = []
    @ObservationIgnored private var lastTypingSent: [BufferID: (state: TypingState, at: Date)] = [:]
    @ObservationIgnored private var pendingRecords: [MessageRecord] = []
    /// The latest write of a buffer's saved state; each waits for the one
    /// before (see `writeBuffer`).
    @ObservationIgnored private var bufferWrites: Task<Void, Never>?
    /// Channels closed while joined whose PART the server hasn't confirmed
    /// yet (folded names). What was said there meanwhile is dropped, so it
    /// can't open the channel again.
    @ObservationIgnored private var partingChannels: Set<String> = []
    /// Channels you left or removed while disconnected from a bouncer, which
    /// is still in them (folded names). When the bouncer rejoins one after
    /// connecting, Vela parts it. Kept for this run of Vela only.
    @ObservationIgnored private var pendingParts: Set<String> = []
    /// Channels you rejoined or reopened while disconnected from a bouncer
    /// (folded names), joined after connecting: Vela doesn't send JOINs to
    /// bouncers otherwise, and the bouncer may have left them.
    @ObservationIgnored private var pendingJoins: Set<String> = []
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
    public func restoreBuffers() async {
        guard let database else { return }
        guard let records = try? await database.buffers(networkID: id) else { return }
        for record in records where record.kind != BufferKind.server.rawValue {
            let kind = BufferKind(rawValue: record.kind) ?? .channel
            let buffer = ensureBuffer(name: record.name, kind: kind, persist: false)
            buffer.isMuted = record.isMuted
            buffer.lastReadAt = record.lastReadAt
            buffer.sortOrder = record.sortOrder
            autoRejoin[fold(record.name)] = record.autoRejoin
        }
        sortBuffers()
    }

    @ObservationIgnored private var autoRejoin: [String: Bool] = [:]
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
                buffer.memberMap = [:]
            }
            historyBatches.values.forEach { $0.buffer.isLoadingHistory = false }
            historyBatches = [:]
            partingChannels = []
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
        // Channels to (re)join: configured auto-join plus restored/open channels.
        var toJoin: [(String, String?)] = []
        var seen = Set<String>()
        for channel in config.autoJoin {
            let folded = fold(channel.name)
            guard seen.insert(folded).inserted else { continue }
            let key = channel.hasKey ? keychain.secret(account: Keychain.channelKeyAccount(networkID: id, channel: folded)) : nil
            toJoin.append((channel.name, key))
        }
        for buffer in channels where autoRejoin[buffer.id.foldedName] ?? true {
            if seen.insert(buffer.id.foldedName).inserted { toJoin.append((buffer.name, nil)) }
        }
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
            Task { [weak self] in
                guard let self, let database = self.database else { return }
                let since = (try? await database.newestMessageTime(networkID: self.id)) ?? .distantPast
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
        let historyBuffer = batch.flatMap { historyBatches[$0.id]?.buffer }
        let isHistory = historyBuffer != nil || isPlayback(message)
        if let batch, historyBatches[batch.id] != nil { historyBatches[batch.id]?.count += 1 }

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

        let destination: BufferModel
        if isupport.isChannel(target) {
            if isParting(target) { return }
            destination = ensureBuffer(name: target, kind: .channel)
        } else if fromSelf {
            destination = ensureBuffer(name: target, kind: .query)
        } else if source.isServer || connectionState != .connected || source.nick == "*" || target == "*" {
            destination = serverBuffer
        } else if kind == .notice, self.buffer(named: source.nick) == nil {
            // Notices from services and the like go to the server buffer unless a query is open.
            destination = serverBuffer
        } else {
            destination = ensureBuffer(name: source.nick, kind: .query)
        }

        typingStopped(nick: source.nick, in: destination)

        let isHighlight = !fromSelf && destination.kind == .channel && highlightMatcher.matches(text)
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
        if isSelf(source.nick), !isHistory, pendingParts.remove(fold(channel)) != nil {
            // The bouncer rejoined a channel you left or removed while you
            // were disconnected: leave it now, and keep it closed or left.
            send(IRCMessage(command: "PART", params: [channel]))
            if buffer(named: channel) == nil { partingChannels.insert(fold(channel)) }
            return
        }
        if !isSelf(source.nick), isParting(channel) { return }
        let buffer = ensureBuffer(name: channel, kind: .channel)
        let account = message.param(1).flatMap { $0 == "*" ? nil : $0 }
        let realname = message.param(2)
        if isSelf(source.nick), !isHistory {
            buffer.isJoined = true
            buffer.memberMap = [:]
            buffer.memberRank = { [isupport] in isupport.rank(ofSymbol: $0.topPrefix) }
            autoRejoin[buffer.id.foldedName] = true
            persistBuffer(buffer)
            if supportsChatHistory { fetchLatestHistory(for: buffer) }
        } else if !isHistory {
            buffer.memberMap[fold(source.nick)] = Member(nick: source.nick, userHost: source.userHost, account: account ?? message.account, realname: realname)
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
        guard let buffer = buffer(named: channel) else {
            // The server confirms leaving a channel you closed.
            if isSelf(source.nick) { partingChannels.remove(fold(channel)) }
            return
        }
        let reason = message.param(1)
        if isSelf(source.nick), !isHistory {
            buffer.isJoined = false
            buffer.memberMap = [:]
            buffer.typingExpiry = [:]
            buffer.refreshTyping()
        } else if !isHistory {
            buffer.memberMap.removeValue(forKey: fold(source.nick))
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
                buffer.memberMap = [:]
            } else {
                buffer.memberMap.removeValue(forKey: fold(kicked))
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
            if !isHistory { buffer.memberMap.removeValue(forKey: key) }
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
            if var member = buffer.memberMap.removeValue(forKey: oldKey) {
                member.nick = newNick
                buffer.memberMap[fold(newNick)] = member
            }
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
                    let key = fold(nick)
                    guard var member = buffer.memberMap[key] else { continue }
                    var symbols = Set(member.prefixes)
                    if adding { symbols.insert(symbol) } else { symbols.remove(symbol) }
                    member.prefixes = String(isupport.prefixSymbols.filter { symbols.contains($0) })
                    buffer.memberMap[key] = member
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
        let key = buffer.id.storeKey
        if let database { Task { try? await database.markRedacted(msgid: msgid, in: key) } }
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
                buffer.memberMap = fresh.mapValues { member in
                    var member = member
                    if let old = buffer.memberMap[fold(member.nick)] {
                        member.isAway = old.isAway
                        member.account = member.account ?? old.account
                        member.realname = member.realname ?? old.realname
                    }
                    return member
                }
            }
            pendingNames.removeValue(forKey: key)
        case "433":
            if connectionState == .connected { error("Nickname \(params.first ?? "") is already in use", in: active) }
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

    private func handleBatchStart(_ batch: IRCBatch) {
        switch batch.type {
        case "chathistory":
            guard let target = batch.params.first else { return }
            let kind: BufferKind = isupport.isChannel(target) ? .channel : .query
            let buffer = self.buffer(named: target) ?? ensureBuffer(name: target, kind: kind)
            historyBatches[batch.id] = (buffer, 0)
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
        Task { [weak self] in
            guard let self else { return }
            let newest = try? await self.database?.newestMessageTime(in: buffer.id.storeKey)
            if let newest {
                self.sendRaw("CHATHISTORY AFTER \(target) timestamp=\(IRCTime.format(newest)) \(limit)")
            } else {
                self.sendRaw("CHATHISTORY LATEST \(target) * \(limit)")
            }
        }
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
        if let database, let records = try? await database.messages(in: buffer.id.storeKey, before: oldest, limit: pageSize), !records.isEmpty {
            buffer.insertSorted(records.map(ChatLine.init(record:)))
            await loadReactions(for: records.compactMap(\.msgid), in: buffer)
            if records.count >= pageSize {
                buffer.isLoadingHistory = false
                return
            }
        }
        if supportsChatHistory, isConnected, client != nil, buffer.kind != .server {
            let since = buffer.lines.first?.time ?? oldest
            pendingBeforeRequests.insert(buffer.id)
            sendRaw("CHATHISTORY BEFORE \(buffer.name) timestamp=\(IRCTime.format(since)) \(historyLimit)")
            // `isLoadingHistory` is cleared when the batch ends.
        } else {
            buffer.isLoadingHistory = false
            buffer.hasMoreHistory = false
        }
    }

    private func loadReactions(for msgids: [String], in buffer: BufferModel) async {
        guard let database, !msgids.isEmpty,
              let reactions = try? await database.reactions(in: buffer.id.storeKey, msgids: msgids) else { return }
        for reaction in reactions {
            buffer.setReaction(msgid: reaction.msgid, nick: reaction.nick, emoji: reaction.emoji, active: true)
        }
    }

    // MARK: Outbound

    private func handleSent(_ message: IRCMessage) {
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
        guard let client else { return }
        Task { await client.send(message) }
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
        case .join(let channels, let keys):
            // Joined on purpose: a part still waiting for a bouncer is off.
            for channel in channels { pendingParts.remove(fold(channel)) }
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
        guard let database else { return }
        let key = buffer.id.storeKey
        Task { try? await database.setReaction(ReactionRecord(msgid: msgid, nick: nick, emoji: emoji), in: key, active: active) }
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
        let buffer = BufferModel(id: BufferID(networkID: id, foldedName: key), name: name, kind: kind)
        // New buffers go after the others of their kind, like a new tab.
        buffer.sortOrder = (buffers.filter { $0.kind == kind }.map(\.sortOrder).max() ?? -1) + 1
        buffer.selfNick = { [unowned self] in self.nick }
        buffer.memberRank = { [isupport] in isupport.rank(ofSymbol: $0.topPrefix) }
        bufferIndex[key] = buffer
        buffers.append(buffer)
        // Opened again on purpose (joined, reopened): no longer leaving it.
        partingChannels.remove(key)
        sortBuffers()
        if persist { persistBuffer(buffer) }
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
    public func close(_ buffer: BufferModel) {
        guard buffer.kind != .server else { return }
        let folded = buffer.id.foldedName
        if buffer.kind == .channel {
            if buffer.isJoined && isConnected {
                send(IRCMessage(command: "PART", params: [buffer.name]))
                partingChannels.insert(folded)
            } else if !isConnected, isBouncer, rejoins(buffer) {
                // The bouncer is still in it and rejoins it on the next
                // connect: part it then. This lasts until Vela quits.
                pendingParts.insert(folded)
            }
            pendingJoins.remove(folded)
        }
        bufferIndex.removeValue(forKey: folded)
        buffers.removeAll { $0.id == buffer.id }
        autoRejoin.removeValue(forKey: folded)
        let key = buffer.id.storeKey
        writeBuffer { try await $0.deleteBuffer(key, keepMessages: true) }
        host?.sessionDidChangeUnreadCounts(self)
    }

    /// Leaves a channel but keeps it in the list, not joined, with its
    /// history (`/part`, Leave Channel). It isn't rejoined on the next
    /// connect, unless it's on the network's auto-join list.
    ///
    /// Disconnected from a bouncer, the PART waits: the bouncer is still in
    /// the channel and rejoins it when Vela connects, so Vela parts it then.
    func leave(_ channel: BufferModel, reason: String? = nil) {
        guard channel.kind == .channel else { return }
        let folded = channel.id.foldedName
        let wasIn = isIn(channel)
        autoRejoin[folded] = false
        pendingJoins.remove(folded)
        persistBuffer(channel)
        if isConnected {
            send(IRCMessage(command: "PART", params: reason.map { [channel.name, $0] } ?? [channel.name]))
        } else if wasIn, isBouncer {
            pendingParts.insert(folded)
        }
    }

    /// Joins a channel you left again (undoing Leave): now when connected,
    /// with its auto-join key if it has one, or on the next connect.
    func rejoin(_ channel: BufferModel) {
        guard channel.kind == .channel else { return }
        let folded = channel.id.foldedName
        autoRejoin[folded] = true
        pendingParts.remove(folded)
        persistBuffer(channel)
        if isConnected {
            sendJoin(channel)
        } else if isBouncer {
            pendingJoins.insert(folded)
        }
    }

    /// Whether you're in `channel`, or will be once connected: what Leave
    /// leaves. A channel you're not in (left, kicked, or not joined yet
    /// while connected) shows dimmed, and closing it removes it.
    public func isIn(_ channel: BufferModel) -> Bool {
        guard channel.kind == .channel else { return false }
        return channel.isJoined || (!isConnected && rejoins(channel))
    }

    /// Whether `buffer` is joined again on the next connect (`/part` says no).
    func rejoins(_ buffer: BufferModel) -> Bool {
        autoRejoin[buffer.id.foldedName] ?? true
    }

    /// A ZNC or soju network: the bouncer joins channels, not Vela.
    var isBouncer: Bool { config.bouncerKind != .none }

    /// Whether `channel` was closed while joined and the server hasn't
    /// confirmed the PART yet.
    private func isParting(_ channel: String) -> Bool {
        !partingChannels.isEmpty && partingChannels.contains(fold(channel)) && buffer(named: channel) == nil
    }

    /// Sends JOIN for `channel`, with its auto-join key if it has one.
    private func sendJoin(_ channel: BufferModel) {
        let key = joinKey(forChannel: channel.id.foldedName)
        send(IRCMessage(command: "JOIN", params: [channel.name] + (key.map { [$0] } ?? [])))
    }

    /// The key of `channel`'s auto-join entry (folded name), if it has one
    /// stored.
    func joinKey(forChannel folded: String) -> String? {
        guard config.autoJoin.contains(where: { $0.hasKey && fold($0.name) == folded }) else { return nil }
        return keychain.secret(account: Keychain.channelKeyAccount(networkID: id, channel: folded))
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
            pendingParts.remove(folded)
            if closed.autoRejoin {
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
    /// never counted (seen on screen, history, your own) stay uncounted.
    public func markRead(_ buffer: BufferModel, upTo time: Date) {
        let readTo = max(buffer.lastReadAt ?? .distantPast, time)
        var unread = 0
        var highlights = 0
        // Lines are in time order: count back to the read position.
        for line in buffer.lines.reversed() {
            guard line.time > readTo else { break }
            guard !line.isHistory, !line.isSelf, line.kind.isConversation else { continue }
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

    private func sortBuffers() {
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

    private func persistBuffer(_ buffer: BufferModel) {
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
            autoRejoin: autoRejoin[buffer.id.foldedName] ?? true
        )
        writeBuffer { try await $0.upsertBuffer(record) }
    }

    /// Writes buffer state in the order it changes: each write waits for the
    /// one before, so closing a channel and reopening it straight away (⌘Z)
    /// can't save the reopened channel before deleting the closed one.
    func writeBuffer(_ write: @escaping @Sendable (VelaDatabase) async throws -> Void) {
        guard let database else { return }
        let previous = bufferWrites
        bufferWrites = Task {
            await previous?.value
            try? await write(database)
        }
    }

    /// Waits for every buffer write made so far (tests).
    func bufferWritesFinished() async {
        await bufferWrites?.value
    }

    private func loadRecentScrollback(for buffer: BufferModel) {
        guard let database else { return }
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
            guard var member = buffer.memberMap[key] else { continue }
            update(&member)
            buffer.memberMap[key] = member
        }
    }

    // MARK: Lines

    func add(_ line: ChatLine, to buffer: BufferModel) {
        // A copy of a line already shown (a bouncer replaying what we saw
        // live) is neither shown nor stored again.
        guard buffer.append(line, limit: host?.behavior.scrollbackInMemory ?? 1000) else { return }
        host?.session(self, didAdd: line, to: buffer)
        if buffer.kind != .server || line.kind.isConversation {
            enqueue(line.record(networkID: id, bufferName: buffer.id.foldedName))
        }
        guard !line.isHistory, !line.isSelf else { return }

        let visible = host?.isBufferVisible(buffer.id) ?? false
        let countsAsUnread = line.kind.isConversation
        if !visible && countsAsUnread {
            if buffer.unreadCount == 0 {
                // Mark where the new lines start as soon as the first one
                // arrives, so a channel left open in an unfocused window
                // shows the marker without waiting for focus.
                buffer.unreadMarkerAfter = buffer.lastReadAt ?? .distantPast
            }
            buffer.unreadCount += 1
            if line.isHighlight || (buffer.kind == .query && line.kind != .notice) {
                buffer.highlightCount += 1
            }
            host?.sessionDidChangeUnreadCounts(self)
        }
        if line.isHighlight || (buffer.kind == .query && line.kind.isConversation) {
            if !buffer.isMuted || line.isHighlight {
                host?.session(self, didReceiveNotable: line, in: buffer)
            }
        }
    }

    func info(_ text: String, in buffer: BufferModel, kind: ChatLineKind = .info) {
        add(ChatLine(kind: kind, text: text), to: buffer)
    }

    func error(_ text: String, in buffer: BufferModel) {
        add(ChatLine(kind: .error, text: text), to: buffer)
    }

    // MARK: Persistence batching

    private func enqueue(_ record: MessageRecord) {
        guard database != nil else { return }
        pendingRecords.append(record)
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.flushPendingRecords()
        }
    }

    private func flushPendingRecords() {
        flushTask = nil
        guard let database, !pendingRecords.isEmpty else { return }
        let records = pendingRecords
        pendingRecords = []
        Task { try? await database.append(records) }
    }

    // MARK: Helpers

    func fold(_ name: String) -> String { isupport.caseMapping.fold(name) }

    func isSelf(_ nick: String) -> Bool { fold(nick) == fold(self.nick) }

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
