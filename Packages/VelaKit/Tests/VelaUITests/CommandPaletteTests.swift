// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import Testing
import VelaTheme
@testable import VelaUI

@Suite("Fuzzy matcher")
struct FuzzyMatcherTests {
    private func score(_ query: String, _ target: String) -> Int? {
        FuzzyMatcher.match(query, in: target)?.score
    }

    @Test func matchesSubsequencesIgnoringCaseAndSpaces() throws {
        let match = try #require(FuzzyMatcher.match("tml", in: "View: Toggle Member List"))
        #expect(match.positions == [6, 13, 20])
        #expect(FuzzyMatcher.match("toggle member", in: "View: Toggle Member List") != nil)
        #expect(FuzzyMatcher.match("TOGGLE", in: "View: Toggle Member List") != nil)
    }

    @Test func rejectsWhatIsNotASubsequence() {
        #expect(FuzzyMatcher.match("xyz", in: "View: Toggle Member List") == nil)
        #expect(FuzzyMatcher.match("listmember", in: "View: Toggle Member List") == nil)
        #expect(FuzzyMatcher.match("longer than target", in: "short") == nil)
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(FuzzyMatcher.match("", in: "anything") == FuzzyMatch(score: 0, positions: []))
        #expect(FuzzyMatcher.match("   ", in: "anything")?.score == 0)
    }

    @Test func ignoresDiacritics() throws {
        let match = try #require(FuzzyMatcher.match("rose", in: "Rosé Pine"))
        #expect(match.positions == [0, 1, 2, 3])
    }

    @Test func prefersWordStartsAndPrefixes() throws {
        // Word starts beat letters in the middle of words.
        let wordStarts = try #require(score("tml", "View: Toggle Member List"))
        let scattered = try #require(score("tml", "Theme: Select Theme…"))
        #expect(wordStarts > scattered)

        // A prefix beats the same letters later on.
        let prefix = try #require(score("swi", "#swift"))
        let middle = try #require(score("swi", "#macswitch"))
        #expect(prefix > middle)

        // A contiguous run beats a spread-out match.
        let run = try #require(score("vela", "#vela"))
        let spread = try #require(score("vela", "#very-late"))
        #expect(run > spread)
    }

    @Test func picksTheBestAlignment() throws {
        // Greedy matching would take the "m" in "Theme"; the best alignment
        // uses the word start of "Match".
        let match = try #require(FuzzyMatcher.match("tm", in: "Theme: Toggle Match System Appearance"))
        #expect(match.positions == [7, 14])
    }

    @Test func substringContainment() {
        let haystack = FuzzyMatcher.prepareQuery("nick list")
        #expect(FuzzyMatcher.contains(haystack, FuzzyMatcher.prepareQuery("nicklist")))
        #expect(FuzzyMatcher.contains(haystack, FuzzyMatcher.prepareQuery("List")))
        #expect(!FuzzyMatcher.contains(haystack, FuzzyMatcher.prepareQuery("nl")))
    }
}

@MainActor
@Suite("Palette ranking")
struct PaletteRankerTests {
    private func command(_ id: String, _ category: VelaCommand.Category, _ title: String, keywords: [String] = []) -> VelaCommand {
        VelaCommand(id: id, category: category, title: title, keywords: keywords) {}
    }

    private var commands: [VelaCommand] {
        [
            command("view.toggleMemberList", .view, "Toggle Member List", keywords: ["nick list"]),
            command("theme.select", .theme, "Select Theme…"),
            command("text.bigger", .text, "Bigger"),
            command("buffer.markAllRead", .buffer, "Mark All as Read"),
        ]
    }

    @Test func emptyQueryListsRecentCommandsFirst() {
        let items = PaletteSource.commandItems(commands, history: ["text.bigger", "theme.select"])
        let rows = PaletteRanker.rows(for: items, query: "", list: .commands)
        #expect(rows.map(\.id) == ["text.bigger", "theme.select", "buffer.markAllRead", "view.toggleMemberList"])
        #expect(rows[0].sectionLabel == "recently used")
        #expect(rows[2].sectionLabel == "other commands")
        #expect(rows[2].startsSection)
    }

