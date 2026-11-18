// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaTheme

@Suite("Theme problems")
struct ThemeProblemTests {
    private func checked(_ json: String) throws -> ThemeLoader.Checked {
        try ThemeLoader.decodeChecked(Data(json.utf8))
    }

    private func problem(_ problems: [ThemeProblem], at path: String) throws -> ThemeProblem {
        try #require(problems.first { $0.path == path }, "no problem at \(path) in \(problems.map(\.path))")
    }

    @Test func cleanThemeHasNoProblems() throws {
        let result = try checked("""
        { "$schema": "x", "name": "Clean", "type": "dark", "author": "Me", "description": "Fine.",
          "include": "Palenight", "vibrancy": "sidebar",
          "colors": { "accent": "#FF8800" }, "nickColors": ["#FF0000"], "ircColors": { "4": "#FF0000" } }
        """)
        #expect(result.problems.isEmpty)
        #expect(result.definition.vibrancy == .sidebar)
    }

    @Test func unknownTopLevelKeys() throws {
        let problems = try checked("""
        { "name": "Typos", "type": "dark", "fontSize": 14, "spacing": 2, "autor": "Me", "accent": "#FFF", "wibble": 1 }
        """).problems
        #expect(problems.allSatisfy { $0.kind == .unknownKey && $0.severity == .warning })

        let fontSize = try problem(problems, at: "fontSize")
        #expect(fontSize.message.hasPrefix("“fontSize” isn't a theme key, so it's ignored."))
        #expect(fontSize.message.contains("Themes only contain colors"))
        #expect(try problem(problems, at: "spacing").message.contains("Themes only contain colors"))

        let author = try problem(problems, at: "autor")
        #expect(author.suggestion == "author")
        #expect(author.message.contains("Did you mean “author”?"))

        // A color token at the top level belongs in "colors".
        #expect(try problem(problems, at: "accent").message.contains("Color tokens go inside \"colors\""))

        let wibble = try problem(problems, at: "wibble")
        #expect(wibble.suggestion == nil)
        #expect(!wibble.message.contains("Themes only contain colors"))
    }

    @Test func unknownTokensSuggestTheClosestToken() throws {
        let result = try checked("""
        { "name": "Typos", "type": "dark",
          "colors": { "sidebar.backgroud": "#111111", "Chat.Background": "#222222", "editor.background": "#000000", "accent": "#FF8800" } }
        """)
        let problems = result.problems
        #expect(problems.count == 3)
        #expect(problems.allSatisfy { $0.kind == .unknownToken && $0.severity == .warning })

        let sidebar = try problem(problems, at: "colors.sidebar.backgroud")
        #expect(sidebar.suggestion == "sidebar.background")
        #expect(sidebar.message == "“colors.sidebar.backgroud” isn't a theme color token, so it's ignored. Did you mean “sidebar.background”?")
        #expect(try problem(problems, at: "colors.Chat.Background").suggestion == "chat.background")
        // Sharing ".background" with many tokens isn't enough for a suggestion.
        #expect(try problem(problems, at: "colors.editor.background").suggestion == nil)

        // The theme still loads, and the token it does know is used.
        let theme = try resolve(result.definition)
        #expect(theme.color(ThemeKey.accent).hex == "#FF8800")
    }

    @Test func badVibrancyIsSkippedWithAFriendlyError() throws {
        let result = try checked("""
        { "name": "Glassy", "type": "dark", "vibrancy": "glass", "colors": { "accent": "#FF8800" } }
        """)
        #expect(result.definition.vibrancy == nil)
        let problem = try problem(result.problems, at: "vibrancy")
        #expect(problem.kind == .invalidVibrancy)
        #expect(problem.severity == .error)
        #expect(problem.message == "“vibrancy”: “glass” isn't a vibrancy value, so it's ignored. Use \"none\", \"sidebar\" or \"window\".")
        // No raw decoding error, and the rest of the theme loads.
        #expect(!problem.message.contains("Cannot initialize"))
        #expect(try resolve(result.definition).vibrancy == .none)
    }

