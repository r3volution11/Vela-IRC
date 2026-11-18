// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaStore

// What the Dock icon shows and does: the badge count and its label
// (`dock.showBadge`, `dock.badgeCounts`, `dock.badgeStyle`), the offline
// mark (`dock.showOffline`) and bouncing (`dock.bounce`, `dock.bounceFor`).
// Pure values, so every rule is unit-tested; `AppModel` feeds them and
// applies the results.

// MARK: - Badge

/// What one buffer has unread, as far as the Dock badge is concerned.
nonisolated public struct DockBadgeBuffer: Sendable, Equatable {
    public var kind: BufferKind
    /// Unread messages, actions and notices (``BufferModel/unreadCount``).
    /// Joins, parts and other events are never counted.
    public var unread: Int
    /// Unread channel messages that mention your nick or a highlight word
    /// (``BufferModel/highlightCount``, for channels). Always part of `unread`.
    public var mentions: Int
    public var isMuted: Bool

    public init(kind: BufferKind, unread: Int, mentions: Int = 0, isMuted: Bool = false) {
        self.kind = kind
        self.unread = unread
        self.mentions = mentions
        self.isMuted = isMuted
    }

    @MainActor
    public init(_ buffer: BufferModel) {
        self.init(kind: buffer.kind, unread: buffer.unreadCount, mentions: buffer.highlightCount, isMuted: buffer.isMuted)
    }
}

/// The Dock badge: what it counts and how the count reads.
nonisolated public enum DockBadge {
    /// The unread messages of the kinds in `counting`, each counted once:
    ///
    /// - channels count every unread message with `.channels`, otherwise
    ///   only mentions with `.mentions` (a mention is never counted twice);
    /// - private conversations count every unread message with `.privateMessages`;
    /// - server buffers never count, and neither do muted buffers, whatever
    ///   they hold.
    public static func count(_ buffers: [DockBadgeBuffer], counting: Set<DockBadgeCount>) -> Int {
        buffers.reduce(0) { total, buffer in
            guard !buffer.isMuted else { return total }
            switch buffer.kind {
            case .channel:
                if counting.contains(.channels) { return total + max(buffer.unread, buffer.mentions) }
                if counting.contains(.mentions) { return total + buffer.mentions }
                return total
            case .query:
                return counting.contains(.privateMessages) ? total + buffer.unread : total
            case .server:
                return total
            }
        }
    }

    /// The text for the Dock tile's badge, or nil for no badge (nothing
    /// unread). `.capped` shows 1 to 99, then "99+".
    public static func label(count: Int, style: DockBadgeStyle) -> String? {
        guard count > 0 else { return nil }
        switch style {
        case .capped: return count > cap ? "\(cap)+" : "\(count)"
        case .exact: return "\(count)"
        case .dot: return dot
        }
    }

    /// The largest number `.capped` shows.
    public static let cap = 99
    /// The badge text for `.dot`.
    public static let dot = "•"

    /// The badge for `buffers` under these settings, or nil for none.
    public static func label(
        for buffers: [DockBadgeBuffer],
        isEnabled: Bool,
        counting: Set<DockBadgeCount>,
        style: DockBadgeStyle
    ) -> String? {
        guard isEnabled else { return nil }
        return label(count: count(buffers, counting: counting), style: style)
    }
}

// MARK: - Offline mark

/// One network's connection, as far as the offline mark is concerned.
nonisolated public struct DockNetworkStatus: Sendable, Equatable {
    public var id: UUID
    /// Registered with the server. Connecting, registering and waiting to
    /// reconnect all count as not connected.
    public var isConnected: Bool
    /// Vela means to be connected: the network connects automatically or
    /// was connected (or asked to connect), and you haven't disconnected it
    /// or quit since (``NetworkSession/expectsConnection``).
    public var expectsConnection: Bool

    public init(id: UUID, isConnected: Bool, expectsConnection: Bool) {
        self.id = id
        self.isConnected = isConnected
        self.expectsConnection = expectsConnection
    }
}

/// Which networks are unexpectedly offline, with a grace period so a quick
/// reconnect (or connecting at launch) never shows the mark.
///
/// A network is offline from the first update that finds it expected but
/// not connected, and shows once it has stayed that way for `grace`. It
/// stops being offline as soon as it's connected again, you disconnect it,
/// or it's removed (missing from an update).
nonisolated public struct DockOfflineTracker: Sendable, Equatable {
    /// How long a network may be offline before the mark shows: long
    /// enough for a reconnect after a dropped connection.
    public static let defaultGrace: TimeInterval = 10

    public var grace: TimeInterval
    /// When each network Vela means to be connected to was first seen offline.
    public private(set) var offlineSince: [UUID: Date] = [:]

    public init(grace: TimeInterval = DockOfflineTracker.defaultGrace) {
        self.grace = grace
    }

    /// Records the state of every network. Networks not listed are
    /// forgotten (removed).
    public mutating func update(_ networks: [DockNetworkStatus], now: Date) {
        var next: [UUID: Date] = [:]
        for network in networks where network.expectsConnection && !network.isConnected {
            next[network.id] = offlineSince[network.id] ?? now
        }
        offlineSince = next
    }

    /// Networks that have been offline for at least the grace period.
    public func offlineNetworks(now: Date) -> Set<UUID> {
        Set(offlineSince.filter { now.timeIntervalSince($0.value) >= grace }.keys)
    }

    /// Whether the Dock should show the offline mark.
    public func showsMark(now: Date) -> Bool {
        offlineSince.values.contains { now.timeIntervalSince($0) >= grace }
    }

    /// When the next network still within its grace period will pass it,
    /// or nil if none is: when to check again.
    public func nextChange(after now: Date) -> Date? {
        offlineSince.values
            .map { $0.addingTimeInterval(grace) }
            .filter { $0 > now }
            .min()
    }
}

// MARK: - Bouncing

/// A request to bounce the Dock icon.
nonisolated public enum DockAttention: Sendable, Equatable {
    /// Bounce once (`NSApplication.RequestUserAttentionType.informationalRequest`).
    case once
    /// Bounce until Vela becomes active (`.criticalRequest`).
    case untilActive
}

/// Whether a new message should bounce the Dock icon.
nonisolated public enum DockBounce {
    /// What kind of bounce-worthy message a line is, if any: a mention in a
    /// channel, or a message, action or notice in a private conversation.
    public static func trigger(isHighlight: Bool, lineKind: ChatLineKind, bufferKind: BufferKind) -> DockBounceTrigger? {
        guard lineKind.isConversation else { return nil }
        switch bufferKind {
        case .channel: return isHighlight ? .mentions : nil
        case .query: return .privateMessages
        case .server: return nil
        }
    }

    /// The bounce for a message of kind `trigger`, or nil for none: only
    /// while Vela isn't the active app, never for a muted buffer, and only
    /// for the kinds in `triggers`.
    public static func attention(
        for trigger: DockBounceTrigger?,
        isMuted: Bool,
        appIsActive: Bool,
        style: DockBounceStyle,
        triggers: Set<DockBounceTrigger>
    ) -> DockAttention? {
        guard let trigger, !isMuted, !appIsActive, triggers.contains(trigger) else { return nil }
        switch style {
        case .off: return nil
        case .once: return .once
        case .untilActive: return .untilActive
        }
    }
}
