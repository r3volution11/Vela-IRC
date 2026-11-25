// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntents
import VelaStore

/// Stands in for Core Spotlight: records each call, can fail a number of
/// them, and can hold calls until released, to catch overlapping updates.
@MainActor
final class FakeSpotlightIndex: SpotlightIndex {
    enum Call: Equatable, CustomStringConvertible {
        /// Entity type, and each entity's title and subtitle.
        case index(String, [String])
        case delete(String, [String])
        case deleteAll(String)

        var description: String {
            switch self {
            case .index(let type, let items): "index \(type) \(items)"
            case .delete(let type, let ids): "delete \(type) \(ids)"
            case .deleteAll(let type): "deleteAll \(type)"
            }
        }
    }

    struct Failure: Error {}

    private(set) var calls: [Call] = []
    /// Calls to fail, from the next one on.
    var failuresLeft = 0
    /// While set, calls wait until ``release()``.
    var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var inFlight = 0
    private(set) var mostInFlight = 0

    var heldCount: Int { held.count }

    func release() {
        isHolding = false
        let waiting = held
        held.removeAll()
        for continuation in waiting { continuation.resume() }
    }

    func clear() {
        calls.removeAll()
    }

    func index<Entity: IndexedEntity>(_ entities: [Entity]) async throws {
        let items = entities.map { entity in
            let representation = entity.displayRepresentation
            let subtitle = representation.subtitle.map { String(localized: $0) } ?? ""
            return "\(String(localized: representation.title)) — \(subtitle)"
        }
        try await perform(.index(Self.name(Entity.self), items))
    }

    func delete<Entity: IndexedEntity>(_ identifiers: [Entity.ID], ofType type: Entity.Type) async throws {
        try await perform(.delete(Self.name(type), identifiers.map { "\($0)" }))
    }

    func deleteAll<Entity: IndexedEntity>(ofType type: Entity.Type) async throws {
        try await perform(.deleteAll(Self.name(type)))
    }

    private func perform(_ call: Call) async throws {
        inFlight += 1
        mostInFlight = max(mostInFlight, inFlight)
        defer { inFlight -= 1 }
        if isHolding {
            await withCheckedContinuation { held.append($0) }
        }
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw Failure()
        }
        calls.append(call)
    }

    static func name<Entity>(_ type: Entity.Type) -> String {
        String(describing: type)
    }

    /// The calls for one entity type.
    func calls(for type: String) -> [Call] {
        calls.filter { call in
            switch call {
            case .index(let name, _), .delete(let name, _), .deleteAll(let name): name == type
            }
        }
    }
}

/// Records how long the indexer asked to wait, and returns at once.
nonisolated final class InstantSleeper: Sendable {
    private let recorded = Recorded()

    var delays: [Duration] { recorded.values }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [recorded] delay in recorded.append(delay) }
    }

    private nonisolated final class Recorded: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Duration] = []

        var values: [Duration] { lock.withLock { stored } }

        func append(_ value: Duration) {
            lock.withLock { stored.append(value) }
        }
    }
}

@MainActor
@Suite("Spotlight indexer", .serialized)
struct SpotlightIndexerTests {
    private let channel = FakeSpotlightIndex.name(ChannelEntity.self)
    private let person = FakeSpotlightIndex.name(PersonEntity.self)

    private struct Setup {
        let app: AppModel
        let index: FakeSpotlightIndex
        let sleeper: InstantSleeper
        let indexer: SpotlightChannelIndexer
        let refreshes: Counter
    }

    @MainActor
    final class Counter {
        var value = 0
    }

    /// The demo networks, indexed into a fake, with instant waits.
    private func start(failing failures: Int = 0, holding: Bool = false, configure: (AppModel) -> Void = { _ in }) async -> Setup {
        let app = AppModel.demo()
        await app.ready()
        configure(app)
        let index = FakeSpotlightIndex()
        index.failuresLeft = failures
        index.isHolding = holding
        let sleeper = InstantSleeper()
        let refreshes = Counter()
        let indexer = SpotlightChannelIndexer(app: app, index: index, refreshAppShortcuts: { refreshes.value += 1 }, sleep: sleeper.sleep)
        indexer.start()
        return Setup(app: app, index: index, sleeper: sleeper, indexer: indexer, refreshes: refreshes)
    }

    /// Lets the indexer's tasks run until `condition` holds.
    private func settle(_ condition: () -> Bool) async {
        var tries = 0
        while !condition(), tries < 2000 {
            tries += 1
            await Task.yield()
        }
    }

    /// Lets everything queued run (for checking that nothing happens).
    private func drain() async {
        for _ in 0..<200 { await Task.yield() }
    }

    private func siriTypes() -> [String] {
        guard #available(macOS 27, *) else { return [] }
        return [FakeSpotlightIndex.name(ConversationEntity.self), FakeSpotlightIndex.name(MessagePersonEntity.self)]
    }

