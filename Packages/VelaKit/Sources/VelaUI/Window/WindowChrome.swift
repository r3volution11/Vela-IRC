// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

/// The window chrome Vela's themed windows share: a transparent, title-less
/// title bar over full-size content, the theme's background and light or
/// dark appearance for system-drawn controls.
///
/// Called from `updateNSView`, which runs on every SwiftUI update of the
/// hosting view, sometimes in the middle of an AppKit layout pass. Setting a
/// window property there can make AppKit lay the window out again, so only
/// properties that differ are written.
@MainActor
enum WindowChrome {
    static func apply(
        to window: NSWindow,
        title: String? = nil,
        backgroundColor: NSColor,
        isOpaque: Bool = true,
        appearanceName: NSAppearance.Name,
        resizable: Bool = false
    ) {
        if let title, window.title != title { window.title = title }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        var styleMask = window.styleMask
        styleMask.insert(.fullSizeContentView)
        if resizable { styleMask.insert(.resizable) }
        if styleMask != window.styleMask { window.styleMask = styleMask }
        if window.isOpaque != isOpaque { window.isOpaque = isOpaque }
        if window.backgroundColor != backgroundColor { window.backgroundColor = backgroundColor }
        if window.appearance?.name != appearanceName { window.appearance = NSAppearance(named: appearanceName) }
        if window.tabbingMode != .disallowed { window.tabbingMode = .disallowed }
    }
}
