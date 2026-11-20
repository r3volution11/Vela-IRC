// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import CoreSpotlight
import Foundation
import Observation
import VelaCore
import VelaStore

/// What ``SpotlightChannelIndexer`` asks of Core Spotlight, so tests can
/// stand in for the system index.
@MainActor
protocol SpotlightIndex: AnyObject {
    func index<Entity: IndexedEntity>(_ entities: [Entity]) async throws
    func delete<Entity: IndexedEntity>(_ identifiers: [Entity.ID], ofType type: Entity.Type) async throws
    func deleteAll<Entity: IndexedEntity>(ofType type: Entity.Type) async throws
}

/// The app's own Core Spotlight index.
final class SystemSpotlightIndex: SpotlightIndex {
    nonisolated func index<Entity: IndexedEntity>(_ entities: [Entity]) async throws {
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    nonisolated func delete<Entity: IndexedEntity>(_ identifiers: [Entity.ID], ofType type: Entity.Type) async throws {
        try await CSSearchableIndex.default().deleteAppEntities(identifiedBy: identifiers, ofType: type)
    }

    nonisolated func deleteAll<Entity: IndexedEntity>(ofType type: Entity.Type) async throws {
        try await CSSearchableIndex.default().deleteAppEntities(ofType: type)
    }
}

/// Keeps Spotlight's index of channel and conversation names in step with
/// the sidebar. Names and networks only, never messages.
///
/// Two kinds of entries are indexed:
/// - **Spotlight results** (``ChannelEntity``): only while
///   `intelligence.spotlightChannels` is on. Turning it off removes them.
/// - **Siri's name lookup** (macOS 27: ``ConversationEntity`` and
///   ``MessagePersonEntity``): always, so Siri can find "#vela" or a nick by
///   name. They're marked `hideInSpotlight`, which keeps them out of
///   Spotlight's results.
///
/// Changes are batched: a burst of joins is indexed once, a moment later.
/// One update runs at a time; a change made during one is indexed right
/// after it. A failed update is tried again from scratch, waiting longer
/// after each failure (``retryDelay(afterFailures:)``).
@MainActor
final class SpotlightChannelIndexer {
    /// What the index reflects: the setting, and each channel's id, name
    /// and network (not unread counts, which change all the time).
    struct Snapshot: Equatable {
        var isEnabled: Bool
        var channels: [String]
    }

    static let debounce: Duration = .seconds(2)
    /// The wait before retrying a failed update, doubled after each
    /// further failure up to ``maximumRetryDelay``.
    static let firstRetryDelay: Duration = .seconds(5)
    static let maximumRetryDelay: Duration = .seconds(300)

    private let app: AppModel
    private let index: any SpotlightIndex
    private let refreshAppShortcuts: (@MainActor () -> Void)?
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The wait before the next update: the debounce, or a retry's delay.
    private var pending: Task<Void, Never>?
    /// The update in progress, if any.
    private var running: Task<Void, Never>?
    /// A change arrived while an update was running: run another after it.
    private var needsAnotherPass = false
    /// What the index holds, as of the last update that went through. Nil
    /// at first and after a failure: the next update starts from scratch.
    private var applied: Snapshot?
    private var spotlightIDs: Set<String> = []
    private var siriIDs: Set<String> = []
    /// The channel list App Shortcuts' parameters were last refreshed for.
    private var shortcutChannels: [String]?
    private var failures = 0

    /// - Parameters:
    ///   - index: The Spotlight index; tests pass their own.
    ///   - refreshAppShortcuts: Called once for each change to the channel
    ///     list (not for unread counts or the setting).
    ///   - sleep: How the indexer waits (tests make it instant).
    init(
        app: AppModel,
        index: (any SpotlightIndex)? = nil,
        refreshAppShortcuts: (@MainActor () -> Void)?,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.app = app
        self.index = index ?? SystemSpotlightIndex()
        self.refreshAppShortcuts = refreshAppShortcuts
        self.sleep = sleep
    }

