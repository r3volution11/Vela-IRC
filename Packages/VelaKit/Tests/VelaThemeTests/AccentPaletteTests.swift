// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaTheme

/// A built-in theme's accent palette, from its file as designed.
func builtInPalette(_ id: String) throws -> AccentPalette {
    let url = ThemeLoader.builtInThemesDirectory.appendingPathComponent("\(id).json")
    return try AccentPalette(definition: ThemeLoader.load(contentsOf: url), id: id)
}

/// `palette`'s theme resolved with `customizations` applied.
func resolved(_ palette: AccentPalette, with customizations: [String: JSONValue]) throws -> ResolvedTheme {
    let overrides = ThemeOverrides(customizations: customizations, themeName: palette.themeName, themeID: palette.themeID)
    return try ThemeResolver.resolve(palette.definition, id: palette.themeID, includeLoader: { _ in nil }, overrides: overrides)
}

@Suite("Accent palette: swatches")
struct AccentSwatchTests {
    static let themes = ["palenight", "lighter", "dracula", "solarized-light"]
    static let allThemes = ThemeLoader.themeFiles(in: ThemeLoader.builtInThemesDirectory).map(ThemeLoader.themeID(for:)).sorted()

    @Test("Swatches are the theme's own, readable and distinct", arguments: AccentSwatchTests.themes)
    func swatches(id: String) throws {
        let palette = try builtInPalette(id)
        let base = palette.base
        let swatches = palette.swatches

        // Default first: the theme's own accent.
        #expect(swatches.first?.isDefault == true)
        #expect(swatches.first?.color == base.color(ThemeKey.accent).withAlpha(1))
        #expect(swatches.dropFirst().allSatisfy { !$0.isDefault })
        #expect(swatches.count >= 5, "\(id) offers too few colors")
        #expect(swatches.count <= AccentPalette.maximumCount)

        // Only colors the theme ships (nick colors, IRC 0–15).
        let definition = palette.definition
        let own = Set(((definition.nickColors ?? []) + (0..<16).compactMap { definition.ircColors?[String($0)] })
            .compactMap { ThemeColor(hex: $0)?.withAlpha(1).hex })
        for swatch in swatches.dropFirst() {
            #expect(own.contains(swatch.color.hex), "\(id): \(swatch.color.hex) isn't one of the theme's colors")
        }

        let window = ThemeAudit.surface(ThemeKey.windowBackground, in: base)
        let sidebar = ThemeAudit.surface(ThemeKey.sidebarBackground, in: base)
        let text = base.color(ThemeKey.windowForeground)
        for swatch in swatches.dropFirst() {
            let color = swatch.color
            #expect(color.contrastRatio(against: window) >= 3, "\(id): \(color.hex) on window.background")
            #expect(color.contrastRatio(against: sidebar) >= 3, "\(id): \(color.hex) on sidebar.background")
            #expect(color.chroma >= 0.03, "\(id): \(color.hex) is a grey")
            #expect(!AccentPalette.looksLikeText(color, text: text), "\(id): \(color.hex) reads as text")
        }

        // De-duplicated, Default included.
        for (i, a) in swatches.enumerated() {
            for b in swatches[(i + 1)...] {
                #expect(a.color.distance(to: b.color) >= AccentPalette.similarDistance, "\(id): \(a.color.hex) ≈ \(b.color.hex)")
            }
        }

        // Ordered by hue after Default, with distinct names.
        let hues = swatches.dropFirst().map { AccentPalette.hueOrder($0.color) }
        #expect(hues == hues.sorted())
        #expect(Set(swatches.map(\.name)).count == swatches.count, "\(id): \(swatches.map(\.name))")
    }

    @Test func palenightOffersCyan() throws {
        let palette = try builtInPalette("palenight")
        #expect(palette.defaultSwatch.name == "Purple")
        #expect(palette.defaultSwatch.accessibilityLabel == "Default, Purple")
        #expect(palette.defaultSwatch.title == "Default (Purple)")
        let cyan = try #require(palette.swatches.first { $0.color == hex("#89DDFF") })
        #expect(cyan.name == "Cyan")
        #expect(cyan.accessibilityLabel == "Cyan")
    }

    @Test func colorNamesFollowHue() {
        let expected: [String: String] = [
            "#F07178": "Red", "#FF0000": "Red", "#F78C6C": "Red", "#FFA500": "Orange", "#DDB585": "Tan",
            "#7D5A3C": "Brown", "#FFCB6B": "Yellow", "#9A6B00": "Gold", "#C3E88D": "Green",
            "#80CBC4": "Teal", "#39ADB5": "Teal", "#89DDFF": "Cyan", "#00FFFF": "Cyan",
            "#82AAFF": "Blue", "#6C71C4": "Indigo", "#A9B4FF": "Lavender", "#C792EA": "Purple",
            "#C8559F": "Magenta", "#FF9CAC": "Pink", "#EBBCBA": "Pink", "#808080": "Gray",
        ]
        for (value, name) in expected {
            #expect(AccentPalette.colorName(hex(value)) == name, "\(value)")
        }
    }

