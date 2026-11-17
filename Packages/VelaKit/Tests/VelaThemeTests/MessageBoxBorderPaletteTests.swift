// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaTheme

/// A built-in theme's message box border palette, from its file as designed.
func builtInBorderPalette(_ id: String) throws -> MessageBoxBorderPalette {
    MessageBoxBorderPalette(accentPalette: try builtInPalette(id))
}

/// `palette`'s theme resolved with `customizations` applied.
func resolved(_ palette: MessageBoxBorderPalette, with customizations: [String: JSONValue]) throws -> ResolvedTheme {
    let overrides = ThemeOverrides(customizations: customizations, themeName: palette.themeName, themeID: palette.themeID)
    return try ThemeResolver.resolve(palette.definition, id: palette.themeID, includeLoader: { _ in nil }, overrides: overrides)
}

@Suite("Message box border: swatches")
struct MessageBoxBorderSwatchTests {
    static let themes = AccentSwatchTests.themes

    @Test("Default first, then the theme's quiet neutrals, accent and colors", arguments: MessageBoxBorderSwatchTests.themes)
    func swatches(id: String) throws {
        let palette = try builtInBorderPalette(id)
        let base = palette.base
        let swatches = palette.swatches

        // Default first: the theme's own border.
        #expect(swatches.first?.isDefault == true)
        #expect(swatches.first?.color == base.color(ThemeKey.inputBorder))
        #expect(swatches.dropFirst().allSatisfy { !$0.isDefault })
        #expect(swatches.count >= 5, "\(id) offers too few colors: \(swatches.map(\.name))")
        #expect(swatches.count <= MessageBoxBorderPalette.maximumCount)
        #expect(Set(swatches.map(\.id)).count == swatches.count)
        #expect(Set(swatches.map(\.name)).count == swatches.count, "\(id): \(swatches.map(\.name))")

        // At least two quiet neutrals, taken straight from the theme's tokens.
        let neutralNames = Set(MessageBoxBorderPalette.neutralTokens.map(\.name))
        let neutrals = swatches.filter { neutralNames.contains($0.name) }
        #expect(neutrals.count >= 2, "\(id): \(swatches.map(\.name))")
        for swatch in neutrals {
            let token = try #require(MessageBoxBorderPalette.neutralTokens.first { $0.name == swatch.name }?.key)
            #expect(swatch.color == base.color(token), "\(id): \(swatch.name)")
        }

        // The accent, as the theme has it.
        #expect(swatches.contains { $0.name == "Accent" && $0.color == base.color(ThemeKey.accent).withAlpha(1) })

        // Everything shows on the field and differs from what came before.
        let field = ThemeAudit.surface(ThemeKey.inputBackground, in: base)
        for (i, a) in swatches.enumerated() {
            #expect(a.color.composited(over: field).distance(to: field) >= MessageBoxBorderPalette.invisibleDistance)
            for b in swatches[(i + 1)...] {
                #expect(a.color.composited(over: field).distance(to: b.color.composited(over: field)) >= MessageBoxBorderPalette.similarDistance,
                        "\(id): \(a.name) ≈ \(b.name)")
            }
        }
    }

    @Test func palenightOffersItsQuietNeutrals() throws {
        let palette = try builtInBorderPalette("palenight")
        let base = palette.base
        let names = palette.swatches.map(\.name)
        // Low contrast is the point: the divider and secondary text stay in.
        let divider = try #require(palette.swatches.first { $0.name == "Divider" })
        #expect(divider.color == base.color(ThemeKey.paneDivider))
        let secondary = try #require(palette.swatches.first { $0.name == "Secondary Text" })
        #expect(secondary.color == base.color(ThemeKey.chatSecondaryForeground))
        #expect(names.contains("Placeholder"))
        // Neutrals run from quietest to strongest, before the accent.
        let field = ThemeAudit.surface(ThemeKey.inputBackground, in: base)
        let neutralNames = Set(MessageBoxBorderPalette.neutralTokens.map(\.name))
        let ratios = palette.swatches.filter { neutralNames.contains($0.name) }
            .map { $0.color.composited(over: field).contrastRatio(against: field) }
        #expect(ratios == ratios.sorted())
        let accentIndex = try #require(names.firstIndex(of: "Accent"))
        #expect(names[1..<accentIndex].allSatisfy(neutralNames.contains))
        // Then other Palenight colors: ones the accent picker offers too.
        let accentColors = Set(try builtInPalette("palenight").swatches.map(\.color))
        let others = palette.swatches[(accentIndex + 1)...]
        #expect(others.count >= 3, "\(names)")
        #expect(others.allSatisfy { accentColors.contains($0.color) }, "\(names)")
        #expect(palette.defaultSwatch.title == "Default (the theme's border)")
    }

    /// With no border (`appearance.messageBoxBorder: "none"`), only the
    /// field's own background sets it apart from the bar around it.
    @Test("Without a border the field still differs from its bar", arguments: AccentSwatchTests.allThemes)
    func fieldDiffersFromItsBar(id: String) throws {
        let base = try builtInPalette(id).base
        let field = ThemeAudit.surface(ThemeKey.inputBackground, in: base)
        let bar = ThemeAudit.surface(ThemeKey.inputContainerBackground, in: base)
        #expect(field.contrastRatio(against: bar) >= 1.03, "\(id): \(field.hex) on \(bar.hex)")
    }

    @Test func lighterOffersItsQuietNeutrals() throws {
        let palette = try builtInBorderPalette("lighter")
        let neutralNames = Set(MessageBoxBorderPalette.neutralTokens.map(\.name))
        #expect(palette.swatches.filter { neutralNames.contains($0.name) }.count >= 2, "\(palette.swatches.map(\.name))")
        #expect(palette.swatches.contains { $0.name == "Secondary Text" })
    }
}

