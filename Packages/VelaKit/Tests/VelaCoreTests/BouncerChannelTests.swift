// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

/// The server side of a network, scripted to answer as the real thing does:
/// ZNC (`*status detach`, a PART, then its two replies), soju (BouncerServ's
/// `channel update -detached`, a PART with "Detach", then its reply, with
/// the command echoed back under echo-message) or a plain IRC server.
/// `attached` are the channels a bouncer joins the client into as it
/// connects. With `detachWorks` false, the bouncer answers without
/// detaching anything.
nonisolated private func reply(
    to line: String, kind: BouncerKind, caps: String, attached: [String], detachWorks: Bool
) -> [String] {
    let server = switch kind {
    case .znc: "znc.test"
    case .soju: "soju.test"
    case .none: "irc.test"
    }
    if line.hasPrefix("CAP LS") { return [":\(server) CAP * LS :\(caps)"] }
    if line.hasPrefix("CAP REQ") {
        let requested = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
        return [":\(server) CAP * ACK :\(requested)"]
    }
    if line == "CAP END" {
        var lines = [":\(server) 001 doug :Welcome", ":\(server) 005 doug CHANTYPES=# CASEMAPPING=rfc1459 :are supported"]
        for channel in attached { lines += [":doug!d@host JOIN \(channel)", ":\(server) 366 doug \(channel) :End"] }
        return lines
    }
    if line.hasPrefix("JOIN ") {
        let channel = String(line.dropFirst(5).prefix { $0 != " " })
        return [":doug!d@host JOIN \(channel)", ":\(server) 366 doug \(channel) :End"]
    }
    if line.hasPrefix("PART ") {
        let channel = String(line.dropFirst(5).prefix { $0 != " " })
        return [":doug!d@host PART \(channel)"]
    }
    let zncDetach = "PRIVMSG *status :detach "
    if kind == .znc, line.hasPrefix(zncDetach) {
        let channel = String(line.dropFirst(zncDetach.count))
        let status = ":*status!znc@znc.in PRIVMSG doug :"
        guard detachWorks else {
            return [status + "There were 0 channels matching [\(channel)]", status + "Detached 0 channels"]
        }
        return [":doug!d@host PART \(channel)", status + "There was 1 channel matching [\(channel)]", status + "Detached 1 channel"]
    }
    let sojuUpdate = "PRIVMSG BouncerServ :channel update "
    if kind == .soju, line.hasPrefix(sojuUpdate) {
        let channel = String(line.dropFirst(sojuUpdate.count).prefix { $0 != " " })
        let echo = caps.contains("echo-message") ? [":doug!d@host \(line)"] : []
        let service = ":BouncerServ!BouncerServ@BouncerServ PRIVMSG doug :"
        guard detachWorks else {
            return echo + [service + "error: unknown channel \"\(channel)\" (type \"help\" for a list of commands)"]
        }
        return echo + [":doug!d@host PART \(channel) :Detach", service + "updated channel \"\(channel)\""]
    }
    return []
}

/// Leaving, detaching, hiding and removing channels on networks with and
/// without a bouncer: the exact commands each sends, what's remembered
/// across a relaunch, what a bouncer relays, and undo.
@MainActor
@Suite("Leaving channels with and without a bouncer")
struct BouncerChannelTests {
    /// An app with one network, wired to a scripted server.
    @MainActor
    private struct Wired {
        let app: AppModel
        let session: NetworkSession
        let factory: MockTransportFactory
        let folder: TemporaryFolder
        let keychain: Keychain
        var transport: MockTransport { factory.latest! }
        var sent: [String] { transport.sentLines }

        func channel(_ name: String) throws -> BufferModel {
            try #require(session.buffer(named: name))
        }

        /// The network as saved in networks.json.
        func saved() throws -> NetworkConfig? {
            let store = NetworkConfigStore(fileURL: folder.url.appending(path: "networks.json"))
            try store.load()
            return store.networks.first { $0.id == session.id }
        }
    }

    private static func config(_ kind: BouncerKind, autoJoin: [AutoJoinChannel] = []) -> NetworkConfig {
        var config = NetworkConfig(name: kind == .none ? "Libera.Chat" : kind == .znc ? "ZNC" : "Libera via soju", host: "bouncer.test", nick: "doug", autoJoin: autoJoin)
        config.bouncerKind = kind
        if kind == .soju {
            // A network soju provides, bound with BOUNCER BIND.
            config.parentNetworkID = UUID()
            config.bouncerNetworkID = "libera"
        }
        return config
    }

