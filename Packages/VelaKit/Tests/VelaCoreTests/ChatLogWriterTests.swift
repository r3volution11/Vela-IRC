// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore

/// A temporary folder for one test, removed afterwards.
final class TemporaryFolder {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appending(path: "VelaChatLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        // Undo any permission changes a test made, then remove everything.
        if let paths = FileManager.default.subpaths(atPath: url.path) {
            for path in [url.path] + paths.map({ url.appending(path: $0).path }) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }

    func contents(_ path: String) -> String? {
        try? String(contentsOf: url.appending(path: path), encoding: .utf8)
    }

    func files(in folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.appending(path: folder).path)) ?? []).sorted()
    }
}

/// A clock the writer reads for its markers.
final class TestNow: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ date: Date) { value = date }

    var date: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Problems the writer reported.
final class ProblemLog: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [String?] = []

    func append(_ message: String?) { lock.withLock { reports.append(message) } }
    var all: [String?] { lock.withLock { reports } }
}

@Suite("Chat log writer")
struct ChatLogWriterTests {
    private let network = UUID()
    private let now = TestNow(logDate("2026-11-17 21:00:00"))

    private func writer(maxOpenHandles: Int = 32, flushDelay: Duration = .seconds(600), problems: ProblemLog? = nil) -> ChatLogWriter {
        let now = now
        return ChatLogWriter(
            clock: utcLogClock,
            flushDelay: flushDelay,
            maxOpenHandles: maxOpenHandles,
            now: { now.date },
            onProblem: { problems?.append($0) }
        )
    }

    private func target(_ name: String, folder: String = "Libera.Chat", network: UUID? = nil) -> ChatLogTarget {
        ChatLogTarget(networkID: network ?? self.network, networkFolder: folder, identity: name.lowercased(), fileBase: name)
    }

    private func entry(_ name: String, _ time: String, _ text: String, nick: String = "alice", history: Bool = false, folder: String = "Libera.Chat") -> ChatLogEntry {
        ChatLogEntry(target: target(name, folder: folder), time: logDate(time), isHistory: history, content: .line(kind: .message, nick: nick, text: text, isSelf: false))
    }

    private func configure(_ writer: ChatLogWriter, _ folder: TemporaryFolder, maxBytes: Int64 = 10 * 1_048_576, keep: Int = 5) async {
        await writer.configure(ChatLogConfiguration(folder: folder.url, maxFileBytes: maxBytes, keepFiles: keep))
    }

