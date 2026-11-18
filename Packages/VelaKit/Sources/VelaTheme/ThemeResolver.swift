// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// User color overrides layered on top of a theme, like VS Code's
/// `workbench.colorCustomizations`.
public struct ThemeOverrides: Sendable, Hashable {
    /// Token key → hex color.
    public var colors: [String: String]
    /// Replaces the nick palette when set.
    public var nickColors: [String]?
    /// mIRC index ("0"…"98") → hex color.
    public var ircColors: [String: String]
    public var vibrancy: ThemeVibrancy?

    public init(
        colors: [String: String] = [:],
        nickColors: [String]? = nil,
        ircColors: [String: String] = [:],
        vibrancy: ThemeVibrancy? = nil
    ) {
        self.colors = colors
        self.nickColors = nickColors
        self.ircColors = ircColors
        self.vibrancy = vibrancy
    }

    public static let none = ThemeOverrides()

    public var isEmpty: Bool {
        colors.isEmpty && nickColors == nil && ircColors.isEmpty && vibrancy == nil
    }

    /// Builds the overrides that apply to one theme from a settings
    /// `colorCustomizations` object: top-level entries apply to every theme,
    /// then each `"[Theme Name]"` scope matching the theme's name or id is
    /// layered on top. A scope key may list several themes
    /// (`"[Nord][Dracula]"`) and use `*` wildcards (`"[Catppuccin *]"`).
    ///
    /// Values: token keys map to hex strings; `"nickColors"` to an array of
    /// hex strings; `"ircColors"` to an object of index → hex; `"vibrancy"`
    /// to `"none"`, `"sidebar"` or `"window"`. `"$accentPicker"` and
    /// `"$borderPicker"` (the keys the accent and message box border pickers
    /// wrote, see `AccentCustomizations`) are skipped.
    public init(customizations: [String: JSONValue], themeName: String, themeID: String) {
        self.init()
        apply(customizations)
        let scopes = customizations.keys
            .filter { Self.scopePatterns(in: $0) != nil }
            .sorted()
        for key in scopes {
            guard let patterns = Self.scopePatterns(in: key),
                  patterns.contains(where: { Self.matches($0, name: themeName, id: themeID) }),
                  let object = customizations[key]?.objectValue
            else { continue }
            apply(object)
        }
    }

    private mutating func apply(_ object: [String: JSONValue]) {
        for (key, value) in object {
            if Self.scopePatterns(in: key) != nil { continue }
            switch key {
            case "nickColors":
                if let array = value.arrayValue {
                    nickColors = array.compactMap(\.stringValue)
                }
            case "ircColors":
                for (index, entry) in value.objectValue ?? [:] {
                    if let hex = entry.stringValue { ircColors[index] = hex }
                }
            case "vibrancy":
                if let raw = value.stringValue, let parsed = ThemeVibrancy(rawValue: raw) {
                    vibrancy = parsed
                }
            case AccentCustomizations.markerKey, MessageBoxBorderCustomizations.markerKey:
                continue
            default:
                if let hex = value.stringValue { colors[key] = hex }
            }
        }
    }

    /// Problems in a `colorCustomizations` object (unknown tokens, bad colors),
    /// suitable for showing next to the settings.
    public static func problems(in customizations: [String: JSONValue]) -> [String] {
        var problems: [String] = []
        func check(_ object: [String: JSONValue], prefix: String) {
            for key in object.keys.sorted() {
                let value = object[key]!
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                if scopePatterns(in: key) != nil {
                    if prefix.isEmpty, let nested = value.objectValue {
                        check(nested, prefix: key)
                    } else {
                        problems.append("“\(path)”: theme scopes must be top-level objects.")
                    }
                    continue
                }
                switch key {
                case "nickColors":
                    guard let array = value.arrayValue else {
                        problems.append("“\(path)” must be an array of colors.")
                        continue
                    }
                    for (index, item) in array.enumerated() where ThemeColor(hex: item.stringValue ?? "") == nil {
                        problems.append("“\(path)[\(index)]” is not a hex color.")
                    }
                case "ircColors":
                    guard let entries = value.objectValue else {
                        problems.append("“\(path)” must be an object of index → color.")
                        continue
                    }
                    for (index, item) in entries.sorted(by: { $0.key < $1.key }) {
                        if Int(index).map({ (0..<IRCPalette.count).contains($0) }) != true {
                            problems.append("“\(path).\(index)”: IRC color indexes run from 0 to 98.")
                        } else if ThemeColor(hex: item.stringValue ?? "") == nil {
                            problems.append("“\(path).\(index)” is not a hex color.")
                        }
                    }
                case "vibrancy":
                    if ThemeVibrancy(rawValue: value.stringValue ?? "") == nil {
                        problems.append(ThemeProblems.vibrancyMessage(path: path, value: value.stringValue))
                    }
                case AccentCustomizations.markerKey, MessageBoxBorderCustomizations.markerKey:
                    // Written by the accent or border picker: the keys it set.
                    if value.arrayValue?.allSatisfy({ $0.stringValue != nil }) != true {
                        problems.append("“\(path)” must be a list of token names.")
                    }
                default:
                    if ThemeRegistry.token(key) == nil {
                        let suggestion = ThemeProblems.suggestion(forToken: key).map { " Did you mean “\($0)”?" } ?? ""
                        problems.append("“\(path)” is not a theme color token, so it's ignored.\(suggestion)")
                    } else if ThemeColor(hex: value.stringValue ?? "") == nil {
                        problems.append("“\(path)” is not a hex color.")
                    }
                }
            }
        }
        check(customizations, prefix: "")
        return problems
    }

