// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The parts of the main window the keyboard moves between, in screen
/// order: ⌥⌘1–⌥⌘4 go straight to one, F6 / ⇧F6 go round them.
///
/// Each area takes the focus when `UIState.focusRequest` names it (see
/// `UIState.focus(_:)`), and reports when it gains or loses the focus with
/// `UIState.setFocused(_:_:)`, so F6 knows where it's going from.
public enum FocusArea: Int, CaseIterable, Sendable {
    /// The sidebar (or its rail), or the tab rows.
    case navigation = 1
    /// The selected channel's or conversation's messages.
    case messages
    /// The message box (also ⌘L, through `UIState.focusInput()`).
    case messageBox
    /// The member list, shown first if it's hidden.
    case members
}

/// A request for an area to take the keyboard focus (`UIState.focus(_:)`).
public struct FocusRequest: Equatable, Sendable {
    public let id = UUID()
    public let area: FocusArea

    public init(area: FocusArea) {
        self.area = area
    }
}

enum FocusAreas {
    /// The areas there are to go to: the sidebar or the tabs unless the
    /// window has neither (Focus), the messages and the message box only
    /// with a channel or conversation selected, the member list only while
    /// it's showing.
    static func available(hasBuffer: Bool, showsMembers: Bool, hasNavigation: Bool = true) -> [FocusArea] {
        FocusArea.allCases.filter { area in
            switch area {
            case .navigation: hasNavigation
            case .messages, .messageBox: hasBuffer
            case .members: hasBuffer && showsMembers
            }
        }
    }

    /// F6 / ⇧F6: the area after (or before) `current` among `available`,
    /// wrapping around. From none of them (nil), or from one that isn't
    /// there any more, F6 goes to the first and ⇧F6 to the last.
    static func adjacent(to current: FocusArea?, forward: Bool, in available: [FocusArea]) -> FocusArea? {
        guard !available.isEmpty else { return nil }
        guard let current, let index = available.firstIndex(of: current) else {
            return forward ? available.first : available.last
        }
        return available[(index + (forward ? 1 : -1) + available.count) % available.count]
    }
}
