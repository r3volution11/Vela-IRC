// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaStore
import VelaTheme

extension EnvironmentValues {
    /// The resolved theme every view draws with. Never hard-code colors:
    /// read `theme[ThemeKey.someToken]` instead.
    @Entry public var theme: ResolvedTheme = .fallbackDark

    /// Typography, spacing and layout preferences derived from settings.json.
    @Entry public var chatStyle: ChatStyle = ChatStyle()
}

extension ThemeSettings {
    /// Reads the appearance keys from settings.json.
    @MainActor
    init(settings: SettingsStore) {
        self.init(
            themeName: settings[.appearanceTheme],
            preferredDarkTheme: settings[.appearancePreferredDarkTheme],
            preferredLightTheme: settings[.appearancePreferredLightTheme],
            followSystemAppearance: settings[.appearanceFollowSystem],
            colorCustomizations: settings[.appearanceColorCustomizations]
        )
    }
}

extension View {
    /// Fills the background with a theme token.
    func themedBackground(_ key: String) -> some View {
        modifier(ThemedBackground(key: key))
    }

    /// Sets the foreground style from a theme token.
    func themedForeground(_ key: String) -> some View {
        modifier(ThemedForeground(key: key))
    }
}

private struct ThemedBackground: ViewModifier {
    @Environment(\.theme) private var theme
    let key: String

    func body(content: Content) -> some View {
        content.background(theme[key])
    }
}

private struct ThemedForeground: ViewModifier {
    @Environment(\.theme) private var theme
    let key: String

    func body(content: Content) -> some View {
        content.foregroundStyle(theme[key])
    }
}
