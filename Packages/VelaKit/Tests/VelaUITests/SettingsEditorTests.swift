// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
import VelaStore
import VelaTheme
@testable import VelaUI

@MainActor
@Suite("Settings editor: search")
struct SettingsEditorSearchTests {
    let catalog = SettingsCatalog.all

    private func entries(_ values: [String: JSONValue] = [:]) -> [SettingsEditorEntry] {
        SettingsEditorEntry.all(catalog: catalog, values: values)
    }

    private func keys(_ query: String, _ values: [String: JSONValue] = [:]) -> [String] {
        let parsed = SettingsQuery(query)
        return entries(values).filter(parsed.matches).map(\.key)
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(SettingsQuery("").isEmpty)
        #expect(keys("").count == catalog.count)
    }

    @Test func wordsMatchTitleKeyDescriptionAndValue() {
        // Title ("Chat: Font Size") and key.
        #expect(keys("font size").contains("chat.fontSize"))
        #expect(keys("chat.fontsize") == ["chat.fontSize"])
        // Description only: "Show initials avatars next to message groups…".
        #expect(keys("initials").contains("chat.showAvatars"))
        // Current value.
        #expect(keys("menlo", ["chat.fontFamily": "Menlo"]) == ["chat.fontFamily"])
        // Every word must match.
        #expect(keys("font zebra").isEmpty)
        // Case doesn't matter.
        #expect(keys("FONT SIZE") == keys("font size"))
    }

    @Test func modifiedFilter() {
        let values: [String: JSONValue] = ["chat.fontSize": 15, "tabs.height": 30]
        #expect(Set(keys("@modified", values)) == ["chat.fontSize", "tabs.height"])
        #expect(keys("@modified tabs", values) == ["tabs.height"])
        #expect(keys("@MODIFIED", values).count == 2)
    }

    @Test func categoryFilterByIDOrTitle() {
        let typing = keys("@category:typing")
        #expect(!typing.isEmpty)
        #expect(typing.allSatisfy { $0.hasPrefix("input.") })
        // "Messages" is the title of the chat category.
        #expect(keys("@category:messages") == keys("@category:chat"))
        // History holds stored messages and chat logs.
        let history: Set<String> = [
            "history.retentionDays", "logging.enabled", "logging.maxFileSizeMB", "logging.keepFiles",
            "logging.includeEvents", "logging.includeServer", "logging.excludedBuffers",
        ]
        #expect(Set(keys("@category:history")) == history)
        // Several categories are OR'ed.
        let both = Set(keys("@category:typing @category:history"))
        #expect(both == Set(typing).union(history))
        // A category that doesn't exist matches nothing.
        #expect(keys("@category:nope").isEmpty)
    }

    @Test func paneFilter() {
        let messages = Set(keys("@pane:messages"))
        #expect(messages.contains("chat.fontSize"))
        #expect(messages.contains("input.autocorrect"))
        #expect(messages.contains("history.retentionDays"))
        #expect(messages.contains("logging.enabled"))
        #expect(!messages.contains("media.autoLoad"))
        #expect(keys("@pane:networks") == ["connection.autoReconnect"])
        #expect(keys("@pane:presets").isEmpty)
    }

    @Test func unknownFilterAndUnknownEntries() {
        let values: [String: JSONValue] = ["zeta.thing": true, "bogus.key": 1, "chat.fontSize": 14]
        let all = entries(values)
        // Known settings in catalog order, then unknown keys sorted.
        #expect(all.suffix(2).map(\.key) == ["bogus.key", "zeta.thing"])
        #expect(all.suffix(2).allSatisfy { $0.isUnknown })
        #expect(keys("@unknown", values) == ["bogus.key", "zeta.thing"])
        // Unknown keys never match category or pane filters.
        #expect(!keys("@category:chat", values).contains("bogus.key"))
        // But words find them by key and value.
        #expect(keys("bogus", values) == ["bogus.key"])
    }

    @Test func incompleteFiltersAreIgnored() {
        #expect(keys("@").count == catalog.count)
        #expect(keys("@mod").count == catalog.count)
        #expect(keys("@category:").count == catalog.count)
        #expect(SettingsQuery("@mod").isEmpty)
    }

