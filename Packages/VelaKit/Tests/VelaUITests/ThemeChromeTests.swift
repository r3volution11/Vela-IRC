// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Testing
import VelaCore
import VelaStore
import VelaTheme
@testable import VelaUI

@MainActor
@Suite("Theme chrome")
struct ThemeChromeTests {
    private func theme(_ colors: [String: String], vibrancy: ThemeVibrancy? = nil) throws -> ResolvedTheme {
        try ThemeResolver.resolve(
            ThemeDefinition(name: "Test", type: .dark, colors: colors, vibrancy: vibrancy),
            id: "test",
            includeLoader: { _ in nil },
            overrides: ThemeOverrides()
        )
    }

    @Test func scrollerThumbUsesTheScrollbarTokens() throws {
        let theme = try theme(["scrollbar.thumb": "#11223380", "scrollbar.thumbHover": "#445566CC"])
        #expect(ThemedScroller.thumbColor(in: theme, isHovering: false).hex == "#11223380")
        #expect(ThemedScroller.thumbColor(in: theme, isHovering: true).hex == "#445566CC")

        let scroller = ThemedScroller()
        scroller.apply(theme)
        #expect(scroller.thumbColor == ThemeColor(hex: "#11223380")!.nsColor)
        #expect(scroller.thumbHoverColor == ThemeColor(hex: "#445566CC")!.nsColor)
        // Overlay scroll bars stay on for the subclass.
        #expect(ThemedScroller.isCompatibleWithOverlayScrollers)
    }

    @Test func scrollerThumbDefaultsFollowTheText() throws {
        let theme = try theme(["window.foreground": "#FFFFFF"])
        #expect(ThemedScroller.thumbColor(in: theme, isHovering: false) == ThemeColor.white.withAlpha(0.2))
        #expect(ThemedScroller.thumbColor(in: theme, isHovering: true) == ThemeColor.white.withAlpha(0.35))
    }

    @Test func primaryButtonsHover() {
        #expect(ThemedButtonStyle.fillKey(prominent: true, isHovering: false) == ThemeKey.buttonBackground)
        #expect(ThemedButtonStyle.fillKey(prominent: true, isHovering: true) == ThemeKey.buttonHoverBackground)
        #expect(ThemedButtonStyle.fillKey(prominent: false, isHovering: true) == ThemeKey.buttonSecondaryBackground)
    }

    @Test func schematicFollowsTheCollapsedSidebar() {
        let settings = AppModel.demo().settings
        #expect(LayoutSchematicConfig(settings: settings).sidebarCollapsed == false)
        settings[.sidebarCollapsed] = true
        #expect(LayoutSchematicConfig(settings: settings).sidebarCollapsed)
        #expect(LayoutSchematicConfig(settings: settings, overrides: ["sidebar.collapsed": false]).sidebarCollapsed == false)
    }

    /// Every token the registry promises is drawn somewhere in the app,
    /// except the ones documented as not drawn yet.
    @Test func everyTokenIsDrawn() throws {
        let notDrawnYet: Set<String> = [ThemeKey.chatFindMatchBackground]
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let keyFile = try String(contentsOf: sources.appendingPathComponent("VelaTheme/ThemeKey.swift"), encoding: .utf8)
        // `public static let windowBorder = "window.border"` → constant name by token.
        var constants: [String: String] = [:]
        let pattern = try NSRegularExpression(pattern: #"public static let (\w+) = "([^"]+)""#)
        for match in pattern.matches(in: keyFile, range: NSRange(keyFile.startIndex..., in: keyFile)) {
            let name = String(keyFile[Range(match.range(at: 1), in: keyFile)!])
            let key = String(keyFile[Range(match.range(at: 2), in: keyFile)!])
            constants[key] = name
        }
        // The app's views, without the previews (which draw every token
        // whether the app does or not).
        let ui = sources.appendingPathComponent("VelaUI")
        var text = ""
        let files = FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift", file.lastPathComponent != "LayoutSchematic.swift" else { continue }
            text += try String(contentsOf: file, encoding: .utf8)
        }
        for token in ThemeRegistry.tokens where !notDrawnYet.contains(token.key) {
            let name = try #require(constants[token.key], "\(token.key) has no ThemeKey constant")
            #expect(text.contains("ThemeKey.\(name)"), "\(token.key) isn't drawn anywhere in VelaUI")
        }
        #expect(ThemeRegistry.token(ThemeKey.chatFindMatchBackground)?.description.contains("not drawn") == true)
    }
}

@MainActor
@Suite("Demo themes folder")
struct DemoThemesDirectoryTests {
    @Test func demoGetsAFreshEmptyTemporaryFolder() throws {
        let first = DemoArguments.themesDirectory(for: ["Vela", "--demo"])
        let second = DemoArguments.themesDirectory(for: ["Vela", "--demo"])
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        #expect(first != second)
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        #expect(first.standardizedFileURL.path.hasPrefix(temporary))
        #expect(first.lastPathComponent.hasPrefix("VelaDemo-Themes-"))
        #expect(!first.path.contains("Application Support"))
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(ThemeLoader.themeFiles(in: first).isEmpty)
    }

    @Test func themesDirCopiesThemeFilesAndLeavesTheSourceAlone() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("VelaUITests-themes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        try Data(#"{ "name": "Glass", "type": "dark", "vibrancy": "sidebar" }"#.utf8)
            .write(to: source.appendingPathComponent("glass.json"))
        try Data("notes".utf8).write(to: source.appendingPathComponent("README.txt"))

        let directory = DemoArguments.themesDirectory(for: ["Vela", "--demo", "--themes-dir", source.path])
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(directory != source)
        #expect(ThemeLoader.themeFiles(in: directory).map(\.lastPathComponent) == ["glass.json"])

        // The store reads the copy, and writing (as the editor would) leaves the source untouched.
        let store = ThemeStore(userThemesDirectory: directory, settings: ThemeSettings(themeName: "Glass", followSystemAppearance: false))
        store.reload()
        #expect(store.current.name == "Glass")
        #expect(store.current.vibrancy == .sidebar)
        _ = try store.saveUserTheme(ThemeDefinition(name: "Another", type: .light))
        #expect(ThemeLoader.themeFiles(in: source).map(\.lastPathComponent) == ["glass.json"])
    }

    @Test func themesDirIsNotMistakenForOtherArguments() {
        let settings = AppModel.demo().settings
        DemoArguments.apply(["Vela", "--demo", "--themes-dir", "/somewhere", "--theme", "Nord"], to: settings)
        #expect(settings[.appearanceTheme] == "Nord")
        #expect(settings[.appearanceFollowSystem] == false)
    }
}
