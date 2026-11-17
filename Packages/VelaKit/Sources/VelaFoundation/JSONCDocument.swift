// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A parsed JSONC text with positions: the value tree, every token, and
/// syntax errors.
///
/// - All offsets and ranges are **UTF-16** (NSString/NSTextView units).
/// - Parsing never fails. Partial text (a half-typed key, a missing comma,
///   an unterminated string, a missing closing brace) still produces a
///   tree for everything that could be recognized, plus ``errors``.
/// - Comments (`//`, `/* */`) and trailing commas are allowed, as in VS
///   Code's settings files; neither is an error.
/// - Duplicate keys are all kept in ``JSONCNode/properties``; when the tree
///   is turned into a ``JSONValue`` the last one wins (as in VS Code).
/// - Fast enough to re-parse on every keystroke: a few thousand lines
///   take a few milliseconds.
///
/// ```swift
/// let document = JSONCDocument(text)
/// if let property = document.root?.lastProperty(named: "chat.fontSize") {
///     textView.setSelectedRange(property.keyRange)
/// }
/// for error in document.errors { print(document.lineAndColumn(at: error.range.location), error.message) }
/// ```
public struct JSONCDocument: Sendable {
    /// The text that was parsed.
    public let text: String
    /// Every token, in order, covering the whole text.
    public let tokens: [JSONCToken]
    /// The top-level value; nil when the text is empty or only comments.
    public let root: JSONCNode?
    /// Syntax errors, sorted by location. Empty for valid JSONC.
    public let errors: [JSONCParseError]
    /// UTF-16 offset where each line starts; the first is 0.
    public let lineStarts: [Int]

    /// The text's UTF-16 code units.
    let units: [UInt16]
    /// Indexes into ``tokens`` of strings that are property names.
    let keyTokenIndexes: Set<Int>

    public init(_ text: String) {
        self.text = text
        let units = Array(text.utf16)
        let (tokens, lineStarts) = JSONCScanner.scan(units)
        var parser = JSONCParser(units: units, tokens: tokens)
        let root = parser.parseDocument()
        self.units = units
        self.tokens = tokens
        self.lineStarts = lineStarts
        self.root = root
        self.errors = parser.errors.enumerated()
            .sorted { ($0.element.range.location, $0.offset) < ($1.element.range.location, $1.offset) }
            .map(\.element)
        self.keyTokenIndexes = parser.keyTokenIndexes
    }

    /// The text's length in UTF-16 code units.
    public var length: Int { units.count }

    /// True when there are no syntax errors.
    public var isValid: Bool { errors.isEmpty }

    /// The whole document as a value (nil when empty, or when the root
    /// value itself is broken). Valid parts of broken documents are kept.
    public var jsonValue: JSONValue? { root?.jsonValue }

    /// The text in `range` (UTF-16).
    public func text(in range: NSRange) -> String {
        let lower = max(0, min(range.location, units.count))
        let upper = max(lower, min(range.location + range.length, units.count))
        return String(decoding: units[lower..<upper], as: UTF16.self)
    }

    // MARK: Lines

