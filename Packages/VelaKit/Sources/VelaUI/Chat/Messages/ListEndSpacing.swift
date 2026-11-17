// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import SwiftUI

/// The space between the last message and the composer.
///
/// Nobody typing: a little more than the gap between messages. Someone
/// typing: the typing line floats over the bottom of the list (see
/// `TypingIndicatorView`) and the space under the last row grows to its
/// height, so the line never covers a message. While the list is pinned to
/// the bottom the conversation eases up to make that room; when the reader
/// has scrolled up, nothing moves.
nonisolated enum ListEndSpacing {
    /// Under the last row while nobody is typing.
    static let resting: CGFloat = 10
    /// Above the typing text, about the gap between two lines. The line's
    /// background fades in over it.
    static let typingLineTopPadding: CGFloat = 4
    /// Between the typing text and the composer.
    static let typingLineBottomPadding: CGFloat = 5
    /// The Jump to present pill's distance above the list's bottom edge, or
    /// above the typing line.
    static let pillInset: CGFloat = 12

    /// Space after the last row. `typingLine` is the typing line's measured
    /// height while it shows, nil while nobody is typing.
    static func height(typingLine: CGFloat?) -> CGFloat {
        guard let typingLine, typingLine > 0 else { return resting }
        return max(resting, typingLine.rounded(.up))
    }

    /// How much further the typing line takes than the resting space: how
    /// far the conversation moves up (when pinned) as the line appears, and
    /// how far the line rises from below the list's edge as it does.
    static func typingRise(typingLine: CGFloat) -> CGFloat {
        height(typingLine: typingLine) - resting
    }

    /// The Jump to present pill's distance from the list's bottom edge.
    static func pillBottomPadding(typingLine: CGFloat?) -> CGFloat {
        pillInset + max(0, typingLine ?? 0)
    }

    /// How the typing line, and the room for it, come and go.
    static let typingAnimation: Animation = .smooth(duration: 0.24)

    /// How long pinning leaves the list to `typingAnimation` before checking
    /// it ended at the bottom.
    static let typingAnimationSettle: TimeInterval = 0.32
}
