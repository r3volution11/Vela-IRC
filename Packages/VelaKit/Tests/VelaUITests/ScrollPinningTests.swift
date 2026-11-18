// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import Testing
import VelaCore
@testable import VelaUI

@Suite("Scroll pinning")
struct ScrollPinningTests {
    /// A 600pt viewport whose bottom edge is `distance` above the end of
    /// `content`. The space after the last row, at the very end, is laid out
    /// when it's in the viewport.
    private func at(distance: CGFloat, content: CGFloat = 3000, container: CGFloat = 600) -> ScrollMetrics {
        let maxY = content - distance
        return ScrollMetrics(
            visibleMinY: maxY - container, visibleMaxY: maxY, contentHeight: content, containerHeight: container,
            contentEnd: distance < container ? content : nil
        )
    }

    /// Pinning that has seen `metrics` (idle) as its last frame.
    private func pinning(pinned: Bool, at metrics: ScrollMetrics) -> ScrollPinning {
        var pinning = ScrollPinning(isPinned: pinned)
        _ = pinning.update(metrics, driver: .programmatic)
        return pinning
    }

    // MARK: Bottom tolerance

    @Test func nearAndAtBottom() {
        #expect(ScrollPinning.isNearBottom(at(distance: 40)))
        #expect(!ScrollPinning.isNearBottom(at(distance: 41)))
        #expect(ScrollPinning.isAtBottom(at(distance: 0.5)))
        #expect(!ScrollPinning.isAtBottom(at(distance: 2)))
        // Content shorter than the viewport is always at the bottom.
        let short = ScrollMetrics(visibleMinY: 0, visibleMaxY: 600, contentHeight: 300, containerHeight: 600)
        #expect(ScrollPinning.isAtBottom(short))
    }

    /// The content height is partly estimated, and can run far past the
    /// last row: the bottom is where the space after the last row ends.
    @Test func theLastRowNotTheEstimateIsTheBottom() {
        // At the last row, with the estimate running 600pt further.
        let atEnd = ScrollMetrics(visibleMinY: 1600, visibleMaxY: 2200, contentHeight: 2800, containerHeight: 600, contentEnd: 2200)
        #expect(atEnd.distanceFromBottom == 0)
        #expect(ScrollPinning.isAtBottom(atEnd))
        // The content's height is rounded up to a whole point: resting a
        // fraction past the last row is still at it.
        let rounded = ScrollMetrics(visibleMinY: 1600.5, visibleMaxY: 2200.5, contentHeight: 2201, containerHeight: 600, contentEnd: 2200)
        #expect(ScrollPinning.isAtBottom(rounded))
        // Short of it.
        let above = ScrollMetrics(visibleMinY: 1500, visibleMaxY: 2100, contentHeight: 2800, containerHeight: 600, contentEnd: 2200)
        #expect(above.distanceFromBottom == 100)
        #expect(!ScrollPinning.isAtBottom(above))
        #expect(!ScrollPinning.isNearBottom(above))
        // Past it: empty space below the last row. Near (so a gesture
        // ending there re-pins), but not at the bottom.
        let past = ScrollMetrics(visibleMinY: 1900, visibleMaxY: 2500, contentHeight: 2500, containerHeight: 600, contentEnd: 2200)
        #expect(past.distanceFromBottom == 0)
        #expect(past.distancePastEnd == 300)
        #expect(ScrollPinning.isNearBottom(past))
        #expect(!ScrollPinning.isAtBottom(past))
        // At the bottom edge of the estimated content with the last row
        // nowhere in view: possibly nothing laid out at all.
        let estimated = ScrollMetrics(visibleMinY: 9400, visibleMaxY: 10_000, contentHeight: 10_000, containerHeight: 600)
        #expect(estimated.distanceFromBottom == 0)
        #expect(!ScrollPinning.isAtBottom(estimated))
    }

