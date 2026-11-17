// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaFoundation

/// The UTF-16 range of the `occurrence`-th match of `needle` in `text`.
func range(of needle: String, in text: String, occurrence: Int = 1) -> NSRange {
    let ns = text as NSString
    var searchStart = 0
    var found = NSRange(location: NSNotFound, length: 0)
    for _ in 0..<occurrence {
        found = ns.range(of: needle, range: NSRange(location: searchStart, length: ns.length - searchStart))
        precondition(found.location != NSNotFound, "\(needle) not found")
        searchStart = found.location + found.length
    }
    return found
}

/// UTF-16 offset of `marker` in `text`, and `text` without it.
func cursor(_ text: String, marker: String = "|") -> (text: String, offset: Int) {
    let location = (text as NSString).range(of: marker).location
    precondition(location != NSNotFound)
    return ((text as NSString).replacingCharacters(in: NSRange(location: location, length: marker.utf16.count), with: ""), location)
}

@Suite("JSONC tokenizer")
struct JSONCScannerTests {
    private func kinds(_ text: String, trivia: Bool = false) -> [JSONCToken.Kind] {
        JSONCScanner.tokens(in: text).filter { trivia || !$0.isTrivia }.map(\.kind)
    }

    @Test func tokenizesValidJSONC() {
        let text = """
            {"a": 1, // note
              "b": [true, false, null], /* block */ "c": -1.5e3,}
            """
        #expect(kinds(text) == [
            .openBrace, .string, .colon, .number, .comma,
            .string, .colon, .openBracket, .true, .comma, .false, .comma, .null, .closeBracket, .comma,
            .string, .colon, .number, .comma, .closeBrace,
        ])
        let tokens = JSONCScanner.tokens(in: text)
        #expect(tokens.contains { $0.kind == .lineComment && $0.range == range(of: "// note", in: text) })
        #expect(tokens.contains { $0.kind == .blockComment && $0.range == range(of: "/* block */", in: text) })
        #expect(tokens.allSatisfy { $0.problem == nil })
    }

    @Test func tokensCoverTheTextContiguously() {
        let text = "{\r\n\t\"a\" : [1,2] // x\r\n/* y\n z */}\n  "
        let tokens = JSONCScanner.tokens(in: text)
        var offset = 0
        for token in tokens {
            #expect(token.range.location == offset)
            offset = token.end
        }
        #expect(offset == text.utf16.count)
        #expect(tokens.filter { $0.kind == .lineBreak }.map(\.range.length) == [2, 2, 1])
    }

    @Test func unterminatedStringsAndCommentsAreTokens() {
        let open = JSONCScanner.tokens(in: "{\"chat.fo\n}")
        #expect(open[1].kind == .string)
        #expect(open[1].problem == .unterminatedString)
        #expect(open[1].range == NSRange(location: 1, length: 8))  // stops before the line break
        #expect(open[2].kind == .lineBreak)

        let atEnd = JSONCScanner.tokens(in: "\"abc")
        #expect(atEnd.map(\.problem) == [.unterminatedString])

        let comment = JSONCScanner.tokens(in: "{} /* never closed\n more")
        #expect(comment.last?.kind == .blockComment)
        #expect(comment.last?.problem == .unterminatedComment)
    }

    @Test func invalidInputBecomesInvalidTokens() {
        #expect(kinds("tru") == [.invalid])
        #expect(kinds("'single'") == [.invalid])
        #expect(kinds("chat.fontSize: 13") == [.invalid, .colon, .number])
        #expect(kinds("/ x") == [.invalid, .invalid])
        let number = JSONCScanner.tokens(in: "12px")
        #expect(number.map(\.kind) == [.number])
        #expect(number.first?.problem == .invalidNumber)
        #expect(kinds(".5") == [.invalid])
        for bad in ["-", "1.", "01", "1e", "1e+"] {
            #expect(JSONCScanner.tokens(in: bad).first?.problem == .invalidNumber, "\(bad)")
        }
        for good in ["0", "-0", "13", "0.35", "-1.5e3", "2E-7", "1e+9"] {
            #expect(JSONCScanner.tokens(in: good).first?.problem == nil, "\(good)")
        }
    }

    @Test func stringEscapes() {
        #expect(JSONCScanner.tokens(in: #""a\"b\\c\/\né""#).map(\.problem) == [nil])
        #expect(JSONCScanner.tokens(in: #""bad \q""#).first?.problem == .invalidEscape)
        #expect(JSONCScanner.tokens(in: #""bad \u12""#).first?.problem == .invalidEscape)
        #expect(JSONCScanner.tokens(in: "\"tab\there\"").first?.problem == .controlCharacterInString)
        // An escaped quote doesn't end the string.
        #expect(JSONCScanner.tokens(in: #""a\"" "b""#).filter { !$0.isTrivia }.count == 2)
    }

    @Test func rangesAreUTF16() {
        let text = #"{"😀 é": "naïve 👍🏽"}"#
        let tokens = JSONCScanner.tokens(in: text).filter { $0.kind == .string }
        #expect(tokens[0].range == range(of: #""😀 é""#, in: text))
        #expect(tokens[0].range.length == 6)
        #expect(tokens[1].range == range(of: #""naïve 👍🏽""#, in: text))
    }

    @Test func byteOrderMarkIsWhitespace() {
        #expect(kinds("\u{FEFF}{}") == [.openBrace, .closeBrace])
    }
}

