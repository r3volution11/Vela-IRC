// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreSpotlight
import Foundation
import Observation
import os
import UniformTypeIdentifiers
import VelaCore
import VelaStore

// MARK: - Items

/// A message as Spotlight indexes it: plain values, made off the main
/// actor, turned into a `CSSearchableItem` only by the system index.
nonisolated struct SpotlightMessageItem: Equatable, Sendable {
    var identifier: String
    var domain: String
    /// "marisol in #vela", or "marisol" in a private conversation.
    var title: String
    var text: String
    var author: String?
    var time: Date
    /// "#vela · Libera.Chat"
    var container: String
    var expiration: Date
}

/// How message items are named in Spotlight. Domains nest with periods, so
/// removing `vela-messages.<network>` removes every item of the network's
/// buffers, and `vela-messages` every message item (never the channel and
/// people items, which have none of these domains). Folded names go in as
/// hex, since a channel name may have periods.
nonisolated enum SpotlightMessageID {
    static let rootDomain = "vela-messages"
    static let prefix = "message/"

    static func domain(network: UUID) -> String {
        "\(rootDomain).\(network.uuidString)"
    }

    static func domain(buffer: BufferID) -> String {
        domain(network: buffer.networkID) + "." + buffer.foldedName.utf8.map { String(format: "%02x", $0) }.joined()
    }

    /// "message/<network>/<line>/<milliseconds>/<folded-name>": everything
    /// opening the message needs, so a result opens without a lookup.
    static func identifier(line: UUID, time: Date, buffer: BufferID) -> String {
        let milliseconds = Int64((time.timeIntervalSince1970 * 1000).rounded())
        return "\(prefix)\(buffer.networkID.uuidString)/\(line.uuidString)/\(milliseconds)/\(buffer.foldedName)"
    }

    /// The conversation and message an identifier names.
    static func parse(_ identifier: String) -> (buffer: BufferID, line: LineReference)? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let parts = identifier.dropFirst(prefix.count).split(separator: "/", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, let network = UUID(uuidString: String(parts[0])), let line = UUID(uuidString: String(parts[1])),
              let milliseconds = Int64(parts[2]), !parts[3].isEmpty else { return nil }
        let time = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        return (BufferID(networkID: network, foldedName: String(parts[3])), LineReference(id: line, time: time))
    }
}

nonisolated extension SpotlightMessageItem {
    /// The most messages one saved batch adds (the newest of it): a bouncer
    /// replaying thousands of lines at once indexes the latest of them.
    static let maximumPerBatch = 2_000
    /// Longer messages are cut to this many characters (IRC lines are
    /// shorter, but several joined by a bouncer needn't be).
    static let maximumTextLength = 1_000

    /// The items for `records`: messages, actions and notices in channels
    /// and private conversations (not network consoles), not deleted, at
    /// most ``maximumPerBatch`` of the newest. They expire when saved
    /// history would (`history.retentionDays`), or never.
    static func items(for records: [MessageRecord], context: SavedMessagesContext, retentionDays: Int) -> [SpotlightMessageItem] {
        var items: [SpotlightMessageItem] = []
        items.reserveCapacity(min(records.count, maximumPerBatch))
        for record in records.suffix(maximumPerBatch * 2) {
            guard !record.isRedacted, ["message", "action", "notice"].contains(record.kind),
                  let buffer = context.buffers[record.bufferName], buffer.kind != .server
            else { continue }
            let body = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            let nick = record.nick ?? ""
            var text = record.kind == "action" ? "\(nick) \(body)" : body
            if text.count > maximumTextLength { text = String(text.prefix(maximumTextLength)) + "…" }
            let bufferID = BufferID(networkID: context.networkID, foldedName: record.bufferName)
            let title = buffer.kind == .query || nick.isEmpty ? (nick.isEmpty ? buffer.name : nick) : "\(nick) in \(buffer.name)"
            items.append(SpotlightMessageItem(
                identifier: SpotlightMessageID.identifier(line: record.id, time: record.time, buffer: bufferID),
                domain: SpotlightMessageID.domain(buffer: bufferID),
                title: title,
                text: text,
                author: nick.isEmpty ? nil : nick,
                time: record.time,
                container: "\(buffer.name) · \(context.networkName)",
                expiration: retentionDays > 0 ? record.time.addingTimeInterval(Double(retentionDays) * 86_400) : .distantFuture
            ))
        }
        return Array(items.suffix(maximumPerBatch))
    }
}

// MARK: - The index

/// What ``SpotlightMessageIndexer`` asks of Core Spotlight, so tests can
/// stand in for it.
protocol MessageSpotlightIndex: Sendable {
    func index(_ items: [SpotlightMessageItem]) async throws
    func delete(identifiers: [String]) async throws
    func delete(domains: [String]) async throws
}

