// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Testing
import VelaCore
import VelaFoundation
import VelaStore
import VelaTheme
@testable import VelaUI

// MARK: - Highlighting

@Suite("Settings JSON view: highlighting")
struct SettingsJSONHighlightingTests {
    private func roles(_ text: String) -> [(String, JSONSyntaxRole)] {
        let ns = text as NSString
        return JSONSyntax.runs(in: text).map { (ns.substring(with: $0.range), $0.role) }
    }

    @Test func tokensMapToRoles() {
        let result = roles("{\n  \"chat.layout\": \"grouped\", // note\n  \"n\": -1.5, \"t\": true, \"z\": null, \"bad\": tru /* c */\n}")
        let expected: [(String, JSONSyntaxRole)] = [
            ("{", .punctuation),
            ("\"chat.layout\"", .propertyKey), (":", .punctuation), ("\"grouped\"", .string), (",", .punctuation),
            ("// note", .comment),
            ("\"n\"", .propertyKey), (":", .punctuation), ("-1.5", .number), (",", .punctuation),
            ("\"t\"", .propertyKey), (":", .punctuation), ("true", .literal), (",", .punctuation),
            ("\"z\"", .propertyKey), (":", .punctuation), ("null", .literal), (",", .punctuation),
            ("\"bad\"", .propertyKey), (":", .punctuation), ("tru", .invalid), ("/* c */", .comment),
            ("}", .punctuation),
        ]
        #expect(result.map(\.0) == expected.map(\.0))
        #expect(result.map(\.1) == expected.map(\.1))
    }

    @Test func halfTypedKeyIsAString() {
        // No colon yet: still a plain string; a key once the colon is typed.
        #expect(roles("{\"chat.fo").last?.1 == .string)
        #expect(roles("{\"chat\" :").first(where: { $0.0 == "\"chat\"" })?.1 == .propertyKey)
        #expect(roles("[\"a\", \"b\"]").filter { $0.1 == .string }.count == 2)
        #expect(roles("{\"n\": 12px}").contains { $0.0 == "12px" && $0.1 == .invalid })
    }

    @Test func rolesUseThemeTokens() {
        #expect(JSONSyntax.colorKey(for: .propertyKey) == ThemeKey.accentText)
        #expect(JSONSyntax.colorKey(for: .string) == ThemeKey.statusSuccess)
        #expect(JSONSyntax.colorKey(for: .number) == ThemeKey.chatNotice)
        #expect(JSONSyntax.colorKey(for: .literal) == ThemeKey.chatAction)
        #expect(JSONSyntax.colorKey(for: .punctuation) == ThemeKey.settingsForeground)
        #expect(JSONSyntax.colorKey(for: .comment) == ThemeKey.settingsSecondaryForeground)
        #expect(JSONSyntax.colorKey(for: .invalid) == ThemeKey.statusError)
        // Every role resolves in the built-in registry.
        for role in JSONSyntaxRole.allCases {
            #expect(ThemeRegistry.token(JSONSyntax.colorKey(for: role)) != nil || JSONSyntax.colorKey(for: role) == ThemeKey.accentText)
        }
    }

    /// Applies `edit` and returns the restyled range.
    private func restyle(_ text: String, _ edit: JSONCEdit) -> (String, NSRange?) {
        let newText = JSONCEdit.apply([edit], to: text)
        let delta = edit.replacement.utf16.count - edit.range.length
        let edited = NSRange(location: edit.range.location, length: edit.replacement.utf16.count)
        let changed = JSONSyntax.changedRange(old: JSONSyntax.runs(in: text), new: JSONSyntax.runs(in: newText), editedRange: edited, delta: delta)
        return (newText, changed)
    }

    @Test func typingInsideAStringRestylesOnlyThatString() {
        let text = "{\n    \"chat.layout\": \"group\",\n    \"chat.fontSize\": 13\n}\n"
        let offset = (text as NSString).range(of: "group").location + 5
        let (newText, changed) = restyle(text, .insert("e", at: offset))
        let string = (newText as NSString).range(of: "\"groupe\"")
        #expect(changed == string)
    }

    @Test func openingACommentRestylesToTheEnd() {
        let text = "{\n    \"a\": 1,\n    \"b\": 2\n}\n"
        let offset = (text as NSString).range(of: "\"a\"").location
        let (newText, changed) = restyle(text, .insert("/*", at: offset))
        let changedEnd = (changed?.location ?? 0) + (changed?.length ?? 0)
        #expect(changed?.location == offset)
        #expect(changedEnd == (newText as NSString).length) // the unterminated comment runs to the end
    }

    @Test func typingAColonTurnsTheStringBeforeIntoAKey() {
        let text = "{\n    \"chat.layout\"\n}"
        let offset = (text as NSString).range(of: "\"chat.layout\"").location + 13
        let (_, changed) = restyle(text, .insert(":", at: offset))
        #expect(changed.map { NSLocationInRange(offset - 1, $0) } == true)
        #expect(changed?.location == offset - 13)
    }