@Suite("Message box border: settings")
struct MessageBoxBorderCustomizationTests {
    @Test func writesBothTokensIntoTheThemeScopeWithAMarker() throws {
        let palette = try builtInBorderPalette("palenight")
        let divider = try #require(palette.swatches.first { $0.name == "Divider" })
        let customizations = palette.applying(divider, to: [:])

        #expect(Array(customizations.keys) == ["[Palenight]"])
        let scope = try #require(customizations["[Palenight]"]?.objectValue)
        #expect(scope[ThemeKey.inputBorder] == .string(divider.color.hex))
        #expect(scope[ThemeKey.inputFocusBorder] == .string(divider.color.hex))
        #expect(scope[MessageBoxBorderCustomizations.markerKey] == .array(["input.border", "input.focusBorder"]))

        // The marker is neither a problem nor a color.
        #expect(ThemeOverrides.problems(in: customizations).isEmpty)
        #expect(ThemeOverrides.problems(in: ["[Palenight]": .object(["$borderPicker": "input.border"])]).count == 1)
        let overrides = ThemeOverrides(customizations: customizations, themeName: "Palenight", themeID: "palenight")
        #expect(overrides.colors[MessageBoxBorderCustomizations.markerKey] == nil)
        // The color shows focused or not.
        let theme = try resolved(palette, with: customizations)
        #expect(theme.color(ThemeKey.inputBorder) == divider.color)
        #expect(theme.color(ThemeKey.inputFocusBorder) == divider.color)
        // Not counted as the user's own overrides.
        #expect(AccentCustomizations.handWrittenCount(in: customizations) == 0)
        // The schema knows the marker.
        #expect(ThemeSchema.colorCustomizationsSchema()["patternProperties"]?["^\\[.+\\]$"]?["properties"]?["$borderPicker"] != nil)
    }