    @Test func togglingATokenAddsOrRemovesIt() {
        #expect(SettingsQuery.toggling("@modified", in: "font") == "font @modified")
        #expect(SettingsQuery.toggling("@modified", in: "font @Modified  size") == "font size")
        #expect(SettingsQuery.toggling("@modified", in: "") == "@modified")
    }

    @Test func settingTheScopeReplacesCategoryPaneAndUnknown() {
        let text = "font @category:chat @pane:messages @unknown @modified"
        #expect(SettingsQuery.settingScope("@category:typing", in: text) == "font @modified @category:typing")
        #expect(SettingsQuery.settingScope(nil, in: text) == "font @modified")
    }

    @Test func chipStates() {
        let query = SettingsQuery("@category:chat")
        #expect(query.includes(.chat))
        #expect(!query.includes(.typing))
        #expect(query.hasScope)
        #expect(!SettingsQuery("font @modified").hasScope)
    }

    @Test func filterCompletions() {
        let completions = SettingsQuery.filterCompletions(
            for: "@ca",
            categories: [.chat, .typing],
            panes: [("messages", "Messages")]
        )
        #expect(completions.map(\.value) == ["@category:chat", "@category:typing"])
        #expect(SettingsQuery.filterCompletions(for: "font", categories: [.chat], panes: []).isEmpty)
        // A complete token isn't offered again.
        #expect(SettingsQuery.filterCompletions(for: "@modified", categories: [], panes: []).isEmpty)
        #expect(SettingsQuery.filterCompletions(for: "@", categories: [], panes: []).map(\.value) == ["@modified", "@unknown"])
    }

    @Test func groupingFollowsCategoryOrderWithUnknownLast() {
        let all = entries(["bogus.key": 1])
        let groups = SettingsEditorGroup.grouping(all)
        let categories = groups.compactMap(\.category)
        #expect(categories == SettingsCategory.allCases.filter { category in all.contains { $0.category == category } })
        #expect(groups.last?.isUnknown == true)
        #expect(groups.last?.entries.map(\.key) == ["bogus.key"])
        #expect(groups.reduce(0) { $0 + $1.entries.count } == all.count)
    }

    @Test func controlKinds() {
        func kind(_ key: String) -> SettingControlKind {
            SettingControlKind(SettingsEditorEntry(key: key, descriptor: SettingsCatalog.descriptor(forKey: key), value: nil))
        }
        #expect(kind("chat.showTimestamps") == .toggle)
        #expect(kind("input.autocorrect") == .followsSystem)
        #expect(kind("chat.layout") == .menu(["classic", "grouped", "columns"]))
        #expect(kind("chat.fontSize") == .number(range: 9...28, integer: false))
        #expect(kind("history.retentionDays") == .number(range: 0...3650, integer: true))
        #expect(kind("chat.fontFamily") == .suggestedString(.fontFamilies))
        #expect(kind("translation.language") == .suggestedString(.languages))
        #expect(kind("highlight.words") == .stringList(nil))
        #expect(kind("media.blurredBuffers") == .stringList(.buffers))
        #expect(kind("media.siteRules") == .siteRules)
        #expect(kind("appearance.colorCustomizations") == .colorCustomizations)
        #expect(kind("bogus.key") == .unknown)
        #expect(kind("bogus.key").isWide)
        #expect(!kind("chat.fontSize").isWide)
    }
}

@Suite("Settings editor: numbers")
struct NumberSettingInputTests {
    @Test func parsesNumbersInRange() {
        #expect(NumberSettingInput.parse(" 14 ", range: 9...28, integer: false) == .success(14))
        #expect(NumberSettingInput.parse("13.5", range: 9...28, integer: false) == .success(13.5))
        #expect(NumberSettingInput.parse("0,5", range: 0...1, integer: false) == .success(0.5))
    }

    @Test func refusesOutOfRangeAndNonNumbers() {
        #expect(NumberSettingInput.parse("30", range: 9...28, integer: false) == .failure(.outOfRange(9...28)))
        #expect(NumberSettingInput.parse("8", range: 9...28, integer: false) == .failure(.outOfRange(9...28)))
        #expect(NumberSettingInput.parse("big", range: 9...28, integer: false) == .failure(.notANumber))
        #expect(NumberSettingInput.parse("", range: nil, integer: false) == .failure(.notANumber))
        #expect(NumberSettingInput.parse("2.5", range: 0...10, integer: true) == .failure(.notWhole))
        #expect(NumberSettingInput.parse("inf", range: nil, integer: false) == .failure(.notANumber))
    }

