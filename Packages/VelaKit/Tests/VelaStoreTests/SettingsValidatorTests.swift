// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

/// The UTF-16 range of the `occurrence`-th match of `needle` in `text`.
func utf16Range(of needle: String, in text: String, occurrence: Int = 1) -> NSRange {
    let ns = text as NSString
    var start = 0
    var found = NSRange(location: NSNotFound, length: 0)
    for _ in 0..<occurrence {
        found = ns.range(of: needle, range: NSRange(location: start, length: ns.length - start))
        precondition(found.location != NSNotFound, "\(needle) not found")
        start = found.location + found.length
    }
    return found
}

@Suite struct SettingsValidatorTests {
    private func only(_ text: String, extraChecks: [String: (JSONValue) -> [String]] = [:]) throws -> SettingsDiagnostic {
        let diagnostics = SettingsValidator.diagnostics(for: text, extraChecks: extraChecks)
        #expect(diagnostics.count == 1, "\(diagnostics)")
        return try #require(diagnostics.first)
    }

    @Test func validSettingsHaveNoProblems() {
        let text = """
            // Comments and trailing commas are fine.
            {
              "$schema": "./settings.schema.json",
              "chat.fontSize": 14,
              "chat.layout": "columns",
              "chat.scrollbackInMemory": 5000,
              "input.autocorrect": "system",
              "input.smartPunctuation": false,
              "highlight.words": ["vela"],
              "media.siteRules": {"example.com": "textOnly"},
              "appearance.colorCustomizations": {"[Palenight]": {"accent": "#ff8800"}},
              "history.retentionDays": 30,
            }
            """
        #expect(SettingsValidator.diagnostics(for: text).isEmpty)
        #expect(SettingsValidator.diagnostics(for: SettingsCatalog.defaultSettingsDocument()).isEmpty)
        #expect(SettingsValidator.diagnostics(for: "").isEmpty)
        #expect(SettingsValidator.diagnostics(for: "// nothing\n").isEmpty)
    }

