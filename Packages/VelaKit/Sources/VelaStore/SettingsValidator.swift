// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// A problem in settings.json text, for squiggles and a problems list.
public struct SettingsDiagnostic: Sendable, Hashable {
    public enum Severity: Int, Sendable, Hashable, Comparable {
        case error
        case warning
        case info

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Kind: Sendable, Hashable {
        /// A syntax error (``JSONCParseError``).
        case syntax(JSONCParseError.Code)
        /// The top-level value isn't an object.
        case notAnObject
        /// A key that appears again later (only the last one counts).
        case duplicateKey
        /// A key Vela doesn't know.
        case unknownKey
        /// A key older versions of Vela used; it's converted at launch.
        case legacyKey
        /// The value has the wrong type (or, for arrays, an element does).
        case typeMismatch
        /// A string that isn't one of the allowed values.
        case valueNotAllowed
        /// A number outside the setting's range.
        case outOfRange
        /// A message from one of the `extraChecks`.
        case extraCheck
    }

    /// UTF-16 range in the text. Never empty unless the text is: problems
    /// at a position (a missing comma at the end, say) cover the character
    /// or token before it.
    public let range: NSRange
    public let severity: Severity
    public let kind: Kind
    public let message: String
    /// The top-level setting the problem is in, if any.
    public let key: String?
    /// For ``Kind/unknownKey``: the known key the user probably meant
    /// (for a "Change to …" quick fix).
    public let suggestedKey: String?

    public init(range: NSRange, severity: Severity, kind: Kind, message: String, key: String? = nil, suggestedKey: String? = nil) {
        self.range = range
        self.severity = severity
        self.kind = kind
        self.message = message
        self.key = key
        self.suggestedKey = suggestedKey
    }
}

/// Checks settings.json text against ``SettingsCatalog``: syntax, duplicate
/// and unknown keys, value types, allowed values and ranges.
///
/// ```swift
/// let diagnostics = SettingsValidator.diagnostics(for: text, extraChecks: [
///     "appearance.colorCustomizations": { value in
///         ThemeOverrides.problems(in: value.objectValue ?? [:])
///     },
/// ])
/// ```
public enum SettingsValidator {
    /// Problems in `text`, sorted by position.
    ///
    /// - Syntax errors and a top level that isn't an object are errors.
    /// - Values Vela can't use (wrong type, a value not in the list) are
    ///   errors: Vela ignores them and uses the default.
    /// - Unknown and duplicate keys and out-of-range numbers are warnings.
    /// - Keys from older versions (converted at launch) are info.
    /// - `extraChecks[key]` runs on the value of each top-level `key` that
    ///   has a usable value; each message becomes a warning on the value.
    public static func diagnostics(
        for text: String,
        extraChecks: [String: (JSONValue) -> [String]] = [:]
    ) -> [SettingsDiagnostic] {
        diagnostics(for: JSONCDocument(text), extraChecks: extraChecks)
    }

    /// ``diagnostics(for:extraChecks:)`` for text that's already parsed.
    public static func diagnostics(
        for document: JSONCDocument,
        extraChecks: [String: (JSONValue) -> [String]] = [:]
    ) -> [SettingsDiagnostic] {
        var checker = Checker(document: document)
        checker.run(extraChecks: extraChecks)
        return checker.diagnostics.enumerated()
            .sorted { ($0.element.range.location, $0.offset) < ($1.element.range.location, $1.offset) }
            .map(\.element)
    }

