// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaFoundation

/// A small seeded random number generator, so failures reproduce.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("JSONC robustness")
struct JSONCRobustnessTests {
    static let fixture = """
        // header comment
        {
          /* block */ "chat.fontSize": 14, // trailing
          "appearance.colorCustomizations": {
            "chat.background": "#000",
            "[Palenight]": { "accent": "#f80", },
          },
          "highlight.words": ["a", "b"],
          "media.siteRules": {
            // never
            "x.com": "block"
          },
          "escape": "a\\"b 😀"
        }

        """

    /// Every intermediate state of typing the fixture from scratch: the
    /// parser, cursor locations and highlights must cope with all of them.
    @Test func everyPrefixWhileTyping() {
        let units = Array(Self.fixture.utf16)
        for length in 0...units.count {
            let text = String(decoding: units[0..<length], as: UTF16.self)
            check(JSONCDocument(text))
        }
    }

    @Test func randomMutations() {
        var random = SplitMix64(state: 42)
        let alphabet = Array("{}[]:,\"/*\\ \n\tatrufelsn0123456789-.é😀")
        for _ in 0..<400 {
            var characters = Array(Self.fixture)
            for _ in 0..<Int.random(in: 1...4, using: &random) {
                let index = Int.random(in: 0..<characters.count, using: &random)
                switch Int.random(in: 0..<3, using: &random) {
                case 0: characters.remove(at: index)
                case 1: characters.insert(alphabet.randomElement(using: &random)!, at: index)
                default: characters[index] = alphabet.randomElement(using: &random)!
                }
            }
            let text = String(characters)
            let document = JSONCDocument(text)
            check(document)
            // Edits either refuse or leave the value in place.
            for path in [["chat.fontSize"], ["appearance.colorCustomizations", "[Palenight]", "fg"], ["new.key"]] {
                guard let edited = try? JSONCEditing.setting(.string("v"), at: path, in: text) else { continue }
                if document.errors.isEmpty {
                    let result = JSONCDocument(edited)
                    #expect(result.errors.isEmpty, "\(text)\n→\n\(edited)")
                    #expect(result.root?.node(at: path)?.jsonValue == .string("v"), "\(text)\n→\n\(edited)")
                }
                _ = try? JSONCEditing.setting(nil, at: path, in: text)
            }
        }
    }

    private func check(_ document: JSONCDocument) {
        let length = document.length
        var previous = -1
        for error in document.errors {
            #expect(error.range.location >= previous)
            #expect(error.range.location + error.range.length <= length)
            previous = error.range.location
        }
        for highlight in document.highlights() {
            #expect(highlight.range.location + highlight.range.length <= length)
        }
        if document.errors.isEmpty, !document.text.isEmpty {
            #expect((try? JSONC.value(from: Data(document.text.utf8))) == document.jsonValue ?? .object([:]) || document.root == nil)
        }
        for offset in 0...length {
            let location = document.location(at: offset)
            let range = location.replaceRange
            #expect(range.location >= 0 && range.location + range.length <= length)
        }
    }

    // MARK: Edit fuzzing

    static let paths: [[String]] = [
        ["a"], ["b"], ["chat.fontSize"], ["d.e"],
        ["obj", "x"], ["obj", "y"], ["obj", "[Scope]", "accent"], ["obj", "[Scope]", "fg"], ["obj"],
    ]
    static let values: [JSONValue] = [
        1, 2.5, -3, "s", "q\"uote", true, false, .null,
        .array([1, "x"]), .array([]), .object(["k": 1]), .object([:]), .object(["n": .object(["m": .array([true])])]),
    ]
    static let starts = [
        "// header\n{\n  // lead\n  \"a\": 1, // a\n  \"obj\": {\n    \"x\": 1 // x\n  }\n}\n",
        "{\r\n\t\"a\": 1,\r\n\t\"obj\": {\r\n\t\t\"x\": 1,\r\n\t},\r\n}\r\n",
        "{\"a\": 1, \"obj\": {\"x\": 1}}",
        "",
        "// only a comment\n",
        "{}",
    ]

    @Test(arguments: 0..<6)
    func randomEditSequencesStayValid(_ startIndex: Int) {
        var random = SplitMix64(state: UInt64(startIndex) &* 7919 &+ 1)
        var text = Self.starts[startIndex]
        var model = JSONCDocument(text).jsonValue ?? .object([:])
        let header = text.hasPrefix("//") ? String(text.prefix { $0 != "\n" && $0 != "\r" }) : nil
        for step in 0..<250 {
            let path = Self.paths.randomElement(using: &random)!
            let value: JSONValue? = Int.random(in: 0..<10, using: &random) < 6 ? Self.values.randomElement(using: &random)! : nil
            let before = text
            do {
                text = try JSONCEditing.setting(value, at: path, in: text)
            } catch {
                Issue.record("step \(step): \(error) for \(path) in\n\(before)")
                return
            }
            model = Self.apply(value, at: path, to: model)
            let document = JSONCDocument(text)
            #expect(document.errors.isEmpty, "step \(step) \(path) = \(String(describing: value))\n\(before)\n→\n\(text)")
            #expect((document.jsonValue ?? .object([:])) == model, "step \(step) \(path) = \(String(describing: value))\n\(before)\n→\n\(text)")
            if let header { #expect(text.hasPrefix(header)) }
            if document.errors.isEmpty == false || (document.jsonValue ?? .object([:])) != model { return }
        }
    }

    /// What setting or removing `value` at `path` does to a plain value.
    static func apply(_ value: JSONValue?, at path: [String], to root: JSONValue) -> JSONValue {
        guard let key = path.first else { return value ?? root }
        guard case .object(var object) = root else {
            // Removing below a non-object changes nothing; setting replaces it.
            guard let value else { return root }
            return apply(value, at: path, to: .object([:]))
        }
        if path.count == 1 {
            object[key] = value
        } else if let child = object[key] {
            if value == nil, child.objectValue == nil { return root }
            object[key] = apply(value, at: Array(path.dropFirst()), to: child)
        } else if let value {
            object[key] = apply(value, at: Array(path.dropFirst()), to: .object([:]))
        }
        return .object(object)
    }
}
