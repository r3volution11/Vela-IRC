// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization
import VelaMedia
import VelaStore

// MARK: - Saved history (`history.save`)

/// Whether message history is saved on this Mac. On, messages, reactions,
/// link previews and downloaded images are kept on disk; off, they live in
/// memory while Vela runs. Buffer state (channels, read positions, mute,
/// order) is saved either way, so unread counts and Catch me up still work
/// with what a bouncer replays.
extension AppModel {
    /// What sessions do with the database: save and load, load what was
    /// kept when saving was turned off, or neither.
    public var historyStorage: HistoryStorage {
        HistoryStorage(saves: settings[.historySave], hasSavedMessages: savedHistory.hasMessages)
    }

    /// Reads what's saved again, for ``savedHistory``.
    @discardableResult
    public func refreshSavedHistory() async -> SavedHistory {
        guard let database, let saved = try? await database.savedHistory() else { return savedHistory }
        savedHistory = saved
        return saved
    }

    /// Deletes saved messages, their search index, reactions and cached
    /// link previews from disk, and empties the image cache. Channels, read
    /// positions and settings stay, and so do the messages on screen until
    /// Vela quits. Chat logs aren't touched.
    public func deleteSavedHistory() async throws {
        ImageLoader.removeDiskCache()
        savedMessagesObserver?.savedHistoryDeleted()
        guard let database else { return }
        do {
            try await database.deleteSavedHistory()
        } catch {
            await refreshSavedHistory()
            throw error
        }
        await refreshSavedHistory()
    }

    /// Keeps the link preview cache and the image cache in step with
    /// `history.save`, from launch on.
    func observeHistorySetting() {
        guard !isDemo else { return }
        applyHistorySetting()
        withObservationTracking {
            _ = settings[.historySave]
        } onChange: { [weak self] in
            // Runs before the change lands; act on it right after.
            Task { @MainActor in
                self?.historySettingChanged()
                self?.observeHistorySetting()
            }
        }
    }

    private func applyHistorySetting() {
        let saves = settings[.historySave]
        previewDiskCache.isOn = saves
        setImageDiskCache(saves)
    }

    private func historySettingChanged() {
        applyHistorySetting()
        // Turned off with history kept: it still loads (HistoryStorage.loadOnly).
        Task { await refreshSavedHistory() }
    }
}

/// Whether ``DatabasePreviewCache`` reads and writes the database. Shared
/// with the link preview service's actor, so it's locked.
nonisolated final class PreviewDiskCacheSwitch: Sendable {
    private let state: Mutex<Bool>

    init(isOn: Bool) {
        state = Mutex(isOn)
    }

    var isOn: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