    @Test func vibrancyInTheWrongCaseOrTypeIsReported() throws {
        let capitalized = try checked(#"{ "name": "A", "type": "dark", "vibrancy": "Sidebar" }"#)
        #expect(capitalized.definition.vibrancy == nil)
        let problem = try problem(capitalized.problems, at: "vibrancy")
        #expect(problem.suggestion == "sidebar")
        #expect(problem.message.contains("Did you mean \"sidebar\"?"))

        let number = try checked(#"{ "name": "B", "type": "dark", "vibrancy": 1 }"#)
        #expect(number.definition.vibrancy == nil)
        #expect(try self.problem(number.problems, at: "vibrancy").message.contains("must be a string"))
    }

    @Test func fatalErrorsStillThrow() {
        // Problems are for what can be skipped; a broken color or missing
        // type still stops the theme, as before.
        #expect(throws: ThemeError.invalidColor(key: "colors.accent", value: "#GGG")) {
            try ThemeLoader.decodeChecked(Data(##"{ "name": "A", "type": "dark", "colors": { "accent": "#GGG" } }"##.utf8))
        }
        #expect(throws: ThemeError.missingField("type")) {
            try ThemeLoader.decodeChecked(Data(#"{ "name": "A" }"#.utf8))
        }
    }

    @Test func definitionCheckFindsUnknownTokensOnly() {
        let definition = ThemeDefinition(name: "Draft", type: .dark, colors: ["chat.forground": "#FFFFFF", "accent": "#FF0000"])
        let problems = ThemeProblems.check(definition)
        #expect(problems.map(\.path) == ["colors.chat.forground"])
        #expect(problems.first?.suggestion == "chat.foreground")
    }

    @Test func builtInThemesHaveNoProblems() throws {
        for url in ThemeLoader.themeFiles(in: ThemeLoader.builtInThemesDirectory) {
            let problems = try ThemeLoader.loadChecked(contentsOf: url).problems
            #expect(problems.isEmpty, "\(url.lastPathComponent): \(problems)")
        }
    }

    @Test func customizationProblemsSuggestTokens() {
        let problems = ThemeOverrides.problems(in: [
            "sidebar.backgroud": "#000000",
            "[Nord]": .object(["vibrancy": "glass"]),
        ])
        #expect(problems.contains("“sidebar.backgroud” is not a theme color token, so it's ignored. Did you mean “sidebar.background”?"))
        #expect(problems.contains("“[Nord].vibrancy”: “glass” isn't a vibrancy value, so it's ignored. Use \"none\", \"sidebar\" or \"window\"."))
    }
}

@Suite("Theme problems in the store")
@MainActor
struct ThemeStoreProblemTests {
    let directory = TemporaryDirectory()

    @Test func storeReportsProblemsAndStillLoadsTheTheme() throws {
        let url = try directory.write("""
        {
          "name": "Harbor",
          "type": "dark",
          "author": "  Someone  ",
          "description": "Blue-grey surfaces.",
          "font": "Menlo",
          "vibrancy": "glass",
          "colors": { "window.background": "#1E2630", "chat.forground": "#FFFFFF" }
        }
        """, to: "harbor.json")
        let store = ThemeStore(userThemesDirectory: directory.url, settings: ThemeSettings(themeName: "Harbor", followSystemAppearance: false))
        store.reload()

        let info = try #require(store.info(for: "Harbor"))
        #expect(store.loadErrors[url] == nil)
        #expect(store.current.name == "Harbor")
        #expect(store.current.color(ThemeKey.windowBackground).hex == "#1E2630")
        #expect(store.problems(for: info).map(\.path) == ["font", "vibrancy", "colors.chat.forground"])
        #expect(store.loadProblems.keys.map(\.lastPathComponent) == ["harbor.json"])

        // Author and description travel to the picker, trimmed.
        #expect(info.author == "Someone")
        #expect(info.description == "Blue-grey surfaces.")

        // Fixing the file clears the problems.
        _ = try directory.write(#"{ "name": "Harbor", "type": "dark" }"#, to: "harbor.json")
        store.reload()
        #expect(store.loadProblems.isEmpty)
        #expect(store.info(for: "Harbor")?.author == nil)
    }

    @Test func builtInsCarryAuthorAndDescription() throws {
        let store = ThemeStore(userThemesDirectory: directory.url)
        store.reload()
        let palenight = try #require(store.info(for: "Palenight"))
        #expect(palenight.author == "Vela")
        #expect(palenight.description?.isEmpty == false)
        #expect(store.loadProblems.isEmpty)
    }
}