    private func libera(_ app: AppModel) throws -> NetworkSession {
        try #require(app.sessions.first { $0.displayName == "Libera.Chat" })
    }

    // MARK: First pass

    @Test func firstPassReplacesWhatAnEarlierRunLeft() async throws {
        let setup = await start()
        let all = ChannelEntity.all(in: setup.app)
        await settle { setup.index.calls(for: person).count == 2 }
        // Each kind is emptied, then filled, so nothing stale survives a
        // relaunch. Spotlight shows channels as channels and private
        // conversations as people; Siri knows them all by name.
        let expected = [channel: all.filter { !$0.isPrivate }.count, person: all.filter(\.isPrivate).count]
            .merging(siriTypes().map { ($0, all.count) }) { first, _ in first }
        for (type, count) in expected {
            let calls = setup.index.calls(for: type)
            #expect(calls.count == 2)
            #expect(calls.first == .deleteAll(type))
            guard case .index(_, let items) = calls.last else {
                Issue.record("\(type) wasn't indexed")
                continue
            }
            #expect(items.count == count, "\(type)")
        }
        #expect(setup.sleeper.delays == [SpotlightChannelIndexer.debounce])
    }

    /// A private conversation is a person in Spotlight, and stays one
    /// after you close it, until Vela quits.
    @Test func peopleYouTalkTo() async throws {
        let setup = await start()
        await settle { setup.index.calls(for: person).count == 2 }
        guard case .index(_, let people) = setup.index.calls(for: person).last else {
            Issue.record("People weren't indexed")
            return
        }
        #expect(people == ["marisol — Private conversation on Libera.Chat"])
        guard case .index(_, let channels) = setup.index.calls(for: channel).last else {
            Issue.record("Channels weren't indexed")
            return
        }
        #expect(!channels.contains { $0.hasPrefix("marisol") })
        setup.index.clear()

        let session = try libera(setup.app)
        setup.app.close(try #require(session.buffer(named: "marisol")))
        await settle { !setup.index.calls(for: person).isEmpty }
        await drain()
        // Still there: it's in Recently Closed, so choosing it reopens it.
        #expect(PersonEntity.all(in: setup.app).map(\.nick) == ["marisol"])
    }

    // MARK: The setting

    @Test func turningOffRemovesOnlySpotlightResults() async throws {
        let setup = await start()
        await settle { setup.index.calls(for: channel).count == 2 }
        setup.index.clear()

        setup.app.settings[.intelligenceSpotlightChannels] = false
        await settle { !setup.index.calls.isEmpty }
        await drain()
        // Siri's lookup entries stay: only the channels and people Spotlight shows go.
        #expect(setup.index.calls == [.deleteAll(channel), .deleteAll(person)])
    }

    @Test func turningOnDeletesThenIndexes() async throws {
        let setup = await start { app in app.settings[.intelligenceSpotlightChannels] = false }
        await settle { setup.index.calls(for: person).count == 1 }
        #expect(setup.index.calls(for: channel) == [.deleteAll(channel)])
        // Siri's entries are indexed while the setting is off.
        for type in siriTypes() {
            #expect(setup.index.calls(for: type).count == 2)
        }
        setup.index.clear()

        setup.app.settings[.intelligenceSpotlightChannels] = true
        await settle { setup.index.calls.count == 4 }
        await drain()
        let calls = setup.index.calls(for: channel)
        #expect(calls.count == 2)
        #expect(calls.first == .deleteAll(channel))
        if case .index(let type, let items) = calls.last {
            #expect(type == channel)
            #expect(items.count == ChannelEntity.all(in: setup.app).filter { !$0.isPrivate }.count)
        } else {
            Issue.record("Channels weren't indexed: \(calls)")
        }
        #expect(setup.index.calls(for: person).count == 2)
    }

    @Test func externalSettingsEditsReachTheIndex() async throws {
        let setup = await start()
        await settle { setup.index.calls(for: channel).count == 2 }
        setup.index.clear()

        // Turned off in settings.json, in another editor.
        let settings = setup.app.settings
        try Data("{\n  \"intelligence.spotlightChannels\": false\n}\n".utf8).write(to: settings.fileURL)
        settings.reload()
        #expect(SpotlightChannelIndexer.snapshot(of: setup.app).isEnabled == false)
        await settle { !setup.index.calls.isEmpty }
        await drain()
        #expect(setup.index.calls == [.deleteAll(channel), .deleteAll(person)])
    }

    // MARK: Channel changes

    @Test func closedChannelIsRemovedAsStale() async throws {
        let setup = await start()
        await settle { setup.index.calls(for: channel).count == 2 }
        setup.index.clear()

        let session = try libera(setup.app)
        let swift = try #require(session.buffer(named: "#swift"))
        let id = swift.id.description
        setup.app.close(swift)
        await settle { setup.index.calls(for: channel).count == 2 }
        await drain()
        for type in [channel] + siriTypes() {
            let calls = setup.index.calls(for: type)
            #expect(calls.first == .delete(type, [id]))
            if case .index(_, let items) = calls.last {
                #expect(!items.contains { $0.hasPrefix("#swift —") })
            } else {
                Issue.record("\(type) wasn't re-indexed: \(calls)")
            }
        }
    }

    @Test func networkRenameReindexes() async throws {
        let setup = await start()
        await settle { setup.index.calls(for: channel).count == 2 }
        setup.index.clear()

        let session = try libera(setup.app)
        var config = session.config
        config.name = "Libera"
        setup.app.updateNetwork(config, secrets: nil)
        await settle { setup.index.calls(for: channel).count == 1 }
        await drain()
        for type in [channel] + siriTypes() {
            let calls = setup.index.calls(for: type)
            // The same channels, so nothing to delete; just their new network.
            #expect(calls.count == 1)
            if case .index(_, let items) = calls.first {
                #expect(items.contains("#vela — Libera"))
                #expect(!items.contains { $0.hasSuffix("— Libera.Chat") })
            } else {
                Issue.record("\(type) wasn't re-indexed: \(calls)")
            }
        }
    }

    // MARK: Robustness

    @Test func failedUpdateIsRetriedWithBackoff() async throws {
        let setup = await start(failing: 1)
        await settle { setup.index.calls(for: channel).count == 2 }
        // The first try failed; the retry waited and indexed everything.
        #expect(setup.sleeper.delays == [SpotlightChannelIndexer.debounce, SpotlightChannelIndexer.firstRetryDelay])
        #expect(setup.index.calls(for: channel).first == .deleteAll(channel))

        // Two failures in a row wait twice as long the second time, then
        // the whole index is rebuilt.
        setup.index.clear()
        setup.index.failuresLeft = 2
        setup.app.close(try #require(try libera(setup.app).buffer(named: "#swift")))
        await settle { setup.index.calls(for: channel).count == 2 }
        #expect(Array(setup.sleeper.delays.suffix(3)) == [
            SpotlightChannelIndexer.debounce,
            SpotlightChannelIndexer.retryDelay(afterFailures: 1),
            SpotlightChannelIndexer.retryDelay(afterFailures: 2),
        ])
        #expect(setup.index.calls(for: channel).first == .deleteAll(channel))
    }