    /// The 0-based line containing `offset`.
    public func lineIndex(at offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// 1-based line and column (in UTF-16 units) of `offset`, for messages.
    public func lineAndColumn(at offset: Int) -> (line: Int, column: Int) {
        let line = lineIndex(at: offset)
        return (line + 1, offset - lineStarts[line] + 1)
    }

    /// UTF-16 offset of the start of the line containing `offset`.
    public func lineStart(at offset: Int) -> Int {
        lineStarts[lineIndex(at: offset)]
    }

    /// The spaces and tabs at the start of the line containing `offset`.
    public func indentation(ofLineAt offset: Int) -> String {
        let start = lineStart(at: offset)
        var end = start
        while end < units.count, units[end] == Unit.space || units[end] == Unit.tab { end += 1 }
        return String(decoding: units[start..<end], as: UTF16.self)
    }

    /// True when only spaces and tabs precede `offset` on its line.
    public func isFirstOnLine(_ offset: Int) -> Bool {
        var index = offset - 1
        while index >= 0 {
            let unit = units[index]
            if unit == Unit.lf || unit == Unit.cr { return true }
            if unit != Unit.space && unit != Unit.tab && unit != Unit.bom { return false }
            index -= 1
        }
        return true
    }

    // MARK: Tokens

    /// Index of the token containing `offset` (the one starting there when
    /// `offset` falls between two tokens); nil at or past the end.
    public func tokenIndex(at offset: Int) -> Int? {
        guard offset >= 0, offset < units.count, !tokens.isEmpty else { return nil }
        var low = 0
        var high = tokens.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if tokens[mid].range.location <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Index of the token that starts at `offset`, if one does.
    public func tokenIndex(startingAt offset: Int) -> Int? {
        guard let index = tokenIndex(at: offset), tokens[index].range.location == offset else { return nil }
        return index
    }

    /// The first token at or after `offset` that isn't whitespace, a line
    /// break or a comment.
    public func significantToken(from offset: Int) -> JSONCToken? {
        guard var index = tokenIndex(at: offset) else { return nil }
        if tokens[index].range.location < offset { index += 1 }
        while index < tokens.count {
            if !tokens[index].isTrivia { return tokens[index] }
            index += 1
        }
        return nil
    }

    /// The last token ending at or before `offset` that isn't whitespace,
    /// a line break or a comment.
    public func significantToken(before offset: Int) -> JSONCToken? {
        guard offset > 0 else { return nil }
        var index = tokenIndex(at: offset - 1) ?? (tokens.count - 1)
        while index >= 0 {
            let token = tokens[index]
            if !token.isTrivia, token.end <= offset { return token }
            index -= 1
        }
        return nil
    }

    /// True when the string token at `index` is a property name.
    public func isPropertyKey(tokenAt index: Int) -> Bool {
        keyTokenIndexes.contains(index)
    }

    // MARK: Highlighting

    /// Syntax-highlighting runs for every non-whitespace token, in order.
    /// Property names are told apart from string values.
    public func highlights() -> [JSONCHighlight] {
        var runs: [JSONCHighlight] = []
        runs.reserveCapacity(tokens.count / 2)
        for (index, token) in tokens.enumerated() {
            let role: JSONCHighlight.Role
            switch token.kind {
            case .whitespace, .lineBreak: continue
            case .string: role = keyTokenIndexes.contains(index) ? .propertyKey : .string
            case .number: role = token.problem == nil ? .number : .invalid
            case .true, .false: role = .boolean
            case .null: role = .null
            case .lineComment, .blockComment: role = .comment
            case .openBrace, .closeBrace, .openBracket, .closeBracket, .colon, .comma: role = .punctuation
            case .invalid: role = .invalid
            }
            runs.append(JSONCHighlight(range: token.range, role: role))
        }
        return runs
    }
}

/// A syntax-highlighting run: a token's range and what it is.
public struct JSONCHighlight: Sendable, Hashable {
    public enum Role: Sendable, Hashable {
        /// A string that names a property.
        case propertyKey
        case string
        case number
        case boolean
        case null
        /// `{ } [ ] : ,`
        case punctuation
        case comment
        /// Bare words, malformed numbers and stray characters.
        case invalid
    }

    public let range: NSRange
    public let role: Role
}

// MARK: - Tree

/// A value in a ``JSONCDocument``, with its position.
public struct JSONCNode: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case object, array, string, number, boolean, null
        /// Something that should have been a value but isn't (`tru`,
        /// `classic` without quotes, `12px`).
        case invalid
    }

    public let kind: Kind
    /// UTF-16 range of the value. For objects and arrays it runs from the
    /// opening bracket through the closing one or, when that is missing,
    /// through the last token that was parsed inside.
    public let range: NSRange
    /// Objects and arrays: the closing bracket, nil when it's missing.
    public let closeRange: NSRange?
    /// Objects: the properties in source order, duplicates included.
    public let properties: [JSONCProperty]
    /// Arrays: the elements in source order.
    public let elements: [JSONCNode]
    /// Arrays: the comma after each element (parallel to ``elements``).
    public let elementCommaRanges: [NSRange?]
    /// Strings (decoded), numbers, booleans and null; nil otherwise.
    public let scalarValue: JSONValue?
    /// Where an unclosed object or array's content stops: the offset of
    /// the token that ended it, or the end of the text.
    let contentEnd: Int

