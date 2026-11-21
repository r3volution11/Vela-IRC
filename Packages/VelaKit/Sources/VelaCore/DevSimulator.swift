// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG

import Foundation
import Observation
import VelaIRC
import VelaStore

/// Vela Dev's state simulator (Developer menu, Debug builds only): puts the
/// window into states that are hard to reach on a real network on demand —
/// offline, connecting, an incoming mention, a very long nick and message, a
/// huge channel, a reconnect storm.
///
/// It all happens on a network of its own, "Simulator". Your real networks
/// are never touched, and nothing is saved: the network lives in memory
/// (it isn't in networks.json and has no database, so no history), its
/// host (`SimulatorHost`) keeps it out of chat logs, the Dock's offline
/// mark and saved settings, AppModel keeps it out of the saved selection,
/// Spotlight, Siri and Shortcuts, and its connection is a stand-in that
/// never opens a socket. Quitting forgets it, and so does Remove Simulator
/// Network.
///
/// The states go through `NetworkSession`'s own event handling, the same
/// code an IRC server's lines go through, so what you see is what a real
/// network would show. A mention posts a real notification when its
/// channel isn't in front, as one from a real network would.
@Observable
public final class DevSimulator {
    public static let networkName = "Simulator"
    /// `.invalid` never resolves (RFC 2606); the transport never tries.
    public static let host = "simulator.invalid"
    public static let nick = "tester"
    public static let channelName = "#simulator"
    public static let hugeChannelName = "#huge"
    /// Lines its buffers keep in memory: more than #huge has.
    static let scrollbackInMemory = 12_000

    /// The networks simulators made in this process. AppModel leaves them
    /// out of what it saves and what it hands to Spotlight, Siri and
    /// Shortcuts.
    static var networkIDs: Set<UUID> = []

    public static func isSimulated(_ networkID: UUID) -> Bool {
        networkIDs.contains(networkID)
    }

    public let app: AppModel
    public private(set) var session: NetworkSession?
    /// A reconnect storm is running.
    public private(set) var isStorming = false

    @ObservationIgnored private var host: SimulatorHost?
    @ObservationIgnored private var stormTask: Task<Void, Never>?
    /// Each channel's members when it was last joined (folded name →
    /// members), so reconnecting puts them back.
    @ObservationIgnored private var rosters: [String: [String: Member]] = [:]
    @ObservationIgnored private var random = ScrollBenchmarkContent.Random(seed: 0x5649_4D55_4C41_5445)
    @ObservationIgnored private var mentionCount = 0

    public init(app: AppModel) {
        self.app = app
    }

    public var isOnline: Bool { session?.connectionState == .connected }

    // MARK: Connection

    /// The connection drops: the network shows offline, with the reason.
    public func goOffline(reason: String = "Connection reset by peer (simulated)") {
        let session = ensureSession()
        stopReconnectStorm()
        guard session.connectionState != .disconnected else { return }
        saveRosters(session)
        session.handle(.disconnected(reason: reason))
    }

    /// Connecting, and it stays there until ``goOnline()``.
    public func startConnecting() {
        let session = ensureSession()
        stopReconnectStorm()
        if session.connectionState != .disconnected {
            saveRosters(session)
            session.handle(.disconnected(reason: "Reconnecting (simulated)"))
        }
        session.handle(.stateChanged(.connecting))
    }

    /// Connected, with its channels joined again.
    public func goOnline() {
        let session = ensureSession()
        stopReconnectStorm()
        guard session.connectionState != .connected else { return }
        register(session)
    }

    // MARK: Messages

    /// Someone in #simulator says your nick. With #simulator in front it's
    /// just a highlighted line; anywhere else it counts as a mention and
    /// posts a notification.
    @discardableResult
    public func mention() -> ChatLine? {
        let session = ensureOnline()
        mentionCount += 1
        let nick = ScrollBenchmarkContent.Generator.nicks[mentionCount % ScrollBenchmarkContent.Generator.nicks.count]
        let texts = [
            "\(Self.nick): can you take a look at this when you get a sec?",
            "hey \(Self.nick), this is a simulated mention (#\(mentionCount))",
            "\(Self.nick) ping — the build is green again",
        ]
        feed(session, ":\(nick)!\(nick)@user/\(nick) PRIVMSG \(Self.channelName) :\(texts[mentionCount % texts.count])")
        return session.buffer(named: Self.channelName)?.lines.last
    }