/// The app's own Core Spotlight index.
nonisolated struct SystemMessageSpotlightIndex: MessageSpotlightIndex {
    func index(_ items: [SpotlightMessageItem]) async throws {
        let searchable = items.map { item in
            let attributes = CSSearchableItemAttributeSet(contentType: .message)
            attributes.title = item.title
            attributes.displayName = item.title
            attributes.contentDescription = item.text
            attributes.textContent = item.text
            attributes.authorNames = item.author.map { [$0] }
            attributes.contentCreationDate = item.time
            attributes.containerDisplayName = item.container
            let searchable = CSSearchableItem(uniqueIdentifier: item.identifier, domainIdentifier: item.domain, attributeSet: attributes)
            searchable.expirationDate = item.expiration
            return searchable
        }
        try await CSSearchableIndex.default().indexSearchableItems(searchable)
    }

    func delete(identifiers: [String]) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers)
    }

    func delete(domains: [String]) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: domains)
    }
}

/// What's remembered between launches: whether Spotlight may hold message
/// items (so turning the setting off while Vela was closed still removes
/// them), and whether the saved history has been indexed once.
@MainActor
protocol SpotlightMessageIndexRecord: AnyObject {
    var mayHaveItems: Bool { get set }
    var backfilled: Bool { get set }
}

final class UserDefaultsSpotlightMessageIndexRecord: SpotlightMessageIndexRecord {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var mayHaveItems: Bool {
        get { defaults.bool(forKey: "Vela.spotlightMessages.mayHaveItems") }
        set { defaults.set(newValue, forKey: "Vela.spotlightMessages.mayHaveItems") }
    }

    var backfilled: Bool {
        get { defaults.bool(forKey: "Vela.spotlightMessages.backfilled") }
        set { defaults.set(newValue, forKey: "Vela.spotlightMessages.backfilled") }
    }
}

final class InMemorySpotlightMessageIndexRecord: SpotlightMessageIndexRecord {
    var mayHaveItems = false
    var backfilled = false
}

// MARK: - The queue

