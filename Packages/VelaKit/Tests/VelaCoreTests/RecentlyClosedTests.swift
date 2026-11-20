// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

/// Leaving and removing channels, closing conversations, and getting them
/// back: Recently Closed, ⇧⌘T, ⌘Z and redo, `/part` and `/close`, the
/// auto-join list and channel keys, bouncers, and the order buffer state is
/// saved in.
@MainActor
@Suite("Leaving, removing and reopening")
struct RecentlyClosedTests {
    @MainActor
    private struct Fixture {
        let app: AppModel
        let sessions: [NetworkSession]
        let folder: TemporaryFolder
        var session: NetworkSession { sessions[0] }

        func buffer(_ name: String, in session: NetworkSession? = nil) throws -> BufferModel {
            try #require((session ?? self.session).buffer(named: name))
        }

        /// The networks as saved in networks.json.
        func savedNetworks() throws -> [NetworkConfig] {
            let store = NetworkConfigStore(fileURL: folder.url.appending(path: "networks.json"))
            try store.load()
            return store.networks
        }
    }

    /// An app with connected networks named `networks`, an in-memory
    /// keychain and no notifications, Dock or saved selection.
    private func makeApp(
        networks: [String] = ["Libera.Chat"],
        autoJoin: [AutoJoinChannel] = [],
        bouncer: BouncerKind = .none,
        database: VelaDatabase? = nil,
        keychain: Keychain = .inMemory()
    ) -> Fixture {
        let folder = TemporaryFolder()
        let app = AppModel(
            settings: SettingsStore(fileURL: folder.url.appending(path: "settings.json"), watchForChanges: false),
            networkStore: NetworkConfigStore(fileURL: folder.url.appending(path: "networks.json")),
            database: database,
            keychain: keychain,
            notifier: SilentNotifier(),
            isDemo: true
        )
        let sessions = networks.map { name in
            var config = NetworkConfig(name: name, host: "irc.test", nick: "doug", autoJoin: autoJoin)
            config.bouncerKind = bouncer
            let session = NetworkSession(config: config, database: database)
            session.nick = "doug"
            session.connectionState = .connected
            var support = ISupport()
            support.apply(["PREFIX=(ov)@+", "CHANTYPES=#", "CASEMAPPING=rfc1459"])
            session.isupport = support
            return session
        }
        app.installDemoSessions(sessions)
        return Fixture(app: app, sessions: sessions, folder: folder)
    }

    private func feed(_ session: NetworkSession, _ lines: String...) {
        for line in lines { session.handle(.message(IRCMessage(line: line)!, batch: nil)) }
    }

    private func join(_ session: NetworkSession, _ channels: String...) {
        for channel in channels { feed(session, ":doug!d@host JOIN \(channel)") }
    }

    private func names(_ buffers: [BufferModel]) -> [String] { buffers.map(\.name) }

    /// An undo manager that groups only where a test says, as the run loop
    /// groups each event in the app.
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

    // MARK: Recently Closed

    @Test func removingAndClosingAreRememberedNewestFirst() throws {
        let fixture = makeApp()
        let (app, session) = (fixture.app, fixture.session)
        join(session, "#a", "#b", "#c")
        session.ensureBuffer(name: "alice", kind: .query)
        #expect(app.recentlyClosed.isEmpty)

        app.close(try fixture.buffer("#b"))
        app.close(try fixture.buffer("alice"))
        app.close(try fixture.buffer("#a"))
        #expect(names(session.buffers) == ["#c"])
        #expect(app.recentlyClosed.map(\.name) == ["#a", "alice", "#b"])
        #expect(app.recentlyClosed.map(\.kind) == [.channel, .query, .channel])
        let latest = try #require(app.recentlyClosed.first)
        #expect(latest.networkName == "Libera.Chat")
        #expect(app.menuTitle(for: latest) == "#a — Libera.Chat")
        // The console never closes.
        app.close(session.serverBuffer)
        #expect(app.recentlyClosed.count == 3)
    }