    /// A message from someone with a very long nick: a long paragraph, an
    /// unbroken 200-character word and a long link. Selects #simulator.
    @discardableResult
    public func longMessage() -> ChatLine? {
        let session = ensureOnline()
        let nick = Self.longNick
        feed(session, ":\(nick)!\(nick)@a-very-long-hostname.users.simulator.invalid JOIN \(Self.channelName)")
        feed(session, ":\(nick)!\(nick)@a-very-long-hostname.users.simulator.invalid PRIVMSG \(Self.channelName) :\(Self.longText)")
        guard let buffer = session.buffer(named: Self.channelName) else { return nil }
        app.select(buffer)
        return buffer.lines.last
    }

    /// #huge: `members` members and `lines` messages over five days (the
    /// scroll benchmark's text, without its links). Selects it.
    @discardableResult
    public func hugeChannel(members memberCount: Int = 5_000, lines lineCount: Int = 10_000) -> BufferModel? {
        let session = ensureOnline()
        let buffer = session.ensureBuffer(name: Self.hugeChannelName, kind: .channel, persist: false)
        if buffer.lines.count < lineCount {
            var generator = ScrollBenchmarkContent.Generator(mix: .text, selfNick: Self.nick)
            let generated = generator.lines(count: lineCount)
            buffer.insertSorted(generated.lines)
            for reaction in generated.reactions {
                buffer.setReaction(msgid: reaction.msgid, nick: reaction.nick, emoji: reaction.emoji, active: true)
            }
            buffer.hasMoreHistory = false
        }
        feed(session, ":\(Self.nick)!\(Self.nick)@simulator.invalid JOIN \(Self.hugeChannelName)")
        feed(session, ":\(Self.host) 332 \(Self.nick) \(Self.hugeChannelName) :A simulated channel with \(memberCount.formatted()) members and \(lineCount.formatted()) messages")
        buffer.replaceMembers(Self.members(count: memberCount, session: session, random: &random))
        rosters[buffer.id.foldedName] = buffer.memberMap
        app.select(buffer)
        return buffer
    }

    // MARK: Reconnect storm

    /// The connection drops and comes back `cycles` times in a row, with a
    /// netsplit's worth of quits and joins in #simulator each time. Ends
    /// connected.
    public func startReconnectStorm(cycles: Int = 15, interval: Duration = .milliseconds(400)) {
        let session = ensureOnline()
        stormTask?.cancel()
        isStorming = true
        stormTask = Task { [weak self] in
            for cycle in 1...max(1, cycles) {
                guard let self, !Task.isCancelled else { return }
                self.saveRosters(session)
                session.handle(.disconnected(reason: "Ping timeout: 240 seconds (simulated storm, \(cycle) of \(cycles))"))
                try? await Task.sleep(for: interval / 3)
                guard !Task.isCancelled else { break }
                session.handle(.stateChanged(.connecting))
                try? await Task.sleep(for: interval / 3)
                guard !Task.isCancelled else { break }
                self.register(session)
                self.netsplit(session)
                try? await Task.sleep(for: interval / 3)
            }
            self?.stormEnded()
        }
    }

    public func stopReconnectStorm() {
        guard stormTask != nil else { return }
        stormTask?.cancel()
        stormTask = nil
        isStorming = false
    }

    /// Waits for a running storm to finish (tests).
    func waitForStorm() async {
        await stormTask?.value
    }

    private func stormEnded() {
        stormTask = nil
        isStorming = false
        if let session, session.connectionState != .connected { register(session) }
    }

    // MARK: Removing

    /// Takes the Simulator network away. Selection moves elsewhere.
    public func removeNetwork() {
        stopReconnectStorm()
        guard let session else { return }
        app.removeSimulatedSession(session)
        Self.networkIDs.remove(session.id)
        self.session = nil
        host = nil
        rosters = [:]
    }

    // MARK: Session

    /// The Simulator network, made (connected, in #simulator) if it isn't there.
    @discardableResult
    func ensureSession() -> NetworkSession {
        if let session, app.session(for: session.id) != nil { return session }
        let config = NetworkConfig(name: Self.networkName, host: Self.host, nick: Self.nick, autoConnect: false)
        let session = NetworkSession(config: config, database: nil, transportFactory: { _ in SimulatedTransport() })
        let host = SimulatorHost(app: app)
        Self.networkIDs.insert(session.id)
        app.installSimulatedSession(session, host: host)
        self.host = host
        self.session = session
        register(session)
        populateChannel(session)
        return session
    }

