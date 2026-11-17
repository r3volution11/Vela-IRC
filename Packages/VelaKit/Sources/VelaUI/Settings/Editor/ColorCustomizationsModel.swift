// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaTheme

/// `appearance.colorCustomizations` as the settings editor shows it:
/// top-level overrides (every theme), then one group per `"[Theme]"` scope.
///
/// The accent picker in Settings → Appearance writes into a theme's scope
/// and lists the tokens it wrote under `"$accentPicker"`; those are marked.
/// Editing one by hand makes it yours: it leaves that list, so picking
/// Default later keeps it.
nonisolated struct ColorCustomizationsModel: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A theme token set to a hex color.
        case color(ThemeColor)
        /// A theme token whose value isn't a hex color.
        case invalidColor
        /// A key that isn't a theme token.
        case unknownToken
        /// `"nickColors"`: the nick palette.
        case nickColors([ThemeColor])
        /// `"ircColors"`: mIRC index → color.
        case ircColors([IRCColor])
        /// `"vibrancy"`: `"none"`, `"sidebar"` or `"window"`.
        case vibrancy(String)
        /// Anything else (nested objects, wrong types): edited as JSON.
        case other
    }

    struct IRCColor: Equatable, Sendable {
        let index: String
        let color: ThemeColor?
    }

    struct Entry: Equatable, Identifiable, Sendable {
        let token: String
        let value: JSONValue
        let kind: Kind
        /// Written by the accent picker (listed in the scope's `$accentPicker`).
        let isAccentPicker: Bool

        var id: String { token }

        /// Token entries edited with a color well.
        var isColorToken: Bool {
            switch kind {
            case .color, .invalidColor, .unknownToken: true
            default: false
            }
        }
    }

    struct Scope: Equatable, Identifiable, Sendable {
        /// The key in settings.json: `"[Palenight]"`, `"[Nord][Dracula]"`.
        let key: String
        /// The theme names (or patterns with `*`) in the key.
        let patterns: [String]
        let entries: [Entry]
        /// Tokens the accent picker wrote here.
        let accentPickerTokens: [String]

        var id: String { key }
        /// `"Palenight"`, `"Nord, Dracula"`.
        var title: String { patterns.joined(separator: ", ") }
    }

    /// Entries for every theme, sorted by token.
    let topLevel: [Entry]
    /// Theme scopes, sorted by title.
    let scopes: [Scope]

    static let markerKey = AccentCustomizations.markerKey
    /// `$accentPicker` and the message box border picker's `$borderPicker`:
    /// lists of tokens, not entries.
    static let pickerMarkerKeys = AccentCustomizations.pickerMarkerKeys
    static let specialKeys = ["nickColors", "ircColors", "vibrancy"]
    static let vibrancyValues = ["none", "sidebar", "window"]

    init(_ customizations: [String: JSONValue]) {
        var topLevel: [Entry] = []
        var scopes: [Scope] = []
        for key in customizations.keys {
            let value = customizations[key]!
            if let patterns = Self.scopePatterns(in: key), let object = value.objectValue {
                let marked = Self.markerTokens(in: object)
                let entries = object.keys
                    .filter { !Self.pickerMarkerKeys.contains($0) && Self.scopePatterns(in: $0) == nil }
                    .sorted()
                    .map { Self.entry(token: $0, value: object[$0]!, isAccentPicker: marked.contains($0)) }
                    // Scopes nested in scopes don't apply; they're shown
                    // so they can be fixed.
                    + object.keys.filter { Self.scopePatterns(in: $0) != nil }.sorted()
                    .map { Entry(token: $0, value: object[$0]!, kind: .other, isAccentPicker: false) }
                scopes.append(Scope(key: key, patterns: patterns, entries: entries, accentPickerTokens: marked))
            } else if !Self.pickerMarkerKeys.contains(key) {
                topLevel.append(Self.entry(token: key, value: value, isAccentPicker: false))
            }
        }
        self.topLevel = topLevel.sorted { $0.token < $1.token }
        self.scopes = scopes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// How many overrides there are, counting the accent picker's.
    var count: Int { topLevel.count + scopes.reduce(0) { $0 + $1.entries.count } }

    func scope(_ key: String) -> Scope? { scopes.first { $0.key == key } }

    private static func entry(token: String, value: JSONValue, isAccentPicker: Bool) -> Entry {
        let kind: Kind
        switch token {
        case "nickColors":
            if let array = value.arrayValue {
                kind = .nickColors(array.compactMap { $0.stringValue.flatMap(ThemeColor.init(hex:)) })
            } else {
                kind = .other
            }
        case "ircColors":
            if let object = value.objectValue {
                let colors = object.keys
                    .sorted { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }
                    .map { IRCColor(index: $0, color: object[$0]?.stringValue.flatMap(ThemeColor.init(hex:))) }
                kind = .ircColors(colors)
            } else {
                kind = .other
            }
        case "vibrancy":
            kind = value.stringValue.map { .vibrancy($0) } ?? .other
        default:
            if let hex = value.stringValue {
                if ThemeRegistry.token(token) == nil {
                    kind = .unknownToken
                } else if let color = ThemeColor(hex: hex) {
                    kind = .color(color)
                } else {
                    kind = .invalidColor
                }
            } else {
                kind = .other
            }
        }
        return Entry(token: token, value: value, kind: kind, isAccentPicker: isAccentPicker)
    }

    // MARK: Editing

    /// `customizations` with `token` set to `value` (nil removes it) at the
    /// top level or in `scope`.
    ///
    /// A token the accent picker wrote becomes hand-written: it leaves the
    /// scope's `$accentPicker` list (dropped when empty). Removing a scope's
    /// last token removes the scope.
    static func setting(
        _ token: String,
        to value: JSONValue?,
        inScope scope: String?,
        of customizations: [String: JSONValue]
    ) -> [String: JSONValue] {
        var result = customizations
        guard let scope else {
            result[token] = value
            return result
        }
        var object = result[scope]?.objectValue ?? [:]
        object[token] = value
        // Either picker's list: a token edited by hand leaves it.
        for marker in pickerMarkerKeys {
            var marked = (object[marker]?.arrayValue ?? []).compactMap(\.stringValue)
            if marked.contains(token) {
                marked.removeAll { $0 == token }
                object[marker] = marked.isEmpty ? nil : .array(marked.map { .string($0) })
            }
        }
        let isEmpty = object.keys.allSatisfy { pickerMarkerKeys.contains($0) }
        result[scope] = isEmpty && value == nil ? nil : .object(object)
        return result
    }

    /// `customizations` with `token` renamed to `newToken` (keeping its
    /// value) at the top level or in `scope`. An existing `newToken` is
    /// replaced.
    static func renaming(
        _ token: String,
        to newToken: String,
        inScope scope: String?,
        of customizations: [String: JSONValue]
    ) -> [String: JSONValue] {
        guard token != newToken else { return customizations }
        let value = scope == nil ? customizations[token] : customizations[scope!]?.objectValue?[token]
        guard let value else { return customizations }
        let added = setting(newToken, to: value, inScope: scope, of: customizations)
        return setting(token, to: nil, inScope: scope, of: added)
    }

    /// `customizations` without the scope `key`.
    static func removingScope(_ key: String, from customizations: [String: JSONValue]) -> [String: JSONValue] {
        var result = customizations
        result[key] = nil
        return result
    }

    /// The scope key for a theme: an existing scope naming exactly that
    /// theme (any case), else `"[Name]"`.
    static func scopeKey(forTheme name: String, in customizations: [String: JSONValue]) -> String {
        let existing = customizations.keys.sorted().first { key in
            guard let patterns = scopePatterns(in: key), patterns.count == 1 else { return false }
            return patterns[0].caseInsensitiveCompare(name) == .orderedSame
        }
        return existing ?? "[\(name)]"
    }

    // MARK: Scopes

    /// `"[A][B]"` → `["A", "B"]`; nil if `key` isn't a scope key. Mirrors
    /// how themes read them (`ThemeOverrides`).
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

    /// Whether a scope pattern names a theme: case-insensitive, `*`
    /// matching any run of characters.
    static func pattern(_ pattern: String, matches name: String) -> Bool {
        let p = Array(pattern.lowercased()), t = Array(name.lowercased())
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

    static func markerTokens(in scope: [String: JSONValue]) -> [String] {
        (scope[markerKey]?.arrayValue ?? []).compactMap(\.stringValue)
    }
}
