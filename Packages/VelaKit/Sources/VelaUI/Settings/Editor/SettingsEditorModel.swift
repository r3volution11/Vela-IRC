// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaStore

// The settings editor's data: which settings to list (known ones plus
// unknown keys found in settings.json), how the search query filters them,
// and how they group into categories. Pure, so it's unit-tested.

// MARK: - Query

/// The settings editor's search text, parsed: words plus filters.
///
/// - `@modified`: settings set in settings.json.
/// - `@unknown`: keys in settings.json that Vela doesn't know.
/// - `@category:<id>`: a ``SettingsCategory`` (by id, or by title without
///   spaces: `@category:messages`). Several are OR'ed.
/// - `@pane:<id>`: the settings shown on a Settings pane (`SettingsPane` id).
///   Several are OR'ed.
///
/// Words must all appear in a setting's title, key, description or current
/// value (case-insensitive). Incomplete or unknown filters (`@mod`) are
/// ignored, so the list doesn't blank out while one is being typed.
nonisolated struct SettingsQuery: Equatable, Sendable {
    var words: [String] = []
    var modified = false
    var unknown = false
    var categories: [String] = []
    var panes: [String] = []

    static let modifiedToken = "@modified"
    static let unknownToken = "@unknown"
    static let categoryPrefix = "@category:"
    static let panePrefix = "@pane:"

    init(_ text: String) {
        for raw in text.split(whereSeparator: \.isWhitespace) {
            let token = raw.lowercased()
            if token == Self.modifiedToken {
                modified = true
            } else if token == Self.unknownToken {
                unknown = true
            } else if token.hasPrefix(Self.categoryPrefix) {
                let value = String(token.dropFirst(Self.categoryPrefix.count))
                if !value.isEmpty { categories.append(value) }
            } else if token.hasPrefix(Self.panePrefix) {
                let value = String(token.dropFirst(Self.panePrefix.count))
                if !value.isEmpty { panes.append(value) }
            } else if token.hasPrefix("@") {
                continue
            } else {
                words.append(token)
            }
        }
    }

    /// No words and no filters: everything matches.
    var isEmpty: Bool { words.isEmpty && !hasFilters }

    var hasFilters: Bool { modified || unknown || !categories.isEmpty || !panes.isEmpty }

    /// Narrowed to a category, a pane or unknown keys (what the category
    /// chips set).
    var hasScope: Bool { unknown || !categories.isEmpty || !panes.isEmpty }

    func matches(_ entry: SettingsEditorEntry) -> Bool {
        if modified, !entry.isModified { return false }
        if unknown, !entry.isUnknown { return false }
        if !categories.isEmpty {
            guard let category = entry.category,
                  categories.contains(where: { Self.names(category).contains($0) })
            else { return false }
        }
        if !panes.isEmpty {
            guard let pane = entry.category?.paneID.lowercased(), panes.contains(pane) else { return false }
        }
        return words.allSatisfy { entry.searchText.contains($0) }
    }

    /// Whether a category chip is on: its category is one of the filters.
    func includes(_ category: SettingsCategory) -> Bool {
        categories.contains { Self.names(category).contains($0) }
    }

    /// What `@category:` accepts for a category: its id and its title
    /// without spaces (`chat` and `messages`).
    static func names(_ category: SettingsCategory) -> [String] {
        [category.rawValue.lowercased(), category.title.lowercased().filter { !$0.isWhitespace }]
    }

    // MARK: Editing the text

    /// `text` with `token` added at the end, or removed when it's there
    /// (any case).
    static func toggling(_ token: String, in text: String) -> String {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let lowered = token.lowercased()
        if tokens.contains(where: { $0.lowercased() == lowered }) {
            tokens.removeAll { $0.lowercased() == lowered }
        } else {
            tokens.append(token)
        }
        return tokens.joined(separator: " ")
    }

    /// `text` without category, pane and unknown filters, plus `scope` (a
    /// filter such as `@category:chat`) when given. What the category chips do.
    static func settingScope(_ scope: String?, in text: String) -> String {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init).filter { token in
            let lowered = token.lowercased()
            return !(lowered.hasPrefix(categoryPrefix) || lowered.hasPrefix(panePrefix) || lowered == unknownToken)
        }
        if let scope { tokens.append(scope) }
        return tokens.joined(separator: " ")
    }

    /// The filter tokens offered while typing a word that starts with `@`.
    static func filterCompletions(for word: String, categories: [SettingsCategory], panes: [(id: String, title: String)]) -> [(value: String, detail: String)] {
        let lowered = word.lowercased()
        guard lowered.hasPrefix("@") else { return [] }
        var all: [(value: String, detail: String)] = [
            (modifiedToken, "Settings set in settings.json"),
            (unknownToken, "Keys Vela doesn't know"),
        ]
        all += categories.map { ("\(categoryPrefix)\($0.rawValue)", "Category: \($0.title)") }
        all += panes.map { ("\(panePrefix)\($0.id)", "Shown on the \($0.title) pane") }
        return all.filter { $0.value.hasPrefix(lowered) && $0.value != lowered }
    }
}

// MARK: - Entries

