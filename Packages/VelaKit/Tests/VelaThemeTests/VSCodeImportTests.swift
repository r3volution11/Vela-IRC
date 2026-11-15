// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaTheme

@Suite("VS Code import")
struct VSCodeImportTests {
    private func importFixture(_ name: String) throws -> (ThemeDefinition, ResolvedTheme) {
        let definition = try VSCodeThemeImporter.importTheme(data: Fixtures.data("vscode/\(name)"), fileName: name)
        try definition.validate()
        return (definition, try resolve(definition))
    }

    @Test func nord() throws {
        // Nord's file is real-world JSONC (it has a block comment).
        let (definition, theme) = try importFixture("nord-color-theme.json")
        #expect(definition.name == "Nord")
        #expect(definition.type == .dark)
        #expect(definition.schema == ThemeDefinition.schemaURL)
        #expect(definition.description?.contains("nord-color-theme.json") == true)

        #expect(theme.color(ThemeKey.chatBackground).hex == "#2E3440")
        #expect(theme.color(ThemeKey.chatForeground).hex == "#D8DEE9")
        #expect(theme.color(ThemeKey.sidebarBackground).hex == "#2E3440")
        #expect(theme.color(ThemeKey.sidebarActiveBackground).hex == "#88C0D0")
        #expect(theme.color(ThemeKey.sidebarActiveForeground).hex == "#2E3440")
        #expect(theme.color(ThemeKey.sidebarBadgeBackground).hex == "#88C0D0")
        #expect(theme.color(ThemeKey.railActiveIndicator).hex == "#88C0D0")
        #expect(theme.color(ThemeKey.accent).hex == "#88C0D0")
        #expect(theme.color(ThemeKey.accentForeground).hex == "#2E3440")
        #expect(theme.color(ThemeKey.chatLink).hex == "#88C0D0")
        #expect(theme.color(ThemeKey.inputBackground).hex == "#3B4252")
        #expect(theme.color(ThemeKey.chatSelectionBackground).hex == "#434C5ECC")
        #expect(theme.color(ThemeKey.chatHighlightBackground).hex == "#88C0D033")
        // editorGroup.border is "#3b425201" (invisible): the next candidate wins.
        #expect(theme.color(ThemeKey.paneDivider).hex == "#3B4252")
        // button.background "#88c0d0ee" is flattened to an opaque fill.
        #expect(theme.color(ThemeKey.buttonBackground).alpha == 1)

        // ANSI → mIRC: 0 bright white, 1 black, 4 bright red, 5 red, 11 bright cyan, 14 bright black.
        #expect(theme.ircColor(0)?.hex == "#ECEFF4")
        #expect(theme.ircColor(1)?.hex == "#3B4252")
        #expect(theme.ircColor(2)?.hex == "#81A1C1")
        #expect(theme.ircColor(4)?.hex == "#BF616A")
        #expect(theme.ircColor(5)?.hex == "#BF616A")
        #expect(theme.ircColor(11)?.hex == "#8FBCBB")
        #expect(theme.ircColor(14)?.hex == "#4C566A")
        #expect(theme.ircColor(15)?.hex == "#E5E9F0")
        #expect(theme.ircColor(16)?.hex == "#470000")

        let nicks = try #require(definition.nickColors)
        #expect(nicks.count >= 6)
        let background = theme.color(ThemeKey.chatBackground)
        for nick in theme.nickColors {
            #expect(nick.contrastRatio(against: background) >= 3.5)
            #expect(nick.chroma >= 0.04, "nick colors must not be greys")
        }
    }

    @Test func tokyoNight() throws {
        let (definition, theme) = try importFixture("tokyo-night-color-theme.json")
        #expect(definition.name == "Tokyo Night")
        #expect(definition.author == "Enkia")
        #expect(theme.kind == .dark)
        #expect(theme.color(ThemeKey.chatBackground).hex == "#1A1B26")
        #expect(theme.color(ThemeKey.sidebarBackground).hex == "#16161E")
        #expect(theme.color(ThemeKey.accent).hex == "#3D59A1")
        #expect(theme.color(ThemeKey.accentForeground).hex == "#FFFFFF")
        let background = theme.color(ThemeKey.chatBackground)
        // The badge accent is too dark to read as text, so accentText is lifted.
        #expect(theme.color(ThemeKey.accentText).contrastRatio(against: background) >= 4.5)
        #expect(theme.color(ThemeKey.chatSelfNick).contrastRatio(against: background) >= 4.5)
        // editorLineNumber.foreground (#363b54) and descriptionForeground
        // (#515670) are too dim; Vela derives readable values instead.
        #expect(definition.colors["chat.timestamp"] == nil)
        #expect(definition.colors["chat.secondaryForeground"] == nil)
        #expect(theme.color(ThemeKey.chatTimestamp).contrastRatio(against: background) >= 2.5)
        // errorForeground is grey in Tokyo Night; editorError wins.
        #expect(theme.color(ThemeKey.statusError).hex == "#DB4B4B")
        #expect(theme.ircColor(4)?.hex == "#F7768E")
        #expect(theme.ircColor(0)?.hex == "#ACB0D0")
        #expect((definition.nickColors?.count ?? 0) >= 6)
    }

