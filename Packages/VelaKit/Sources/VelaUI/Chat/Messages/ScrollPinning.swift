// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import VelaCore

// MARK: Scroll metrics

/// The scroll values the message list reacts to.
///
/// The lazy stack's content height is partly an estimate: rows it hasn't
/// laid out count at an average height. In a long channel whose rows vary
/// a lot (one-line messages between 315 pt video players) that estimate
/// can run thousands of points past where the rows really end, and the
/// bottom *edge* of the content is then empty space. So while the space
/// after the last row is laid out in view, its bottom (`contentEnd`) is
/// where the list ends.
nonisolated struct ScrollMetrics: Equatable, Sendable {
    var visibleMinY: CGFloat
    var visibleMaxY: CGFloat
    var contentHeight: CGFloat
    var containerHeight: CGFloat
    /// The bottom of the space after the last row (`DisplayItemID.end`), in
    /// content coordinates, while it's laid out in the visible rect; nil
    /// otherwise.
    var contentEnd: CGFloat?

    init(visibleMinY: CGFloat, visibleMaxY: CGFloat, contentHeight: CGFloat, containerHeight: CGFloat, contentEnd: CGFloat? = nil) {
        self.visibleMinY = visibleMinY
        self.visibleMaxY = visibleMaxY
        self.contentHeight = contentHeight
        self.containerHeight = containerHeight
        self.contentEnd = contentEnd
    }

    /// Where the newest line ends: `contentEnd`, or the (estimated) content
    /// height while the end isn't laid out.
    var end: CGFloat { contentEnd ?? contentHeight }

    /// How much content lies below the visible rect. Zero when the visible
    /// rect reaches past the end (see `distancePastEnd`).
    var distanceFromBottom: CGFloat { max(0, end - visibleMaxY) }

    /// How far the visible rect reaches below the last row: space with
    /// nothing in it. Known only while the end is in view; zero otherwise.
    var distancePastEnd: CGFloat {
        guard let contentEnd else { return 0 }
        return max(0, visibleMaxY - contentEnd)
    }

    var fitsWithoutScrolling: Bool { contentHeight <= containerHeight + 1 }
}

// MARK: Pinning