/// Takes saved messages from sessions (off the main actor) and hands them
/// to Spotlight one operation at a time, in order, on a background task.
/// Nothing here runs on the main actor: a session's flush only hands over
/// the array it just wrote.
nonisolated final class SpotlightMessageQueue: SavedMessagesSink {
    enum Operation: Sendable {
        case add([MessageRecord], SavedMessagesContext, generation: Int)
        case deleteAll
        case deleteDomains([String])
        case deleteIdentifiers([String])
        /// Resumes once everything before it is done (tests, the backfill's pace).
        case barrier(CheckedContinuation<Void, Never>)
    }

    struct State: Sendable {
        var isEnabled = false
        /// Bumped when items are removed wholesale: additions queued
        /// before then are dropped.
        var generation = 0
        var retentionDays = 0
        /// Conversations and networks removed lately, and when: a batch
        /// written just before one was removed mustn't put it back.
        var removedBuffers: [BufferID: ContinuousClock.Instant] = [:]
        var removedNetworks: [UUID: ContinuousClock.Instant] = [:]
    }

    /// How long a removed conversation's late messages are kept out.
    static let removalGrace: Duration = .seconds(30)
    /// The most items handed to Core Spotlight at once.
    static let chunkSize = 500

    let state = OSAllocatedUnfairLock(initialState: State())
    private let continuation: AsyncStream<Operation>.Continuation
    private let consumer: Task<Void, Never>
    /// Calls to the index that failed, for tests.
    let failures = OSAllocatedUnfairLock(initialState: 0)

    init(index: any MessageSpotlightIndex) {
        let (stream, continuation) = AsyncStream<Operation>.makeStream()
        self.continuation = continuation
        let state = self.state
        let failures = self.failures
        consumer = Task.detached(priority: .utility) {
            for await operation in stream {
                do {
                    try await Self.perform(operation, index: index, state: state)
                } catch {
                    failures.withLock { $0 += 1 }
                }
            }
        }
    }

    deinit {
        continuation.finish()
        consumer.cancel()
    }

    // MARK: SavedMessagesSink

    func didSave(_ messages: [MessageRecord], context: SavedMessagesContext) {
        let generation: Int? = state.withLock { $0.isEnabled ? $0.generation : nil }
        guard let generation else { return }
        continuation.yield(.add(messages, context, generation: generation))
    }

    // MARK: Control (from the indexer)

    func enable(retentionDays: Int) {
        state.withLock {
            $0.isEnabled = true
            $0.retentionDays = retentionDays
        }
    }

    func setRetentionDays(_ days: Int) {
        state.withLock { $0.retentionDays = days }
    }

    /// Stops taking messages and removes every message item.
    func disable() {
        state.withLock {
            $0.isEnabled = false
            $0.generation += 1
        }
        continuation.yield(.deleteAll)
    }

    /// Removes every message item, and keeps taking new ones.
    func removeAll() {
        state.withLock { $0.generation += 1 }
        continuation.yield(.deleteAll)
    }

    func remove(buffer: BufferID) {
        state.withLock { $0.removedBuffers[buffer] = .now }
        continuation.yield(.deleteDomains([SpotlightMessageID.domain(buffer: buffer)]))
    }

    func remove(network: UUID) {
        state.withLock { $0.removedNetworks[network] = .now }
        continuation.yield(.deleteDomains([SpotlightMessageID.domain(network: network)]))
    }

    func remove(line: UUID, time: Date, buffer: BufferID) {
        continuation.yield(.deleteIdentifiers([SpotlightMessageID.identifier(line: line, time: time, buffer: buffer)]))
    }

    /// Adds records read from saved history (the first indexing), as of
    /// `generation`.
    func backfill(_ records: [MessageRecord], context: SavedMessagesContext, generation: Int) {
        continuation.yield(.add(records, context, generation: generation))
    }

    /// Returns once everything queued so far has been handed to Spotlight.
    func settled() async {
        await withCheckedContinuation { continuation.yield(.barrier($0)) }
    }

    // MARK: Work

    private static func perform(_ operation: Operation, index: any MessageSpotlightIndex, state: OSAllocatedUnfairLock<State>) async throws {
        switch operation {
        case .add(let records, let context, let generation):
            let now = ContinuousClock.now
            let (current, retention, skip) = state.withLock { state -> (Bool, Int, Set<String>) in
                state.removedBuffers = state.removedBuffers.filter { now - $0.value < removalGrace }
                state.removedNetworks = state.removedNetworks.filter { now - $0.value < removalGrace }
                guard state.isEnabled, state.generation == generation, state.removedNetworks[context.networkID] == nil else {
                    return (false, 0, [])
                }
                let skipped = state.removedBuffers.keys.filter { $0.networkID == context.networkID }.map(\.foldedName)
                return (true, state.retentionDays, Set(skipped))
            }
            guard current else { return }
            var context = context
            for name in skip { context.buffers[name] = nil }
            let items = SpotlightMessageItem.items(for: records, context: context, retentionDays: retention)
            var start = items.startIndex
            while start < items.endIndex {
                let end = min(start + chunkSize, items.endIndex)
                // Dropped meanwhile (turned off, history deleted): stop.
                guard state.withLock({ $0.isEnabled && $0.generation == generation }) else { return }
                try await index.index(Array(items[start..<end]))
                start = end
            }
        case .deleteAll:
            try await index.delete(domains: [SpotlightMessageID.rootDomain])
        case .deleteDomains(let domains):
            try await index.delete(domains: domains)
        case .deleteIdentifiers(let identifiers):
            try await index.delete(identifiers: identifiers)
        case .barrier(let continuation):
            continuation.resume()
        }
    }
}

// MARK: - The indexer

/// Spotlight's index of your saved messages (`intelligence.spotlightMessages`,
/// off by default). It works only while message history is saved
/// (`history.save`) and never in demo mode.
///
/// - **Turning it on** indexes the newest ``backfillLimit`` saved messages of
///   each network once, in the background, a page at a time; after that,
///   each batch of messages a session saves is indexed as it's written.
/// - **Turning it off**, or turning off `history.save`, removes every
///   message item. So do deleting saved history; removing a channel,
///   closing a conversation or removing a network removes theirs; a
///   message its sender deletes is removed too.
/// - **Cost:** nothing on the main actor per message. A session hands over
///   each batch it saves (every 400 ms at most) after writing it; items are
///   made and indexed on a background task, 500 at a time.
@MainActor
final class SpotlightMessageIndexer: SavedMessagesObserver {
    /// How many of each network's newest saved messages turning it on indexes.
    static let backfillLimit = 5_000
    /// The pause between networks while indexing saved history.
    static let backfillPause: Duration = .milliseconds(250)

    private let app: AppModel
    private let queue: SpotlightMessageQueue
    private let record: any SpotlightMessageIndexRecord
    private var isEnabled = false
    private var retentionDays = 0
    private var started = false
    private var backfill: Task<Void, Never>?

    init(app: AppModel, index: (any MessageSpotlightIndex)? = nil, record: (any SpotlightMessageIndexRecord)? = nil) {
        self.app = app
        self.queue = SpotlightMessageQueue(index: index ?? SystemMessageSpotlightIndex())
        self.record = record ?? UserDefaultsSpotlightMessageIndexRecord()
    }

    /// Whether messages are indexed now: the setting, with history saved,
    /// outside demo mode.
    static func isEnabled(_ app: AppModel) -> Bool {
        !app.isDemo && app.database != nil && app.settings[.historySave] && app.settings[.intelligenceSpotlightMessages]
    }