    private func ensureOnline() -> NetworkSession {
        let session = ensureSession()
        if session.connectionState != .connected, !isStorming { register(session) }
        return session
    }

    /// What a server's welcome does: connecting, registering, connected,
    /// then the channels joined again with their members.
    private func register(_ session: NetworkSession) {
        if session.connectionState == .disconnected { session.handle(.stateChanged(.connecting)) }
        session.handle(.stateChanged(.registering))
        session.handle(.capabilitiesChanged(["server-time", "message-tags", "batch", "away-notify", "draft/message-redaction"]))
        var support = ISupport()
        support.apply(["PREFIX=(qaohv)~&@%+", "CHANTYPES=#", "NETWORK=\(Self.networkName)", "CASEMAPPING=rfc1459", "NICKLEN=64"])
        session.handle(.isupportChanged(support))
        session.handle(.stateChanged(.connected))
        session.handle(.registered(nick: Self.nick))
        for buffer in session.channels {
            feed(session, ":\(Self.nick)!\(Self.nick)@simulator.invalid JOIN \(buffer.name)")
            if let roster = rosters[buffer.id.foldedName] { buffer.replaceMembers(roster) }
        }
    }

    /// #simulator: a few dozen people and some conversation.
    private func populateChannel(_ session: NetworkSession) {
        feed(session, ":\(Self.nick)!\(Self.nick)@simulator.invalid JOIN \(Self.channelName)")
        feed(session, ":\(Self.host) 332 \(Self.nick) \(Self.channelName) :Vela Dev's state simulator · nothing here is real or saved")
        let nicks = Array(ScrollBenchmarkContent.Generator.nicks.prefix(36))
        for chunk in stride(from: 0, to: nicks.count, by: 12) {
            let names = nicks[chunk..<min(chunk + 12, nicks.count)].enumerated().map { index, nick in
                (chunk == 0 && index < 2 ? "@" : chunk == 0 && index < 5 ? "+" : "") + nick
            }
            feed(session, ":\(Self.host) 353 \(Self.nick) = \(Self.channelName) :\(names.joined(separator: " "))")
        }
        // A server's NAMES lists you too.
        feed(session, ":\(Self.host) 353 \(Self.nick) = \(Self.channelName) :\(Self.nick)")
        feed(session, ":\(Self.host) 366 \(Self.nick) \(Self.channelName) :End of /NAMES list.")
        for (nick, text) in [
            ("marisol", "welcome to the simulator — use the Developer menu to change what happens here"),
            ("kenji", "offline, connecting, mentions, long messages, a huge channel, reconnect storms"),
            ("ada", "none of it touches a real network, and quitting forgets all of it"),
        ] {
            feed(session, ":\(nick)!\(nick)@user/\(nick) PRIVMSG \(Self.channelName) :\(text)")
        }
        if let buffer = session.buffer(named: Self.channelName) { rosters[buffer.id.foldedName] = buffer.memberMap }
    }

    /// A handful of people quit and come back, as after a netsplit.
    private func netsplit(_ session: NetworkSession) {
        guard let buffer = session.buffer(named: Self.channelName) else { return }
        let others = buffer.members.map(\.nick).filter { $0 != Self.nick }
        guard !others.isEmpty else { return }
        let split = (0..<min(6, others.count)).map { _ in others[random.int(others.count)] }
        for nick in Set(split) {
            feed(session, ":\(nick)!\(nick)@user/\(nick) QUIT :*.net *.split")
        }
        for nick in Set(split) {
            feed(session, ":\(nick)!\(nick)@user/\(nick) JOIN \(Self.channelName)")
        }
    }

    private func saveRosters(_ session: NetworkSession) {
        for buffer in session.channels where !buffer.memberMap.isEmpty {
            rosters[buffer.id.foldedName] = buffer.memberMap
        }
    }

    private func feed(_ session: NetworkSession, _ line: String) {
        guard let message = IRCMessage(line: line) else { return }
        session.handle(.message(message, batch: nil))
    }

    // MARK: Content