    @Test func messages() {
        #expect(NumberSettingInput.Problem.outOfRange(9...28).message(integer: false) == "Must be between 9 and 28.")
        #expect(NumberSettingInput.Problem.outOfRange(0...1).message(integer: false) == "Must be between 0 and 1.")
        #expect(NumberSettingInput.Problem.notWhole.message(integer: true) == "Enter a whole number.")
    }

    @Test func clampsToTheRange() {
        #expect(NumberSettingInput.clamp(40, to: 9...28) == 28)
        #expect(NumberSettingInput.clamp(2, to: 9...28) == 9)
        #expect(NumberSettingInput.clamp(12, to: 9...28) == 12)
        #expect(NumberSettingInput.clamp(-5, to: nil) == -5)
    }

    @Test func stepsAndFormatting() {
        #expect(NumberSettingInput.step(for: 9...28, integer: false) == 1)
        #expect(NumberSettingInput.step(for: 0...1, integer: false) == 0.05)
        #expect(NumberSettingInput.step(for: 0...1, integer: true) == 1)
        #expect(NumberSettingInput.step(for: 200...100_000, integer: true) == 100)
        #expect(NumberSettingInput.step(for: 0...3650, integer: true) == 10)
        #expect(NumberSettingInput.step(for: nil, integer: false) == 1)
        #expect(NumberSettingInput.format(13, integer: false) == "13")
        #expect(NumberSettingInput.format(0.35, integer: false) == "0.35")
        #expect(NumberSettingInput.format(2.5, integer: false) == "2.5")
        #expect(NumberSettingInput.format(30, integer: true) == "30")
    }

    @Test func jsonValuesForUnknownKeys() {
        #expect(SettingsJSONText.parse("true") == .value(.bool(true)))
        #expect(SettingsJSONText.parse("[\"a\", 2,]") == .value(.array([.string("a"), .number(2)])))
        #expect(SettingsJSONText.parse("{\"a\": 1} // note") == .value(.object(["a": .number(1)])))
        if case .problem = SettingsJSONText.parse("hello") {} else { Issue.record("Bare words aren't JSON") }
        if case .problem = SettingsJSONText.parse("  ") {} else { Issue.record("Empty text isn't JSON") }
        #expect(SettingsJSONText.entry(key: "chat.fontSize", value: 13) == "\"chat.fontSize\": 13")
    }
}

@Suite("Settings editor: token field")
struct TokenFieldModelTests {
    let suggestions = [
        TokenSuggestion(value: "uuid/#vela", label: "#vela · Libera.Chat"),
        TokenSuggestion(value: "uuid/#swift", label: "#swift · Libera.Chat"),
        TokenSuggestion(value: "Menlo"),
    ]

    @Test func commitsTypedText() {
        var model = TokenFieldModel(values: ["one"], allowsMultiple: true)
        #expect(model.commit("  two ", suggestions: [], resolve: { $0 }) == .added("two"))
        #expect(model.values == ["one", "two"])
    }

    @Test func typedTextMatchingASuggestionStoresItsValue() {
        var model = TokenFieldModel(values: [], allowsMultiple: true)
        #expect(model.commit("#VELA · libera.chat", suggestions: suggestions, resolve: { _ in nil }) == .added("uuid/#vela"))
        #expect(model.commit("menlo", suggestions: suggestions, resolve: { _ in nil }) == .added("Menlo"))
    }

    @Test func refusesDuplicatesIgnoringCase() {
        var model = TokenFieldModel(values: ["Vela"], allowsMultiple: true)
        #expect(model.commit("vela", suggestions: [], resolve: { $0 }) == .duplicate("vela"))
        #expect(model.add("VELA") == .duplicate("VELA"))
        #expect(model.values == ["Vela"])
    }

    @Test func rejectedAndEmptyText() {
        var model = TokenFieldModel(values: [], allowsMultiple: true)
        #expect(model.commit("#nowhere", suggestions: suggestions, resolve: { _ in nil }) == .rejected)
        #expect(model.commit("   ", suggestions: suggestions, resolve: { $0 }) == .empty)
        #expect(model.values.isEmpty)
    }

