// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaTheme

@Suite("Token registry")
struct ThemeRegistryTests {
    @Test func keysAreUniqueAndDescribed() {
        let keys = ThemeRegistry.tokens.map(\.key)
        #expect(Set(keys).count == keys.count)
        let groups = Set(ThemeRegistry.groups.map(\.id))
        for token in ThemeRegistry.tokens {
            #expect(!token.description.isEmpty, "\(token.key) needs a description")
            #expect(groups.contains(token.group), "\(token.key) has unknown group \(token.group)")
        }
    }

    @Test func containsRequiredKeys() {
        let required = [
            "window.background", "window.foreground", "window.border", "pane.divider",
            "titleBar.background", "titleBar.foreground", "titleBar.secondaryForeground", "titleBar.border",
            "sidebar.background", "sidebar.foreground", "sidebar.secondaryForeground", "sidebar.headerForeground",
            "sidebar.hoverBackground", "sidebar.activeBackground", "sidebar.activeForeground",
            "sidebar.unreadForeground", "sidebar.highlightForeground", "sidebar.badgeBackground",
            "sidebar.badgeForeground", "sidebar.highlightBadgeBackground", "sidebar.highlightBadgeForeground",
            "sidebar.disconnectedForeground", "sidebar.border",
            "rail.background", "rail.foreground", "rail.activeBackground", "rail.activeIndicator",
            "chat.background", "chat.foreground", "chat.secondaryForeground", "chat.timestamp", "chat.link",
            "chat.selfNick", "chat.selfMessageBackground", "chat.highlightBackground", "chat.highlightBorder",
            "chat.mention", "chat.notice", "chat.action", "chat.event", "chat.event.join", "chat.event.part",
            "chat.event.quit", "chat.event.nick", "chat.event.mode", "chat.event.topic", "chat.error",
            "chat.serverMessage", "chat.dayDivider", "chat.unreadMarker", "chat.hoverBackground",
            "chat.selectionBackground", "chat.codeBackground", "chat.codeForeground",
            "input.containerBackground", "input.background", "input.foreground", "input.placeholder",
            "input.border", "input.focusBorder",
            "memberList.background", "memberList.foreground", "memberList.headerForeground",
            "memberList.awayForeground", "memberList.border",
            "embed.background", "embed.border", "embed.accent", "embed.title", "embed.description",
            "embed.siteName", "embed.placeholderBackground",
            "reaction.background", "reaction.foreground", "reaction.border", "reaction.selfBackground",
            "reaction.selfBorder", "reply.quoteBar", "reply.foreground", "reply.background", "typing.foreground",
            "accent", "accentForeground", "focusBorder", "button.background", "button.foreground",
            "button.secondaryBackground", "button.secondaryForeground", "scrollbar.thumb", "scrollbar.thumbHover",
            "popover.background", "popover.foreground", "popover.border",
            "settings.background", "settings.sidebarBackground", "settings.foreground",
            "settings.secondaryForeground", "settings.border", "settings.controlBackground",
        ]
        for key in required {
            #expect(ThemeRegistry.token(key) != nil, "missing \(key)")
        }
        #expect(ThemeRegistry.token(ThemeKey.memberListBackground)?.dark == .ref(ThemeKey.sidebarBackground))
    }

    @Test func defaultsReferenceExistingTokensWithoutCycles() {
        for kind in ThemeKind.allCases {
            for token in ThemeRegistry.tokens {
                for reference in token.defaultValue(for: kind).references {
                    #expect(ThemeRegistry.token(reference) != nil, "\(token.key) refers to unknown \(reference)")
                }
            }
            var evaluator = DefaultsEvaluator(explicit: [:], fallback: .black) {
                ThemeRegistry.token($0)?.defaultValue(for: kind)
            }
            for token in ThemeRegistry.tokens { _ = evaluator.value(of: token.key) }
            #expect(evaluator.cycles.isEmpty, "cycles in \(kind) defaults: \(evaluator.cycles)")
        }
    }

    @Test func registryDefaultsAloneAreReadable() {
        for kind in ThemeKind.allCases {
            let theme = ResolvedTheme.registryDefaults(kind)
            let failures = ThemeAudit.audit(theme).filter { !$0.passes }
            #expect(failures.isEmpty, "\(kind) defaults: \(failures)")
        }
    }
}

@Suite("Theme resolution")
struct ThemeResolverTests {
    @Test func everyTokenIsResolved() throws {
        let theme = try resolve(ThemeDefinition(name: "Empty", type: .dark))
        for token in ThemeRegistry.tokens {
            #expect(theme.colors[token.key] != nil, "\(token.key) unresolved")
        }
        #expect(theme.ircColors.count == 99)
        #expect(!theme.nickColors.isEmpty)
        #expect(theme.vibrancy == .none)
    }

