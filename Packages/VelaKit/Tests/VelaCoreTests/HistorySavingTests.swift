// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaMedia
import VelaStore

/// A session host that says what happens to history (`history.save`).
@MainActor
private final class HistoryHost: SessionHost {
    var historyStorage: HistoryStorage
    var behavior = SessionBehavior()
    var factory: MockTransportFactory?

    /// Sessions hold their host weakly; these hosts last as long as the tests.
    private static var retained: [HistoryHost] = []

    init(_ storage: HistoryStorage) {
        historyStorage = storage
        Self.retained.append(self)
    }

    func clientConfig(for session: NetworkSession) -> IRCClientConfig {
        var config = IRCClientConfig(host: "irc.test", port: 6667, useTLS: false, nick: session.config.nick)
        config.pingInterval = .zero
        config.pingTimeout = .zero
        config.floodPolicy = .disabled
        return config
    }

    func isBufferVisible(_ id: BufferID) -> Bool { false }
    func activeBuffer(in session: NetworkSession) -> BufferModel? { nil }
    func session(_ session: NetworkSession, didReceiveNotable line: ChatLine, in buffer: BufferModel) {}
    func session(_ session: NetworkSession, didUpdateBouncerNetworks networks: [BouncerNetwork]) {}
    func sessionDidChangeConfig(_ session: NetworkSession) {}
    func sessionDidChangeUnreadCounts(_ session: NetworkSession) {}
}

