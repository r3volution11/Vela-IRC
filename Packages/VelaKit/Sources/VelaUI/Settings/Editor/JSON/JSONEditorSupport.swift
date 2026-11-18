// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaStore
import VelaTheme

// The JSON view's text logic, apart from its views: revealing keys,
// copying defaults in, diagnostics, hover documentation and typing.

// MARK: - Reveal and copy

/// Finding a setting in settings.json, adding it when it's missing. Used
/// by "Edit in settings.json" (`revealKeyInJSON`) and the defaults pane's ✎.
nonisolated enum JSONReveal {
    struct Plan: Equatable, Sendable {
        /// Edits that add the setting (empty when it's already there).
        var edits: [JSONCEdit]
        /// What to select afterwards, in the edited text: the value (for
        /// strings, the text inside the quotes, ready to type over).
        var selection: NSRange
        /// True when the setting was added.
        var added: Bool { !edits.isEmpty }
    }

    /// Selects `key`'s value (the last one, which counts), or adds
    /// `"key": defaultValue` at the end of the file and selects that.
    /// Nil when the key is missing and there's no default or the text is
    /// too broken to add to.
    static func plan(key: String, defaultValue: JSONValue?, in text: String) -> Plan? {
        let document = JSONCDocument(text)
        if let property = document.root?.lastProperty(named: key) {
            return Plan(edits: [], selection: selection(for: property))
        }
        guard let defaultValue,
              let edits = try? JSONCEditing.edits(setting: defaultValue, at: [key], in: text),
              !edits.isEmpty
        else { return nil }
        let edited = JSONCDocument(JSONCEdit.apply(edits, to: text))
        guard let property = edited.root?.lastProperty(named: key) else { return nil }
        return Plan(edits: edits, selection: selection(for: property))
    }

    /// The value to select for `property`: inside a string's quotes, the
    /// whole of any other value, or the spot after the colon when the value
    /// is missing.
    static func selection(for property: JSONCProperty) -> NSRange {
        guard let value = property.value else { return property.valueRange }
        if value.kind == .string, value.range.length >= 2 {
            return NSRange(location: value.range.location + 1, length: value.range.length - 2)
        }
        return value.range
    }
}

// MARK: - Diagnostics