    @Test func duplicateNamesGetQualifiers() {
        #expect(AccentPalette.names(for: [hex("#82AAFF"), hex("#2B4C9B")]) == ["Light Blue", "Dark Blue"])
        #expect(AccentPalette.names(for: [hex("#9CCFD8"), hex("#3E8FB0"), hex("#31748F")]) == ["Light Cyan", "Cyan", "Dark Cyan"])
        #expect(AccentPalette.names(for: [hex("#82AAFF"), hex("#7FA6FA")]) == ["Blue", "Blue 2"])
    }

    @Test func nextSwatchCyclesAndWraps() throws {
        let palette = try builtInPalette("palenight")
        let swatches = palette.swatches
        #expect(palette.nextSwatch(after: .swatch(swatches[0])) == swatches[1])
        #expect(palette.nextSwatch(after: .swatch(swatches[swatches.count - 1])) == swatches[0])
        #expect(palette.nextSwatch(after: .custom(hex("#123456"))) == swatches[1])
    }
}

@Suite("Accent palette: recoloring")
struct AccentRecolorTests {
    @Test("Every swatch keeps the theme's contrast", arguments: AccentSwatchTests.allThemes)
    func contrastHolds(id: String) throws {
        let palette = try builtInPalette(id)
        let baseFindings = ThemeAudit.audit(palette.base)
        for swatch in palette.swatches.dropFirst() {
            let theme = try resolved(palette, with: palette.applying(swatch, to: [:]))
            for (finding, base) in zip(ThemeAudit.audit(theme), baseFindings) where base.passes {
                #expect(finding.passes, "\(id) → \(swatch.name): \(finding)")
            }
            let accent = theme.color(ThemeKey.accent)
            #expect(accent == swatch.color)
            #expect(theme.color(ThemeKey.accentForeground).contrastRatio(against: accent) >= 4.5)
            for background in [ThemeKey.windowBackground, ThemeKey.chatBackground, ThemeKey.settingsBackground] {
                let ratio = theme.color(ThemeKey.accentText).contrastRatio(against: ThemeAudit.surface(background, in: theme))
                #expect(ratio >= 4.5, "\(id) → \(swatch.name): accentText on \(background) \(ratio)")
            }
        }
    }

    @Test("Every accent-colored token follows, keeping its alpha", arguments: AccentSwatchTests.themes)
    func accentTokensFollow(id: String) throws {
        let palette = try builtInPalette(id)
        let oldAccent = palette.base.color(ThemeKey.accent).withAlpha(1)
        let swatch = try #require(palette.swatches.last)
        let overrides = palette.overrides(for: swatch)
        let theme = try resolved(palette, with: palette.applying(swatch, to: [:]))
        for key in palette.definition.colors.keys where !AccentRecolor.semanticTokens.contains(key) {
            let original = palette.base.color(key)
            guard original.withAlpha(1).distance(to: oldAccent) < AccentRecolor.sameColor else { continue }
            let now = theme.color(key)
            #expect(overrides[key] != nil, "\(id): \(key) wasn't recolored")
            #expect(now.withAlpha(1).distance(to: oldAccent) > 0.05, "\(id): \(key) still has the old accent")
            #expect(abs(now.alpha - original.alpha) < 0.003, "\(id): \(key) lost its alpha")
        }
    }

    /// A small theme exercising alpha, semantic tokens, accent-derived
    /// tints and the derived defaults.
    static let sample = ThemeDefinition(
        name: "Sample",
        type: .dark,
        colors: [
            "window.background": "#202030",
            "window.foreground": "#D0D0E0",
            "sidebar.background": "#1A1A28",
            "accent": "#C792EA",
            "accentText": "#C792EA",
            "accentForeground": "#1F1B2E",
            "chat.selectionBackground": "#C792EA55",
            "status.success": "#C792EA",
            "button.hoverBackground": "#D4A8F0",
            "chat.link": "#82AAFF",
        ],
        nickColors: ["#F07178", "#FFCB6B", "#C3E88D", "#89DDFF", "#82AAFF"]
    )