/// A database file that outlives one session, for "relaunching".
private struct ScratchDatabase {
    let directory: URL
    var url: URL { directory.appending(path: "vela.sqlite") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "VelaHistory-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func open() throws -> VelaDatabase { try VelaDatabase(url: url) }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
@Suite("Saving message history (history.save)")
struct HistorySavingTests {
    private let config = NetworkConfig(name: "Test", host: "irc.test", nick: "doug")

    private func makeSession(_ storage: HistoryStorage, database: VelaDatabase) -> (NetworkSession, HistoryHost) {
        let host = HistoryHost(storage)
        let session = NetworkSession(config: config, database: database)
        session.host = host
        session.nick = "doug"
        session.connectionState = .connected
        var support = ISupport()
        support.apply(["PREFIX=(ov)@+", "CHANTYPES=#", "CASEMAPPING=rfc1459"])
        session.isupport = support
        return (session, host)
    }

    private func feed(_ session: NetworkSession, _ lines: String...) {
        for line in lines { session.handle(.message(IRCMessage(line: line)!, batch: nil)) }
    }

    /// A session's worth of chat: joining, messages, a reaction, a
    /// redaction, reading and muting the channel. Returns once everything
    /// Vela writes in the background has been written.
    private func chat(in session: NetworkSession, database: VelaDatabase) async throws {
        feed(session,
             ":doug!d@host JOIN #vela",
             "@msgid=m1 :ada!a@host PRIVMSG #vela :a secret plan",
             "@msgid=m2 :wren!w@host PRIVMSG #vela :tell nobody",
             "@+draft/react=👍;+draft/reply=m1 :wren!w@host TAGMSG #vela",
             ":ada!a@host PRIVMSG doug :psst")
        await session.flushPendingRecordsNow()
        feed(session, ":ada!a@host REDACT #vela m2")
        let vela = try #require(session.buffer(named: "#vela"))
        // Saved whole, one after the other: the mute must win.
        session.markRead(vela)
        session.setMuted(true, for: vela)
        await session.flushPendingRecordsNow()
    }

    // MARK: Off

    @Test func offSavesNoMessagesReactionsOrSearchIndex() async throws {
        let scratch = try ScratchDatabase()
        defer { scratch.cleanup() }
        let database = try scratch.open()
        let (session, _) = makeSession(.memoryOnly, database: database)
        try await chat(in: session, database: database)

        // Everything is in memory.
        let vela = try #require(session.buffer(named: "#vela"))
        #expect(vela.lines.map(\.text).contains("a secret plan"))
        #expect(vela.reactions(for: "m1").map(\.emoji) == ["👍"])

        let counts = try await database.storageCounts()
        #expect(counts.messages == 0)
        #expect(counts.fullTextEntries == 0)
        #expect(counts.reactions == 0)
        #expect(counts.linkPreviews == 0)
        // Channel list and per-buffer state are still saved.
        #expect(counts.buffers == 2)
        let saved = try await database.buffers(networkID: session.id)
        let state = try #require(saved.first { $0.foldedName == "#vela" })
        #expect(state.isMuted)
        // Stored as seconds since 1970: equal to well under a millisecond.
        let savedReadAt = try #require(state.lastReadAt)
        let readAt = try #require(vela.lastReadAt)
        #expect(abs(savedReadAt.timeIntervalSince(readAt)) < 0.001)

        // The text isn't anywhere in the files.
        for suffix in ["", "-wal"] {
            let data = (try? Data(contentsOf: URL(fileURLWithPath: scratch.url.path(percentEncoded: false) + suffix))) ?? Data()
            #expect(data.range(of: Data("secret plan".utf8)) == nil)
        }
    }

    @Test func offLoadsNothingAfterARelaunch() async throws {
        let scratch = try ScratchDatabase()
        defer { scratch.cleanup() }
        do {
            let database = try scratch.open()
            let (session, _) = makeSession(.memoryOnly, database: database)
            try await chat(in: session, database: database)
            session.shutdown()
        }

        let (relaunched, _) = makeSession(.memoryOnly, database: try scratch.open())
        await relaunched.restoreBuffers()
        let vela = try #require(relaunched.buffer(named: "#vela"))
        #expect(vela.isMuted)
        #expect(vela.lastReadAt != nil)
        #expect(relaunched.buffer(named: "ada") != nil)
        try await Task.sleep(for: .milliseconds(150))
        #expect(vela.lines.isEmpty)
        // Scrolling up asks the server (here: nobody), never the disk.
        relaunched.connectionState = .disconnected
        await relaunched.loadOlderHistory(for: vela)
        #expect(vela.lines.isEmpty)
        #expect(!vela.hasMoreHistory)
    }

    /// With nothing saved, what a bouncer replays after a relaunch still
    /// counts as unread past the saved read position (for badges, the New
    /// line and Catch me up).
    @Test func offStillCountsAReplayAgainstTheSavedReadPosition() async throws {
        let scratch = try ScratchDatabase()
        defer { scratch.cleanup() }
        let readAt = Date(timeIntervalSince1970: 1_800_000_000)
        do {
            let database = try scratch.open()
            let (session, _) = makeSession(.memoryOnly, database: database)
            feed(session, ":doug!d@host JOIN #vela")
            let vela = try #require(session.buffer(named: "#vela"))
            vela.lastReadAt = readAt
            session.persistBuffer(vela)
            await session.flushPendingRecordsNow()
        }

        let (relaunched, _) = makeSession(.memoryOnly, database: try scratch.open())
        await relaunched.restoreBuffers()
        let vela = try #require(relaunched.buffer(named: "#vela"))
        #expect(vela.lastReadAt == readAt)
        #expect(vela.lines.isEmpty)

        let batch = IRCBatch(id: "b1", type: "chathistory", params: ["#vela"], parentID: nil)
        relaunched.handle(.batchStarted(batch))
        for (index, (offset, text)) in [(-60.0, "read before"), (60.0, "missed one"), (120.0, "doug: missed two")].enumerated() {
            let time = ISO8601DateFormatter.string(
                from: readAt.addingTimeInterval(offset), timeZone: .gmt,
                formatOptions: [.withInternetDateTime, .withFractionalSeconds]
            )
            relaunched.handle(.message(IRCMessage(line: "@time=\(time);msgid=r\(index);batch=b1 :ada!a@host PRIVMSG #vela :\(text)")!, batch: batch))
        }
        relaunched.handle(.batchEnded(batch))

        #expect(vela.unreadCount == 2)
        #expect(vela.highlightCount == 1)
        #expect(vela.unreadMarkerAfter == readAt)
    }

    @Test func memoryStaysBoundedWhileOff() async throws {
        let scratch = try ScratchDatabase()
        defer { scratch.cleanup() }
        let (session, host) = makeSession(.memoryOnly, database: try scratch.open())
        host.behavior.scrollbackInMemory = 200
        feed(session, ":doug!d@host JOIN #vela")
        for index in 0..<1_000 { feed(session, ":ada!a@host PRIVMSG #vela :line \(index)") }
        let vela = try #require(session.buffer(named: "#vela"))
        // Trimmed to the limit, with up to 200 more before the next trim.
        #expect(vela.lines.count <= 400)
        #expect(vela.lines.last?.text == "line 999")
    }

    // MARK: On

    @Test func onSavesAndLoadsAsBefore() async throws {
        let scratch = try ScratchDatabase()
        defer { scratch.cleanup() }
        let database = try scratch.open()
        do {
            let (session, _) = makeSession(.saveAndLoad, database: database)
            try await chat(in: session, database: database)
            session.shutdown()
        }
        let counts = try await database.storageCounts()
        // A join and three messages (#vela and the query), all indexed.
        #expect(counts.messages == 4)
        #expect(counts.fullTextEntries == 4)
        #expect(counts.reactions == 1)
        #expect(counts.buffers == 2)
        #expect(try await database.search("plan", networkID: nil, limit: 5).map(\.text) == ["a secret plan"])
        #expect(try await database.buffers(networkID: config.id).first { $0.foldedName == "#vela" }?.isMuted == true)

        let (relaunched, _) = makeSession(.saveAndLoad, database: try scratch.open())
        await relaunched.restoreBuffers()
        let vela = try #require(relaunched.buffer(named: "#vela"))
        try await waitUntil { vela.lines.count == 3 && !vela.reactions(for: "m1").isEmpty }
        #expect(vela.lines.map(\.text).contains("a secret plan"))
        #expect(vela.lines.first { $0.msgid == "m2" }?.isRedacted == true)
    }

    // MARK: Kept

    @Test func keptHistoryStillLoadsButNothingNewIsSaved() async throws {
        let scratch = try ScratchDatabase()
        defer { scratch.cleanup() }
        let database = try scratch.open()
        do {
            let (session, _) = makeSession(.saveAndLoad, database: database)
            try await chat(in: session, database: database)
            session.shutdown()
        }
        let before = try await database.storageCounts()

        let (relaunched, _) = makeSession(.loadOnly, database: try scratch.open())
        await relaunched.restoreBuffers()
        let vela = try #require(relaunched.buffer(named: "#vela"))
        try await waitUntil { vela.lines.count == 3 }
        feed(relaunched,
             "@msgid=m3 :ada!a@host PRIVMSG #vela :not saved",
             "@+draft/react=🎉;+draft/reply=m3 :wren!w@host TAGMSG #vela")
        await relaunched.flushPendingRecordsNow()
        try await Task.sleep(for: .milliseconds(150))
        #expect(vela.lines.last?.text == "not saved")
        #expect(try await database.storageCounts() == before)
    }

    @Test func storageModes() {
        #expect(HistoryStorage(saves: true, hasSavedMessages: false) == .saveAndLoad)
        #expect(HistoryStorage(saves: false, hasSavedMessages: true) == .loadOnly)
        #expect(HistoryStorage(saves: false, hasSavedMessages: false) == .memoryOnly)
        #expect(HistoryStorage.saveAndLoad.saves && HistoryStorage.saveAndLoad.loads)
        #expect(!HistoryStorage.loadOnly.saves && HistoryStorage.loadOnly.loads)
        #expect(!HistoryStorage.memoryOnly.saves && !HistoryStorage.memoryOnly.loads)
    }

    // MARK: Catching up after connecting

    /// Connects to a scripted server with `chathistory`, joining #vela, and
    /// returns what Vela asked for when it joined.
    private func historyRequests(_ storage: HistoryStorage, database: VelaDatabase) async throws -> (NetworkSession, MockTransport) {
        let factory = MockTransportFactory { transport, _ in
            transport.setResponder { line in
                if line.hasPrefix("CAP LS") { return [":irc.test CAP * LS :server-time batch message-tags draft/chathistory"] }
                if line.hasPrefix("CAP REQ :") { return [":irc.test CAP * ACK :\(line.dropFirst("CAP REQ :".count))"] }
                if line == "CAP END" {
                    return [":irc.test 001 doug :Welcome", ":irc.test 005 doug CHANTYPES=# CHATHISTORY=50 :are supported"]
                }
                if line.hasPrefix("JOIN ") {
                    return [":doug!d@host JOIN #vela", ":irc.test 353 doug = #vela :doug ada", ":irc.test 366 doug #vela :End"]
                }
                return []
            }
        }
        let host = HistoryHost(storage)
        host.factory = factory
        var config = config
        config.autoJoin = [AutoJoinChannel(name: "#vela")]
        let session = NetworkSession(config: config, database: database, transportFactory: factory.makeTransport)
        session.host = host
        session.connect()
        try await waitUntil { factory.latest != nil }
        let transport = try #require(factory.latest)
        try await waitUntil { transport.sentLines.contains { $0.hasPrefix("CHATHISTORY") } }
        return (session, transport)
    }

    private static let savedTime = Date(timeIntervalSince1970: 1_700_000_000)

    private func databaseWithOldHistory(_ scratch: ScratchDatabase) async throws -> VelaDatabase {
        let database = try scratch.open()
        try await database.append([MessageRecord(
            networkID: config.id, bufferName: "#vela", time: Self.savedTime, kind: "message", nick: "ada", text: "long ago"
        )])
        return database
    }

    @Test func savingCatchesUpFromWhatWasSaved() async throws {
        let scratch = try ScratchDatabase()
        defer { scratch.cleanup() }
        let (session, transport) = try await historyRequests(.saveAndLoad, database: try await databaseWithOldHistory(scratch))
        defer { session.shutdown() }
        #expect(transport.sentLines.filter { $0.hasPrefix("CHATHISTORY") }
            == ["CHATHISTORY AFTER #vela timestamp=\(IRCTime.format(Self.savedTime)) 50"])
    }

    @Test func keptHistoryDoesntHoldBackTheLatestMessages() async throws {
        let scratch = try ScratchDatabase()
        defer { scratch.cleanup() }
        // Saving is off: what was saved long ago isn't where to catch up from.
        let (session, transport) = try await historyRequests(.loadOnly, database: try await databaseWithOldHistory(scratch))
        defer { session.shutdown() }
        #expect(transport.sentLines.filter { $0.hasPrefix("CHATHISTORY") } == ["CHATHISTORY LATEST #vela * 50"])
    }

    @Test func offCatchesUpFromWhatArrivedThisSession() async throws {
        let scratch = try ScratchDatabase()
        defer { scratch.cleanup() }
        let (session, transport) = try await historyRequests(.memoryOnly, database: try scratch.open())
        defer { session.shutdown() }
        #expect(transport.sentLines.filter { $0.hasPrefix("CHATHISTORY") } == ["CHATHISTORY LATEST #vela * 50"])

        // Rejoining (after a kick, say) asks for what came after the newest
        // line received, not after the new JOIN.
        let vela = try #require(session.buffer(named: "#vela"))
        feed(session, ":ada!a@host PRIVMSG #vela :still here")
        let newest = try #require(vela.newestReceivedAt)
        feed(session, ":doug!d@host JOIN #vela")
        try await waitUntil { transport.sentLines.filter { $0.hasPrefix("CHATHISTORY") }.count == 2 }
        #expect(transport.sentLines.filter { $0.hasPrefix("CHATHISTORY") }.last
            == "CHATHISTORY AFTER #vela timestamp=\(IRCTime.format(newest)) 50")
    }

