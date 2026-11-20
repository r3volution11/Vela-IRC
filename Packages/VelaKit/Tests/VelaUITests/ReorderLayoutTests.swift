// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Testing
@testable import VelaUI

@Suite("Reorder layout")
struct ReorderLayoutTests {
    /// Four 20pt rows with 2pt gaps: a 0…20, b 22…42, c 44…64, d 66…86.
    private let layout = ReorderLayout(
        ids: ["a", "b", "c", "d"],
        spans: ["a": 0...20, "b": 22...42, "c": 44...64, "d": 66...86]
    )

    @Test func landsPastEverySiblingWhoseMiddleItsEdgeCrosses() {
        #expect(layout.proposedIndex(for: "a", translation: 0) == 0)
        #expect(layout.proposedIndex(for: "a", translation: 11) == 0)   // trailing edge 31: not past b's middle (32)
        #expect(layout.proposedIndex(for: "a", translation: 13) == 1)
        #expect(layout.proposedIndex(for: "a", translation: 70) == 3)
        #expect(layout.proposedIndex(for: "d", translation: -70) == 0)
        #expect(layout.proposedIndex(for: "c", translation: -11) == 2)  // leading edge 33: not past b's middle
        #expect(layout.proposedIndex(for: "c", translation: -13) == 1)
    }

    @Test func aWiderItemStillReachesBothEnds() {
        // A wide tab between two narrow ones: held at the ends, its middle
        // never gets past theirs, but its edges do.
        let tabs = ReorderLayout(ids: [1, 2, 3], spans: [1: 0...30, 2: 34...134, 3: 138...168])
        let front = tabs.clampedTranslation(-500, for: 2)
        let back = tabs.clampedTranslation(500, for: 2)
        #expect(front == -34)
        #expect(back == 34)
        #expect(tabs.proposedIndex(for: 2, translation: front) == 0)
        #expect(tabs.proposedIndex(for: 2, translation: back) == 2)

        // The wide one last: it reaches the front, and passes its neighbor
        // as soon as its leading edge crosses that one's middle.
        let last = ReorderLayout(ids: [1, 3, 2], spans: [1: 0...30, 3: 34...64, 2: 68...168])
        #expect(last.proposedIndex(for: 2, translation: last.clampedTranslation(-500, for: 2)) == 0)
        #expect(last.proposedIndex(for: 2, translation: -20) == 1)       // leading edge 48: past 3's middle (49)
        #expect(last.proposedIndex(for: 2, translation: -18) == 2)
    }

    @Test func siblingsShiftByTheDraggedLengthAndGap() {
        // a → index 2: b and c slide up by 22.
        #expect(layout.offset(of: "b", dragging: "a", to: 2) == -22)
        #expect(layout.offset(of: "c", dragging: "a", to: 2) == -22)
        #expect(layout.offset(of: "d", dragging: "a", to: 2) == 0)
        // d → index 1: b and c slide down; the last row uses the gap before it.
        #expect(layout.offset(of: "a", dragging: "d", to: 1) == 0)
        #expect(layout.offset(of: "b", dragging: "d", to: 1) == 22)
        #expect(layout.offset(of: "c", dragging: "d", to: 1) == 22)
        // The dragged item itself follows the pointer, not this.
        #expect(layout.offset(of: "a", dragging: "a", to: 2) == 0)
    }

    @Test func draggedItemStaysWithinTheSiblings() {
        #expect(layout.clampedTranslation(-50, for: "a") == 0)
        #expect(layout.clampedTranslation(200, for: "a") == 66)
        #expect(layout.clampedTranslation(-200, for: "d") == -66)
    }

    @Test func siblingsNotLaidOutYetKeepTheirSide() {
        // a hasn't been measured (scrolled away in a lazy stack): it stays before c.
        let partial = ReorderLayout(ids: ["a", "b", "c"], spans: ["b": 22...42, "c": 44...64])
        #expect(partial.proposedIndex(for: "c", translation: 0) == 2)
        #expect(partial.proposedIndex(for: "c", translation: -23) == 1)
    }

    @Test func droppedItemGlidesExactlyIntoItsNewSlot() {
        // a → index 2: it ends against c's far edge (c moves up by a's 22).
        #expect(layout.finalOffset(of: "a", to: 2) == 44)
        // d → index 1: it takes b's place.
        #expect(layout.finalOffset(of: "d", to: 1) == -44)
        #expect(layout.finalOffset(of: "b", to: 1) == nil)

        // Variable widths: tab 1 (80 wide) after tab 3 lands at 228 - 80.
        let tabs = ReorderLayout(ids: [1, 2, 3], spans: [1: 0...80, 2: 84...124, 3: 128...228])
        #expect(tabs.finalOffset(of: 1, to: 2) == 148)
        #expect(tabs.finalOffset(of: 3, to: 0) == -128)

        // Sidebar sections: the first has a smaller top inset (2) than the
        // rest (10), so it swaps with the next. The offsets still land
        // where the new layout puts each one.
        let sections = ReorderLayout(ids: ["A", "B"], spans: ["A": 2...42, "B": 53...83])
        #expect(sections.finalOffset(of: "A", to: 1) == 41)   // new top: 2 + 30 + 1 + 10 = 43
        #expect(sections.offset(of: "B", dragging: "A", to: 1) == -51)   // new top: 2
    }

    @Test func variableWidthTabs() {
        // Tabs 0…80, 84…124, 128…228 (4pt gaps).
        let tabs = ReorderLayout(ids: [1, 2, 3], spans: [1: 0...80, 2: 84...124, 3: 128...228])
        #expect(tabs.proposedIndex(for: 1, translation: 23) == 0)       // trailing edge 103 < 104
        #expect(tabs.proposedIndex(for: 1, translation: 25) == 1)       // 105 > 104
        #expect(tabs.offset(of: 2, dragging: 1, to: 1) == -84)
        #expect(tabs.proposedIndex(for: 3, translation: -23) == 2)      // leading edge 105 > 104
        #expect(tabs.proposedIndex(for: 3, translation: -25) == 1)      // 103 < 104
        #expect(tabs.offset(of: 2, dragging: 3, to: 1) == 104)
    }
}