    init(
        kind: Kind,
        range: NSRange,
        closeRange: NSRange? = nil,
        properties: [JSONCProperty] = [],
        elements: [JSONCNode] = [],
        elementCommaRanges: [NSRange?] = [],
        scalarValue: JSONValue? = nil,
        contentEnd: Int? = nil
    ) {
        self.kind = kind
        self.range = range
        self.closeRange = closeRange
        self.properties = properties
        self.elements = elements
        self.elementCommaRanges = elementCommaRanges
        self.scalarValue = scalarValue
        self.contentEnd = contentEnd ?? range.endOffset
    }

    /// True for objects and arrays.
    public var isContainer: Bool { kind == .object || kind == .array }

    /// Objects and arrays: whether the closing bracket is there.
    public var isClosed: Bool { closeRange != nil }

    /// The value, recursively. Nil for ``Kind/invalid``; invalid members of
    /// objects and arrays are left out. Duplicate keys: the last one wins.
    public var jsonValue: JSONValue? {
        switch kind {
        case .object:
            var object: [String: JSONValue] = [:]
            for property in properties {
                if let value = property.value?.jsonValue { object[property.key] = value }
            }
            return .object(object)
        case .array:
            return .array(elements.compactMap(\.jsonValue))
        case .string, .number, .boolean, .null:
            return scalarValue
        case .invalid:
            return nil
        }
    }

    /// The last property named `key` (the one whose value counts).
    public func lastProperty(named key: String) -> JSONCProperty? {
        properties.last { $0.key == key }
    }

    /// The node at `path` (object keys from here), or nil.
    public func node(at path: [String]) -> JSONCNode? {
        var node = self
        for key in path {
            guard node.kind == .object, let next = node.lastProperty(named: key)?.value else { return nil }
            node = next
        }
        return node
    }

    /// The property at `path` (object keys from here; the last names the
    /// property), or nil.
    public func property(at path: [String]) -> JSONCProperty? {
        guard let last = path.last, let parent = node(at: Array(path.dropLast())), parent.kind == .object else {
            return nil
        }
        return parent.lastProperty(named: last)
    }

    /// True when `offset` is between this container's brackets (after the
    /// opening one, at or before the closing one).
    func containsInside(_ offset: Int) -> Bool {
        guard isContainer, offset > range.location else { return false }
        if let closeRange { return offset <= closeRange.location }
        return offset <= contentEnd
    }
}

/// A `"key": value` member of an object.
public struct JSONCProperty: Sendable, Hashable {
    /// The decoded key.
    public let key: String
    /// The key string, quotes included (UTF-16).
    public let keyRange: NSRange
    /// The colon, nil when it's missing.
    public let colonRange: NSRange?
    /// The value, nil when it's missing.
    public let value: JSONCNode?
    /// The comma after the property, nil for the last one (unless it has a
    /// trailing comma) or when it's missing.
    public internal(set) var commaRange: NSRange?

    /// From the key through the value (or as far as the property goes when
    /// the value or colon is missing). Excludes the comma.
    public var range: NSRange {
        let end = value?.range.endOffset ?? colonRange?.endOffset ?? keyRange.endOffset
        return NSRange(location: keyRange.location, length: end - keyRange.location)
    }

    /// The value's range, or an empty range just after the colon (or key)
    /// when the value is missing.
    public var valueRange: NSRange {
        value?.range ?? NSRange(location: colonRange?.endOffset ?? keyRange.endOffset, length: 0)
    }
}

/// A syntax error in a ``JSONCDocument``.
public struct JSONCParseError: Sendable, Hashable {
    public enum Code: Sendable, Hashable {
        case valueExpected
        case propertyNameExpected
        case colonExpected
        case commaExpected
        case closeBraceExpected
        case closeBracketExpected
        case endOfFileExpected
        case unexpectedComma
        /// A bare word (or malformed number) where a value should be.
        case invalidValue
        case unterminatedString
        case unterminatedComment
        case invalidEscape
        case controlCharacterInString
        case invalidNumber
        case numberOutOfRange
        case tooDeeplyNested
    }

    public let code: Code
    /// UTF-16 range. It can be empty (length 0), e.g. at the end of the text
    /// for a missing closing brace.
    public let range: NSRange

    public init(code: Code, range: NSRange) {
        self.code = code
        self.range = range
    }

