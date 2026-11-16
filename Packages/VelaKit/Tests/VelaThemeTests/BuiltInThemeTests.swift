// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaTheme

@Suite("Built-in themes")
struct BuiltInThemeTests {
    static let expected: [String: (name: String, kind: ThemeKind)] = [
        "oceanic": ("Oceanic", .dark),
        "darker": ("Darker", .dark),
        "palenight": ("Palenight", .dark),
        "ocean": ("Ocean", .dark),
        "deepforest": ("Deepforest", .dark),
        "volcano": ("Volcano", .dark),
        "lighter": ("Lighter", .light),
        "sandy-beach": ("Sandy Beach", .light),
        "vela-graphite": ("Vela Graphite", .dark),
        "vela-paper": ("Vela Paper", .light),
        "vela-mist": ("Vela Mist", .light),
        "dracula": ("Dracula", .dark),
        "nord": ("Nord", .dark),
        "catppuccin-latte": ("Catppuccin Latte", .light),
        "catppuccin-mocha": ("Catppuccin Mocha", .dark),
        "tokyo-night": ("Tokyo Night", .dark),
        "one-dark": ("One Dark", .dark),
        "gruvbox-dark": ("Gruvbox Dark", .dark),
        "solarized-dark": ("Solarized Dark", .dark),
        "solarized-light": ("Solarized Light", .light),
        "rose-pine": ("Rosé Pine", .dark),
    ]

    static var files: [URL] { ThemeLoader.themeFiles(in: ThemeLoader.builtInThemesDirectory) }

    @Test func allExpectedThemesShip() {
        let ids = Set(Self.files.map(ThemeLoader.themeID(for:)))
        #expect(ids == Set(Self.expected.keys))
    }

    @Test("Loads, resolves every token and passes the contrast audit", arguments: BuiltInThemeTests.files)
    func builtIn(url: URL) throws {
        let id = ThemeLoader.themeID(for: url)
        let definition = try ThemeLoader.load(contentsOf: url)
        let expected = try #require(Self.expected[id])
        #expect(definition.name == expected.name)
        #expect(definition.type == expected.kind)
        #expect(definition.schema == ThemeDefinition.schemaURL)
        #expect(definition.include == nil)
        #expect(definition.author?.isEmpty == false)
        #expect(definition.description?.isEmpty == false)

        // Every color key is a real token (no typos).
        for key in definition.colors.keys {
            #expect(ThemeRegistry.token(key) != nil, "\(id): unknown token \(key)")
        }
        // Designed, not recolored: key surfaces are set explicitly.
        let keySurfaces = [
            "window.background", "titleBar.background", "sidebar.background", "rail.background",
            "chat.background", "chat.foreground", "input.background", "memberList.background",
            "embed.background", "accent", "accentForeground",
        ]
        for key in keySurfaces {
            #expect(definition.colors[key] != nil, "\(id) should set \(key)")
        }
        #expect((definition.nickColors?.count ?? 0) >= 8, "\(id) should tune its nick palette")
        for index in 0..<16 {
            #expect(definition.ircColors?[String(index)] != nil, "\(id) should tune IRC color \(index)")
        }

        let theme = try ThemeResolver.resolve(definition, id: id, includeLoader: { _ in nil }, overrides: [:])
        // At most one near-text color is skipped from a designed palette.
        #expect(theme.nickPalette.count >= theme.nickColors.count - 1, "\(id) skips \(theme.nickColors.count - theme.nickPalette.count) nick colors")
        #expect(theme.kind == expected.kind)
        for token in ThemeRegistry.tokens {
            #expect(theme.colors[token.key] != nil, "\(id): \(token.key) unresolved")
        }
        let body = theme.color(ThemeKey.chatForeground).contrastRatio(against: theme.color(ThemeKey.chatBackground))
        #expect(body >= 4.5, "\(id): body text contrast \(body)")
        let failures = ThemeAudit.audit(theme).filter { !$0.passes }
        #expect(failures.isEmpty, "\(id): \(failures)")
    }

    @Test func namesAreUnique() throws {
        let names = try Self.files.map { try ThemeLoader.load(contentsOf: $0).name.lowercased() }
        #expect(Set(names).count == names.count)
    }

    @Test func noProprietaryNames() throws {
        for url in Self.files {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.localizedCaseInsensitiveContains("Monokai"), "\(url.lastPathComponent)")
            #expect(!(try ThemeLoader.load(contentsOf: url).name.localizedCaseInsensitiveContains("Material")))
        }
        for name in Self.expected.values.map(\.name) {
            #expect(!name.localizedCaseInsensitiveContains("Material"))
        }
    }

    @Test func fallbacksAreTheDefaultPair() {
        #expect(ResolvedTheme.fallbackDark.name == "Palenight")
        #expect(ResolvedTheme.fallbackDark.kind == .dark)
        #expect(ResolvedTheme.fallbackLight.name == "Lighter")
        #expect(ResolvedTheme.fallbackLight.kind == .light)
        #expect(ThemeSettings.default.preferredDarkTheme == "Palenight")
        #expect(ThemeSettings.default.preferredLightTheme == "Lighter")
    }

    @Test func lookupByIDOrName() throws {
        #expect(try ThemeLoader.builtInDefinition(named: "rose-pine")?.name == "Rosé Pine")
        #expect(try ThemeLoader.builtInDefinition(named: "ROSÉ PINE")?.name == "Rosé Pine")
        #expect(try ThemeLoader.builtInDefinition(named: "nope") == nil)
    }
}
