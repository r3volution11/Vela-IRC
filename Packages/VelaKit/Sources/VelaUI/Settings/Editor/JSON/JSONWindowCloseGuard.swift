// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

/// Holds the Settings window open while the JSON view has unsaved edits,
/// so closing it can ask Save / Discard / Cancel in the view itself.
///
/// While installed, the window's close button and ⌘W call `onCloseAttempt`
/// instead of closing. SwiftUI owns the window's delegate, so rather than
/// replacing it this retargets the close button and watches for ⌘W; it's
/// installed only while there are unsaved edits and the JSON view is in
/// the window, and removed (restoring the button) as soon as either stops.
@MainActor
final class JSONWindowCloseGuard: NSObject {
    private weak var window: NSWindow?
    private weak var originalTarget: AnyObject?
    private var originalAction: Selector?
    private var keyMonitor: Any?
    private let onCloseAttempt: () -> Void

    init(onCloseAttempt: @escaping () -> Void) {
        self.onCloseAttempt = onCloseAttempt
    }

    var isInstalled: Bool { window != nil }

    /// Guards `window` (or nothing, for nil). Re-guarding the same window
    /// does nothing.
    func guardWindow(_ newWindow: NSWindow?) {
        guard newWindow !== window else { return }
        remove()
        guard let newWindow, let button = newWindow.standardWindowButton(.closeButton) else { return }
        window = newWindow
        originalTarget = button.target
        originalAction = button.action
        button.target = self
        button.action = #selector(closeButtonClicked(_:))
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "w"
            else { return event }
            self.onCloseAttempt()
            return nil
        }
    }

    /// Restores the close button and stops watching ⌘W.
    func remove() {
        if let window, let button = window.standardWindowButton(.closeButton), button.target === self {
            button.target = originalTarget ?? window
            button.action = originalAction ?? #selector(NSWindow.performClose(_:))
        }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window = nil
        originalTarget = nil
        originalAction = nil
    }

    /// Closes the guarded window for real (after Save or Discard).
    func closeWindow() {
        guard let window else { return }
        remove()
        window.performClose(nil)
    }

    @objc private func closeButtonClicked(_ sender: Any?) {
        onCloseAttempt()
    }
}
