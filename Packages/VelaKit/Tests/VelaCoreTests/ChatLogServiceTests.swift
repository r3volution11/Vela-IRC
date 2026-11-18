// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

/// A session host that hands lines to a ``ChatLogService``, as AppModel does.
@MainActor
final class LoggingHost: SessionHost {
    let logs: ChatLogService
    var behavior = SessionBehavior()

    init(logs: ChatLogService) { self.logs = logs }

    func clientConfig(for session: NetworkSession) -> IRCClientConfig {
        IRCClientConfig(host: "irc.test", port: 6667, useTLS: false, nick: "doug")
    }
    func isBufferVisible(_ id: BufferID) -> Bool { false }
    func activeBuffer(in session: NetworkSession) -> BufferModel? { nil }
    func session(_ session: NetworkSession, didReceiveNotable line: ChatLine, in buffer: BufferModel) {}
    func session(_ session: NetworkSession, didUpdateBouncerNetworks networks: [BouncerNetwork]) {}
    func sessionDidChangeConfig(_ session: NetworkSession) {}
    func sessionDidChangeUnreadCounts(_ session: NetworkSession) {}
    func sessionDidChangeConnection(_ session: NetworkSession) { logs.connectionChanged(session) }
    func session(_ session: NetworkSession, didAdd line: ChatLine, to buffer: BufferModel) {
        logs.record(line, in: buffer, session: session)
    }
    func session(_ session: NetworkSession, didRedact line: ChatLine, by nick: String?, reason: String?, at time: Date, isHistory: Bool, in buffer: BufferModel) {
        logs.recordRedaction(of: line, by: nick, reason: reason, at: time, isHistory: isHistory, in: buffer, session: session)
    }
}

@MainActor
final class HostKeeper {
    var all: [LoggingHost] = []
}

@MainActor
@Suite("Chat logs")
struct ChatLogServiceTests {
    let folder = TemporaryFolder()
    let settings: SettingsStore
    let preferences = InMemoryChatLogPreferences()
    /// Sessions hold their host weakly; this keeps them for the test.
    let hosts = HostKeeper()

    init() {
        settings = SettingsStore(fileURL: folder.url.appending(path: "settings.json"), watchForChanges: false)
    }

    private var logsFolder: URL { folder.url.appending(path: "Logs", directoryHint: .isDirectory) }

    private func service(isDemo: Bool = false, bookmarks: FakeBookmarks = FakeBookmarks()) -> ChatLogService {
        ChatLogService(settings: settings, defaultFolder: logsFolder, preferences: preferences, bookmarks: bookmarks, isDemo: isDemo, flushDelay: .seconds(600))
    }

    private func session(_ logs: ChatLogService, name: String = "Libera.Chat", config: NetworkConfig? = nil) -> (NetworkSession, LoggingHost) {
        let host = LoggingHost(logs: logs)
        host.behavior.autoReconnect = false
        let session = NetworkSession(config: config ?? NetworkConfig(name: name, host: "irc.test", nick: "doug"), database: nil)
        session.host = host
        hosts.all.append(host)
        session.nick = "doug"
        session.connectionState = .connected
        var support = ISupport()
        support.apply(["PREFIX=(ov)@+", "CHANTYPES=#", "CASEMAPPING=rfc1459"])
        session.isupport = support
        return (session, host)
    }

    private func feed(_ session: NetworkSession, _ lines: String..., batch: IRCBatch? = nil) {
        for line in lines { session.handle(.message(IRCMessage(line: line)!, batch: batch)) }
    }

    private func log(_ path: String) -> String? {
        folder.contents("Logs/\(path)")
    }

    private func stamp(_ iso: String) -> String {
        ChatLogClock().string(from: try! Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(iso))
    }

