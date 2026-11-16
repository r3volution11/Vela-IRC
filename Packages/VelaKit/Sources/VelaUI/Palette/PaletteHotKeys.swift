// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

/// ⌘K, the alternate shortcut for "Go to Conversation…" (⌘P in the Go menu).
///
/// A menu item carries one key equivalent and SwiftUI has no hidden menu
/// items, so a local key monitor forwards ⌘K to the ⌘P menu item. Going
/// through the menu keeps a single code path (and its enabled state).
/// Left alone while a sheet or modal panel is up.
enum PaletteHotKeys {
    private static var monitor: Any?

    static func installIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) } ? nil : event
        }
    }

    /// Whether the event was ⌘K and was forwarded.
    private static func handle(_ event: NSEvent) -> Bool {
        let alternate = VelaCommandCatalog.Shortcuts.goToConversationAlternate
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == .command,
              event.charactersIgnoringModifiers?.lowercased() == String(alternate.key.character),
              NSApp.modalWindow == nil,
              let window = event.window,
              window.attachedSheet == nil,
              window.sheetParent == nil,
              let (menu, index) = menuItem(matching: VelaCommandCatalog.Shortcuts.goToConversation),
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

private extension NSEvent.ModifierFlags {
    init(_ modifiers: EventModifiers) {
        self = []
        if modifiers.contains(.command) { insert(.command) }
        if modifiers.contains(.shift) { insert(.shift) }
        if modifiers.contains(.option) { insert(.option) }
        if modifiers.contains(.control) { insert(.control) }
    }
}