    /// Simulates the layout manager (colors before the edit stay, after it
    /// move by delta, typed text gets whatever) and restyles only the
    /// changed range: every non-whitespace character must end up with the
    /// role a full restyle gives it.
    @Test func incrementalRestylingMatchesAFullRestyle() {
        var generator = SeededGenerator(seed: 42)
        let fragments = ["\"", "{", "}", "[", "]", ":", ",", " ", "\n", "//", "/*", "*/", "1", "-2.5", "true", "nul", "\"k\": ", "ab", "\\", "\r\n"]
        var text = "{\n    \"chat.layout\": \"grouped\", // hi\n    \"n\": [1, 2, true],\n    /* block */ \"x\": null\n}\n"
        var shown = perCharacterRoles(text)
        for _ in 0..<400 {
            let length = (text as NSString).length
            let location = Int.random(in: 0...length, using: &generator)
            let deleteLength = Bool.random(using: &generator) ? 0 : Int.random(in: 0...min(4, length - location), using: &generator)
            let insert = Bool.random(using: &generator) ? fragments.randomElement(using: &generator)! : ""
            let edit = JSONCEdit(range: NSRange(location: location, length: deleteLength), replacement: insert)
            let oldRuns = JSONSyntax.runs(in: text)
            let newText = JSONCEdit.apply([edit], to: text)
            let newRuns = JSONSyntax.runs(in: newText)
            let insertedLength = insert.utf16.count
            let delta = insertedLength - deleteLength
            // What the layout manager shows right after the edit.
            var mapped = Array(shown[..<location])
            mapped += Array(repeating: JSONSyntaxRole?.some(.invalid), count: insertedLength)
            mapped += shown[(location + deleteLength)...]
            let changed = JSONSyntax.changedRange(
                old: oldRuns, new: newRuns,
                editedRange: NSRange(location: location, length: insertedLength), delta: delta
            )
            if let changed {
                for index in changed.location..<(changed.location + changed.length) { mapped[index] = nil }
                for run in newRuns where NSIntersectionRange(run.range, changed).length > 0 {
                    let clipped = NSIntersectionRange(run.range, changed)
                    for index in clipped.location..<(clipped.location + clipped.length) { mapped[index] = run.role }
                }
            }
            let expected = perCharacterRoles(newText)
            let units = Array(newText.utf16)
            for index in units.indices where !isSpace(units[index]) {
                #expect(mapped[index] == expected[index], "after editing \(edit) at \(index) in \(newText.debugDescription)")
                if mapped[index] != expected[index] { return }
            }
            text = newText
            shown = mapped
        }
    }

    private func perCharacterRoles(_ text: String) -> [JSONSyntaxRole?] {
        var roles = [JSONSyntaxRole?](repeating: nil, count: (text as NSString).length)
        for run in JSONSyntax.runs(in: text) {
            for index in run.range.location..<(run.range.location + run.range.length) { roles[index] = run.role }
        }
        return roles
    }

    private func isSpace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xFEFF }
}

// MARK: - Line index

@Suite("Settings JSON view: line numbers")
struct SettingsJSONLineIndexTests {
    @Test func findsLines() {
        let index = JSONLineIndex("a\nbb\r\ncc\rd")
        #expect(index.starts == [0, 2, 6, 9])
        #expect(index.line(containing: 0) == 0)
        #expect(index.line(containing: 3) == 1)
        #expect(index.line(containing: 6) == 2)
        #expect(index.line(containing: 100) == 3)
        #expect(JSONLineIndex("x\n").starts == [0, 2])
    }

    @Test func staysCorrectAcrossRandomEdits() {
        var generator = SeededGenerator(seed: 7)
        let pieces = ["\n", "\r", "\r\n", "a", "bc", "\n\n", " ", ""]
        var text = "{\n  \"a\": 1,\r\n  \"b\": 2\r}\n"
        var index = JSONLineIndex(text)
        for _ in 0..<500 {
            let length = (text as NSString).length
            let location = Int.random(in: 0...length, using: &generator)
            let deleteLength = Int.random(in: 0...min(3, length - location), using: &generator)
            let insert = pieces.randomElement(using: &generator)!
            let edit = JSONCEdit(range: NSRange(location: location, length: deleteLength), replacement: insert)
            text = JSONCEdit.apply([edit], to: text)
            index.update(
                editedRange: NSRange(location: location, length: insert.utf16.count),
                delta: insert.utf16.count - deleteLength,
                in: text as NSString
            )
            #expect(index == JSONLineIndex(text), "after \(edit) → \(text.debugDescription)")
            if index != JSONLineIndex(text) { return }
        }
    }
}

// MARK: - Dirty, save and reload

@Suite("Settings JSON view: saving and external changes")
struct SettingsJSONBufferTests {
    @Test func editsMakeTheBufferDirty() {
        let model = JSONBufferModel(diskText: "{}", revision: 0)
        #expect(!model.isDirty("{}"))
        #expect(model.isDirty("{ }"))
        #expect(model.isDirty("{]"))
    }

    @Test func cleanBufferReloadsSilently() {
        var model = JSONBufferModel(diskText: "{}", revision: 0)
        #expect(model.fileChanged(diskText: "{\"a\": 1}", revision: 1, buffer: "{}") == .reload("{\"a\": 1}"))
        #expect(model.baseline == "{\"a\": 1}")
        #expect(model.baselineRevision == 1)
        #expect(model.conflict == nil)
        // The same revision again is nothing new.
        #expect(model.fileChanged(diskText: "{\"a\": 1}", revision: 1, buffer: "{\"a\": 1}") == .none)
    }

