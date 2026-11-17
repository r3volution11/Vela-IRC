// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// What the cursor is on in a ``JSONCDocument``, for completion: a
/// property name, a property value, an array element, or nothing useful
/// (a comment, outside the top-level value).
///
/// Paths are object keys from the root. Array indexes aren't part of
/// paths: inside an array, ``path`` names the property holding it.
public struct JSONCLocation: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// Nothing to complete (in a comment, outside the root value, or the
        /// root isn't an object or array).
        case none
        /// Typing a property name in the object at ``JSONCLocation/path``.
        case propertyKey
        /// Typing the value of the property at ``JSONCLocation/path``.
        case propertyValue
        /// Typing an element of the array held by the property at ``JSONCLocation/path``.
        case arrayElement
    }

    public var kind: Kind
    /// - ``Kind/propertyKey``: the object's path (`[]` at the top level).
    /// - ``Kind/propertyValue``: the property's path (its key last).
    /// - ``Kind/arrayElement``: the path of the property holding the array.
    public var path: [String]
    /// What's typed so far: the text from the start of the word or string
    /// (after the opening quote) to the cursor.
    public var prefix: String
    /// The range a completion replaces (UTF-16): the whole key string,
    /// value or word under the cursor, quotes included, or an empty range
    /// at the cursor.
    public var replaceRange: NSRange
    /// True when the cursor is inside a string's quotes.
    public var isInsideQuotes: Bool
    /// ``Kind/propertyKey``: the other keys already in the object (the key
    /// being edited is left out).
    public var siblingKeys: [String]
    /// ``Kind/propertyKey``: a colon already follows, so a completion should
    /// insert just the key.
    public var hasColon: Bool
    /// Something follows that needs a comma after the inserted text.
    public var needsCommaAfter: Bool
    /// Where a comma is missing after the previous member (insert `,`
    /// there), if anywhere.
    public var missingCommaOffset: Int?

    public init(
        kind: Kind,
        path: [String] = [],
        prefix: String = "",
        replaceRange: NSRange = NSRange(location: 0, length: 0),
        isInsideQuotes: Bool = false,
        siblingKeys: [String] = [],
        hasColon: Bool = false,
        needsCommaAfter: Bool = false,
        missingCommaOffset: Int? = nil
    ) {
        self.kind = kind
        self.path = path
        self.prefix = prefix
        self.replaceRange = replaceRange
        self.isInsideQuotes = isInsideQuotes
        self.siblingKeys = siblingKeys
        self.hasColon = hasColon
        self.needsCommaAfter = needsCommaAfter
        self.missingCommaOffset = missingCommaOffset
    }

    public static let none = JSONCLocation(kind: .none)
}

extension JSONCDocument {
    /// What the cursor at `offset` (UTF-16) is on. See ``JSONCLocation``.
    public func location(at offset: Int) -> JSONCLocation {
        let offset = max(0, min(offset, length))
        var finder = LocationFinder(document: self, offset: offset)
        if offset > 0, let index = tokenIndex(at: offset - 1) {
            let token = tokens[index]
            switch token.kind {
            case .lineComment:
                return .none
            case .blockComment:
                if !(token.problem == nil && offset == token.end) { return .none }
            case .string:
                let terminated = token.problem != .unterminatedString
                if offset < token.end || !terminated {
                    finder.word = token.range
                    finder.wordIsString = true
                }
            case .number, .true, .false, .null, .invalid:
                finder.word = token.range
            default:
                break
            }
        }
        guard let root, root.containsInside(offset) else { return .none }
        return root.kind == .object ? finder.inObject(root, path: []) : finder.inArray(root, path: [])
    }
}

private struct LocationFinder {
    let document: JSONCDocument
    let offset: Int
    /// The string, number, literal or bare word the cursor is in or at the
    /// end of.
    var word: NSRange?
    var wordIsString = false

    private func prefix(of range: NSRange) -> String {
        let start = range.location + (wordIsString ? 1 : 0)
        return document.text(in: NSRange(location: start, length: max(0, offset - start)))
    }

    private static let valueEndKinds: Set<JSONCToken.Kind> = [
        .string, .number, .true, .false, .null, .closeBrace, .closeBracket, .invalid,
    ]
    private static let valueStartKinds: Set<JSONCToken.Kind> = [
        .string, .number, .true, .false, .null, .openBrace, .openBracket, .invalid,
    ]

