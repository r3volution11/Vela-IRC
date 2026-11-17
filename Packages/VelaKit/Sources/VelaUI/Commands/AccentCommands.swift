// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

extension VelaCommandCatalog {
    /// The current theme's accent color.
    var accentCommands: [VelaCommand] {
        [nextAccentColor, resetAccentColor]
    }

    var nextAccentColor: VelaCommand {
        let themeStore = context.themeStore
        let settings = context.app.settings
        let info = themeStore.currentInfo
        let palette = info.flatMap { AccentActions.palette(for: $0, themeStore: themeStore) }
        return VelaCommand(
            id: "theme.nextAccent", category: .theme, title: "Next Accent Color",
            keywords: ["accent", "primary color", "highlight color", "tint", "cycle"],
            isEnabled: (palette?.swatches.count ?? 0) > 1
        ) {
            guard let palette else { return }
            AccentActions.selectNext(in: palette, settings: settings)
        }
    }

    var resetAccentColor: VelaCommand {
        let themeStore = context.themeStore
        let settings = context.app.settings
        let info = themeStore.currentInfo
        let isCustomized = info.map { AccentActions.hasGeneratedAccent(for: $0, settings: settings) } ?? false
        return VelaCommand(
            id: "theme.resetAccent", category: .theme, title: "Reset Accent Color",
            keywords: ["accent", "default", "primary color", "restore"],
            isEnabled: isCustomized
        ) {
            guard let info else { return }
            AccentActions.reset(for: info, settings: settings)
        }
    }
}

/// Accent color actions shared by Settings → Appearance and the palette.
@MainActor
enum AccentActions {
    private struct CacheKey: Hashable {
        let id: String
        let definition: ThemeDefinition
    }

    private static var cache: [CacheKey: AccentPalette] = [:]

    /// The accent choices for a theme, from its file as designed (cached
    /// until the file changes). `nil` if the theme can't be resolved.
    static func palette(for info: ThemeInfo, themeStore: ThemeStore) -> AccentPalette? {
        guard let definition = try? themeStore.flattenedDefinition(for: info) else { return nil }
        let key = CacheKey(id: info.id, definition: definition)
        if let cached = cache[key] { return cached }
        guard let palette = try? AccentPalette(definition: definition, id: info.id) else { return nil }
        if cache.count > 48 { cache.removeAll() }
        cache[key] = palette
        return palette
    }

    static func choice(in palette: AccentPalette, settings: SettingsStore) -> AccentChoice {
        palette.choice(in: settings[.appearanceColorCustomizations])
    }

    /// Switches the palette's theme to `swatch` (Default removes the
    /// generated tokens and keeps hand-written ones).
    static func select(_ swatch: AccentSwatch, in palette: AccentPalette, settings: SettingsStore) {
        let current = settings[.appearanceColorCustomizations]
        let updated = palette.applying(swatch, to: current)
        if updated != current { settings[.appearanceColorCustomizations] = updated }
    }

    static func selectNext(in palette: AccentPalette, settings: SettingsStore) {
        let next = palette.nextSwatch(after: choice(in: palette, settings: settings))
        select(next, in: palette, settings: settings)
    }

    /// Back to the theme's own accent: removes what the picker wrote.
    static func reset(for info: ThemeInfo, settings: SettingsStore) {
        let current = settings[.appearanceColorCustomizations]
        let updated = AccentCustomizations.removing(from: current, themeName: info.name, themeID: info.id)
        if updated != current { settings[.appearanceColorCustomizations] = updated }
    }

    static func hasGeneratedAccent(for info: ThemeInfo, settings: SettingsStore) -> Bool {
        !AccentCustomizations.generatedKeys(
            in: settings[.appearanceColorCustomizations],
            themeName: info.name,
            themeID: info.id
        ).isEmpty
    }
}