    @Test func emptyQueryWithoutHistoryIsAlphabetical() {
        let items = PaletteSource.commandItems(commands, history: [])
        let rows = PaletteRanker.rows(for: items, query: "", list: .commands)
        #expect(rows.map(\.item.label.text) == [
            "Buffer: Mark All as Read", "Text: Bigger", "Theme: Select Theme…", "View: Toggle Member List",
        ])
        #expect(rows.allSatisfy { $0.sectionLabel == nil })
    }

    @Test func hidesDisabledAndMenuOnlyCommands() {
        var disabled = command("buffer.close", .buffer, "Close")
        disabled.isEnabled = false
        var menuOnly = command("view.commandPalette", .view, "Command Palette…")
        menuOnly.showsInPalette = false
        let items = PaletteSource.commandItems([disabled, menuOnly] + commands, history: [])
        #expect(!items.contains { $0.id == "buffer.close" || $0.id == "view.commandPalette" })
    }

    @Test func queryRanksAndHighlights() throws {
        let items = PaletteSource.commandItems(commands, history: [])
        let rows = PaletteRanker.rows(for: items, query: "tml", list: .commands)
        let first = try #require(rows.first)
        #expect(first.id == "view.toggleMemberList")
        #expect(first.labelMatches == [6, 13, 20])
    }

    @Test func keywordsMatchAsSubstringsWithoutHighlights() throws {
        let items = PaletteSource.commandItems(commands, history: [])
        let rows = PaletteRanker.rows(for: items, query: "nicklist", list: .commands)
        let first = try #require(rows.first)
        #expect(first.id == "view.toggleMemberList")
        #expect(first.labelMatches.isEmpty)
        // Scattered letters of a keyword don't count.
        #expect(PaletteRanker.rows(for: items, query: "nkls", list: .commands).isEmpty)
    }

    @Test func themesAreGroupedDarkThenLightWithCurrentPreselected() {
        let themes = [
            ThemeInfo(id: "lighter", name: "Lighter", kind: .light, source: .builtIn, url: URL(fileURLWithPath: "/lighter.json")),
            ThemeInfo(id: "nord", name: "Nord", kind: .dark, source: .builtIn, url: URL(fileURLWithPath: "/nord.json")),
            ThemeInfo(id: "palenight", name: "Palenight", kind: .dark, source: .builtIn, url: URL(fileURLWithPath: "/palenight.json")),
        ]
        let items = PaletteSource.themeItems(themes, currentID: "palenight")
        let rows = PaletteRanker.rows(for: items, query: "", list: .themes)
        #expect(rows.map(\.id) == ["nord", "palenight", "lighter"])
        #expect(rows[0].sectionLabel == "dark themes")
        #expect(rows[2].sectionLabel == "light themes")
        #expect(rows[2].startsSection)
        #expect(PaletteRanker.initialSelection(in: rows, list: .themes, query: "") == 1)

        let filtered = PaletteRanker.rows(for: items, query: "e", list: .themes)
        #expect(filtered.map(\.id) == ["palenight", "lighter"])
        #expect(filtered[0].sectionLabel == "dark themes")
        #expect(filtered[1].sectionLabel == "light themes")
    }
}

@Suite("Shortcut glyphs")
struct ShortcutGlyphTests {
    @Test func modifiersInMenuOrder() {
        let shortcut = KeyboardShortcut("p", modifiers: [.command, .shift])
        #expect(ShortcutGlyphs.glyphs(for: shortcut) == ["⇧", "⌘", "P"])
        let all = KeyboardShortcut(.upArrow, modifiers: [.command, .shift, .option, .control])
        #expect(ShortcutGlyphs.string(for: all) == "⌃⌥⇧⌘↑")
        #expect(ShortcutGlyphs.spoken(shortcut) == "Shift Command P")
    }

    /// ⇧⌘[ is written ⌘{ (what the keys type) and shown as the keys.
    @Test func shiftedBracketsShowAsTheKeys() {
        let previous = VelaCommandCatalog.Shortcuts.previousTab
        #expect(ShortcutGlyphs.glyphs(for: previous) == ["⇧", "⌘", "["])
        #expect(ShortcutGlyphs.string(for: VelaCommandCatalog.Shortcuts.nextTab) == "⇧⌘]")
        #expect(ShortcutGlyphs.spoken(previous) == "Shift Command Left Bracket")
        #expect(ShortcutGlyphs.string(for: VelaCommandCatalog.Shortcuts.nextNetwork) == "⌃⌘]")
        #expect(ShortcutGlyphs.string(for: VelaCommandCatalog.Shortcuts.moveTabBack) == "⌥⇧⌘[")
        #expect(ShortcutGlyphs.string(for: VelaCommandCatalog.Shortcuts.moveNetworkForward) == "⌃⌥⌘]")
    }
}
