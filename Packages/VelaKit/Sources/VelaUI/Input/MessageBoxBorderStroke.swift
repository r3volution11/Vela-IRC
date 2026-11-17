// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import VelaStore
import VelaTheme

/// The line around the message box: a theme token and a width.
nonisolated struct MessageBoxBorderStroke: Equatable {
    let token: String
    let width: CGFloat

    /// The quiet line: `input.border`, 1 pt.
    static let quiet = MessageBoxBorderStroke(token: ThemeKey.inputBorder, width: 1)
    /// While typing with the accent style: `input.focusBorder`, 1.5 pt.
    static let focused = MessageBoxBorderStroke(token: ThemeKey.inputFocusBorder, width: 1.5)
}

extension MessageBoxBorder {
    /// The stroke to draw, or nil for no border.
    func stroke(isFocused: Bool) -> MessageBoxBorderStroke? {
        switch self {
        case .none: nil
        case .subtle: .quiet
        case .accent: isFocused ? .focused : .quiet
        }
    }

    /// Whether focusing the field changes the border, so the change is
    /// worth animating.
    var changesWithFocus: Bool {
        stroke(isFocused: true) != stroke(isFocused: false)
    }
}