    /// The known setting an unknown `key` most likely meant, by edit
    /// distance (ignoring case) and by matching the part after the dot.
    public static func suggestion(forUnknownKey key: String) -> String? {
        guard descriptors[key] == nil else { return nil }
        let known = catalog.map(\.key)
        let lowered = key.lowercased()
        if let exact = known.first(where: { $0.lowercased() == lowered }) { return exact }

        let limit = max(2, key.count / 4)
        var best: (key: String, distance: Int)?
        for candidate in known {
            let distance = editDistance(lowered, candidate.lowercased())
            if distance <= limit, distance < best?.distance ?? .max {
                best = (candidate, distance)
            }
        }
        if let best { return best.key }

        // `fontSize` or `foo.fontsize` → `chat.fontSize`: the same name in
        // another group (the first in catalog order).
        let name = lowered.split(separator: ".").last.map(String.init) ?? lowered
        guard !name.isEmpty else { return nil }
        return known.first { candidate in
            let candidateName = candidate.lowercased().split(separator: ".").last.map(String.init) ?? ""
            return candidateName == name || (name.count >= 4 && candidate.lowercased().hasSuffix(lowered))
        }
    }

    /// Keys allowed in settings.json besides the settings themselves.
    static let metaKeys: Set<String> = ["$schema"]

    /// ``SettingsCatalog/all`` (built once), in catalog order.
    static let catalog: [SettingDescriptor] = SettingsCatalog.all
    /// ``catalog`` by key.
    static let descriptors: [String: SettingDescriptor] = Dictionary(
        catalog.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }
    )

    /// Keys older versions of Vela wrote, and what replaced them.
    static let legacyKeys: [String: String] = [
        SettingsMigration.LegacyKey.blockedDomains: "media.siteRules",
        SettingsMigration.LegacyKey.allowedDomains: "media.siteRules",
        SettingsMigration.LegacyKey.mediaPresentation: "media.linkPreviewSize, media.videos and media.imageSize",
        SettingsMigration.LegacyKey.mediaLoadVideoEmbeds: "media.videos",
    ]

    /// Optimal string alignment distance (Levenshtein plus transpositions).
    static func editDistance(_ a: String, _ b: String) -> Int {
        EditDistance.distance(a, b)
    }
}

// MARK: - Checking

private struct Checker {
    let document: JSONCDocument
    var diagnostics: [SettingsDiagnostic] = []

    init(document: JSONCDocument) {
        self.document = document
    }

    mutating func run(extraChecks: [String: (JSONValue) -> [String]]) {
        for error in document.errors {
            add(error.range, .error, .syntax(error.code), error.message)
        }
        guard let root = document.root else { return }
        guard root.kind == .object else {
            add(root.range, .error, .notAnObject, "Settings must be an object: { \"setting\": value }.")
            return
        }

        let lastIndex = Dictionary(root.properties.enumerated().map { ($0.element.key, $0.offset) }, uniquingKeysWith: max)
        for (index, property) in root.properties.enumerated() {
            let key = property.key
            guard lastIndex[key] == index else {
                add(property.keyRange, .warning, .duplicateKey, "“\(key)” is set again below; only the last one is used.", key: key)
                continue
            }
            let descriptor = SettingsValidator.descriptors[key]
            if descriptor == nil {
                if let replacement = SettingsValidator.legacyKeys[key] {
                    add(property.keyRange, .info, .legacyKey,
                        "Replaced by \(replacement). Vela converts this setting when it starts.", key: key)
                } else if !SettingsValidator.metaKeys.contains(key) {
                    let suggestion = SettingsValidator.suggestion(forUnknownKey: key)
                    let message = "Unknown setting." + (suggestion.map { " Did you mean “\($0)”?" } ?? "")
                    add(property.keyRange, .warning, .unknownKey, message, key: key, suggestedKey: suggestion)
                }
            }
            guard let value = property.value, value.kind != .invalid else { continue }
            let before = diagnostics.count
            if let descriptor { check(value, against: descriptor) }
            // Extra checks only make sense for a value of the right type.
            let wrongType = diagnostics[before...].contains { $0.kind == .typeMismatch && $0.range == value.range }
            if let extraCheck = extraChecks[key], !wrongType, let json = value.jsonValue {
                for message in extraCheck(json) {
                    add(value.range, .warning, .extraCheck, message, key: key)
                }
            }
        }
    }

    // MARK: Schema

