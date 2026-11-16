// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Testing
@testable import VelaUI

@Suite("Sidebar auto-scroll")
struct SidebarAutoScrollTests {
    /// A 400pt-tall visible area: the edge bands are 0…36 and 364…400.
    private func speed(_ pointer: CGFloat, from start: CGFloat, height: CGFloat = 400) -> CGFloat {
        SidebarAutoScroll.speed(pointer: pointer, start: start, height: height)
    }

    @Test func holdsStillAwayFromTheEdges() {
        #expect(speed(200, from: 100) == 0)
        #expect(speed(37, from: 200) == 0)
        #expect(speed(363, from: 200) == 0)
    }

    @Test func scrollsTowardTheEdgeThePointerNears() {
        #expect(speed(380, from: 200) > 0)
        #expect(speed(20, from: 200) < 0)
    }

    @Test func grabbingNearAnEdgeOnlyScrollsOnceThePointerHeadsForIt() {
        // Picked up in the bottom band and moved up: no scrolling down.
        #expect(speed(370, from: 390) == 0)
        #expect(speed(395, from: 390) > 0)
        #expect(speed(10, from: 5) == 0)
    }

    @Test func fasterDeeperInTheBandAndFullSpeedPastTheEdge() {
        #expect(speed(366, from: 0) < speed(398, from: 0))
        #expect(speed(366, from: 0) >= SidebarAutoScroll.speeds.lowerBound)
        #expect(speed(400, from: 0) == SidebarAutoScroll.speeds.upperBound)
        #expect(speed(900, from: 0) == SidebarAutoScroll.speeds.upperBound)
        #expect(speed(-50, from: 100) == -SidebarAutoScroll.speeds.upperBound)
    }

    @Test func shortAreasUseNarrowerBands() {
        // 80pt tall: bands of 20.
        #expect(speed(40, from: 0, height: 80) == 0)
        #expect(speed(70, from: 0, height: 80) > 0)
        #expect(speed(10, from: 40, height: 0) == 0)
    }
}
