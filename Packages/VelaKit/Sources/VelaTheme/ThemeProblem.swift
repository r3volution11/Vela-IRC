// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// Something in a theme file that Vela skipped. Unlike a `ThemeError`, a
/// problem doesn't stop the theme from loading: the rest of the file is
/// used, and only the key or value named here is left out.
public struct ThemeProblem: Sendable, Hashable, CustomStringConvertible {
    public enum Severity: String, Sendable, Hashable {
        /// Probably a typo: a key or token name Vela doesn't know.
        case warning
        /// A value Vela can't use.
        case error
    }

    public enum Kind: Sendable, Hashable {
        /// A top-level key that isn't part of a theme file.
        case unknownKey
        /// A name in `colors` that isn't a theme token.
        case unknownToken
        /// A `vibrancy` value other than `none`, `sidebar` or `window`.
        case invalidVibrancy
    }

    public let severity: Severity
    public let kind: Kind
    /// Where in the file, e.g. `fontSize`, `colors.sidebar.backgroud` or `vibrancy`.
    public let path: String
    /// A sentence for people editing the file by hand.
    public let message: String
    /// The name the author most likely meant, if there's a close one.
    public let suggestion: String?

    public init(severity: Severity, kind: Kind, path: String, message: String, suggestion: String? = nil) {
        self.severity = severity
        self.kind = kind
        self.path = path
        self.message = message
        self.suggestion = suggestion
    }

    public var description: String { message }
}

/// Finds typos and unusable values in theme files: unknown top-level keys,
/// unknown color tokens and bad `vibrancy` values. Used when themes load
/// (Settings → Appearance), by the theme editor and by `vela-theme-tool check`.
public enum ThemeProblems {
    /// Every top-level key a theme file may have.
    public static let knownKeys = [
        "$schema", "name", "type", "include", "author", "description",
        "colors", "nickColors", "ircColors", "vibrancy",
    ]

    /// Words that suggest a key is about fonts, sizes or layout, which
    /// themes don't set.
    static let layoutWords = [
        "font", "typeface", "size", "layout", "spacing", "padding", "margin",
        "width", "height", "density", "radius", "roundness", "lineheight",
        "avatar", "timestamp", "compact", "monospace",
    ]

    /// Problems in a theme file's top-level object.
    public static func check(_ value: JSONValue) -> [ThemeProblem] {
        guard let object = value.objectValue else { return [] }
        var problems: [ThemeProblem] = []
        for key in object.keys.sorted() where !knownKeys.contains(key) {
            problems.append(unknownKey(key))
        }
        if let vibrancy = object["vibrancy"], let problem = vibrancyProblem(vibrancy) {
            problems.append(problem)
        }
        if let colors = object["colors"]?.objectValue {
            problems += tokenProblems(Array(colors.keys))
        }
        return problems
    }

    /// Problems in raw theme JSON(C). Empty if the text doesn't parse; the
    /// loader reports that as an error instead.
    public static func check(_ data: Data) -> [ThemeProblem] {
        guard let value = try? JSONC.value(from: data) else { return [] }
        return check(value)
    }

    /// Problems left in a decoded definition: names in `colors` that aren't
    /// tokens. (Unknown keys and bad `vibrancy` values don't survive decoding.)
    public static func check(_ definition: ThemeDefinition) -> [ThemeProblem] {
        tokenProblems(Array(definition.colors.keys))
    }

    /// The token an unknown name most likely meant. Token names share long
    /// endings (`….background`), so only a near miss counts: at most
    /// `max(2, name.count / 6)` edits.
    public static func suggestion(forToken name: String) -> String? {
        guard ThemeRegistry.token(name) == nil else { return nil }
        return EditDistance.closest(to: name, in: ThemeRegistry.tokens.map(\.key), limit: max(2, name.count / 6))
    }

    /// The message for a value that isn't one of the vibrancy values.
    public static func vibrancyMessage(path: String, value: String?) -> String {
        let valid = "Use \"none\", \"sidebar\" or \"window\"."
        guard let value else { return "“\(path)” must be a string, so it's ignored. \(valid)" }
        if let match = ThemeVibrancy.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }) {
            return "“\(path)”: “\(value)” isn't a vibrancy value, so it's ignored. Did you mean \"\(match.rawValue)\"? \(valid)"
        }
        return "“\(path)”: “\(value)” isn't a vibrancy value, so it's ignored. \(valid)"
    }

    // MARK: Pieces

    private static func tokenProblems(_ names: [String]) -> [ThemeProblem] {
        names.sorted().compactMap { name in
            guard ThemeRegistry.token(name) == nil else { return nil }
            let suggestion = suggestion(forToken: name)
            var message = "“colors.\(name)” isn't a theme color token, so it's ignored."
            if let suggestion { message += " Did you mean “\(suggestion)”?" }
            return ThemeProblem(severity: .warning, kind: .unknownToken, path: "colors.\(name)", message: message, suggestion: suggestion)
        }
    }

    private static func unknownKey(_ key: String) -> ThemeProblem {
        var message = "“\(key)” isn't a theme key, so it's ignored."
        var suggestion: String?
        if ThemeRegistry.token(key) != nil {
            message += " Color tokens go inside \"colors\": { \"\(key)\": … }."
        } else if let close = EditDistance.closest(to: key, in: knownKeys) {
            suggestion = close
            message += " Did you mean “\(close)”?"
        } else if looksLikeLayout(key) {
            message += " Themes only contain colors: fonts, sizes and layout are settings (Settings → Messages and Layout, or settings.json)."
        }
        return ThemeProblem(severity: .warning, kind: .unknownKey, path: key, message: message, suggestion: suggestion)
    }

    private static func vibrancyProblem(_ value: JSONValue) -> ThemeProblem? {
        if let raw = value.stringValue, ThemeVibrancy(rawValue: raw) != nil { return nil }
        let suggestion = value.stringValue.flatMap { raw in
            ThemeVibrancy.allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }?.rawValue
        }
        return ThemeProblem(
            severity: .error,
            kind: .invalidVibrancy,
            path: "vibrancy",
            message: vibrancyMessage(path: "vibrancy", value: value.stringValue),
            suggestion: suggestion
        )
    }

    static func looksLikeLayout(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return layoutWords.contains { lowered.contains($0) }
    }
}
