// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

/// Second shortcuts for menu commands: ⌘K for Go to Conversation… (⌘P),
/// and ⌃Tab / ⌃⇧Tab for Next and Previous Tab (⇧⌘] / ⇧⌘[), as in Safari.
///
/// A menu item carries one key equivalent and SwiftUI has no hidden menu
/// items, so a local key monitor forwards each alternate to its command's
/// menu item. Going through the menu keeps a single code path (and its
/// enabled state). Left alone while a sheet or modal panel is up.
enum AlternateShortcuts {
    private static var monitor: Any?

    private struct Alternate {
        /// Matches the pressed keys.
        let matches: (NSEvent) -> Bool
        /// The menu item's shortcut.
        let primary: KeyboardShortcut
        /// Only in the main window: elsewhere (Settings) ⌃Tab moves the
        /// keyboard focus, as it does in any Mac window.
        var mainWindowOnly = false
    }

    private static let alternates: [Alternate] = {
        typealias Shortcuts = VelaCommandCatalog.Shortcuts
        return [
            Alternate(
                matches: { $0.modifiers == .command && $0.charactersIgnoringModifiers?.lowercased() == "k" },
                primary: Shortcuts.goToConversation
            ),
            Alternate(
                matches: { $0.keyCode == tabKeyCode && $0.modifiers == .control },
                primary: Shortcuts.nextTab,
                mainWindowOnly: true
            ),
            Alternate(
                matches: { $0.keyCode == tabKeyCode && $0.modifiers == [.control, .shift] },
                primary: Shortcuts.previousTab,
                mainWindowOnly: true
            ),
        ]
    }()

    /// Tab, wherever the keyboard layout puts its other keys.
    private static let tabKeyCode: UInt16 = 48

    static func installIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) } ? nil : event
        }
    }

    /// Whether the event was an alternate and was forwarded.
    private static func handle(_ event: NSEvent) -> Bool {
        guard let alternate = alternates.first(where: { $0.matches(event) }),
              NSApp.modalWindow == nil,
              let window = event.window,
              window.attachedSheet == nil,
              window.sheetParent == nil,
              !alternate.mainWindowOnly || MainWindows.contains(window),
              let (menu, index) = menuItem(matching: alternate.primary),
              menu.items[index].isEnabled
        else { return false }
        menu.performActionForItem(at: index)
        return true
    }

    private static func menuItem(matching shortcut: KeyboardShortcut) -> (NSMenu, Int)? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        let key = String(shortcut.key.character)
        let mask = NSEvent.ModifierFlags(shortcut.modifiers)
        func search(_ menu: NSMenu) -> (NSMenu, Int)? {
            for (index, item) in menu.items.enumerated() {
                if item.keyEquivalent == key,
                   item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]) == mask {
                    return (menu, index)
                }
                if let submenu = item.submenu, let found = search(submenu) { return found }
            }
            return nil
        }
        return search(mainMenu)
    }
}

/// Vela's main windows, as opposed to Settings, the theme editor and the
/// other windows (registered by `WindowUndoManagerBridge`).
@MainActor
enum MainWindows {
    private static let windows = NSHashTable<NSWindow>.weakObjects()

    static func register(_ window: NSWindow) {
        windows.add(window)
    }

    static func contains(_ window: NSWindow) -> Bool {
        windows.contains(window)
    }
}

private extension NSEvent {
    /// The modifier keys held, without caps lock, fn and the like.
    var modifiers: NSEvent.ModifierFlags {
        modifierFlags.intersection([.command, .shift, .option, .control])
    }
}

private extension NSEvent.ModifierFlags {
    init(_ modifiers: EventModifiers) {
        self = []
        if modifiers.contains(.command) { insert(.command) }
        if modifiers.contains(.shift) { insert(.shift) }
        if modifiers.contains(.option) { insert(.option) }
        if modifiers.contains(.control) { insert(.control) }
    }
}