    @Test func singleValueReplaces() {
        var model = TokenFieldModel(values: ["Menlo", "ignored"], allowsMultiple: false)
        #expect(model.values == ["Menlo"])
        #expect(model.add("Monaco") == .replaced("Monaco"))
        #expect(model.values == ["Monaco"])
        #expect(model.removeLast() == "Monaco")
        #expect(model.add("Menlo") == .added("Menlo"))
    }

    @Test func removing() {
        var model = TokenFieldModel(values: ["a", "b", "c"], allowsMultiple: true)
        model.remove("b")
        #expect(model.values == ["a", "c"])
        #expect(model.removeLast() == "c")
        #expect(model.removeLast() == "a")
        #expect(model.removeLast() == nil)
    }

    @Test func commasSplitTypedText() {
        #expect(TokenFieldModel.split("a, b,c") == (["a", "b"], "c"))
        #expect(TokenFieldModel.split("a,") == (["a"], ""))
        #expect(TokenFieldModel.split(",, a ,  ") == (["a"], ""))
        #expect(TokenFieldModel.split("abc") == ([], "abc"))
    }

    @Test func filteringPutsPrefixMatchesFirstAndSkipsChosen() {
        let all = [
            TokenSuggestion(value: "chat.background"),
            TokenSuggestion(value: "window.background"),
            TokenSuggestion(value: "background.x"),
            TokenSuggestion(value: "accent", detail: "Controls"),
        ]
        #expect(TokenFieldModel.filter(all, query: "back").map(\.value) == ["background.x", "chat.background", "window.background"])
        #expect(TokenFieldModel.filter(all, query: "controls").map(\.value) == ["accent"])
        #expect(TokenFieldModel.filter(all, query: "", excluding: ["ACCENT"]).count == 3)
        #expect(TokenFieldModel.filter(all, query: "", limit: 2).count == 2)
    }

    @Test func returnPicksOnlyAPrefixMatch() {
        let patterns = ["HH:mm", "HH:mm:ss", "[HH:mm]"].map { TokenSuggestion(value: $0) }
        let typedPrefix = TokenFieldModel.filter(patterns, query: "HH")
        #expect(TokenFieldModel.autoHighlight(query: "HH", in: typedPrefix) == 0)
        // A custom pattern that only appears inside suggestions stays as typed.
        let custom = TokenFieldModel.filter(patterns, query: "H:mm")
        #expect(!custom.isEmpty)
        #expect(TokenFieldModel.autoHighlight(query: "H:mm", in: custom) == nil)
        #expect(TokenFieldModel.autoHighlight(query: "", in: patterns) == nil)
    }
}

@Suite("Settings editor: buffer labels")
struct BufferLabelTests {
    let libera = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let oftc = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    var networks: [SettingSuggestionProvider.NetworkBuffers] {
        [
            .init(id: libera, name: "Libera.Chat", buffers: [("#vela", "#Vela"), ("#swift", "#swift"), ("alice", "Alice")]),
            .init(id: oftc, name: "OFTC", buffers: [("#swift", "#swift")]),
        ]
    }

    @Test func labels() {
        #expect(SettingSuggestionProvider.bufferLabel("\(libera.uuidString)/#vela", networks: networks) == "#Vela · Libera.Chat")
        #expect(SettingSuggestionProvider.bufferLabel("\(libera.uuidString)/*", networks: networks) == "All of Libera.Chat")
        // Lowercase UUIDs written by hand still resolve.
        #expect(SettingSuggestionProvider.bufferLabel("\(oftc.uuidString.lowercased())/#swift", networks: networks) == "#swift · OFTC")
        // A buffer that isn't loaded shows its folded name.
        #expect(SettingSuggestionProvider.bufferLabel("\(oftc.uuidString)/#debian", networks: networks) == "#debian · OFTC")
    }

    @Test func unknownEntriesShowRaw() {
        let stranger = "33333333-3333-3333-3333-333333333333/#vela"
        #expect(SettingSuggestionProvider.bufferLabel(stranger, networks: networks) == stranger)
        #expect(SettingSuggestionProvider.bufferLabel("not an entry", networks: networks) == "not an entry")
        #expect(SettingSuggestionProvider.bufferLabel("\(libera.uuidString)/", networks: networks) == "\(libera.uuidString)/")
    }

