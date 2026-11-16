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

    @Test func landsPastEverySiblingWhoseMiddleItCrosses() {
        #expect(layout.proposedIndex(for: "a", translation: 0) == 0)
        #expect(layout.proposedIndex(for: "a", translation: 21) == 0)   // center 31: not past b's middle (32)
        #expect(layout.proposedIndex(for: "a", translation: 23) == 1)
        #expect(layout.proposedIndex(for: "a", translation: 70) == 3)
        #expect(layout.proposedIndex(for: "d", translation: -70) == 0)
        #expect(layout.proposedIndex(for: "c", translation: -23) == 1)
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

    @Test func variableWidthTabs() {
        // Tabs 0…80, 84…124, 128…228 (4pt gaps).
        let tabs = ReorderLayout(ids: [1, 2, 3], spans: [1: 0...80, 2: 84...124, 3: 128...228])
        #expect(tabs.proposedIndex(for: 1, translation: 70) == 1)       // center 110 > 104
        #expect(tabs.offset(of: 2, dragging: 1, to: 1) == -84)
        #expect(tabs.proposedIndex(for: 3, translation: -75) == 1)      // center 103 < 104
        #expect(tabs.offset(of: 2, dragging: 3, to: 1) == 104)
    }
}