    @Test func recolorKeepsAlphaAndSemanticColors() throws {
        let palette = try AccentPalette(definition: Self.sample, id: "sample")
        let cyan = try #require(palette.swatches.first { $0.color == hex("#89DDFF") })
        let overrides = palette.overrides(for: cyan)

        #expect(overrides[ThemeKey.accent] == hex("#89DDFF"))
        #expect(overrides[ThemeKey.chatSelectionBackground]?.hex == "#89DDFF55")
        #expect(overrides[ThemeKey.statusSuccess] == nil, "semantic colors stay")
        #expect(overrides[ThemeKey.chatLink] == nil, "unrelated colors stay")
        // The lighter hover shade becomes a lighter shade of cyan.
        let hover = try #require(overrides[ThemeKey.buttonHoverBackground])
        #expect(abs(hover.hue - hex("#89DDFF").hue) < 10)
        #expect(hover.luminance > hex("#89DDFF").luminance)

        // Tokens the theme leaves to defaults follow through the registry.
        let theme = try resolved(palette, with: palette.applying(cyan, to: [:]))
        #expect(theme.color(ThemeKey.tabActiveIndicator) == hex("#89DDFF"))
        #expect(theme.color(ThemeKey.buttonBackground) == hex("#89DDFF"))
        #expect(theme.color(ThemeKey.accentForeground).contrastRatio(against: hex("#89DDFF")) >= 4.5)
    }

    @Test func darkAccentGetsLightText() throws {
        // A light theme picking a dark accent: white text on it.
        let foreground = AccentRecolor.accentForeground(on: hex("#283593"), like: hex("#0E3438"))
        #expect(foreground.contrastRatio(against: hex("#283593")) >= 4.5)
        #expect(!foreground.isDark)
        // A light accent keeps a dark, re-tinted foreground.
        let dark = AccentRecolor.accentForeground(on: hex("#89DDFF"), like: hex("#1F1B2E"))
        #expect(dark.isDark)
        #expect(dark.contrastRatio(against: hex("#89DDFF")) >= 4.5)
    }

    @Test func lightnessAdjustmentReachesContrast() {
        let light = hex("#FAFAFA")
        let adjusted = hex("#39ADB5").adjustingLightness(toReach: 4.5, against: [light])
        let stored = ThemeColor(hex: adjusted.hex)!
        #expect(stored.contrastRatio(against: light) >= 4.5)
        #expect(abs(adjusted.hue - hex("#39ADB5").hue) < 6, "keeps its hue")
        #expect(adjusted.luminance < hex("#39ADB5").luminance)
        // Already readable: unchanged.
        #expect(hex("#00666E").adjustingLightness(toReach: 4.5, against: [light]) == hex("#00666E"))
    }

    @Test func oklabRoundTrip() {
        for value in ["#C792EA", "#89DDFF", "#000000", "#FFFFFF", "#9A6B00", "#283593"] {
            let color = hex(value)
            let lab = color.oklab
            #expect(ThemeColor(oklabL: lab.l, a: lab.a, b: lab.b).hex == color.hex)
        }
        // Out of gamut: chroma is reduced into sRGB, lightness kept.
        let clipped = ThemeColor(oklchL: 0.9, c: 0.4, h: 140)
        #expect(abs(clipped.oklab.l - 0.9) < 0.01)
    }
}

@Suite("Accent palette: settings")
struct AccentCustomizationTests {
    @Test func writesIntoTheThemeScopeWithAMarker() throws {
        let palette = try builtInPalette("palenight")
        let cyan = try #require(palette.swatches.first { $0.name == "Cyan" })
        let customizations = palette.applying(cyan, to: [:])

        #expect(Array(customizations.keys) == ["[Palenight]"])
        let scope = try #require(customizations["[Palenight]"]?.objectValue)
        #expect(scope["accent"] == .string("#89DDFF"))
        let marker = AccentCustomizations.markerKeys(in: scope)
        #expect(Set(marker) == Set(scope.keys).subtracting([AccentCustomizations.markerKey]))
        #expect(marker.contains("accentText") && marker.contains("accentForeground"))

        // The marker is neither a problem nor a color.
        #expect(ThemeOverrides.problems(in: customizations).isEmpty)
        let overrides = ThemeOverrides(customizations: customizations, themeName: "Palenight", themeID: "palenight")
        #expect(overrides.colors[AccentCustomizations.markerKey] == nil)
        #expect(ThemeOverrides.problems(in: ["[Palenight]": .object(["$accentPicker": "accent"])]).count == 1)
    }

