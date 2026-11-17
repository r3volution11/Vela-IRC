// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaFoundation

@Suite("JSONC editing")
struct JSONCEditingTests {
    private func set(_ value: JSONValue?, _ path: [String], in text: String) throws -> String {
        let result = try JSONCEditing.setting(value, at: path, in: text)
        // Every edit leaves valid JSONC with the intended value.
        let document = JSONCDocument(result)
        #expect(document.errors.isEmpty, "\(result)")
        if let value {
            #expect(document.root?.node(at: path)?.jsonValue == value, "\(result)")
        } else {
            #expect(document.root?.property(at: path) == nil, "\(result)")
        }
        return result
    }

    // MARK: Inserting

    @Test func insertIntoEmptyDocuments() throws {
        #expect(try set(1, ["a"], in: "") == "{\n    \"a\": 1\n}\n")
        #expect(try set(1, ["a"], in: "  \n") == "{\n    \"a\": 1\n}\n")
        #expect(try set(1, ["a"], in: "// my settings\n") == "// my settings\n{\n    \"a\": 1\n}\n")
        #expect(try set(1, ["a"], in: "// my settings") == "// my settings\n{\n    \"a\": 1\n}\n")
        #expect(try set("x", ["a", "b"], in: "") == "{\n    \"a\": {\n        \"b\": \"x\"\n    }\n}\n")
    }

