// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Testing
@testable import VelaUI

@Suite("Space under the last message")
struct ListEndSpacingTests {
    @Test func nobodyTypingLeavesOnlyBreathingRoom() {
        // Was 30pt: a 12pt spacer plus an 18pt typing line kept even when empty.
        #expect(ListEndSpacing.height(typingLine: nil) == ListEndSpacing.resting)
        #expect(ListEndSpacing.resting >= 6 && ListEndSpacing.resting <= 12)
        // Not measured yet: no room to make.
        #expect(ListEndSpacing.height(typingLine: 0) == ListEndSpacing.resting)
    }

    @Test func typingLineGetsItsWholeHeight() {
        // The line floats over the list, so the room must cover all of it.
        #expect(ListEndSpacing.height(typingLine: 23) == 23)
        #expect(ListEndSpacing.height(typingLine: 22.4) == 23)
        #expect(ListEndSpacing.height(typingLine: 31) == 31)
        // Never less than the resting space.
        #expect(ListEndSpacing.height(typingLine: 4) == ListEndSpacing.resting)
    }

    @Test func riseIsTheExtraRoom() {
        #expect(ListEndSpacing.typingRise(typingLine: 23) == 23 - ListEndSpacing.resting)
        #expect(ListEndSpacing.typingRise(typingLine: 0) == 0)
        #expect(ListEndSpacing.typingRise(typingLine: 4) == 0)
        // Showing then hiding the line returns the list to where it was.
        let shown = ListEndSpacing.height(typingLine: 23)
        #expect(shown - ListEndSpacing.typingRise(typingLine: 23) == ListEndSpacing.height(typingLine: nil))
    }

    @Test func jumpPillClearsTheTypingLine() {
        #expect(ListEndSpacing.pillBottomPadding(typingLine: nil) == ListEndSpacing.pillInset)
        #expect(ListEndSpacing.pillBottomPadding(typingLine: 23) == ListEndSpacing.pillInset + 23)
        #expect(ListEndSpacing.pillBottomPadding(typingLine: -5) == ListEndSpacing.pillInset)
    }
}