    @Test func handWrittenOverridesWin() throws {
        let palette = try builtInPalette("palenight")
        let cyan = try #require(palette.swatches.first { $0.name == "Cyan" })
        let original: [String: JSONValue] = [
            "chat.background": "#000000",
            "button.background": "#123456",
            "[Palenight]": .object(["sidebar.activeBackground": "#111111", "chat.link": "#FF0000"]),
            "[Nord]": .object(["accent": "#00FF00"]),
        ]
        let customizations = palette.applying(cyan, to: original)

        #expect(customizations["chat.background"] == "#000000")
        #expect(customizations["button.background"] == "#123456")
        #expect(customizations["[Nord]"] == original["[Nord]"])
        let scope = try #require(customizations["[Palenight]"]?.objectValue)
        #expect(scope["sidebar.activeBackground"] == "#111111", "hand-written scope entries aren't replaced")
        #expect(scope["chat.link"] == "#FF0000")
        #expect(scope["button.background"] == nil, "a top-level hand-written token isn't shadowed")
        let marker = Set(AccentCustomizations.markerKeys(in: scope))
        #expect(!marker.contains("sidebar.activeBackground"))
        #expect(!marker.contains("button.background"))

        let theme = try resolved(palette, with: customizations)
        #expect(theme.color(ThemeKey.accent) == hex("#89DDFF"))
        #expect(theme.color(ThemeKey.buttonBackground) == hex("#123456"))
        #expect(theme.color(ThemeKey.sidebarActiveBackground) == hex("#111111"))
        #expect(AccentCustomizations.handWrittenCount(in: customizations) == 5)
    }

    @Test func defaultRemovesOnlyGeneratedTokens() throws {
        let palette = try builtInPalette("palenight")
        let original: [String: JSONValue] = [
            "chat.background": "#000000",
            "[Palenight]": .object(["chat.link": "#FF0000"]),
        ]
        var customizations = original
        for swatch in palette.swatches.dropFirst() {
            customizations = palette.applying(swatch, to: customizations)
        }
        // Switching swatches leaves nothing stale behind.
        let last = try #require(palette.swatches.last)
        #expect(customizations == palette.applying(last, to: original))

        let reset = palette.applying(palette.defaultSwatch, to: customizations)
        #expect(reset == original)
        #expect(AccentCustomizations.removing(from: customizations, themeName: "Palenight", themeID: "palenight") == original)
        // A scope that only held generated tokens disappears.
        #expect(palette.applying(palette.defaultSwatch, to: palette.applying(last, to: [:])) == [:])
    }

    @Test("Choosing a swatch reads back as that swatch", arguments: AccentSwatchTests.themes)
    func detectionRoundTrip(id: String) throws {
        let palette = try builtInPalette(id)
        #expect(palette.choice(in: [:]) == .swatch(palette.defaultSwatch))
        for swatch in palette.swatches {
            let customizations = palette.applying(swatch, to: [:])
            #expect(palette.choice(in: customizations) == .swatch(swatch), "\(id): \(swatch.name)")
            let generated = AccentCustomizations.generatedKeys(in: customizations, themeName: palette.themeName, themeID: id)
            #expect(generated.isEmpty == swatch.isDefault)
        }
        #expect(palette.choice(in: ["accent": "#123456"]) == .custom(hex("#123456")))
    }

    @Test func eachThemeKeepsItsOwnChoice() throws {
        let palenight = try builtInPalette("palenight")
        let lighter = try builtInPalette("lighter")
        let cyan = try #require(palenight.swatches.first { $0.name == "Cyan" })
        let purple = try #require(lighter.swatches.first { $0.name == "Purple" })
        var customizations = palenight.applying(cyan, to: [:])
        customizations = lighter.applying(purple, to: customizations)

        #expect(palenight.choice(in: customizations) == .swatch(cyan))
        #expect(lighter.choice(in: customizations) == .swatch(purple))
        customizations = lighter.applying(lighter.defaultSwatch, to: customizations)
        #expect(palenight.choice(in: customizations) == .swatch(cyan))
        #expect(lighter.choice(in: customizations) == .swatch(lighter.defaultSwatch))
    }

    @Test func scopeKeys() {
        #expect(AccentCustomizations.scopeKey(in: [:], themeName: "Palenight", themeID: "palenight") == "[Palenight]")
        #expect(AccentCustomizations.scopeKey(in: [:], themeName: "Odd [beta]", themeID: "odd-beta") == "[odd-beta]")
        #expect(AccentCustomizations.scopeKey(in: [:], themeName: "Star*", themeID: "star") == "[star]")
        // An existing single-theme scope is reused, in any case; lists and
        // wildcards aren't.
        let existing: [String: JSONValue] = ["[palenight]": .object(["chat.link": "#FF0000"]), "[Pale*]": .object([:]), "[Nord][Palenight]": .object([:])]
        #expect(AccentCustomizations.scopeKey(in: existing, themeName: "Palenight", themeID: "palenight") == "[palenight]")
    }
}