    @Test func suggestionsRoundTrip() {
        let suggestions = SettingSuggestionProvider.bufferSuggestions(networks: networks)
        // Networks first, then each buffer.
        #expect(suggestions.prefix(2).map(\.label) == ["All of Libera.Chat", "All of OFTC"])
        #expect(suggestions.count == 2 + 4)
        for suggestion in suggestions {
            // Stored value → label → the same suggestion's value.
            #expect(SettingSuggestionProvider.bufferLabel(suggestion.value, networks: networks) == suggestion.label)
            var model = TokenFieldModel(values: [], allowsMultiple: true)
            #expect(model.commit(suggestion.label, suggestions: suggestions, resolve: { _ in nil }) == .added(suggestion.value))
        }
        #expect(suggestions.contains { $0.value == "\(libera.uuidString)/*" })
    }

    @Test func resolvingTypedNames() {
        let suggestions = SettingSuggestionProvider.bufferSuggestions(networks: networks)
        // Only Libera.Chat has #vela.
        #expect(SettingSuggestionProvider.resolveBuffer("#vela", suggestions: suggestions) == "\(libera.uuidString)/#vela")
        // Both have #swift: ambiguous.
        #expect(SettingSuggestionProvider.resolveBuffer("#swift", suggestions: suggestions) == nil)
        // A network's name stands for the whole network.
        #expect(SettingSuggestionProvider.resolveBuffer("oftc", suggestions: suggestions) == "\(oftc.uuidString)/*")
        // Raw entries are accepted as written.
        let raw = "\(oftc.uuidString)/#weird"
        #expect(SettingSuggestionProvider.resolveBuffer(raw, suggestions: suggestions) == raw)
        #expect(SettingSuggestionProvider.resolveBuffer("#nowhere", suggestions: suggestions) == nil)
    }
}

@Suite("Settings editor: color customizations")
struct ColorCustomizationsModelTests {
    let customizations: [String: JSONValue] = [
        "chat.background": "#1E1E2E",
        "accent": "#FF8A65",
        "nickColors": .array(["#FF0000", "#00FF00"]),
        "vibrancy": "sidebar",
        "made.up": "#123456",
        "window.foreground": "blue",
        "[Palenight]": .object([
            "accent": "#89DDFF",
            "button.background": "#89DDFF",
            "chat.link": "#C3E88D",
            "$accentPicker": .array(["accent", "button.background"]),
        ]),
        "[Nord][Dracula]": .object(["ircColors": .object(["1": "#000000", "0": "#FFFFFF", "12": "nope"])]),
    ]

    @Test func splitsTopLevelAndScopes() {
        let model = ColorCustomizationsModel(customizations)
        #expect(model.topLevel.map(\.token) == ["accent", "chat.background", "made.up", "nickColors", "vibrancy", "window.foreground"])
        #expect(model.scopes.map(\.key) == ["[Nord][Dracula]", "[Palenight]"])
        #expect(model.scopes[0].title == "Nord, Dracula")
        #expect(model.scopes[1].entries.map(\.token) == ["accent", "button.background", "chat.link"])
        #expect(model.count == 6 + 1 + 3)
    }

    @Test func kinds() {
        let model = ColorCustomizationsModel(customizations)
        func kind(_ token: String) -> ColorCustomizationsModel.Kind? { model.topLevel.first { $0.token == token }?.kind }
        #expect(kind("chat.background") == .color(ThemeColor(hex: "#1E1E2E")!))
        #expect(kind("made.up") == .unknownToken)
        #expect(kind("window.foreground") == .invalidColor)
        #expect(kind("vibrancy") == .vibrancy("sidebar"))
        #expect(kind("nickColors") == .nickColors([ThemeColor(hex: "#FF0000")!, ThemeColor(hex: "#00FF00")!]))
        guard case .ircColors(let irc) = model.scopes[0].entries[0].kind else {
            Issue.record("ircColors should be read as IRC colors")
            return
        }
        #expect(irc.map(\.index) == ["0", "1", "12"])
        #expect(irc.last?.color == nil)
    }

    @Test func accentPickerTokensAreMarked() {
        let palenight = ColorCustomizationsModel(customizations).scope("[Palenight]")!
        #expect(palenight.accentPickerTokens == ["accent", "button.background"])
        #expect(palenight.entries.filter(\.isAccentPicker).map(\.token) == ["accent", "button.background"])
        #expect(ColorCustomizationsModel(customizations).topLevel.allSatisfy { !$0.isAccentPicker })
    }