/// Theme checks for `appearance.colorCustomizations`, plugged into
/// ``SettingsValidator`` as an extra check.
nonisolated enum JSONColorChecks {
    static let settingKey = "appearance.colorCustomizations"

    /// For ``SettingsValidator/diagnostics(for:extraChecks:)``: unknown
    /// tokens and bad colors, from ``ThemeOverrides/problems(in:)``.
    static var extraChecks: [String: (JSONValue) -> [String]] {
        [settingKey: { value in ThemeOverrides.problems(in: value.objectValue ?? [:]) }]
    }

    /// The validator puts extra-check warnings on the whole value; this
    /// narrows each one to the member its message names (`“[Nord].accent”
    /// is not a hex color.`): the key for unknown tokens and misplaced
    /// scopes, the value for bad colors.
    static func refine(_ diagnostics: [SettingsDiagnostic], in document: JSONCDocument) -> [SettingsDiagnostic] {
        guard diagnostics.contains(where: { $0.kind == .extraCheck && $0.key == settingKey }),
              let object = document.root?.lastProperty(named: settingKey)?.value,
              object.kind == .object
        else { return diagnostics }
        return diagnostics.map { diagnostic in
            guard diagnostic.kind == .extraCheck, diagnostic.key == settingKey,
                  let path = quotedPath(in: diagnostic.message),
                  let range = range(of: path, in: object, keyProblem: isKeyProblem(diagnostic.message))
            else { return diagnostic }
            return SettingsDiagnostic(
                range: range, severity: diagnostic.severity, kind: diagnostic.kind,
                message: diagnostic.message, key: diagnostic.key, suggestedKey: diagnostic.suggestedKey
            )
        }
    }

    private static func isKeyProblem(_ message: String) -> Bool {
        message.contains("is not a theme color token") || message.contains("theme scopes must be")
            || message.contains("IRC color indexes")
    }

    /// The text between the first “ and ”.
    static func quotedPath(in message: String) -> String? {
        guard let open = message.firstIndex(of: "“"),
              let close = message[message.index(after: open)...].firstIndex(of: "”")
        else { return nil }
        return String(message[message.index(after: open)..<close])
    }

    /// The range a problem at `path` should underline. Paths join keys
    /// with dots, but token names contain dots too, so scopes (`[…]`),
    /// array indexes (`[3]`) and `ircColors.N` are peeled off explicitly.
    static func range(of path: String, in object: JSONCNode, keyProblem: Bool) -> NSRange? {
        var path = Substring(path)
        var index: Int?
        if path.hasSuffix("]"), let open = path.lastIndex(of: "["), open != path.startIndex,
           let number = Int(path[path.index(after: open)..<path.index(before: path.endIndex)])
        {
            index = number
            path = path[..<open]
        }
        var container = object
        if path.hasPrefix("["), let close = path.range(of: "].") {
            let scope = String(path[..<path.index(after: close.lowerBound)])
            if let value = container.lastProperty(named: scope)?.value, value.kind == .object {
                container = value
                path = path[close.upperBound...]
            }
        }
        var property = container.lastProperty(named: String(path))
        if property == nil, path.hasPrefix("ircColors."),
           let colors = container.lastProperty(named: "ircColors")?.value, colors.kind == .object
        {
            property = colors.lastProperty(named: String(path.dropFirst("ircColors.".count)))
        }
        guard let property else { return nil }
        if keyProblem { return property.keyRange }
        guard let value = property.value else { return property.keyRange }
        if let index, value.kind == .array, value.elements.indices.contains(index) {
            return value.elements[index].range
        }
        return value.range
    }

    /// Diagnostics moved along with an edit, so squiggles stay under their
    /// text until the next validation. Ones the edit touches stretch over
    /// it; ones it deleted entirely go.
    static func shift(_ diagnostics: [SettingsDiagnostic], editedRange: NSRange, delta: Int) -> [SettingsDiagnostic] {
        let editStart = editedRange.location
        let editEnd = editedRange.location + editedRange.length
        let oldEditEnd = editEnd - delta
        return diagnostics.compactMap { diagnostic in
            let start = diagnostic.range.location
            let end = start + diagnostic.range.length
            let newStart: Int, newEnd: Int
            if end <= editStart {
                return diagnostic
            } else if start >= oldEditEnd {
                newStart = start + delta
                newEnd = end + delta
            } else {
                newStart = min(start, editStart)
                newEnd = end > oldEditEnd ? end + delta : editEnd
            }
            guard newEnd > newStart else { return nil }
            return SettingsDiagnostic(
                range: NSRange(location: newStart, length: newEnd - newStart),
                severity: diagnostic.severity, kind: diagnostic.kind, message: diagnostic.message,
                key: diagnostic.key, suggestedKey: diagnostic.suggestedKey
            )
        }
    }

    /// "2 problems · 1 warning"-style summary counts.
    static func counts(_ diagnostics: [SettingsDiagnostic]) -> (errors: Int, warnings: Int, infos: Int) {
        var counts = (errors: 0, warnings: 0, infos: 0)
        for diagnostic in diagnostics {
            switch diagnostic.severity {
            case .error: counts.errors += 1
            case .warning: counts.warnings += 1
            case .info: counts.infos += 1
            }
        }
        return counts
    }
}

// MARK: - Hover documentation

