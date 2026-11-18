// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaStore

/// Where the message list lands when it opens, and what coming back to
/// Vela does to it, following `chat.openAt`. Pure, so it's tested without
/// views.
///
/// - **First unread** (the default): a list with unread lines opens at the
///   New line (or, with the line hidden, at the first unread row) a little
///   below the top, and "Jump to present" takes the reader down; one with
///   nothing unread opens at the newest line. Coming back to Vela leaves
///   the list where it is.
/// - **Newest**: every list opens at the bottom and stays pinned there, so
///   there's nothing to scroll down to and no pill. Coming back to Vela
///   keeps it at the newest line. A reader who scrolled up themselves keeps
///   their place, and the pill counts what arrived meanwhile, like irssi's
///   "-- more --": scrolling up is the only thing that unpins the list.
///
/// Either way, a Catch me up card asked for from a channel's menu or the
/// palette is brought into view.
nonisolated enum ListLanding: Equatable, Sendable {
    /// Settle on the newest line, pinned. The bottom the list starts at is
    /// worked out from estimated row heights, and in a long channel with
    /// media it can be past the last row, showing nothing; so it's scrolled
    /// to for real (`MessageListView.scrollToBottom`).
    case bottom
    /// This row (the New line, or the first unread row) near the top.
    case unread(DisplayItemID)
    /// The Catch me up card that was asked for.
    case catchUpCard
    /// Leave the list where it is (coming back to Vela).
    case stay

    /// Where a list opens: selecting a channel, launching Vela, reopening
    /// the window.
    ///
    /// - Parameters:
    ///   - revealsCatchUpCard: A Catch me up card for this buffer is waiting
    ///     to be shown (opened from a context menu or the palette).
    ///   - unreadTarget: Where the unread lines start
    ///     (``unreadTarget(in:after:)``); nil when nothing's unread, and the
    ///     list opens at the newest line.
    static func onOpen(openAt: ChatOpenPosition, revealsCatchUpCard: Bool, unreadTarget: DisplayItemID?) -> ListLanding {
        if revealsCatchUpCard { return .catchUpCard }
        guard let unreadTarget else { return .bottom }
        return openAt == .firstUnread ? .unread(unreadTarget) : .bottom
    }

    /// The window became active again. With Newest, a list that's following
    /// the bottom settles on the newest line; one the reader scrolled up
    /// stays put.
    static func onWindowActivated(openAt: ChatOpenPosition, isPinned: Bool, isUserScrolling: Bool) -> ListLanding {
        guard openAt == .newest, isPinned, !isUserScrolling else { return .stay }
        return .bottom
    }

    /// Where the unread lines start: the New line when it's drawn,
    /// otherwise the first row newer than the read position `marker`
    /// (`BufferModel.unreadMarkerAfter`). Nil when nothing's unread.
    static func unreadTarget(in items: DisplayItems, after marker: Date?) -> DisplayItemID? {
        guard let marker else { return nil }
        if items.contains(id: .unreadMarker) { return .unreadMarker }
        return items.firstItem(after: marker)
    }
}
