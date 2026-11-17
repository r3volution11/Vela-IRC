// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// A color a theme's accent can be switched to.
public struct AccentSwatch: Sendable, Hashable, Identifiable {
    public let color: ThemeColor
    /// An approximate color name from the hue, e.g. "Cyan" or "Light Blue".
    public let name: String
    /// The theme's own accent.
    public let isDefault: Bool

    public var id: String { color.hex }

    /// "Default, Purple" or "Cyan", for VoiceOver.
    public var accessibilityLabel: String { isDefault ? "Default, \(name)" : name }

    /// "Default (Purple)" or "Cyan", for tooltips and menus.
    public var title: String { isDefault ? "Default (\(name))" : name }

    public init(color: ThemeColor, name: String, isDefault: Bool) {
        self.color = color
        self.name = name
        self.isDefault = isDefault
    }
}

/// Which accent a theme is using, read back from `colorCustomizations`.
public enum AccentChoice: Sendable, Hashable {
    /// One of the palette's swatches (possibly the Default one).
    case swatch(AccentSwatch)
    /// An accent set by hand that isn't one of the swatches.
    case custom(ThemeColor)

    public var swatch: AccentSwatch? {
        if case .swatch(let swatch) = self { return swatch }
        return nil
    }
}

/// The accent colors a theme offers: its own accent ("Default") first, then
/// the other colors it ships (its nick colors and IRC colors 0–15) that work
/// as an accent, ordered by hue.
///
/// A candidate must have a clear hue (not a grey), stand apart from the
/// text color, reach 3:1 against the window and sidebar backgrounds, and
/// look different from the swatches before it (OKLab distance).
public struct AccentPalette: Sendable {
    public let themeName: String
    public let themeID: String
    /// The theme as designed (flattened, no user overrides).
    public let definition: ThemeDefinition
    /// `definition` resolved without user overrides.
    public let base: ResolvedTheme
    /// Default first, then by hue. At most `maximumCount`.
    public let swatches: [AccentSwatch]

    /// Up to this many swatches, Default included.
    public static let maximumCount = 10
    /// Candidates closer than this (OKLab ΔE) count as the same color. A
    /// little under `NickPaletteGeometry.oklabSimilar`: swatches sit side by
    /// side and are picked deliberately, so subtler differences still count.
    public static let similarDistance = 0.08
    /// Minimum contrast against the window and sidebar backgrounds.
    public static let minimumContrast = 3.0

    /// `definition` must already be flattened (its `include` merged in, as
    /// `ThemeStore.flattenedDefinition(for:)` returns it).
    public init(definition: ThemeDefinition, id: String) throws {
        let base = try ThemeResolver.resolve(definition, id: id, includeLoader: { _ in nil }, overrides: .none)
        self.init(definition: definition, base: base)
    }

    public init(definition: ThemeDefinition, base: ResolvedTheme) {
        self.definition = definition
        self.base = base
        self.themeName = base.name
        self.themeID = base.id
        self.swatches = Self.swatches(for: definition, base: base)
    }

    public var defaultSwatch: AccentSwatch { swatches[0] }

    // MARK: Candidates

    static func swatches(for definition: ThemeDefinition, base: ResolvedTheme) -> [AccentSwatch] {
        let accent = base.color(ThemeKey.accent).withAlpha(1)
        var colors = [accent]
        for color in candidates(for: definition, base: base) where colors.count < maximumCount {
            colors.append(color)
        }
        let others = colors.dropFirst().sorted { hueOrder($0) < hueOrder($1) }
        let ordered = [accent] + others
        let names = names(for: ordered)
        return ordered.enumerated().map { index, color in
            AccentSwatch(color: color, name: names[index], isDefault: index == 0)
        }
    }