/// What the hover card shows for a key: its title, summary, default, type
/// or allowed values, and whether it's modified.
nonisolated struct JSONHoverDocs: Equatable, Sendable {
    var title: String
    var key: String
    var summary: String?
    /// Label/value rows: "Default", "Type" or "Values".
    var facts: [Fact]
    var isModified: Bool

    struct Fact: Equatable, Sendable {
        var label: String
        var value: String
    }

    /// Docs for a setting.
    init(descriptor: SettingDescriptor, isModified: Bool) {
        title = descriptor.title
        key = descriptor.key
        summary = descriptor.summary.isEmpty ? nil : descriptor.summary
        self.isModified = isModified
        var facts = [Fact(label: "Default", value: JSONHoverDocs.display(descriptor.defaultValue))]
        if descriptor.followsSystem {
            facts.append(Fact(label: "Values", value: "true, false or \"system\" (same as macOS)"))
        } else if let values = descriptor.enumValues, !values.isEmpty {
            facts.append(Fact(label: "Values", value: values.map { "\"\($0)\"" }.joined(separator: ", ")))
        } else if let values = descriptor.itemEnumValues, !values.isEmpty {
            facts.append(Fact(label: "Values", value: "A list of any of " + values.map { "\"\($0)\"" }.joined(separator: ", ")))
        } else if let allowed = descriptor.objectValueEnum {
            facts.append(Fact(label: "Type", value: "Object of site → " + allowed.map { "\"\($0)\"" }.joined(separator: ", ")))
        } else {
            facts.append(Fact(label: "Type", value: JSONHoverDocs.typeDescription(descriptor)))
        }
        self.facts = facts
    }

    /// Docs for a theme color token inside `appearance.colorCustomizations`.
    init?(themeToken key: String) {
        guard let token = ThemeRegistry.token(key) else { return nil }
        title = key
        self.key = key
        summary = token.description
        isModified = false
        let group = ThemeRegistry.groups.first { $0.id == token.group }?.title
        facts = [Fact(label: "Type", value: "Theme color" + (group.map { " · \($0)" } ?? ""))]
    }

    /// `13`, `"grouped"`, `[]`, `{}`.
    static func display(_ value: JSONValue) -> String {
        JSONCEditing.compact(value)
    }

    /// "Number from 9 to 28", "Whole number", "Text", "List of text"…
    static func typeDescription(_ descriptor: SettingDescriptor) -> String {
        typeDescription(schema: descriptor.schema, range: descriptor.numberRange)
    }

    static func typeDescription(schema: JSONValue, range: ClosedRange<Double>? = nil) -> String {
        guard let object = schema.objectValue else { return "Any value" }
        if let branches = object["oneOf"]?.arrayValue ?? object["anyOf"]?.arrayValue {
            let names = branches.map { typeDescription(schema: $0) }
            return names.joined(separator: " or ")
        }
        let rangeText = range.map { " from \(number($0.lowerBound)) to \(number($0.upperBound))" } ?? ""
        switch object["type"]?.stringValue {
        case "boolean": return "true or false"
        case "integer": return "Whole number" + rangeText
        case "number": return "Number" + rangeText
        case "string": return "Text"
        case "array":
            if let items = object["items"], items.objectValue?["type"]?.stringValue == "string" { return "List of text" }
            return "List"
        case "object": return "Object"
        default: return "Any value"
        }
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
}

// MARK: - Typing

/// Editing behavior of the JSON view: indentation on Return, Tab and
/// ⇧Tab, and paired quotes.
nonisolated enum JSONTyping {
    /// The text Return inserts at `selection` and where the caret goes in
    /// it: a line break plus the line's indentation, one level deeper after
    /// `{` or `[`. When `}` or `]` follows the caret, it moves to its own
    /// line below (`{|}` → `{\n    |\n}`).
    static func newline(in text: NSString, selection: NSRange, indentUnit: String, lineEnding: String) -> (text: String, caret: Int) {
        let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        var indentEnd = lineStart
        while indentEnd < selection.location, isSpace(text.character(at: indentEnd)) { indentEnd += 1 }
        let indent = text.substring(with: NSRange(location: lineStart, length: indentEnd - lineStart))

        let before = previousNonSpace(in: text, before: selection.location, notBefore: lineStart)
        let afterOffset = selection.location + selection.length
        let after = nextNonSpace(in: text, from: afterOffset)
        let opens = before == 0x7B || before == 0x5B // { [
        guard opens else {
            let inserted = lineEnding + indent
            return (inserted, inserted.utf16.count)
        }
        let inner = lineEnding + indent + indentUnit
        let closes = (before == 0x7B && after == 0x7D) || (before == 0x5B && after == 0x5D)
        if closes {
            return (inner + lineEnding + indent, inner.utf16.count)
        }
        return (inner, inner.utf16.count)
    }

    enum QuoteAction: Equatable, Sendable {
        /// Insert `""` and put the caret between.
        case insertPair
        /// Step over the closing quote that's already there.
        case skipClosing
        /// Insert a single `"`.
        case insertSingle
    }

    /// What typing `"` at `caret` (with nothing selected) does.
    static func quoteAction(in text: NSString, at caret: Int) -> QuoteAction {
        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
        // Inside a string on this line? Count unescaped quotes before the caret.
        var quotes = 0
        var index = lineRange.location
        var escaped = false
        while index < caret {
            let c = text.character(at: index)
            if escaped {
                escaped = false
            } else if c == 0x5C { // backslash
                escaped = true
            } else if c == 0x22 {
                quotes += 1
            } else if c == 0x2F, quotes % 2 == 0, index + 1 < caret, text.character(at: index + 1) == 0x2F {
                return .insertSingle // in a // comment
            }
            index += 1
        }
        let insideString = quotes % 2 == 1
        let next: unichar? = caret < text.length ? text.character(at: caret) : nil
        if insideString {
            return next == 0x22 && !escaped ? .skipClosing : .insertSingle
        }
        // Pair only where a string can start and nothing word-like follows.
        guard let next else { return .insertPair }
        switch next {
        case 0x20, 0x09, 0x0A, 0x0D, 0x7D, 0x5D, 0x2C, 0x3A: return .insertPair // space tab LF CR } ] , :
        default: return .insertSingle
        }
    }

    /// A quick, line-local check before the full completion context is
    /// worked out: `"`, `:` and `[` might open the list anywhere outside a
    /// comment; other word characters only inside a string, or as a bare
    /// word right after a colon, comma or `[` (`t` → `true`).
    static func mightOpenCompletion(afterTyping typed: String, in text: NSString, at caret: Int) -> Bool {
        guard typed.utf16.count == 1, let unit = typed.utf16.first, caret > 0 else { return false }
        let lineStart = text.lineRange(for: NSRange(location: min(caret, text.length), length: 0)).location
        var quotes = 0
        var escaped = false
        var index = lineStart
        while index < caret - 1 {
            let c = text.character(at: index)
            if escaped {
                escaped = false
            } else if c == 0x5C {
                escaped = true
            } else if c == 0x22 {
                quotes += 1
            } else if c == 0x2F, quotes % 2 == 0, index + 1 < caret, [0x2F, 0x2A].contains(text.character(at: index + 1)) {
                return false // in a comment
            }
            index += 1
        }
        if unit == 0x22 || unit == 0x3A || unit == 0x5B { return true } // " : [
        if quotes % 2 == 1 { return true }
        // A bare word: what comes before it?
        var start = caret - 1
        while start > lineStart, JSONTyping.isWordUnit(text.character(at: start - 1)) { start -= 1 }
        var before = start - 1
        while before >= 0, [0x20, 0x09, 0x0A, 0x0D].contains(text.character(at: before)) { before -= 1 }
        guard before >= 0 else { return false }
        return [0x3A, 0x2C, 0x5B].contains(text.character(at: before)) // : , [
    }

    private static func isWordUnit(_ c: unichar) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2E || c == 0x2D || c == 0x5F
    }

    /// For ⇧Tab: the ranges to delete to outdent each line touched by
    /// `selection` by one level (`indentUnit`, or as much of it as there is).
    static func outdentRanges(in text: NSString, selection: NSRange, indentUnit: String) -> [NSRange] {
        let lines = text.lineRange(for: selection)
        var ranges: [NSRange] = []
        var lineStart = lines.location
        let unitLength = max(1, indentUnit == "\t" ? 1 : indentUnit.utf16.count)
        repeat {
            var count = 0
            if lineStart < text.length, text.character(at: lineStart) == 0x09 {
                count = 1
            } else {
                while count < unitLength, lineStart + count < text.length, text.character(at: lineStart + count) == 0x20 {
                    count += 1
                }
            }
            if count > 0 { ranges.append(NSRange(location: lineStart, length: count)) }
            let next = NSMaxRange(text.lineRange(for: NSRange(location: lineStart, length: 0)))
            guard next > lineStart else { break }
            lineStart = next
        } while lineStart < NSMaxRange(lines)
        return ranges
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }

    private static func previousNonSpace(in text: NSString, before offset: Int, notBefore start: Int) -> unichar? {
        var index = offset - 1
        while index >= start {
            let c = text.character(at: index)
            if !isSpace(c) { return c }
            index -= 1
        }
        return nil
    }

    private static func nextNonSpace(in text: NSString, from offset: Int) -> unichar? {
        var index = offset
        while index < text.length {
            let c = text.character(at: index)
            if c == 0x0A || c == 0x0D { return nil }
            if !isSpace(c) { return c }
            index += 1
        }
        return nil
    }
}

// MARK: - Selection

nonisolated enum JSONSelection {
    /// `selection` after `edit` (a reload from disk, say): before the edit
    /// it stays, after it it moves with the text, and inside it it's pulled
    /// to the edit's bounds.
    static func adjust(_ selection: NSRange, for edit: JSONCEdit) -> NSRange {
        let editStart = edit.range.location
        let oldEditEnd = edit.range.location + edit.range.length
        let newLength = edit.replacement.utf16.count
        let newEditEnd = editStart + newLength
        let delta = newLength - edit.range.length
        func map(_ offset: Int, isEnd: Bool) -> Int {
            if offset <= editStart { return offset }
            if offset >= oldEditEnd { return offset + delta }
            return isEnd ? newEditEnd : min(offset, newEditEnd)
        }
        let start = map(selection.location, isEnd: false)
        let end = max(start, map(selection.location + selection.length, isEnd: true))
        return NSRange(location: start, length: selection.length == 0 ? 0 : end - start)
    }
}
