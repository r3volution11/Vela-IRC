// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import SwiftUI

/// A theme with every registry token resolved to a concrete color. This is
/// what views read from; it's immutable and cheap to pass around.
public struct ResolvedTheme: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let kind: ThemeKind
    public let vibrancy: ThemeVibrancy
    /// Every registry token, plus any extra keys the theme defined.
    public let colors: [String: ThemeColor]
    /// Palette for nickname colors (never empty).
    public let nickColors: [ThemeColor]
    /// mIRC colors 0–98 (always 99 entries).
    public let ircColors: [ThemeColor]

    public init(
        id: String,
        name: String,
        kind: ThemeKind,
        vibrancy: ThemeVibrancy,
        colors: [String: ThemeColor],
        nickColors: [ThemeColor],
        ircColors: [ThemeColor]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.vibrancy = vibrancy
        self.colors = colors
        self.nickColors = nickColors.isEmpty ? NickPalette.defaultPalette(for: kind) : nickColors
        var irc = Array(ircColors.prefix(IRCPalette.count))
        if irc.count < IRCPalette.count {
            irc += IRCPalette.standard[irc.count...]
        }
        self.ircColors = irc
    }

    /// The resolved color for `key`. Unknown keys return `window.foreground`
    /// so a typo is visible but never crashes; prefer `ThemeKey` constants.
    public func color(_ key: String) -> ThemeColor {
        colors[key] ?? colors[ThemeKey.windowForeground] ?? (kind == .dark ? .white : .black)
    }

    public subscript(_ key: String) -> SwiftUI.Color {
        color(key).color
    }

    /// A stable color for a nickname: FNV-1a over the RFC 1459 case-folded
    /// nick, so `Alice`, `alice` and `ALICE` match, as do `nick[away]` and
    /// `nick{away}`, and the color doesn't change between launches.
    public func nickColor(for nick: String) -> ThemeColor {
        nickColors[Self.nickColorIndex(for: nick, paletteSize: nickColors.count)]
    }

    /// mIRC color `index` (0–98), or `nil` for 99 ("default") and anything
    /// out of range.
    public func ircColor(_ index: Int) -> ThemeColor? {
        ircColors.indices.contains(index) ? ircColors[index] : nil
    }

    /// `.dark` or `.light`, for `.preferredColorScheme(_:)`.
    public var colorScheme: ColorScheme { kind == .dark ? .dark : .light }

    /// The matching system appearance, for `NSApp.appearance` so menus,
    /// context menus and alerts follow the theme's light/dark kind.
    public var appearanceName: NSAppearance.Name { kind == .dark ? .darkAqua : .aqua }

    static func nickColorIndex(for nick: String, paletteSize: Int) -> Int {
        guard paletteSize > 0 else { return 0 }
        var hash: UInt32 = 2_166_136_261
        for byte in casefold(nick).utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(paletteSize))
    }

    /// RFC 1459 case mapping: ASCII lowercase plus `[]\~` → `{}|^`.
    static func casefold(_ nick: String) -> String {
        String(nick.lowercased().map { character -> Character in
            switch character {
            case "[": "{"
            case "]": "}"
            case "\\": "|"
            case "~": "^"
            default: character
            }
        })
    }

    // MARK: Fallbacks

    /// Used when nothing else can be loaded. Palenight, the default dark
    /// theme, if the bundled file loads; registry defaults otherwise.
    public static let fallbackDark: ResolvedTheme = builtIn(id: "palenight") ?? registryDefaults(.dark)

    /// Lighter, the default light theme, or registry defaults.
    public static let fallbackLight: ResolvedTheme = builtIn(id: "lighter") ?? registryDefaults(.light)

    public static func fallback(for kind: ThemeKind) -> ResolvedTheme {
        kind == .dark ? fallbackDark : fallbackLight
    }

    /// A theme made only of registry defaults.
    public static func registryDefaults(_ kind: ThemeKind) -> ResolvedTheme {
        let definition = ThemeDefinition(
            schema: nil,
            name: kind == .dark ? "Default Dark" : "Default Light",
            type: kind
        )
        // Registry defaults contain no includes or literals that can fail.
        return (try? ThemeResolver.resolve(definition, id: "default-\(kind.rawValue)", includeLoader: { _ in nil }, overrides: [:]))
            ?? ResolvedTheme(id: "default-\(kind.rawValue)", name: definition.name, kind: kind, vibrancy: .none,
                             colors: [:], nickColors: [], ircColors: IRCPalette.standard)
    }

    private static func builtIn(id: String) -> ResolvedTheme? {
        let url = ThemeLoader.builtInThemesDirectory.appendingPathComponent("\(id).json")
        guard let definition = try? ThemeLoader.load(contentsOf: url) else { return nil }
        return try? ThemeResolver.resolve(definition, id: id, includeLoader: { reference in
            try ThemeLoader.builtInDefinition(named: reference)
        }, overrides: [:])
    }
}
