// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaTheme

@Suite("ThemeStore")
@MainActor
struct ThemeStoreTests {
    let directory = TemporaryDirectory()

    private func makeStore(
        settings: ThemeSettings = .default,
        appearance: ThemeKind = .dark
    ) -> ThemeStore {
        let store = ThemeStore(userThemesDirectory: directory.url, settings: settings, systemAppearance: appearance)
        store.reload()
        return store
    }

    @Test func listsBuiltInsSorted() {
        let store = makeStore()
        #expect(store.themes.count == BuiltInThemeTests.expected.count)
        #expect(store.themes.allSatisfy { $0.source == .builtIn })
        let names = store.themes.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(store.loadErrors.isEmpty)
        #expect(store.info(for: "palenight")?.name == "Palenight")
        #expect(store.info(for: "  sandy beach ")?.id == "sandy-beach")
    }

    @Test func followsSystemAppearance() {
        let store = makeStore(appearance: .dark)
        #expect(store.current.name == "Palenight")
        #expect(store.currentInfo?.id == "palenight")
        store.updateSystemAppearance(.light)
        #expect(store.current.name == "Lighter")
        #expect(store.current.kind == .light)

        store.settings.preferredDarkTheme = "nord"
        store.settings.preferredLightTheme = "SOLARIZED LIGHT"
        #expect(store.current.name == "Solarized Light")
        store.updateSystemAppearance(.dark)
        #expect(store.current.name == "Nord")
    }

    @Test func fixedThemeIgnoresSystemAppearance() {
        let settings = ThemeSettings(themeName: "Vela Paper", followSystemAppearance: false)
        let store = makeStore(settings: settings, appearance: .dark)
        #expect(store.current.name == "Vela Paper")
        store.updateSystemAppearance(.light)
        store.updateSystemAppearance(.dark)
        #expect(store.current.name == "Vela Paper")
        store.settings.themeName = "dracula"
        #expect(store.current.name == "Dracula")
    }

    @Test func unknownThemeFallsBackToDefaultForKind() {
        let store = makeStore(settings: ThemeSettings(preferredLightTheme: "Does Not Exist"), appearance: .light)
        #expect(store.current.name == "Lighter")
    }

    @Test func colorCustomizationsApplyGloballyAndPerTheme() throws {
        let store = makeStore(appearance: .dark)
        store.settings.colorCustomizations = [
            "chat.timestamp": "#123456",
            "[Palenight]": .object(["accent": "#FF0000"]),
            "[Lighter]": .object(["accent": "#00FF00"]),
            "chat.bogus": "#FFFFFF",
        ]
        #expect(store.current.color(ThemeKey.chatTimestamp).hex == "#123456")
        #expect(store.current.color(ThemeKey.accent).hex == "#FF0000")
        #expect(store.customizationProblems.count == 1)
        store.updateSystemAppearance(.light)
        #expect(store.current.color(ThemeKey.accent).hex == "#00FF00")
        #expect(store.current.color(ThemeKey.chatTimestamp).hex == "#123456")
        let nord = try #require(store.info(for: "Nord"))
        #expect(store.resolvedTheme(for: nord)?.color(ThemeKey.chatTimestamp).hex == "#123456")
        #expect(store.resolvedTheme(for: nord)?.color(ThemeKey.accent).hex == "#88C0D0")
    }

