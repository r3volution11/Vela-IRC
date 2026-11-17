// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

// JSONC syntax: a tokenizer for highlighting and the token stream the
// positioned parser (JSONCDocument) is built on.
//
// Every offset and range in the JSONC types is in UTF-16 code units, the
// unit NSString, NSRange and NSTextView use, so ranges can be handed to
// AppKit text APIs as they are.

/// One lexical token of JSONC text.
///
/// The tokens of a text are contiguous and cover all of it: whitespace,
/// line breaks and comments are tokens too. Broken input never fails;
/// it becomes tokens with a ``problem`` (an unterminated string, for
/// example) or ``Kind/invalid`` tokens.
public struct JSONCToken: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case openBrace, closeBrace, openBracket, closeBracket, colon, comma
        /// A string, quotes included. Unterminated strings end before the
        /// line break (strings can't span lines).
        case string
        /// A number. Malformed ones (`12px`, `1.`) have ``Problem/invalidNumber``.
        case number
        case `true`, `false`, null
        /// `// …` up to (not including) the line break.
        case lineComment
        /// `/* … */`, possibly spanning lines; unterminated ones run to the end.
        case blockComment
        /// Spaces, tabs and byte order marks.
        case whitespace
        /// `\n`, `\r\n` or `\r`.
        case lineBreak
        /// Anything else: a bare word such as `tru` or `chat.fontSize`, or a
        /// stray character such as `/` or `'`.
        case invalid
    }

    /// Something wrong with a token's own text.
    public enum Problem: Sendable, Hashable {
        case unterminatedString
        case unterminatedComment
        /// A backslash escape other than `\" \\ \/ \b \f \n \r \t \uXXXX`.
        case invalidEscape
        /// A raw control character (such as a tab) inside a string.
        case controlCharacterInString
        case invalidNumber
    }

    public let kind: Kind
    /// UTF-16 range of the token in the text.
    public let range: NSRange
    public let problem: Problem?

    public init(kind: Kind, range: NSRange, problem: Problem? = nil) {
        self.kind = kind
        self.range = range
        self.problem = problem
    }

    /// UTF-16 offset just past the token.
    public var end: Int { range.location + range.length }

    /// Whitespace, line breaks and comments.
    public var isTrivia: Bool {
        switch kind {
        case .whitespace, .lineBreak, .lineComment, .blockComment: true
        default: false
        }
    }

    public var isComment: Bool { kind == .lineComment || kind == .blockComment }

    /// Tokens that can start a value: strings, numbers, literals, `{`, `[`.
    public var startsValue: Bool {
        switch kind {
        case .string, .number, .true, .false, .null, .openBrace, .openBracket: true
        default: false
        }
    }
}

/// Splits JSONC text into ``JSONCToken``s.
public enum JSONCScanner {
    /// The tokens of `text`, in order. Their ranges are UTF-16.
    public static func tokens(in text: String) -> [JSONCToken] {
        scan(Array(text.utf16)).tokens
    }

    /// Tokens plus the UTF-16 offset where each line starts (the first is 0).
    static func scan(_ units: [UInt16]) -> (tokens: [JSONCToken], lineStarts: [Int]) {
        units.withUnsafeBufferPointer { scan($0) }
    }