    @Test func logsWhatWasWrittenByNetworkAndChannel() async {
        let logs = service()
        logs.start(networkIDs: [])
        settings[.loggingEnabled] = true
        let (session, _) = session(logs)
        feed(session,
             "@time=2026-11-17T21:04:01.000Z :doug!d@host JOIN #Vela",
             ":irc.test 332 doug #Vela :Vela, a \u{02}native\u{02} IRC client",
             "@time=2026-11-17T21:04:05.000Z :alice!a@example.org PRIVMSG #vela :hi \u{03}04doug\u{03}, see https://velairc.app",
             "@time=2026-11-17T21:04:09.000Z :doug!d@host PRIVMSG #vela :\u{01}ACTION waves\u{01}",
             "@time=2026-11-17T21:04:12.000Z :ChanServ!s@services NOTICE #vela :Welcome",
             "@time=2026-11-17T21:06:00.000Z :alice!a@example.org PART #vela :bye",
             "@time=2026-11-17T21:07:00.000Z :bob!b@host PRIVMSG doug :private hello",
             ":irc.test 001 doug :Welcome to the network")
        await logs.flush()

        let channel = log("Libera.Chat/#Vela.log") ?? ""
        #expect(channel.hasPrefix("--- Log opened "))
        let lines = channel.split(separator: "\n").dropFirst().map(String.init)
        #expect(lines.count == 6)
        #expect(lines[0] == "[\(stamp("2026-11-17T21:04:01.000Z"))] -!- doug (d@host) joined #Vela")
        #expect(lines[1].hasSuffix("] -!- Topic: Vela, a native IRC client"))
        #expect(lines[2] == "[\(stamp("2026-11-17T21:04:05.000Z"))] <alice> hi doug, see https://velairc.app")
        #expect(lines[3] == "[\(stamp("2026-11-17T21:04:09.000Z"))] * doug waves")
        #expect(lines[4] == "[\(stamp("2026-11-17T21:04:12.000Z"))] -ChanServ- Welcome")
        #expect(lines[5] == "[\(stamp("2026-11-17T21:06:00.000Z"))] -!- alice left #Vela (bye)")
        #expect(log("Libera.Chat/bob.log")?.contains("] <bob> private hello") == true)
        // Server messages are off by default.
        #expect(log("Libera.Chat/server.log") == nil)
    }

    @Test func eventsAndServerMessagesFollowTheirSwitches() async {
        let logs = service()
        logs.start(networkIDs: [])
        settings[.loggingEnabled] = true
        settings[.loggingIncludeEvents] = false
        settings[.loggingIncludeServer] = true
        let (session, _) = session(logs)
        feed(session,
             ":doug!d@host JOIN #vela",
             ":alice!a@host PRIVMSG #vela :hello",
             ":alice!a@host QUIT :gone",
             ":irc.test 001 doug :Welcome to the network")
        await logs.flush()
        let channel = log("Libera.Chat/#vela.log") ?? ""
        #expect(channel.contains("<alice> hello"))
        #expect(!channel.contains("joined") && !channel.contains("quit"))
        #expect(log("Libera.Chat/server.log")?.contains("-!- Welcome to the network") == true)
    }

    @Test func leftOutChannelsAndNetworksAreNotLogged() async {
        let logs = service()
        logs.start(networkIDs: [])
        settings[.loggingEnabled] = true
        let (session, _) = session(logs)
        settings[.loggingExcludedBuffers] = ["\(session.id.uuidString.lowercased())/#secret"]
        feed(session, ":alice!a@host PRIVMSG #Secret :hush", ":alice!a@host PRIVMSG #open :hello")
        await logs.flush()
        #expect(log("Libera.Chat/#Secret.log") == nil)
        #expect(log("Libera.Chat/#open.log") != nil)

        settings[.loggingExcludedBuffers] = [BufferScopeList.networkEntry(for: session.id)]
        feed(session, ":alice!a@host PRIVMSG #other :hello")
        await logs.flush()
        #expect(log("Libera.Chat/#other.log") == nil)
    }

    @Test func offByDefault() async {
        let logs = service()
        logs.start(networkIDs: [])
        let (session, _) = session(logs)
        feed(session, ":alice!a@host PRIVMSG #vela :hello")
        await logs.flush()
        #expect(!logs.isLogging)
        #expect(!FileManager.default.fileExists(atPath: logsFolder.path))
    }

    @Test func demoModeNeverLogs() async {
        let logs = service(isDemo: true)
        logs.start(networkIDs: [])
        settings[.loggingEnabled] = true
        let (session, _) = session(logs)
        feed(session, ":alice!a@host PRIVMSG #vela :hello")
        await logs.flush()
        #expect(!logs.isLogging)
        #expect(!FileManager.default.fileExists(atPath: logsFolder.path))
    }