@Suite("JSONC parser")
struct JSONCParserTests {
    static let commentRich = """
        // Vela settings
        {
            /* Appearance */
            "appearance.theme": "Palenight", // dark
            "appearance.colorCustomizations": {
                "chat.background": "#1e1e2e", // darker
                "[Lighter]": {
                    "accent": "#ff8800",
                },
            },
            "highlight.words": ["vela", "release"],
            "chat.fontSize": 14.5,
            "chat.showTimestamps": false,
            "future.setting": null,
            "escapes": "tab\\t quote\\" slash\\/ \\u00e9 \\ud83d\\ude00",
        }

        """

    @Test func parsesValidJSONCLikeTheDecoder() throws {
        for text in [Self.commentRich, "{}", "[1, 2, {\"a\": []}]", "\"just a string\"", "  42  ", "{\"a\": {\"b\": {\"c\": [true, null]}}}"] {
            let document = JSONCDocument(text)
            #expect(document.errors.isEmpty, "\(text)")
            #expect(document.jsonValue == (try JSONC.value(from: Data(text.utf8))), "\(text)")
        }
    }

    @Test func positionsOfPropertiesAndValues() throws {
        let text = Self.commentRich
        let document = JSONCDocument(text)
        let root = try #require(document.root)
        #expect(root.kind == .object)
        #expect(root.properties.map(\.key) == [
            "appearance.theme", "appearance.colorCustomizations", "highlight.words",
            "chat.fontSize", "chat.showTimestamps", "future.setting", "escapes",
        ])

        let theme = try #require(root.lastProperty(named: "appearance.theme"))
        #expect(theme.keyRange == range(of: #""appearance.theme""#, in: text))
        #expect(theme.value?.range == range(of: #""Palenight""#, in: text))
        #expect(theme.range == range(of: #""appearance.theme": "Palenight""#, in: text))
        #expect(theme.commaRange == NSRange(location: range(of: #""Palenight""#, in: text).endOffset, length: 1))

        let nested = try #require(root.node(at: ["appearance.colorCustomizations", "[Lighter]"]))
        #expect(nested.kind == .object)
        #expect(nested.properties.first?.key == "accent")
        #expect(nested.properties.first?.commaRange != nil)  // trailing comma
        #expect(root.property(at: ["appearance.colorCustomizations", "chat.background"])?.value?.scalarValue == "#1e1e2e")

        let words = try #require(root.lastProperty(named: "highlight.words")?.value)
        #expect(words.kind == .array)
        #expect(words.elements.map(\.scalarValue) == ["vela", "release"])
        #expect(words.elementCommaRanges.map { $0 != nil } == [true, false])
        #expect(words.range == range(of: #"["vela", "release"]"#, in: text))

        #expect(root.lastProperty(named: "escapes")?.value?.scalarValue == .string("tab\t quote\" slash/ é 😀"))
        #expect(root.lastProperty(named: "chat.fontSize")?.value?.scalarValue == .number(14.5))
        #expect(root.closeRange != nil)
    }

    @Test func emptyAndCommentOnlyTextHasNoRoot() {
        for text in ["", "   \n", "// nothing yet\n", "/* a */ // b"] {
            let document = JSONCDocument(text)
            #expect(document.root == nil)
            #expect(document.errors.isEmpty)
        }
    }

    @Test func missingCommaKeepsBothProperties() throws {
        let text = """
            {
              "a": 1
              "b": 2
            }
            """
        let document = JSONCDocument(text)
        #expect(document.errors.map(\.code) == [.commaExpected])
        #expect(document.errors.first?.range == range(of: #""b""#, in: text))
        #expect(document.jsonValue == .object(["a": 1, "b": 2]))
    }

    @Test func trailingCommasAreFine() {
        #expect(JSONCDocument(#"{"a": [1, 2,], "b": {"c": 1,},}"#).errors.isEmpty)
    }

    @Test func doubleCommaIsAnError() {
        #expect(JSONCDocument(#"{"a": 1,, "b": 2}"#).errors.map(\.code) == [.unexpectedComma])
        #expect(JSONCDocument(#"[1,,2]"#).errors.map(\.code) == [.unexpectedComma])
    }

    @Test func partialTextWhileTyping() throws {
        // A half-typed key on its own line.
        let typingKey = JSONCDocument("{\n  \"a\": 1,\n  \"ch\n}")
        #expect(typingKey.errors.map(\.code).contains(.unterminatedString))
        #expect(typingKey.root?.properties.map(\.key) == ["a", "ch"])
        #expect(typingKey.root?.isClosed == true)

        // A key without a value yet, followed by another property.
        let noValue = JSONCDocument("{\n  \"chat.layout\":\n  \"b\": 2\n}")
        #expect(noValue.errors.map(\.code) == [.valueExpected])
        #expect(noValue.root?.properties.map(\.key) == ["chat.layout", "b"])
        #expect(noValue.root?.properties.first?.value == nil)
        #expect(noValue.jsonValue == .object(["b": 2]))

        // A half-typed value.
        let typingValue = JSONCDocument("{\n  \"chat.layout\": \"gro\n}")
        #expect(typingValue.errors.map(\.code) == [.unterminatedString])
        #expect(typingValue.root?.properties.first?.value?.scalarValue == "gro")

        // A bare word value.
        let bare = JSONCDocument("{\"chat.layout\": classic, \"b\": 1}")
        #expect(bare.errors.map(\.code) == [.invalidValue])
        #expect(bare.root?.properties.first?.value?.kind == .invalid)
        #expect(bare.jsonValue == .object(["b": 1]))

        // A key without quotes.
        let unquoted = JSONCDocument("{\n  chat.fontSize: 13,\n  \"b\": 1\n}")
        #expect(unquoted.errors.map(\.code) == [.propertyNameExpected])
        #expect(unquoted.jsonValue == .object(["b": 1]))

        // A missing colon.
        let noColon = JSONCDocument(#"{"a" 1}"#)
        #expect(noColon.errors.map(\.code) == [.colonExpected])
        #expect(noColon.jsonValue == .object(["a": 1]))

        // Unclosed objects and arrays.
        let unclosed = JSONCDocument("{\n  \"a\": {\"x\": 1,\n  \"b\": 2,\n")
        #expect(unclosed.errors.map(\.code) == [.closeBraceExpected, .closeBraceExpected])
        #expect(unclosed.root?.isClosed == false)
        let openArray = JSONCDocument("{\n  \"a\": [1, 2,\n  \"b\": 3\n}")
        #expect(openArray.errors.map(\.code) == [.closeBracketExpected])
        #expect(openArray.jsonValue == .object(["a": .array([1, 2]), "b": 3]))
    }

    @Test func topLevelProblems() {
        #expect(JSONCDocument("{} {}").errors.map(\.code) == [.endOfFileExpected])
        #expect(JSONCDocument("}").errors.map(\.code) == [.valueExpected])
        #expect(JSONCDocument("[1, 2]").root?.kind == .array)
        #expect(JSONCDocument("{\"a\": 1e999}").errors.map(\.code) == [.numberOutOfRange])
        #expect(JSONCDocument("{} /* open").errors.map(\.code) == [.unterminatedComment])
    }

    @Test func duplicateKeysKeepEveryPropertyAndTheLastWins() {
        let document = JSONCDocument(#"{"a": 1, "b": 2, "a": 3}"#)
        #expect(document.root?.properties.map(\.key) == ["a", "b", "a"])
        #expect(document.jsonValue == .object(["a": 3, "b": 2]))
        #expect(document.root?.lastProperty(named: "a")?.value?.scalarValue == 3)
    }

    @Test func deepNestingDoesNotOverflow() {
        let text = String(repeating: "[", count: 20_000) + String(repeating: "]", count: 20_000)
        let document = JSONCDocument(text)
        #expect(document.errors.map(\.code).contains(.tooDeeplyNested))
    }

    @Test func lineAndColumn() {
        let document = JSONCDocument("{\r\n  \"a\": 1,\n\t\"b\"\n}")
        #expect(document.lineStarts == [0, 3, 13, 18])
        #expect(document.lineAndColumn(at: 0) == (1, 1))
        #expect(document.lineAndColumn(at: 5) == (2, 3))
        #expect(document.lineAndColumn(at: 14) == (3, 2))
        #expect(document.indentation(ofLineAt: 14) == "\t")
        // Lines inside block comments count too.
        #expect(JSONCDocument("/* a\nb\r\nc */ {}").lineStarts == [0, 5, 8])
    }

    @Test func highlightsTellKeysFromStrings() {
        let text = #"{"a": "b", "c": [1, true, null], // x"# + "\n}"
        let roles = JSONCDocument(text).highlights().map(\.role)
        #expect(roles == [
            .punctuation, .propertyKey, .punctuation, .string, .punctuation,
            .propertyKey, .punctuation, .punctuation, .number, .punctuation, .boolean, .punctuation, .null, .punctuation,
            .punctuation, .comment, .punctuation,
        ])
    }

    @Test func largeFilesParseQuickly() {
        var lines = ["{"]
        for index in 0..<4000 {
            lines.append("    // comment \(index)")
            lines.append("    \"section\(index).key\": {\"value\": [\(index), \"text \(index)\", true]},")
        }
        lines.append("}")
        let text = lines.joined(separator: "\n")
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let document = JSONCDocument(text)
            #expect(document.errors.isEmpty)
            #expect(document.root?.properties.count == 4000)
        }
        #expect(elapsed < .seconds(1))
    }
}

