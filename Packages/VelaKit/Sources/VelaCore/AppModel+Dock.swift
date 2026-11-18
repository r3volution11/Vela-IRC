// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Observation
import VelaStore

/// What `AppModel` keeps between Dock updates.
struct DockState {
    var offlineTracker = DockOfflineTracker()
    /// Re-checks the offline mark when a network's grace period ends.
    var offlineCheck: Task<Void, Never>?
    /// The bounce in progress, so a burst of messages doesn't stack them
    /// and switching to Vela can stop it.
    var attentionRequest: (id: Int, attention: DockAttention)?
    /// Set when Vela starts quitting: nothing changes the Dock after that.
    var isStopped = false
}

// MARK: - Dock badge, offline mark and bouncing

/// The Dock tile's badge (`dock.showBadge`, `dock.badgeCounts`,
/// `dock.badgeStyle`), the offline mark (`dock.showOffline`, drawn by the
/// scene layer from ``showsOfflineMark``) and bouncing (`dock.bounce`,
/// `dock.bounceFor`). The rules live in ``DockBadge``,
/// ``DockOfflineTracker`` and ``DockBounce``; this applies them.
///
/// None of it runs in demo mode, so screenshots and demo runs never touch
/// the Dock.
extension AppModel {
    /// The Dock badge the current unread counts and settings call for, or
    /// nil for none.
    public var dockBadgeLabel: String? {
        DockBadge.label(
            for: sessions.flatMap { $0.allBuffers.map { DockBadgeBuffer($0) } },
            isEnabled: settings[.dockShowBadge],
            counting: Set(settings[.dockBadgeCounts]),
            style: settings[.dockBadgeStyle]
        )
    }

    /// Each network's connection, for the offline mark. Bouncer networks
    /// count by their own connection; one whose bouncer was removed never
    /// connects, so it isn't listed.
    var dockNetworkStatuses: [DockNetworkStatus] {
        sessions.filter { !isOrphanedChild($0) }.map {
            DockNetworkStatus(id: $0.id, isConnected: $0.isConnected, expectsConnection: $0.expectsConnection)
        }
    }

    /// Brings the badge and the offline mark up to date.
    func updateDock() {
        updateDockBadge()
        updateOfflineMark()
    }

    func updateDockBadge() {
        guard !isDemo, !dock.isStopped, let tile = NSApp?.dockTile else { return }
        let label = dockBadgeLabel
        if tile.badgeLabel != label { tile.badgeLabel = label }
    }

    func updateOfflineMark() {
        guard !isDemo, !dock.isStopped else { return }
        let now = Date()
        dock.offlineTracker.update(dockNetworkStatuses, now: now)
        let shows = settings[.dockShowOffline] && dock.offlineTracker.showsMark(now: now)
        if showsOfflineMark != shows { showsOfflineMark = shows }
        scheduleOfflineCheck(at: dock.offlineTracker.nextChange(after: now))
    }

    /// Checks again when the next network's grace period ends.
    private func scheduleOfflineCheck(at date: Date?) {
        dock.offlineCheck?.cancel()
        dock.offlineCheck = nil
        guard let date else { return }
        let delay = max(0.05, date.timeIntervalSinceNow)
        dock.offlineCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.updateOfflineMark()
        }
    }

    /// Follows the Dock settings, whether they change in Settings, the
    /// command palette or settings.json.
    func observeDockSettings() {
        guard !isDemo else { return }
        withObservationTracking {
            _ = settings[.dockShowBadge]
            _ = settings[.dockBadgeCounts]
            _ = settings[.dockBadgeStyle]
            _ = settings[.dockShowOffline]
        } onChange: { [weak self] in
            // Runs before the change lands; act on it right after.
            Task { @MainActor in
                self?.updateDock()
                self?.observeDockSettings()
            }
        }
    }

    /// Bounces the Dock icon for `line`, if `dock.bounce` and
    /// `dock.bounceFor` ask for it and Vela is in the background.
    func requestDockAttention(for line: ChatLine, in buffer: BufferModel) {
        guard !isDemo, !dock.isStopped, let app = NSApp else { return }
        let trigger = DockBounce.trigger(isHighlight: line.isHighlight, lineKind: line.kind, bufferKind: buffer.kind)
        guard let attention = DockBounce.attention(
            for: trigger,
            isMuted: buffer.isMuted,
            appIsActive: app.isActive,
            style: settings[.dockBounce],
            triggers: Set(settings[.dockBounceFor])
        ) else { return }
        // Already bouncing until you come back: nothing to add.
        if dock.attentionRequest?.attention == .untilActive { return }
        let id = app.requestUserAttention(attention == .untilActive ? .criticalRequest : .informationalRequest)
        dock.attentionRequest = (id, attention)
    }

    /// Stops a bounce in progress (Vela became active).
    func cancelDockAttention() {
        guard let request = dock.attentionRequest else { return }
        dock.attentionRequest = nil
        NSApp?.cancelUserAttentionRequest(request.id)
    }

    /// Vela is quitting: leave the Dock as it is.
    func stopDockUpdates() {
        dock.isStopped = true
        dock.offlineCheck?.cancel()
        dock.offlineCheck = nil
    }
}