    // MARK: Link previews

    private func preview(_ url: String) -> LinkPreview {
        LinkPreview(url: URL(string: url)!, kind: .page, title: "A page")
    }

    @Test func previewsStayInMemoryWhileOff() async throws {
        let database = try VelaDatabase.inMemory()
        let diskCache = PreviewDiskCacheSwitch(isOn: false)
        let cache = DatabasePreviewCache(database: database, diskCache: diskCache)
        await cache.storePreview(preview("https://example.com/off"))
        #expect(try await database.storageCounts().linkPreviews == 0)

        diskCache.isOn = true
        await cache.storePreview(preview("https://example.com/on"))
        #expect(try await database.storageCounts().linkPreviews == 1)
        #expect(await cache.cachedPreview(for: URL(string: "https://example.com/on")!)?.title == "A page")

        // Off again: the disk cache isn't read either.
        diskCache.isOn = false
        #expect(await cache.cachedPreview(for: URL(string: "https://example.com/on")!) == nil)
    }

    // MARK: The app

    private func makeApp(save: Bool?, database: VelaDatabase?) throws -> (AppModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "VelaHistoryApp-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = SettingsStore(fileURL: directory.appending(path: "settings.json"), watchForChanges: false)
        if let save { settings[.historySave] = save }
        let app = AppModel(
            settings: settings,
            networkStore: NetworkConfigStore(fileURL: directory.appending(path: "networks.json")),
            database: database,
            notifier: SilentNotifier()
        )
        return (app, directory)
    }