    private static func scan(_ u: UnsafeBufferPointer<UInt16>) -> (tokens: [JSONCToken], lineStarts: [Int]) {
        let n = u.count
        var tokens: [JSONCToken] = []
        tokens.reserveCapacity(n / 3 + 1)
        var lineStarts = [0]
        var i = 0

        @inline(__always) func add(_ kind: JSONCToken.Kind, _ start: Int, _ problem: JSONCToken.Problem? = nil) {
            tokens.append(JSONCToken(kind: kind, range: NSRange(location: start, length: i - start), problem: problem))
        }

        while i < n {
            let start = i
            let c = u[i]
            switch c {
            case Unit.space, Unit.tab, Unit.bom:
                while i < n, u[i] == Unit.space || u[i] == Unit.tab || u[i] == Unit.bom { i += 1 }
                add(.whitespace, start)
            case Unit.lf:
                i += 1
                lineStarts.append(i)
                add(.lineBreak, start)
            case Unit.cr:
                i += 1
                if i < n, u[i] == Unit.lf { i += 1 }
                lineStarts.append(i)
                add(.lineBreak, start)
            case Unit.openBrace: i += 1; add(.openBrace, start)
            case Unit.closeBrace: i += 1; add(.closeBrace, start)
            case Unit.openBracket: i += 1; add(.openBracket, start)
            case Unit.closeBracket: i += 1; add(.closeBracket, start)
            case Unit.colon: i += 1; add(.colon, start)
            case Unit.comma: i += 1; add(.comma, start)
            case Unit.quote:
                let problem = scanString(u, &i)
                add(.string, start, problem)
            case Unit.slash where i + 1 < n && u[i + 1] == Unit.slash:
                i += 2
                while i < n, u[i] != Unit.lf, u[i] != Unit.cr { i += 1 }
                add(.lineComment, start)
            case Unit.slash where i + 1 < n && u[i + 1] == Unit.star:
                i += 2
                var terminated = false
                while i < n {
                    if u[i] == Unit.star, i + 1 < n, u[i + 1] == Unit.slash {
                        i += 2
                        terminated = true
                        break
                    }
                    if u[i] == Unit.lf {
                        lineStarts.append(i + 1)
                    } else if u[i] == Unit.cr, !(i + 1 < n && u[i + 1] == Unit.lf) {
                        lineStarts.append(i + 1)
                    }
                    i += 1
                }
                add(.blockComment, start, terminated ? nil : .unterminatedComment)
            default:
                if isWordUnit(c) {
                    while i < n, isWordUnit(u[i]) { i += 1 }
                    let kind = wordKind(u, start, i)
                    let problem: JSONCToken.Problem? =
                        kind == .number && !isValidNumber(u, start, i) ? .invalidNumber : nil
                    add(kind, start, problem)
                } else {
                    // A lone `/` (or similar): one character, keeping
                    // surrogate pairs together.
                    i += 1
                    add(.invalid, start)
                }
            }
        }
        return (tokens, lineStarts)
    }

    /// Scans a string starting at the opening quote; leaves `i` past it.
    private static func scanString(_ u: UnsafeBufferPointer<UInt16>, _ i: inout Int) -> JSONCToken.Problem? {
        let n = u.count
        var problem: JSONCToken.Problem?
        i += 1
        while true {
            guard i < n else { return .unterminatedString }
            let c = u[i]
            if c == Unit.quote {
                i += 1
                return problem
            }
            if c == Unit.lf || c == Unit.cr {
                return .unterminatedString
            }
            if c == Unit.backslash {
                i += 1
                guard i < n else { return .unterminatedString }
                let escaped = u[i]
                if escaped == Unit.lf || escaped == Unit.cr { return .unterminatedString }
                i += 1
                switch escaped {
                case Unit.quote, Unit.backslash, Unit.slash,
                     UInt16(UInt8(ascii: "b")), UInt16(UInt8(ascii: "f")), UInt16(UInt8(ascii: "n")),
                     UInt16(UInt8(ascii: "r")), UInt16(UInt8(ascii: "t")):
                    break
                case UInt16(UInt8(ascii: "u")):
                    var digits = 0
                    while digits < 4, i < n, hexValue(u[i]) != nil {
                        i += 1
                        digits += 1
                    }
                    if digits < 4 { problem = problem ?? .invalidEscape }
                default:
                    problem = problem ?? .invalidEscape
                }
                continue
            }
            if c < 0x20 { problem = problem ?? .controlCharacterInString }
            i += 1
        }
    }

    /// Characters that make up bare words: everything except whitespace,
    /// line breaks, structural characters, quotes and slashes.
    @inline(__always) static func isWordUnit(_ c: UInt16) -> Bool {
        switch c {
        case Unit.space, Unit.tab, Unit.lf, Unit.cr, Unit.bom,
             Unit.openBrace, Unit.closeBrace, Unit.openBracket, Unit.closeBracket,
             Unit.colon, Unit.comma, Unit.quote, Unit.slash:
            false
        default:
            true
        }
    }