    /// `"[A][B]"` → `["A", "B"]`; `nil` if the key isn't a scope key.
    static func scopePatterns(in key: String) -> [String]? {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        var patterns: [String] = []
        var rest = Substring(trimmed)
        while !rest.isEmpty {
            guard rest.first == "[", let close = rest.firstIndex(of: "]") else { return nil }
            patterns.append(String(rest[rest.index(after: rest.startIndex)..<close]).trimmingCharacters(in: .whitespaces))
            rest = rest[rest.index(after: close)...].drop(while: { $0 == " " })
        }
        return patterns.isEmpty ? nil : patterns
    }

    static func matches(_ pattern: String, name: String, id: String) -> Bool {
        glob(pattern, matches: name) || glob(pattern, matches: id)
    }

    /// Case-insensitive glob with `*` as the only wildcard.
    static func glob(_ pattern: String, matches text: String) -> Bool {
        let p = Array(pattern.lowercased()), t = Array(text.lowercased())
        var pi = 0, ti = 0, star = -1, mark = 0
        while ti < t.count {
            if pi < p.count, p[pi] != "*", p[pi] == t[ti] {
                pi += 1; ti += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; mark = ti; pi += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; ti = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}

/// Turns a `ThemeDefinition` (plus its includes and the user's overrides)
/// into a `ResolvedTheme`.
///
/// Precedence, lowest first: token default for the theme's kind → included
/// base theme(s) → the theme's own colors → global overrides → overrides
/// scoped to this theme.
public enum ThemeResolver {
    /// Maximum `include` depth, to keep pathological chains cheap.
    public static let maxIncludeDepth = 8

    public static func resolve(
        _ definition: ThemeDefinition,
        id: String,
        includeLoader: (String) throws -> ThemeDefinition?,
        overrides: [String: String]
    ) throws -> ResolvedTheme {
        try resolve(definition, id: id, includeLoader: includeLoader, overrides: ThemeOverrides(colors: overrides))
    }

    public static func resolve(
        _ definition: ThemeDefinition,
        id: String,
        includeLoader: (String) throws -> ThemeDefinition?,
        overrides: ThemeOverrides
    ) throws -> ResolvedTheme {
        let flat = try flatten(definition, includeLoader: includeLoader)
        try flat.validate()

        var explicit: [String: ThemeColor] = [:]
        for (key, value) in flat.colors {
            explicit[key] = ThemeColor(hex: value)
        }
        // Overrides with invalid values are skipped rather than failing the
        // whole theme; `ThemeOverrides.problems(in:)` reports them.
        for (key, value) in overrides.colors {
            if let color = ThemeColor(hex: value) { explicit[key] = color }
        }

        let colors = resolveColors(kind: flat.type, explicit: explicit)

        var nickColors = NickPalette.defaultPalette(for: flat.type)
        if let custom = flat.nickColors?.compactMap(ThemeColor.init(hex:)), !custom.isEmpty {
            nickColors = custom
        }
        if let custom = overrides.nickColors?.compactMap(ThemeColor.init(hex:)), !custom.isEmpty {
            nickColors = custom
        }

        var ircColors = IRCPalette.standard
        for source in [flat.ircColors ?? [:], overrides.ircColors] {
            for (key, value) in source {
                guard let index = Int(key), ircColors.indices.contains(index),
                      let color = ThemeColor(hex: value) else { continue }
                ircColors[index] = color
            }
        }

        return ResolvedTheme(
            id: id,
            name: flat.name,
            kind: flat.type,
            vibrancy: overrides.vibrancy ?? flat.vibrancy ?? .none,
            colors: colors,
            nickColors: nickColors,
            ircColors: ircColors
        )
    }

    /// Merges a definition with its `include` chain into a single
    /// self-contained definition (`include` is `nil` in the result). The
    /// including theme's `name`, `type` and metadata win; colors and IRC
    /// colors are merged key by key; `nickColors` and `vibrancy` are
    /// inherited when unset.
    public static func flatten(
        _ definition: ThemeDefinition,
        includeLoader: (String) throws -> ThemeDefinition?
    ) throws -> ThemeDefinition {
        // Cycles are detected by repeated include references rather than
        // names, so a user theme called "Dracula" may include the built-in
        // "Dracula" (the loader decides what a reference points to).
        var chain: [ThemeDefinition] = [definition]
        var references: [String] = []
        var next = definition.include
        while let reference = next?.trimmingCharacters(in: .whitespaces), !reference.isEmpty {
            if references.contains(where: { $0.caseInsensitiveCompare(reference) == .orderedSame })
                || references.count >= maxIncludeDepth {
                throw ThemeError.includeCycle([definition.name] + references + [reference])
            }
            references.append(reference)
            guard let base = try includeLoader(reference) else {
                throw ThemeError.includeNotFound(reference)
            }
            chain.append(base)
            next = base.include
        }

        var result = definition
        result.include = nil
        result.colors = [:]
        var ircColors: [String: String] = [:]
        var hasIRCColors = false
        // Apply from the deepest base up to the theme itself.
        for layer in chain.reversed() {
            result.colors.merge(layer.colors) { _, new in new }
            if let layerIRC = layer.ircColors {
                hasIRCColors = true
                ircColors.merge(layerIRC) { _, new in new }
            }
            if let nick = layer.nickColors { result.nickColors = nick }
            if let vibrancy = layer.vibrancy { result.vibrancy = vibrancy }
        }
        result.ircColors = hasIRCColors ? ircColors : nil
        return result
    }

    /// Resolves every registry token for `kind`, starting from `explicit`
    /// values and filling the rest from token defaults.
    public static func resolveColors(kind: ThemeKind, explicit: [String: ThemeColor]) -> [String: ThemeColor] {
        var evaluator = DefaultsEvaluator(
            explicit: explicit,
            fallback: kind == .dark ? ThemeColor(hex: "#808080")! : ThemeColor(hex: "#7F7F7F")!,
            defaults: { ThemeRegistry.token($0)?.defaultValue(for: kind) }
        )
        for token in ThemeRegistry.tokens {
            _ = evaluator.value(of: token.key)
        }
        return evaluator.resolved
    }
}

/// Evaluates token defaults recursively, memoizing results and breaking
/// reference cycles (a key that is reached while it's still being evaluated
/// gets the fallback color and is reported in `cycles`).
struct DefaultsEvaluator {
    private(set) var resolved: [String: ThemeColor]
    private(set) var cycles: Set<String> = []
    let fallback: ThemeColor
    let defaults: (String) -> TokenDefault?
    private var inProgress: Set<String> = []

    init(explicit: [String: ThemeColor], fallback: ThemeColor, defaults: @escaping (String) -> TokenDefault?) {
        self.resolved = explicit
        self.fallback = fallback
        self.defaults = defaults
    }

    mutating func value(of key: String) -> ThemeColor {
        if let color = resolved[key] { return color }
        guard let expression = defaults(key) else { return fallback }
        guard !inProgress.contains(key) else {
            cycles.insert(key)
            return fallback
        }
        inProgress.insert(key)
        let color = evaluate(expression)
        inProgress.remove(key)
        resolved[key] = color
        return color
    }

    private mutating func operand(_ text: String) -> ThemeColor {
        if text.hasPrefix("#") { return ThemeColor(hex: text) ?? fallback }
        return value(of: text)
    }

    private mutating func evaluate(_ expression: TokenDefault) -> ThemeColor {
        switch expression {
        case .hex(let hex):
            return ThemeColor(hex: hex) ?? fallback
        case .ref(let key):
            return operand(key)
        case .transparent(let key, let factor):
            let base = operand(key)
            return base.withAlpha(base.alpha * factor)
        case .mix(let first, let second, let amount):
            let a = operand(first)
            let b = operand(second)
            return a.mixed(with: b, amount: amount)
        case .contrast(let key):
            return Self.contrastingForeground(on: operand(key).withAlpha(1))
        }
    }

    /// White when it reaches AA (4.5:1) or beats the alternative; otherwise
    /// a near-black tinted with the fill's hue.
    static func contrastingForeground(on fill: ThemeColor) -> ThemeColor {
        let white = ThemeColor.white
        let dark = fill.mixed(with: .black, amount: 0.82)
        let whiteContrast = white.contrastRatio(against: fill)
        let darkContrast = dark.contrastRatio(against: fill)
        return whiteContrast >= 4.5 || whiteContrast >= darkContrast ? white : dark
    }
}