/// One row of the settings editor: a known setting, or a key in
/// settings.json that Vela doesn't know.
nonisolated struct SettingsEditorEntry: Identifiable, Hashable, Sendable {
    let key: String
    /// Nil for unknown keys.
    let descriptor: SettingDescriptor?
    /// The value set in settings.json, if any.
    let value: JSONValue?
    /// Lowercased title, key, description and value, for search.
    let searchText: String

    init(key: String, descriptor: SettingDescriptor?, value: JSONValue?) {
        self.key = key
        self.descriptor = descriptor
        self.value = value
        let shown = value ?? descriptor?.defaultValue
        let parts = [
            descriptor?.title ?? key,
            key,
            descriptor?.summary ?? "",
            shown.map(SettingsJSONText.compact) ?? "",
        ]
        searchText = parts.joined(separator: "\n").lowercased()
    }

    var id: String { key }
    var isModified: Bool { value != nil }
    var isUnknown: Bool { descriptor == nil }
    var category: SettingsCategory? { descriptor?.settingsCategory }
    /// The value in effect: the one in settings.json, else the default.
    var effectiveValue: JSONValue { value ?? descriptor?.defaultValue ?? .null }

    /// Every known setting in catalog order, then unknown keys from `values`
    /// sorted by key.
    static func all(catalog: [SettingDescriptor], values: [String: JSONValue]) -> [SettingsEditorEntry] {
        let known = Set(catalog.map(\.key))
        let entries = catalog.map { SettingsEditorEntry(key: $0.key, descriptor: $0, value: values[$0.key]) }
        let unknown = values.keys
            .filter { !known.contains($0) }
            .sorted()
            .map { SettingsEditorEntry(key: $0, descriptor: nil, value: values[$0]) }
        return entries + unknown
    }
}

/// A run of entries under one header: a category, or the unknown keys.
nonisolated struct SettingsEditorGroup: Identifiable, Hashable, Sendable {
    /// Nil for unknown keys (and known keys without a category).
    let category: SettingsCategory?
    let isUnknown: Bool
    let entries: [SettingsEditorEntry]

    var id: String { category?.rawValue ?? (isUnknown ? "unknown" : "other") }
    var title: String { category?.title ?? (isUnknown ? "Unknown" : "Other") }

    /// `entries` grouped in ``SettingsCategory`` order, keeping their order
    /// within a group; known settings without a category next, unknown keys
    /// last.
    static func grouping(_ entries: [SettingsEditorEntry]) -> [SettingsEditorGroup] {
        var groups: [SettingsEditorGroup] = SettingsCategory.allCases.compactMap { category in
            let members = entries.filter { $0.category == category }
            return members.isEmpty ? nil : SettingsEditorGroup(category: category, isUnknown: false, entries: members)
        }
        let other = entries.filter { !$0.isUnknown && $0.category == nil }
        if !other.isEmpty { groups.append(SettingsEditorGroup(category: nil, isUnknown: false, entries: other)) }
        let unknown = entries.filter(\.isUnknown)
        if !unknown.isEmpty { groups.append(SettingsEditorGroup(category: nil, isUnknown: true, entries: unknown)) }
        return groups
    }
}

// MARK: - Numbers

/// Typed numbers: parsing, range checks, clamping and display.
nonisolated enum NumberSettingInput {
    enum Problem: Error, Equatable {
        case notANumber
        case notWhole
        case outOfRange(ClosedRange<Double>)

        func message(integer: Bool) -> String {
            switch self {
            case .notANumber: integer ? "Enter a whole number." : "Enter a number."
            case .notWhole: "Enter a whole number."
            case .outOfRange(let range):
                "Must be between \(NumberSettingInput.format(range.lowerBound, integer: integer)) and \(NumberSettingInput.format(range.upperBound, integer: integer))."
            }
        }
    }

    /// The number typed in `text`, if it's one and fits `range`.
    static func parse(_ text: String, range: ClosedRange<Double>?, integer: Bool) -> Result<Double, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value.isFinite else { return .failure(.notANumber) }
        if integer, value.rounded() != value { return .failure(.notWhole) }
        if let range, !range.contains(value) { return .failure(.outOfRange(range)) }
        return .success(value)
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>?) -> Double {
        guard let range else { return value }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// The stepper's step: a twentieth of a range no wider than 1
    /// (`tabs.roundness`), 10 or 100 for ranges over 1,000 or 10,000 wide,
    /// else 1.
    static func step(for range: ClosedRange<Double>?, integer: Bool) -> Double {
        guard let range else { return 1 }
        let width = range.upperBound - range.lowerBound
        if width > 10_000 { return 100 }
        if width > 1_000 { return 10 }
        if width <= 1, !integer { return width / 20 }
        return 1
    }

    /// `13`, `0.35`, `2.5`: no trailing zeros.
    static func format(_ value: Double, integer: Bool) -> String {
        if integer || value.rounded() == value, abs(value) < 1e15 { return String(Int(value.rounded())) }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

// MARK: - JSON text

nonisolated enum SettingsJSONText {
    /// Compact JSON for a value: `"grouped"`, `13`, `["a","b"]`.
    static func compact(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    /// `"chat.fontSize": 13`, as it would appear in settings.json.
    static func entry(key: String, value: JSONValue) -> String {
        "\(compact(.string(key))): \(compact(value))"
    }

    enum Parsed: Equatable {
        case value(JSONValue)
        /// Why the text isn't JSON.
        case problem(String)
    }

    /// Parses JSON (with comments) typed for a value, or says why it isn't.
    static func parse(_ text: String) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .problem("Enter a JSON value, such as true, 12, \"text\" or [\"a\", \"b\"].") }
        do {
            return .value(try JSONC.value(from: Data(trimmed.utf8)))
        } catch {
            return .problem("Not valid JSON. Strings need double quotes, like \"text\".")
        }
    }

    /// The type of a schema (`"boolean"`, `"number"`, `"integer"`,
    /// `"string"`, `"array"`, `"object"`), or nil (`SystemFollowingBool`).
    static func schemaType(_ schema: JSONValue) -> String? {
        schema.objectValue?["type"]?.stringValue
    }
}