    private static func wordKind(_ u: UnsafeBufferPointer<UInt16>, _ start: Int, _ end: Int) -> JSONCToken.Kind {
        let first = u[start]
        if first == Unit.minus || (first >= Unit.zero && first <= Unit.nine) { return .number }
        if matches(u, start, end, "true") { return .true }
        if matches(u, start, end, "false") { return .false }
        if matches(u, start, end, "null") { return .null }
        return .invalid
    }

    private static func matches(_ u: UnsafeBufferPointer<UInt16>, _ start: Int, _ end: Int, _ word: StaticString) -> Bool {
        guard end - start == word.utf8CodeUnitCount else { return false }
        let bytes = UnsafeBufferPointer(start: word.utf8Start, count: word.utf8CodeUnitCount)
        for (offset, byte) in bytes.enumerated() where u[start + offset] != UInt16(byte) {
            return false
        }
        return true
    }

    /// JSON's number grammar: `-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?`.
    private static func isValidNumber(_ u: UnsafeBufferPointer<UInt16>, _ start: Int, _ end: Int) -> Bool {
        var j = start
        func isDigit(_ k: Int) -> Bool { k < end && u[k] >= Unit.zero && u[k] <= Unit.nine }
        if j < end, u[j] == Unit.minus { j += 1 }
        if j < end, u[j] == Unit.zero {
            j += 1
        } else if isDigit(j) {
            while isDigit(j) { j += 1 }
        } else {
            return false
        }
        if j < end, u[j] == UInt16(UInt8(ascii: ".")) {
            j += 1
            guard isDigit(j) else { return false }
            while isDigit(j) { j += 1 }
        }
        if j < end, u[j] == UInt16(UInt8(ascii: "e")) || u[j] == UInt16(UInt8(ascii: "E")) {
            j += 1
            if j < end, u[j] == UInt16(UInt8(ascii: "+")) || u[j] == Unit.minus { j += 1 }
            guard isDigit(j) else { return false }
            while isDigit(j) { j += 1 }
        }
        return j == end
    }

    static func hexValue(_ c: UInt16) -> UInt16? {
        switch c {
        case Unit.zero...Unit.nine: c - Unit.zero
        case UInt16(UInt8(ascii: "a"))...UInt16(UInt8(ascii: "f")): c - UInt16(UInt8(ascii: "a")) + 10
        case UInt16(UInt8(ascii: "A"))...UInt16(UInt8(ascii: "F")): c - UInt16(UInt8(ascii: "A")) + 10
        default: nil
        }
    }
}

/// UTF-16 code units the JSONC code looks at.
enum Unit {
    static let space = UInt16(UInt8(ascii: " "))
    static let tab = UInt16(UInt8(ascii: "\t"))
    static let lf = UInt16(UInt8(ascii: "\n"))
    static let cr = UInt16(UInt8(ascii: "\r"))
    static let bom: UInt16 = 0xFEFF
    static let openBrace = UInt16(UInt8(ascii: "{"))
    static let closeBrace = UInt16(UInt8(ascii: "}"))
    static let openBracket = UInt16(UInt8(ascii: "["))
    static let closeBracket = UInt16(UInt8(ascii: "]"))
    static let colon = UInt16(UInt8(ascii: ":"))
    static let comma = UInt16(UInt8(ascii: ","))
    static let quote: UInt16 = 0x22
    static let backslash = UInt16(UInt8(ascii: "\\"))
    static let slash = UInt16(UInt8(ascii: "/"))
    static let star = UInt16(UInt8(ascii: "*"))
    static let minus = UInt16(UInt8(ascii: "-"))
    static let zero = UInt16(UInt8(ascii: "0"))
    static let nine = UInt16(UInt8(ascii: "9"))
}

extension NSRange {
    /// `location + length`.
    var endOffset: Int { location + length }
}