@Suite("JSONC cursor locations")
struct JSONCLocationTests {
    private func location(_ marked: String) -> (JSONCLocation, String) {
        let (text, offset) = cursor(marked)
        return (JSONCDocument(text).location(at: offset), text)
    }

    @Test func keyPositions() {
        let (empty, _) = location("{\n  |\n}")
        #expect(empty.kind == .propertyKey)
        #expect(empty.path == [])
        #expect(empty.prefix == "")
        #expect(!empty.needsCommaAfter)
        #expect(empty.missingCommaOffset == nil)

        let (typing, text) = location("{\n  \"a\": 1,\n  \"ch|\n}")
        #expect(typing.kind == .propertyKey)
        #expect(typing.prefix == "ch")
        #expect(typing.isInsideQuotes)
        #expect(typing.replaceRange == range(of: "\"ch", in: text))
        #expect(typing.siblingKeys == ["a"])
        #expect(!typing.hasColon)

        let (existing, _) = location("{\"chat.fo|ntSize\": 13}")
        #expect(existing.kind == .propertyKey)
        #expect(existing.prefix == "chat.fo")
        #expect(existing.hasColon)
        #expect(existing.siblingKeys.isEmpty)

        let (bare, bareText) = location("{\n  \"a\": 1,\n  cha|\n}")
        #expect(bare.kind == .propertyKey)
        #expect(bare.prefix == "cha")
        #expect(!bare.isInsideQuotes)
        #expect(bare.replaceRange == range(of: "cha", in: bareText))

        let (middle, _) = location("{\n  \"a\": 1,\n  |\n  \"b\": 2\n}")
        #expect(middle.kind == .propertyKey)
        #expect(middle.needsCommaAfter)
        #expect(middle.siblingKeys == ["a", "b"])

        let (afterNoComma, text2) = location("{\n  \"a\": 1\n  |\n}")
        #expect(afterNoComma.kind == .propertyKey)
        #expect(afterNoComma.missingCommaOffset == range(of: "1", in: text2).endOffset)
    }

