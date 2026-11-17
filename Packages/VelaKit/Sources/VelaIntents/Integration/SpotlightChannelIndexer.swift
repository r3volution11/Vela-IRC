// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import CoreSpotlight
import Foundation
import Observation
import VelaCore
import VelaStore

/// Keeps Spotlight's index of channel and conversation names in step with
/// the sidebar while `intelligence.spotlightChannels` is on, and empties it
/// when it's turned off. Names and networks only, never messages. Changes
/// are batched: a burst of joins is indexed once, a moment later.
@MainActor
final class SpotlightChannelIndexer {
    /// What the index reflects: the setting, and each channel's id, name
    /// and network (not unread counts, which change all the time).
    struct Snapshot: Equatable {
        var isEnabled: Bool
        var channels: [String]
    }

    static let debounce: Duration = .seconds(2)

    private let app: AppModel
    private let refreshAppShortcuts: (@MainActor () -> Void)?
    private var pending: Task<Void, Never>?
    private var applied: Snapshot?
    private var indexedIDs: Set<String> = []

    init(app: AppModel, refreshAppShortcuts: (@MainActor () -> Void)?) {
        self.app = app
        self.refreshAppShortcuts = refreshAppShortcuts
    }

    func start() {
        observe()
        schedule()
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

    private func observe() {
        withObservationTracking {
            _ = Self.snapshot(of: app)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.schedule()
                self?.observe()
            }
        }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.update()
        }
    }

    private func update() async {
        let snapshot = Self.snapshot(of: app)
        let previous = applied
        guard snapshot != previous else { return }
        applied = snapshot
        do {
            if snapshot.isEnabled {
                let channels = ChannelEntity.all(in: app)
                let ids = Set(channels.map(\.id))
                // The first pass (or just turned on) drops whatever an
                // earlier run left behind; later ones drop closed channels.
                let stale: [String]? = previous?.isEnabled == true ? Array(indexedIDs.subtracting(ids)) : nil
                try await Self.index(channels, replacing: stale)
                if #available(macOS 27, *) {
                    try await Self.index(ConversationEntity.all(in: app), replacing: stale)
                    try await Self.index(MessagePersonEntity.all(in: app), replacing: stale)
                }
                indexedIDs = ids
            } else if previous?.isEnabled != false {
                try await Self.removeAll(ChannelEntity.self)
                if #available(macOS 27, *) {
                    try await Self.removeAll(ConversationEntity.self)
                    try await Self.removeAll(MessagePersonEntity.self)
                }
                indexedIDs = []
            }
        } catch {
            // Try again on the next change.
            applied = nil
        }
        if previous?.channels != snapshot.channels {
            refreshAppShortcuts?()
        }
    }

    /// Indexes `entities`, first removing `stale` ones (all of this type if nil).
    private nonisolated static func index<Entity: IndexedEntity>(
        _ entities: [Entity],
        replacing stale: [Entity.ID]?
    ) async throws {
        let index = CSSearchableIndex.default()
        if let stale {
            if !stale.isEmpty { try await index.deleteAppEntities(identifiedBy: stale, ofType: Entity.self) }
        } else {
            try await index.deleteAppEntities(ofType: Entity.self)
        }
        try await index.indexAppEntities(entities)
    }

    private nonisolated static func removeAll<Entity: IndexedEntity>(_ type: Entity.Type) async throws {
        try await CSSearchableIndex.default().deleteAppEntities(ofType: type)
    }
}
