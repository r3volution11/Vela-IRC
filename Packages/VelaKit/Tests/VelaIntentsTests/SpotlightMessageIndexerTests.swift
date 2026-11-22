// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import os
@testable import VelaCore
@testable import VelaIntents
import VelaStore

/// Stands in for Core Spotlight's message items.
nonisolated final class FakeMessageIndex: MessageSpotlightIndex {
    enum Call: Equatable {
        case index([String])
        case deleteIdentifiers([String])
        case deleteDomains([String])
    }

    private let recorded = OSAllocatedUnfairLock(initialState: (calls: [Call](), items: [String: SpotlightMessageItem]()))

    var calls: [Call] { recorded.withLock { $0.calls } }
    /// What's in the index now, by identifier.
    var items: [String: SpotlightMessageItem] { recorded.withLock { $0.items } }

    func clear() { recorded.withLock { $0.calls.removeAll() } }

    func index(_ items: [SpotlightMessageItem]) async throws {
        recorded.withLock { state in
            state.calls.append(.index(items.map(\.identifier)))
            for item in items { state.items[item.identifier] = item }
        }
    }

    func delete(identifiers: [String]) async throws {
        recorded.withLock { state in
            state.calls.append(.deleteIdentifiers(identifiers))
            for identifier in identifiers { state.items[identifier] = nil }
        }
    }

    func delete(domains: [String]) async throws {
        recorded.withLock { state in
            state.calls.append(.deleteDomains(domains))
            state.items = state.items.filter { _, item in
                !domains.contains { item.domain == $0 || item.domain.hasPrefix($0 + ".") }
            }
        }
    }
}

