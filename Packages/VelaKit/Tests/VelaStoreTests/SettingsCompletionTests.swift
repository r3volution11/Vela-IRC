// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite struct SettingsCompletionTests {
    /// The context at `|` in `marked`, and the text without the marker.
    private func context(_ marked: String) -> (SettingsCompletionContext, String) {
        let location = (marked as NSString).range(of: "|").location
        let text = (marked as NSString).replacingCharacters(in: NSRange(location: location, length: 1), with: "")
        return (SettingsCompletion.context(in: text, at: location), text)
    }

    private func keyPosition(_ marked: String) throws -> (SettingsKeyPosition, String) {
        let (context, text) = context(marked)
        guard case .key(let position) = context else {
            Issue.record("Expected a key context, got \(context)")
            throw CancellationError()
        }
        return (position, text)
    }

    private func valuePosition(_ marked: String) throws -> (SettingsValuePosition, String) {
        let (context, text) = context(marked)
        guard case .value(let position) = context else {
            Issue.record("Expected a value context, got \(context)")
            throw CancellationError()
        }
        return (position, text)
    }

    /// Applies `item` and returns the new text and the selected text.
    private func accept(_ item: SettingsCompletionItem, in text: String) -> (text: String, selected: String) {
        let result = JSONCEdit.apply(item.edits, to: text)
        return (result, (result as NSString).substring(with: item.selectionAfterApplying))
    }

    private func item(_ label: String, in items: [SettingsCompletionItem]) throws -> SettingsCompletionItem {
        try #require(items.first { $0.label == label }, "\(label) not in \(items.map(\.label))")
    }

    // MARK: Keys

    @Test func keysOnAnEmptyLine() throws {
        let (position, text) = try keyPosition("{\n  \"chat.layout\": \"classic\",\n  |\n}")
        #expect(position.prefix == "")
        #expect(position.existingKeys == ["chat.layout"])
        #expect(!position.needsCommaAfter)

        let items = SettingsCompletion.items(for: .key(position))
        #expect(items.count == SettingsCatalog.all.count)
        let fontSize = try item("chat.fontSize", in: items)
        #expect(fontSize.kind == .setting)
        #expect(fontSize.title == "Chat: Font Size")
        #expect(fontSize.detail == "Chat font size in points.")
        #expect(fontSize.insertText == "\"chat.fontSize\": 13")
        #expect(!fontSize.isSet)
        #expect(try item("chat.layout", in: items).isSet)

        let (result, selected) = accept(fontSize, in: text)
        #expect(result == "{\n  \"chat.layout\": \"classic\",\n  \"chat.fontSize\": 13\n}")
        #expect(selected == "13")
    }

    @Test func keyInsertsSelectTheDefault() throws {
        let (position, text) = try keyPosition("{\n  |\n}")
        let items = SettingsCompletion.items(for: .key(position))
        #expect(accept(try item("chat.layout", in: items), in: text).selected == "grouped")
        #expect(accept(try item("chat.colorNicks", in: items), in: text).selected == "true")

        // Empty strings, objects and arrays put the caret inside.
        for label in ["chat.fontFamily", "appearance.colorCustomizations", "highlight.words"] {
            let completion = try item(label, in: items)
            #expect(completion.selection.length == 0)
            let (result, _) = accept(completion, in: text)
            let caret = completion.selectionAfterApplying.location
            let around = (result as NSString).substring(with: NSRange(location: caret - 1, length: 2))
            #expect(["\"\"", "{}", "[]"].contains(around), "\(label): \(around)")
        }
    }

    @Test func keyBeforeAnotherPropertyAddsAComma() throws {
        let (position, text) = try keyPosition("{\n  |\n  \"chat.layout\": \"classic\"\n}")
        #expect(position.needsCommaAfter)
        let fontSize = try item("chat.fontSize", in: SettingsCompletion.items(for: .key(position)))
        #expect(fontSize.insertText == "\"chat.fontSize\": 13,")
        let (result, selected) = accept(fontSize, in: text)
        #expect(result == "{\n  \"chat.fontSize\": 13,\n  \"chat.layout\": \"classic\"\n}")
        #expect(selected == "13")
        #expect(JSONCDocument(result).errors.isEmpty)
    }

    @Test func keyAfterAPropertyMissingItsCommaFixesIt() throws {
        let (position, text) = try keyPosition("{\n  \"chat.layout\": \"classic\"\n  \"chat.fo|\n}")
        #expect(position.prefix == "chat.fo")
        #expect(position.isInsideQuotes)
        let fontSize = try item("chat.fontSize", in: SettingsCompletion.items(for: .key(position)))
        #expect(fontSize.additionalEdits.count == 1)
        let (result, selected) = accept(fontSize, in: text)
        #expect(result == "{\n  \"chat.layout\": \"classic\",\n  \"chat.fontSize\": 13\n}")
        #expect(selected == "13")
    }

    @Test func renamingAKeyKeepsItsValue() throws {
        let (position, text) = try keyPosition("{\"chat.fo|ntSize\": 15}")
        #expect(position.hasValue)
        let fontSize = try item("chat.fontSize", in: SettingsCompletion.items(for: .key(position)))
        #expect(fontSize.insertText == "\"chat.fontSize\"")
        let (result, _) = accept(fontSize, in: text)
        #expect(result == "{\"chat.fontSize\": 15}")
        #expect(fontSize.selectionAfterApplying.location == 16)
    }

    @Test func bareWordsBecomeQuotedKeys() throws {
        let (position, text) = try keyPosition("{\n  sidebar.wi|\n}")
        #expect(position.prefix == "sidebar.wi")
        #expect(!position.isInsideQuotes)
        let width = try item("sidebar.width", in: SettingsCompletion.items(for: .key(position)))
        #expect(accept(width, in: text).text == "{\n  \"sidebar.width\": 200\n}")
    }

    // MARK: Values

    @Test func enumValues() throws {
        let (position, text) = try valuePosition("{\"chat.layout\": \"c|\"}")
        #expect(position.key == "chat.layout")
        #expect(position.prefix == "c")
        #expect(position.isInsideQuotes)
        let items = SettingsCompletion.items(for: .value(position))
        #expect(items.map(\.label) == [#""classic""#, #""grouped""#, #""columns""#])
        #expect(items.map(\.isDefault) == [false, true, false])
        #expect(items.map(\.filterText) == ["classic", "grouped", "columns"])
        let (result, _) = accept(items[2], in: text)
        #expect(result == #"{"chat.layout": "columns"}"#)
        #expect(SettingsCompletion.filter(items, matching: "c").map(\.label) == [#""classic""#, #""columns""#])
    }

    @Test func booleanValues() throws {
        let (position, text) = try valuePosition("{\n  \"chat.colorNicks\": |\n  \"chat.layout\": \"classic\"\n}")
        #expect(position.needsCommaAfter)
        let items = SettingsCompletion.items(for: .value(position))
        #expect(items.map(\.label) == ["true", "false"])
        #expect(items.first?.isDefault == true)
        let (result, _) = accept(items[1], in: text)
        #expect(result == "{\n  \"chat.colorNicks\": false,\n  \"chat.layout\": \"classic\"\n}")
    }

    @Test func settingsThatFollowMacOSOfferSystem() throws {
        let (position, _) = try valuePosition("{\"input.autocorrect\": |}")
        let items = SettingsCompletion.items(for: .value(position))
        #expect(items.map(\.label) == ["true", "false", #""system""#])
        #expect(items.map(\.isDefault) == [false, false, true])
    }

    @Test func otherValuesOfferTheDefault() throws {
        let (number, _) = try valuePosition("{\"chat.fontSize\": 1|}")
        #expect(number.prefix == "1")
        #expect(SettingsCompletion.items(for: .value(number)).map(\.label) == ["13"])

        let (string, text) = try valuePosition("{\"chat.fontFamily\": |}")
        let items = SettingsCompletion.items(for: .value(string))
        #expect(items.map(\.label) == [#""""#])
        #expect(accept(items[0], in: text).text == #"{"chat.fontFamily": ""}"#)
        #expect(items[0].selectionAfterApplying.location == 21)

        let (array, _) = try valuePosition("{\"highlight.words\": [\"a\", |]}")
        #expect(array.isArrayElement)
        #expect(SettingsCompletion.items(for: .value(array)).isEmpty)

        let (unknown, _) = try valuePosition("{\"made.up\": |}")
        #expect(SettingsCompletion.items(for: .value(unknown)).isEmpty)
    }

    @Test func appSuppliedValues() throws {
        let (position, text) = try valuePosition("{\"appearance.theme\": \"Pa|\"}")
        #expect(position.descriptor?.suggestionSource == .themes)
        let theme = SettingsCompletion.valueItem("Palenight", title: "Palenight", detail: "Built-in theme", at: position)
        #expect(theme.isDefault)
        #expect(accept(theme, in: text).text == #"{"appearance.theme": "Palenight"}"#)
    }

    // MARK: Nested objects

    @Test func nestedKeysAndValues() throws {
        let (context, text) = context("{\n  \"media.siteRules\": {\n    \"example.com\": \"block\",\n    |\n  }\n}")
        guard case .nestedKey(let position) = context else {
            Issue.record("Expected a nested key, got \(context)")
            return
        }
        #expect(position.settingKey == "media.siteRules")
        #expect(position.descriptor?.suggestionSource == .domains)
        #expect(position.existingKeys == ["example.com"])
        #expect(SettingsCompletion.items(for: context).isEmpty)

        let domain = SettingsCompletion.keyItem("imgur.com", detail: "Seen in #vela", at: position)
        let (result, selected) = accept(domain, in: text)
        #expect(result == "{\n  \"media.siteRules\": {\n    \"example.com\": \"block\",\n    \"imgur.com\": \"\"\n  }\n}")
        #expect(selected == "")
        #expect(domain.selectionAfterApplying.location == (result as NSString).range(of: "\"\"").location + 1)

        let (valueContext, _) = self.context("{\"media.siteRules\": {\"imgur.com\": \"|\"}}")
        guard case .nestedValue(let valuePosition) = valueContext else {
            Issue.record("Expected a nested value, got \(valueContext)")
            return
        }
        #expect(valuePosition.path == ["media.siteRules", "imgur.com"])
        #expect(SettingsCompletion.items(for: valueContext).map(\.label) == [#""allow""#, #""textOnly""#, #""block""#])
    }

    @Test func themeScopes() throws {
        let (context, _) = context("{\"appearance.colorCustomizations\": {\"[Palenight]\": {\"acc|\"}}}")
        guard case .nestedKey(let position) = context else {
            Issue.record("Expected a nested key, got \(context)")
            return
        }
        #expect(position.objectPath == ["appearance.colorCustomizations", "[Palenight]"])
        #expect(position.prefix == "acc")
        #expect(position.descriptor?.suggestionSource == .themeTokens)
    }

    // MARK: Nothing to offer

    @Test func noCompletionInCommentsOrOutside() {
        #expect(context("{\n  // chat.fo|\n}").0 == .none)
        #expect(context("{} |").0 == .none)
        #expect(context("[|]").0 == .none)
        #expect(context("|").0 == .none)
    }

    // MARK: Filtering

    @Test func filterRanksPrefixMatchesFirst() throws {
        let (position, _) = try keyPosition("{|}")
        let items = SettingsCompletion.items(for: .key(position))
        let fontSize = SettingsCompletion.filter(items, matching: "fontSi").map(\.label)
        #expect(Array(fontSize.prefix(2)) == ["chat.fontSize", "sidebar.fontSize"])
        #expect(SettingsCompletion.filter(items, matching: "chat.fo").first?.label == "chat.fontFamily")
        #expect(SettingsCompletion.filter(items, matching: "Font Size").map(\.label).contains("chat.fontSize"))
        #expect(SettingsCompletion.filter(items, matching: "cfs").map(\.label).contains("chat.fontSize"))
        #expect(SettingsCompletion.filter(items, matching: "").count == items.count)
        #expect(SettingsCompletion.filter(items, matching: "qqqq").isEmpty)
    }

    // MARK: Hover

    @Test func hover() throws {
        let text = """
            {
              "chat.fontSize": 13,
              "made.up": 1,
              "media.siteRules": {"example.com": "block"}
            }
            """
        let keyRange = utf16Range(of: "\"chat.fontSize\"", in: text)
        let hover = try #require(SettingsCompletion.hover(in: text, at: keyRange.location + 3))
        #expect(hover.key == "chat.fontSize")
        #expect(hover.range == keyRange)
        #expect(hover.descriptor?.summary == "Chat font size in points.")
        #expect(hover.isSetting)

        let unknown = try #require(SettingsCompletion.hover(in: text, at: utf16Range(of: "made.up", in: text).location))
        #expect(unknown.descriptor == nil)

        let nested = try #require(SettingsCompletion.hover(in: text, at: utf16Range(of: "example.com", in: text).location))
        #expect(nested.path == ["media.siteRules", "example.com"])
        #expect(nested.descriptor?.key == "media.siteRules")
        #expect(!nested.isSetting)

        #expect(SettingsCompletion.hover(in: text, at: utf16Range(of: "13", in: text).location + 1) == nil)
        // Right after the closing quote still counts (for the text cursor).
        #expect(SettingsCompletion.hover(in: text, at: keyRange.location + keyRange.length)?.key == "chat.fontSize")
    }
}
