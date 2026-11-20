// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaStore

/// What Siri and Shortcuts see right after they launch Vela: `ready()`
/// waits for each buffer's restored history, and unread lines and mentions
/// are counted from the read position and that history, not from live
/// counts (which start at zero).
@MainActor
@Suite("Readiness for Siri")
struct IntentReadinessTests {
    /// A real (not demo) app on an in-memory store with one network that
    /// doesn't connect, and the saved buffers and messages of an earlier run.
    private func launchedApp(
        buffers: [BufferRecord],
        messages: [MessageRecord],
        network: NetworkConfig
    ) async throws -> AppModel {
        let folder = FileManager.default.temporaryDirectory.appending(path: "VelaReadiness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let database = try VelaDatabase.inMemory()
        for buffer in buffers { try await database.upsertBuffer(buffer) }
        try await database.append(messages)
        let networks = NetworkConfigStore(fileURL: folder.appending(path: "networks.json"))
        networks.upsert(network)
        let settings = SettingsStore(fileURL: folder.appending(path: "settings.json"), watchForChanges: false)
        settings.saveDelay = .seconds(60)
        return AppModel(settings: settings, networkStore: networks, database: database, notifier: SilentNotifier())
    }

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func message(_ network: UUID, _ buffer: String, minute: Int, nick: String = "ada", text: String = "hi", isSelf: Bool = false, isHighlight: Bool = false) -> MessageRecord {
        MessageRecord(
            networkID: network,
            bufferName: buffer,
            time: start.addingTimeInterval(TimeInterval(minute * 60)),
            kind: "message",
            nick: nick,
            text: text,
            isSelf: isSelf,
            isHighlight: isHighlight
        )
    }

    @Test func readyWaitsForHistoryAndCountsFromTheReadPosition() async throws {
        let network = NetworkConfig(name: "Libera.Chat", host: "irc.example.invalid", nick: "doug", autoConnect: false)
        let id = network.id
        let readAt = start.addingTimeInterval(10 * 60)
        let app = try await launchedApp(
            buffers: [
                BufferRecord(networkID: id, name: "#quiet", foldedName: "#quiet", kind: "channel", lastReadAt: readAt, sortOrder: 0),
                BufferRecord(networkID: id, name: "#vela", foldedName: "#vela", kind: "channel", lastReadAt: readAt, sortOrder: 1),
                BufferRecord(networkID: id, name: "marisol", foldedName: "marisol", kind: "query", lastReadAt: readAt),
            ],
            messages: [
                // #quiet: everything was read.
                message(id, "#quiet", minute: 5),
                message(id, "#quiet", minute: 9),
                // #vela: two read, four new (one of them yours, one a mention).
                message(id, "#vela", minute: 2),
                message(id, "#vela", minute: 8),
                message(id, "#vela", minute: 11),
                message(id, "#vela", minute: 12, nick: "doug", isSelf: true),
                message(id, "#vela", minute: 13, text: "doug: look", isHighlight: true),
                message(id, "#vela", minute: 14),
                // marisol: one new private message.
                message(id, "marisol", minute: 15, nick: "marisol"),
            ],
            network: network
        )

        await app.ready()

        #expect(app.isReady)
        let session = try #require(app.sessions.first)
        let vela = try #require(session.buffer(named: "#vela"))
        // The history is there by the time ready() returns.
        #expect(vela.lines.count == 6)
        #expect(session.buffer(named: "marisol")?.lines.count == 1)
        // Live counts haven't seen any of it…
        #expect(vela.unreadCount == 0)
        // …but what's newer than the read position is unread.
        #expect(vela.unreadByReadPosition == UnreadTally(unread: 3, mentions: 1))
        #expect(app.busiestUnreadBuffer?.name == "#vela")
        let mentions = app.mentionSummary
        #expect(mentions.entries.map(\.name) == ["#vela", "marisol"])
        #expect(mentions.entries.map(\.mentions) == [1, 1])
        #expect(mentions.totalMentions == 2)
    }

    @Test func nothingNewMeansCaughtUp() async throws {
        let network = NetworkConfig(name: "OFTC", host: "irc.example.invalid", nick: "doug", autoConnect: false)
        let app = try await launchedApp(
            buffers: [BufferRecord(networkID: network.id, name: "#tor", foldedName: "#tor", kind: "channel", lastReadAt: start.addingTimeInterval(3600))],
            messages: [message(network.id, "#tor", minute: 1), message(network.id, "#tor", minute: 2)],
            network: network
        )
        await app.ready()
        #expect(app.sessions.first?.buffer(named: "#tor")?.lines.count == 2)
        #expect(app.busiestUnreadBuffer == nil)
        #expect(app.mentionSummary.isEmpty)
    }

    // MARK: Counting

    private func buffer(_ name: String, kind: BufferKind = .channel, readAt: Date?) -> BufferModel {
        let buffer = BufferModel(id: BufferID(networkID: UUID(), foldedName: name), name: name, kind: kind)
        buffer.lastReadAt = readAt
        return buffer
    }

    private func line(minute: Int, kind: ChatLineKind = .message, isSelf: Bool = false, isHighlight: Bool = false, isRedacted: Bool = false) -> ChatLine {
        ChatLine(time: start.addingTimeInterval(TimeInterval(minute * 60)), kind: kind, nick: isSelf ? "doug" : "ada",
                 text: "hi", isSelf: isSelf, isHighlight: isHighlight, isRedacted: isRedacted, isHistory: true)
    }

    @Test func readPositionCountsOthersConversationOnly() {
        let channel = buffer("#vela", readAt: start.addingTimeInterval(5 * 60))
        channel.lines = [
            line(minute: 1, isHighlight: true),  // read
            line(minute: 6),
            line(minute: 7, kind: .join),  // not conversation
            line(minute: 8, isSelf: true),  // yours
            line(minute: 9, isRedacted: true),  // deleted
            line(minute: 10, kind: .notice, isHighlight: true),
            line(minute: 11, kind: .action),
        ]
        #expect(channel.unreadByReadPosition == UnreadTally(unread: 3, mentions: 1))

        // In a private conversation every message is a mention; notices aren't.
        let query = buffer("marisol", kind: .query, readAt: nil)
        query.lines = [line(minute: 1), line(minute: 2, kind: .notice), line(minute: 3, kind: .action)]
        #expect(query.unreadByReadPosition == UnreadTally(unread: 3, mentions: 2))
    }

    @Test func tallyTakesTheLargerCountUnlessOnScreen() {
        let channel = buffer("#vela", readAt: start)
        channel.lines = [line(minute: 1), line(minute: 2, isHighlight: true)]
        #expect(UnreadTally(buffer: channel, isOnScreen: false) == UnreadTally(unread: 2, mentions: 1))
        // Live counts that are ahead (lines stamped before the read
        // position, say) win.
        channel.unreadCount = 5
        channel.highlightCount = 2
        #expect(UnreadTally(buffer: channel, isOnScreen: false) == UnreadTally(unread: 5, mentions: 2))
        // On screen, new lines are seen as they arrive: only live counts.
        channel.unreadCount = 0
        channel.highlightCount = 0
        #expect(UnreadTally(buffer: channel, isOnScreen: true) == UnreadTally(unread: 0, mentions: 0))
    }

    @Test func pendingWorkWaitsForEveryLoad() async {
        let work = PendingWork()
        await work.wait()  // Nothing in flight: returns at once.
        work.begin()
        work.begin()
        let finished = Flag()
        let waiter = Task { @MainActor in
            await work.wait()
            finished.isSet = true
        }
        for _ in 0..<5 { await Task.yield() }
        work.end()
        for _ in 0..<5 { await Task.yield() }
        #expect(!finished.isSet)
        work.end()
        await waiter.value
        #expect(finished.isSet)
        #expect(work.isIdle)
    }

    @MainActor
    private final class Flag {
        var isSet = false
    }
}
