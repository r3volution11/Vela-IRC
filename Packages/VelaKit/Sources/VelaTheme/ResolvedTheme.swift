// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import SwiftUI
import VelaFoundation

/// A theme with every registry token resolved to a concrete color. This is
/// what views read from; it's immutable and cheap to pass around.
public struct ResolvedTheme: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let kind: ThemeKind
    public let vibrancy: ThemeVibrancy
    /// Every registry token, plus any extra keys the theme defined.
    public let colors: [String: ThemeColor]
    /// Palette for nickname colors, as the theme defines it (never empty).
    public let nickColors: [ThemeColor]
    /// The nick colors handed out: `nickColors` minus any that would read
    /// as plain text (see `isDistinctNickColor`). Never empty.
    public let nickPalette: [ThemeColor]
    /// How different each pair of `nickPalette` colors looks, for keeping
    /// people in one conversation apart (`NickColorAssigner`).
    public let nickPaletteGeometry: NickPaletteGeometry
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
        let palette = Self.usableNickPalette(self.nickColors, colors: colors)
        self.nickPalette = palette
        self.nickPaletteGeometry = NickPaletteGeometry(
            distances: palette.map { a in palette.map { a.distance(to: $0) } },
            reserved: Self.selfLikeNickColors(palette, selfNick: colors[ThemeKey.chatSelfNick])
        )
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

    /// A stable color for a nickname, the same everywhere: see
    /// `NickColorAssigner.usualIndex(for:palette:)`. Never one that looks
    /// like `chat.selfNick`, your own nick's color. Within a conversation,
    /// prefer the conversation's assignment, which keeps the people talking
    /// there apart.
    public func nickColor(for nick: String) -> ThemeColor {
        nickPalette[NickColorAssigner.usualIndex(for: nick, palette: nickPaletteGeometry)]
    }

    /// The `nickPalette` color at `index` (wrapping, so any index is safe).
    public func nickColor(at index: Int) -> ThemeColor {
        nickPalette[((index % nickPalette.count) + nickPalette.count) % nickPalette.count]
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
        NickColorAssigner.preferredIndex(for: nick, paletteSize: paletteSize)
    }

    // MARK: Nick palette

    /// Whether `color` can be a nick color on this theme: it must stand out
    /// from the message text, or a colored nick reads as an uncolored one
    /// (a pale grey-blue beside pale grey-blue text), and it must be
    /// readable on the chat background (the audit's 3:1).
    static func isDistinctNickColor(_ color: ThemeColor, text: ThemeColor?, background: ThemeColor?) -> Bool {
        if let background, color.contrastRatio(against: background) < ThemeAudit.nickMinimum { return false }
        if let text {
            let distance = color.distance(to: text)
            // Nearly the text color, or a greyish color close to it.
            if distance < 0.04 || (color.chroma < 0.045 && distance < 0.12) { return false }
        }
        return true
    }

    /// `palette` minus the colors that aren't distinct. Keeps the theme's
    /// palette when too few would be left to tell people apart.
    static func usableNickPalette(_ palette: [ThemeColor], colors: [String: ThemeColor]) -> [ThemeColor] {
        let text = colors[ThemeKey.chatForeground]
        let background = colors[ThemeKey.chatBackground]
        let usable = palette.filter { isDistinctNickColor($0, text: text, background: background) }
        return usable.count >= min(4, palette.count) ? usable : palette
    }

    /// The entries of `palette` nobody else is given because they look like
    /// your own nick (`chat.selfNick`): closer to it than
    /// `NickPaletteGeometry.oklabSimilar`, the distance under which the
    /// assigner already treats two people's colors as alike. Your nick is in
    /// every conversation, so its color is held the way a current
    /// speaker's is. Many themes put their self color in the palette too
    /// (Palenight's #C792EA, Dracula's #BD93F9), and a blue next to a
    /// purple self color reads as the same person at a glance. Closest
    /// first, and never so many that fewer than four colors (or the whole
    /// palette, when it's smaller) are left to hand out.
    static func selfLikeNickColors(_ palette: [ThemeColor], selfNick: ThemeColor?) -> Set<Int> {
        guard let selfNick else { return [] }
        let alike = palette.indices
            .map { (index: $0, distance: palette[$0].distance(to: selfNick)) }
            .filter { $0.distance < NickPaletteGeometry.oklabSimilar }
            .sorted { $0.distance < $1.distance }
        let room = max(0, palette.count - min(4, palette.count))
        return Set(alike.prefix(room).map(\.index))
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