    /// A pinned list whose visible rect ended up below the last row (the
    /// content height re-estimated under it) or where the last row isn't
    /// laid out scrolls back to it, and stops once it's there.
    @Test func pinnedFollowsBackToTheLastRow() {
        var pinning = pinning(pinned: true, at: at(distance: 0))
        let past = ScrollMetrics(visibleMinY: 33_557, visibleMaxY: 34_027, contentHeight: 34_027, containerHeight: 470, contentEnd: 33_551)
        let r1 = pinning.update(past, driver: .idle)
        #expect(r1)
        let nowhere = ScrollMetrics(visibleMinY: 141_935, visibleMaxY: 142_470, contentHeight: 142_470, containerHeight: 535)
        let r2 = pinning.update(nowhere, driver: .idle)
        #expect(r2)
        #expect(pinning.isPinned)
        let there = ScrollMetrics(visibleMinY: 33_081, visibleMaxY: 33_551, contentHeight: 34_027, containerHeight: 470, contentEnd: 33_551)
        let r3 = pinning.update(there, driver: .idle)
        #expect(!r3)
        #expect(pinning.settle() == false)
    }

    // MARK: Pinned

    @Test func pinnedFollowsGrowth() {
        var pinning = pinning(pinned: true, at: at(distance: 0))
        // A new line or an image loading pushes the bottom down.
        let r47 = pinning.update(at(distance: 320, content: 3320), driver: .idle)
        #expect(r47)
        #expect(pinning.isPinned)
        // Back at the bottom: nothing to do.
        let r50 = pinning.update(at(distance: 0, content: 3320), driver: .idle)
        #expect(!r50)
    }

    @Test func driftWithoutAGestureNeverUnpins() {
        var pinning = pinning(pinned: true, at: at(distance: 0))
        // SwiftUI moving the offset on its own (a lazy row re-measured, a
        // correction during live resize) is pulled back to the bottom.
        let r57 = pinning.update(at(distance: 217), driver: .idle)
        #expect(r57)
        #expect(pinning.isPinned)
        let r59 = pinning.update(at(distance: 900, content: 1800, container: 400), driver: .idle)
        #expect(r59)
        #expect(pinning.isPinned)
    }

    @Test func scrollingUpPastTheToleranceUnpins() {
        var pinning = pinning(pinned: true, at: at(distance: 0))
        // A little peek stays pinned…
        let r66 = pinning.update(at(distance: 30), driver: .user)
        #expect(!r66)
        #expect(pinning.isPinned)
        // …further up unpins.
        let r69 = pinning.update(at(distance: 120), driver: .user)
        #expect(!r69)
        #expect(!pinning.isPinned)
        // Unpinned, growth below doesn't move the reader.
        let r72 = pinning.update(at(distance: 400, content: 3280), driver: .idle)
        #expect(!r72)
        #expect(!pinning.isPinned)
    }

    @Test func rowsMeasuredMidGestureDontRepin() {
        // The reader scrolls up 80pt; then, without moving, rows below are
        // re-measured smaller and the distance shrinks under the tolerance.
        var pinning = pinning(pinned: true, at: at(distance: 0, content: 4000))
        _ = pinning.update(at(distance: 80, content: 4000), driver: .user)
        #expect(!pinning.isPinned)
        let minY = at(distance: 80, content: 4000).visibleMinY
        let shrunk = ScrollMetrics(visibleMinY: minY, visibleMaxY: minY + 600, contentHeight: 3940, containerHeight: 600)
        #expect(shrunk.distanceFromBottom == 20)
        _ = pinning.update(shrunk, driver: .user)
        #expect(!pinning.isPinned)
        // With the bottom anchor, rows shrinking while pinned move the
        // offset up without the reader leaving the bottom.
        var anchored = self.pinning(pinned: true, at: at(distance: 0, content: 4000))
        _ = anchored.update(at(distance: 0, content: 3800), driver: .user)
        #expect(anchored.isPinned)
    }

    @Test func scrollingBackDownRepins() {
        var pinning = pinning(pinned: false, at: at(distance: 800))
        _ = pinning.update(at(distance: 300), driver: .user)
        #expect(!pinning.isPinned)
        _ = pinning.update(at(distance: 35), driver: .user)
        #expect(pinning.isPinned)
    }

    @Test func gestureEndingNearTheBottomRepins() {
        var near = pinning(pinned: false, at: at(distance: 30))
        near.gestureEnded()
        #expect(near.isPinned)
        var far = pinning(pinned: false, at: at(distance: 300))
        far.gestureEnded()
        #expect(!far.isPinned)
    }

