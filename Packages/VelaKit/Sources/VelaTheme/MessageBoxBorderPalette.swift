// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// A color the message box border can be switched to.
public struct MessageBoxBorderSwatch: Sendable, Hashable, Identifiable {
    /// As the theme has it, alpha included (a divider can be translucent).
    public let color: ThemeColor
    /// What the color is in the theme ("Divider", "Secondary Text",
    /// "Accent") or, for its other colors, an approximate name ("Cyan").
    public let name: String
    /// The theme's own border: no override.
    public let isDefault: Bool

    public var id: String { isDefault ? "default" : color.hex }

    /// "Default (the theme's border)" or "Divider", for tooltips.
    public var title: String { isDefault ? "Default (\(name))" : name }

    /// For VoiceOver.
    public var accessibilityLabel: String { isDefault ? "Default, \(name)" : name }

    public init(color: ThemeColor, name: String, isDefault: Bool) {
        self.color = color
        self.name = name
        self.isDefault = isDefault
    }
}

/// Which border color a theme is using, read back from `colorCustomizations`.
public enum MessageBoxBorderChoice: Sendable, Hashable {
    /// One of the palette's swatches (possibly the Default one).
    case swatch(MessageBoxBorderSwatch)
    /// Any other color: picked with Custom…, or set by hand.
    case custom(ThemeColor)

    public var swatch: MessageBoxBorderSwatch? {
        if case .swatch(let swatch) = self { return swatch }
        return nil
    }
}

/// The colors a theme offers for the message box border: its own border
/// ("Default") first, then its quiet neutrals (dividers, borders, secondary
/// text), its accent, and some of its other colors.
///
/// Unlike `AccentPalette`, low-contrast colors are the point here: a border
/// that barely shows is what "quiet" means. Only colors that would vanish
/// into the field (or repeat an earlier swatch) are left out.
public struct MessageBoxBorderPalette: Sendable {
    public let themeName: String
    public let themeID: String
    /// The theme as designed (flattened, no user overrides).
    public let definition: ThemeDefinition
    /// `definition` resolved without user overrides.
    public let base: ResolvedTheme
    /// Default first, then neutrals from quietest to strongest, the accent,
    /// then other colors by hue. At most `maximumCount`.
    public let swatches: [MessageBoxBorderSwatch]

    /// Up to this many swatches, Default included.
    public static let maximumCount = 10
    /// Colors closer than this (OKLab ΔE, drawn over the field) count as the
    /// same. Small, since neutrals differ only a little and that's the point.
    public static let similarDistance = 0.02
    /// A color closer than this to the field's background wouldn't show.
    public static let invisibleDistance = 0.015

    /// The theme's neutral tokens offered as borders, with their names.
    public static let neutralTokens: [(key: String, name: String)] = [
        (ThemeKey.paneDivider, "Divider"),
        (ThemeKey.windowBorder, "Window Border"),
        (ThemeKey.embedBorder, "Link Preview Border"),
        (ThemeKey.inputPlaceholder, "Placeholder"),
        (ThemeKey.chatSecondaryForeground, "Secondary Text"),
    ]

    /// `definition` must already be flattened (its `include` merged in, as
    /// `ThemeStore.flattenedDefinition(for:)` returns it).
    public init(definition: ThemeDefinition, id: String) throws {
        let base = try ThemeResolver.resolve(definition, id: id, includeLoader: { _ in nil }, overrides: .none)
        self.init(definition: definition, base: base)
    }

    /// The same theme as an accent palette, which has already resolved it.
    public init(accentPalette: AccentPalette) {
        self.init(definition: accentPalette.definition, base: accentPalette.base)
    }

    public init(definition: ThemeDefinition, base: ResolvedTheme) {
        self.definition = definition
        self.base = base
        self.themeName = base.name
        self.themeID = base.id
        self.swatches = Self.swatches(for: definition, base: base)
    }

    public var defaultSwatch: MessageBoxBorderSwatch { swatches[0] }

    // MARK: Swatches

