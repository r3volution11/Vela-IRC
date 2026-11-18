// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

extension View {
    /// Makes the whole view one link, like a link preview: a click anywhere
    /// in it opens `url` (through `openURL`), or runs `action` instead, while
    /// the text inside stays selectable. A drag selects, a double-click
    /// selects a word and a triple-click the line, and none of them opens
    /// anything more. Give the `Text`s inside `.textSelection(.enabled)`.
    ///
    /// The same machinery as links in messages (`LinkPointerText`): a
    /// transparent AppKit view over this one shows the pointing hand and
    /// lets every click through to what's underneath, and `LinkClickMonitor`
    /// acts on a click: pressed and released in place, not Shift or Control.
    ///
    /// Controls inside (a button, a blurred image's Click to show) mark
    /// themselves `.outsideLinkClickArea()` and keep their own clicks, pointer
    /// and help. Put hover effects (`.onHover`), `.help` and the context menu
    /// on this view, outside the modifier: the views under the AppKit view
    /// don't see the pointer.
    func linkClickArea(_ url: URL, perform action: (() -> Void)? = nil) -> some View {
        modifier(LinkClickAreaModifier(url: url, action: action))
    }

    /// Leaves this view (a control of its own) out of a `linkClickArea`
    /// around it: clicking it doesn't open the link, and it keeps its own
    /// pointer, hover and help.
    func outsideLinkClickArea() -> some View {
        anchorPreference(key: LinkClickAreaExclusions.self, value: .bounds) { [$0] }
    }
}

/// The bounds of the views marked `.outsideLinkClickArea()`.
private struct LinkClickAreaExclusions: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

private struct LinkClickAreaModifier: ViewModifier {
    let url: URL
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(LinkClickAreaExclusions.self) { excluded in
            GeometryReader { proxy in
                LinkClickAreaRegion(url: url, excluded: excluded.map { proxy[$0] }, action: action)
                    .pointerStyle(.link)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The transparent AppKit view over a `linkClickArea`: one link covering it.
private struct LinkClickAreaRegion: NSViewRepresentable {
    let url: URL
    /// In the view's own (top-left origin) coordinates.
    let excluded: [CGRect]
    let action: (() -> Void)?

    func makeNSView(context: Context) -> LinkPointerRegionView {
        let view = LinkPointerRegionView(regions: LinkRegions())
        view.coversBounds = true
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: LinkPointerRegionView, context: Context) {
        view.urls = [url]
        view.excluded = excluded
        if let action {
            view.open = { _ in action() }
        } else {
            let openURL = context.environment.openURL
            view.open = { openURL($0) }
        }
    }
}