    @Test func insertIntoEmptyObjects() throws {
        #expect(try set(1, ["a"], in: "{}") == "{\n    \"a\": 1\n}")
        #expect(try set(1, ["a"], in: "{ }\n") == "{\n    \"a\": 1\n}\n")
        #expect(try set(1, ["a"], in: "{\n}\n") == "{\n    \"a\": 1\n}\n")
        // Comments inside are kept; the property goes after them, lined up.
        #expect(try set(1, ["a"], in: "{\n  // nothing yet\n}\n") == "{\n  // nothing yet\n  \"a\": 1\n}\n")
        #expect(try set(1, ["a"], in: "{ /* empty */ }") == "{ /* empty */\n    \"a\": 1\n}")
        // A nested empty object opens up at its indentation.
        let nested = "{\n  \"media.siteRules\": {},\n  \"b\": 1\n}"
        #expect(try set("block", ["media.siteRules", "example.com"], in: nested)
            == "{\n  \"media.siteRules\": {\n    \"example.com\": \"block\"\n  },\n  \"b\": 1\n}")
    }

    @Test func insertIntoOneLineObjects() throws {
        #expect(try set(2, ["b"], in: #"{"a": 1}"#) == #"{"a": 1, "b": 2}"#)
        #expect(try set(2, ["b"], in: #"{"a": 1,}"#) == #"{"a": 1, "b": 2,}"#)
        #expect(try set(.array([1, 2]), ["b", "y"], in: #"{"a": 1, "b": {"x": 1}}"#) == #"{"a": 1, "b": {"x": 1, "y": [1, 2]}}"#)
    }

    @Test func insertIntoMultiLineObjectWithComments() throws {
        let text = """
            {
              // comment
              "a": 1, // about a
              "b": "two" // about b
            }

            """
        #expect(try set(true, ["c"], in: text) == """
            {
              // comment
              "a": 1, // about a
              "b": "two", // about b
              "c": true
            }

            """)
    }

    @Test func insertAfterTrailingComma() throws {
        let text = "{\n  \"a\": 1,\n  \"b\": 2,\n}\n"
        #expect(try set(3, ["c"], in: text) == "{\n  \"a\": 1,\n  \"b\": 2,\n  \"c\": 3,\n}\n")
    }

    @Test func insertBeforeCommentsThatFollowTheLastProperty() throws {
        let text = """
            {
              "a": 1,
              // "b": 2,
              /* trailing block */
            }
            """
        #expect(try set(3, ["c"], in: text) == """
            {
              "a": 1,
              "c": 3,
              // "b": 2,
              /* trailing block */
            }
            """)
    }

    @Test func insertWhenTheBraceSharesTheLastLine() throws {
        #expect(try set(2, ["b"], in: "{\n  \"a\": 1}") == "{\n  \"a\": 1,\n  \"b\": 2\n}")
    }

    @Test func insertWithTabsAndPrettyPrintedValues() throws {
        let text = "{\n\t\"a\": 1\n}"
        #expect(try set(.object(["x": .array([1]), "w": "z"]), ["b"], in: text)
            == "{\n\t\"a\": 1,\n\t\"b\": {\n\t\t\"w\": \"z\",\n\t\t\"x\": [\n\t\t\t1\n\t\t]\n\t}\n}")
    }

    @Test func insertWithCRLF() throws {
        #expect(try set(2, ["b"], in: "{\r\n  \"a\": 1\r\n}\r\n") == "{\r\n  \"a\": 1,\r\n  \"b\": 2\r\n}\r\n")
        #expect(try set(1, ["a"], in: "// x\r\n{\r\n}\r\n") == "// x\r\n{\r\n    \"a\": 1\r\n}\r\n")
    }

    @Test func keepsTheSpaceBeforeColonStyle() throws {
        // How Vela wrote settings.json before edits were minimal.
        let old = "{\n  \"a\" : 1,\n  \"b\" : [\n    \"x\"\n  ]\n}\n"
        #expect(try set(.object(["k": 1]), ["c"], in: old) == "{\n  \"a\" : 1,\n  \"b\" : [\n    \"x\"\n  ],\n  \"c\" : {\n    \"k\" : 1\n  }\n}\n")
    }

    @Test func trailingCommaStyleAppliesToNewObjects() throws {
        let text = "{\n  \"a\": {\n    \"x\": 1,\n  },\n}\n"
        #expect(try set(.object(["k": 1, "l": 2]), ["b"], in: text)
            == "{\n  \"a\": {\n    \"x\": 1,\n  },\n  \"b\": {\n    \"k\": 1,\n    \"l\": 2,\n  },\n}\n")
    }

    @Test func nestedInsertCreatesMissingObjects() throws {
        let text = """
            {
              "appearance.colorCustomizations": {
                "chat.background": "#000000", // darker
                "[Palenight]": {
                  "accent": "#ff8800" // orange
                }
              }
            }
            """
        #expect(try set("#ffffff", ["appearance.colorCustomizations", "[Palenight]", "chat.foreground"], in: text) == """
            {
              "appearance.colorCustomizations": {
                "chat.background": "#000000", // darker
                "[Palenight]": {
                  "accent": "#ff8800", // orange
                  "chat.foreground": "#ffffff"
                }
              }
            }
            """)
        #expect(try set("#123456", ["appearance.colorCustomizations", "[Lighter]", "accent"], in: text) == """
            {
              "appearance.colorCustomizations": {
                "chat.background": "#000000", // darker
                "[Palenight]": {
                  "accent": "#ff8800" // orange
                },
                "[Lighter]": {
                  "accent": "#123456"
                }
              }
            }
            """)
        #expect(try set("block", ["media.siteRules", "example.com"], in: text) == """
            {
              "appearance.colorCustomizations": {
                "chat.background": "#000000", // darker
                "[Palenight]": {
                  "accent": "#ff8800" // orange
                }
              },
              "media.siteRules": {
                "example.com": "block"
              }
            }
            """)
    }

    // MARK: Replacing

    @Test func replaceTouchesOnlyTheValue() throws {
        let text = "{\n  \"a\": 1, // note\n  \"b\": \"x\"\n}"
        let edits = try JSONCEditing.edits(setting: 5, at: ["a"], in: text)
        #expect(edits == [JSONCEdit(range: range(of: "1", in: text), replacement: "5")])
        #expect(try set("y", ["b"], in: text) == "{\n  \"a\": 1, // note\n  \"b\": \"y\"\n}")
        #expect(try JSONCEditing.edits(setting: 1, at: ["a"], in: text).isEmpty)
        // An equal value written differently, comments inside included, is left alone.
        let commented = "{\n  \"o\": { // c\n    \"x\": 1.0\n  }\n}"
        #expect(try JSONCEditing.edits(setting: .object(["x": 1]), at: ["o"], in: commented).isEmpty)
    }

    @Test func replaceWithObjectIsPrettyPrintedAtThePropertysIndentation() throws {
        let text = "{\n    \"a\": 1, // note\n    \"b\": 2\n}"
        #expect(try set(.object(["x": 1, "y": "z"]), ["a"], in: text)
            == "{\n    \"a\": {\n        \"x\": 1,\n        \"y\": \"z\"\n    }, // note\n    \"b\": 2\n}")
    }

    @Test func replaceNonObjectOnThePath() throws {
        #expect(try set(1, ["a", "b"], in: #"{"a": 5}"#) == #"{"a": {"b": 1}}"#)
        #expect(try set(1, ["a", "b"], in: "{\n  \"a\": null\n}") == "{\n  \"a\": {\n    \"b\": 1\n  }\n}")
    }

    @Test func numbersAndStringsAreWrittenAsJSON() throws {
        let result = try set(.object(["q\"uote": "back\\slash\nline é 😀", "n": 0.35, "i": 1000, "neg": -2, "big": 1e20]), ["v"], in: "{}")
        #expect(result.contains(#""q\"uote": "back\\slash\nline é 😀""#))
        #expect(result.contains(#""n": 0.35"#))
        #expect(result.contains(#""i": 1000"#))
        #expect(result.contains(#""neg": -2"#))
        #expect(result.contains(#""big": 1e+20"#))
    }

    // MARK: Removing

    static let removalFixture = """
        {
          // Leading comment for a
          "a": 1, // about a
          "b": 2, /* about b */
          // Leading comment for c
          "c": 3 // about c
        }

        """

    @Test func removeFirstMiddleAndLast() throws {
        let text = Self.removalFixture
        #expect(try set(nil, ["a"], in: text) == """
            {
              // Leading comment for a
              "b": 2, /* about b */
              // Leading comment for c
              "c": 3 // about c
            }

            """)
        #expect(try set(nil, ["b"], in: text) == """
            {
              // Leading comment for a
              "a": 1, // about a
              // Leading comment for c
              "c": 3 // about c
            }

            """)
        #expect(try set(nil, ["c"], in: text) == """
            {
              // Leading comment for a
              "a": 1, // about a
              "b": 2 /* about b */
              // Leading comment for c
            }

            """)
        var all = text
        for key in ["b", "a", "c"] { all = try set(nil, [key], in: all) }
        #expect(all == "{\n  // Leading comment for a\n  // Leading comment for c\n}\n")
    }

    @Test func removeFromOneLineObjects() throws {
        let text = #"{"a": 1, "b": 2, "c": 3}"#
        #expect(try set(nil, ["a"], in: text) == #"{"b": 2, "c": 3}"#)
        #expect(try set(nil, ["b"], in: text) == #"{"a": 1, "c": 3}"#)
        #expect(try set(nil, ["c"], in: text) == #"{"a": 1, "b": 2}"#)
        #expect(try set(nil, ["a"], in: #"{ "a": 1 }"#) == "{}")
        #expect(try set(nil, ["b"], in: "{\n  \"a\": 1, \"b\": 2\n}") == "{\n  \"a\": 1\n}")
        #expect(try set(nil, ["a"], in: "{\n  \"a\": 1, \"b\": 2\n}") == "{\n  \"b\": 2\n}")
    }

    @Test func removeTheOnlyProperty() throws {
        #expect(try set(nil, ["a"], in: "{\n  \"a\": 1\n}\n") == "{\n}\n")
        #expect(try set(nil, ["a"], in: "{\n  \"a\": 1,\n}") == "{\n}")
    }

    @Test func removeMultiLineValue() throws {
        let text = "{\n  \"a\": {\n    \"x\": 1\n  },\n  \"b\": 2\n}"
        #expect(try set(nil, ["a"], in: text) == "{\n  \"b\": 2\n}")
        #expect(try set(nil, ["b"], in: text) == "{\n  \"a\": {\n    \"x\": 1\n  }\n}")
    }

    @Test func removeNested() throws {
        let text = """
            {
              "appearance.colorCustomizations": {
                "chat.background": "#000000", // darker
                "[Palenight]": {
                  "accent": "#ff8800" // orange
                }
              }
            }
            """
        #expect(try set(nil, ["appearance.colorCustomizations", "[Palenight]", "accent"], in: text) == """
            {
              "appearance.colorCustomizations": {
                "chat.background": "#000000", // darker
                "[Palenight]": {
                }
              }
            }
            """)
        #expect(try set(nil, ["appearance.colorCustomizations", "[Palenight]"], in: text) == """
            {
              "appearance.colorCustomizations": {
                "chat.background": "#000000" // darker
              }
            }
            """)
    }

    @Test func removeEveryDuplicate() throws {
        let text = "{\n  \"a\": 1,\n  \"b\": 2,\n  \"a\": 3\n}"
        let edits = try JSONCEditing.edits(setting: nil, at: ["a"], in: text)
        #expect(edits.count == 1)
        #expect(JSONCEdit.apply(edits, to: text) == "{\n  \"b\": 2\n}")
    }

    @Test func removingSomethingMissingChangesNothing() throws {
        #expect(try JSONCEditing.edits(setting: nil, at: ["x"], in: #"{"a": 1}"#).isEmpty)
        #expect(try JSONCEditing.edits(setting: nil, at: ["a", "x"], in: #"{"a": 1}"#).isEmpty)
        #expect(try JSONCEditing.edits(setting: nil, at: ["x"], in: "").isEmpty)
    }

    @Test func removeWithCRLF() throws {
        let text = "{\r\n  \"a\": 1,\r\n  \"b\": 2\r\n}\r\n"
        #expect(try set(nil, ["b"], in: text) == "{\r\n  \"a\": 1\r\n}\r\n")
        #expect(try set(nil, ["a"], in: text) == "{\r\n  \"b\": 2\r\n}\r\n")
    }

    // MARK: Broken text

    @Test func refusesToEditBrokenStructure() {
        #expect(throws: JSONCEditingError.rootIsNotAnObject) { try JSONCEditing.edits(setting: 1, at: ["a"], in: "[1]") }
        #expect(throws: JSONCEditingError.rootIsNotAnObject) { try JSONCEditing.edits(setting: 1, at: ["a"], in: "}") }
        #expect(throws: JSONCEditingError.unclosedObject(path: [])) { try JSONCEditing.edits(setting: 1, at: ["b"], in: #"{"a": 1,"#) }
        #expect(throws: JSONCEditingError.unclosedObject(path: ["a"])) {
            try JSONCEditing.edits(setting: 1, at: ["a", "c"], in: "{\"a\": {\"b\": 1\n")
        }
    }

    @Test func editsWorkDespiteErrorsElsewhere() throws {
        // A broken value in another property doesn't stop an edit.
        let text = "{\n  \"a\": tru,\n  \"b\": 1\n}"
        let result = try JSONCEditing.setting(2, at: ["b"], in: text)
        #expect(result == "{\n  \"a\": tru,\n  \"b\": 2\n}")
    }

    // MARK: Helpers

    @Test func formatDetection() {
        let spaces = JSONCFormat(detectingIn: JSONCDocument("{\n  \"a\": {\n    \"b\": 1\n  }\n}"))
        #expect(spaces.indent == "  ")
        #expect(spaces.lineEnding == "\n")
        #expect(!spaces.trailingCommas)
        let tabs = JSONCFormat(detectingIn: JSONCDocument("{\r\n\t\"a\": 1,\r\n}"))
        #expect(tabs.indent == "\t")
        #expect(tabs.lineEnding == "\r\n")
        #expect(tabs.trailingCommas)
        #expect(JSONCFormat(detectingIn: JSONCDocument("{\"a\": 1}")) == .standard)
        #expect(JSONCFormat(detectingIn: JSONCDocument("{\n  \"a\" : 1\n}")).spaceBeforeColon)
    }

    @Test func applyAndDifference() {
        let text = "abc😀def"
        #expect(JSONCEdit.apply([.insert("X", at: 0), .delete(NSRange(location: 3, length: 2)), .insert("Y", at: 8)], to: text) == "XabcdefY")
        #expect(JSONCEdit.apply([.insert("1", at: 2), .insert("2", at: 2)], to: "ab") == "ab12")
        let edit = JSONCEdit.difference(from: "{\n  \"a\": 1\n}", to: "{\n  \"a\": 22\n}")
        #expect(edit == JSONCEdit(range: NSRange(location: 9, length: 1), replacement: "22"))
        #expect(JSONCEdit.difference(from: "same", to: "same") == nil)
        #expect(JSONCEdit.difference(from: "a😀", to: "a😁").map { JSONCEdit.apply([$0], to: "a😀") } == "a😁")
    }
}