    private static func defaultCaps(_ kind: BouncerKind) -> String {
        switch kind {
        case .znc: "server-time znc.in/self-message"
        case .soju: "server-time echo-message message-tags soju.im/bouncer-networks draft/chathistory"
        case .none: "server-time"
        }
    }

    /// An app around `config`, its network not connected yet.
    private func makeApp(
        _ config: NetworkConfig,
        caps: String? = nil,
        attached: [String] = [],
        detachWorks: Bool = true,
        database: VelaDatabase? = nil,
        keychain: Keychain = .inMemory(),
        folder: TemporaryFolder = TemporaryFolder()
    ) -> Wired {
        let kind = config.bouncerKind
        let caps = caps ?? Self.defaultCaps(kind)
        let factory = MockTransportFactory { transport, _ in
            transport.setResponder { line in reply(to: line, kind: kind, caps: caps, attached: attached, detachWorks: detachWorks) }
        }
        let app = AppModel(
            settings: SettingsStore(fileURL: folder.url.appending(path: "settings.json"), watchForChanges: false),
            networkStore: NetworkConfigStore(fileURL: folder.url.appending(path: "networks.json")),
            database: database,
            keychain: keychain,
            notifier: SilentNotifier(),
            isDemo: true
        )
        let session = NetworkSession(config: config, database: database, transportFactory: factory.makeTransport)
        app.installDemoSessions([session])
        return Wired(app: app, session: session, factory: factory, folder: folder, keychain: keychain)
    }

    /// `makeApp`, connected and registered, with `ready` true.
    private func connect(
        _ config: NetworkConfig,
        caps: String? = nil,
        attached: [String] = [],
        detachWorks: Bool = true,
        database: VelaDatabase? = nil,
        keychain: Keychain = .inMemory(),
        until ready: @escaping (NetworkSession) -> Bool = { _ in true }
    ) async throws -> Wired {
        let wired = makeApp(config, caps: caps, attached: attached, detachWorks: detachWorks, database: database, keychain: keychain)
        wired.session.connect()
        try await waitUntil { wired.session.isConnected && attached.allSatisfy { wired.session.buffer(named: $0)?.isJoined == true } && ready(wired.session) }
        return wired
    }

