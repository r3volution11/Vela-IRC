// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import VelaCore

// MARK: Scroll metrics

/// The scroll values the message list reacts to.
nonisolated struct ScrollMetrics: Equatable, Sendable {
    var visibleMinY: CGFloat
    var visibleMaxY: CGFloat
    var contentHeight: CGFloat
    var containerHeight: CGFloat

    init(visibleMinY: CGFloat, visibleMaxY: CGFloat, contentHeight: CGFloat, containerHeight: CGFloat) {
        self.visibleMinY = visibleMinY
        self.visibleMaxY = visibleMaxY
        self.contentHeight = contentHeight
        self.containerHeight = containerHeight
    }

    /// How much content lies below the visible rect. Zero when the visible
    /// rect reaches past the content: LazyVStack re-estimates row heights as
    /// rows appear, so the reported content height can lag behind the
    /// visible rect, which then still shows the end.
    var distanceFromBottom: CGFloat { max(0, contentHeight - visibleMaxY) }

    var fitsWithoutScrolling: Bool { contentHeight <= containerHeight + 1 }
}

// MARK: Pinning

/// Decides when the message list follows the newest line.
///
/// The list is *pinned* while the reader is at (or within
/// `bottomTolerance` of) the bottom. Pinned, every change in size — a new
/// line, an image or link card finishing loading, a reaction, a window
/// resize, a font change — keeps the bottom in view, and any drift (lazy
/// rows being re-measured, SwiftUI correcting its offset) is scrolled back.
///
/// Only the reader unpins the list, by scrolling up past the tolerance in a
/// gesture. While unpinned nothing scrolls them (except sending a message,
/// which always returns to the present) until they come back to the bottom.
nonisolated struct ScrollPinning: Sendable {
    /// Distance from the bottom that still counts as "at the bottom".
    static let bottomTolerance: CGFloat = 40

    /// What is moving the list right now.
    enum Driver: Sendable {
        /// No gesture: layout changes and SwiftUI's own corrections. (The
        /// list isn't focusable, so there is no keyboard scrolling.)
        case idle
        /// A trackpad, wheel or scroller gesture, including momentum.
        case user
        /// A programmatic scroll (reply jump, jump to present) still running.
        case programmatic
    }

    private(set) var isPinned: Bool
    /// The last metrics seen.
    private(set) var metrics: ScrollMetrics?

    init(isPinned: Bool = true) {
        self.isPinned = isPinned
    }

    static func isNearBottom(_ metrics: ScrollMetrics) -> Bool {
        metrics.fitsWithoutScrolling || metrics.distanceFromBottom <= bottomTolerance
    }

    /// Whether the newest content is entirely visible.
    static func isAtBottom(_ metrics: ScrollMetrics) -> Bool {
        metrics.fitsWithoutScrolling || metrics.distanceFromBottom <= 0.5
    }

    /// Updates the pinned state for new scroll geometry. Returns true when
    /// the list should scroll to the bottom to stay pinned.
    mutating func update(_ new: ScrollMetrics, driver: Driver) -> Bool {
        let previous = metrics
        metrics = new
        switch driver {
        case .programmatic:
            // Intermediate frames of a programmatic scroll aren't intent.
            return false
        case .user:
            // Follow the direction the reader moves. Rows re-measured
            // mid-gesture change the distance to the bottom without the
            // reader moving, and must neither unpin nor re-pin the list.
            guard let previous else { return false }
            if new.visibleMinY < previous.visibleMinY - 0.5 {
                if !Self.isNearBottom(new) { isPinned = false }
            } else if new.visibleMinY > previous.visibleMinY + 0.5 {
                if Self.isNearBottom(new) { isPinned = true }
            }
            return false
        case .idle:
            // Never the reader, so never unpins. Pinned: scroll back to the
            // bottom after growth or drift. Unpinned: follow again once the
            // bottom is in view (the content shrank, the window grew).
            if isPinned { return !Self.isAtBottom(new) }
            if Self.isAtBottom(new) { isPinned = true }
            return false
        }
    }

    /// A scroll gesture (and its momentum) ended: a reader who stopped near
    /// the bottom follows it again.
    mutating func gestureEnded() {
        if !isPinned, let metrics, Self.isNearBottom(metrics) { isPinned = true }
    }

    /// Follow the bottom (sending a message, "Jump to present").
    mutating func pin() { isPinned = true }

    /// Stop following the bottom (jumping to a message or the unread marker).
    mutating func unpin() { isPinned = false }

    /// Re-derives the state once a programmatic scroll has finished, from
    /// where it landed. Returns true when the list should scroll to the
    /// bottom (a jump to present that fell short, e.g. after rows were
    /// re-measured on the way).
    mutating func settle() -> Bool {
        guard let metrics else { return isPinned }
        if isPinned { return !Self.isAtBottom(metrics) }
        isPinned = Self.isNearBottom(metrics)
        return false
    }
}

// MARK: Line tracking

/// Watches a buffer's lines for what the list must react to: lines that
/// arrived since the last check, and messages the user just sent.
nonisolated struct LineTracker: Sendable {
    /// How far from the end to look for a newly sent message. Local echo
    /// can land a little before the last line when the bouncer's clock runs
    /// ahead (lines are kept in time order).
    static let ownMessageWindow = 64

    struct Change: Equatable, Sendable {
        /// The user sent a message (local echo or echo-message), so the list
        /// returns to the present.
        var sentMessage = false
        /// Conversation lines from others appended at the end.
        var newFromOthers = 0
        /// Lines appended at the end.
        var appended = 0
        /// Lines inserted before the previous last line (history, playback,
        /// or a line with an earlier timestamp).
        var inserted = 0
    }

    private(set) var lastLineID: UUID?
    private(set) var newestSentID: UUID?
    private(set) var count = 0

    init(lines: [ChatLine]) {
        lastLineID = lines.last?.id
        newestSentID = Self.newestSent(in: lines[...])
        count = lines.count
    }

    /// A live message the user sent (not one replayed from history).
    static func isSent(_ line: ChatLine) -> Bool {
        line.isSelf && !line.isHistory && line.kind.isConversation
    }

    private static func newestSent(in lines: ArraySlice<ChatLine>) -> UUID? {
        lines.last(where: isSent)?.id
    }

    mutating func update(_ lines: [ChatLine]) -> Change {
        var change = Change()
        let previousLast = lastLineID
        let previousCount = count
        lastLineID = lines.last?.id
        count = lines.count

        // New lines usually arrive at the end, so search backwards.
        let appended: ArraySlice<ChatLine>
        if let previousLast {
            if let index = lines.lastIndex(where: { $0.id == previousLast }) {
                appended = lines[(index + 1)...]
            } else {
                appended = []   // rebuilt or trimmed past it: nothing is "new"
            }
        } else {
            appended = lines[...]
        }
        change.appended = appended.count
        change.newFromOthers = appended.reduce(0) { $0 + ($1.kind.isConversation && !$1.isSelf ? 1 : 0) }
        change.inserted = max(0, lines.count - previousCount - appended.count)

        if let sent = Self.newestSent(in: lines.suffix(Self.ownMessageWindow)), sent != newestSentID {
            newestSentID = sent
            change.sentMessage = true
        }
        return change
    }
}

/// Cheap identity of a buffer's lines, to notice appends, insertions and
/// trims without comparing arrays.
nonisolated struct LinesSignature: Equatable, Sendable {
    var count: Int
    var firstID: UUID?
    var lastID: UUID?

    init(_ lines: [ChatLine]) {
        count = lines.count
        firstID = lines.first?.id
        lastID = lines.last?.id
    }
}