    @Test func leavingKeepsTheChannelAndIsntRemembered() throws {
        let fixture = makeApp()
        let (app, session) = (fixture.app, fixture.session)
        join(session, "#a")
        let a = try fixture.buffer("#a")
        #expect(session.isIn(a))
        app.leave(a)
        feed(session, ":doug!d@host PART #a")
        #expect(session.buffer(named: "#a") === a)
        #expect(!a.isJoined)
        #expect(!session.isIn(a))
        #expect(!session.rejoins(a))
        #expect(app.recentlyClosed.isEmpty)
    }

    @Test func theListKeepsTheNewestTwenty() throws {
        let fixture = makeApp()
        let names = (0..<25).map { "#c\($0)" }
        for name in names { join(fixture.session, name) }
        for name in names { fixture.app.close(try fixture.buffer(name)) }
        #expect(AppModel.recentlyClosedLimit == 20)
        #expect(fixture.app.recentlyClosed.map(\.name) == names.suffix(20).reversed())
    }

    @Test func closingAgainMovesItToTheTop() throws {
        let fixture = makeApp()
        let app = fixture.app
        join(fixture.session, "#a", "#b")
        app.close(try fixture.buffer("#a"))
        app.close(try fixture.buffer("#b"))
        #expect(app.recentlyClosed.map(\.name) == ["#b", "#a"])

        app.reopen(try #require(app.recentlyClosed.last))
        #expect(app.recentlyClosed.map(\.name) == ["#b"])
        app.close(try fixture.buffer("#a"))
        #expect(app.recentlyClosed.map(\.name) == ["#a", "#b"])
    }

    @Test func reopeningGoesFurtherBackEachTime() throws {
        let fixture = makeApp()
        let app = fixture.app
        join(fixture.session, "#a", "#b", "#c")
        for name in ["#a", "#b", "#c"] { app.close(try fixture.buffer(name)) }
        app.reopenLastClosed()
        #expect(app.selectedBuffer?.name == "#c")
        app.reopenLastClosed()
        #expect(app.selectedBuffer?.name == "#b")
        #expect(app.recentlyClosed.map(\.name) == ["#a"])
        app.reopenLastClosed()
        app.reopenLastClosed()   // nothing left
        #expect(app.recentlyClosed.isEmpty)
        #expect(names(fixture.session.channels) == ["#a", "#b", "#c"])
    }

    @Test func removingANetworkForgetsWhatWasClosedThere() throws {
        let fixture = makeApp(networks: ["Libera.Chat", "OFTC"])
        let (libera, oftc) = (fixture.sessions[0], fixture.sessions[1])
        let app = fixture.app
        let undoManager = undoManager(for: app)
        join(libera, "#vela")
        join(oftc, "#debian")
        try event(undoManager) { app.close(try fixture.buffer("#vela", in: libera)) }
        try event(undoManager) { app.close(try fixture.buffer("#debian", in: oftc)) }
        app.removeNetwork(id: oftc.id)
        #expect(app.recentlyClosed.map(\.name) == ["#vela"])
        // Its ⌘Z went with it; Libera.Chat's is next.
        undoManager.undo()
        #expect(libera.buffer(named: "#vela") != nil)
        #expect(!undoManager.canUndo)
    }

    @Test func aChannelOpenedAgainLeavesTheList() throws {
        let fixture = makeApp()
        let app = fixture.app
        let undoManager = undoManager(for: app)
        join(fixture.session, "#a", "#b")
        try event(undoManager) { app.close(try fixture.buffer("#a")) }
        // Joined again by hand: nothing to reopen, nothing to undo.
        join(fixture.session, "#a")
        #expect(app.recentlyClosed.isEmpty)
        #expect(!undoManager.canUndo)
        // A conversation someone writes in again, too.
        fixture.session.ensureBuffer(name: "alice", kind: .query)
        try event(undoManager) { app.close(try fixture.buffer("alice")) }
        fixture.session.ensureBuffer(name: "Alice", kind: .query)
        #expect(app.recentlyClosed.isEmpty)
    }

    @Test func closesYouDidntMakeArentRemembered() throws {
        let fixture = makeApp()
        let app = fixture.app
        let undoManager = undoManager(for: app)
        let query = fixture.session.ensureBuffer(name: "stranger", kind: .query)
        event(undoManager) { app.close(query, reopenable: false) }
        #expect(fixture.session.buffer(named: "stranger") == nil)
        #expect(app.recentlyClosed.isEmpty)
        #expect(undoManager.undoActionName.isEmpty)
    }

    // MARK: Reopening

    @Test func reopeningPutsItBackAsItWas() throws {
        let fixture = makeApp()
        let (app, session) = (fixture.app, fixture.session)
        join(session, "#a", "#b", "#c", "#d")
        session.ensureBuffer(name: "bob", kind: .query)
        session.ensureBuffer(name: "amy", kind: .query)
        let b = try fixture.buffer("#b")
        session.setMuted(true, for: b)
        let readAt = Date(timeIntervalSince1970: 1_800_000_000)
        b.lastReadAt = readAt
        b.unreadCount = 3
        b.highlightCount = 1
        app.select(try fixture.buffer("#a"))

        app.close(b)
        app.close(try fixture.buffer("amy"))
        #expect(names(session.channels) == ["#a", "#c", "#d"])

        app.reopenLastClosed()
        #expect(names(session.queries) == ["bob", "amy"])
        app.reopenLastClosed()
        let reopened = try fixture.buffer("#b")
        #expect(reopened !== b)
        #expect(reopened.id == b.id)
        #expect(names(session.channels) == ["#a", "#b", "#c", "#d"])
        #expect(session.channels.map(\.sortOrder) == [0, 1, 2, 3])
        #expect(reopened.isMuted)
        #expect(reopened.lastReadAt == readAt)
        // Selected, with the New line where it was.
        #expect(app.selectedBufferID == reopened.id)
        #expect(reopened.unreadMarkerAfter == readAt)
        // Joined again: it's rejoined on the next connect, too.
        #expect(session.rejoins(reopened))
    }

    @Test func aChannelYouLeftStaysLeftWhenReopened() throws {
        let fixture = makeApp()
        let (app, session) = (fixture.app, fixture.session)
        join(session, "#a")
        session.submit("/part", in: try fixture.buffer("#a"))
        feed(session, ":doug!d@host PART #a")
        app.close(try fixture.buffer("#a"))
        app.reopenLastClosed()
        let a = try fixture.buffer("#a")
        #expect(!a.isJoined)
        #expect(!session.rejoins(a))
    }

    @Test func offlineItsJoinedOnTheNextConnect() throws {
        let fixture = makeApp()
        let (app, session) = (fixture.app, fixture.session)
        join(session, "#a")
        session.handle(.disconnected(reason: nil))
        app.close(try fixture.buffer("#a"))
        app.reopenLastClosed()
        let a = try fixture.buffer("#a")
        #expect(!a.isJoined)
        #expect(session.rejoins(a))
    }

    // MARK: The auto-join list and keys

    @Test func removingTakesTheChannelOffTheAutoJoinListAndReopeningPutsItBack() throws {
        let keychain = Keychain.inMemory()
        let fixture = makeApp(
            autoJoin: [AutoJoinChannel(name: "#a"), AutoJoinChannel(name: "#Secret", hasKey: true), AutoJoinChannel(name: "#c")],
            keychain: keychain
        )
        let (app, session) = (fixture.app, fixture.session)
        let account = Keychain.channelKeyAccount(networkID: session.id, channel: "#secret")
        try keychain.setSecret("hunter2", account: account)
        join(session, "#a", "#Secret", "#c")

        // Leaving keeps it on the list.
        app.leave(try fixture.buffer("#c"))
        #expect(session.config.autoJoin.map(\.name) == ["#a", "#Secret", "#c"])

        app.close(try fixture.buffer("#secret"))
        #expect(session.config.autoJoin.map(\.name) == ["#a", "#c"])
        #expect(try fixture.savedNetworks().first?.autoJoin.map(\.name) == ["#a", "#c"])
        #expect(keychain.secret(account: account) == nil)

        app.reopenLastClosed()
        #expect(session.config.autoJoin == [AutoJoinChannel(name: "#a"), AutoJoinChannel(name: "#Secret", hasKey: true), AutoJoinChannel(name: "#c")])
        #expect(try fixture.savedNetworks().first?.autoJoin.map(\.name) == ["#a", "#Secret", "#c"])
        #expect(keychain.secret(account: account) == "hunter2")
        #expect(session.joinKey(forChannel: "#secret") == "hunter2")
    }

    /// Against a scripted server: Remove parts the channel, what was said
    /// before the server saw the PART doesn't bring it back, and reopening
    /// joins it with its key.
    @Test func reopeningJoinsWithTheChannelsKey() async throws {
        let keychain = Keychain.inMemory()
        let factory = MockTransportFactory { transport, _ in
            transport.setResponder { line in
                if line.hasPrefix("CAP LS") { return [":irc.test CAP * LS :server-time"] }
                if line.hasPrefix("CAP REQ") { return [":irc.test CAP * ACK :server-time"] }
                if line == "CAP END" { return [":irc.test 001 doug :Welcome", ":irc.test 005 doug CHANTYPES=# :are supported"] }
                if line.hasPrefix("JOIN ") {
                    let channel = String(line.dropFirst(5).prefix { $0 != " " })
                    return [":doug!d@host JOIN \(channel)", ":irc.test 366 doug \(channel) :End"]
                }
                if line.hasPrefix("PART ") {
                    let channel = String(line.dropFirst(5))
                    return [":alice!a@host PRIVMSG \(channel) :said before the PART", ":doug!d@host PART \(channel)"]
                }
                return []
            }
        }
        let fakeHost = FakeHost()
        fakeHost.factory = factory
        let config = NetworkConfig(
            name: "Libera.Chat", host: "irc.test", nick: "doug",
            autoJoin: [AutoJoinChannel(name: "#secret", hasKey: true), AutoJoinChannel(name: "#vela")]
        )
        let account = Keychain.channelKeyAccount(networkID: config.id, channel: "#secret")
        try keychain.setSecret("hunter2", account: account)
        let session = NetworkSession(config: config, database: nil, transportFactory: factory.makeTransport)
        session.keychain = keychain
        session.host = fakeHost
        session.connect()
        try await waitUntil { session.buffer(named: "#secret")?.isJoined == true && session.buffer(named: "#vela")?.isJoined == true }
        let transport = try #require(factory.latest)
        #expect(transport.sentLines.contains("JOIN #secret hunter2"))

        let folder = TemporaryFolder()
        let app = AppModel(
            settings: SettingsStore(fileURL: folder.url.appending(path: "settings.json"), watchForChanges: false),
            networkStore: NetworkConfigStore(fileURL: folder.url.appending(path: "networks.json")),
            database: nil, keychain: keychain, notifier: SilentNotifier(), isDemo: true
        )
        app.installDemoSessions([session])
        app.close(try #require(session.buffer(named: "#secret")))
        try await waitUntil { transport.sentLines.contains("PART #secret") }
        try await Task.sleep(for: .milliseconds(150))
        #expect(session.buffer(named: "#secret") == nil)
        #expect(session.config.autoJoin.map(\.name) == ["#vela"])
        #expect(keychain.secret(account: account) == nil)

        app.reopenLastClosed()
        try await waitUntil { session.buffer(named: "#secret")?.isJoined == true }
        #expect(transport.sentLines.filter { $0 == "JOIN #secret hunter2" }.count == 2)
        #expect(names(session.channels) == ["#secret", "#vela"])
        #expect(app.selectedBuffer?.name == "#secret")
    }

    // MARK: Bouncers

    /// Removing or leaving a channel while disconnected from a bouncer
    /// can't part it. When the bouncer rejoins it after connecting, Vela
    /// parts it then, and a removed channel doesn't come back.
    @Test func aBouncersReplayedJoinIsParted() async throws {
        let factory = MockTransportFactory { transport, _ in
            transport.setResponder { line in
                if line.hasPrefix("CAP LS") { return [":znc.test CAP * LS :server-time"] }
                if line.hasPrefix("CAP REQ") { return [":znc.test CAP * ACK :server-time"] }
                if line == "CAP END" {
                    // ZNC rejoins its channels and plays back their buffers.
                    return [
                        ":znc.test 001 doug :Welcome", ":znc.test 005 doug CHANTYPES=# :are supported",
                        ":doug!d@host JOIN #removed", ":znc.test 366 doug #removed :End",
                        ":bob!b@host PRIVMSG #removed :played back",
                        ":doug!d@host JOIN #left", ":znc.test 366 doug #left :End",
                        ":doug!d@host JOIN #kept", ":znc.test 366 doug #kept :End",
                    ]
                }
                if line.hasPrefix("PART ") { return [":doug!d@host \(line)"] }
                return []
            }
        }
        let fakeHost = FakeHost()
        fakeHost.factory = factory
        var config = NetworkConfig(name: "ZNC", host: "znc.test", nick: "doug")
        config.bouncerKind = .znc
        let session = NetworkSession(config: config, database: nil, transportFactory: factory.makeTransport)
        session.host = fakeHost
        for name in ["#removed", "#left", "#kept"] { session.ensureBuffer(name: name, kind: .channel, persist: false) }

        let folder = TemporaryFolder()
        let app = AppModel(
            settings: SettingsStore(fileURL: folder.url.appending(path: "settings.json"), watchForChanges: false),
            networkStore: NetworkConfigStore(fileURL: folder.url.appending(path: "networks.json")),
            database: nil, keychain: .inMemory(), notifier: SilentNotifier(), isDemo: true
        )
        app.installDemoSessions([session])
        #expect(session.isIn(try #require(session.buffer(named: "#left"))))
        app.close(try #require(session.buffer(named: "#removed")))
        app.leave(try #require(session.buffer(named: "#left")))

        session.host = fakeHost
        session.connect()
        let transport = try #require(await factory.waitForTransport(count: 1))
        try await waitUntil { session.buffer(named: "#kept")?.isJoined == true && transport.sentLines.filter { $0.hasPrefix("PART") }.count == 2 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(Set(transport.sentLines.filter { $0.hasPrefix("PART") }) == ["PART #removed", "PART #left"])
        #expect(session.buffer(named: "#removed") == nil)
        #expect(session.buffer(named: "#left")?.isJoined == false)
        #expect(!transport.sentLines.contains { $0.hasPrefix("JOIN") })
    }

    @Test func rejoiningOfflineOnABouncerJoinsAfterConnecting() async throws {
        let factory = MockTransportFactory { transport, _ in
            transport.setResponder { line in
                if line.hasPrefix("CAP LS") { return [":znc.test CAP * LS :server-time"] }
                if line.hasPrefix("CAP REQ") { return [":znc.test CAP * ACK :server-time"] }
                if line == "CAP END" { return [":znc.test 001 doug :Welcome", ":znc.test 005 doug CHANTYPES=# :are supported"] }
                if line.hasPrefix("JOIN ") { return [":doug!d@host \(line)"] }
                return []
            }
        }
        let fakeHost = FakeHost()
        fakeHost.factory = factory
        var config = NetworkConfig(name: "ZNC", host: "znc.test", nick: "doug")
        config.bouncerKind = .znc
        let session = NetworkSession(config: config, database: nil, transportFactory: factory.makeTransport)
        session.host = fakeHost
        let channel = session.ensureBuffer(name: "#back", kind: .channel, persist: false)
        session.leave(channel)
        session.rejoin(channel)
        session.connect()
        try await waitUntil { session.buffer(named: "#back")?.isJoined == true }
        let transport = try #require(factory.latest)
        #expect(transport.sentLines.filter { $0.hasPrefix("JOIN") } == ["JOIN #back"])
    }

    // MARK: /part and /close

    @Test func slashCloseRemovesAndMovesTheSelection() throws {
        let fixture = makeApp(autoJoin: [AutoJoinChannel(name: "#b")])
        let (app, session) = (fixture.app, fixture.session)
        app.settings[.navigationStyle] = .sidebar
        join(session, "#a", "#b", "#c")
        let b = try fixture.buffer("#b")
        app.select(b)
        session.submit("/close", in: b)
        #expect(session.buffer(named: "#b") == nil)
        #expect(session.config.autoJoin.isEmpty)
        // Its right-hand neighbor, never a closed buffer.
        #expect(app.selectedBuffer?.name == "#c")
        #expect(app.recentlyClosed.map(\.name) == ["#b"])
        session.submit("/wc", in: try fixture.buffer("#c"))
        #expect(app.selectedBuffer?.name == "#a")
    }

    @Test func slashPartLeavesAndCanBeUndone() throws {
        let fixture = makeApp()
        let (app, session) = (fixture.app, fixture.session)
        let undoManager = undoManager(for: app)
        join(session, "#a")
        let a = try fixture.buffer("#a")
        try event(undoManager) { session.submit("/leave bye", in: a) }
        #expect(!session.rejoins(a))
        #expect(session.buffer(named: "#a") === a)
        #expect(undoManager.undoMenuItemTitle == "Undo Leave Channel")
        undoManager.undo()
        #expect(session.rejoins(a))
    }

    // MARK: Undo

    @Test func undoAndRedoARemove() throws {
        let fixture = makeApp(autoJoin: [AutoJoinChannel(name: "#b")])
        let (app, session) = (fixture.app, fixture.session)
        let undoManager = undoManager(for: app)
        join(session, "#a", "#b", "#c")
        let b = try fixture.buffer("#b")
        b.unreadCount = 2
        app.select(try fixture.buffer("#a"))

        event(undoManager) { app.close(b) }
        #expect(undoManager.canUndo)
        #expect(undoManager.undoMenuItemTitle == "Undo Remove Channel")

        undoManager.undo()
        let restored = try fixture.buffer("#b")
        #expect(names(session.channels) == ["#a", "#b", "#c"])
        #expect(restored.unreadCount == 2)
        #expect(session.config.autoJoin.map(\.name) == ["#b"])
        // It wasn't selected, so the selection stays.
        #expect(app.selectedBuffer?.name == "#a")
        #expect(app.recentlyClosed.isEmpty)
        #expect(undoManager.redoMenuItemTitle == "Redo Remove Channel")

        undoManager.redo()
        #expect(session.buffer(named: "#b") == nil)
        #expect(session.config.autoJoin.isEmpty)
        #expect(app.recentlyClosed.map(\.name) == ["#b"])
        #expect(undoManager.undoMenuItemTitle == "Undo Remove Channel")
        undoManager.undo()
        #expect(names(session.channels) == ["#a", "#b", "#c"])

        // The selected one comes back selected.
        app.select(try fixture.buffer("#c"))
        try event(undoManager) { app.close(try fixture.buffer("#c")) }
        #expect(app.selectedBuffer?.name == "#b")
        undoManager.undo()
        #expect(app.selectedBuffer?.name == "#c")

        // A conversation.
        let alice = session.ensureBuffer(name: "alice", kind: .query)
        event(undoManager) { app.close(alice) }
        #expect(undoManager.undoMenuItemTitle == "Undo Close Conversation")
    }

    @Test func undoAndRedoALeave() throws {
        let fixture = makeApp()
        let (app, session) = (fixture.app, fixture.session)
        let undoManager = undoManager(for: app)
        join(session, "#a")
        let a = try fixture.buffer("#a")
        event(undoManager) { app.leave(a) }
        feed(session, ":doug!d@host PART #a")
        #expect(undoManager.undoMenuItemTitle == "Undo Leave Channel")
        undoManager.undo()
        // JOIN goes out (there's no server here); it's rejoined on connect too.
        #expect(session.rejoins(a))
        #expect(undoManager.redoMenuItemTitle == "Redo Leave Channel")
        undoManager.redo()
        #expect(!session.rejoins(a))
        #expect(session.buffer(named: "#a") === a)
    }

    @Test func undoGoesBackThroughSeveralRemoves() throws {
        let fixture = makeApp()
        let (app, session) = (fixture.app, fixture.session)
        let undoManager = undoManager(for: app)
        let channels = (0..<22).map { "#c\($0)" }
        for name in channels { join(session, name) }
        for name in channels { try event(undoManager) { app.close(try fixture.buffer(name)) } }
        // Further back than the list goes.
        for _ in channels { undoManager.undo() }
        #expect(names(session.channels) == channels)
        #expect(app.recentlyClosed.isEmpty)
    }

    @Test func reopeningAnotherWayTakesItsUndoAway() throws {
        let fixture = makeApp()
        let app = fixture.app
        let undoManager = undoManager(for: app)
        join(fixture.session, "#a", "#b")
        try event(undoManager) { app.close(try fixture.buffer("#a")) }
        try event(undoManager) { app.close(try fixture.buffer("#b")) }
        app.reopenLastClosed()
        // ⌘Z now undoes removing #a, the remove still in effect.
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(fixture.session.buffer(named: "#a") != nil)
        #expect(!undoManager.canUndo)
    }

    // MARK: Saving

    private actor WriteLog {
        var order: [Int] = []
        func append(_ step: Int) { order.append(step) }
    }

    /// Each buffer write waits for the one before, however long it takes.
    @Test func bufferWritesRunInTheOrderTheyreMade() async throws {
        let fixture = makeApp(database: try VelaDatabase.inMemory())
        let session = fixture.session
        let log = WriteLog()
        session.writeBuffer { _ in
            try await Task.sleep(for: .milliseconds(60))
            await log.append(1)
        }
        session.writeBuffer { _ in await log.append(2) }
        session.writeBuffer { _ in await log.append(3) }
        await session.bufferWritesFinished()
        #expect(await log.order == [1, 2, 3])
    }

    /// A remove deletes the buffer's saved state and a reopen saves it
    /// again; done straight after each other (⌘Z), they must reach the
    /// database in that order, or the reopened channel is gone next launch.
    @Test func bufferStateIsSavedInOrder() async throws {
        let database = try VelaDatabase.inMemory()
        let fixture = makeApp(database: database)
        let (app, session) = (fixture.app, fixture.session)
        join(session, "#a", "#b")
        session.setMuted(true, for: try fixture.buffer("#b"))
        for _ in 0..<100 {
            app.close(try fixture.buffer("#b"))
            app.reopenLastClosed()
        }
        await session.bufferWritesFinished()
        var saved = try await database.buffers(networkID: session.id)
        #expect(saved.map(\.foldedName) == ["#a", "#b"])
        #expect(saved.last?.isMuted == true)
        #expect(saved.last?.sortOrder == 1)

        app.close(try fixture.buffer("#b"))
        await session.bufferWritesFinished()
        saved = try await database.buffers(networkID: session.id)
        #expect(saved.map(\.foldedName) == ["#a"])
    }
}