/// Decides when the message list follows the newest line.
///
/// The list is *pinned* while the reader is at (or within
/// `bottomTolerance` of) the bottom. Pinned, every change in size — a new
/// line, an image or link card finishing loading, a reaction, a window
/// resize, a font change — keeps the bottom in view, and any drift (lazy
/// rows being re-measured, SwiftUI correcting its offset, the visible rect
/// left below the last row by a re-estimated content height) is scrolled
/// back. When the list itself gets shorter (the composer growing a line),
/// it scrolls to the bottom anew, whatever SwiftUI reports
/// (`mustScrollToBottomAnew`).
///
/// Only the reader unpins the list: by scrolling up past the tolerance in a
/// gesture, or from the keyboard (Page Up or Home in the message box, a
/// message selected above the list's top edge). While unpinned nothing
/// scrolls them (except sending a message,
/// which always returns to the present) until they come back to the bottom.
/// Nothing scrolls under a gesture either: what it held back (new lines, a
/// sent message) is followed when it ends, if the reader stayed at the
/// bottom (`holdBackFollow()`, `gestureEnded()`).
nonisolated struct ScrollPinning: Sendable {
    /// Distance from the bottom that still counts as "at the bottom".
    static let bottomTolerance: CGFloat = 40

    /// What is moving the list right now.
    enum Driver: Sendable {
        /// No gesture: layout changes and SwiftUI's own corrections.
        case idle
        /// A trackpad, wheel or scroller gesture, including momentum.
        case user
        /// A programmatic scroll (reply jump, jump to present, and the
        /// keyboard's: Page Up in the message box, a selected message
        /// brought into view) still running.
        case programmatic
    }

    private(set) var isPinned: Bool
    /// The last metrics seen.
    private(set) var metrics: ScrollMetrics?
    /// A follow the reader's gesture held back: new lines arrived, or a
    /// message was sent, while they scrolled without leaving the bottom.
    private(set) var followHeldBack = false

    init(isPinned: Bool = true) {
        self.isPinned = isPinned
    }

    /// Within `bottomTolerance` of the newest line, or past it.
    static func isNearBottom(_ metrics: ScrollMetrics) -> Bool {
        metrics.fitsWithoutScrolling || metrics.distanceFromBottom <= bottomTolerance
    }

    /// Whether the newest line sits at the bottom of the visible rect: the
    /// space after it in view there, with nothing below (but the fraction of
    /// a point the content's height is rounded up by). A visible rect at the
    /// bottom edge of the (estimated) content without that space in it
    /// isn't: there may be nothing laid out there at all.
    static func isAtBottom(_ metrics: ScrollMetrics) -> Bool {
        if metrics.fitsWithoutScrolling { return true }
        guard metrics.contentEnd != nil else { return false }
        return metrics.distanceFromBottom <= 0.5 && metrics.distancePastEnd <= 1
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

    /// Whether the list must scroll to the bottom again even though `new`
    /// says it's there: it got shorter while following the newest line.
    ///
    /// The composer growing a line, a reply bar or bottom tabs appearing
    /// and the window getting shorter all take height from the list. Its
    /// bottom anchor then moves the offset down by as much, and SwiftUI
    /// reports the list at the bottom. But on the Mac that move can be lost:
    /// it reaches the scroll view while the scroll view is still its old
    /// height, where it would scroll past the end, so it's held at the old
    /// end. The list then shows the newest line under its bottom edge (by as
    /// much as it got shorter: under the composer) while every report says
    /// it's at the bottom, and stays that way.
    ///
    /// Not while the reader scrolls: that moves the scroll view itself,
    /// which brings SwiftUI's offset back in line.
    func mustScrollToBottomAnew(from previous: ScrollMetrics?, to new: ScrollMetrics, driver: Driver) -> Bool {
        guard isPinned, driver != .user, let previous else { return false }
        return new.containerHeight < previous.containerHeight - 0.5
    }

    /// The list should follow the newest line, but the reader is scrolling
    /// (`MessageListView` doesn't scroll under a gesture). It does once the
    /// gesture ends, if it's still pinned then.
    mutating func holdBackFollow() {
        if isPinned { followHeldBack = true }
    }

    /// A scroll gesture (and its momentum) ended: a reader who stopped near
    /// the bottom follows it again. Returns true when the list should scroll
    /// to the bottom: a follow was held back during the gesture and the
    /// list, still pinned, isn't at the bottom. (Nothing else would move it
    /// there: its geometry has stopped changing.)
    mutating func gestureEnded() -> Bool {
        defer { followHeldBack = false }
        if !isPinned, let metrics, Self.isNearBottom(metrics) { isPinned = true }
        guard isPinned, followHeldBack else { return false }
        return !(metrics.map(Self.isAtBottom) ?? false)
    }

    /// Follow the bottom (sending a message, "Jump to present").
    mutating func pin() { isPinned = true }

    /// Stop following the bottom (jumping to a message or the unread marker).
    mutating func unpin() {
        isPinned = false
        followHeldBack = false
    }

    /// Re-derives the state once a programmatic scroll has finished, from
    /// where it landed. Returns true when the list should scroll to the
    /// bottom (a jump to present that fell short, e.g. after rows were
    /// re-measured on the way).
    ///
    /// Landing near the bottom follows it again, as after a gesture, unless
    /// `followsNearBottom` is false: then only landing at it does. A scroll
    /// that brought a row selected with the keyboard into view a little
    /// above the bottom stays there, rather than following the newest line
    /// and cutting the row off again.
    mutating func settle(followsNearBottom: Bool = true) -> Bool {
        guard let metrics else { return isPinned }
        if isPinned { return !Self.isAtBottom(metrics) }
        isPinned = followsNearBottom ? Self.isNearBottom(metrics) : Self.isAtBottom(metrics)
        return false
    }
}

// MARK: Settling at the bottom

/// How a scroll to the bottom makes sure it got there
/// (`MessageListView.scrollToBottom`).
///
/// The scroll goes to the space after the last row, by id, but can land
/// where the lazy stack *estimates* that space is, with nothing laid out:
/// the list shows nothing. Each try lets the stack measure more rows and
/// land closer, and the stack also measures rows on its own when the app
/// has a moment. So the list checks every `interval` and scrolls again
/// until the space is at the bottom of the visible rect, for `budget`
/// seconds *and* at least `minimumTries` tries: a busy main actor that
/// delays the checks can't run the budget out in a few tries, and time
/// while another scroll or animation is under way doesn't count at all.
/// Then a few `lateTries`, further apart, in case nothing else moves the
/// list (it scrolls back on its own after any change in its geometry).
///
/// An equal `ScrollPosition` is ignored, so tries cycle through three
/// anchors a hair apart, each different from the one before, and a list
/// that got there on one of them settles back on `.bottom`.
nonisolated struct BottomSettle: Equatable, Sendable {
    static let interval: TimeInterval = 0.03
    static let budget: TimeInterval = 2
    static let minimumTries = 10
    /// Waits before each try once the budget is spent.
    static let lateTries: [TimeInterval] = [0.5, 1, 2]
    /// Anchors the tries cycle through; `1` is `.bottom`.
    static let anchors: [CGFloat] = [0.9999, 1, 0.99995]
    /// The anchor of a scroll to the bottom that SwiftUI must carry out
    /// when its position is `.bottom` already (`MessageListView`'s
    /// `scrollToBottom(anew:)`). Not the first try's, so that try isn't
    /// ignored in turn.
    static let anewAnchor: CGFloat = anchors[2]

    enum Step: Equatable, Sendable {
        /// Check again after `wait`.
        case wait
        /// Scroll to the space after the last row with this anchor (a
        /// `UnitPoint` y), then check again after `wait`.
        case scroll(anchor: CGFloat)
        /// Stop checking; `settleBack` scrolls to it with `.bottom` once more.
        case done(settleBack: Bool)
    }

    /// Checking time spent so far, not counting other scrolls.
    private(set) var spent: TimeInterval = 0
    private(set) var tries = 0
    private(set) var lateTriesMade = 0
    /// The anchor of the last scroll: before any try, the first scroll's
    /// (`.bottom`, unless it was `anewAnchor`).
    private(set) var lastAnchor: CGFloat

    init(firstAnchor: CGFloat = 1) {
        lastAnchor = firstAnchor
    }

    private var inBudget: Bool { spent < Self.budget || tries < Self.minimumTries }

    /// How long to wait before the next check.
    var wait: TimeInterval {
        inBudget ? Self.interval : Self.lateTries[min(lateTriesMade, Self.lateTries.count - 1)]
    }

    /// A check, `waited` seconds after the last one.
    mutating func check(waited: TimeInterval, otherScrollUnderWay: Bool, atBottom: Bool) -> Step {
        if atBottom { return .done(settleBack: lastAnchor != 1) }
        if otherScrollUnderWay { return .wait }
        if inBudget {
            spent += max(0, waited)
        } else if lateTriesMade < Self.lateTries.count {
            lateTriesMade += 1
        } else {
            return .done(settleBack: lastAnchor != 1)
        }
        tries += 1
        let anchor = Self.anchors[(tries - 1) % Self.anchors.count]
        lastAnchor = anchor
        return .scroll(anchor: anchor)
    }
}

// MARK: The clip view

/// Whether AppKit shows the list where SwiftUI reports it.
///
/// On the Mac, SwiftUI's `ScrollView` is an `NSScrollView`, and an offset
/// SwiftUI sets doesn't always reach its clip view: one that reaches it
/// before the clip view or the document has its new size is held where
/// AppKit allows. SwiftUI keeps reporting the offset it set, at the bottom,
/// while the clip view shows the list short of it: the newest line stays
/// under the list's bottom edge, under the composer, until something else
/// scrolls it. (`ScrollPinning.mustScrollToBottomAnew` heads off the case
/// seen most, the list getting shorter; this catches any other.)
///
/// So a list following the newest line compares the two once a change has
/// been laid out (`MessageListController.queueClipCheck`), and scrolls to
/// the bottom again when they differ. A scroll makes SwiftUI set the offset
/// anew, which brings the clip view in line. The checks that follow that
/// scroll (`BottomSettle`) note whether it did. A difference a scroll
/// didn't fix isn't one a scroll can fix, so it's left alone rather than
/// scrolled at after every change.
nonisolated struct ClipViewSync: Equatable, Sendable {
    /// More than this between the two is the clip view out of step.
    static let tolerance: CGFloat = 1

    /// The difference last scrolled for, until the two are seen to agree.
    private(set) var resynced: CGFloat?

    static func agree(reportedMinY: CGFloat, clipMinY: CGFloat) -> Bool {
        abs(clipMinY - reportedMinY) <= tolerance
    }

    /// Whether the list must scroll to bring the clip view, at `clipMinY`,
    /// to the offset SwiftUI reports, `reportedMinY`.
    mutating func needsScroll(reportedMinY: CGFloat, clipMinY: CGFloat) -> Bool {
        let difference = clipMinY - reportedMinY
        guard !Self.agree(reportedMinY: reportedMinY, clipMinY: clipMinY) else {
            resynced = nil
            return false
        }
        if let resynced, abs(resynced - difference) <= 0.5 { return false }
        resynced = difference
        return true
    }

    /// Where the two are now, after a scroll: once they agree, the next
    /// difference, whatever it is, is scrolled for again.
    mutating func observe(reportedMinY: CGFloat, clipMinY: CGFloat) {
        if Self.agree(reportedMinY: reportedMinY, clipMinY: clipMinY) { resynced = nil }
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