    /// An undo manager that groups only where a test says.
    private func undoManager(for app: AppModel) -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        app.undoManager = undoManager
        return undoManager
    }

    private func event(_ undoManager: UndoManager, _ body: () throws -> Void) rethrows {
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        try body()
    }

    private func feed(_ session: NetworkSession, _ lines: String...) {
        for line in lines { session.handle(.message(IRCMessage(line: line)!, batch: nil)) }
    }

    private func waitForMessage(_ text: String, in key: BufferKey, of database: VelaDatabase) async throws -> Bool {
        for _ in 0..<60 {
            if try await database.latestMessages(in: key, limit: 20).contains(where: { $0.text == text }) { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    // MARK: How Vela knows it's a bouncer

    @Test func theBouncerIsTheNetworksOwnOrTheOneItsCapabilitiesGiveAway() {
        let session = NetworkSession(config: Self.config(.none), database: nil)
        #expect(session.bouncerKind == .none)
        #expect(!session.isBouncer)
        session.capabilities = ["server-time", "znc.in/playback"]
        #expect(session.bouncerKind == .znc)
        session.capabilities = ["soju.im/bouncer-networks", "echo-message"]
        #expect(session.bouncerKind == .soju)
        // What the network says wins.
        let znc = NetworkSession(config: Self.config(.znc), database: nil)
        znc.capabilities = ["soju.im/bouncer-networks"]
        #expect(znc.bouncerKind == .znc)
        #expect(znc.bouncerName == "ZNC")
        #expect(znc.bouncerServiceNick == "*status")
        #expect(NetworkSession(config: Self.config(.soju), database: nil).bouncerServiceNick == "BouncerServ")
    }

    @Test func detachCommands() {
        #expect(NetworkSession.detachCommand(for: "#vela", bouncer: .znc) == "detach #vela")
        #expect(NetworkSession.detachCommand(for: "#vela", bouncer: .soju) == "channel update #vela -detached true")
        #expect(NetworkSession.detachCommand(for: "#vela", bouncer: .none) == nil)
        // soju reads its arguments like a shell.
        #expect(NetworkSession.detachCommand(for: "#it's", bouncer: .soju) == "channel update \"#it's\" -detached true")
        #expect(NetworkSession.sojuArgument("#a\"b\\c") == "\"#a\\\"b\\\\c\"")
    }

    // MARK: A network without a bouncer

    /// Leave parts, keeps the channel, and takes it off the auto-join list,
    /// so it stays left when Vela reconnects. Join puts the entry back where
    /// it was and joins with its key, which stays in the Keychain meanwhile.
    @Test func leaveTakesAChannelOffTheAutoJoinListAndJoinPutsItBack() async throws {
        let keychain = Keychain.inMemory()
        let config = Self.config(.none, autoJoin: [
            AutoJoinChannel(name: "#a"), AutoJoinChannel(name: "#Secret", hasKey: true), AutoJoinChannel(name: "#c"),
        ])
        let account = Keychain.channelKeyAccount(networkID: config.id, channel: "#secret")
        try keychain.setSecret("hunter2", account: account)
        let wired = try await connect(config, keychain: keychain) { session in
            ["#a", "#Secret", "#c"].allSatisfy { session.buffer(named: $0)?.isJoined == true }
        }
        let (app, session) = (wired.app, wired.session)
        #expect(wired.sent.contains("JOIN #Secret hunter2"))
        let secret = try wired.channel("#Secret")

        app.leave(secret)
        try await waitUntil { !secret.isJoined }
        #expect(wired.sent.last == "PART #Secret")
        #expect(session.buffer(named: "#Secret") === secret)
        #expect(session.config.autoJoin.map(\.name) == ["#a", "#c"])
        #expect(try wired.saved()?.autoJoin.map(\.name) == ["#a", "#c"])
        #expect(keychain.secret(account: account) == "hunter2")
        #expect(app.recentlyClosed.isEmpty)

        // It stays left when Vela reconnects.
        session.reconnect()
        let second = try #require(await wired.factory.waitForTransport(count: 2))
        try await waitUntil { session.buffer(named: "#c")?.isJoined == true && session.buffer(named: "#a")?.isJoined == true }
        try await Task.sleep(for: .milliseconds(100))
        #expect(second.sentLines.filter { $0.hasPrefix("JOIN") } == ["JOIN #a", "JOIN #c"])
        #expect(!secret.isJoined)

        // Join Channel: back on the list where it was, joined with its key.
        app.rejoin(secret)
        try await waitUntil { secret.isJoined }
        #expect(second.sentLines.last == "JOIN #Secret hunter2")
        #expect(session.config.autoJoin == [
            AutoJoinChannel(name: "#a"), AutoJoinChannel(name: "#Secret", hasKey: true), AutoJoinChannel(name: "#c"),
        ])
        #expect(try wired.saved()?.autoJoin.map(\.name) == ["#a", "#Secret", "#c"])
    }

    /// A channel you left keeps its old auto-join entry across a relaunch.
    @Test func theLeftEntryOutlastsARelaunch() async throws {
        let database = try VelaDatabase.inMemory()
        let keychain = Keychain.inMemory()
        let config = Self.config(.none, autoJoin: [AutoJoinChannel(name: "#a"), AutoJoinChannel(name: "#secret", hasKey: true)])
        try keychain.setSecret("hunter2", account: Keychain.channelKeyAccount(networkID: config.id, channel: "#secret"))
        let wired = makeApp(config, database: database, keychain: keychain)
        let secret = wired.session.ensureBuffer(name: "#secret", kind: .channel)
        wired.app.leave(secret)
        #expect(wired.session.config.autoJoin.map(\.name) == ["#a"])
        await wired.session.bufferWritesFinished()

        let relaunched = NetworkSession(config: wired.session.config, database: database)
        relaunched.keychain = keychain
        await relaunched.restoreBuffers()
        let restored = try #require(relaunched.buffer(named: "#secret"))
        #expect(!relaunched.rejoins(restored))
        #expect(relaunched.joinKey(forChannel: "#secret") == "hunter2")
        relaunched.rejoin(restored)
        #expect(relaunched.config.autoJoin == [AutoJoinChannel(name: "#a"), AutoJoinChannel(name: "#secret", hasKey: true)])
    }

    @Test func leaveCanBeUndoneAndTheEntryComesBack() throws {
        let wired = makeApp(Self.config(.none, autoJoin: [AutoJoinChannel(name: "#a"), AutoJoinChannel(name: "#b")]))
        let (app, session) = (wired.app, wired.session)
        session.connectionState = .connected
        let undoManager = undoManager(for: app)
        let a = session.ensureBuffer(name: "#a", kind: .channel, persist: false)
        feed(session, ":doug!d@host JOIN #a")
        event(undoManager) { app.leave(a) }
        feed(session, ":doug!d@host PART #a")
        #expect(session.config.autoJoin.map(\.name) == ["#b"])
        #expect(undoManager.undoMenuItemTitle == "Undo Leave Channel")
        undoManager.undo()
        #expect(session.config.autoJoin.map(\.name) == ["#a", "#b"])
        #expect(session.rejoins(a))
        undoManager.redo()
        #expect(session.config.autoJoin.map(\.name) == ["#b"])
        #expect(!session.rejoins(a))
    }

    /// Remove (and a tab's ×, which is Remove here) parts the channel and
    /// takes its entry and key away; reopening puts them back.
    @Test func removeOnANetworkWithoutABouncer() async throws {
        let wired = try await connect(Self.config(.none, autoJoin: [AutoJoinChannel(name: "#a")])) { session in
            session.buffer(named: "#a")?.isJoined == true
        }
        wired.app.close(try wired.channel("#a"))
        try await waitUntil { wired.sent.last == "PART #a" }
        #expect(wired.session.buffer(named: "#a") == nil)
        #expect(wired.session.config.autoJoin.isEmpty)
        #expect(wired.app.recentlyClosed.map(\.name) == ["#a"])
        #expect(!wired.sent.contains { $0.hasPrefix("PRIVMSG") })
    }

    // MARK: ZNC

    @Test func zncDetachesWithStatusAndReattachesWithJoin() async throws {
        let wired = try await connect(Self.config(.znc), caps: "server-time znc.in/self-message znc.in/playback", attached: ["#vela", "#swift"])
        let (app, session) = (wired.app, wired.session)
        let vela = try wired.channel("#vela")
        #expect(session.isIn(vela))

        app.detach(vela)
        try await waitUntil { vela.isDetached }
        #expect(wired.sent.contains("PRIVMSG *status :detach #vela"))
        #expect(!wired.sent.contains { $0.hasPrefix("PART") })
        #expect(!vela.isJoined)
        #expect(!session.isIn(vela))
        #expect(session.canHide(vela))
        #expect(session.buffer(named: "#vela") === vela)
        #expect(vela.lines.last?.text == "You left #vela here. ZNC stays in it and keeps its history; join it again to catch up.")
        // ZNC's answers go to the server console, not a *status conversation.
        try await waitUntil { session.serverBuffer.lines.contains { $0.text == "Detached 1 channel" } }
        #expect(session.serverBuffer.lines.contains { $0.text == "There was 1 channel matching [#vela]" })
        #expect(session.buffer(named: "*status") == nil)

        // Join Channel: a JOIN reattaches it, and ZNC's playback module is
        // asked for what was missed.
        app.rejoin(vela)
        try await waitUntil { vela.isJoined }
        #expect(!vela.isDetached)
        #expect(wired.sent.contains("JOIN #vela"))
        try await waitUntil { wired.sent.contains("PRIVMSG *playback :PLAY #vela 0") }
        #expect(!wired.sent.contains { $0.hasPrefix("PART") })
    }

    /// A detach ZNC doesn't confirm leaves you in the channel, says so in the
    /// server console, and never parts instead.
    @Test func aFailedZNCDetachIsReported() async throws {
        let wired = try await connect(Self.config(.znc), attached: ["#vela"], detachWorks: false)
        let session = wired.session
        session.detachTimeout = .milliseconds(150)
        let vela = try wired.channel("#vela")
        wired.app.detach(vela)
        try await waitUntil { session.serverBuffer.lines.contains { $0.kind == .error && $0.text.contains("didn't detach #vela") } }
        let report = try #require(session.serverBuffer.lines.last { $0.kind == .error })
        #expect(report.text == "ZNC didn't detach #vela, so you're still in it. Its reply, if it sent one, is above. To leave the channel on ZNC too, use Remove Channel….")
        #expect(session.serverBuffer.lines.contains { $0.text == "Detached 0 channels" })
        #expect(vela.lines.contains { $0.kind == .error && $0.text.hasPrefix("ZNC didn't detach #vela") })
        #expect(vela.isJoined)
        #expect(!vela.isDetached)
        #expect(session.isIn(vela))
        #expect(!wired.sent.contains { $0.hasPrefix("PART") })
        #expect(session.buffer(named: "*status") == nil)
    }

    /// Typed `/part` really parts, even through a bouncer, and Remove parts
    /// a channel the bouncer has detached, so it forgets it.
    @Test func partAndRemoveReallyPartThroughABouncer() async throws {
        let wired = try await connect(Self.config(.znc), attached: ["#vela", "#swift"])
        let (app, session) = (wired.app, wired.session)
        let vela = try wired.channel("#vela")
        session.submit("/part", in: vela)
        try await waitUntil { !vela.isJoined }
        #expect(wired.sent.contains("PART #vela"))
        #expect(!wired.sent.contains { $0.contains("*status") })
        #expect(!vela.isDetached)

        let swift = try wired.channel("#swift")
        app.detach(swift)
        try await waitUntil { swift.isDetached }
        app.close(swift)
        try await waitUntil { wired.sent.last == "PART #swift" }
        #expect(session.buffer(named: "#swift") == nil)
    }

    // MARK: soju

    @Test func sojuDetachesWithBouncerServ() async throws {
        let wired = try await connect(Self.config(.soju), attached: ["#vela", "#swift"])
        let (app, session) = (wired.app, wired.session)
        #expect(wired.sent.contains("BOUNCER BIND libera"))
        let vela = try wired.channel("#vela")

        app.detach(vela)
        try await waitUntil { vela.isDetached }
        #expect(wired.sent.contains("PRIVMSG BouncerServ :channel update #vela -detached true"))
        #expect(!wired.sent.contains { $0.hasPrefix("PART") })
        #expect(!vela.isJoined)
        #expect(vela.lines.last?.text == "You left #vela here. soju stays in it and keeps its history; join it again to catch up.")
        // The echoed command and soju's answer don't open a conversation.
        try await waitUntil { session.serverBuffer.lines.contains { $0.text == "updated channel \"#vela\"" } }
        #expect(session.buffer(named: "BouncerServ") == nil)

        // soju detaching a channel by itself (-detach-after) parts it with "Detach".
        let swift = try wired.channel("#swift")
        wired.transport.receive(":doug!d@host PART #swift :Detach")
        try await waitUntil { swift.isDetached }
        #expect(!swift.isJoined)

        // Join reattaches, and Vela asks for what it missed.
        let historyRequests = { wired.sent.filter { $0.hasPrefix("CHATHISTORY") && $0.contains("#vela") }.count }
        let before = historyRequests()
        app.rejoin(vela)
        try await waitUntil { vela.isJoined }
        #expect(!vela.isDetached)
        #expect(wired.sent.contains("JOIN #vela"))
        try await waitUntil { historyRequests() == before + 1 }
    }

    @Test func aFailedSojuDetachIsReported() async throws {
        let wired = try await connect(Self.config(.soju), attached: ["#vela"], detachWorks: false)
        let session = wired.session
        session.detachTimeout = .milliseconds(150)
        let vela = try wired.channel("#vela")
        wired.app.detach(vela)
        try await waitUntil { session.serverBuffer.lines.contains { $0.kind == .error && $0.text.contains("didn't detach #vela") } }
        #expect(session.serverBuffer.lines.contains { $0.text.hasPrefix("error: unknown channel") })
        #expect(vela.isJoined)
        #expect(!vela.isDetached)
        #expect(!wired.sent.contains { $0.hasPrefix("PART") })
        #expect(session.buffer(named: "BouncerServ") == nil)
    }

    // MARK: Undo

    @Test func undoingADetachReattaches() async throws {
        let wired = try await connect(Self.config(.znc), attached: ["#vela"])
        let undoManager = undoManager(for: wired.app)
        let vela = try wired.channel("#vela")
        event(undoManager) { wired.app.detach(vela) }
        try await waitUntil { vela.isDetached }
        #expect(undoManager.undoMenuItemTitle == "Undo Leave Channel")
        undoManager.undo()
        try await waitUntil { vela.isJoined }
        #expect(!vela.isDetached)
        #expect(wired.sent.filter { $0.hasPrefix("JOIN") } == ["JOIN #vela"])
        #expect(undoManager.redoMenuItemTitle == "Redo Leave Channel")
        undoManager.redo()
        try await waitUntil { vela.isDetached }
        #expect(wired.sent.filter { $0 == "PRIVMSG *status :detach #vela" }.count == 2)
        #expect(!wired.sent.contains { $0.hasPrefix("PART") })
    }

    // MARK: Hiding

    /// A detached channel can be hidden: out of the list, still on the
    /// bouncer (no PART), still hidden after a relaunch, and back where it
    /// was when it's shown.
    @Test func hideAndShow() async throws {
        let database = try VelaDatabase.inMemory()
        let wired = try await connect(Self.config(.znc), attached: ["#a", "#vela", "#c"], database: database)
        let (app, session) = (wired.app, wired.session)
        let vela = try wired.channel("#vela")
        // Only a detached channel can be hidden.
        #expect(!session.canHide(vela))
        app.hide(vela)
        #expect(session.buffer(named: "#vela") === vela)

        app.detach(vela)
        try await waitUntil { vela.isDetached }
        app.select(vela)
        app.hide(vela)
        #expect(session.channels.map(\.name) == ["#a", "#c"])
        #expect(session.hiddenChannels.map(\.name) == ["#vela"])
        #expect(app.selectedBuffer?.name == "#c")
        #expect(app.recentlyClosed.first?.wasHidden == true)
        #expect(!wired.sent.contains { $0.hasPrefix("PART") })
        #expect(app.hiddenChannels.map(\.channel.name) == ["#vela"])

        // Still hidden after a relaunch.
        await session.bufferWritesFinished()
        let relaunched = NetworkSession(config: session.config, database: database)
        await relaunched.restoreBuffers()
        #expect(relaunched.channels.map(\.name) == ["#a", "#c"])
        let hidden = try #require(relaunched.hiddenChannels.first)
        #expect(hidden.name == "#vela")
        // Shown: back in its place, still detached.
        let shown = try #require(relaunched.showHiddenChannel(hidden.id))
        #expect(relaunched.channels.map(\.name) == ["#a", "#vela", "#c"])
        #expect(shown.isDetached)
        #expect(!shown.isJoined)
        #expect(relaunched.hiddenChannels.isEmpty)
        await relaunched.bufferWritesFinished()
        #expect(try await database.buffers(networkID: session.id).first { $0.foldedName == "#vela" }?.isHidden == false)

        // In this run, it's in Recently Closed: ⇧⌘T shows it, as it was.
        app.reopenLastClosed()
        #expect(session.channels.map(\.name) == ["#a", "#vela", "#c"])
        let back = try wired.channel("#vela")
        #expect(back.isDetached)
        #expect(app.selectedBuffer === back)
        #expect(session.hiddenChannels.isEmpty)
        #expect(!wired.sent.contains { $0.hasPrefix("PART") || $0.hasPrefix("JOIN") })
    }

    @Test func hideCanBeUndoneAndRedone() throws {
        let wired = makeApp(Self.config(.znc))
        let (app, session) = (wired.app, wired.session)
        session.connectionState = .connected
        let undoManager = undoManager(for: app)
        feed(session, ":doug!d@host JOIN #a", ":doug!d@host JOIN #vela")
        let vela = try wired.channel("#vela")
        event(undoManager) { app.detach(vela) }
        feed(session, ":doug!d@host PART #vela")
        #expect(vela.isDetached)

        event(undoManager) { app.hide(vela) }
        #expect(session.buffer(named: "#vela") == nil)
        #expect(undoManager.undoMenuItemTitle == "Undo Hide Channel")
        undoManager.undo()
        let shown = try wired.channel("#vela")
        #expect(shown.isDetached)
        #expect(session.channels.map(\.name) == ["#a", "#vela"])
        #expect(session.hiddenChannels.isEmpty)
        #expect(app.recentlyClosed.isEmpty)
        #expect(undoManager.redoMenuItemTitle == "Redo Hide Channel")
        undoManager.redo()
        #expect(session.buffer(named: "#vela") == nil)
        #expect(session.hiddenChannels.map(\.name) == ["#vela"])
    }

    @Test func showingFromTheNetworkSettingsOrThePalette() throws {
        let wired = makeApp(Self.config(.soju))
        let (app, session) = (wired.app, wired.session)
        session.connectionState = .connected
        feed(session, ":doug!d@host JOIN #a", ":doug!d@host JOIN #vela")
        let vela = try wired.channel("#vela")
        feed(session, ":doug!d@host PART #vela :Detach")
        app.hide(vela)
        // As after a relaunch: not in Recently Closed.
        app.recentlyClosed = []
        let hidden = try #require(app.hiddenChannels.first)
        #expect(hidden.session === session)

        // The network settings show it without selecting it…
        let shown = try #require(app.show(hidden.channel, selecting: false))
        #expect(shown.isDetached)
        #expect(app.selectedBuffer !== shown)
        #expect(session.hiddenChannels.isEmpty)

        // …the palette shows it and selects it.
        app.hide(shown)
        app.recentlyClosed = []
        let rehidden = try #require(app.hiddenChannels.first)
        let again = try #require(app.show(rehidden.channel))
        #expect(app.selectedBuffer === again)

        // Parted by name while hidden, it's forgotten.
        app.hide(again)
        session.submit("/part #vela", in: session.serverBuffer)
        #expect(session.hiddenChannels.isEmpty)
        #expect(session.buffer(named: "#vela") == nil)
    }

    // MARK: What a bouncer relays

    /// soju relays highlights from detached channels, and another client can
    /// reattach one on ZNC: what arrives counts, but the channel stays
    /// detached, and a hidden one stays hidden (it's kept on disk).
    @Test func relayedMessagesNeitherReattachNorUnhide() async throws {
        let database = try VelaDatabase.inMemory()
        let config = Self.config(.soju)
        let session = NetworkSession(config: config, database: database)
        let host = FakeHost()
        session.host = host
        session.nick = "doug"
        session.connectionState = .connected
        var support = ISupport()
        support.apply(["CHANTYPES=#", "CASEMAPPING=rfc1459"])
        session.isupport = support
        feed(session, ":doug!d@host JOIN #vela", ":doug!d@host JOIN #quiet", ":doug!d@host JOIN #open")
        feed(session, ":doug!d@host PART #vela :Detach", ":doug!d@host PART #quiet :Detach")
        let vela = try #require(session.buffer(named: "#vela"))
        session.hide(try #require(session.buffer(named: "#quiet")))
        #expect(session.hiddenChannels.map(\.name) == ["#quiet"])

        feed(session, ":alice!a@host PRIVMSG #vela :doug: are you around?")
        #expect(vela.isDetached)
        #expect(!vela.isJoined)
        #expect(vela.unreadCount == 1)
        #expect(vela.highlightCount == 1)
        #expect(host.notable.map(\.text) == ["doug: are you around?"])

        feed(session, ":bob!b@host PRIVMSG #quiet :doug: you there?", ":bob!b@host JOIN #quiet")
        #expect(session.buffer(named: "#quiet") == nil)
        #expect(session.hiddenChannels.map(\.name) == ["#quiet"])
        #expect(host.notable.count == 1)
        let key = BufferKey(networkID: session.id, foldedName: "#quiet")
        #expect(try await waitForMessage("doug: you there?", in: key, of: database))

        // soju's own relay notice goes to the server console.
        feed(session, ":BouncerServ!BouncerServ@BouncerServ NOTICE doug :highlight in #quiet: <bob> doug: you there?")
        #expect(session.buffer(named: "#quiet") == nil)
        #expect(session.buffer(named: "BouncerServ") == nil)
        #expect(session.serverBuffer.lines.last?.text == "highlight in #quiet: <bob> doug: you there?")

        // The bouncer attaching it for real (it joins you in) brings it back.
        feed(session, ":doug!d@host JOIN #quiet")
        let quiet = try #require(session.buffer(named: "#quiet"))
        #expect(quiet.isJoined)
        #expect(!quiet.isDetached)
        #expect(session.hiddenChannels.isEmpty)
    }

    // MARK: Across a relaunch

    /// Detached channels come back detached and dimmed. The bouncer doesn't
    /// join Vela into them, and Vela doesn't join them either.
    @Test func detachedChannelsSurviveARelaunch() async throws {
        let database = try VelaDatabase.inMemory()
        let first = try await connect(Self.config(.znc), attached: ["#vela", "#kept"], database: database)
        let vela = try first.channel("#vela")
        first.app.detach(vela)
        try await waitUntil { vela.isDetached }
        first.session.shutdown()
        await first.session.bufferWritesFinished()
        let saved = try await database.buffers(networkID: first.session.id)
        #expect(saved.first { $0.foldedName == "#vela" }?.isDetached == true)
        #expect(saved.first { $0.foldedName == "#kept" }?.isDetached == false)

        // Relaunched: ZNC joins Vela into #kept only.
        let second = makeApp(first.session.config, attached: ["#kept"], database: database)
        await second.session.restoreBuffers()
        let restored = try second.channel("#vela")
        #expect(restored.isDetached)
        #expect(!restored.isJoined)
        #expect(!second.session.isIn(restored))
        second.session.connect()
        try await waitUntil { second.session.buffer(named: "#kept")?.isJoined == true }
        try await Task.sleep(for: .milliseconds(100))
        #expect(restored.isDetached)
        #expect(!restored.isJoined)
        #expect(!second.sent.contains { $0.hasPrefix("JOIN") || $0.hasPrefix("PART") || $0.contains("detach") })

        // Without a bouncer, a detached channel isn't joined on connect either.
        var plain = first.session.config
        plain.bouncerKind = .none
        let third = makeApp(plain, database: database)
        await third.session.restoreBuffers()
        third.session.connect()
        try await waitUntil { third.session.buffer(named: "#kept")?.isJoined == true }
        #expect(!third.sent.contains("JOIN #vela"))
    }

    /// Removing and leaving a channel while disconnected from the bouncer
    /// wait in networks.json, through a relaunch. After the next
    /// registration Vela parts and detaches them, and each comes off the
    /// list once it's sent. The bouncer's joins into them as Vela connects
    /// don't bring them back.
    @Test func waitingPartsAndDetachesSurviveARelaunch() async throws {
        let database = try VelaDatabase.inMemory()
        let folder = TemporaryFolder()
        let first = makeApp(Self.config(.znc), database: database, folder: folder)
        let (app, session) = (first.app, first.session)
        for name in ["#removed", "#quiet", "#kept"] { session.ensureBuffer(name: name, kind: .channel) }
        app.close(try first.channel("#removed"))
        app.detach(try first.channel("#quiet"))
        #expect(try first.channel("#quiet").isDetached)
        #expect(session.config.pendingParts == ["#removed"])
        #expect(session.config.pendingDetaches == ["#quiet"])
        #expect(try first.saved()?.pendingParts == ["#removed"])
        #expect(try first.saved()?.pendingDetaches == ["#quiet"])
        await session.bufferWritesFinished()

        // Relaunched from what was saved. ZNC is still in all three.
        let store = NetworkConfigStore(fileURL: folder.url.appending(path: "networks.json"))
        try store.load()
        let config = try #require(store.networks.first)
        let second = makeApp(config, attached: ["#removed", "#quiet", "#kept"], database: database, folder: folder)
        second.app.networkStore.upsert(config)
        await second.session.restoreBuffers()
        #expect(try second.channel("#quiet").isDetached)
        second.session.connect()
        try await waitUntil {
            second.session.buffer(named: "#kept")?.isJoined == true && second.session.config.pendingParts.isEmpty
                && second.session.config.pendingDetaches.isEmpty
        }
        try await waitUntil { second.session.detachRequests.isEmpty }
        #expect(second.sent.contains("PART #removed"))
        #expect(second.sent.contains("PRIVMSG *status :detach #quiet"))
        #expect(!second.sent.contains { $0.hasPrefix("JOIN") })
        #expect(second.session.buffer(named: "#removed") == nil)
        let quiet = try second.channel("#quiet")
        #expect(quiet.isDetached)
        #expect(!quiet.isJoined)
        #expect(try second.saved()?.pendingParts.isEmpty == true)
        #expect(try second.saved()?.pendingDetaches.isEmpty == true)
    }

    /// The network editor works on an older copy of the network: saving it
    /// keeps what's waiting for the bouncer.
    @Test func editingTheNetworkKeepsWhatsWaiting() throws {
        let wired = makeApp(Self.config(.znc))
        let (app, session) = (wired.app, wired.session)
        app.networkStore.upsert(session.config)
        var edited = try #require(app.networkStore.network(id: session.id))
        session.ensureBuffer(name: "#removed", kind: .channel)
        app.close(try wired.channel("#removed"))
        edited.name = "Renamed"
        app.updateNetwork(edited, secrets: nil)
        #expect(session.config.name == "Renamed")
        #expect(session.config.pendingParts == ["#removed"])
        #expect(try wired.saved()?.pendingParts == ["#removed"])
    }

    /// Reopening a channel removed while disconnected, before its part was
    /// sent: the part is off, and a detached one stays detached.
    @Test func reopeningBeforeTheWaitingPartIsSent() throws {
        let wired = makeApp(Self.config(.znc))
        let (app, session) = (wired.app, wired.session)
        session.ensureBuffer(name: "#quiet", kind: .channel)
        app.detach(try wired.channel("#quiet"))
        app.close(try wired.channel("#quiet"))
        #expect(session.config.pendingParts == ["#quiet"])
        #expect(session.config.pendingDetaches.isEmpty)
        app.reopenLastClosed()
        #expect(session.config.pendingParts.isEmpty)
        #expect(session.config.pendingDetaches == ["#quiet"])
        let quiet = try wired.channel("#quiet")
        #expect(quiet.isDetached)
        #expect(!session.isIn(quiet))
    }

    /// Undoing a detach made while disconnected: the bouncer never heard of
    /// it, so nothing's sent and the channel is in again.
    @Test func undoingAnOfflineDetach() throws {
        let wired = makeApp(Self.config(.znc))
        let (app, session) = (wired.app, wired.session)
        let undoManager = undoManager(for: app)
        let quiet = session.ensureBuffer(name: "#quiet", kind: .channel)
        #expect(session.isIn(quiet))
        event(undoManager) { app.detach(quiet) }
        #expect(quiet.isDetached)
        #expect(!session.isIn(quiet))
        undoManager.undo()
        #expect(!quiet.isDetached)
        #expect(session.isIn(quiet))
        #expect(session.config.pendingDetaches.isEmpty)
        #expect(session.pendingJoins.isEmpty)
    }
}