    @Test func dirtyBufferGetsAConflict() {
        var model = JSONBufferModel(diskText: "{}", revision: 0)
        let mine = "{\"chat.fontSize\": 14}"
        #expect(model.fileChanged(diskText: "{\"b\": 2}", revision: 1, buffer: mine) == .conflict)
        #expect(model.conflict == .init(diskText: "{\"b\": 2}", revision: 1))
        // Still dirty against the old baseline until resolved.
        #expect(model.isDirty(mine))
        // Another change on disk updates the conflict.
        #expect(model.fileChanged(diskText: "{\"b\": 3}", revision: 2, buffer: mine) == .conflict)
        #expect(model.conflict?.revision == 2)
        #expect(model.fileChanged(diskText: "{\"b\": 3}", revision: 2, buffer: mine) == .none)
    }

    @Test func reloadTakesTheFileAndKeepMineKeepsTheEdits() {
        var reload = JSONBufferModel(diskText: "{}", revision: 0)
        _ = reload.fileChanged(diskText: "{\"b\": 2}", revision: 3, buffer: "{\"x\": 1}")
        #expect(reload.reloadFromConflict() == "{\"b\": 2}")
        #expect(reload.conflict == nil)
        #expect(!reload.isDirty("{\"b\": 2}"))
        #expect(reload.baselineRevision == 3)

        var keep = JSONBufferModel(diskText: "{}", revision: 0)
        _ = keep.fileChanged(diskText: "{\"b\": 2}", revision: 3, buffer: "{\"x\": 1}")
        keep.keepMine()
        #expect(keep.conflict == nil)
        #expect(keep.isDirty("{\"x\": 1}"))
        #expect(keep.baseline == "{\"b\": 2}")
        // No banner again for the same change.
        #expect(keep.fileChanged(diskText: "{\"b\": 2}", revision: 3, buffer: "{\"x\": 1}") == .none)
    }

    @Test func fileMatchingTheEditsIsNoConflict() {
        var model = JSONBufferModel(diskText: "{}", revision: 0)
        #expect(model.fileChanged(diskText: "{\"x\": 1}", revision: 1, buffer: "{\"x\": 1}") == .none)
        #expect(!model.isDirty("{\"x\": 1}"))
    }

    @Test func savingSetsTheBaselineAndResolvesConflicts() {
        var model = JSONBufferModel(diskText: "{}", revision: 0)
        _ = model.fileChanged(diskText: "{\"b\": 2}", revision: 1, buffer: "{\"x\": 1}")
        model.saved("{\"x\": 1}", revision: 2)
        #expect(model.conflict == nil)
        #expect(!model.isDirty("{\"x\": 1}"))
        // The store reports the view's own save as revision 2: not external.
        #expect(model.fileChanged(diskText: "{\"x\": 1}", revision: 2, buffer: "{\"x\": 1}") == .none)
    }

    @Test func revertGoesBackToTheFile() {
        var model = JSONBufferModel(diskText: "{\"a\": 1}", revision: 4)
        #expect(model.revert() == "{\"a\": 1}")
        _ = model.fileChanged(diskText: "{\"a\": 2}", revision: 5, buffer: "{\"mine\": 1}")
        #expect(model.revert() == "{\"a\": 2}")
        #expect(model.conflict == nil)
    }

    @MainActor
    @Test func storeRoundTripMatchesTheModel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VelaJSONView-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"), watchForChanges: false)
        var model = JSONBufferModel(diskText: store.fileText(), revision: store.fileRevision)
        let edited = "{\n    // mine\n    \"chat.fontSize\": 15\n}\n"
        try store.saveFileText(edited)
        model.saved(edited, revision: store.fileRevision)
        #expect(store[.chatFontSize] == 15)
        #expect(model.fileChanged(diskText: store.fileText(), revision: store.fileRevision, buffer: edited) == .none)
        // An app-side change while clean: reloads.
        store[.chatFontSize] = 16
        store.flush()
        let response = model.fileChanged(diskText: store.fileText(), revision: store.fileRevision, buffer: edited)
        guard case .reload(let text) = response else {
            Issue.record("expected a reload, got \(response)")
            return
        }
        #expect(text.contains("// mine"))
        #expect(text.contains("16"))
        // Invalid text is saved exactly; the store keeps its last good values.
        try store.saveFileText("{ \"chat.fontSize\": ")
        #expect(store.lastError != nil)
        #expect(store[.chatFontSize] == 16)
    }
}

// MARK: - Completion

@Suite("Settings JSON view: completion")
struct SettingsJSONCompletionTests {
    private let suggestions: JSONCompletionModel.Suggestions = { source in
        switch source {
        case .themes: [TokenSuggestion(value: "Palenight", detail: "Dark"), TokenSuggestion(value: "Lighter", detail: "Light")]
        case .buffers:
            [TokenSuggestion(value: "00000000-0000-0000-0000-000000000001/#vela", label: "#vela · Libera.Chat")]
        case .themeTokens:
            SettingSuggestionProvider.themeTokenSuggestions(themeNames: ["Nord"])
        case .domains: [TokenSuggestion(value: "example.com")]
        default: []
        }
    }

    /// `text` with `|` as the caret: the context, items and accepted result.
    private func complete(_ marked: String, picking label: String) -> (text: String, caret: NSRange)? {
        let caret = (marked as NSString).range(of: "|").location
        let text = marked.replacingOccurrences(of: "|", with: "")
        let context = SettingsCompletion.context(in: text, at: caret)
        let items = JSONCompletionModel.filtered(JSONCompletionModel.items(for: context, suggestions: suggestions), for: context)
        guard let item = items.first(where: { $0.label == label }) else { return nil }
        let (edits, selection) = JSONCompletionModel.acceptance(of: item, in: text as NSString)
        return (JSONCEdit.apply(edits, to: text), selection)
    }