    @Test func writesOnFlushWithOpenAndCloseMarkers() async {
        let folder = TemporaryFolder()
        let writer = writer()
        await configure(writer, folder)
        await writer.append(entry("#vela", "2026-11-17 21:04:05", "hello"))
        #expect(folder.contents("Libera.Chat/#vela.log") == nil, "Nothing is written before a flush")
        await writer.flush()
        #expect(folder.contents("Libera.Chat/#vela.log") == """
        --- Log opened 2026-11-17 21:00:00 ---
        [2026-11-17 21:04:05] <alice> hello

        """)
        await writer.append(entry("#vela", "2026-11-17 21:04:09", "again"))
        now.date = logDate("2026-11-17 23:00:00")
        await writer.closeAll()
        #expect(folder.contents("Libera.Chat/#vela.log") == """
        --- Log opened 2026-11-17 21:00:00 ---
        [2026-11-17 21:04:05] <alice> hello
        [2026-11-17 21:04:09] <alice> again
        --- Log closed 2026-11-17 23:00:00 ---

        """)
        #expect(await writer.openHandleCount == 0)
    }

    @Test func flushesOnItsOwnAboutOnceASecond() async throws {
        let folder = TemporaryFolder()
        let writer = writer(flushDelay: .milliseconds(50))
        await configure(writer, folder)
        await writer.append(entry("#vela", "2026-11-17 21:04:05", "soon"))
        for _ in 0..<100 where folder.contents("Libera.Chat/#vela.log") == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(folder.contents("Libera.Chat/#vela.log")?.contains("<alice> soon") == true)
    }

    @Test func appendsToAnExistingLogInANewSession() async {
        let folder = TemporaryFolder()
        let first = writer()
        await configure(first, folder)
        await first.append(entry("#vela", "2026-11-17 21:04:05", "one"))
        await first.closeAll()
        let second = writer()
        await configure(second, folder)
        await second.append(entry("#vela", "2026-11-18 09:00:00", "two"))
        await second.closeAll()
        let text = folder.contents("Libera.Chat/#vela.log") ?? ""
        #expect(text.components(separatedBy: "--- Log opened").count == 3)
        #expect(text.components(separatedBy: "--- Log closed").count == 3)
        #expect(text.contains("<alice> one\n--- Log closed"))
        #expect(text.hasSuffix("<alice> two\n--- Log closed 2026-11-17 21:00:00 ---\n"))
    }

    @Test func rotatesAndKeepsTheNewestFiles() async {
        let folder = TemporaryFolder()
        let writer = writer()
        // A marker and a line are 75 bytes: every new line starts a new file.
        await configure(writer, folder, maxBytes: 100, keep: 3)
        for day in 1...6 {
            let date = String(format: "2026-11-%02d 10:00:00", day)
            await writer.append(entry("#vela", date, "day \(day)"))
            await writer.flush()
        }
        let files = folder.files(in: "Libera.Chat")
        // The current file plus two full ones; the oldest were deleted.
        #expect(files.count == 3)
        #expect(files.contains("#vela.log"))
        let rotated = files.filter { $0 != "#vela.log" }
        #expect(rotated.allSatisfy { ChatLogNaming.parseRotated($0, base: "#vela") != nil })
        #expect(rotated.allSatisfy { !$0.contains("2026-11-01 –") })
        // Every file starts with its own "Log opened" and full ones end closed.
        for name in rotated {
            let text = folder.contents("Libera.Chat/\(name)") ?? ""
            #expect(text.hasPrefix("--- Log opened"))
            #expect(text.hasSuffix("---\n") && text.contains("--- Log closed"))
        }
        #expect(folder.contents("Libera.Chat/#vela.log")?.contains("day 6") == true)
    }

    @Test func rotatedFilesAreNamedForTheDatesTheyCover() async {
        let folder = TemporaryFolder()
        let writer = writer()
        await configure(writer, folder, maxBytes: 130, keep: 0)
        await writer.append(entry("#vela", "2026-11-01 10:00:00", "first"))
        await writer.append(entry("#vela", "2026-11-17 10:00:00", "second"))
        await writer.flush()
        await writer.append(entry("#vela", "2026-11-18 10:00:00", "third"))
        await writer.flush()
        let files = folder.files(in: "Libera.Chat")
        #expect(files.contains("#vela 2026-11-01 – 2026-11-17.log"))
        #expect(folder.contents("Libera.Chat/#vela.log")?.contains("third") == true)
    }

    @Test func keepAllNeverDeletes() async {
        let folder = TemporaryFolder()
        let writer = writer()
        await configure(writer, folder, maxBytes: 100, keep: 0)
        for day in 1...6 {
            await writer.append(entry("#vela", String(format: "2026-11-%02d 10:00:00", day), "day \(day)"))
            await writer.flush()
        }
        #expect(folder.files(in: "Libera.Chat").count == 6)
    }

    @Test func twoFullFilesInOneDayGetACounter() async {
        let folder = TemporaryFolder()
        let writer = writer()
        await configure(writer, folder, maxBytes: 100, keep: 0)
        for minute in 0..<4 {
            await writer.append(entry("#vela", String(format: "2026-11-17 10:%02d:00", minute), "minute \(minute)"))
            await writer.flush()
        }
        let files = folder.files(in: "Libera.Chat")
        #expect(files.contains("#vela 2026-11-17 – 2026-11-17.log"))
        #expect(files.contains("#vela 2026-11-17 – 2026-11-17 (2).log"))
    }

    @Test func pruneSortsByDateNotName() throws {
        let folder = TemporaryFolder()
        let names = [
            "#vela 2026-09-01 – 2026-10-01.log",
            "#vela 2026-10-01 – 2026-11-01.log",
            "#vela 2026-11-01 – 2026-11-17.log",
            "#vela 2026-11-17 – 2026-11-17 (2).log",
            "#vela.log",
            "#vela-dev 2026-01-01 – 2026-02-01.log",
            "notes.txt",
        ]
        for name in names { try Data().write(to: folder.url.appending(path: name)) }
        ChatLogWriter.prune(in: folder.url, base: "#vela", keep: 3)
        #expect(folder.files(in: ".") == [
            "#vela 2026-11-01 – 2026-11-17.log",
            "#vela 2026-11-17 – 2026-11-17 (2).log",
            "#vela-dev 2026-01-01 – 2026-02-01.log",
            "#vela.log",
            "notes.txt",
        ])
    }

    // MARK: Replayed lines

    @Test func replayedLinesFillTheGapSinceTheLogEnded() async throws {
        let folder = TemporaryFolder()
        try FileManager.default.createDirectory(at: folder.url.appending(path: "Libera.Chat"), withIntermediateDirectories: true)
        try """
        --- Log opened 2026-11-16 08:00:00 ---
        [2026-11-16 20:00:00] <alice> before Vela quit
        --- Log closed 2026-11-16 22:00:00 ---

        """.write(to: folder.url.appending(path: "Libera.Chat/#vela.log"), atomically: true, encoding: .utf8)

        let writer = writer()
        await configure(writer, folder)
        // Connecting: your join arrives live, then the bouncer replays.
        await writer.append(entry("#vela", "2026-11-17 09:00:00", "live first", nick: "doug"))
        await writer.append(entry("#vela", "2026-11-16 19:00:00", "already logged long ago", history: true))
        await writer.append(entry("#vela", "2026-11-16 20:00:00", "before Vela quit", history: true))
        await writer.append(entry("#vela", "2026-11-16 23:00:00", "said while Vela was closed", history: true))
        await writer.append(entry("#vela", "2026-11-17 08:30:00", "also missed", history: true))
        // The same replay again (a second history request) adds nothing.
        await writer.append(entry("#vela", "2026-11-16 23:00:00", "said while Vela was closed", history: true))
        await writer.flush()
        let text = folder.contents("Libera.Chat/#vela.log") ?? ""
        #expect(text.components(separatedBy: "before Vela quit").count == 2)
        #expect(!text.contains("already logged long ago"))
        #expect(text.components(separatedBy: "said while Vela was closed").count == 2)
        #expect(text.contains("also missed"))
        #expect(text.contains("live first"))
    }

    @Test func aNewLogTakesNoReplayedLinesFromBeforeIt() async {
        let folder = TemporaryFolder()
        let writer = writer()
        await configure(writer, folder)
        await writer.append(entry("#new", "2026-11-17 09:00:00", "my join", nick: "doug"))
        await writer.append(entry("#new", "2026-11-17 08:00:00", "said before I joined", history: true))
        await writer.append(entry("#new", "2026-11-17 09:00:30", "replayed after I joined", history: true))
        await writer.flush()
        let text = folder.contents("Libera.Chat/#new.log") ?? ""
        #expect(!text.contains("before I joined"))
        #expect(text.contains("replayed after I joined"))
    }

    @Test func reconnectingReplaysWhatWasMissedWhileOffline() async {
        let folder = TemporaryFolder()
        let writer = writer()
        await configure(writer, folder)
        await writer.append(entry("#vela", "2026-11-17 09:00:00", "before the drop"))
        await writer.networkDisconnected(network)
        // Reconnected: live lines first, then the replay of the gap.
        await writer.append(entry("#vela", "2026-11-17 09:30:00", "after reconnecting", nick: "doug"))
        await writer.append(entry("#vela", "2026-11-17 09:00:00", "before the drop", history: true))
        await writer.append(entry("#vela", "2026-11-17 09:10:00", "while offline", history: true))
        await writer.flush()
        let text = folder.contents("Libera.Chat/#vela.log") ?? ""
        #expect(text.components(separatedBy: "before the drop").count == 2)
        #expect(text.contains("while offline"))
        #expect(text.contains("after reconnecting"))
    }

    // MARK: Names and folders

    @Test func usesAnExistingFileWhoseNameDiffersOnlyInCase() async throws {
        let folder = TemporaryFolder()
        let network = folder.url.appending(path: "Libera.Chat")
        try FileManager.default.createDirectory(at: network, withIntermediateDirectories: true)
        try "[2026-11-01 10:00:00] <alice> old\n".write(to: network.appending(path: "#Vela[1].log"), atomically: true, encoding: .utf8)
        let writer = writer()
        await configure(writer, folder)
        // rfc1459 folds [ to {, so #vela{1} is the same channel.
        let target = ChatLogTarget(networkID: self.network, networkFolder: "Libera.Chat", identity: "#vela{1}", fileBase: "#vela{1}", caseMapping: .rfc1459)
        await writer.append(ChatLogEntry(target: target, time: logDate("2026-11-17 10:00:00"), isHistory: false, content: .line(kind: .message, nick: "bob", text: "new", isSelf: false)))
        await writer.flush()
        #expect(folder.files(in: "Libera.Chat") == ["#Vela[1].log"])
        #expect(folder.contents("Libera.Chat/#Vela[1].log")?.contains("<bob> new") == true)
    }

    @Test func renamingANetworkMovesItsFolder() async {
        let folder = TemporaryFolder()
        let writer = writer()
        await configure(writer, folder)
        await writer.append(entry("#vela", "2026-11-17 10:00:00", "before", folder: "irc.libera.chat"))
        await writer.flush()
        await writer.renameNetworkFolder(network, from: "irc.libera.chat", to: "Libera.Chat")
        await writer.append(entry("#vela", "2026-11-17 10:01:00", "after", folder: "Libera.Chat"))
        await writer.flush()
        #expect(folder.files(in: ".") == ["Libera.Chat"])
        let text = folder.contents("Libera.Chat/#vela.log") ?? ""
        #expect(text.contains("before") && text.contains("after"))
        #expect(text.components(separatedBy: "Log opened").count == 2, "The log carries on")
    }

    @Test func keepsFewHandlesOpen() async {
        let folder = TemporaryFolder()
        let writer = writer(maxOpenHandles: 2)
        await configure(writer, folder)
        for name in ["#a", "#b", "#c", "#d"] {
            await writer.append(entry(name, "2026-11-17 10:00:00", "hi \(name)"))
        }
        await writer.flush()
        #expect(await writer.openHandleCount == 2)
        await writer.append(entry("#a", "2026-11-17 10:01:00", "again"))
        await writer.flush()
        #expect(await writer.openHandleCount == 2)
        #expect(folder.contents("Libera.Chat/#a.log")?.contains("again") == true)
        #expect(folder.files(in: "Libera.Chat").count == 4)
    }

    @Test func changingTheFolderClosesTheOldLogs() async {
        let first = TemporaryFolder(), second = TemporaryFolder()
        let writer = writer()
        await configure(writer, first)
        await writer.append(entry("#vela", "2026-11-17 10:00:00", "one"))
        await configure(writer, second)
        await writer.append(entry("#vela", "2026-11-17 10:01:00", "two"))
        await writer.flush()
        #expect(first.contents("Libera.Chat/#vela.log")?.hasSuffix("--- Log closed 2026-11-17 21:00:00 ---\n") == true)
        #expect(second.contents("Libera.Chat/#vela.log")?.contains("two") == true)
        await writer.configure(nil)
        await writer.append(entry("#vela", "2026-11-17 10:02:00", "three"))
        await writer.flush()
        #expect(second.contents("Libera.Chat/#vela.log")?.contains("three") == false)
    }

    @Test func reportsWriteProblemsAndRecovers() async throws {
        let folder = TemporaryFolder()
        let problems = ProblemLog()
        let writer = writer(problems: problems)
        await configure(writer, folder)
        // A network folder Vela can't write to.
        let locked = folder.url.appending(path: "Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        await writer.append(entry("#vela", "2026-11-17 10:00:00", "lost", folder: "Locked"))
        await writer.flush()
        let problem = try #require(await writer.problem)
        #expect(problem.contains("#vela.log"))
        #expect(problem.contains("Permission denied"))
        #expect(problems.all == [problem])

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        await writer.append(entry("#vela", "2026-11-17 10:01:00", "saved", folder: "Locked"))
        await writer.flush()
        #expect(await writer.problem == nil)
        #expect(problems.all == [problem, nil])
        let text = folder.contents("Locked/#vela.log") ?? ""
        #expect(text.contains("saved") && !text.contains("lost"))
    }
}