    @Test func saveLoadAndShadowUserThemes() throws {
        let store = makeStore()
        var definition = ThemeDefinition(
            name: "My Night",
            type: .dark,
            include: "Palenight",
            colors: ["accent": "#FF8800"]
        )
        let info = try store.saveUserTheme(definition)
        #expect(info.source == .user)
        #expect(info.id == "my-night")
        #expect(FileManager.default.fileExists(atPath: info.url.path))
        #expect(try store.definition(for: info).include == "Palenight")
        let resolved = try #require(store.resolvedTheme(for: info))
        #expect(resolved.color(ThemeKey.accent).hex == "#FF8800")
        #expect(resolved.color(ThemeKey.windowBackground).hex == "#292D3E", "included from Palenight")
        #expect(try store.flattenedDefinition(for: info).colors["window.background"] == "#292D3E")

        // Saving again with the same name overwrites the same file.
        definition.colors["accent"] = "#00FF88"
        let again = try store.saveUserTheme(definition)
        #expect(again.url == info.url)
        #expect(store.themes.filter { $0.name == "My Night" }.count == 1)

        // A user file with a built-in's id replaces it and may include it by name.
        _ = try directory.write(##"{"name": "Dracula", "type": "dark", "include": "Dracula", "colors": {"accent": "#00FF00"}}"##, to: "dracula.json")
        store.reloadUserThemes()
        let dracula = try #require(store.info(for: "dracula"))
        #expect(dracula.source == .user)
        #expect(store.themes.filter { $0.name == "Dracula" }.count == 1)
        #expect(store.resolvedTheme(for: dracula)?.color(ThemeKey.chatBackground).hex == "#282A36")
        #expect(store.resolvedTheme(for: dracula)?.color(ThemeKey.accent).hex == "#00FF00")
        #expect(store.loadErrors.isEmpty)

        try store.deleteUserTheme(again)
        #expect(store.info(for: "my-night") == nil)
        let builtIn = try #require(store.info(for: "nord"))
        #expect(throws: ThemeError.notAUserTheme("Nord")) { try store.deleteUserTheme(builtIn) }
    }

    @Test func brokenFilesKeepTheLastGoodVersion() throws {
        let store = makeStore(settings: ThemeSettings(themeName: "Live", followSystemAppearance: false))
        let file = try directory.write(##"{"name": "Live", "type": "dark", "colors": {"accent": "#111111"}}"##, to: "live.json")
        store.reloadUserThemes()
        #expect(store.current.name == "Live")
        #expect(store.current.color(ThemeKey.accent).hex == "#111111")

        try Data(##"{"name": "Live", "type": "dark", "colors": {"accent": "#2222"##.utf8).write(to: file)
        store.reloadUserThemes()
        #expect(store.loadErrors[file] != nil)
        #expect(store.current.color(ThemeKey.accent).hex == "#111111", "last good version stays active")
        #expect(store.info(for: "live") != nil)

        try Data(##"{"name": "Live", "type": "dark", "colors": {"accent": "#333333"}}"##.utf8).write(to: file)
        store.reloadUserThemes()
        #expect(store.loadErrors[file] == nil)
        #expect(store.current.color(ThemeKey.accent).hex == "#333333")

        // A file that has never parsed is reported but not listed.
        let broken = try directory.write("{ nope", to: "broken.json")
        store.reloadUserThemes()
        #expect(store.loadErrors[broken] != nil)
        #expect(store.info(for: "broken") == nil)

        // Missing includes are reported up front.
        let orphan = try directory.write(##"{"name": "Orphan", "type": "dark", "include": "Nowhere"}"##, to: "orphan.json")
        store.reloadUserThemes()
        #expect(store.loadErrors[orphan]?.contains("Nowhere") == true)
    }

    @Test func liveReloadThroughFSEvents() async throws {
        let store = ThemeStore(
            userThemesDirectory: directory.url,
            settings: ThemeSettings(themeName: "Watched", followSystemAppearance: false),
            systemAppearance: .dark
        )
        store.start()
        defer { store.stop() }
        #expect(store.current.name == "Palenight")

        _ = try directory.write(##"{"name": "Watched", "type": "light", "colors": {"accent": "#ABCDEF"}}"##, to: "watched.json")
        let deadline = Date().addingTimeInterval(10)
        while store.current.name != "Watched", Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.current.name == "Watched")
        #expect(store.current.color(ThemeKey.accent).hex == "#ABCDEF")
    }

    @Test func importsVSCodeVelaAndVSIX() throws {
        let store = makeStore()
        // Name clashes with the built-in Nord, so it gets a suffix.
        let nord = try store.importTheme(from: Fixtures.url("vscode/nord-color-theme.json"))
        #expect(nord.map(\.name) == ["Nord (Imported)"])
        #expect(nord.first?.id == "nord-imported")
        #expect(nord.first?.source == .user)
        let written = try ThemeLoader.load(contentsOf: try #require(nord.first).url)
        #expect(written.colors["chat.background"] == "#2E3440")
        #expect(written.schema == ThemeDefinition.schemaURL)

        let again = try store.importTheme(from: Fixtures.url("vscode/nord-color-theme.json"))
        #expect(again.map(\.name) == ["Nord (Imported 2)"])

        let vsix = try store.importTheme(from: Fixtures.url("vscode/lantern-themes.vsix"))
        #expect(vsix.map(\.name) == ["Lantern Dark", "Lantern Light"])
        #expect(vsix.map(\.kind) == [.dark, .light])

        // A Vela theme file is copied as-is (with a unique name).
        let elsewhere = TemporaryDirectory()
        let velaFile = try elsewhere.write(##"{"name": "Paper Copy", "type": "light", "include": "Vela Paper"}"##, to: "paper-copy.jsonc")
        let vela = try store.importTheme(from: velaFile)
        #expect(vela.first?.name == "Paper Copy")
        #expect(try store.definition(for: try #require(vela.first)).include == "Vela Paper")

        #expect(throws: ThemeError.unsupportedFile("notes.txt")) {
            try store.importTheme(from: directory.url.appendingPathComponent("notes.txt"))
        }
        #expect(store.loadErrors.isEmpty)
    }

    @Test func draftPreviewsLive() throws {
        let store = makeStore(appearance: .dark)
        store.draft = ThemeDefinition(name: "Draft", type: .light, include: "Lighter", colors: ["accent": "#FF00FF"])
        #expect(store.current.name == "Draft")
        #expect(store.current.kind == .light)
        #expect(store.current.color(ThemeKey.accent).hex == "#FF00FF")
        #expect(store.currentInfo == nil)

        store.draft?.colors["accent"] = "#00FFFF"
        #expect(store.current.color(ThemeKey.accent).hex == "#00FFFF")

        store.draft?.include = "Missing"
        #expect(store.draftError?.contains("Missing") == true)
        #expect(store.current.color(ThemeKey.accent).hex == "#00FFFF", "keeps the last good preview")

        store.draft = nil
        #expect(store.draftError == nil)
        #expect(store.current.name == "Palenight")
    }

    @Test func slugsAndUniqueness() {
        #expect(ThemeStore.slug("Rosé Pine Moon") == "rose-pine-moon")
        #expect(ThemeStore.slug("  Tokyo Night (Storm)!! ") == "tokyo-night-storm")
        #expect(ThemeStore.slug("☃︎") == "theme")
        #expect(ThemeStore.uniqueID("nord", taken: ["nord", "nord-2"]) == "nord-3")
        #expect(ThemeStore.uniqueName("Nord", taken: ["nord"]) == "Nord (Imported)")
    }
}