    /// A short, user-facing description.
    public var message: String {
        switch code {
        case .valueExpected: "Expected a value."
        case .propertyNameExpected: "Expected a setting name in double quotes."
        case .colonExpected: "Expected a colon."
        case .commaExpected: "Expected a comma."
        case .closeBraceExpected: "Expected a comma or closing brace."
        case .closeBracketExpected: "Expected a comma or closing bracket."
        case .endOfFileExpected: "Expected the end of the file."
        case .unexpectedComma: "Unexpected comma."
        case .invalidValue: "Invalid value. Text must be in double quotes."
        case .unterminatedString: "Unterminated string."
        case .unterminatedComment: "Unterminated comment."
        case .invalidEscape: "Invalid escape sequence in string."
        case .controlCharacterInString: "Control characters in strings must be escaped."
        case .invalidNumber: "Invalid number."
        case .numberOutOfRange: "Number is too large."
        case .tooDeeplyNested: "Too deeply nested."
        }
    }
}

// MARK: - Parser

/// Recursive-descent parser with error recovery over the token stream.
struct JSONCParser {
    private let units: [UInt16]
    private let tokens: [JSONCToken]
    /// Indexes of the non-trivia tokens.
    private let significant: [Int]
    private var position = 0
    private(set) var errors: [JSONCParseError] = []
    private(set) var keyTokenIndexes: Set<Int> = []
    /// Kinds of the open containers, innermost last.
    private var containers: [JSONCNode.Kind] = []

    static let maxDepth = 64

    init(units: [UInt16], tokens: [JSONCToken]) {
        self.units = units
        self.tokens = tokens
        var significant: [Int] = []
        significant.reserveCapacity(tokens.count / 2)
        for (index, token) in tokens.enumerated() where !token.isTrivia {
            significant.append(index)
        }
        self.significant = significant
    }

    mutating func parseDocument() -> JSONCNode? {
        reportTokenProblems()
        guard let first = current else { return nil }
        guard let root = parseValue() else {
            report(.valueExpected, first.range)
            return nil
        }
        if let extra = current {
            report(.endOfFileExpected, extra.range)
            position = significant.count
        }
        return root
    }

    // MARK: Token access

    private var current: JSONCToken? {
        position < significant.count ? tokens[significant[position]] : nil
    }

    private func peek(_ distance: Int = 1) -> JSONCToken? {
        let index = position + distance
        return index < significant.count ? tokens[significant[index]] : nil
    }

    private mutating func advance() { position += 1 }

    private var endOfText: NSRange { NSRange(location: units.count, length: 0) }

    /// Where parsing stopped: the current token's start, or the end of the text.
    private var stopOffset: Int { current?.range.location ?? units.count }

    /// True when a line break separates the current token from the one before.
    private func lineBreakBeforeCurrent() -> Bool {
        guard position > 0, position < significant.count else { return false }
        for index in (significant[position - 1] + 1)..<significant[position] {
            let token = tokens[index]
            if token.kind == .lineBreak { return true }
            if token.kind == .blockComment || token.kind == .lineComment {
                for offset in token.range.location..<token.end where units[offset] == Unit.lf || units[offset] == Unit.cr {
                    return true
                }
            }
        }
        return false
    }

    /// True when the current token is a string followed by a colon, i.e.
    /// the next property's name.
    private var currentIsPropertyName: Bool {
        current?.kind == .string && peek()?.kind == .colon
    }

    private mutating func report(_ code: JSONCParseError.Code, _ range: NSRange) {
        errors.append(JSONCParseError(code: code, range: range))
    }

    private mutating func reportTokenProblems() {
        for token in tokens {
            guard let problem = token.problem else { continue }
            let code: JSONCParseError.Code = switch problem {
            case .unterminatedString: .unterminatedString
            case .unterminatedComment: .unterminatedComment
            case .invalidEscape: .invalidEscape
            case .controlCharacterInString: .controlCharacterInString
            case .invalidNumber: .invalidNumber
            }
            report(code, token.range)
        }
    }

    // MARK: Values