    @Test("Choosing a swatch reads back as that swatch", arguments: MessageBoxBorderSwatchTests.themes)
    func roundTrip(id: String) throws {
        let palette = try builtInBorderPalette(id)
        #expect(palette.choice(in: [:]) == .swatch(palette.defaultSwatch))
        for swatch in palette.swatches {
            let customizations = palette.applying(swatch, to: [:])
            #expect(palette.choice(in: customizations) == .swatch(swatch), "\(id): \(swatch.name)")
            #expect((MessageBoxBorderCustomizations.color(in: customizations, themeName: palette.themeName, themeID: id) == nil) == swatch.isDefault)
        }
        // Custom…: any color, alpha included.
        let custom = palette.applying(color: hex("#12345680"), to: [:])
        #expect(palette.choice(in: custom) == .custom(hex("#12345680")))
        #expect(custom["[\(palette.themeName)]"]?.objectValue?[ThemeKey.inputBorder] == .string("#12345680"))
        // Set by hand in settings.json.
        #expect(palette.choice(in: ["input.border": "#123456"]) == .custom(hex("#123456")))
    }

    @Test func defaultRemovesOnlyThePickersTokens() throws {
        let palette = try builtInBorderPalette("palenight")
        let original: [String: JSONValue] = [
            "chat.background": "#000000",
            "[Palenight]": .object(["chat.link": "#FF0000"]),
            "[Nord]": .object(["input.border": "#00FF00"]),
        ]
        var customizations = original
        for swatch in palette.swatches.dropFirst() {
            customizations = palette.applying(swatch, to: customizations)
        }
        customizations = palette.applying(color: hex("#ABCDEF"), to: customizations)
        // Switching colors leaves nothing stale behind.
        #expect(customizations == palette.applying(color: hex("#ABCDEF"), to: original))
        #expect(customizations["[Nord]"] == original["[Nord]"])

        let reset = palette.applying(palette.defaultSwatch, to: customizations)
        #expect(reset == original)
        #expect(palette.removing(from: original) == original)
        // A scope that only held the picker's tokens disappears.
        #expect(palette.applying(palette.defaultSwatch, to: palette.applying(color: hex("#ABCDEF"), to: [:])) == [:])
    }

    @Test func eachThemeKeepsItsOwnColor() throws {
        let palenight = try builtInBorderPalette("palenight")
        let lighter = try builtInBorderPalette("lighter")
        var customizations = palenight.applying(color: hex("#111111"), to: [:])
        customizations = lighter.applying(color: hex("#EEEEEE"), to: customizations)
        #expect(palenight.choice(in: customizations) == .custom(hex("#111111")))
        #expect(lighter.choice(in: customizations) == .custom(hex("#EEEEEE")))
        customizations = lighter.removing(from: customizations)
        #expect(palenight.choice(in: customizations) == .custom(hex("#111111")))
        #expect(lighter.choice(in: customizations) == .swatch(lighter.defaultSwatch))
    }
}

@Suite("Message box border: with the accent picker")
struct MessageBoxBorderAccentTests {
    let accent: AccentPalette
    let border: MessageBoxBorderPalette
    let cyan: AccentSwatch
    let color = hex("#4A4F6A")

    init() throws {
        accent = try builtInPalette("palenight")
        border = MessageBoxBorderPalette(accentPalette: accent)
        cyan = try #require(accent.swatches.first { $0.name == "Cyan" })
    }

    /// Palenight sets input.focusBorder to its accent, so the accent picker
    /// recolors it.
    @Test func accentPickerRecolorsTheFocusBorder() throws {
        let customizations = accent.applying(cyan, to: [:])
        let generated = AccentCustomizations.generatedKeys(in: customizations, themeName: "Palenight", themeID: "palenight")
        #expect(generated.contains(ThemeKey.inputFocusBorder))
        #expect(try resolved(accent, with: customizations).color(ThemeKey.inputFocusBorder) == hex("#89DDFF"))
    }