    /// Something value-like right after `offset`.
    private func valueFollows(_ offset: Int) -> Bool {
        guard let next = document.significantToken(from: offset) else { return false }
        return Self.valueStartKinds.contains(next.kind)
    }

    /// The end of a value-like token right before `offset` inside
    /// `container`, which then needs a comma.
    private func missingComma(before offset: Int, in container: JSONCNode) -> Int? {
        guard let previous = document.significantToken(before: offset),
              previous.range.location > container.range.location,
              Self.valueEndKinds.contains(previous.kind)
        else { return nil }
        if previous.kind == .string,
           let index = document.tokenIndex(startingAt: previous.range.location),
           document.isPropertyKey(tokenAt: index)
        {
            return nil
        }
        return previous.end
    }

    func inObject(_ object: JSONCNode, path: [String]) -> JSONCLocation {
        let properties = object.properties
        for (index, property) in properties.enumerated() {
            if let word, word == property.keyRange {
                return key(in: object, path: path, editing: index, replace: word, prefix: prefix(of: word))
            }
            guard let colon = property.colonRange, offset >= colon.endOffset else { continue }
            let valuePath = path + [property.key]
            if let value = property.value {
                if value.isContainer, value.containsInside(offset) {
                    return value.kind == .object ? inObject(value, path: valuePath) : inArray(value, path: valuePath)
                }
                if offset <= value.range.location {
                    let replace = value.isContainer ? NSRange(location: offset, length: 0) : value.range
                    return self.value(of: property, path: valuePath, replace: replace, prefix: "", inQuotes: false)
                }
                if !value.isContainer, let word, word == value.range {
                    return self.value(of: property, path: valuePath, replace: word, prefix: prefix(of: word), inQuotes: wordIsString)
                }
            } else {
                let regionEnd = property.commaRange?.location
                    ?? (index + 1 < properties.count ? properties[index + 1].keyRange.location : nil)
                    ?? object.closeRange?.location
                    ?? object.contentEnd
                if offset <= regionEnd {
                    let replace = word ?? NSRange(location: offset, length: 0)
                    let typed = word.map(prefix(of:)) ?? ""
                    return self.value(of: property, path: valuePath, replace: replace, prefix: typed, inQuotes: word != nil && wordIsString)
                }
            }
        }
        let replace = word ?? NSRange(location: offset, length: 0)
        return key(in: object, path: path, editing: nil, replace: replace, prefix: word.map(prefix(of:)) ?? "")
    }

    func inArray(_ array: JSONCNode, path: [String]) -> JSONCLocation {
        for element in array.elements {
            if element.isContainer, element.containsInside(offset) {
                return element.kind == .object ? inObject(element, path: path) : inArray(element, path: path)
            }
        }
        let replace = word ?? NSRange(location: offset, length: 0)
        return JSONCLocation(
            kind: .arrayElement,
            path: path,
            prefix: word.map(prefix(of:)) ?? "",
            replaceRange: replace,
            isInsideQuotes: word != nil && wordIsString,
            needsCommaAfter: valueFollows(replace.endOffset),
            missingCommaOffset: missingComma(before: replace.location, in: array)
        )
    }

    private func key(in object: JSONCNode, path: [String], editing: Int?, replace: NSRange, prefix: String) -> JSONCLocation {
        let siblings = object.properties.enumerated().filter { $0.offset != editing }.map(\.element.key)
        let hasColon = document.significantToken(from: replace.endOffset)?.kind == .colon
        return JSONCLocation(
            kind: .propertyKey,
            path: path,
            prefix: prefix,
            replaceRange: replace,
            isInsideQuotes: word != nil && wordIsString,
            siblingKeys: siblings,
            hasColon: hasColon,
            needsCommaAfter: !hasColon && valueFollows(replace.endOffset),
            missingCommaOffset: missingComma(before: replace.location, in: object)
        )
    }

    private func value(of property: JSONCProperty, path: [String], replace: NSRange, prefix: String, inQuotes: Bool) -> JSONCLocation {
        JSONCLocation(
            kind: .propertyValue,
            path: path,
            prefix: prefix,
            replaceRange: replace,
            isInsideQuotes: inQuotes,
            needsCommaAfter: property.commaRange == nil && valueFollows(replace.endOffset)
        )
    }
}