    /// The theme's own colors that work as an accent, in the theme's order
    /// (nick colors, then IRC colors 0–15), without near-duplicates.
    static func candidates(for definition: ThemeDefinition, base: ResolvedTheme) -> [ThemeColor] {
        let accent = base.color(ThemeKey.accent).withAlpha(1)
        let nick = definition.nickColors.map { $0.compactMap(ThemeColor.init(hex:)) } ?? []
        let ownNick = nick.isEmpty ? NickPalette.defaultPalette(for: base.kind) : nick
        let irc = (0..<16).compactMap { index in definition.ircColors?[String(index)].flatMap(ThemeColor.init(hex:)) }
        let texts = [ThemeKey.windowForeground, ThemeKey.chatForeground].map { base.color($0).withAlpha(1) }
        let backgrounds = [ThemeKey.windowBackground, ThemeKey.sidebarBackground].map { ThemeAudit.surface($0, in: base) }
        let minimumChroma = max(0.03, min(0.06, accent.chroma * 0.6))

        var result: [ThemeColor] = []
        for raw in ownNick + irc {
            let color = raw.withAlpha(1)
            guard color.chroma >= minimumChroma,
                  !texts.contains(where: { looksLikeText(color, text: $0) }),
                  backgrounds.allSatisfy({ color.contrastRatio(against: $0) >= minimumContrast }),
                  color.distance(to: accent) >= similarDistance,
                  !result.contains(where: { $0.distance(to: color) < similarDistance })
            else { continue }
            result.append(color)
        }
        return result
    }

    /// Nearly the text color, or a greyish color close to it (the same rule
    /// that keeps such colors out of the nick palette).
    static func looksLikeText(_ color: ThemeColor, text: ThemeColor) -> Bool {
        let distance = color.distance(to: text)
        return distance < 0.04 || (color.chroma < 0.045 && distance < 0.12)
    }