    @Test func syntaxErrors() throws {
        let text = "{\n  \"chat.fontSize\": 14\n  \"chat.layout\": \"classic\"\n}"
        let diagnostic = try only(text)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.kind == .syntax(.commaExpected))
        #expect(diagnostic.message == "Expected a comma.")
        #expect(diagnostic.range == utf16Range(of: "\"chat.layout\"", in: text))
    }

    @Test func problemsAtTheEndCoverTheLastToken() throws {
        let text = "{\n  \"chat.fontSize\": 14,\n"
        let diagnostic = try only(text)
        #expect(diagnostic.kind == .syntax(.closeBraceExpected))
        #expect(diagnostic.range == utf16Range(of: ",", in: text))

        let missingValue = try only("{\"chat.fontSize\": }")
        #expect(missingValue.kind == .syntax(.valueExpected))
        #expect(missingValue.range == NSRange(location: 16, length: 1))  // the colon
    }

    @Test func topLevelMustBeAnObject() throws {
        let diagnostic = try only("[1, 2]")
        #expect(diagnostic.kind == .notAnObject)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.range == NSRange(location: 0, length: 6))
    }

    @Test func duplicateKeys() throws {
        let text = #"{"chat.fontSize": 12, "chat.layout": "grouped", "chat.fontSize": 14}"#
        let diagnostic = try only(text)
        #expect(diagnostic.kind == .duplicateKey)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.key == "chat.fontSize")
        #expect(diagnostic.range == utf16Range(of: "\"chat.fontSize\"", in: text))
    }

    @Test func unknownKeysSuggestWhatWasMeant() throws {
        let cases: [(typed: String, suggestion: String?)] = [
            ("chat.fontsize", "chat.fontSize"),    // case
            ("chat.fontSise", "chat.fontSize"),    // typo
            ("chat.fnotSize", "chat.fontSize"),    // transposition
            ("fontSize", "chat.fontSize"),         // missing group
            ("chat.colourNicks", "chat.colorNicks"),
            ("totally.unrelated", nil),
        ]
        for (typed, suggestion) in cases {
            let text = "{\"\(typed)\": 1}"
            let diagnostic = try only(text)
            #expect(diagnostic.kind == .unknownKey, "\(typed)")
            #expect(diagnostic.severity == .warning)
            #expect(diagnostic.suggestedKey == suggestion, "\(typed)")
            #expect(diagnostic.range == utf16Range(of: "\"\(typed)\"", in: text))
            if let suggestion {
                #expect(diagnostic.message == "Unknown setting. Did you mean “\(suggestion)”?")
            } else {
                #expect(diagnostic.message == "Unknown setting.")
            }
        }
        #expect(SettingsValidator.suggestion(forUnknownKey: "chat.fontSize") == nil)
    }

    @Test func legacyKeysAreInfo() throws {
        let diagnostic = try only(#"{"media.blockedDomains": ["a.com"]}"#)
        #expect(diagnostic.kind == .legacyKey)
        #expect(diagnostic.severity == .info)
        #expect(diagnostic.message.contains("media.siteRules"))
    }

    @Test func typeMismatches() throws {
        let cases: [(json: String, value: String, message: String)] = [
            (#"{"chat.showTimestamps": "false"}"#, #""false""#, "Expected true or false."),
            (#"{"chat.fontFamily": 12}"#, "12", "Expected a string."),
            (#"{"chat.fontSize": "13"}"#, #""13""#, "Expected a number."),
            (#"{"history.retentionDays": 1.5}"#, "1.5", "Expected a whole number."),
            (#"{"highlight.words": "vela"}"#, #""vela""#, "Expected an array."),
            (#"{"media.siteRules": ["a.com"]}"#, #"["a.com"]"#, "Expected an object."),
        ]
        for (json, value, message) in cases {
            let diagnostic = try only(json)
            #expect(diagnostic.kind == .typeMismatch, "\(json)")
            #expect(diagnostic.severity == .error)
            #expect(diagnostic.message == message, "\(json)")
            #expect(diagnostic.range == utf16Range(of: value, in: json), "\(json)")
        }
    }

    @Test func enumValues() throws {
        let text = #"{"chat.layout": "cozy"}"#
        let diagnostic = try only(text)
        #expect(diagnostic.kind == .valueNotAllowed)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Value is not accepted. Valid values: “classic”, “grouped”, “columns”.")
        #expect(diagnostic.key == "chat.layout")
        #expect(diagnostic.range == utf16Range(of: "\"cozy\"", in: text))
    }

    @Test func numbersOutOfRange() throws {
        let diagnostic = try only(#"{"chat.fontSize": 100}"#)
        #expect(diagnostic.kind == .outOfRange)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.message == "Value must be between 9 and 28.")
        #expect(try only(#"{"tabs.roundness": 1.5}"#).message == "Value must be between 0 and 1.")
        #expect(SettingsValidator.diagnostics(for: #"{"chat.fontSize": 28, "tabs.roundness": 0.35}"#).isEmpty)
    }

    @Test func settingsThatFollowMacOS() throws {
        for good in ["true", "false", "\"system\""] {
            #expect(SettingsValidator.diagnostics(for: "{\"input.autocorrect\": \(good)}").isEmpty, "\(good)")
        }
        for bad in ["\"on\"", "1", "null"] {
            let diagnostic = try only("{\"input.autocorrect\": \(bad)}")
            #expect(diagnostic.kind == .typeMismatch)
            #expect(diagnostic.message == "Expected true, false or \"system\".")
        }
    }

    @Test func siteRuleValues() {
        let text = #"{"media.siteRules": {"a.com": "maybe", "b.com": 3, "c.com": "allow"}}"#
        let diagnostics = SettingsValidator.diagnostics(for: text)
        #expect(diagnostics.map(\.kind) == [.valueNotAllowed, .typeMismatch])
        #expect(diagnostics.map(\.range) == [utf16Range(of: "\"maybe\"", in: text), utf16Range(of: "3", in: text)])
        #expect(diagnostics.first?.message == "Value is not accepted. Valid values: “allow”, “textOnly”, “block”.")
        #expect(diagnostics.allSatisfy { $0.key == "media.siteRules" })
    }

    @Test func arrayElementsOfTheWrongType() {
        let text = #"{"highlight.words": ["ok", 42, true]}"#
        let diagnostics = SettingsValidator.diagnostics(for: text)
        #expect(diagnostics.map(\.message) == ["Expected a string.", "Expected a string."])
        #expect(diagnostics.map(\.range) == [utf16Range(of: "42", in: text), utf16Range(of: "true", in: text)])
    }

    @Test func extraChecksAreAnchoredToTheValue() throws {
        let text = ##"{"appearance.colorCustomizations": {"nope": "#12"}, "chat.fontSize": 13}"##
        var seen: JSONValue?
        let diagnostics = SettingsValidator.diagnostics(for: text, extraChecks: [
            "appearance.colorCustomizations": { value in
                seen = value
                return ["“nope” is not a theme token.", "“#12” is not a color."]
            },
            "chat.fontSize": { _ in [] },
        ])
        #expect(seen == .object(["nope": "#12"]))
        #expect(diagnostics.map(\.kind) == [.extraCheck, .extraCheck])
        #expect(diagnostics.allSatisfy { $0.severity == .warning && $0.key == "appearance.colorCustomizations" })
        #expect(diagnostics.first?.range == utf16Range(of: ##"{"nope": "#12"}"##, in: text))
    }

    @Test func extraChecksSkipValuesOfTheWrongTypeAndRunForAnyKey() throws {
        var calls = 0
        let checks: [String: (JSONValue) -> [String]] = [
            "appearance.colorCustomizations": { _ in calls += 1; return ["nope"] },
            "made.up": { _ in calls += 1; return ["custom"] },
        ]
        let wrongType = try only(#"{"appearance.colorCustomizations": [1]}"#, extraChecks: checks)
        #expect(wrongType.kind == .typeMismatch)
        #expect(calls == 0)
        let unknown = SettingsValidator.diagnostics(for: #"{"made.up": 1}"#, extraChecks: checks)
        #expect(unknown.map(\.kind) == [.unknownKey, .extraCheck])
        #expect(calls == 1)
    }

    @Test func brokenValuesOnlyReportTheSyntaxError() throws {
        let diagnostic = try only(#"{"chat.layout": classic}"#)
        #expect(diagnostic.kind == .syntax(.invalidValue))
    }

    @Test func diagnosticsAreSortedByPosition() {
        let text = """
            {
              "zzz.unknown": 1,
              "chat.layout": "cozy",
              "chat.fontSize": 99,
              "chat.fontSize": 12
            """
        let diagnostics = SettingsValidator.diagnostics(for: text)
        #expect(diagnostics.map(\.kind) == [.unknownKey, .valueNotAllowed, .duplicateKey, .syntax(.closeBraceExpected)])
        let locations = diagnostics.map(\.range.location)
        #expect(locations == locations.sorted())
    }

    @Test func editDistance() {
        #expect(SettingsValidator.editDistance("kitten", "sitting") == 3)
        #expect(SettingsValidator.editDistance("ab", "ba") == 1)
        #expect(SettingsValidator.editDistance("", "abc") == 3)
        #expect(SettingsValidator.editDistance("same", "same") == 0)
    }
}
