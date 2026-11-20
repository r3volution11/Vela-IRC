// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore

/// Hands the main window's undo manager to `AppModel`, so leaving or
/// removing a channel and closing a conversation go on the same undo stack
/// as typing in the message box: ⌘Z undoes whatever you did last, as in any
/// Mac app. Also registers the window as a main window (`MainWindows`).
struct WindowUndoManagerBridge: NSViewRepresentable {
    let app: AppModel

    func makeNSView(context: Context) -> BridgeView {
        BridgeView(app: app)
    }

    func updateNSView(_ view: BridgeView, context: Context) {}

    final class BridgeView: NSView {
        private weak var app: AppModel?

        init(app: AppModel) {
            self.app = app
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The window's own, which the message box's text view uses too.
            if let window {
                app?.undoManager = window.undoManager
                MainWindows.register(window)
            }
        }
    }
}
