// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A text replacement: put ``replacement`` where ``range`` (UTF-16) was.
public struct JSONCEdit: Sendable, Hashable {
    public var range: NSRange
    public var replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    /// An insertion at `offset`.
    public static func insert(_ text: String, at offset: Int) -> JSONCEdit {
        JSONCEdit(range: NSRange(location: offset, length: 0), replacement: text)
    }

    /// A deletion of `range`.
    public static func delete(_ range: NSRange) -> JSONCEdit {
        JSONCEdit(range: range, replacement: "")
    }

    /// Applies `edits` to `text`. The edits' ranges refer to the original
    /// `text` and must not overlap; their order doesn't matter, except that
    /// insertions at the same offset are applied in the order given.
    public static func apply(_ edits: [JSONCEdit], to text: String) -> String {
        guard !edits.isEmpty else { return text }
        let units = Array(text.utf16)
        let sorted = edits.enumerated()
            .sorted { ($0.element.range.location, $0.offset) < ($1.element.range.location, $1.offset) }
            .map(\.element)
        var out: [UInt16] = []
        out.reserveCapacity(units.count + sorted.reduce(0) { $0 + $1.replacement.utf16.count })
        var cursor = 0
        for edit in sorted {
            let start = min(max(edit.range.location, cursor), units.count)
            let end = min(max(edit.range.location + edit.range.length, start), units.count)
            out.append(contentsOf: units[cursor..<start])
            out.append(contentsOf: edit.replacement.utf16)
            cursor = end
        }
        out.append(contentsOf: units[cursor...])
        return String(decoding: out, as: UTF16.self)
    }

    /// The single smallest edit that turns `old` into `new` (common prefix
    /// and suffix left alone), or nil when they're equal.
    public static func difference(from old: String, to new: String) -> JSONCEdit? {
        let a = Array(old.utf16)
        let b = Array(new.utf16)
        guard a != b else { return nil }
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
              a[a.count - 1 - suffix] == b[b.count - 1 - suffix]
        {
            suffix += 1
        }
        // Don't split a surrogate pair.
        if prefix > 0, UTF16.isLeadSurrogate(a[prefix - 1]) { prefix -= 1 }
        if suffix > 0, UTF16.isTrailSurrogate(a[a.count - suffix]) { suffix -= 1 }
        return JSONCEdit(
            range: NSRange(location: prefix, length: a.count - suffix - prefix),
            replacement: String(decoding: b[prefix..<(b.count - suffix)], as: UTF16.self)
        )
    }
}

/// How new JSONC text is laid out, normally detected from the file being
/// edited so additions look like the rest of it.
public struct JSONCFormat: Sendable, Hashable {
    /// One level of indentation: spaces or a tab.
    public var indent: String
    /// `"\n"` or `"\r\n"`.
    public var lineEnding: String
    /// Whether multi-line objects and arrays end with a comma after their
    /// last member.
    public var trailingCommas: Bool
    /// `"key" : value` rather than `"key": value`.
    public var spaceBeforeColon: Bool

    public init(indent: String = "    ", lineEnding: String = "\n", trailingCommas: Bool = false, spaceBeforeColon: Bool = false) {
        self.indent = indent
        self.lineEnding = lineEnding
        self.trailingCommas = trailingCommas
        self.spaceBeforeColon = spaceBeforeColon
    }

    /// Four spaces, `\n`, no trailing commas: VS Code's defaults.
    public static let standard = JSONCFormat()