    private mutating func parseValue() -> JSONCNode? {
        guard let token = current else { return nil }
        switch token.kind {
        case .openBrace, .openBracket:
            guard containers.count < Self.maxDepth else {
                report(.tooDeeplyNested, token.range)
                return skipNestedValue()
            }
            return token.kind == .openBrace ? parseObject() : parseArray()
        case .string:
            advance()
            return JSONCNode(kind: .string, range: token.range, scalarValue: .string(decodeString(token)))
        case .number:
            advance()
            guard token.problem == nil else { return JSONCNode(kind: .invalid, range: token.range) }
            let text = String(decoding: units[token.range.location..<token.end], as: UTF16.self)
            guard let number = Double(text), number.isFinite else {
                report(.numberOutOfRange, token.range)
                return JSONCNode(kind: .invalid, range: token.range)
            }
            return JSONCNode(kind: .number, range: token.range, scalarValue: .number(number))
        case .true, .false:
            advance()
            return JSONCNode(kind: .boolean, range: token.range, scalarValue: .bool(token.kind == .true))
        case .null:
            advance()
            return JSONCNode(kind: .null, range: token.range, scalarValue: .null)
        case .invalid:
            advance()
            report(.invalidValue, token.range)
            return JSONCNode(kind: .invalid, range: token.range)
        default:
            return nil
        }
    }

    private enum Separator {
        /// At the start, or just after a comma.
        case none
        /// After a member: a comma (or the closing bracket) should follow.
        case needed
        /// After recovering from an error: a comma may or may not follow.
        case optional
    }

    private mutating func parseObject() -> JSONCNode {
        let open = current!
        advance()
        containers.append(.object)
        defer { containers.removeLast() }

        var properties: [JSONCProperty] = []
        var separator = Separator.none
        var lastEnd = open.end
        var closeRange: NSRange?

        loop: while true {
            guard let token = current else {
                report(.closeBraceExpected, endOfText)
                break
            }
            switch token.kind {
            case .closeBrace:
                closeRange = token.range
                lastEnd = token.end
                advance()
                break loop
            case .comma:
                switch separator {
                case .needed: properties[properties.count - 1].commaRange = token.range
                case .optional: break
                case .none: report(.unexpectedComma, token.range)
                }
                separator = .none
                lastEnd = token.end
                advance()
            case .string:
                if separator == .needed { report(.commaExpected, token.range) }
                let property = parseProperty()
                properties.append(property)
                lastEnd = max(lastEnd, property.range.endOffset)
                // After a missing value or an unclosed object or array, don't
                // pile a "comma expected" on top.
                let complete = property.value.map { !$0.isContainer || $0.isClosed } ?? false
                separator = complete ? .needed : .optional
            case .closeBracket where containers.dropLast().contains(.array):
                // Most likely the end of an enclosing array.
                report(.closeBraceExpected, token.range)
                break loop
            default:
                report(.propertyNameExpected, token.range)
                lastEnd = max(lastEnd, skipBrokenProperty())
                separator = .optional
            }
        }
        return JSONCNode(
            kind: .object,
            range: NSRange(location: open.range.location, length: lastEnd - open.range.location),
            closeRange: closeRange,
            properties: properties,
            contentEnd: closeRange?.location ?? stopOffset
        )
    }

    private mutating func parseProperty() -> JSONCProperty {
        let keyToken = current!
        keyTokenIndexes.insert(significant[position])
        let key = decodeString(keyToken)
        advance()

        var colonRange: NSRange?
        var value: JSONCNode?
        if let colon = current, colon.kind == .colon {
            colonRange = colon.range
            advance()
            if let next = current, next.startsValue || next.kind == .invalid, !currentIsPropertyName {
                value = parseValue()
            } else {
                // `"a": }`, `"a": ,`, or `"a":` followed by the next property.
                report(.valueExpected, NSRange(location: colon.end, length: 0))
            }
        } else {
            report(.colonExpected, NSRange(location: keyToken.end, length: 0))
            // `"a" 1`: take a value on the same line.
            if let next = current, next.startsValue || next.kind == .invalid,
               !currentIsPropertyName, !lineBreakBeforeCurrent()
            {
                value = parseValue()
            }
        }
        return JSONCProperty(key: key, keyRange: keyToken.range, colonRange: colonRange, value: value, commaRange: nil)
    }

    /// Skips something that isn't a property, such as `chat.fontSize: 13`
    /// (a key without quotes) or a stray value. Returns the end of what was
    /// skipped.
    private mutating func skipBrokenProperty() -> Int {
        guard let token = current else { return units.count }
        var end = token.end
        if token.kind == .openBrace || token.kind == .openBracket {
            if let skipped = parseValue() { end = skipped.range.endOffset }
            return end
        }
        advance()
        if token.kind != .colon {
            guard let colon = current, colon.kind == .colon, !lineBreakBeforeCurrent() else { return end }
            end = colon.end
            advance()
        }
        if let next = current, next.startsValue || next.kind == .invalid, !currentIsPropertyName {
            if let skipped = parseValue() { end = skipped.range.endOffset }
        }
        return end
    }

