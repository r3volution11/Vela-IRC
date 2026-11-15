// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A forgiving, allocation-light tokenizer for the `<head>` of real-world HTML.
///
/// It works on UTF-8 (or any ASCII-compatible) bytes and only understands
/// what metadata extraction needs: start/end tags with attributes, comments,
/// and raw-text elements (`script`, `style`, `title`, …) whose content must
/// not be scanned for tags. It never throws; malformed input just ends early.
struct HTMLTagScanner {
    enum Token {
        /// A start tag. Names and attribute names are lowercased; attribute
        /// values are entity-decoded. For raw-text elements (`title`, `script`,
        /// `style`, `textarea`) `rawText` holds the element's content.
        case startTag(name: String, attributes: [String: String], rawText: String?)
        case endTag(name: String)
    }

    private let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    init(_ html: String) {
        self.init(bytes: Array(html.utf8))
    }

    /// Byte offset just past the last token returned.
    var position: Int { index }

    private static let rawTextElements: Set<String> = ["script", "style", "title", "textarea", "xmp", "noembed"]
    /// Elements whose whole subtree is skipped (an `<svg>` may contain a `<title>`).
    private static let skippedElements: Set<String> = ["svg", "math", "template"]

    mutating func next() -> Token? {
        while let open = firstIndex(of: UInt8(ascii: "<"), from: index) {
            index = open + 1
            guard index < bytes.count else { return nil }
            let c = bytes[index]

            if c == UInt8(ascii: "!") {
                if matches("!--", at: index) {
                    index = endOfSequence("-->", from: index + 3) ?? bytes.count
                } else {
                    // <!DOCTYPE …>, <![CDATA[ … ]]> and other markup declarations.
                    index = (firstIndex(of: UInt8(ascii: ">"), from: index) ?? bytes.count - 1) + 1
                }
                continue
            }
            if c == UInt8(ascii: "?") {
                index = (firstIndex(of: UInt8(ascii: ">"), from: index) ?? bytes.count - 1) + 1
                continue
            }
            if c == UInt8(ascii: "/") {
                index += 1
                let name = readTagName()
                index = (firstIndex(of: UInt8(ascii: ">"), from: index) ?? bytes.count - 1) + 1
                guard !name.isEmpty else { continue }
                return .endTag(name: name)
            }
            guard Self.isASCIILetter(c) else { continue }

            let name = readTagName()
            let (attributes, selfClosing) = readAttributes()

            if Self.skippedElements.contains(name) {
                if !selfClosing { index = endOfClosingTag(name) ?? bytes.count }
                continue
            }
            if Self.rawTextElements.contains(name), !selfClosing {
                let contentStart = index
                let closeStart = startOfClosingTag(name) ?? bytes.count
                let raw = String(decoding: bytes[contentStart..<closeStart], as: UTF8.self)
                index = closeStart
                if index < bytes.count {
                    index = (firstIndex(of: UInt8(ascii: ">"), from: index) ?? bytes.count - 1) + 1
                }
                return .startTag(name: name, attributes: attributes, rawText: raw)
            }
            return .startTag(name: name, attributes: attributes, rawText: nil)
        }
        index = bytes.count
        return nil
    }

    // MARK: - Pieces

    private mutating func readTagName() -> String {
        let start = index
        while index < bytes.count {
            let c = bytes[index]
            if Self.isWhitespace(c) || c == UInt8(ascii: ">") || c == UInt8(ascii: "/") { break }
            index += 1
        }
        return Self.lowercasedASCII(bytes[start..<index])
    }

    private mutating func readAttributes() -> ([String: String], Bool) {
        var attributes: [String: String] = [:]
        var selfClosing = false

        while index < bytes.count {
            skipWhitespace()
            guard index < bytes.count else { break }
            let c = bytes[index]
            if c == UInt8(ascii: ">") {
                index += 1
                return (attributes, selfClosing)
            }
            if c == UInt8(ascii: "/") {
                selfClosing = index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: ">")
                index += 1
                continue
            }

            let nameStart = index
            while index < bytes.count {
                let c = bytes[index]
                if Self.isWhitespace(c) || c == UInt8(ascii: "=") || c == UInt8(ascii: ">") { break }
                if c == UInt8(ascii: "/"), index > nameStart { break }
                index += 1
            }
            if index == nameStart { index += 1; continue }
            let name = Self.lowercasedASCII(bytes[nameStart..<index])
            selfClosing = false

            skipWhitespace()
            var value = ""
            if index < bytes.count, bytes[index] == UInt8(ascii: "=") {
                index += 1
                skipWhitespace()
                value = readAttributeValue()
            }
            if attributes[name] == nil { attributes[name] = value }
        }
        return (attributes, selfClosing)
    }

    private mutating func readAttributeValue() -> String {
        guard index < bytes.count else { return "" }
        let quote = bytes[index]
        let start: Int
        let end: Int
        if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
            start = index + 1
            end = firstIndex(of: quote, from: start) ?? bytes.count
            index = min(end + 1, bytes.count)
        } else {
            start = index
            while index < bytes.count, !Self.isWhitespace(bytes[index]), bytes[index] != UInt8(ascii: ">") {
                index += 1
            }
            end = index
        }
        return HTMLEntities.decode(String(decoding: bytes[start..<end], as: UTF8.self))
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, Self.isWhitespace(bytes[index]) { index += 1 }
    }

    private func firstIndex(of byte: UInt8, from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        return bytes[start...].firstIndex(of: byte)
    }

    /// Case-insensitive match of an ASCII literal at `position`.
    private func matches(_ literal: String, at position: Int) -> Bool {
        let utf8 = literal.utf8
        guard position + utf8.count <= bytes.count else { return false }
        var i = position
        for expected in utf8 {
            if Self.lowercase(bytes[i]) != expected { return false }
            i += 1
        }
        return true
    }

    /// Index just past the first occurrence of `literal` at or after `start`.
    private func endOfSequence(_ literal: String, from start: Int) -> Int? {
        let count = literal.utf8.count
        var i = start
        while let candidate = firstIndex(of: literal.utf8.first!, from: i) {
            if matches(literal, at: candidate) { return candidate + count }
            i = candidate + 1
        }
        return nil
    }

    /// Index of the `<` that starts `</name` (followed by whitespace, `/` or `>`).
    private func startOfClosingTag(_ name: String) -> Int? {
        let needle = "</" + name
        var i = index
        while let candidate = firstIndex(of: UInt8(ascii: "<"), from: i) {
            let after = candidate + needle.utf8.count
            if matches(needle, at: candidate),
               after >= bytes.count || Self.isWhitespace(bytes[after]) || bytes[after] == UInt8(ascii: ">")
                || bytes[after] == UInt8(ascii: "/") {
                return candidate
            }
            i = candidate + 1
        }
        return nil
    }

    private func endOfClosingTag(_ name: String) -> Int? {
        guard let start = startOfClosingTag(name) else { return nil }
        return (bytes[start...].firstIndex(of: UInt8(ascii: ">")) ?? bytes.count - 1) + 1
    }

    // MARK: - ASCII helpers

    static func isWhitespace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D
    }

    static func isASCIILetter(_ c: UInt8) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }

    static func lowercase(_ c: UInt8) -> UInt8 {
        (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c
    }

    static func lowercasedASCII(_ slice: ArraySlice<UInt8>) -> String {
        String(decoding: slice.lazy.map(lowercase), as: UTF8.self)
    }
}