    @Test func jsoncWithoutTypeOrTerminalColors() throws {
        let (definition, theme) = try importFixture("harbor-color-theme.jsonc")
        #expect(definition.name == "Harbor")
        #expect(definition.type == .dark, "inferred from the editor background")
        #expect(theme.color(ThemeKey.chatBackground).hex == "#1B2430")
        #expect(theme.color(ThemeKey.accent).hex == "#F2A65A")
        #expect(theme.color(ThemeKey.accentForeground).hex == "#1B2430")
        #expect(theme.color(ThemeKey.scrollbarThumb).hex == "#FFFFFF22")
        #expect(definition.colors["chat.timestamp"] == nil, "#3a4656 is too dim for timestamps")
        #expect(definition.ircColors == nil, "no terminal colors to map")

        // Nick palette derived from distinct, saturated tokenColors.
        let nicks = try #require(definition.nickColors).map { ThemeColor(hex: $0)! }
        #expect(nicks.count >= 6)
        #expect(!nicks.contains(hex("#5C6B7E")), "comment grey is not a nick color")
        #expect(nicks.first == hex("#A3D9A5") || nicks.first == hex("#F2A65A"), "most used first")
        let background = theme.color(ThemeKey.chatBackground)
        for nick in nicks { #expect(nick.contrastRatio(against: background) >= 3.5) }
    }

    @Test func lightThemeTypeFromLuminance() throws {
        let json = ##"{"name": "Paperish", "colors": {"editor.background": "#FDFDFD", "editor.foreground": "#222222"}}"##
        let definition = try VSCodeThemeImporter.importTheme(data: Data(json.utf8), fileName: "paperish.json")
        #expect(definition.type == .light)
        let theme = try resolve(definition)
        #expect(theme.color(ThemeKey.chatForeground).hex == "#222222")
    }

    @Test func nameFromFileWhenMissing() throws {
        let json = ##"{"type": "dark", "colors": {"editor.background": "#000000"}}"##
        let definition = try VSCodeThemeImporter.importTheme(data: Data(json.utf8), fileName: "night-owl-color-theme.json")
        #expect(definition.name == "Night Owl")
        #expect(VSCodeThemeImporter.displayName(forFile: "my_cool_theme.json") == "My Cool Theme")
    }

    @Test func rejectsNonThemes() {
        #expect(throws: ThemeError.notAVSCodeTheme("package.json")) {
            try VSCodeThemeImporter.importTheme(data: Data(##"{"name": "x", "version": "1"}"##.utf8), fileName: "package.json")
        }
        #expect(throws: ThemeError.self) {
            try VSCodeThemeImporter.importTheme(data: Data("not json".utf8), fileName: "x.json")
        }
    }

    @Test func detectsVSCodeVersusVela() throws {
        #expect(VSCodeThemeImporter.looksLikeVSCodeTheme(try JSONC.value(from: Fixtures.data("vscode/nord-color-theme.json"))))
        #expect(VSCodeThemeImporter.looksLikeVSCodeTheme(try JSONC.value(from: Fixtures.data("vscode/harbor-color-theme.jsonc"))))
        let palenight = try Data(contentsOf: ThemeLoader.builtInThemesDirectory.appendingPathComponent("palenight.json"))
        #expect(!VSCodeThemeImporter.looksLikeVSCodeTheme(try JSONC.value(from: palenight)))
        let bare: JSONValue = .object(["name": "x", "type": "dark", "colors": .object(["chat.background": "#000000"])])
        #expect(!VSCodeThemeImporter.looksLikeVSCodeTheme(bare))
        let vs: JSONValue = .object(["name": "x", "type": "vs-dark", "colors": .object(["focusBorder": "#000000"])])
        #expect(VSCodeThemeImporter.looksLikeVSCodeTheme(vs))
    }

    @Test func vsix() throws {
        let definitions = try VSCodeThemeImporter.importVSIX(at: Fixtures.url("vscode/lantern-themes.vsix"))
        // The .tmTheme contribution is skipped.
        #expect(definitions.map(\.name) == ["Lantern Dark", "Lantern Light"])
        #expect(definitions.allSatisfy { $0.author == "Vela Test Suite" })

        let dark = definitions[0]
        #expect(dark.type == .dark, "from uiTheme")
        let darkTheme = try resolve(dark)
        // Own value beats the included base; base values fill the rest.
        #expect(darkTheme.color(ThemeKey.chatBackground).hex == "#1E1A16")
        #expect(darkTheme.color(ThemeKey.sidebarBackground).hex == "#17130F")
        #expect(darkTheme.color(ThemeKey.chatForeground).hex == "#EDE3D6")
        #expect(darkTheme.color(ThemeKey.accent).hex == "#E0A040")
        #expect(darkTheme.ircColor(4)?.hex == "#F08070")
        #expect(darkTheme.ircColor(0)?.hex == "#FFF8EE")

        let light = definitions[1]
        #expect(light.type == .light, "from uiTheme")
        let lightTheme = try resolve(light)
        #expect(lightTheme.color(ThemeKey.accent).hex == "#B0601E")
        #expect(lightTheme.color(ThemeKey.accentForeground).hex == "#FFFFFF")
        #expect(lightTheme.color(ThemeKey.chatLink).hex == "#2A6CA8")
    }

    @Test func vsixErrors() throws {
        let directory = TemporaryDirectory()
        let bogus = try directory.write("not a zip", to: "bogus.vsix")
        #expect(throws: ThemeError.self) { try VSCodeThemeImporter.importVSIX(at: bogus) }
    }

    @Test func pathNormalization() {
        #expect(VSCodeThemeImporter.normalize("extension/./themes/../themes/a.json") == "extension/themes/a.json")
        #expect(VSCodeThemeImporter.normalize("extension//themes/a.json") == "extension/themes/a.json")
    }
}
