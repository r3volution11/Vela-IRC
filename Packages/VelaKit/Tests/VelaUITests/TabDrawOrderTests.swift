// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import VelaUI

@Suite("Tab draw order")
struct TabDrawOrderTests {
    /// Console, three channels, two queries; channels move among channels.
    private let tabs = ["console", "#a", "#b", "#c", "alice", "bob"]
    private let channels = ["#a", "#b", "#c"]

    private func channelOrder(dragging dragged: String, to target: Int) -> [String] {
        TabDrawOrder.order(tabs, siblings: channels, dragged: dragged, target: target) { id in
            channels.contains(id) ? id : nil
        }
    }

    @Test func draggedTabTakesItsProposedSlotAmongItsSiblings() {
        #expect(channelOrder(dragging: "#a", to: 0) == tabs)
        #expect(channelOrder(dragging: "#a", to: 2) == ["console", "#b", "#c", "#a", "alice", "bob"])
        #expect(channelOrder(dragging: "#c", to: 0) == ["console", "#c", "#a", "#b", "alice", "bob"])
        // Out of range clamps, like the model.
        #expect(channelOrder(dragging: "#b", to: 9) == ["console", "#a", "#c", "#b", "alice", "bob"])
    }

    @Test func aBouncerMovesWithItsNetworks() {
        // Standalone A, bouncer B with networks b1 and b2, standalone C.
        let ids = ["A", "B", "b1", "b2", "C"]
        let parents = ["b1": "B", "b2": "B"]
        let topLevel = ["A", "B", "C"]
        func owner(_ id: String) -> String? {
            topLevel.contains(id) ? id : parents[id].flatMap { topLevel.contains($0) ? $0 : nil }
        }
        #expect(TabDrawOrder.order(ids, siblings: topLevel, dragged: "B", target: 2, owner: owner) == ["A", "C", "B", "b1", "b2"])
        #expect(TabDrawOrder.order(ids, siblings: topLevel, dragged: "C", target: 0, owner: owner) == ["C", "A", "B", "b1", "b2"])

        // A bouncer's networks move among themselves.
        let children = ["b1", "b2"]
        let childOrder = TabDrawOrder.order(ids, siblings: children, dragged: "b1", target: 1) { id in
            children.contains(id) ? id : nil
        }
        #expect(childOrder == ["A", "B", "b2", "b1", "C"])
    }

    @Test func separatorsSitBetweenPlainTabsAsDrawn() {
        // #a dragged past #b: drawn console, #b, #a, #c.
        let drawn = channelOrder(dragging: "#a", to: 1)
        let separated = TabDrawOrder.separated(drawn) { $0 != "#a" && $0 != "bob" }
        // None next to the dragged tab, none after the last tab.
        #expect(separated == ["console", "#c"])
    }
}