    @Test func scrollbackFromTheDatabaseIsNotLoggedAgain() async {
        let logs = service()
        logs.start(networkIDs: [])
        settings[.loggingEnabled] = true
        let (session, _) = session(logs)
        let buffer = session.ensureBuffer(name: "#vela", kind: .channel, persist: false)
        // How restored and older messages arrive from Vela's database.
        buffer.insertSorted([ChatLine(kind: .message, nick: "alice", text: "from the database", isHistory: true)])
        feed(session, ":alice!a@host PRIVMSG #vela :live")
        await logs.flush()
        let text = log("Libera.Chat/#vela.log") ?? ""
        #expect(text.contains("<alice> live"))
        #expect(!text.contains("from the database"))
    }

    @Test func replayedLinesAfterADropFillTheGapOnce() async {
        let logs = service()
        logs.start(networkIDs: [])
        settings[.loggingEnabled] = true
        let (session, _) = session(logs)
        feed(session, "@time=2026-11-17T09:00:00.000Z :alice!a@host PRIVMSG #vela :before the drop")
        session.handle(.disconnected(reason: "Ping timeout"))
        session.connectionState = .connected
        feed(session, "@time=2026-11-17T09:30:00.000Z :doug!d@host PRIVMSG #vela :back")
        let batch = IRCBatch(id: "h1", type: "chathistory", params: ["#vela"])
        session.handle(.batchStarted(batch))
        feed(session,
             "@time=2026-11-17T09:00:00.500Z :alice!a@host PRIVMSG #vela :before the drop",
             "@time=2026-11-17T09:10:00.000Z :bob!b@host PRIVMSG #vela :while you were away",
             batch: batch)
        session.handle(.batchEnded(batch))
        await logs.flush()
        let text = log("Libera.Chat/#vela.log") ?? ""
        #expect(text.components(separatedBy: "before the drop").count == 2)
        #expect(text.contains("<bob> while you were away"))
        #expect(text.contains("<doug> back"))
    }

    @Test func deletedMessagesAreNotedNotRemoved() async {
        let logs = service()
        logs.start(networkIDs: [])
        settings[.loggingEnabled] = true
        let (session, _) = session(logs)
        feed(session,
             "@msgid=abc;time=2026-11-17T09:00:00.000Z :alice!a@host PRIVMSG #vela :oops",
             ":bob!b@host REDACT #vela abc :spam")
        await logs.flush()
        let text = log("Libera.Chat/#vela.log") ?? ""
        #expect(text.contains("<alice> oops"))
        #expect(text.contains("-!- bob deleted a message from alice sent at \(stamp("2026-11-17T09:00:00.000Z")) (spam)"))
    }

    @Test func aRenamedNetworkTakesItsFolderAlong() async {
        let logs = service()
        logs.start(networkIDs: [])
        settings[.loggingEnabled] = true
        let (session, _) = session(logs, name: "Libera")
        feed(session, ":alice!a@host PRIVMSG #vela :one")
        await logs.flush()
        var config = session.config
        config.name = "Libera.Chat"
        session.updateConfig(config)
        feed(session, ":alice!a@host PRIVMSG #vela :two")
        await logs.flush()
        #expect(folder.files(in: "Logs") == ["Libera.Chat"])
        let text = log("Libera.Chat/#vela.log") ?? ""
        #expect(text.contains("one") && text.contains("two"))
        #expect(preferences.networkFolders[session.id.uuidString] == "Libera.Chat")
    }

