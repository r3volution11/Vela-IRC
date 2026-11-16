// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// One user-invokable action, shared by the menu bar and the command palette
/// so their titles, shortcuts and enabled states never drift apart.
///
/// Commands are cheap values built on demand by ``VelaCommandCatalog``; a
/// menu builds the few it shows, the palette builds them all when it opens.
struct VelaCommand: Identifiable {
    /// Stable identifier (`"view.toggleMemberList"`), used for the palette's
    /// recently-used list. Per-network commands append the network's id.
    let id: String
    let category: Category
    /// The palette title without its category, VS Code style:
    /// `"Toggle Member List"` is shown as "View: Toggle Member List".
    let title: String
    /// The menu bar title, when it differs from `title` (often dynamic, e.g.
    /// "Hide Member List").
    var menuTitle: String?
    var shortcut: KeyboardShortcut?
    /// Extra words the palette matches on (not displayed).
    var keywords: [String] = []
    /// Disabled commands are greyed out in menus and hidden from the palette.
    var isEnabled = true
    /// For choices and toggles: whether it's the current state. Menus show a
    /// checkmark; the palette shows one on the right.
    var isChecked: Bool?
    /// Commands that only make sense in menus (e.g. "Command Palette…").
    var showsInPalette = true
    let perform: () -> Void

    enum Category: String, CaseIterable {
        case buffer = "Buffer"
        case channel = "Channel"
        case chat = "Chat"
        case go = "Go"
        case layout = "Layout"
        case media = "Media"
        case navigation = "Navigation"
        case network = "Network"
        case preset = "Preset"
        case settings = "Settings"
        case tabs = "Tabs"
        case text = "Text"
        case theme = "Theme"
        case view = "View"
    }

    /// "View: Toggle Member List".
    var paletteTitle: String { "\(category.rawValue): \(title)" }

    var resolvedMenuTitle: String { menuTitle ?? title }

    /// The shortcut as menu-style glyphs, e.g. `["⇧", "⌘", "M"]`.
    var shortcutGlyphs: [String] { shortcut.map(ShortcutGlyphs.glyphs(for:)) ?? [] }
}

// MARK: - Shortcut glyphs

/// Renders `KeyboardShortcut`s the way macOS menus do (⌃⌥⇧⌘, then the key).
enum ShortcutGlyphs {
    static func glyphs(for shortcut: KeyboardShortcut) -> [String] {
        glyphs(modifiers: shortcut.modifiers, key: shortcut.key)
    }

    static func glyphs(modifiers: EventModifiers, key: KeyEquivalent) -> [String] {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyGlyph(key))
        return parts
    }

    static func string(for shortcut: KeyboardShortcut) -> String {
        glyphs(for: shortcut).joined()
    }

    static func keyGlyph(_ key: KeyEquivalent) -> String {
        switch key {
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .return: "↩"
        case .escape: "⎋"
        case .delete: "⌫"
        case .deleteForward: "⌦"
        case .tab: "⇥"
        case .space: "Space"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        default: String(key.character).uppercased()
        }
    }

    /// Spoken form for VoiceOver, e.g. "Shift Command M".
    static func spoken(_ shortcut: KeyboardShortcut) -> String {
        var words: [String] = []
        let modifiers = shortcut.modifiers
        if modifiers.contains(.control) { words.append("Control") }
        if modifiers.contains(.option) { words.append("Option") }
        if modifiers.contains(.shift) { words.append("Shift") }
        if modifiers.contains(.command) { words.append("Command") }
        switch shortcut.key {
        case .upArrow: words.append("Up Arrow")
        case .downArrow: words.append("Down Arrow")
        case .leftArrow: words.append("Left Arrow")
        case .rightArrow: words.append("Right Arrow")
        case "+": words.append("Plus")
        case "-": words.append("Minus")
        case ",": words.append("Comma")
        default: words.append(keyGlyph(shortcut.key))
        }
        return words.joined(separator: " ")
    }
}

// MARK: - Menu items

/// A menu bar button for a command: its menu title, shortcut and enabled state.
struct CommandMenuButton: View {
    let command: VelaCommand

    init(_ command: VelaCommand) {
        self.command = command
    }

    var body: some View {
        Button(command.resolvedMenuTitle, action: command.perform)
            .keyboardShortcut(command.shortcut)
            .disabled(!command.isEnabled)
    }
}

/// A checkmarked menu item for a choice or toggle command.
struct CommandMenuToggle: View {
    let command: VelaCommand

    init(_ command: VelaCommand) {
        self.command = command
    }

    var body: some View {
        Toggle(command.resolvedMenuTitle, isOn: Binding(
            get: { command.isChecked ?? false },
            set: { _ in command.perform() }
        ))
        .keyboardShortcut(command.shortcut)
        .disabled(!command.isEnabled)
    }
}