    private mutating func parseArray() -> JSONCNode {
        let open = current!
        advance()
        containers.append(.array)
        defer { containers.removeLast() }

        var elements: [JSONCNode] = []
        var commas: [NSRange?] = []
        var separator = Separator.none
        var lastEnd = open.end
        var closeRange: NSRange?

        loop: while true {
            guard let token = current else {
                report(.closeBracketExpected, endOfText)
                break
            }
            switch token.kind {
            case .closeBracket:
                closeRange = token.range
                lastEnd = token.end
                advance()
                break loop
            case .comma:
                switch separator {
                case .needed: commas[commas.count - 1] = token.range
                case .optional: break
                case .none: report(.unexpectedComma, token.range)
                }
                separator = .none
                lastEnd = token.end
                advance()
            case .closeBrace where containers.dropLast().contains(.object):
                report(.closeBracketExpected, token.range)
                break loop
            case .string where currentIsPropertyName && containers.dropLast().contains(.object):
                // `"key":` inside an array: the array is missing its `]`.
                report(.closeBracketExpected, NSRange(location: lastEnd, length: 0))
                break loop
            default:
                if token.startsValue || token.kind == .invalid {
                    if separator == .needed { report(.commaExpected, token.range) }
                    if let element = parseValue() {
                        elements.append(element)
                        commas.append(nil)
                        lastEnd = element.range.endOffset
                        separator = !element.isContainer || element.isClosed ? .needed : .optional
                    }
                } else {
                    report(.valueExpected, token.range)
                    lastEnd = token.end
                    advance()
                    separator = .optional
                }
            }
        }
        return JSONCNode(
            kind: .array,
            range: NSRange(location: open.range.location, length: lastEnd - open.range.location),
            closeRange: closeRange,
            elements: elements,
            elementCommaRanges: commas,
            contentEnd: closeRange?.location ?? stopOffset
        )
    }

    /// Skips a too-deeply nested value without recursing.
    private mutating func skipNestedValue() -> JSONCNode {
        let start = current!.range.location
        var depth = 0
        var end = start
        while let token = current {
            switch token.kind {
            case .openBrace, .openBracket: depth += 1
            case .closeBrace, .closeBracket: depth -= 1
            default: break
            }
            end = token.end
            advance()
            if depth == 0 { break }
        }
        return JSONCNode(kind: .invalid, range: NSRange(location: start, length: end - start))
    }

    // MARK: Strings

    /// The decoded contents of a string token (unterminated ones too).
    private func decodeString(_ token: JSONCToken) -> String {
        let start = token.range.location + 1
        var end = token.end
        if token.problem != .unterminatedString, end > start, units[end - 1] == Unit.quote { end -= 1 }
        guard start < end else { return "" }
        return Self.unescape(units, start, end)
    }

    static func unescape(_ units: [UInt16], _ start: Int, _ end: Int) -> String {
        guard units[start..<end].contains(Unit.backslash) else {
            return String(decoding: units[start..<end], as: UTF16.self)
        }
        var out: [UInt16] = []
        out.reserveCapacity(end - start)
        var index = start
        while index < end {
            let unit = units[index]
            guard unit == Unit.backslash, index + 1 < end else {
                out.append(unit)
                index += 1
                continue
            }
            let escaped = units[index + 1]
            index += 2
            switch escaped {
            case UInt16(UInt8(ascii: "b")): out.append(0x08)
            case UInt16(UInt8(ascii: "f")): out.append(0x0C)
            case UInt16(UInt8(ascii: "n")): out.append(0x0A)
            case UInt16(UInt8(ascii: "r")): out.append(0x0D)
            case UInt16(UInt8(ascii: "t")): out.append(0x09)
            case UInt16(UInt8(ascii: "u")):
                var value: UInt16 = 0
                var digits = 0
                while digits < 4, index < end, let digit = JSONCScanner.hexValue(units[index]) {
                    value = value << 4 | digit
                    index += 1
                    digits += 1
                }
                if digits == 4 { out.append(value) }
            default: out.append(escaped)
            }
        }
        return String(decoding: out, as: UTF16.self)
    }
}