    func start() {
        observe()
        schedule(after: Self.debounce)
    }

    static func snapshot(of app: AppModel) -> Snapshot {
        Snapshot(
            isEnabled: app.settings[.intelligenceSpotlightChannels],
            channels: app.conversationBuffers.map { buffer in
                let network = app.session(for: buffer.id.networkID)?.displayName ?? ""
                return "\(buffer.id.description)\t\(buffer.name)\t\(network)"
            }
        )
    }

    /// How long to wait after the `failures`th failure in a row.
    static func retryDelay(afterFailures failures: Int) -> Duration {
        var delay = firstRetryDelay
        for _ in 1..<max(1, failures) {
            delay *= 2
            if delay >= maximumRetryDelay { return maximumRetryDelay }
        }
        return min(delay, maximumRetryDelay)
    }

    private func observe() {
        withObservationTracking {
            _ = Self.snapshot(of: app)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.schedule(after: Self.debounce)
                self?.observe()
            }
        }
    }

    /// Updates after `delay`, replacing a wait already scheduled. Only the
    /// wait is cancelled, never an update in progress.
    private func schedule(after delay: Duration) {
        pending?.cancel()
        pending = Task { [weak self, sleep] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.updateNow()
        }
    }

    /// Starts an update, or asks the one running for another pass.
    private func updateNow() {
        guard running == nil else {
            needsAnotherPass = true
            return
        }
        running = Task { [weak self] in
            await self?.runUpdates()
        }
    }

    private func runUpdates() async {
        repeat {
            needsAnotherPass = false
            await update()
        } while needsAnotherPass
        running = nil
    }

    private func update() async {
        let snapshot = Self.snapshot(of: app)
        if snapshot != applied {
            let previous = applied
            do {
                try await apply(snapshot, over: previous)
                applied = snapshot
                failures = 0
            } catch {
                applied = nil
                failures += 1
                // A change already waiting retries soon enough.
                if !needsAnotherPass { schedule(after: Self.retryDelay(afterFailures: failures)) }
            }
        }
        if shortcutChannels != snapshot.channels {
            shortcutChannels = snapshot.channels
            refreshAppShortcuts?()
        }
    }

    /// Brings the index from `previous` (nil: unknown) to `snapshot`. The
    /// entities are read before the first wait, so they match `snapshot`.
    private func apply(_ snapshot: Snapshot, over previous: Snapshot?) async throws {
        let channels = ChannelEntity.all(in: app)
        let ids = Set(channels.map(\.id))

        // Siri's lookup by name, whatever the setting. On a first pass
        // (or after a failure) everything an earlier run left is replaced;
        // later passes remove closed channels.
        if #available(macOS 27, *), previous?.channels != snapshot.channels {
            let conversations = ConversationEntity.all(in: app)
            let people = MessagePersonEntity.all(in: app)
            let stale: [String]? = previous == nil ? nil : Array(siriIDs.subtracting(ids))
            try await replace(conversations, stale: stale)
            try await replace(people, stale: stale)
            siriIDs = ids
        }

        // Spotlight results: only while the setting is on.
        if snapshot.isEnabled {
            let stale: [String]? = previous?.isEnabled == true ? Array(spotlightIDs.subtracting(ids)) : nil
            try await replace(channels, stale: stale)
            spotlightIDs = ids
        } else if previous?.isEnabled != false {
            try await index.deleteAll(ofType: ChannelEntity.self)
            spotlightIDs = []
        }
    }

    /// Indexes `entities`, first removing `stale` ones (all of the type if nil).
    private func replace<Entity: IndexedEntity>(_ entities: [Entity], stale: [Entity.ID]?) async throws {
        if let stale {
            if !stale.isEmpty { try await index.delete(stale, ofType: Entity.self) }
        } else {
            try await index.deleteAll(ofType: Entity.self)
        }
        try await index.index(entities)
    }
}
