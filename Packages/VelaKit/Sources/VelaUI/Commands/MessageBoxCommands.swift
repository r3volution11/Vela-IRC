// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

extension VelaCommandCatalog {
    /// The message box border styles, for the palette.
    var messageBoxBorderCommands: [VelaCommand] { Self.messageBoxBorderCommands(context.app.settings) }

    /// Static so tests can build them from a bare settings store.
    static func messageBoxBorderCommands(_ settings: SettingsStore) -> [VelaCommand] {
        let current = settings[.appearanceMessageBoxBorder]
        func command(_ style: MessageBoxBorder, _ title: String, keywords: [String]) -> VelaCommand {
            VelaCommand(
                id: "input.messageBoxBorder.\(style.rawValue)", category: .typing, title: "Message Box Border: \(title)",
                keywords: ["composer", "input", "field", "outline", "focus ring", "border"] + keywords,
                isChecked: current == style
            ) { settings[.appearanceMessageBoxBorder] = style }
        }
        return [
            command(.none, "None", keywords: ["borderless", "hide", "off"]),
            command(.subtle, "Subtle", keywords: ["quiet", "default"]),
            command(.accent, "Accent When Typing", keywords: ["accent", "highlight", "focus"]),
        ]
    }
}

/// Message box border color actions for Settings → Appearance.
@MainActor
enum MessageBoxBorderActions {
    private struct CacheKey: Hashable {
        let id: String
        let definition: ThemeDefinition
    }

    private static var cache: [CacheKey: MessageBoxBorderPalette] = [:]

    /// The border colors a theme offers, from its file as designed (cached
    /// until the file changes). `nil` if the theme can't be resolved.
    static func palette(for info: ThemeInfo, themeStore: ThemeStore) -> MessageBoxBorderPalette? {
        guard let accent = AccentActions.palette(for: info, themeStore: themeStore) else { return nil }
        let key = CacheKey(id: info.id, definition: accent.definition)
        if let cached = cache[key] { return cached }
        let palette = MessageBoxBorderPalette(accentPalette: accent)
        if cache.count > 48 { cache.removeAll() }
        cache[key] = palette
        return palette
    }

    static func choice(in palette: MessageBoxBorderPalette, settings: SettingsStore) -> MessageBoxBorderChoice {
        palette.choice(in: settings[.appearanceColorCustomizations])
    }

    /// Switches the palette's theme to `swatch` (Default removes what the
    /// picker wrote and keeps hand-written overrides).
    static func select(_ swatch: MessageBoxBorderSwatch, in palette: MessageBoxBorderPalette, settings: SettingsStore) {
        let current = settings[.appearanceColorCustomizations]
        let updated = palette.applying(swatch, to: current)
        if updated != current { settings[.appearanceColorCustomizations] = updated }
    }

    /// Custom…: any color.
    static func select(_ color: ThemeColor, in palette: MessageBoxBorderPalette, settings: SettingsStore) {
        let current = settings[.appearanceColorCustomizations]
        let updated = palette.applying(color: color, to: current)
        if updated != current { settings[.appearanceColorCustomizations] = updated }
    }

    /// Whether the picker has set a color for the palette's theme (rather
    /// than settings.json setting `input.border` by hand).
    static func hasPickedColor(in palette: MessageBoxBorderPalette, settings: SettingsStore) -> Bool {
        MessageBoxBorderCustomizations.color(
            in: settings[.appearanceColorCustomizations],
            themeName: palette.themeName,
            themeID: palette.themeID
        ) != nil
    }
}