    @Test func settingKeyInsertsKeyAndDefaultWithTheValueSelected() throws {
        let result = try #require(complete("{\n    \"chat.fon|\"\n}", picking: "chat.fontSize"))
        #expect(result.text == "{\n    \"chat.fontSize\": 13\n}")
        #expect((result.text as NSString).substring(with: result.caret) == "13")
    }

    @Test func enumDefaultIsSelectedInsideQuotes() throws {
        let result = try #require(complete("{\n    \"|\"\n}", picking: "chat.layout"))
        #expect(result.text == "{\n    \"chat.layout\": \"grouped\"\n}")
        #expect((result.text as NSString).substring(with: result.caret) == "grouped")
    }

    @Test func missingCommaIsAddedBeforeANewKey() throws {
        let result = try #require(complete("{\n    \"a\": 1\n    \"chat.layout|\"\n}", picking: "chat.layout"))
        #expect(result.text == "{\n    \"a\": 1,\n    \"chat.layout\": \"grouped\"\n}")
    }

    @Test func valueAfterABareColonGetsASpace() throws {
        let result = try #require(complete("{\"chat.layout\":|}", picking: "\"classic\""))
        #expect(result.text == "{\"chat.layout\": \"classic\"}")
        #expect(result.caret == NSRange(location: (result.text as NSString).range(of: "\"}").location + 1, length: 0))
    }

    @Test func valueReplacesTheWholeValue() throws {
        let result = try #require(complete("{\"chat.layout\": \"co|uped\"}", picking: "\"columns\""))
        #expect(result.text == "{\"chat.layout\": \"columns\"}")
    }

    @Test func themeSuggestionsReplaceTheModelsDefault() {
        let text = "{\"appearance.theme\": \"\"}"
        let caret = (text as NSString).range(of: "\"\"").location + 1
        let context = SettingsCompletion.context(in: text, at: caret)
        let items = JSONCompletionModel.items(for: context, suggestions: suggestions)
        let palenight = items.filter { $0.label == "\"Palenight\"" }
        #expect(palenight.count == 1)
        #expect(palenight.first?.isDefault == true)
        #expect(palenight.first?.detail == "Dark · Default")
        #expect(items.contains { $0.label == "\"Lighter\"" })
    }

    @Test func channelListsShowFriendlyNamesAndMatchThem() throws {
        let text = "{\"media.disabledBuffers\": [\"#ve\"]}"
        let caret = (text as NSString).range(of: "#ve").location + 3
        let context = SettingsCompletion.context(in: text, at: caret)
        let items = JSONCompletionModel.filtered(JSONCompletionModel.items(for: context, suggestions: suggestions), for: context)
        let item = try #require(items.first)
        #expect(item.title == "#vela · Libera.Chat")
        let (edits, _) = JSONCompletionModel.acceptance(of: item, in: text as NSString)
        #expect(JSONCEdit.apply(edits, to: text) == "{\"media.disabledBuffers\": [\"00000000-0000-0000-0000-000000000001/#vela\"]}")
    }

    @Test func colorCustomizationKeysAndValues() throws {
        // Tokens and scopes at the top of the object; a scope gets {} with the caret inside.
        let scoped = try #require(complete("{\"appearance.colorCustomizations\": {\"[No|\"}}", picking: "[Nord]"))
        #expect(scoped.text == "{\"appearance.colorCustomizations\": {\"[Nord]\": {}}}")
        #expect((scoped.text as NSString).substring(to: scoped.caret.location).hasSuffix("{\"[Nord]\": {"))
        // A token gets "" with the caret inside, ready for a color.
        let token = try #require(complete("{\"appearance.colorCustomizations\": {\"[Nord]\": {\"accen|\"}}}", picking: "accent"))
        #expect(token.text == "{\"appearance.colorCustomizations\": {\"[Nord]\": {\"accent\": \"\"}}}")
        // No scopes inside a scope.
        let text = "{\"appearance.colorCustomizations\": {\"[Nord]\": {\"|\"}}}"
        let caret = (text as NSString).range(of: "|").location
        let clean = text.replacingOccurrences(of: "|", with: "")
        let items = JSONCompletionModel.items(for: SettingsCompletion.context(in: clean, at: caret), suggestions: suggestions)
        #expect(!items.contains { $0.label == "[Nord]" })
        #expect(items.contains { $0.label == "accent" })
        // Vibrancy values.
        let vibrancy = try #require(complete("{\"appearance.colorCustomizations\": {\"vibrancy\": \"|\"}}", picking: "\"sidebar\""))
        #expect(vibrancy.text == "{\"appearance.colorCustomizations\": {\"vibrancy\": \"sidebar\"}}")
    }

    @Test func currentThemeColorIsOfferedForATokenValue() {
        let text = "{\"appearance.colorCustomizations\": {\"accent\": \"\"}}"
        let caret = (text as NSString).range(of: "\"\"").location + 1
        let items = JSONCompletionModel.items(for: SettingsCompletion.context(in: text, at: caret), suggestions: suggestions) { token in
            token == "accent" ? "#C792EA" : nil
        }
        #expect(items.map(\.label) == ["\"#C792EA\""])
        #expect(items.first?.title == "Current theme color")
    }

    @Test func siteRuleDomainsThenRules() throws {
        let key = try #require(complete("{\"media.siteRules\": {\"ex|\"}}", picking: "example.com"))
        #expect(key.text == "{\"media.siteRules\": {\"example.com\": \"\"}}")
        let value = try #require(complete("{\"media.siteRules\": {\"example.com\": \"|\"}}", picking: "\"block\""))
        #expect(value.text == "{\"media.siteRules\": {\"example.com\": \"block\"}}")
    }