    static func swatches(for definition: ThemeDefinition, base: ResolvedTheme) -> [MessageBoxBorderSwatch] {
        let field = ThemeAudit.surface(ThemeKey.inputBackground, in: base)
        // How a border color looks: drawn over the field.
        func drawn(_ color: ThemeColor) -> ThemeColor { color.composited(over: field) }

        var result = [MessageBoxBorderSwatch(color: base.color(ThemeKey.inputBorder), name: "the theme's border", isDefault: true)]
        func isNew(_ color: ThemeColor) -> Bool {
            let shown = drawn(color)
            return shown.distance(to: field) >= invisibleDistance
                && !result.contains { drawn($0.color).distance(to: shown) < similarDistance }
        }

        // Neutrals, quietest first.
        var neutrals: [MessageBoxBorderSwatch] = []
        for (key, name) in neutralTokens {
            let color = base.color(key)
            let shown = drawn(color)
            guard isNew(color), !neutrals.contains(where: { drawn($0.color).distance(to: shown) < similarDistance }) else { continue }
            neutrals.append(MessageBoxBorderSwatch(color: color, name: name, isDefault: false))
        }
        neutrals.sort { drawn($0.color).contrastRatio(against: field) < drawn($1.color).contrastRatio(against: field) }
        result += neutrals

        let accent = base.color(ThemeKey.accent).withAlpha(1)
        if isNew(accent) {
            result.append(MessageBoxBorderSwatch(color: accent, name: "Accent", isDefault: false))
        }

        // Then the theme's other colors that work as an accent, by hue.
        var others: [ThemeColor] = []
        for color in AccentPalette.candidates(for: definition, base: base) where result.count + others.count < maximumCount {
            if isNew(color), !others.contains(where: { $0.distance(to: color) < similarDistance }) {
                others.append(color)
            }
        }
        others.sort { AccentPalette.hueOrder($0) < AccentPalette.hueOrder($1) }
        let names = AccentPalette.names(for: others)
        result += others.enumerated().map { MessageBoxBorderSwatch(color: $1, name: names[$0], isDefault: false) }
        return Array(result.prefix(maximumCount))
    }

    // MARK: Settings

    /// The theme's border color according to `customizations`: the swatch
    /// the picker set, `.custom` for another color (Custom…, or
    /// `input.border` set by hand), the Default swatch otherwise.
    public func choice(in customizations: [String: JSONValue]) -> MessageBoxBorderChoice {
        let picked = MessageBoxBorderCustomizations.color(in: customizations, themeName: themeName, themeID: themeID)
        let color: ThemeColor
        if let picked {
            color = picked
        } else {
            // Set by hand: whatever sets input.border, other than the accent picker.
            let own = AccentCustomizations.removing(from: customizations, themeName: themeName, themeID: themeID)
            let overrides = ThemeOverrides(customizations: own, themeName: themeName, themeID: themeID)
            guard let hex = overrides.colors[ThemeKey.inputBorder], let handWritten = ThemeColor(hex: hex) else {
                return .swatch(defaultSwatch)
            }
            color = handWritten
        }
        if let swatch = swatches.dropFirst().first(where: { $0.color.hex == color.hex }) {
            return .swatch(swatch)
        }
        return .custom(color)
    }

    /// `customizations` with this theme's border set to `swatch` (Default
    /// removes the picker's tokens).
    public func applying(_ swatch: MessageBoxBorderSwatch, to customizations: [String: JSONValue]) -> [String: JSONValue] {
        swatch.isDefault ? removing(from: customizations) : applying(color: swatch.color, to: customizations)
    }

    /// `customizations` with this theme's border set to `color`, focused or
    /// not.
    public func applying(color: ThemeColor, to customizations: [String: JSONValue]) -> [String: JSONValue] {
        MessageBoxBorderCustomizations.applying(color, to: customizations, themeName: themeName, themeID: themeID)
    }

    /// Back to the theme's own border: removes what the picker wrote. When
    /// the accent picker is in use and recolors the border tokens, its
    /// colors for them come back.
    public func removing(from customizations: [String: JSONValue]) -> [String: JSONValue] {
        let removed = MessageBoxBorderCustomizations.removing(from: customizations, themeName: themeName, themeID: themeID)
        guard removed != customizations else { return customizations }
        return restoringAccent(in: removed)
    }