    @Test func fallbackChainFollowsTheMostSpecificValue() throws {
        // Only the window is set: the member list derives from the sidebar,
        // which derives from the window.
        let base = try resolve(ThemeDefinition(name: "A", type: .dark, colors: ["window.background": "#102030"]))
        #expect(base.color(ThemeKey.chatBackground).hex == "#102030")
        #expect(base.color(ThemeKey.memberListBackground) == base.color(ThemeKey.sidebarBackground))
        #expect(base.color(ThemeKey.sidebarBackground) != base.color(ThemeKey.windowBackground))

        // Setting the sidebar moves the member list with it.
        let sidebar = try resolve(ThemeDefinition(
            name: "B", type: .dark,
            colors: ["window.background": "#102030", "sidebar.background": "#ABCDEF"]
        ))
        #expect(sidebar.color(ThemeKey.memberListBackground).hex == "#ABCDEF")
        #expect(sidebar.color(ThemeKey.railBackground).hex == "#ABCDEF")
        #expect(sidebar.color(ThemeKey.settingsSidebarBackground).hex == "#ABCDEF")

        // Setting the member list directly wins over the chain.
        let member = try resolve(ThemeDefinition(
            name: "C", type: .dark,
            colors: ["sidebar.background": "#ABCDEF", "memberList.background": "#123456"]
        ))
        #expect(member.color(ThemeKey.memberListBackground).hex == "#123456")
    }

    @Test func accentPropagates() throws {
        let theme = try resolve(ThemeDefinition(name: "A", type: .dark, colors: ["accent": "#FF8800"]))
        #expect(theme.color(ThemeKey.buttonBackground).hex == "#FF8800")
        #expect(theme.color(ThemeKey.chatLink).hex == "#FF8800")
        #expect(theme.color(ThemeKey.sidebarHighlightBadgeBackground).hex == "#FF8800")
        #expect(theme.color(ThemeKey.chatSelectionBackground).alpha < 1)
        // contrast(accent): dark text on a light orange fill.
        #expect(theme.color(ThemeKey.accentForeground).isDark)
        let blue = try resolve(ThemeDefinition(name: "B", type: .dark, colors: ["accent": "#1A4FA0"]))
        #expect(blue.color(ThemeKey.accentForeground) == .white)
    }

    @Test func lightDefaultsDarkenAccentText() throws {
        let theme = try resolve(ThemeDefinition(name: "L", type: .light, colors: ["accent": "#39ADB5"]))
        let text = theme.color(ThemeKey.accentText)
        #expect(text != theme.color(ThemeKey.accent))
        #expect(text.contrastRatio(against: theme.color(ThemeKey.chatBackground)) >= 4.5)
    }

    @Test func cycleProtection() {
        let defaults: [String: TokenDefault] = [
            "a": .ref("b"),
            "b": .mix("c", "#FFFFFF", 0.5),
            "c": .ref("a"),
            "d": .ref("d"),
            "e": .transparent("a", 0.5),
            "f": .hex("#123456"),
        ]
        var evaluator = DefaultsEvaluator(explicit: [:], fallback: hex("#808080")) { defaults[$0] }
        for key in defaults.keys.sorted() { _ = evaluator.value(of: key) }
        #expect(!evaluator.cycles.isEmpty)
        #expect(evaluator.cycles.isSuperset(of: ["d"]))
        #expect(evaluator.resolved["f"]?.hex == "#123456")
        #expect(evaluator.resolved.keys.count == defaults.count)

        // An explicit value breaks the cycle entirely.
        var fixed = DefaultsEvaluator(explicit: ["a": hex("#000000")], fallback: hex("#808080")) { defaults[$0] }
        #expect(fixed.value(of: "c").hex == "#000000")
        #expect(fixed.value(of: "b").hex == "#808080")
        #expect(fixed.cycles.isEmpty)
    }

    @Test func unknownKeysPassThrough() throws {
        let theme = try resolve(ThemeDefinition(name: "A", type: .dark, colors: ["future.token": "#010203"]))
        #expect(theme.color("future.token").hex == "#010203")
        #expect(theme.color("not.a.token") == theme.color(ThemeKey.windowForeground))
    }