    @Test func typingOpensTheListWhereItHelps() {
        func context(_ marked: String) -> SettingsCompletionContext {
            let caret = (marked as NSString).range(of: "|").location
            return SettingsCompletion.context(in: marked.replacingOccurrences(of: "|", with: ""), at: caret)
        }
        #expect(JSONCompletionModel.shouldOpen(afterTyping: "\"", context: context("{\"|\"}")))
        #expect(JSONCompletionModel.shouldOpen(afterTyping: ":", context: context("{\"chat.layout\":|}")))
        #expect(JSONCompletionModel.shouldOpen(afterTyping: "c", context: context("{\"c|\"}")))
        #expect(JSONCompletionModel.shouldOpen(afterTyping: "t", context: context("{\"chat.showAvatars\": t|}")))
        #expect(!JSONCompletionModel.shouldOpen(afterTyping: " ", context: context("{\"a\": 1, |}")))
        #expect(!JSONCompletionModel.shouldOpen(afterTyping: "x", context: context("{// x|\n}")))
        #expect(!JSONCompletionModel.shouldOpen(afterTyping: "ab", context: context("{\"|\"}")))
    }
}

// MARK: - Reveal and defaults

@Suite("Settings JSON view: reveal and copying defaults")
struct SettingsJSONRevealTests {
    @Test func revealSelectsTheLastValue() throws {
        let text = "{\n    \"chat.fontSize\": 12,\n    // again\n    \"chat.fontSize\": 14\n}\n"
        let plan = try #require(JSONReveal.plan(key: "chat.fontSize", defaultValue: 13, in: text))
        #expect(!plan.added)
        #expect(plan.selection == (text as NSString).range(of: "14"))
    }

    @Test func revealSelectsInsideAStringsQuotes() throws {
        let text = "{\"chat.layout\": \"classic\"}"
        let plan = try #require(JSONReveal.plan(key: "chat.layout", defaultValue: "grouped", in: text))
        #expect((text as NSString).substring(with: plan.selection) == "classic")
    }

    @Test func revealOfAMissingValueGoesAfterTheColon() throws {
        let text = "{\"chat.layout\": }"
        let plan = try #require(JSONReveal.plan(key: "chat.layout", defaultValue: "grouped", in: text))
        #expect(!plan.added)
        #expect(plan.selection.length == 0)
        #expect(plan.selection.location >= (text as NSString).range(of: ":").location + 1)
    }

    @Test func copyingADefaultAppendsItWithTheFilesStyle() throws {
        let text = "{\n\t// mine\n\t\"chat.layout\": \"classic\"\n}\n"
        let descriptor = try #require(SettingsCatalog.descriptor(forKey: "chat.fontSize"))
        let plan = try #require(JSONReveal.plan(key: descriptor.key, defaultValue: descriptor.defaultValue, in: text))
        #expect(plan.added)
        let edited = JSONCEdit.apply(plan.edits, to: text)
        #expect(edited == "{\n\t// mine\n\t\"chat.layout\": \"classic\",\n\t\"chat.fontSize\": 13\n}\n")
        #expect((edited as NSString).substring(with: plan.selection) == "13")
    }

    @Test func copyingIntoAnEmptyFile() throws {
        let plan = try #require(JSONReveal.plan(key: "chat.layout", defaultValue: "grouped", in: "{\n}\n"))
        let edited = JSONCEdit.apply(plan.edits, to: "{\n}\n")
        #expect(JSONCDocument(edited).jsonValue == .object(["chat.layout": "grouped"]))
        #expect((edited as NSString).substring(with: plan.selection) == "grouped")
    }

    @Test func unknownMissingKeyOrBrokenTextCantBeAdded() {
        #expect(JSONReveal.plan(key: "nope.nothing", defaultValue: nil, in: "{}") == nil)
        #expect(JSONReveal.plan(key: "chat.layout", defaultValue: "grouped", in: "[1, 2]") == nil)
    }
}

// MARK: - Diagnostics, selection, typing, hover

@Suite("Settings JSON view: diagnostics and editing")
struct SettingsJSONEditingTests {
    @Test func colorProblemsPointAtTheMember() throws {
        let text = """
        {
            "appearance.colorCustomizations": {
                "chat.background": "#123456",
                "notAToken": "#fff",
                "[Nord]": { "accent": "blue" },
                "nickColors": ["#fff", "red"]
            }
        }
        """
        let document = JSONCDocument(text)
        let raw = SettingsValidator.diagnostics(for: document, extraChecks: JSONColorChecks.extraChecks)
        let refined = JSONColorChecks.refine(raw, in: document)
        let ns = text as NSString
        let ranges = refined.filter { $0.kind == .extraCheck }.map { ns.substring(with: $0.range) }
        #expect(ranges.contains("\"notAToken\""))
        #expect(ranges.contains("\"blue\""))
        #expect(ranges.contains("\"red\""))
        #expect(refined.count == raw.count)
    }