    @Test func unpinnedFollowsAgainOnceTheBottomIsInView() {
        var pinning = pinning(pinned: false, at: at(distance: 200))
        // The window grew (or content shrank) until the end is visible.
        let r114 = pinning.update(at(distance: 0, content: 3000, container: 800), driver: .idle)
        #expect(!r114)
        #expect(pinning.isPinned)
    }

    // MARK: Programmatic scrolls

    @Test func programmaticFramesAreIgnoredThenSettled() {
        var pinning = pinning(pinned: true, at: at(distance: 0))
        pinning.unpin()   // jumping to a reply
        let r123 = pinning.update(at(distance: 25), driver: .programmatic)
        #expect(!r123)
        #expect(!pinning.isPinned)
        // It landed near the bottom: follow from here.
        let r126 = pinning.settle()
        #expect(!r126)
        #expect(pinning.isPinned)

        // "Jump to present" that fell short of the bottom asks for another scroll.
        var short = self.pinning(pinned: false, at: at(distance: 5000))
        short.pin()
        _ = short.update(at(distance: 60), driver: .programmatic)
        let r133 = short.settle()
        #expect(r133)
        #expect(short.isPinned)

        // A jump that lands far up stays unpinned.
        var far = self.pinning(pinned: false, at: at(distance: 0))
        _ = far.update(at(distance: 1500), driver: .programmatic)
        let r139 = far.settle()
        #expect(!r139)
        #expect(!far.isPinned)
    }
}

@Suite("Line tracking")
struct LineTrackerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ nick: String, _ seconds: Double, isSelf: Bool = false, history: Bool = false,
                      kind: ChatLineKind = .message) -> ChatLine {
        ChatLine(time: start.addingTimeInterval(seconds), kind: kind, nick: nick, text: "hi", isSelf: isSelf, isHistory: history)
    }

    @Test func countsAppendedLinesFromOthers() {
        var lines = [line("a", 0), line("b", 1)]
        var tracker = LineTracker(lines: lines)
        lines += [line("c", 2), line("me", 3, isSelf: true, history: true), line("x", 4, kind: .join)]
        let change = tracker.update(lines)
        #expect(change.appended == 3)
        #expect(change.newFromOthers == 1)
        #expect(change.inserted == 0)
        #expect(!change.sentMessage)
    }

    @Test func detectsSentMessages() {
        var lines = [line("a", 0), line("me", 1, isSelf: true)]
        var tracker = LineTracker(lines: lines)
        // An own line that was already there isn't "just sent".
        let r168 = tracker.update(lines).sentMessage
        #expect(!r168)
        lines.append(line("me", 2, isSelf: true))
        let r170 = tracker.update(lines).sentMessage
        #expect(r170)
        // Reported once.
        lines.append(line("b", 3))
        let r173 = tracker.update(lines).sentMessage
        #expect(!r173)
        // Actions count; own joins and replayed own messages don't.
        lines.append(line("me", 4, isSelf: true, kind: .action))
        let r176 = tracker.update(lines).sentMessage
        #expect(r176)
        lines.append(line("me", 5, isSelf: true, kind: .join))
        lines.append(line("me", 6, isSelf: true, history: true))
        let r179 = tracker.update(lines).sentMessage
        #expect(!r179)
    }

    @Test func detectsSentMessageInsertedBeforeTheLastLine() {
        // The bouncer's clock runs ahead: local echo sorts before the newest line.
        var lines = [line("a", 0), line("b", 10)]
        var tracker = LineTracker(lines: lines)
        lines.insert(line("me", 9, isSelf: true), at: 1)
        let change = tracker.update(lines)
        #expect(change.sentMessage)
        #expect(change.appended == 0)
        #expect(change.inserted == 1)
    }

    @Test func historyInsertedAboveIsNotNew() {
        var lines = [line("a", 100), line("b", 101)]
        var tracker = LineTracker(lines: lines)
        lines.insert(contentsOf: [line("old", 1), line("old", 2)], at: 0)
        let change = tracker.update(lines)
        #expect(change.appended == 0)
        #expect(change.newFromOthers == 0)
        #expect(change.inserted == 2)
    }

    @Test func signatureNoticesAppendsInsertionsAndTrims() {
        let lines = [line("a", 0), line("b", 1), line("c", 2)]
        let base = LinesSignature(lines)
        #expect(LinesSignature(lines + [line("d", 3)]) != base)
        #expect(LinesSignature([line("z", -1)] + lines) != base)
        #expect(LinesSignature(Array(lines.dropFirst())) != base)
        #expect(LinesSignature(lines) == base)
    }
}