    @Test func invalidThemeColorThrows() {
        #expect(throws: ThemeError.invalidColor(key: "colors.accent", value: "#12")) {
            try resolve(ThemeDefinition(name: "A", type: .dark, colors: ["accent": "#12"]))
        }
    }

    // MARK: Includes

    private let base = ThemeDefinition(
        name: "Base",
        type: .dark,
        colors: ["window.background": "#111111", "accent": "#00FF00", "chat.link": "#0000FF"],
        nickColors: ["#AA0000", "#00AA00"],
        ircColors: ["4": "#FF1111", "5": "#551111"],
        vibrancy: .sidebar
    )

    private func loader(_ themes: [ThemeDefinition]) -> (String) throws -> ThemeDefinition? {
        { reference in themes.first { $0.name.caseInsensitiveCompare(reference) == .orderedSame } }
    }

    @Test func includesLayerOnTopOfTheBase() throws {
        let child = ThemeDefinition(
            name: "Child",
            type: .dark,
            include: "base",
            colors: ["accent": "#FF00FF"],
            ircColors: ["4": "#EE0000"]
        )
        let theme = try ThemeResolver.resolve(child, id: "child", includeLoader: loader([base]), overrides: [:])
        #expect(theme.name == "Child")
        #expect(theme.color(ThemeKey.windowBackground).hex == "#111111")
        #expect(theme.color(ThemeKey.accent).hex == "#FF00FF")
        #expect(theme.color(ThemeKey.chatLink).hex == "#0000FF")
        #expect(theme.nickColors.map(\.hex) == ["#AA0000", "#00AA00"])
        #expect(theme.ircColor(4)?.hex == "#EE0000")
        #expect(theme.ircColor(5)?.hex == "#551111")
        #expect(theme.ircColor(6) == IRCPalette.standard[6])
        #expect(theme.vibrancy == .sidebar)

        let flat = try ThemeResolver.flatten(child, includeLoader: loader([base]))
        #expect(flat.include == nil)
        #expect(flat.colors["window.background"] == "#111111")
    }

    @Test func includeChains() throws {
        let middle = ThemeDefinition(name: "Middle", type: .dark, include: "Base", colors: ["chat.link": "#00FFFF"])
        let top = ThemeDefinition(name: "Top", type: .light, include: "Middle")
        let theme = try ThemeResolver.resolve(top, id: "top", includeLoader: loader([base, middle]), overrides: [:])
        #expect(theme.kind == .light)
        #expect(theme.color(ThemeKey.chatLink).hex == "#00FFFF")
        #expect(theme.color(ThemeKey.windowBackground).hex == "#111111")
    }

    @Test func includeErrors() {
        let missing = ThemeDefinition(name: "Orphan", type: .dark, include: "Nowhere")
        #expect(throws: ThemeError.includeNotFound("Nowhere")) {
            try ThemeResolver.resolve(missing, id: "x", includeLoader: { _ in nil }, overrides: [:])
        }

        let a = ThemeDefinition(name: "A", type: .dark, include: "B")
        let b = ThemeDefinition(name: "B", type: .dark, include: "A")
        #expect(throws: ThemeError.self) {
            try ThemeResolver.resolve(a, id: "a", includeLoader: loader([a, b]), overrides: [:])
        }
        do {
            _ = try ThemeResolver.flatten(a, includeLoader: loader([a, b]))
        } catch let error as ThemeError {
            guard case .includeCycle(let chain) = error else {
                Issue.record("Expected includeCycle, got \(error)")
                return
            }
            #expect(chain.first == "A")
        } catch {
            Issue.record("Unexpected \(error)")
        }

        let selfInclude = ThemeDefinition(name: "Me", type: .dark, include: "Me")
        #expect(throws: ThemeError.self) {
            try ThemeResolver.flatten(selfInclude, includeLoader: loader([selfInclude]))
        }
    }

    // MARK: Overrides

    @Test func globalAndScopedOverrides() throws {
        let customizations: [String: JSONValue] = [
            "chat.background": "#000000",
            "accent": "#111111",
            "[Base]": .object(["accent": "#222222", "nickColors": .array(["#123456"])]),
            "[Other]": .object(["accent": "#333333"]),
            "[Ba*][Nope]": .object(["chat.link": "#444444"]),
            "ircColors": .object(["4": "#ABABAB"]),
            "vibrancy": "window",
        ]
        let overrides = ThemeOverrides(customizations: customizations, themeName: "Base", themeID: "base-file")
        let theme = try ThemeResolver.resolve(base, id: "base-file", includeLoader: { _ in nil }, overrides: overrides)
        #expect(theme.color(ThemeKey.chatBackground).hex == "#000000")
        #expect(theme.color(ThemeKey.windowBackground).hex == "#111111")
        #expect(theme.color(ThemeKey.accent).hex == "#222222", "scoped beats global")
        #expect(theme.color(ThemeKey.chatLink).hex == "#444444", "wildcard scope applies")
        #expect(theme.nickColors.map(\.hex) == ["#123456"])
        #expect(theme.ircColor(4)?.hex == "#ABABAB")
        #expect(theme.vibrancy == .window)

        // Scopes match the id too, case-insensitively.
        let byID = ThemeOverrides(customizations: ["[BASE-FILE]": .object(["accent": "#555555"])], themeName: "x", themeID: "base-file")
        #expect(byID.colors["accent"] == "#555555")

        // Other themes only see global entries.
        let other = ThemeOverrides(customizations: customizations, themeName: "Unrelated", themeID: "unrelated")
        #expect(other.colors["accent"] == "#111111")
        #expect(other.colors["chat.link"] == nil)
    }

    @Test func contractOverloadAndInvalidOverridesAreIgnored() throws {
        let theme = try ThemeResolver.resolve(
            base,
            id: "base",
            includeLoader: { _ in nil },
            overrides: ["accent": "not a color", "chat.background": "#FAFAFA"]
        )
        #expect(theme.color(ThemeKey.accent).hex == "#00FF00")
        #expect(theme.color(ThemeKey.chatBackground).hex == "#FAFAFA")
    }

    @Test func overrideProblemsAreReported() {
        let problems = ThemeOverrides.problems(in: [
            "chat.backgound": "#000",
            "accent": "blue",
            "nickColors": .array(["#FFF", "nope"]),
            "ircColors": .object(["120": "#FFF"]),
            "[Palenight]": .object(["vibrancy": "glass"]),
            "chat.link": "#FFF",
        ])
        #expect(problems.count == 5)
        #expect(problems.contains { $0.contains("chat.backgound") })
        #expect(!problems.contains { $0.contains("chat.link") })
    }

    @Test func scopeParsingAndGlobs() {
        #expect(ThemeOverrides.scopePatterns(in: "[A]") == ["A"])
        #expect(ThemeOverrides.scopePatterns(in: "[A][B C]") == ["A", "B C"])
        #expect(ThemeOverrides.scopePatterns(in: "[A] [B]") == ["A", "B"])
        #expect(ThemeOverrides.scopePatterns(in: "accent") == nil)
        #expect(ThemeOverrides.scopePatterns(in: "[A]x") == nil)
        #expect(ThemeOverrides.glob("Catppuccin *", matches: "catppuccin mocha"))
        #expect(ThemeOverrides.glob("*light*", matches: "Solarized Light"))
        #expect(!ThemeOverrides.glob("Catppuccin *", matches: "Nord"))
        #expect(ThemeOverrides.glob("*", matches: "anything"))
    }
}