@MainActor
@Suite("Spotlight message indexing", .serialized)
struct SpotlightMessageIndexerTests {
    private let network = UUID(uuidString: "6B1D9C6E-1234-4C5D-8E9F-0A1B2C3D4E5F")!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ buffer: String, _ text: String, minute: Int = 0, kind: String = "message", nick: String? = "ada", network: UUID? = nil, redacted: Bool = false) -> MessageRecord {
        MessageRecord(
            networkID: network ?? self.network, bufferName: buffer, time: start.addingTimeInterval(TimeInterval(minute * 60)),
            kind: kind, nick: nick, text: text, isRedacted: redacted
        )
    }

    private var context: SavedMessagesContext {
        SavedMessagesContext(networkID: network, networkName: "Libera.Chat", buffers: [
            "#vela": .init(name: "#Vela", kind: .channel),
            "marisol": .init(name: "Marisol", kind: .query),
            "*server*": .init(name: "Libera.Chat", kind: .server),
        ])
    }

    // MARK: Items

    @Test func itemsAreMessagesOfConversations() {
        let records = [
            record("#vela", "hello", minute: 1),
            record("#vela", "waves", minute: 2, kind: "action"),
            record("marisol", "psst", minute: 3, nick: "marisol"),
            record("#vela", "ada has joined", minute: 4, kind: "join"),
            record("*server*", "MOTD", minute: 5, kind: "notice"),
            record("#vela", "deleted", minute: 6, redacted: true),
            record("#closed", "gone", minute: 7),
            record("#vela", "   ", minute: 8),
        ]
        let items = SpotlightMessageItem.items(for: records, context: context, retentionDays: 0)
        #expect(items.map(\.text) == ["hello", "ada waves", "psst"])
        #expect(items.map(\.title) == ["ada in #Vela", "ada in #Vela", "marisol"])
        #expect(items[0].container == "#Vela · Libera.Chat")
        #expect(items[0].author == "ada")
        #expect(items[0].expiration == .distantFuture)
        #expect(items[2].domain == SpotlightMessageID.domain(buffer: BufferID(networkID: network, foldedName: "marisol")))
    }

    @Test func itemsExpireWithSavedHistory() {
        let items = SpotlightMessageItem.items(for: [record("#vela", "hi")], context: context, retentionDays: 30)
        #expect(items.first?.expiration == start.addingTimeInterval(30 * 86_400))
    }

    @Test func longTextIsCut() throws {
        let long = String(repeating: "a", count: 5_000)
        let item = try #require(SpotlightMessageItem.items(for: [record("#vela", long)], context: context, retentionDays: 0).first)
        #expect(item.text.count == SpotlightMessageItem.maximumTextLength + 1)
    }

    /// A huge replay indexes only its newest messages.
    @Test func batchesAreCapped() {
        let records = (0..<5_000).map { record("#vela", "line \($0)", minute: $0) }
        let items = SpotlightMessageItem.items(for: records, context: context, retentionDays: 0)
        #expect(items.count == SpotlightMessageItem.maximumPerBatch)
        #expect(items.last?.text == "line 4999")
    }

    @Test func identifiersCarryWhatOpeningNeeds() throws {
        let line = UUID()
        for name in ["#vela", "#a.b/c", "marisol", "#über"] {
            let buffer = BufferID(networkID: network, foldedName: name)
            let time = Date(timeIntervalSince1970: 1_800_000_123.456)
            let identifier = SpotlightMessageID.identifier(line: line, time: time, buffer: buffer)
            let parsed = try #require(SpotlightResults.message(forItemIdentifier: identifier))
            #expect(parsed.buffer == buffer)
            #expect(parsed.line.id == line)
            #expect(abs(parsed.line.time.timeIntervalSince(time)) < 0.001)
            // Domains nest by periods; names never add any.
            let domain = SpotlightMessageID.domain(buffer: buffer)
            #expect(domain.split(separator: ".").count == 3)
            #expect(domain.hasPrefix(SpotlightMessageID.domain(network: network) + "."))
        }
        #expect(SpotlightResults.message(forItemIdentifier: "io.github.something") == nil)
        #expect(SpotlightResults.message(forItemIdentifier: "message/not/a/real") == nil)
    }

    // MARK: The queue

    @Test func queueIndexesOnlyWhileEnabled() async {
        let index = FakeMessageIndex()
        let queue = SpotlightMessageQueue(index: index)
        queue.didSave([record("#vela", "too early")], context: context)
        await queue.settled()
        #expect(index.calls.isEmpty)

        queue.enable(retentionDays: 0)
        queue.didSave([record("#vela", "hello")], context: context)
        await queue.settled()
        #expect(index.items.count == 1)

        queue.disable()
        queue.didSave([record("#vela", "too late")], context: context)
        await queue.settled()
        #expect(index.calls.last == .deleteDomains([SpotlightMessageID.rootDomain]))
        #expect(index.items.isEmpty)
    }

    @Test func queueHandsOverAtMost500AtATime() async {
        let index = FakeMessageIndex()
        let queue = SpotlightMessageQueue(index: index)
        queue.enable(retentionDays: 0)
        queue.didSave((0..<1_200).map { record("#vela", "line \($0)", minute: $0) }, context: context)
        await queue.settled()
        let sizes = index.calls.compactMap { if case .index(let ids) = $0 { ids.count } else { nil } }
        #expect(sizes == [500, 500, 200])
    }

    /// Removing a conversation removes its items, and a batch saved just
    /// before doesn't bring them back.
    @Test func removedConversationsStayOut() async {
        let index = FakeMessageIndex()
        let queue = SpotlightMessageQueue(index: index)
        queue.enable(retentionDays: 0)
        queue.didSave([record("#vela", "one"), record("marisol", "two", nick: "marisol")], context: context)
        await queue.settled()
        #expect(index.items.count == 2)

        queue.remove(buffer: BufferID(networkID: network, foldedName: "#vela"))
        queue.didSave([record("#vela", "late", minute: 1)], context: context)
        await queue.settled()
        #expect(index.items.values.map(\.text) == ["two"])
    }

    @Test func removedNetworksStayOut() async {
        let index = FakeMessageIndex()
        let queue = SpotlightMessageQueue(index: index)
        queue.enable(retentionDays: 0)
        queue.didSave([record("#vela", "one")], context: context)
        await queue.settled()
        queue.remove(network: network)
        queue.didSave([record("marisol", "late")], context: context)
        await queue.settled()
        #expect(index.items.isEmpty)
        #expect(index.calls.contains(.deleteDomains([SpotlightMessageID.domain(network: network)])))
    }

    @Test func deletedMessagesAreRemoved() async throws {
        let index = FakeMessageIndex()
        let queue = SpotlightMessageQueue(index: index)
        queue.enable(retentionDays: 0)
        let message = record("#vela", "oops")
        queue.didSave([message], context: context)
        queue.remove(line: message.id, time: message.time, buffer: message.bufferKey.bufferID)
        await queue.settled()
        #expect(index.items.isEmpty)
    }

    // MARK: The indexer

    /// A real (not demo) app on an in-memory store: one network that never
    /// connects, with #vela and a private conversation saved from before.
    private func launchedApp(save: Bool, indexMessages: Bool, messages: [MessageRecord] = []) async throws -> (AppModel, NetworkSession) {
        let app = try await unstartedApp(save: save, indexMessages: indexMessages, messages: messages)
        await app.ready()
        return (app, try #require(app.sessions.first))
    }

    /// The app as the indexer finds it at launch: networks not restored yet.
    private func unstartedApp(save: Bool, indexMessages: Bool, messages: [MessageRecord] = []) async throws -> AppModel {
        let folder = FileManager.default.temporaryDirectory.appending(path: "VelaSpotlight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = NetworkConfig(name: "Libera.Chat", host: "irc.example.invalid", nick: "doug", autoConnect: false)
        let database = try VelaDatabase.inMemory()
        for (name, kind) in [("#vela", "channel"), ("marisol", "query")] {
            try await database.upsertBuffer(BufferRecord(networkID: config.id, name: name, foldedName: name, kind: kind, lastReadAt: nil, sortOrder: 0))
        }
        try await database.append(messages.map { message in
            var message = message
            message.networkID = config.id
            return message
        })
        let networks = NetworkConfigStore(fileURL: folder.appending(path: "networks.json"))
        networks.upsert(config)
        let settings = SettingsStore(fileURL: folder.appending(path: "settings.json"), watchForChanges: false)
        settings.saveDelay = .seconds(60)
        settings[.historySave] = save
        settings[.intelligenceSpotlightMessages] = indexMessages
        return AppModel(settings: settings, networkStore: networks, database: database, notifier: SilentNotifier())
    }

    private func indexer(_ app: AppModel, record: InMemorySpotlightMessageIndexRecord = .init()) -> (SpotlightMessageIndexer, FakeMessageIndex) {
        let index = FakeMessageIndex()
        let indexer = SpotlightMessageIndexer(app: app, index: index, record: record)
        indexer.start()
        return (indexer, index)
    }

    /// Lets the settings' observation run.
    private func drain() async {
        for _ in 0..<50 { await Task.yield() }
    }

    @Test func offByDefault() async throws {
        #expect(SettingKey.intelligenceSpotlightMessages.defaultValue == false)
        let (app, _) = try await launchedApp(save: true, indexMessages: false)
        let (indexer, index) = indexer(app)
        await indexer.settled()
        #expect(app.savedMessagesSink == nil)
        #expect(index.calls.isEmpty)
    }

    @Test func needsSavedHistory() async throws {
        let (app, _) = try await launchedApp(save: false, indexMessages: true)
        let (indexer, index) = indexer(app)
        await indexer.settled()
        #expect(app.savedMessagesSink == nil)
        #expect(index.calls.isEmpty)
    }

    @Test func neverInDemoMode() async throws {
        let app = AppModel.demo()
        await app.ready()
        app.settings[.intelligenceSpotlightMessages] = true
        app.settings[.historySave] = true
        let (indexer, index) = indexer(app)
        await indexer.settled()
        #expect(app.savedMessagesObserver == nil)
        #expect(index.calls.isEmpty)
    }

    /// Turning it on indexes what's saved, once, then new messages as
    /// they're saved.
    @Test func turningOnIndexesSavedHistoryThenNewMessages() async throws {
        let (app, session) = try await launchedApp(save: true, indexMessages: false, messages: [
            record("#vela", "from yesterday", minute: 1),
            record("marisol", "a secret", minute: 2, nick: "marisol"),
            record("*server*", "MOTD", minute: 3, kind: "notice"),
        ])
        let record = InMemorySpotlightMessageIndexRecord()
        let (indexer, index) = indexer(app, record: record)
        app.settings[.intelligenceSpotlightMessages] = true
        await drain()
        await indexer.settled()
        #expect(Set(index.items.values.map(\.text)) == ["from yesterday", "a secret"])
        #expect(record.backfilled && record.mayHaveItems)
        #expect(app.savedMessagesSink != nil)

        // A new message, saved by the session's next batch.
        let vela = try #require(session.buffer(named: "#vela"))
        session.add(ChatLine(kind: .message, nick: "wren", text: "just now"), to: vela)
        await session.flushPendingRecordsNow()
        await indexer.settled()
        #expect(index.items.values.contains { $0.text == "just now" && $0.title == "wren in #vela" })
    }

    /// At launch the indexer starts before the networks are restored: saved
    /// history is indexed once they are.
    @Test func savedHistoryIsIndexedOnceVelaIsReady() async throws {
        let app = try await unstartedApp(save: true, indexMessages: true, messages: [record("#vela", "from before")])
        let (indexer, index) = indexer(app)
        #expect(app.sessions.isEmpty)
        await app.ready()
        await indexer.settled()
        #expect(index.items.values.map(\.text) == ["from before"])
    }

    @Test func turningOffRemovesEverything() async throws {
        let (app, _) = try await launchedApp(save: true, indexMessages: true, messages: [record("#vela", "hello")])
        let record = InMemorySpotlightMessageIndexRecord()
        let (indexer, index) = indexer(app, record: record)
        await indexer.settled()
        #expect(index.items.count == 1)

        app.settings[.intelligenceSpotlightMessages] = false
        await drain()
        await indexer.settled()
        #expect(index.items.isEmpty)
        #expect(app.savedMessagesSink == nil)
        #expect(!record.mayHaveItems && !record.backfilled)
    }

    @Test func turningOffSavedHistoryRemovesEverything() async throws {
        let (app, _) = try await launchedApp(save: true, indexMessages: true, messages: [record("#vela", "hello")])
        let (indexer, index) = indexer(app)
        await indexer.settled()
        app.settings[.historySave] = false
        await drain()
        await indexer.settled()
        #expect(index.items.isEmpty)
        #expect(index.calls.last == .deleteDomains([SpotlightMessageID.rootDomain]))
    }

    /// Turned off while Vela was closed (in settings.json): what's left
    /// from before is removed at launch.
    @Test func leftoversAreRemovedAtLaunch() async throws {
        let (app, _) = try await launchedApp(save: true, indexMessages: false)
        let record = InMemorySpotlightMessageIndexRecord()
        record.mayHaveItems = true
        record.backfilled = true
        let (indexer, index) = indexer(app, record: record)
        await indexer.settled()
        #expect(index.calls == [.deleteDomains([SpotlightMessageID.rootDomain])])
        #expect(!record.mayHaveItems && !record.backfilled)
    }

    @Test func deletingSavedHistoryRemovesEverything() async throws {
        let (app, _) = try await launchedApp(save: true, indexMessages: true, messages: [record("#vela", "hello")])
        let (indexer, index) = indexer(app)
        await indexer.settled()
        try await app.deleteSavedHistory()
        await indexer.settled()
        #expect(index.items.isEmpty)
    }

    @Test func removingAConversationRemovesItsMessages() async throws {
        let (app, session) = try await launchedApp(save: true, indexMessages: true, messages: [
            record("#vela", "channel talk"),
            record("marisol", "private talk", nick: "marisol"),
        ])
        let (indexer, index) = indexer(app)
        await indexer.settled()
        #expect(index.items.count == 2)
        app.close(try #require(session.buffer(named: "marisol")))
        await indexer.settled()
        #expect(index.items.values.map(\.text) == ["channel talk"])
    }

    @Test func removingANetworkRemovesItsMessages() async throws {
        let (app, session) = try await launchedApp(save: true, indexMessages: true, messages: [record("#vela", "hello")])
        let (indexer, index) = indexer(app)
        await indexer.settled()
        app.removeNetwork(id: session.id)
        await indexer.settled()
        #expect(index.items.isEmpty)
        #expect(index.calls.last == .deleteDomains([SpotlightMessageID.domain(network: session.id)]))
    }

    /// Indexing hands its work off: a busy channel's flush costs the main
    /// actor only the batch's buffer names.
    @Test func flushingABusyChannelStaysOffTheMainActor() async throws {
        let (app, session) = try await launchedApp(save: true, indexMessages: true)
        let (indexer, index) = indexer(app)
        await indexer.settled()
        let vela = try #require(session.buffer(named: "#vela"))
        for number in 0..<1_000 {
            session.add(ChatLine(kind: .message, nick: "bot", text: "line \(number)"), to: vela)
        }
        await session.flushPendingRecordsNow()
        await indexer.settled()
        #expect(index.items.count == 1_000)
    }
}

private extension BufferKey {
    var bufferID: BufferID { BufferID(networkID: networkID, foldedName: foldedName) }
}
