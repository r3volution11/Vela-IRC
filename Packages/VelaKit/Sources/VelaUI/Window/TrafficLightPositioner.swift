// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

/// How the window's close/minimize/zoom buttons are arranged.
enum TrafficLightLayout: Equatable {
    /// Side by side, vertically centered in a title strip of `stripHeight`.
    case horizontal(stripHeight: CGFloat)
    /// Stacked top to bottom, centered in a column `columnWidth` wide
    /// (used when the sidebar is collapsed to its narrow rail).
    case vertical(columnWidth: CGFloat)

    /// Height of the area the stacked buttons occupy, so the rail can keep
    /// its content below them.
    static let verticalStackHeight: CGFloat = 86
}

/// Repositions the real (native) traffic-light buttons rather than drawing
/// replacements, so hover glyphs, the inactive-window look and the green
/// button's tiling menu keep working. AppKit re-lays out the title bar on
/// resize, key changes and full-screen transitions, so the layout is
/// re-applied whenever that happens.
@MainActor
final class TrafficLightPositioner {
    private weak var window: NSWindow?
    private var layout: TrafficLightLayout = .horizontal(stripHeight: 52)
    private var observers: [NSObjectProtocol] = []
    private var isApplying = false
    private var originalLeading: CGFloat?
    private var originalSpacing: CGFloat?

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didChangeScreenNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            })
        }
        for button in buttons {
            button.postsFrameChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: button, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            })
        }
        if let container = titlebarContainer {
            container.postsFrameChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: container, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            })
        }
        apply()
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    func update(_ newLayout: TrafficLightLayout) {
        guard newLayout != layout else { return }
        layout = newLayout
        apply()
    }

    // MARK: Layout

    private var buttons: [NSButton] {
        guard let window else { return [] }
        return [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
    }

    private var titlebarView: NSView? { buttons.first?.superview }
    private var titlebarContainer: NSView? { titlebarView?.superview }

    private func apply() {
        guard !isApplying, let window, !window.styleMask.contains(.fullScreen) else { return }
        let buttons = self.buttons
        guard buttons.count == 3, let titlebarView, let container = titlebarContainer, let frameView = container.superview else { return }
        isApplying = true
        defer { isApplying = false }

        // Learn the system's horizontal metrics once, from its own layout.
        if originalLeading == nil {
            originalLeading = buttons[0].frame.minX
            originalSpacing = buttons[1].frame.minX - buttons[0].frame.maxX
        }
        let leading = originalLeading ?? 20
        let spacing = max(6, originalSpacing ?? 8)
        let size = buttons[0].frame.size

        // Keep the title-bar container no larger than the buttons need, so it
        // never sits over (and swallows clicks meant for) the header, tabs or
        // the top of the message list. Dragging elsewhere is handled by the
        // SwiftUI title strips.
        let containerHeight: CGFloat
        let containerWidth: CGFloat
        let origins: [CGPoint]
        switch layout {
        case .horizontal(let stripHeight):
            containerHeight = stripHeight
            containerWidth = leading * 2 + size.width * 3 + spacing * 2
            let y = ((stripHeight - size.height) / 2).rounded()
            origins = (0..<3).map { index in
                CGPoint(x: leading + CGFloat(index) * (size.width + spacing), y: y)
            }
        case .vertical(let columnWidth):
            containerHeight = TrafficLightLayout.verticalStackHeight
            containerWidth = columnWidth
            let x = ((columnWidth - size.width) / 2).rounded()
            let gap = spacing + 3
            let top: CGFloat = 18
            origins = (0..<3).map { index in
                // Title bar views aren't flipped: y counts up from the bottom.
                let fromTop = top + CGFloat(index) * (size.height + gap)
                return CGPoint(x: x, y: containerHeight - fromTop - size.height)
            }
        }

        let containerFrame = NSRect(
            x: 0,
            y: frameView.bounds.height - containerHeight,
            width: containerWidth,
            height: containerHeight
        )
        if container.frame != containerFrame { container.frame = containerFrame }
        if titlebarView.frame != container.bounds { titlebarView.frame = container.bounds }
        for (button, origin) in zip(buttons, origins) where button.frame.origin != origin {
            button.setFrameOrigin(origin)
        }
    }
}
