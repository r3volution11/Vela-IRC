// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

/// Hands the `NSScrollView` behind the message list's `ScrollView` to
/// `found`, from inside its content, once it's in a window.
struct ListScrollViewProbe: NSViewRepresentable {
    let found: (NSScrollView) -> Void

    final class ProbeView: NSView {
        var found: ((NSScrollView) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, let scrollView = enclosingScrollView { found?(scrollView) }
        }
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.setAccessibilityElement(false)
        view.found = found
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {}
}