    @Test func retryDelaysDoubleUpToTheMaximum() {
        #expect(SpotlightChannelIndexer.retryDelay(afterFailures: 1) == .seconds(5))
        #expect(SpotlightChannelIndexer.retryDelay(afterFailures: 2) == .seconds(10))
        #expect(SpotlightChannelIndexer.retryDelay(afterFailures: 3) == .seconds(20))
        #expect(SpotlightChannelIndexer.retryDelay(afterFailures: 7) == SpotlightChannelIndexer.maximumRetryDelay)
        #expect(SpotlightChannelIndexer.retryDelay(afterFailures: 50) == SpotlightChannelIndexer.maximumRetryDelay)
    }

    @Test func updatesNeverOverlap() async throws {
        let setup = await start(holding: true)
        // The first update is stuck in its first call.
        await settle { setup.index.heldCount == 1 }
        #expect(setup.index.heldCount == 1)

        // A change meanwhile waits for it rather than starting alongside.
        let swift = try #require(try libera(setup.app).buffer(named: "#swift"))
        let id = swift.id.description
        setup.app.close(swift)
        await drain()
        #expect(setup.index.heldCount == 1)

        setup.index.release()
        await settle { setup.index.calls(for: channel).contains(.delete(channel, [id])) }
        #expect(setup.index.mostInFlight == 1)
        // Then the change was indexed, after the first update.
        #expect(setup.index.calls(for: channel).contains(.delete(channel, [id])))
    }

    // MARK: App Shortcuts

    @Test func appShortcutsRefreshOncePerChannelListChange() async throws {
        let setup = await start()
        await settle { setup.refreshes.value == 1 }
        await settle { setup.index.calls(for: channel).count == 2 }
        #expect(setup.refreshes.value == 1)

        // Unread counts and the setting aren't the channel list.
        let session = try libera(setup.app)
        let vela = try #require(session.buffer(named: "#vela"))
        vela.unreadCount += 3
        vela.highlightCount += 1
        setup.app.settings[.intelligenceSpotlightChannels] = false
        await settle { setup.index.calls(for: channel).count == 3 }
        await drain()
        #expect(setup.refreshes.value == 1)

        // A channel closing is.
        setup.app.close(try #require(session.buffer(named: "#swift")))
        await settle { setup.refreshes.value == 2 }
        await drain()
        #expect(setup.refreshes.value == 2)
    }
}