@Suite("Nick and IRC colors")
struct NickColorTests {
    @Test func stableAndCaseInsensitive() throws {
        let theme = try resolve(ThemeDefinition(name: "A", type: .dark))
        #expect(theme.nickColor(for: "Alice") == theme.nickColor(for: "alice"))
        #expect(theme.nickColor(for: "ALICE") == theme.nickColor(for: "alice"))
        #expect(theme.nickColor(for: "nick[away]") == theme.nickColor(for: "NICK{AWAY}"))
        #expect(theme.nickColor(for: "a\\b~") == theme.nickColor(for: "a|b^"))
        // FNV-1a is fixed, so indexes never change between launches.
        #expect(ResolvedTheme.nickColorIndex(for: "alice", paletteSize: 12) == ResolvedTheme.nickColorIndex(for: "Alice", paletteSize: 12))
        #expect(ResolvedTheme.nickColorIndex(for: "", paletteSize: 12) == Int(2_166_136_261 % 12))
    }

    @Test func spreadsAcrossThePalette() throws {
        let theme = try resolve(ThemeDefinition(name: "A", type: .dark))
        let nicks = (0..<200).map { "user\($0)" }
        let used = Set(nicks.map { theme.nickColor(for: $0) })
        #expect(used.count == theme.nickColors.count)
    }

    @Test func ircPalette() throws {
        let theme = try resolve(ThemeDefinition(name: "A", type: .dark))
        #expect(theme.ircColor(0)?.hex == "#FFFFFF")
        #expect(theme.ircColor(1)?.hex == "#000000")
        #expect(theme.ircColor(16)?.hex == "#470000")
        #expect(theme.ircColor(98)?.hex == "#FFFFFF")
        #expect(theme.ircColor(99) == nil)
        #expect(theme.ircColor(-1) == nil)
        #expect(IRCPalette.standardHex.count == 99)
        for value in IRCPalette.standardHex { #expect(ThemeColor(hex: value) != nil) }
    }
}