    /// The format `document` uses; anything it doesn't show comes from
    /// `fallback`.
    public init(detectingIn document: JSONCDocument, fallback: JSONCFormat = .standard) {
        self = fallback
        if let lineBreak = document.tokens.first(where: { $0.kind == .lineBreak }) {
            lineEnding = document.text(in: lineBreak.range)
        }
        guard let root = document.root else { return }

        var indents: [String: Int] = [:]
        var trailing = 0, notTrailing = 0
        var spaced = 0, tight = 0
        var samples = 0

        func visit(_ node: JSONCNode) {
            guard node.isContainer, samples < 500 else { return }
            let parentIndent = document.indentation(ofLineAt: node.range.location)
            var childStarts: [Int] = []
            var lastHasComma = false
            if node.kind == .object {
                for property in node.properties {
                    childStarts.append(property.keyRange.location)
                    if let colon = property.colonRange {
                        if colon.location > property.keyRange.endOffset { spaced += 1 } else { tight += 1 }
                    }
                }
                lastHasComma = node.properties.last?.commaRange != nil
            } else {
                childStarts = node.elements.map(\.range.location)
                lastHasComma = node.elementCommaRanges.last.map { $0 != nil } ?? false
            }
            for start in childStarts where document.isFirstOnLine(start) {
                let childIndent = document.indentation(ofLineAt: start)
                if childIndent.count > parentIndent.count, childIndent.hasPrefix(parentIndent) {
                    indents[String(childIndent.dropFirst(parentIndent.count)), default: 0] += 1
                    samples += 1
                }
            }
            if let close = node.closeRange, !childStarts.isEmpty, document.isFirstOnLine(close.location) {
                if lastHasComma { trailing += 1 } else { notTrailing += 1 }
            }
            for property in node.properties { if let value = property.value { visit(value) } }
            for element in node.elements { visit(element) }
        }
        visit(root)

        if let best = indents.max(by: { ($0.value, -$0.key.count) < ($1.value, -$1.key.count) }) {
            indent = best.key.contains("\t") ? "\t" : best.key
        }
        if trailing + notTrailing > 0 { trailingCommas = trailing > notTrailing }
        if spaced + tight > 0 { spaceBeforeColon = spaced > tight }
    }
}

public enum JSONCEditingError: Error, Sendable, Hashable, LocalizedError {
    /// The text's top-level value isn't an object (or can't be parsed).
    case rootIsNotAnObject
    /// An object on the path is missing its closing brace.
    case unclosedObject(path: [String])
    /// A property on the path has no value (`"key":` with nothing after).
    case missingValue(path: [String])

    public var errorDescription: String? {
        switch self {
        case .rootIsNotAnObject: "The top level must be an object."
        case .unclosedObject(let path): "The object at “\(path.joined(separator: " → "))” isn't closed."
        case .missingValue(let path): "“\(path.joined(separator: " → "))” has no value."
        }
    }
}

/// Minimal, comment-preserving edits to JSONC text, like the `modify` and
/// `applyEdits` functions of Microsoft's jsonc-parser.
///
/// - Values are addressed by a path of object keys, e.g.
///   `["appearance.colorCustomizations", "[Palenight]", "accent"]`.
/// - Comments, indentation (tabs or spaces), line endings and the
///   trailing-comma style are kept. Only the touched value changes.
/// - Replacing a value replaces just its text; objects and arrays are
///   pretty-printed at the property's indentation.
/// - Removing a property takes its comma and any comment after it on the
///   same line with it; when it had the line to itself, the whole line goes.
///   Comments on the lines above it stay.
/// - A new property is appended after the last one in its object, with
///   the file's indentation and the right commas. Objects written on one
///   line stay on one line (`{"a": 1, "b": 2}`); empty objects are opened up
///   (`{\n    "b": 2\n}`). Missing objects along the path are created.
/// - Text without a top-level value gets a new pretty-printed object.
///
/// ```swift
/// let edits = try JSONCEditing.edits(setting: "#ff8800",
///                                    at: ["appearance.colorCustomizations", "[Palenight]", "accent"],
///                                    in: text)
/// let newText = JSONCEdit.apply(edits, to: text)
/// // or: let newText = try JSONCEditing.setting("#ff8800", at: path, in: text)
/// ```
public enum JSONCEditing {
    /// Edits that set the value at `path` to `value`, or remove the
    /// property when `value` is nil. Ranges refer to `text`; apply them with
    /// ``JSONCEdit/apply(_:to:)``. Empty when nothing needs to change
    /// (removing something that isn't there).
    ///
    /// - Parameter format: The layout for new text; detected from `text`
    ///   when nil.
    /// - Throws: ``JSONCEditingError`` when the text around the path is too
    ///   broken to edit safely. Errors elsewhere in the text don't matter.
    public static func edits(setting value: JSONValue?, at path: [String], in text: String, format: JSONCFormat? = nil) throws -> [JSONCEdit] {
        let document = JSONCDocument(text)
        let editor = JSONCEditor(document: document, format: format ?? JSONCFormat(detectingIn: document))
        guard let value else { return editor.removeAll(at: path) }
        return try editor.set(value, at: path)
    }

    /// `text` with the value at `path` set to `value` (or removed, for nil).
    public static func setting(_ value: JSONValue?, at path: [String], in text: String, format: JSONCFormat? = nil) throws -> String {
        JSONCEdit.apply(try edits(setting: value, at: path, in: text, format: format), to: text)
    }