    @Test func valuePositions() {
        let (empty, _) = location("{\"chat.layout\": |}")
        #expect(empty.kind == .propertyValue)
        #expect(empty.path == ["chat.layout"])
        #expect(empty.replaceRange.length == 0)

        let (quoted, text) = location("{\"chat.layout\": \"gr|ouped\"}")
        #expect(quoted.kind == .propertyValue)
        #expect(quoted.prefix == "gr")
        #expect(quoted.isInsideQuotes)
        #expect(quoted.replaceRange == range(of: "\"grouped\"", in: text))

        let (literal, _) = location("{\"chat.colorNicks\": tr|}")
        #expect(literal.kind == .propertyValue)
        #expect(literal.prefix == "tr")
        #expect(!literal.isInsideQuotes)

        let (missing, _) = location("{\n  \"chat.layout\": |\n  \"b\": 2\n}")
        #expect(missing.kind == .propertyValue)
        #expect(missing.path == ["chat.layout"])
        #expect(missing.needsCommaAfter)

        let (before, beforeText) = location("{\"chat.fontSize\": |13}")
        #expect(before.kind == .propertyValue)
        #expect(before.replaceRange == range(of: "13", in: beforeText))
    }

    @Test func nestedPositions() {
        let (nestedKey, _) = location("{\"media.siteRules\": {\"example.com\": \"block\", \"|\"}}")
        #expect(nestedKey.kind == .propertyKey)
        #expect(nestedKey.path == ["media.siteRules"])
        #expect(nestedKey.siblingKeys == ["example.com"])

        let (nestedValue, _) = location("{\"media.siteRules\": {\"example.com\": \"bl|\"}}")
        #expect(nestedValue.kind == .propertyValue)
        #expect(nestedValue.path == ["media.siteRules", "example.com"])
        #expect(nestedValue.prefix == "bl")

        let (scope, _) = location("{\"appearance.colorCustomizations\": {\"[Palenight]\": {\n  |\n}}}")
        #expect(scope.kind == .propertyKey)
        #expect(scope.path == ["appearance.colorCustomizations", "[Palenight]"])

        let (element, _) = location("{\"highlight.words\": [\"vela\", \"re|\"]}")
        #expect(element.kind == .arrayElement)
        #expect(element.path == ["highlight.words"])
        #expect(element.prefix == "re")
    }

    @Test func nothingInCommentsOrOutside() {
        #expect(location("{\n  // a co|mment\n}").0.kind == .none)
        #expect(location("{\n  /* a | */\n}").0.kind == .none)
        #expect(location("{}|").0.kind == .none)
        #expect(location("|{}").0.kind == .none)
        #expect(location("// only |").0.kind == .none)
        // Right after a block comment is fine.
        #expect(location("{ /* x */| }").0.kind == .propertyKey)
        // After a string's closing quote is not inside it.
        let (after, _) = location("{\"a\": \"b\"|}")
        #expect(after.kind == .propertyKey)
        #expect(!after.isInsideQuotes)
    }

    @Test func unclosedRootStillCompletes() {
        let (open, _) = location("{\n  \"a\": 1,\n  |")
        #expect(open.kind == .propertyKey)
        #expect(open.siblingKeys == ["a"])
    }
}