    private mutating func check(_ node: JSONCNode, against descriptor: SettingDescriptor) {
        let key = descriptor.key
        if descriptor.followsSystem {
            if node.kind != .boolean, node.scalarValue != .string(SystemFollowingBool.system.rawValue) {
                add(node.range, .error, .typeMismatch, "Expected true, false or \"system\".", key: key)
            }
            return
        }
        check(node, schema: descriptor.schema, key: key)
        if let allowed = descriptor.objectValueEnum, node.kind == .object {
            for property in node.properties {
                guard let value = property.value, value.kind != .invalid else { continue }
                if value.kind != .string {
                    add(value.range, .error, .typeMismatch, "Expected one of \(Self.list(allowed)).", key: key)
                } else if let string = value.scalarValue?.stringValue, !allowed.contains(string) {
                    add(value.range, .error, .valueNotAllowed, "Value is not accepted. Valid values: \(Self.list(allowed)).", key: key)
                }
            }
        }
    }

    private mutating func check(_ node: JSONCNode, schema: JSONValue, key: String) {
        guard let schema = schema.objectValue else { return }
        if let branches = schema["oneOf"]?.arrayValue ?? schema["anyOf"]?.arrayValue {
            let matches = branches.contains { branch in
                var trial = Checker(document: document)
                trial.check(node, schema: branch, key: key)
                return trial.diagnostics.allSatisfy { $0.severity != .error }
            }
            if !matches {
                add(node.range, .error, .typeMismatch, "Value doesn't match any of the allowed types.", key: key)
            }
            return
        }

        switch schema["type"]?.stringValue {
        case "boolean":
            guard node.kind == .boolean else { return mismatch(node, "Expected true or false.", key) }
        case "string":
            guard node.kind == .string else { return mismatch(node, "Expected a string.", key) }
        case "number":
            guard node.kind == .number else { return mismatch(node, "Expected a number.", key) }
        case "integer":
            guard node.kind == .number, let number = node.scalarValue?.doubleValue, number.rounded() == number else {
                return mismatch(node, "Expected a whole number.", key)
            }
        case "array":
            guard node.kind == .array else { return mismatch(node, "Expected an array.", key) }
            if let items = schema["items"] {
                for element in node.elements where element.kind != .invalid {
                    check(element, schema: items, key: key)
                }
            }
        case "object":
            guard node.kind == .object else { return mismatch(node, "Expected an object.", key) }
        default:
            break
        }

        if let allowed = schema["enum"]?.arrayValue, let value = node.scalarValue, !allowed.contains(value) {
            let names = allowed.compactMap(\.stringValue)
            add(node.range, .error, .valueNotAllowed, "Value is not accepted. Valid values: \(Self.list(names)).", key: key)
        }
        if let number = node.scalarValue?.doubleValue,
           let minimum = schema["minimum"]?.doubleValue,
           let maximum = schema["maximum"]?.doubleValue,
           !(minimum...maximum).contains(number)
        {
            add(node.range, .warning, .outOfRange,
                "Value must be between \(Self.number(minimum)) and \(Self.number(maximum)).", key: key)
        }
    }

    private mutating func mismatch(_ node: JSONCNode, _ message: String, _ key: String) {
        add(node.range, .error, .typeMismatch, message, key: key)
    }

    private static func list(_ values: [String]) -> String {
        values.map { "“\($0)”" }.joined(separator: ", ")
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }

    // MARK: Ranges

    private mutating func add(
        _ range: NSRange,
        _ severity: SettingsDiagnostic.Severity,
        _ kind: SettingsDiagnostic.Kind,
        _ message: String,
        key: String? = nil,
        suggestedKey: String? = nil
    ) {
        diagnostics.append(SettingsDiagnostic(
            range: visible(range), severity: severity, kind: kind, message: message, key: key, suggestedKey: suggestedKey
        ))
    }

    /// Widens an empty range to the character or token before it (or the
    /// one at it), so there's something to underline.
    private func visible(_ range: NSRange) -> NSRange {
        guard range.length == 0, document.length > 0 else { return range }
        if let previous = document.significantToken(before: range.location) {
            return previous.range
        }
        let location = min(range.location, document.length - 1)
        return NSRange(location: location, length: 1)
    }
}