    /// `value` as pretty-printed JSON: keys sorted, nested lines indented
    /// one ``JSONCFormat/indent`` deeper than `baseIndent` (the indentation
    /// of the line the value starts on).
    public static func format(_ value: JSONValue, baseIndent: String = "", format: JSONCFormat = .standard) -> String {
        JSONCWriter(format: format).pretty(value, baseIndent: baseIndent)
    }

    /// `value` as one line of JSON: `{"a": 1, "b": [true, null]}`.
    public static func compact(_ value: JSONValue, format: JSONCFormat = .standard) -> String {
        JSONCWriter(format: format).compact(value)
    }

    /// `string` as a JSON string literal, quotes included.
    public static func quote(_ string: String) -> String {
        JSONCWriter.quote(string)
    }
}

// MARK: - Writing values

struct JSONCWriter {
    let format: JSONCFormat

    var colon: String { format.spaceBeforeColon ? " : " : ": " }

    func pretty(_ value: JSONValue, baseIndent: String) -> String {
        let inner = baseIndent + format.indent
        let eol = format.lineEnding
        switch value {
        case .object(let object) where !object.isEmpty:
            let keys = object.keys.sorted()
            var out = "{" + eol
            for (index, key) in keys.enumerated() {
                out += inner + Self.quote(key) + colon + pretty(object[key]!, baseIndent: inner)
                if index < keys.count - 1 || format.trailingCommas { out += "," }
                out += eol
            }
            return out + baseIndent + "}"
        case .array(let array) where !array.isEmpty:
            var out = "[" + eol
            for (index, element) in array.enumerated() {
                out += inner + pretty(element, baseIndent: inner)
                if index < array.count - 1 || format.trailingCommas { out += "," }
                out += eol
            }
            return out + baseIndent + "]"
        default:
            return compact(value)
        }
    }