    @Test func diagnosticsMoveWithEdits() {
        let diagnostic = SettingsDiagnostic(range: NSRange(location: 10, length: 4), severity: .warning, kind: .unknownKey, message: "x")
        func shifted(_ range: NSRange, _ delta: Int) -> NSRange? {
            JSONColorChecks.shift([diagnostic], editedRange: range, delta: delta).first?.range
        }
        #expect(shifted(NSRange(location: 2, length: 3), 3) == NSRange(location: 13, length: 4)) // insert before
        #expect(shifted(NSRange(location: 20, length: 1), 1) == NSRange(location: 10, length: 4)) // after
        #expect(shifted(NSRange(location: 12, length: 1), 1) == NSRange(location: 10, length: 5)) // inside
        #expect(shifted(NSRange(location: 9, length: 0), -6) == nil) // deleted with its text
    }

    @Test func reloadKeepsTheSelection() {
        let edit = JSONCEdit(range: NSRange(location: 5, length: 2), replacement: "abcd")
        #expect(JSONSelection.adjust(NSRange(location: 1, length: 2), for: edit) == NSRange(location: 1, length: 2))
        #expect(JSONSelection.adjust(NSRange(location: 10, length: 0), for: edit) == NSRange(location: 12, length: 0))
        #expect(JSONSelection.adjust(NSRange(location: 6, length: 0), for: edit) == NSRange(location: 6, length: 0))
        #expect(JSONSelection.adjust(NSRange(location: 3, length: 3), for: edit) == NSRange(location: 3, length: 6))
    }

    @Test func returnKeepsAndDeepensIndentation() {
        let text = "{\n    \"a\": {}\n}" as NSString
        let inside = text.range(of: "{}").location + 1
        let opened = JSONTyping.newline(in: text, selection: NSRange(location: inside, length: 0), indentUnit: "    ", lineEnding: "\n")
        #expect(opened.text == "\n        \n    ")
        #expect(opened.caret == 9)
        let afterValue = text.range(of: "{}").location + 2
        let plain = JSONTyping.newline(in: text, selection: NSRange(location: afterValue, length: 0), indentUnit: "    ", lineEnding: "\n")
        #expect(plain.text == "\n    ")
    }

    @Test func quotesPairAndStepOver() {
        #expect(JSONTyping.quoteAction(in: "{\n    \n}", at: 6) == .insertPair)
        #expect(JSONTyping.quoteAction(in: "{\"abc\"}", at: 5) == .skipClosing)
        #expect(JSONTyping.quoteAction(in: "{\"a\\\"}", at: 5) == .insertSingle) // after an escape
        #expect(JSONTyping.quoteAction(in: "{x}", at: 1) == .insertSingle)
        #expect(JSONTyping.quoteAction(in: "// a \n", at: 5) == .insertSingle)
    }

    @Test func onlyLikelyKeystrokesParseForCompletion() {
        func check(_ marked: String, _ typed: String) -> Bool {
            let caret = (marked as NSString).range(of: "|").location
            return JSONTyping.mightOpenCompletion(afterTyping: typed, in: marked.replacingOccurrences(of: "|", with: "") as NSString, at: caret)
        }
        #expect(check("{\"|", "\""))
        #expect(check("{\"a\":|", ":"))
        #expect(check("{\"chat.f|\"", "f"))
        #expect(check("{\"a\": t|", "t"))
        #expect(check("{\"a\": [1, t|", "t"))
        #expect(!check("{\"a\": 12|", "2") == false) // after a colon: could be a value
        #expect(!check("// note \"x|", "x"))
        #expect(!check("{ /* \"x|", "x"))
        #expect(!check("{\"a\": 1 }  x|", "x"))
    }

    @Test func largeFilesStayQuick() {
        var lines = ["{"]
        for index in 0..<8000 {
            lines.append("    // Setting number \(index), with a comment")
            lines.append("    \"group\(index).name\": \"value \(index)\",")
        }
        lines.append("}")
        let text = lines.joined(separator: "\n")
        let old = JSONSyntax.runs(in: text)
        let offset = (text as NSString).range(of: "value 4000").location + 5
        let edited = JSONCEdit.apply([.insert("x", at: offset)], to: text)
        let start = Date()
        let new = JSONSyntax.runs(in: edited)
        let changed = JSONSyntax.changedRange(old: old, new: new, editedRange: NSRange(location: offset, length: 1), delta: 1)
        var index = JSONLineIndex(text)
        index.update(editedRange: NSRange(location: offset, length: 1), delta: 1, in: edited as NSString)
        let elapsed = Date().timeIntervalSince(start)
        #expect(changed?.length == ("\"valuex 4000\"" as NSString).length)
        #expect(elapsed < 1, "one keystroke in a 16,000-line file took \(elapsed) s")
    }

    @Test func shiftTabOutdents() {
        let text = "{\n        \"a\": 1,\n  \"b\": 2\n}" as NSString
        let ranges = JSONTyping.outdentRanges(in: text, selection: NSRange(location: 3, length: 16), indentUnit: "    ")
        #expect(ranges == [NSRange(location: 2, length: 4), NSRange(location: 18, length: 2)])
    }