    func start() {
        guard !started, !app.isDemo else { return }
        started = true
        app.savedMessagesObserver = self
        // Off, but items may be left from before (turned off in
        // settings.json while Vela was closed, say): remove them.
        if !Self.isEnabled(app), record.mayHaveItems {
            queue.disable()
            record.mayHaveItems = false
            record.backfilled = false
        }
        apply()
        observe()
    }

    /// Waits until everything queued has reached the index (tests).
    func settled() async {
        await backfill?.value
        await queue.settled()
    }

    private func observe() {
        withObservationTracking {
            _ = app.settings[.intelligenceSpotlightMessages]
            _ = app.settings[.historySave]
            _ = app.settings[.historyRetentionDays]
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.apply()
                self?.observe()
            }
        }
    }

    private func apply() {
        let enabled = Self.isEnabled(app)
        let retention = max(0, app.settings[.historyRetentionDays])
        defer {
            isEnabled = enabled
            retentionDays = retention
        }
        if enabled, !isEnabled {
            queue.enable(retentionDays: retention)
            record.mayHaveItems = true
            if !record.backfilled { startBackfill() }
        } else if !enabled, isEnabled {
            backfill?.cancel()
            backfill = nil
            queue.disable()
            record.mayHaveItems = false
            record.backfilled = false
        } else if enabled, retention != retentionDays {
            queue.setRetentionDays(retention)
            // Kept for less time now: start over, so what's indexed expires
            // with the history it came from.
            if retention > 0, retentionDays == 0 || retention < retentionDays {
                backfill?.cancel()
                queue.removeAll()
                startBackfill()
            }
        }
    }

    /// Indexes each network's newest saved messages, off the main actor,
    /// once Vela has restored its networks and conversations (at launch,
    /// the indexer starts before they are).
    private func startBackfill() {
        guard let database = app.database else { return }
        let queue = self.queue
        backfill = Task { [weak self] in
            while let self, !self.app.isReady {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
            guard let self, !Task.isCancelled else { return }
            let networks = Self.contexts(of: self.app)
            let generation = queue.state.withLock { $0.generation }
            let retention = max(0, self.app.settings[.historyRetentionDays])
            let cutoff = retention > 0 ? Date().addingTimeInterval(-Double(retention) * 86_400) : .distantPast
            // Off the main actor. It stops when what it's indexing for is
            // dropped (turned off, history deleted): the queue's generation moves on.
            let current: @Sendable () -> Bool = { queue.state.withLock { $0.generation == generation && $0.isEnabled } }
            let finished = await Task.detached(priority: .background) {
                for network in networks {
                    guard current() else { return false }
                    let records = (try? await database.conversation(networkID: network.networkID, after: cutoff, limit: Self.backfillLimit)) ?? []
                    guard current() else { return false }
                    queue.backfill(records, context: network, generation: generation)
                    // One network at a time: Spotlight takes the last before the next is read.
                    await queue.settled()
                    try? await Task.sleep(for: Self.backfillPause)
                }
                return true
            }.value
            if finished, !Task.isCancelled { self.record.backfilled = true }
        }
    }

    /// How each network and its open conversations are named. Saved
    /// messages of conversations no longer open aren't indexed.
    private static func contexts(of app: AppModel) -> [SavedMessagesContext] {
        app.automationSessions.map { session in
            SavedMessagesContext(
                networkID: session.id,
                networkName: session.displayName,
                buffers: Dictionary(
                    session.buffers.filter { $0.kind != .server }.map { ($0.id.foldedName, SavedMessagesContext.Buffer(name: $0.name, kind: $0.kind)) },
                    uniquingKeysWith: { first, _ in first }
                )
            )
        }
    }

    // MARK: SavedMessagesObserver

    var sink: (any SavedMessagesSink)? {
        isEnabled ? queue : nil
    }

    func savedHistoryDeleted() {
        guard isEnabled else { return }
        backfill?.cancel()
        queue.removeAll()
    }

    func conversationRemoved(_ bufferID: BufferID) {
        guard isEnabled else { return }
        queue.remove(buffer: bufferID)
    }

    func networkRemoved(_ networkID: UUID) {
        guard isEnabled else { return }
        queue.remove(network: networkID)
    }

    func messageRedacted(_ lineID: UUID, time: Date, in bufferID: BufferID) {
        guard isEnabled else { return }
        queue.remove(line: lineID, time: time, buffer: bufferID)
    }
}

// MARK: - Opening results

/// What a Spotlight result Vela indexed stands for, when you choose it.
public enum SpotlightResults {
    /// The conversation and message of a message result (its
    /// `CSSearchableItemActivityIdentifier`), or nil if it isn't one.
    public nonisolated static func message(forItemIdentifier identifier: String) -> (buffer: BufferID, line: LineReference)? {
        SpotlightMessageID.parse(identifier)
    }
}