    /// 64 characters, the most Vela's simulator network allows (NICKLEN).
    static let longNick = "an_extraordinarily_long_nickname_that_keeps_going_and_going_1234"

    static let longText: String = {
        let paragraph = "This is a deliberately long message for checking how rows wrap, how the hover toolbar and the timestamps sit beside many lines of text, and how the composer, the sidebar and the member list cope with a nick this long. "
        let word = String(repeating: "unbroken", count: 25)
        let link = "https://example.com/a/really/long/path/that/goes/on/" + String(repeating: "and-on-", count: 12) + "?query=" + String(repeating: "x", count: 40)
        return paragraph + paragraph + word + " " + link + " " + paragraph
    }()

    /// `count` members with made-up nicks, a few of them ops and voiced.
    static func members(count: Int, session: NetworkSession, random: inout ScrollBenchmarkContent.Random) -> [String: Member] {
        let names = ScrollBenchmarkContent.Generator.nicks
        var members: [String: Member] = [:]
        members.reserveCapacity(count + 1)
        members[session.fold(Self.nick)] = Member(nick: Self.nick, prefixes: "@", userHost: "\(Self.nick)@simulator.invalid")
        var index = 0
        while members.count < count + 1 {
            let round = index / names.count
            let member = names[index % names.count] + (round == 0 ? "" : String(round))
            index += 1
            let roll = random.int(1_000)
            let prefix = roll < 8 ? "@" : roll < 40 ? "+" : ""
            members[session.fold(member)] = Member(nick: member, prefixes: prefix, userHost: "\(member)@user/\(member)", isAway: roll > 900)
        }
        return members
    }
}

/// The Simulator network's host: the app for what shows on screen (what's
/// visible, unread counts, notifications), nothing for what's saved or
/// logged. It never reconnects on its own.
final class SimulatorHost: SessionHost {
    weak var app: AppModel?

    init(app: AppModel) {
        self.app = app
    }

    func clientConfig(for session: NetworkSession) -> IRCClientConfig {
        var config = IRCClientConfig(host: DevSimulator.host, nick: session.config.nick)
        config.pingInterval = .zero
        config.pingTimeout = .zero
        return config
    }

    func isBufferVisible(_ id: BufferID) -> Bool { app?.isBufferVisible(id) ?? false }
    func activeBuffer(in session: NetworkSession) -> BufferModel? { app?.activeBuffer(in: session) }

    func session(_ session: NetworkSession, didReceiveNotable line: ChatLine, in buffer: BufferModel) {
        app?.session(session, didReceiveNotable: line, in: buffer)
    }

    func session(_ session: NetworkSession, didUpdateBouncerNetworks networks: [BouncerNetwork]) {}
    /// Never saved to networks.json.
    func sessionDidChangeConfig(_ session: NetworkSession) {}
    func sessionDidChangeUnreadCounts(_ session: NetworkSession) { app?.sessionDidChangeUnreadCounts(session) }
    /// No chat-log lines and no Dock offline mark.
    func sessionDidChangeConnection(_ session: NetworkSession) {}
    /// Not logged.
    func session(_ session: NetworkSession, didAdd line: ChatLine, to buffer: BufferModel) {}
    func session(_ session: NetworkSession, didRedact line: ChatLine, by nick: String?, reason: String?, at time: Date, isHistory: Bool, in buffer: BufferModel) {}
    /// Never donated to Siri.
    func session(_ session: NetworkSession, didSendComposerMessageIn buffer: BufferModel) {}

    /// The app's, but it never reconnects by itself, and it keeps enough
    /// lines in memory for #huge's.
    var behavior: SessionBehavior {
        var behavior = app?.behavior ?? SessionBehavior()
        behavior.autoReconnect = false
        behavior.scrollbackInMemory = max(behavior.scrollbackInMemory, DevSimulator.scrollbackInMemory)
        return behavior
    }

    var historyStorage: HistoryStorage { .memoryOnly }
}

/// The Simulator network's connection: Connect (from the Network menu)
/// fails at once, without opening anything.
nonisolated struct SimulatedTransport: IRCTransport {
    func open() async throws -> AsyncThrowingStream<String, Error> {
        throw IRCTransportError.connectionFailed("The Simulator network has no server. Use the Developer menu to change its state.")
    }

    func send(_ line: String) async throws {}
    func close() async {}
}

#endif