    @Test func appFollowsTheSetting() async throws {
        let database = try VelaDatabase.inMemory()
        let (app, directory) = try makeApp(save: nil, database: database)
        defer { try? FileManager.default.removeItem(at: directory) }
        // The image cache is shared by every test in this process.
        defer { ImageLoader.setDiskCacheEnabled(true) }

        // Off by default.
        #expect(app.historyStorage == .memoryOnly)
        #expect(!app.previewDiskCache.isOn)

        app.observeHistorySetting()
        app.settings[.historySave] = true
        try await waitUntil { app.previewDiskCache.isOn }
        #expect(app.historyStorage == .saveAndLoad)
        #expect(ImageLoader.httpCache.diskCapacity == ImageLoader.diskCacheCapacity)

        // Turned off with history kept, it still loads.
        try await database.append([MessageRecord(networkID: UUID(), bufferName: "#vela", time: Date(), kind: "message", text: "kept")])
        app.settings[.historySave] = false
        try await waitUntil { !app.previewDiskCache.isOn && app.savedHistory.hasMessages }
        #expect(app.historyStorage == .loadOnly)
        #expect(ImageLoader.httpCache.diskCapacity == 0)
    }

    @Test func deletingSavedHistory() async throws {
        let database = try VelaDatabase.inMemory()
        let network = UUID()
        try await database.append([MessageRecord(networkID: network, bufferName: "#vela", msgid: "x", time: Date(), kind: "message", text: "kept")])
        try await database.setReaction(ReactionRecord(msgid: "x", nick: "ada", emoji: "👍"), in: BufferKey(networkID: network, foldedName: "#vela"), active: true)
        try await database.storePreviewJSON(Data("{}".utf8), url: "https://example.com/")
        try await database.upsertBuffer(BufferRecord(networkID: network, name: "#vela", foldedName: "#vela", kind: "channel", isMuted: true))
        let (app, directory) = try makeApp(save: false, database: database)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(await app.refreshSavedHistory() == SavedHistory(hasMessages: true, hasReactions: true, hasLinkPreviews: true))
        #expect(app.historyStorage == .loadOnly)

        try await app.deleteSavedHistory()

        #expect(app.savedHistory.isEmpty)
        #expect(app.historyStorage == .memoryOnly)
        #expect(try await database.storageCounts() == StorageCounts(buffers: 1))
        #expect(try await database.buffers(networkID: network).first?.isMuted == true)
    }
}
