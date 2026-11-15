// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// A theme available to pick: a built-in or a file in the user's Themes folder.
public struct ThemeInfo: Sendable, Identifiable, Hashable {
    /// The file name without extension, e.g. `palenight`.
    public let id: String
    public let name: String
    public let kind: ThemeKind
    public let source: Source
    public let url: URL

    public enum Source: Sendable, Hashable {
        case builtIn
        case user
    }

    public init(id: String, name: String, kind: ThemeKind, source: Source, url: URL) {
        self.id = id
        self.name = name
        self.kind = kind
        self.source = source
        self.url = url
    }

    /// Whether `reference` names this theme by id or name (case-insensitive).
    public func matches(_ reference: String) -> Bool {
        id.caseInsensitiveCompare(reference) == .orderedSame
            || name.caseInsensitiveCompare(reference) == .orderedSame
    }
}

/// The theme-related part of settings.json. Themes are referenced by name
/// (case-insensitive) or id.
public struct ThemeSettings: Sendable, Equatable {
    /// The theme used when not following the system appearance.
    public var themeName: String
    /// Used when following the system appearance and it's dark.
    public var preferredDarkTheme: String
    /// Used when following the system appearance and it's light.
    public var preferredLightTheme: String
    public var followSystemAppearance: Bool
    /// VS Code-style overrides:
    /// `{"chat.background": "#000", "[Palenight]": {"accent": "#FF0"}}`.
    public var colorCustomizations: [String: JSONValue]

    public static let defaultDarkTheme = "Palenight"
    public static let defaultLightTheme = "Lighter"

    public init(
        themeName: String = ThemeSettings.defaultDarkTheme,
        preferredDarkTheme: String = ThemeSettings.defaultDarkTheme,
        preferredLightTheme: String = ThemeSettings.defaultLightTheme,
        followSystemAppearance: Bool = true,
        colorCustomizations: [String: JSONValue] = [:]
    ) {
        self.themeName = themeName
        self.preferredDarkTheme = preferredDarkTheme
        self.preferredLightTheme = preferredLightTheme
        self.followSystemAppearance = followSystemAppearance
        self.colorCustomizations = colorCustomizations
    }

    public static let `default` = ThemeSettings()

    /// The theme reference to use for a given system appearance.
    public func themeReference(systemAppearance: ThemeKind) -> String {
        guard followSystemAppearance else { return themeName }
        return systemAppearance == .dark ? preferredDarkTheme : preferredLightTheme
    }
}