    @Test func editingAnAccentPickerTokenMakesItHandWritten() {
        let edited = ColorCustomizationsModel.setting("accent", to: "#FFFFFF", inScope: "[Palenight]", of: customizations)
        let scope = edited["[Palenight]"]?.objectValue
        #expect(scope?["accent"] == "#FFFFFF")
        #expect(scope?["$accentPicker"] == .array(["button.background"]))
        // The last one drops the marker.
        let both = ColorCustomizationsModel.setting("button.background", to: nil, inScope: "[Palenight]", of: edited)
        #expect(both["[Palenight]"]?.objectValue?["$accentPicker"] == nil)
        #expect(both["[Palenight]"]?.objectValue?.keys.sorted() == ["accent", "chat.link"])
    }

    @Test func removingTheLastTokenRemovesTheScope() {
        var result = ColorCustomizationsModel.setting("ircColors", to: nil, inScope: "[Nord][Dracula]", of: customizations)
        #expect(result["[Nord][Dracula]"] == nil)
        result = ColorCustomizationsModel.setting("accent", to: "#000000", inScope: "[Lighter]", of: result)
        #expect(result["[Lighter]"] == .object(["accent": "#000000"]))
    }

    @Test func topLevelEdits() {
        var result = ColorCustomizationsModel.setting("accent", to: nil, inScope: nil, of: customizations)
        #expect(result["accent"] == nil)
        result = ColorCustomizationsModel.renaming("made.up", to: "chat.link", inScope: nil, of: result)
        #expect(result["made.up"] == nil)
        #expect(result["chat.link"] == "#123456")
        let renamedInScope = ColorCustomizationsModel.renaming("chat.link", to: "chat.mention", inScope: "[Palenight]", of: customizations)
        #expect(renamedInScope["[Palenight]"]?.objectValue?["chat.mention"] == "#C3E88D")
        #expect(ColorCustomizationsModel.removingScope("[Palenight]", from: customizations)["[Palenight]"] == nil)
    }

    @Test func scopeKeysAndPatterns() {
        #expect(ColorCustomizationsModel.scopeKey(forTheme: "palenight", in: customizations) == "[Palenight]")
        #expect(ColorCustomizationsModel.scopeKey(forTheme: "Nord", in: customizations) == "[Nord]")
        #expect(ColorCustomizationsModel.scopePatterns(in: "[A] [B]") == ["A", "B"])
        #expect(ColorCustomizationsModel.scopePatterns(in: "accent") == nil)
        #expect(ColorCustomizationsModel.pattern("Catppuccin *", matches: "Catppuccin Mocha"))
        #expect(ColorCustomizationsModel.pattern("palenight", matches: "Palenight"))
        #expect(!ColorCustomizationsModel.pattern("Nord", matches: "Nord Light"))
    }
}

@MainActor
@Suite("Settings editor: shared state")
struct SettingsEditorStateTests {
    @Test func paneLinksAndPaletteSearchAskForAdvanced() {
        let editor = SettingsEditorState()
        editor.showInEditor("@pane:messages")
        #expect(editor.requestedPane == .advanced)
        #expect(editor.query == "@pane:messages")
        #expect(editor.focusSearchRequest == 1)

        editor.requestedPane = nil
        editor.openSearch()
        #expect(editor.requestedPane == .advanced)
        // The palette keeps the current search.
        #expect(editor.query == "@pane:messages")
        #expect(editor.focusSearchRequest == 2)
    }

    @Test func sidebarSearchLeavesFocusInTheSidebar() {
        let editor = SettingsEditorState()
        editor.mode = .json
        editor.searchFromSidebar("font")
        #expect(editor.requestedPane == .advanced)
        #expect(editor.mode == .ui)
        #expect(editor.query == "font")
        #expect(editor.focusSearchRequest == 0)
    }

    @Test func unsavedJSONEditsAreLeftToTheJSONView() {
        let editor = SettingsEditorState()
        editor.requestMode(.json)
        editor.hasUnsavedJSON = true
        editor.requestMode(.ui)
        #expect(editor.mode == .json)
        #expect(editor.pendingMode == .ui)
        editor.search("font")
        #expect(editor.mode == .json)
        #expect(editor.query == "font")
        editor.hasUnsavedJSON = false
        editor.requestMode(.ui)
        #expect(editor.mode == .ui)
        #expect(editor.pendingMode == nil)
    }
}