    @Test func aNetworkRenamedWhileVelaWasClosedKeepsItsLogs() async throws {
        let config = NetworkConfig(name: "Libera.Chat", host: "irc.test", nick: "doug")
        preferences.networkFolders = [config.id.uuidString: "Libera"]
        let old = logsFolder.appending(path: "Libera", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try "[2026-11-01 10:00:00] <alice> from last week\n".write(to: old.appending(path: "#vela.log"), atomically: true, encoding: .utf8)
        settings[.loggingEnabled] = true
        let logs = service()
        logs.start(networkIDs: [config.id])
        let (session, _) = session(logs, config: config)
        feed(session, ":alice!a@host PRIVMSG #vela :today")
        await logs.flush()
        #expect(folder.files(in: "Logs") == ["Libera.Chat"])
        let text = log("Libera.Chat/#vela.log") ?? ""
        #expect(text.contains("from last week") && text.contains("today"))
    }

    @Test func turningLoggingOffClosesTheLogs() async throws {
        let logs = service()
        logs.start(networkIDs: [])
        settings[.loggingEnabled] = true
        let (session, _) = session(logs)
        feed(session, ":alice!a@host PRIVMSG #vela :hello")
        settings[.loggingEnabled] = false
        // The settings change reaches the writer on the next main-actor turn.
        for _ in 0..<50 where !(log("Libera.Chat/#vela.log")?.contains("--- Log closed") ?? false) {
            try await Task.sleep(for: .milliseconds(20))
            await logs.flush()
        }
        #expect(log("Libera.Chat/#vela.log")?.contains("<alice> hello\n--- Log closed") == true)
        feed(session, ":alice!a@host PRIVMSG #vela :not logged")
        await logs.flush()
        #expect(log("Libera.Chat/#vela.log")?.contains("not logged") == false)
    }

    @Test func choosingAFolderAndGoingBack() async throws {
        let bookmarks = FakeBookmarks()
        let logs = service(bookmarks: bookmarks)
        logs.start(networkIDs: [])
        settings[.loggingEnabled] = true
        let chosen = folder.url.appending(path: "Chosen", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        try logs.chooseFolder(chosen)
        #expect(logs.folderStatus == .custom)
        #expect(preferences.folderBookmark != nil)
        #expect(preferences.folderPath == chosen.path)

        let (session, _) = session(logs)
        feed(session, ":alice!a@host PRIVMSG #vela :in the chosen folder")
        await logs.flush()
        #expect(folder.contents("Chosen/Libera.Chat/#vela.log")?.contains("in the chosen folder") == true)

        logs.useDefaultFolder()
        feed(session, ":alice!a@host PRIVMSG #vela :back in Vela's folder")
        await logs.flush()
        #expect(logs.folderStatus == .standard)
        #expect(preferences.folderBookmark == nil)
        #expect(folder.contents("Chosen/Libera.Chat/#vela.log")?.contains("--- Log closed") == true)
        #expect(log("Libera.Chat/#vela.log")?.contains("back in Vela's folder") == true)
        #expect(bookmarks.stopped == [chosen])
    }

    @Test func aChosenFolderThatIsGoneFallsBackAtLaunch() {
        preferences.folderBookmark = Data("x".utf8)
        preferences.folderPath = "/Volumes/Gone/Logs"
        let logs = service(bookmarks: FakeBookmarks(.fails))
        logs.start(networkIDs: [])
        #expect(logs.folderURL == logsFolder)
        #expect(logs.folderStatus == .unavailable(path: "/Volumes/Gone/Logs"))
        // Kept, so the folder comes back when its disk does.
        #expect(preferences.folderBookmark != nil)
    }

    @Test func aFolderThatCantBeRememberedIsNotUsed() {
        let bookmarks = FakeBookmarks()
        bookmarks.bookmarkFails = true
        let logs = service(bookmarks: bookmarks)
        logs.start(networkIDs: [])
        #expect(throws: (any Error).self) { try logs.chooseFolder(folder.url) }
        #expect(logs.folderStatus == .standard)
        #expect(preferences.folderBookmark == nil)
    }

    @Test func pathsShowFromYourHomeFolder() {
        let home = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        #expect(ChatLogService.abbreviate(home + "/Logs/IRC") == "~/Logs/IRC")
        #expect(ChatLogService.abbreviate("/Volumes/Archive") == "/Volumes/Archive")
    }
}

@MainActor
@Suite("Chat logs in the app")
struct ChatLogAppModelTests {
    @Test func logsGoNextToSettingsAndChannelsCanBeLeftOut() {
        let folder = TemporaryFolder()
        let app = AppModel(
            settings: SettingsStore(fileURL: folder.url.appending(path: "settings.json"), watchForChanges: false),
            networkStore: NetworkConfigStore(fileURL: folder.url.appending(path: "networks.json")),
            database: nil,
            isDemo: true
        )
        #expect(app.chatLogs.defaultFolderURL == folder.url.appending(path: "Logs", directoryHint: .isDirectory))
        let network = UUID()
        let channel = BufferID(networkID: network, foldedName: "#vela")
        #expect(!app.isLogExcluded(channel))
        app.setLogExcluded(true, for: channel)
        #expect(app.isLogExcluded(channel))
        #expect(app.settings[.loggingExcludedBuffers] == [channel.description])
        app.setLogExcluded(true, network: network)
        #expect(app.isLogExcluded(network: network))
        #expect(app.isLogExcluded(BufferID(networkID: network, foldedName: "#other")))
        app.setLogExcluded(false, network: network)
        app.setLogExcluded(false, for: channel)
        #expect(app.settings[.loggingExcludedBuffers].isEmpty)
    }
}
