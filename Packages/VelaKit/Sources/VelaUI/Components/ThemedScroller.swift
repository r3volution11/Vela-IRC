// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaTheme

/// A vertical scroller whose thumb is drawn in `scrollbar.thumb`
/// (`scrollbar.thumbHover` under the pointer or while dragged) on a clear
/// track. Everything else is AppKit's: overlay or always-visible scroll bars
/// per System Settings, fading, expanding on hover, paging clicks.
final class ThemedScroller: NSScroller {
    var thumbColor: NSColor = .tertiaryLabelColor {
        didSet { if thumbColor != oldValue { needsDisplay = true } }
    }
    var thumbHoverColor: NSColor = .secondaryLabelColor {
        didSet { if thumbHoverColor != oldValue { needsDisplay = true } }
    }

    private var isHovering = false {
        didSet { if isHovering != oldValue { needsDisplay = true } }
    }
    private var isDraggingKnob = false

    /// Without this, AppKit falls back to always-visible scroll bars for a
    /// subclass that draws its own parts.
    override class var isCompatibleWithOverlayScrollers: Bool { self == ThemedScroller.self }

    /// The thumb colors for a theme: `scrollbar.thumb`, and
    /// `scrollbar.thumbHover` under the pointer or while dragged.
    static func thumbColor(in theme: ResolvedTheme, isHovering: Bool) -> ThemeColor {
        theme.color(isHovering ? ThemeKey.scrollbarThumbHover : ThemeKey.scrollbarThumb)
    }

    func apply(_ theme: ResolvedTheme) {
        thumbColor = Self.thumbColor(in: theme, isHovering: false).nsColor
        thumbHoverColor = Self.thumbColor(in: theme, isHovering: true).nsColor
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // A clear track: the surface under the scroll view shows through.
    }

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.width > 0, knob.height > 0 else { return }
        let vertical = bounds.height >= bounds.width
        let expanded = isHovering || isDraggingKnob || scrollerStyle == .legacy
        let thickness: CGFloat = expanded ? min(9, (vertical ? knob.width : knob.height) - 4) : min(6, (vertical ? knob.width : knob.height) - 4)
        let trailingInset: CGFloat = 3
        let rect: NSRect = vertical
            ? NSRect(x: knob.maxX - trailingInset - thickness, y: knob.minY + 2, width: thickness, height: max(thickness, knob.height - 4))
            : NSRect(x: knob.minX + 2, y: knob.maxY - trailingInset - thickness, width: max(thickness, knob.width - 4), height: thickness)
        let path = NSBezierPath(roundedRect: rect, xRadius: thickness / 2, yRadius: thickness / 2)
        (isHovering || isDraggingKnob ? thumbHoverColor : thumbColor).setFill()
        path.fill()
    }

    override func trackKnob(with event: NSEvent) {
        isDraggingKnob = true
        needsDisplay = true
        super.trackKnob(with: event)
        isDraggingKnob = false
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self && area.userInfo?["ThemedScroller"] != nil {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: ["ThemedScroller": true]
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
    }
}

extension View {
    /// Gives the enclosing scroll view a `ThemedScroller`. Apply to the
    /// content inside a `ScrollView`.
    func themedScrollers() -> some View {
        background(ThemedScrollerInstaller())
    }
}

/// Finds the `NSScrollView` behind a SwiftUI `ScrollView` (from inside its
/// content) and swaps in a `ThemedScroller`, keeping its colors current.
/// If SwiftUI ever stops using an `NSScrollView`, the scroll bars simply
/// stay the system's.
private struct ThemedScrollerInstaller: NSViewRepresentable {
    @Environment(\.theme) private var theme

    final class ProbeView: NSView {
        var theme: ResolvedTheme?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }

        func install() {
            guard let theme, let scrollView = enclosingScrollView else { return }
            let scroller: ThemedScroller
            if let existing = scrollView.verticalScroller as? ThemedScroller {
                scroller = existing
            } else {
                scroller = ThemedScroller()
                scroller.controlSize = scrollView.verticalScroller?.controlSize ?? .regular
                scrollView.verticalScroller = scroller
                scroller.scrollerStyle = scrollView.scrollerStyle
            }
            scroller.apply(theme)
        }
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.theme = theme
        view.install()
    }
}