@Suite("Settling at the bottom")
struct BottomSettleTests {
    /// Checks every `every` seconds, never at the bottom, until the settle
    /// gives up; returns the anchors it scrolled with.
    private func tries(every waited: TimeInterval, settle: inout BottomSettle) -> [CGFloat] {
        var anchors: [CGFloat] = []
        for _ in 0..<10_000 {
            switch settle.check(waited: waited, otherScrollUnderWay: false, atBottom: false) {
            case .scroll(let anchor): anchors.append(anchor)
            case .wait: continue
            case .done: return anchors
            }
        }
        Issue.record("never gave up")
        return anchors
    }

    @Test func stopsOnceAtTheBottom() {
        var settle = BottomSettle()
        #expect(settle.check(waited: 0.03, otherScrollUnderWay: false, atBottom: true) == .done(settleBack: false))
        // Got there on a try with another anchor: back on `.bottom`.
        var nudged = BottomSettle()
        guard case .scroll(let anchor) = nudged.check(waited: 0.03, otherScrollUnderWay: false, atBottom: false) else {
            Issue.record("didn't scroll")
            return
        }
        #expect(anchor != 1)
        #expect(nudged.check(waited: 0.03, otherScrollUnderWay: false, atBottom: true) == .done(settleBack: true))
    }

    /// Time, not a count of tries: checks every 30 ms keep going for the
    /// whole budget, each try with an anchor other than the last.
    @Test func keepsTryingForTheBudget() {
        var settle = BottomSettle()
        let anchors = tries(every: BottomSettle.interval, settle: &settle)
        let inBudget = anchors.count - BottomSettle.lateTries.count
        #expect(Double(inBudget) * BottomSettle.interval >= BottomSettle.budget - BottomSettle.interval)
        #expect(zip([1] + anchors, anchors).allSatisfy { $0 != $1 })
        #expect(anchors.allSatisfy { abs($0 - 1) < 0.001 })
    }

    /// A busy main actor delays every check by half a second: the budget
    /// runs out in time, but not before the minimum number of tries.
    @Test func aBusyMainActorStillGetsItsTries() {
        var settle = BottomSettle()
        let anchors = tries(every: 0.5, settle: &settle)
        #expect(anchors.count == BottomSettle.minimumTries + BottomSettle.lateTries.count)
    }

    /// Time while another scroll or animation runs doesn't count.
    @Test func otherScrollsDontUseTheBudget() {
        var settle = BottomSettle()
        for _ in 0..<500 {
            #expect(settle.check(waited: 0.03, otherScrollUnderWay: true, atBottom: false) == .wait)
        }
        #expect(settle.spent == 0)
        #expect(settle.tries == 0)
        #expect(settle.wait == BottomSettle.interval)
        guard case .scroll = settle.check(waited: 0.03, otherScrollUnderWay: false, atBottom: false) else {
            Issue.record("didn't scroll once the other scroll ended")
            return
        }
    }

    /// Once the budget is spent: a few tries further apart, then it stops.
    @Test func lateTriesThenStops() {
        var settle = BottomSettle()
        while settle.wait == BottomSettle.interval {
            _ = settle.check(waited: BottomSettle.interval, otherScrollUnderWay: false, atBottom: false)
        }
        var waits: [TimeInterval] = []
        var step = BottomSettle.Step.wait
        repeat {
            waits.append(settle.wait)
            step = settle.check(waited: settle.wait, otherScrollUnderWay: false, atBottom: false)
        } while step != .done(settleBack: true) && step != .done(settleBack: false)
        #expect(Array(waits.prefix(BottomSettle.lateTries.count)) == BottomSettle.lateTries)
        #expect(settle.lateTriesMade == BottomSettle.lateTries.count)
    }
}
