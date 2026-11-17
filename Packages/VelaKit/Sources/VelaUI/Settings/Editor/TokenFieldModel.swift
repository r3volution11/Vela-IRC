// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A value a ``TokenField`` (or a ``SuggestionTextField``) offers.
nonisolated struct TokenSuggestion: Hashable, Identifiable, Sendable {
    /// What's stored when it's picked.
    var value: String
    /// What's shown, in the list and on the chip.
    var label: String
    /// Secondary text at the end of the row: a language code, a theme's
    /// kind, a timestamp preview.
    var detail: String?
    /// Draw the label in this font family (font suggestions).
    var previewFontFamily: String?

    var id: String { value }

    init(value: String, label: String? = nil, detail: String? = nil, previewFontFamily: String? = nil) {
        self.value = value
        self.label = label ?? value
        self.detail = detail
        self.previewFontFamily = previewFontFamily
    }
}

/// The logic of a Tagify-style token field, apart from its views: which
/// values it holds, committing typed text, duplicates, and filtering the
/// suggestions.
nonisolated struct TokenFieldModel: Equatable, Sendable {
    /// The values in order. A single-value field holds at most one.
    var values: [String]
    var allowsMultiple: Bool

    enum CommitResult: Equatable {
        /// A new value was added.
        case added(String)
        /// The single value was replaced.
        case replaced(String)
        /// Already there; nothing changed.
        case duplicate(String)
        /// The text isn't an acceptable value.
        case rejected
        /// Nothing typed.
        case empty
    }

    init(values: [String], allowsMultiple: Bool) {
        self.values = allowsMultiple ? values : Array(values.prefix(1))
        self.allowsMultiple = allowsMultiple
    }

    /// Adds `value`, or for a single-value field replaces it. Duplicates
    /// (ignoring case) are refused.
    @discardableResult
    mutating func add(_ value: String) -> CommitResult {
        guard !value.isEmpty else { return .empty }
        if contains(value) { return .duplicate(value) }
        if allowsMultiple {
            values.append(value)
            return .added(value)
        }
        let replacing = !values.isEmpty
        values = [value]
        return replacing ? .replaced(value) : .added(value)
    }

    /// Commits typed text: a suggestion whose label or value matches it
    /// (ignoring case) wins; otherwise `resolve` turns the text into a value,
    /// or rejects it by returning nil.
    @discardableResult
    mutating func commit(_ text: String, suggestions: [TokenSuggestion], resolve: (String) -> String?) -> CommitResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let value = Self.resolve(trimmed, suggestions: suggestions, resolve: resolve) else { return .rejected }
        return add(value)
    }

    mutating func remove(_ value: String) {
        values.removeAll { $0 == value }
    }

    /// ⌫ in an empty field: removes the last value.
    @discardableResult
    mutating func removeLast() -> String? {
        values.popLast()
    }

    func contains(_ value: String) -> Bool {
        values.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }

    // MARK: Helpers

    /// The value typed `text` stands for (see ``commit(_:suggestions:resolve:)``).
    static func resolve(_ text: String, suggestions: [TokenSuggestion], resolve: (String) -> String?) -> String? {
        if let match = suggestions.first(where: {
            $0.label.caseInsensitiveCompare(text) == .orderedSame || $0.value.caseInsensitiveCompare(text) == .orderedSame
        }) {
            return match.value
        }
        return resolve(text)
    }

    /// Splits typed or pasted text on commas: the complete pieces (trimmed,
    /// empty ones dropped) and what follows the last comma, still being typed.
    static func split(_ text: String) -> (pieces: [String], remainder: String) {
        guard text.contains(",") else { return ([], text) }
        var parts = text.components(separatedBy: ",")
        let remainder = parts.removeLast()
        let pieces = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (pieces, remainder.trimmingCharacters(in: .whitespaces).isEmpty ? "" : remainder)
    }

    /// Suggestions for `query`, without the ones already chosen: everything
    /// for an empty query; otherwise matches in the label, value or detail,
    /// those starting with the query first.
    static func filter(_ suggestions: [TokenSuggestion], query: String, excluding chosen: [String] = [], limit: Int = 200) -> [TokenSuggestion] {
        let available = suggestions.filter { suggestion in
            !chosen.contains { $0.caseInsensitiveCompare(suggestion.value) == .orderedSame }
        }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Array(available.prefix(limit)) }
        var prefixed: [TokenSuggestion] = []
        var contained: [TokenSuggestion] = []
        for suggestion in available {
            let label = suggestion.label.lowercased()
            let value = suggestion.value.lowercased()
            if label.hasPrefix(needle) || value.hasPrefix(needle) {
                prefixed.append(suggestion)
            } else if label.contains(needle) || value.contains(needle) || (suggestion.detail?.lowercased().contains(needle) ?? false) {
                contained.append(suggestion)
            }
        }
        return Array((prefixed + contained).prefix(limit))
    }

    /// The suggestion Return picks without arrowing to it: the first one,
    /// when it starts with what's typed. Otherwise Return commits the text
    /// as typed, so a custom value isn't swapped for a longer suggestion.
    static func autoHighlight(query: String, in filtered: [TokenSuggestion]) -> Int? {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty, let first = filtered.first else { return nil }
        return first.label.lowercased().hasPrefix(needle) || first.value.lowercased().hasPrefix(needle) ? 0 : nil
    }
}