    func compact(_ value: JSONValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let bool): bool ? "true" : "false"
        case .number(let number): Self.number(number)
        case .string(let string): Self.quote(string)
        case .array(let array): "[" + array.map(compact).joined(separator: ", ") + "]"
        case .object(let object):
            "{" + object.keys.sorted().map { Self.quote($0) + colon + compact(object[$0]!) }.joined(separator: ", ") + "}"
        }
    }

    static func number(_ number: Double) -> String {
        guard number.isFinite else { return "null" }
        if number.rounded() == number, abs(number) < 1e15 { return String(Int64(number)) }
        return "\(number)"
    }

    static func quote(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

// MARK: - Editing

struct JSONCEditor {
    let document: JSONCDocument
    let format: JSONCFormat

    private var writer: JSONCWriter { JSONCWriter(format: format) }
    private var eol: String { format.lineEnding }
    private var tokens: [JSONCToken] { document.tokens }

    // MARK: Set

    func set(_ value: JSONValue, at path: [String]) throws -> [JSONCEdit] {
        guard let root = document.root else {
            guard document.errors.isEmpty else { throw JSONCEditingError.rootIsNotAnObject }
            return freshDocument(Self.wrap(value, in: path))
        }
        if path.isEmpty {
            let indent = document.indentation(ofLineAt: root.range.location)
            return [JSONCEdit(range: root.range, replacement: writer.pretty(value, baseIndent: indent))]
        }
        guard root.kind == .object else { throw JSONCEditingError.rootIsNotAnObject }

        var object = root
        for (index, key) in path.enumerated() {
            let rest = Array(path[(index + 1)...])
            guard let property = object.lastProperty(named: key) else {
                guard object.isClosed else { throw JSONCEditingError.unclosedObject(path: Array(path[..<index])) }
                return insert(key: key, value: Self.wrap(value, in: rest), into: object)
            }
            guard let existing = property.value else {
                throw JSONCEditingError.missingValue(path: Array(path[...index]))
            }
            if rest.isEmpty || existing.kind != .object {
                let newValue = Self.wrap(value, in: rest)
                // Already that value (however it's written): leave it, and
                // any comments inside it, alone.
                guard existing.jsonValue != newValue else { return [] }
                return [JSONCEdit(range: existing.range, replacement: formatted(newValue, forPropertyAt: property, in: object))]
            }
            guard existing.isClosed else { throw JSONCEditingError.unclosedObject(path: Array(path[...index])) }
            object = existing
        }
        return []
    }

    /// `value` nested in objects for each key of `path`: `{"a": {"b": value}}`.
    static func wrap(_ value: JSONValue, in path: [String]) -> JSONValue {
        path.reversed().reduce(value) { .object([$1: $0]) }
    }

    private func isOneLine(_ object: JSONCNode) -> Bool {
        guard let close = object.closeRange else { return false }
        return document.lineIndex(at: object.range.location) == document.lineIndex(at: close.location)
    }

    private func formatted(_ value: JSONValue, forPropertyAt property: JSONCProperty, in object: JSONCNode) -> String {
        if isOneLine(object) { return writer.compact(value) }
        return writer.pretty(value, baseIndent: document.indentation(ofLineAt: property.keyRange.location))
    }

    private func entry(_ key: String, _ value: JSONValue, indent: String?) -> String {
        let text = indent.map { writer.pretty(value, baseIndent: $0) } ?? writer.compact(value)
        return JSONCWriter.quote(key) + writer.colon + text
    }

    private func freshDocument(_ value: JSONValue) -> [JSONCEdit] {
        let body = writer.pretty(value, baseIndent: "") + eol
        if tokens.allSatisfy({ $0.kind == .whitespace || $0.kind == .lineBreak }) {
            return [JSONCEdit(range: NSRange(location: 0, length: document.length), replacement: body)]
        }
        // Only comments: add the object after them.
        let endsWithLineBreak = tokens.last?.kind == .lineBreak
        return [.insert((endsWithLineBreak ? "" : eol) + body, at: document.length)]
    }

    private func insert(key: String, value: JSONValue, into object: JSONCNode) -> [JSONCEdit] {
        let open = object.range.location
        let close = object.closeRange!.location
        let parentIndent = document.indentation(ofLineAt: open)

        guard let last = object.properties.last else {
            var childIndent = parentIndent + format.indent
            let interior = NSRange(location: open + 1, length: close - open - 1)
            let interiorTokens = tokens.filter { $0.range.location >= interior.location && $0.end <= close }
            if interiorTokens.allSatisfy({ $0.kind == .whitespace || $0.kind == .lineBreak }) {
                let line = entry(key, value, indent: childIndent) + (format.trailingCommas ? "," : "")
                return [JSONCEdit(range: interior, replacement: eol + childIndent + line + eol + parentIndent)]
            }
            // Comments inside: add the property after them, before the
            // brace, lined up with them.
            if let comment = interiorTokens.last(where: { $0.isComment && document.isFirstOnLine($0.range.location) }) {
                childIndent = document.indentation(ofLineAt: comment.range.location)
            }
            let line = entry(key, value, indent: childIndent) + (format.trailingCommas ? "," : "")
            if document.isFirstOnLine(close) {
                return [.insert(childIndent + line + eol, at: document.lineStart(at: close))]
            }
            let start = endOfContent(before: close, notBefore: open + 1)
            return [JSONCEdit(range: NSRange(location: start, length: close - start), replacement: eol + childIndent + line + eol + parentIndent)]
        }

        let lastEnd = last.range.endOffset
        if isOneLine(object) {
            let text = entry(key, value, indent: nil)
            if let comma = last.commaRange {
                return [.insert(" " + text + ",", at: comma.endOffset)]
            }
            return [.insert(", " + text, at: lastEnd)]
        }

        let childIndent = document.isFirstOnLine(last.keyRange.location)
            ? document.indentation(ofLineAt: last.keyRange.location)
            : parentIndent + format.indent
        let line = entry(key, value, indent: childIndent) + (last.commaRange != nil ? "," : "")
        let afterLast = last.commaRange?.endOffset ?? lastEnd
        let commaText = last.commaRange == nil ? "," : ""

        // Add the new line after the rest of the last property's line
        // (its trailing comment, if any).
        var anchor = afterLast
        var index = document.tokenIndex(startingAt: afterLast)
        while let current = index {
            let token = tokens[current]
            guard token.kind == .whitespace || token.kind == .lineComment
                || (token.kind == .blockComment && !containsLineBreak(token))
            else { break }
            anchor = token.end
            index = current + 1 < tokens.count ? current + 1 : nil
        }
        let atLineEnd = index == nil || tokens[index!].kind == .lineBreak
        if atLineEnd {
            if anchor == lastEnd {
                return [.insert(commaText + eol + childIndent + line, at: lastEnd)]
            }
            var edits: [JSONCEdit] = []
            if !commaText.isEmpty { edits.append(.insert(commaText, at: lastEnd)) }
            edits.append(.insert(eol + childIndent + line, at: anchor))
            return edits
        }
        // Something else follows on that line (`"a": 1}`): break the line.
        let tail = tokens[index!].kind == .closeBrace && tokens[index!].range.location == close ? eol + parentIndent : ""
        return [.insert(commaText + eol + childIndent + line + tail, at: afterLast)]
    }

    private func containsLineBreak(_ token: JSONCToken) -> Bool {
        document.units[token.range.location..<token.end].contains { $0 == Unit.lf || $0 == Unit.cr }
    }

    /// The offset after the last non-space, non-tab character before `offset`.
    private func endOfContent(before offset: Int, notBefore floor: Int) -> Int {
        var index = offset
        while index > floor, document.units[index - 1] == Unit.space || document.units[index - 1] == Unit.tab {
            index -= 1
        }
        return index
    }

    // MARK: Remove

    /// Removes every property at `path` (duplicates included).
    func removeAll(at path: [String]) -> [JSONCEdit] {
        let first = remove(at: path)
        guard !first.isEmpty else { return [] }
        var text = JSONCEdit.apply(first, to: document.text)
        var rounds = 0
        while rounds < 100 {
            let next = JSONCEditor(document: JSONCDocument(text), format: format).remove(at: path)
            guard !next.isEmpty else { break }
            text = JSONCEdit.apply(next, to: text)
            rounds += 1
        }
        if rounds == 0 { return first }
        return JSONCEdit.difference(from: document.text, to: text).map { [$0] } ?? []
    }

    /// Removes the last property at `path`.
    func remove(at path: [String]) -> [JSONCEdit] {
        guard let key = path.last, let root = document.root, root.kind == .object,
              let object = root.node(at: Array(path.dropLast())), object.kind == .object,
              let index = object.properties.lastIndex(where: { $0.key == key })
        else { return [] }
        return removal(of: index, in: object)
    }

    private func removal(of index: Int, in object: JSONCNode) -> [JSONCEdit] {
        let properties = object.properties
        let property = properties[index]
        let start = property.keyRange.location
        let end = property.range.endOffset
        let afterProperty = property.commaRange?.endOffset ?? end

        // What follows on the same line: spaces and comments, then a line
        // break (or the end), or something else.
        var trailingEnd = afterProperty
        var lineEnd: Int?
        var nextStart: Int?
        var tokenIndex = document.tokenIndex(startingAt: afterProperty)
        if tokenIndex == nil { lineEnd = afterProperty }
        while let current = tokenIndex {
            let token = tokens[current]
            if token.kind == .whitespace || token.kind == .lineComment
                || (token.kind == .blockComment && !containsLineBreak(token))
            {
                trailingEnd = token.end
                tokenIndex = current + 1 < tokens.count ? current + 1 : nil
                if tokenIndex == nil { lineEnd = trailingEnd }
            } else if token.kind == .lineBreak {
                lineEnd = token.end
                break
            } else {
                nextStart = token.range.location
                break
            }
        }
        let firstOnLine = document.isFirstOnLine(start)
        let previous = index > 0 ? properties[index - 1] : nil

        if firstOnLine, let lineEnd {
            // The property has its lines to itself: remove them whole.
            var edits = [JSONCEdit.delete(NSRange(location: document.lineStart(at: start), length: lineEnd - document.lineStart(at: start)))]
            if property.commaRange == nil, let comma = previous?.commaRange {
                // It was last: the one before is last now, without a comma.
                edits.append(.delete(comma))
            }
            return edits
        }
        if property.commaRange == nil, let previous {
            // Last, sharing its line: remove from the end of the one before.
            let from = previous.range.endOffset
            let to = lineEnd != nil ? trailingEnd : end
            return [.delete(NSRange(location: from, length: to - from))]
        }
        if lineEnd != nil {
            // Last on its line, after something else: keep that.
            let from = endOfContent(before: start, notBefore: object.range.location + 1)
            return [.delete(NSRange(location: from, length: trailingEnd - from))]
        }
        // Something follows on the same line.
        let from = property.commaRange == nil ? endOfContent(before: start, notBefore: object.range.location + 1) : start
        let to = nextStart ?? afterProperty
        return [.delete(NSRange(location: from, length: to - from))]
    }
}