    /// The accent picker skips tokens the border picker holds; once those
    /// are let go, picking the same accent again fills them back in.
    func restoringAccent(in customizations: [String: JSONValue]) -> [String: JSONValue] {
        guard let accent = AccentCustomizations.pickedAccent(in: customizations, themeName: themeName, themeID: themeID) else {
            return customizations
        }
        let generated = AccentRecolor.overrides(for: definition, base: base, accent: accent)
        guard MessageBoxBorderCustomizations.tokens.contains(where: { generated[$0] != nil }) else { return customizations }
        return AccentCustomizations.applying(generated, to: customizations, themeName: themeName, themeID: themeID)
    }
}

/// Reading and writing the border color picker's tokens in a settings
/// `colorCustomizations` object.
///
/// Like the accent picker, it writes into the theme's own scope and lists
/// what it wrote, under `"$borderPicker"`, so Default removes exactly that:
///
/// ```jsonc
/// "[Palenight]": {
///   "input.border": "#4E5579",
///   "input.focusBorder": "#4E5579",
///   "$borderPicker": ["input.border", "input.focusBorder"]
/// }
/// ```
///
/// Both tokens get the color, so it shows focused or not. The border
/// picker wins over the accent picker: it takes these tokens out of
/// `"$accentPicker"`, and the accent picker leaves alone what's already in
/// the scope.
public enum MessageBoxBorderCustomizations {
    /// The scope entry listing the keys the border picker wrote.
    public static let markerKey = "$borderPicker"
    /// What the picker sets.
    public static let tokens = [ThemeKey.inputBorder, ThemeKey.inputFocusBorder]

    /// The color the picker set for a theme, if it has.
    public static func color(in customizations: [String: JSONValue], themeName: String, themeID: String) -> ThemeColor? {
        for key in AccentCustomizations.ownScopeKeys(in: customizations, themeName: themeName, themeID: themeID) {
            guard let scope = customizations[key]?.objectValue, scope[markerKey] != nil,
                  let hex = scope[ThemeKey.inputBorder]?.stringValue, let color = ThemeColor(hex: hex)
            else { continue }
            return color
        }
        return nil
    }

    /// `customizations` with `color` written into the theme's scope for both
    /// border tokens, replacing what either picker wrote for them.
    public static func applying(
        _ color: ThemeColor,
        to customizations: [String: JSONValue],
        themeName: String,
        themeID: String
    ) -> [String: JSONValue] {
        var result = removing(from: customizations, themeName: themeName, themeID: themeID)
        // Take the tokens over from the accent picker, wherever it wrote them.
        for key in AccentCustomizations.ownScopeKeys(in: result, themeName: themeName, themeID: themeID) {
            guard var scope = result[key]?.objectValue, scope[AccentCustomizations.markerKey] != nil else { continue }
            let accentKeys = AccentCustomizations.markerKeys(in: scope)
            let taken = accentKeys.filter(tokens.contains)
            guard !taken.isEmpty else { continue }
            for token in taken { scope[token] = nil }
            scope[AccentCustomizations.markerKey] = .array(accentKeys.filter { !tokens.contains($0) }.map { .string($0) })
            result[key] = .object(scope)
        }
        let key = AccentCustomizations.scopeKey(in: result, themeName: themeName, themeID: themeID)
        var scope = result[key]?.objectValue ?? [:]
        for token in tokens { scope[token] = .string(color.hex) }
        scope[markerKey] = .array(tokens.map { .string($0) })
        result[key] = .object(scope)
        return result
    }

    /// `customizations` without the tokens the picker wrote for a theme.
    /// Hand-written entries stay; a scope left empty is removed.
    public static func removing(from customizations: [String: JSONValue], themeName: String, themeID: String) -> [String: JSONValue] {
        var result = customizations
        for key in AccentCustomizations.ownScopeKeys(in: customizations, themeName: themeName, themeID: themeID) {
            guard var scope = result[key]?.objectValue, scope[markerKey] != nil else { continue }
            for token in markerKeys(in: scope) { scope[token] = nil }
            scope[markerKey] = nil
            result[key] = scope.isEmpty ? nil : .object(scope)
        }
        return result
    }

    static func markerKeys(in scope: [String: JSONValue]) -> [String] {
        (scope[markerKey]?.arrayValue ?? []).compactMap(\.stringValue)
    }
}