    @Test func borderAfterAccentWins() throws {
        var customizations = accent.applying(cyan, to: [:])
        customizations = border.applying(color: color, to: customizations)

        let scope = try #require(customizations["[Palenight]"]?.objectValue)
        let accentKeys = AccentCustomizations.markerKeys(in: scope)
        #expect(!accentKeys.contains(ThemeKey.inputFocusBorder), "the border picker took the token over")
        #expect(accentKeys.contains(ThemeKey.accent))
        var theme = try resolved(accent, with: customizations)
        #expect(theme.color(ThemeKey.inputFocusBorder) == color)
        #expect(theme.color(ThemeKey.inputBorder) == color)
        #expect(theme.color(ThemeKey.accent) == hex("#89DDFF"))

        // Picking another accent, or the same one, keeps the border.
        let green = try #require(accent.swatches.first { $0.name.contains("Green") })
        for swatch in [green, cyan] {
            customizations = accent.applying(swatch, to: customizations)
            theme = try resolved(accent, with: customizations)
            #expect(theme.color(ThemeKey.inputFocusBorder) == color, "\(swatch.name)")
            #expect(theme.color(ThemeKey.accent) == swatch.color)
            #expect(border.choice(in: customizations) == .custom(color))
        }
        // Resetting the accent keeps it too.
        customizations = accent.applying(accent.defaultSwatch, to: customizations)
        theme = try resolved(accent, with: customizations)
        #expect(theme.color(ThemeKey.inputFocusBorder) == color)
        #expect(theme.color(ThemeKey.accent) == hex("#C792EA"))
        #expect(customizations == border.applying(color: color, to: [:]))
        #expect(AccentCustomizations.handWrittenCount(in: customizations) == 0)
    }

    @Test func accentAfterBorderLeavesTheBorderAlone() throws {
        var customizations = border.applying(color: color, to: [:])
        customizations = accent.applying(cyan, to: customizations)

        #expect(Array(customizations.keys) == ["[Palenight]"], "both pickers share the theme's scope")
        let scope = try #require(customizations["[Palenight]"]?.objectValue)
        #expect(!AccentCustomizations.markerKeys(in: scope).contains(ThemeKey.inputFocusBorder))
        #expect(MessageBoxBorderCustomizations.markerKeys(in: scope) == [ThemeKey.inputBorder, ThemeKey.inputFocusBorder])
        let theme = try resolved(accent, with: customizations)
        #expect(theme.color(ThemeKey.inputFocusBorder) == color)
        #expect(theme.color(ThemeKey.accent) == hex("#89DDFF"))
        #expect(accent.choice(in: customizations) == .swatch(cyan))
        #expect(border.choice(in: customizations) == .custom(color))
        // Picking it again lands on the same file as picking it in the other order.
        #expect(customizations == border.applying(color: color, to: accent.applying(cyan, to: [:])))
    }

    @Test func borderDefaultBringsTheAccentsFocusBorderBack() throws {
        // Either order, then Default for the border.
        let orders = [
            border.applying(color: color, to: accent.applying(cyan, to: [:])),
            accent.applying(cyan, to: border.applying(color: color, to: [:])),
        ]
        for customizations in orders {
            let reset = border.removing(from: customizations)
            #expect(reset == accent.applying(cyan, to: [:]), "exactly what picking Cyan alone writes")
            let theme = try resolved(accent, with: reset)
            #expect(theme.color(ThemeKey.inputFocusBorder) == hex("#89DDFF"))
            #expect(theme.color(ThemeKey.inputBorder) == accent.base.color(ThemeKey.inputBorder))
            #expect(border.choice(in: reset) == .swatch(border.defaultSwatch))
        }
        // Without an accent picked, Default leaves the theme's own colors.
        let plain = border.removing(from: border.applying(color: color, to: [:]))
        #expect(plain == [:])
    }

    @Test func handWrittenBorderIsCustomAndStays() throws {
        let original: [String: JSONValue] = ["[Palenight]": .object(["input.border": "#222222"])]
        #expect(border.choice(in: original) == .custom(hex("#222222")))
        // Default only removes what the picker wrote.
        #expect(border.removing(from: original) == original)
        // The accent picker's own focus border isn't read as a border color.
        #expect(border.choice(in: accent.applying(cyan, to: [:])) == .swatch(border.defaultSwatch))
    }
}