    @Test func hoverDocsDescribeTheSetting() throws {
        let fontSize = JSONHoverDocs(descriptor: try #require(SettingsCatalog.descriptor(forKey: "chat.fontSize")), isModified: true)
        #expect(fontSize.title == "Chat: Font Size")
        #expect(fontSize.isModified)
        #expect(fontSize.facts.first == .init(label: "Default", value: "13"))
        #expect(fontSize.facts.last?.value.contains("9 to 28") == true)
        let layout = JSONHoverDocs(descriptor: try #require(SettingsCatalog.descriptor(forKey: "chat.layout")), isModified: false)
        #expect(layout.facts.contains { $0.label == "Values" && $0.value.contains("\"columns\"") })
        let autocorrect = JSONHoverDocs(descriptor: try #require(SettingsCatalog.descriptor(forKey: "input.autocorrect")), isModified: false)
        #expect(autocorrect.facts.contains { $0.value.contains("\"system\"") })
        #expect(JSONHoverDocs(themeToken: "chat.background") != nil)
        #expect(JSONHoverDocs(themeToken: "nope") == nil)
    }
}

/// A small deterministic generator for the randomized tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - The editing session, end to end

/// Drives the real session and text view in an offscreen window: typing,
/// completion from the keyboard, saving, reverting, external changes,
/// leaving with unsaved edits, reveal and copying defaults.
@MainActor
@Suite("Settings JSON view: editing session", .serialized)
struct SettingsJSONSessionTests {
    struct Harness {
        let session: SettingsJSONSession
        let editor: SettingsEditorState
        let store: SettingsStore
        let window: NSWindow
        var text: String { session.textView.string }

        func type(_ string: String) {
            for character in string {
                session.textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }

        func press(_ selector: Selector) {
            session.textView.doCommand(by: selector)
        }

        func caret(after marker: String) {
            let range = (text as NSString).range(of: marker)
            session.textView.setSelectedRange(NSRange(location: range.location + range.length, length: 0))
        }

        var selectedText: String {
            (text as NSString).substring(with: session.textView.selectedRange())
        }
    }

    private func harness(_ initial: String) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VelaJSONSession-\(UUID().uuidString)")
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"), watchForChanges: false)
        try store.saveFileText(initial)
        let editor = SettingsEditorState()
        editor.mode = .json
        let session = SettingsJSONSession.session(for: editor)
        let app = AppModel.demo()
        let themeStore = ThemeStore(userThemesDirectory: directory.appendingPathComponent("Themes"))
        session.attach(store: store) { SettingSuggestionProvider(app: app, themeStore: themeStore, translations: nil) }
        session.apply(theme: .fallbackDark, font: .monospacedSystemFont(ofSize: 12, weight: .regular))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        session.editorPane.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        window.contentView = session.editorPane
        session.editorPane.layoutSubtreeIfNeeded()
        window.makeFirstResponder(session.textView)
        return Harness(session: session, editor: editor, store: store, window: window)
    }

    @Test func typingMakesItDirtyAndSavingWritesExactly() throws {
        let h = try harness("{\n    // keep me\n    \"chat.fontSize\": 13\n}\n")
        #expect(!h.session.isDirty)
        h.caret(after: "13")
        h.type("5")
        #expect(h.session.isDirty)
        #expect(h.editor.hasUnsavedJSON)
        #expect(h.session.save())
        #expect(!h.session.isDirty)
        #expect(!h.editor.hasUnsavedJSON)
        #expect(h.store.fileText() == "{\n    // keep me\n    \"chat.fontSize\": 135\n}\n")
        #expect(h.store[.chatFontSize] == 135)
        // Saving invalid text writes it as is; the store keeps the last good values.
        h.caret(after: "135")
        h.type(",,")
        #expect(h.session.save())
        #expect(h.store.fileText().contains("135,,"))
        #expect(h.store.lastError != nil)
        #expect(h.store[.chatFontSize] == 135)
    }

    @Test func keysAreColoredWithTheTheme() throws {
        let h = try harness("{\"chat.layout\": \"classic\"}")
        let layoutManager = try #require(h.session.textView.layoutManager)
        let keyColor = layoutManager.temporaryAttribute(.foregroundColor, atCharacterIndex: 2, effectiveRange: nil) as? NSColor
        #expect(keyColor == ResolvedTheme.fallbackDark.color(ThemeKey.accentText).nsColor)
        let valueColor = layoutManager.temporaryAttribute(.foregroundColor, atCharacterIndex: 18, effectiveRange: nil) as? NSColor
        #expect(valueColor == ResolvedTheme.fallbackDark.color(ThemeKey.statusSuccess).nsColor)
        // Typing a colon after a string turns it into a key.
        h.caret(after: "\"classic\"")
        h.type(" \"x\"")
        let typedString = layoutManager.temporaryAttribute(.foregroundColor, atCharacterIndex: 28, effectiveRange: nil) as? NSColor
        #expect(typedString == ResolvedTheme.fallbackDark.color(ThemeKey.statusSuccess).nsColor)
    }

    @Test func completingASettingFromTheKeyboard() throws {
        let h = try harness("{\n    \n}\n")
        h.caret(after: "{\n    ")
        h.type("\"")
        #expect(h.text == "{\n    \"\"\n}\n") // paired quotes
        #expect(h.session.completion != nil)
        h.type("chat.lay")
        #expect(h.text == "{\n    \"chat.lay\"\n}\n")
        #expect(h.session.completion?.selectedItem?.label == "chat.layout")
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.text == "{\n    \"chat.layout\": \"grouped\"\n}\n")
        #expect(h.selectedText == "grouped")
        // The values come up next; ↓ then Return picks one.
        let values = h.session.completion?.items.map(\.label) ?? []
        #expect(values.contains("\"classic\"") && values.contains("\"columns\""))
        let columns = try #require(values.firstIndex(of: "\"columns\""))
        let current = h.session.completion?.selectedIndex ?? 0
        for _ in 0..<((columns - current + values.count) % values.count) {
            h.press(#selector(NSResponder.moveDown(_:)))
        }
        h.press(#selector(NSResponder.insertTab(_:)))
        #expect(h.text == "{\n    \"chat.layout\": \"columns\"\n}\n")
        #expect(h.session.completion == nil)
        // Esc closes the list; Return then just breaks the line, indented.
        h.caret(after: "\"columns\"")
        h.session.updateCompletion(explicit: true)
        h.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(h.session.completion == nil)
        h.type(",")
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.text == "{\n    \"chat.layout\": \"columns\",\n    \n}\n")
    }

    @Test func numbersDontReopenTheList() throws {
        let h = try harness("{\n    \n}\n")
        h.caret(after: "{\n    ")
        h.type("\"chat.fontSi")
        h.press(#selector(NSResponder.insertNewline(_:)))
        #expect(h.text == "{\n    \"chat.fontSize\": 13\n}\n")
        #expect(h.selectedText == "13")
        #expect(h.session.completion == nil)
    }

    @Test func cleanBufferFollowsTheFileKeepingTheCaret() throws {
        let h = try harness("{\n    \"chat.fontSize\": 13,\n    \"chat.layout\": \"classic\"\n}\n")
        h.caret(after: "\"chat.layout\"")
        h.store[.chatFontSize] = 15
        h.store.flush()
        h.session.syncWithStore()
        #expect(h.text.contains("\"chat.fontSize\": 15"))
        #expect(!h.session.isDirty)
        #expect(!h.session.hasConflict)
        let caret = h.session.textView.selectedRange().location
        #expect((h.text as NSString).substring(to: caret).hasSuffix("\"chat.layout\""))
    }

    @Test func dirtyBufferGetsTheConflictBanner() throws {
        let h = try harness("{\n    \"chat.fontSize\": 13\n}\n")
        h.caret(after: "13")
        h.type("0")
        try h.store.saveFileText("{\n    \"chat.fontSize\": 20\n}\n") // someone else
        h.session.syncWithStore()
        #expect(h.session.hasConflict)
        #expect(h.text.contains("130"))
        h.session.keepMyChanges()
        #expect(!h.session.hasConflict)
        #expect(h.session.isDirty)
        try h.store.saveFileText("{\n    \"chat.fontSize\": 21\n}\n")
        h.session.syncWithStore()
        #expect(h.session.hasConflict)
        h.session.reloadFromDisk()
        #expect(!h.session.hasConflict)
        #expect(!h.session.isDirty)
        #expect(h.text.contains("21"))
    }

    @Test func revertGoesBackToTheSavedFile() throws {
        let h = try harness("{\"chat.fontSize\": 13}")
        h.caret(after: "13")
        h.type("99")
        h.session.revert()
        #expect(h.text == "{\"chat.fontSize\": 13}")
        #expect(!h.session.isDirty)
    }

    @Test func switchingViewsWithUnsavedEditsAsks() throws {
        let h = try harness("{\"chat.fontSize\": 13}")
        h.caret(after: "13")
        h.type("1")
        h.editor.requestMode(.ui)
        #expect(h.editor.mode == .json)
        #expect(h.editor.pendingMode == .ui)
        h.session.resolveLeave(.cancel)
        #expect(h.editor.mode == .json)
        #expect(h.editor.pendingMode == nil)
        #expect(h.session.isDirty)

        h.editor.requestMode(.ui)
        h.session.resolveLeave(.save)
        #expect(h.editor.mode == .ui)
        #expect(h.store[.chatFontSize] == 131)

        h.editor.mode = .json
        h.caret(after: "131")
        h.type("7")
        h.editor.requestMode(.ui)
        h.session.resolveLeave(.discard)
        #expect(h.editor.mode == .ui)
        #expect(h.text == "{\"chat.fontSize\": 131}")
        #expect(!h.editor.hasUnsavedJSON)
    }

    @Test func revealAndCopyDefault() throws {
        let h = try harness("{\n    \"chat.layout\": \"classic\"\n}\n")
        h.session.reveal(key: "chat.layout")
        #expect(h.selectedText == "classic")
        #expect(!h.session.isDirty)
        h.session.copyDefault(key: "chat.showAvatars")
        #expect(h.text == "{\n    \"chat.layout\": \"classic\",\n    \"chat.showAvatars\": false\n}\n")
        #expect(h.selectedText == "false")
        #expect(h.session.isDirty)
        // One undo removes the copied setting again.
        h.session.undoManager.undo()
        #expect(h.text == "{\n    \"chat.layout\": \"classic\"\n}\n")
        #expect(!h.session.isDirty)
    }

    @Test func validationFindsProblemsAndTheQuickFixFixesThem() async throws {
        let h = try harness("{\n    \"chat.fontSizee\": 13\n}\n")
        // Checking is debounced and runs in the background: wait for it
        // rather than a fixed time, which a busy machine can overrun.
        try await Self.waitUntil { h.session.diagnostics.contains { $0.kind == .unknownKey } }
        let problem = try #require(h.session.diagnostics.first { $0.kind == .unknownKey })
        #expect(problem.suggestedKey == "chat.fontSize")
        #expect(!h.session.textView.diagnostics.isEmpty)
        h.session.applyQuickFix(.init(range: problem.range, key: "chat.fontSize"))
        #expect(h.text == "{\n    \"chat.fontSize\": 13\n}\n")
        try await Self.waitUntil { h.session.diagnostics.isEmpty }
        #expect(h.session.diagnostics.isEmpty)
    }

    /// Polls `condition` until it holds or `timeout` passes.
    private static func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
