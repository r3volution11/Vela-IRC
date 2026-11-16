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

extension View {
    /// Keeps drags that start on this view from moving the window.
    ///
    /// macOS moves a window itself, in the window server, when a drag
    /// starts in the title bar's drag region, before the app gets a say.
    /// SwiftUI content laid out there doesn't carve itself out of that
    /// region, so a drag that starts on a tab (to reorder it) is taken over
    /// and moves the window. While the pointer is over this view the window
    /// isn't movable, which empties the region; a press here then belongs
    /// to the view. Elsewhere the title bar still moves the window. Clicks
    /// and hover reach the view as usual.
    func excludedFromWindowDragRegion() -> some View {
        background(WindowDragExclusion())
    }
}

/// An empty AppKit view that tracks the pointer over its area and lets
/// every event through to the SwiftUI content.
private struct WindowDragExclusion: NSViewRepresentable {
    final class ExclusionView: NSView {
        private var isInside = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) { setInside(true) }
        override func mouseExited(with event: NSEvent) { setInside(false) }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            // Removed (a tab closed) while under the pointer: no exit comes.
            setInside(false)
            super.viewWillMove(toWindow: newWindow)
        }

        private func setInside(_ inside: Bool) {
            guard inside != isInside, let window else { return }
            isInside = inside
            if inside { TitleBarDragGuard.enter(window) } else { TitleBarDragGuard.leave(window) }
        }
    }

    func makeNSView(context: Context) -> ExclusionView {
        let view = ExclusionView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: ExclusionView, context: Context) {}
}

/// Counts the excluded views under the pointer per window (moving between
/// adjacent tabs can report the enter before the exit), and keeps the
/// window unmovable while there's any.
@MainActor
private enum TitleBarDragGuard {
    private static var counts: [ObjectIdentifier: Int] = [:]

    static func enter(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        counts[id, default: 0] += 1
        if counts[id] == 1 { window.isMovable = false }
    }

    static func leave(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard let count = counts[id], count > 0 else { return }
        if count == 1 {
            counts[id] = nil
            window.isMovable = true
        } else {
            counts[id] = count - 1
        }
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