    /// Hue order starting at red, so pinks sit next to magentas at the end.
    static func hueOrder(_ color: ThemeColor) -> Double {
        (color.hue - 15 + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: Names

    /// An approximate name for a color, from its OKLCh hue and lightness.
    public static func colorName(_ color: ThemeColor) -> String {
        let (l, c, h) = color.oklch
        if c < 0.03 { return l > 0.85 ? "White" : (l < 0.25 ? "Black" : "Gray") }
        switch h {
        case 12..<45:
            if l >= 0.8 && c < 0.09 { return "Pink" }
            return l < 0.5 && c < 0.15 ? "Brown" : "Red"
        case 45..<75:
            if l < 0.55 { return "Brown" }
            return h >= 60 && c < 0.09 ? "Tan" : "Orange"
        case 75..<115: return l >= 0.8 ? "Yellow" : "Gold"
        case 115..<165: return "Green"
        case 165..<200: return l >= 0.85 ? "Cyan" : "Teal"
        case 200..<215: return l < 0.7 ? "Teal" : "Cyan"
        case 215..<240: return "Cyan"
        case 240..<272: return "Blue"
        case 272..<292: return l < 0.72 ? "Indigo" : "Lavender"
        case 292..<320: return "Purple"
        case 320..<345: return l >= 0.78 ? "Pink" : "Magenta"
        default: return "Pink"
        }
    }

    /// Names for `colors`, made distinct by lightness: two blues become
    /// "Light Blue" and "Dark Blue", three "Light Blue", "Blue" and "Dark
    /// Blue"; numbers ("Blue 2") when they're too alike in lightness.
    static func names(for colors: [ThemeColor]) -> [String] {
        var names = colors.map(colorName)
        for name in Set(names) {
            let indexes = names.indices.filter { names[$0] == name }
            guard indexes.count > 1 else { continue }
            let byLightness = indexes.sorted { colors[$0].oklab.l > colors[$1].oklab.l }
            let lightness = byLightness.map { colors[$0].oklab.l }
            let spread = zip(lightness, lightness.dropFirst()).map { $0 - $1 }.min() ?? 0
            if indexes.count <= 3, spread > 0.04 {
                names[byLightness.first!] = "Light \(name)"
                names[byLightness.last!] = "Dark \(name)"
            } else {
                for (position, index) in indexes.enumerated() where position > 0 {
                    names[index] = "\(name) \(position + 1)"
                }
            }
        }
        return names
    }

    // MARK: Recoloring

    /// The token overrides that switch this theme to `swatch`'s color, or
    /// none for the Default swatch.
    public func overrides(for swatch: AccentSwatch) -> [String: ThemeColor] {
        if swatch.isDefault { return [:] }
        return AccentRecolor.overrides(for: definition, base: base, accent: swatch.color)
    }

    // MARK: Settings

    /// The theme's current accent according to `customizations`: a swatch
    /// when the accent in effect is one, `.custom` when something else sets
    /// it, the Default swatch otherwise.
    public func choice(in customizations: [String: JSONValue]) -> AccentChoice {
        let overrides = ThemeOverrides(customizations: customizations, themeName: themeName, themeID: themeID)
        guard let hex = overrides.colors[ThemeKey.accent], let color = ThemeColor(hex: hex)?.withAlpha(1) else {
            return .swatch(defaultSwatch)
        }
        if let swatch = swatches.first(where: { $0.color.distance(to: color) < 0.004 }) {
            return .swatch(swatch)
        }
        return .custom(color)
    }

    /// `customizations` with this theme's accent set to `swatch`: the
    /// generated tokens go into the theme's `"[Name]"` scope (Default just
    /// removes them).
    public func applying(_ swatch: AccentSwatch, to customizations: [String: JSONValue]) -> [String: JSONValue] {
        let generated = overrides(for: swatch)
        if generated.isEmpty {
            return AccentCustomizations.removing(from: customizations, themeName: themeName, themeID: themeID)
        }
        return AccentCustomizations.applying(generated, to: customizations, themeName: themeName, themeID: themeID)
    }

    /// The swatch after the current one, wrapping around to Default.
    public func nextSwatch(after choice: AccentChoice) -> AccentSwatch {
        guard let current = choice.swatch, let index = swatches.firstIndex(of: current) else {
            return swatches.count > 1 ? swatches[1] : swatches[0]
        }
        return swatches[(index + 1) % swatches.count]
    }
}

/// Reading and writing the accent picker's tokens in a settings
/// `colorCustomizations` object.
///
/// The picker writes into the theme's own scope, `"[Palenight]"`, and lists
/// the keys it wrote under `"$accentPicker"`, so choosing Default removes
/// exactly those and leaves hand-written overrides alone:
///
/// ```jsonc
/// "[Palenight]": {
///   "accent": "#89DDFF",
///   "button.background": "#89DDFF",
///   …
///   "$accentPicker": ["accent", "button.background", …]
/// }
/// ```
///
/// Entries written by hand win: a token already set in the scope, at the
/// top level or in another scope matching the theme is left alone (except
/// `accent` itself, which is the choice).
public enum AccentCustomizations {
    /// The scope entry listing the keys the accent picker wrote.
    public static let markerKey = "$accentPicker"

    /// The scope key the picker writes to for a theme: an existing
    /// single-theme scope naming it (by name or id, any case), else
    /// `"[Name]"` (`"[id]"` when the name has `[`, `]` or `*` in it).
    public static func scopeKey(in customizations: [String: JSONValue], themeName: String, themeID: String) -> String {
        let own = ownScopeKeys(in: customizations, themeName: themeName, themeID: themeID)
        if let marked = own.first(where: { customizations[$0]?.objectValue?[markerKey] != nil }) { return marked }
        if let exact = own.first(where: { ThemeOverrides.scopePatterns(in: $0) == [themeName] }) { return exact }
        if let first = own.first { return first }
        let usesName = !themeName.contains(where: { "[]*".contains($0) })
        return "[\(usesName ? themeName : themeID)]"
    }

    /// The keys the picker wrote for a theme (empty when it hasn't).
    public static func generatedKeys(in customizations: [String: JSONValue], themeName: String, themeID: String) -> [String] {
        ownScopeKeys(in: customizations, themeName: themeName, themeID: themeID)
            .flatMap { markerKeys(in: customizations[$0]?.objectValue ?? [:]) }
    }

    /// `customizations` with `generated` written into the theme's scope,
    /// replacing what the picker wrote before.
    public static func applying(
        _ generated: [String: ThemeColor],
        to customizations: [String: JSONValue],
        themeName: String,
        themeID: String
    ) -> [String: JSONValue] {
        var result = removing(from: customizations, themeName: themeName, themeID: themeID)
        let key = scopeKey(in: result, themeName: themeName, themeID: themeID)
        var scope = result[key]?.objectValue ?? [:]
        let elsewhere = handWrittenKeys(in: result, excludingScope: key, themeName: themeName, themeID: themeID)
        var written: [String] = []
        for token in generated.keys.sorted() {
            if token != ThemeKey.accent, scope[token] != nil || elsewhere.contains(token) { continue }
            scope[token] = .string(generated[token]!.hex)
            written.append(token)
        }
        scope[markerKey] = .array(written.map { .string($0) })
        result[key] = .object(scope)
        return result
    }

    /// `customizations` without the tokens the picker wrote for a theme.
    /// Hand-written entries stay; a scope left empty is removed.
    public static func removing(from customizations: [String: JSONValue], themeName: String, themeID: String) -> [String: JSONValue] {
        var result = customizations
        for key in ownScopeKeys(in: customizations, themeName: themeName, themeID: themeID) {
            guard var scope = result[key]?.objectValue, scope[markerKey] != nil else { continue }
            for token in markerKeys(in: scope) { scope[token] = nil }
            scope[markerKey] = nil
            result[key] = scope.isEmpty ? nil : .object(scope)
        }
        return result
    }

    /// How many overrides were written by hand: top-level entries plus
    /// scoped ones, not counting what the accent picker wrote.
    public static func handWrittenCount(in customizations: [String: JSONValue]) -> Int {
        customizations.reduce(0) { count, entry in
            guard ThemeOverrides.scopePatterns(in: entry.key) != nil else { return count + 1 }
            guard let scope = entry.value.objectValue else { return count + 1 }
            let generated = Set(markerKeys(in: scope))
            return count + scope.keys.filter { $0 != markerKey && !generated.contains($0) }.count
        }
    }

    // MARK: Helpers

    /// Scope keys naming exactly this one theme (no wildcards, no lists).
    static func ownScopeKeys(in customizations: [String: JSONValue], themeName: String, themeID: String) -> [String] {
        customizations.keys.sorted().filter { key in
            guard let patterns = ThemeOverrides.scopePatterns(in: key), patterns.count == 1,
                  !patterns[0].contains("*") else { return false }
            return patterns[0].caseInsensitiveCompare(themeName) == .orderedSame
                || patterns[0].caseInsensitiveCompare(themeID) == .orderedSame
        }
    }

    static func markerKeys(in scope: [String: JSONValue]) -> [String] {
        (scope[markerKey]?.arrayValue ?? []).compactMap(\.stringValue)
    }

    /// Token keys set by hand for this theme outside `excludingScope`: at
    /// the top level and in other scopes matching it.
    static func handWrittenKeys(
        in customizations: [String: JSONValue],
        excludingScope: String,
        themeName: String,
        themeID: String
    ) -> Set<String> {
        var keys = Set(customizations.keys.filter { ThemeOverrides.scopePatterns(in: $0) == nil })
        for (key, value) in customizations where key != excludingScope {
            guard let patterns = ThemeOverrides.scopePatterns(in: key),
                  patterns.contains(where: { ThemeOverrides.matches($0, name: themeName, id: themeID) }),
                  let scope = value.objectValue else { continue }
            let generated = Set(markerKeys(in: scope))
            keys.formUnion(scope.keys.filter { $0 != markerKey && !generated.contains($0) })
        }
        return keys
    }
}
