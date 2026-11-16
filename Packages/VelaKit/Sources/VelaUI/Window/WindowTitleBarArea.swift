// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

extension View {
    /// Makes this view behave like a native title bar: dragging moves the
    /// window and a double-click zooms or minimizes it, following the user's
    /// "Double-click a window's title bar to…" setting in System Settings.
    func windowTitleBarArea() -> some View {
        gesture(WindowDragGesture())
            .simultaneousGesture(TapGesture(count: 2).onEnded { performTitleBarDoubleClick() })
            .allowsWindowActivationEvents(true)
    }
}

@MainActor
private func performTitleBarDoubleClick() {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
    // "Maximize" (zoom, the default), "Minimize" or "None".
    let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
    switch action {
    case "Minimize": window.performMiniaturize(nil)
    case "None": break
    default: window.performZoom(nil)
    }
}
