// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaTheme

@Suite("Vibrancy")
struct ThemeVibrancyTests {
    @Test func reduceTransparencyDrawsEveryThemeOpaque() {
        for vibrancy in ThemeVibrancy.allCases {
            #expect(vibrancy.effective(reduceTransparency: true) == .none)
            #expect(vibrancy.effective(reduceTransparency: false) == vibrancy)
        }
        #expect(!ThemeVibrancy.none.isTranslucent)
        #expect(ThemeVibrancy.sidebar.isTranslucent)
        #expect(ThemeVibrancy.window.isTranslucent)
    }

    @Test func whatEachValuePutsOnAMaterial() {
        for surface in ThemeSurface.allCases {
            #expect(ThemeVibrancy.none.material(for: surface) == nil)
        }
        #expect(ThemeVibrancy.sidebar.material(for: .sidebar) == .sidebar)
        #expect(ThemeVibrancy.sidebar.material(for: .tabs) == .sidebar)
        #expect(ThemeVibrancy.sidebar.material(for: .content) == nil)
        #expect(ThemeVibrancy.window.material(for: .sidebar) == .sidebar)
        #expect(ThemeVibrancy.window.material(for: .tabs) == .window)
        #expect(ThemeVibrancy.window.material(for: .content) == .window)
    }

    @Test func opaqueColorsTintTranslucentOnesAreUsedAsWritten() {
        let opaque = hex("#292D3E")
        #expect(ThemeVibrancy.tint(opaque).alpha == ThemeVibrancy.tintOpacity)
        #expect(ThemeVibrancy.tint(opaque).withAlpha(1) == opaque)
        let translucent = hex("#292D3E80")
        #expect(ThemeVibrancy.tint(translucent) == translucent)
        let clear = hex("#292D3E00")
        #expect(ThemeVibrancy.tint(clear).alpha == 0)
    }

    @Test func surfaceColorsFollowTheMaterialRules() throws {
        let theme = try resolve(ThemeDefinition(name: "T", type: .dark, colors: [
            "sidebar.background": "#202020",
            "chat.background": "#303030",
        ]))
        #expect(theme.surfaceColor(ThemeKey.sidebarBackground, on: .sidebar, vibrancy: .none).alpha == 1)
        #expect(theme.surfaceColor(ThemeKey.sidebarBackground, on: .sidebar, vibrancy: .sidebar).alpha == ThemeVibrancy.tintOpacity)
        #expect(theme.surfaceColor(ThemeKey.chatBackground, on: .content, vibrancy: .sidebar).alpha == 1)
        #expect(theme.surfaceColor(ThemeKey.chatBackground, on: .content, vibrancy: .window).alpha == ThemeVibrancy.tintOpacity)
        // Reduce Transparency: the effective vibrancy is none, so opaque again.
        let effective = ThemeVibrancy.window.effective(reduceTransparency: true)
        #expect(theme.surfaceColor(ThemeKey.chatBackground, on: .content, vibrancy: effective).alpha == 1)
    }

    @Test func materialStandInIsTheLeastFavorableDesktop() {
        // Dark themes are measured over a bright desktop, light ones over a dark one.
        #expect(ThemeVibrancy.materialStandIn(for: .dark).hex == "#404040")
        #expect(ThemeVibrancy.materialStandIn(for: .light).hex == "#BFBFBF")
        #expect(ThemeVibrancy.materialStandIn(for: .dark).alpha == 1)
    }

    @Test func vibrancyResolvesFromOverridesThenThemeThenInclude() throws {
        let base = ThemeDefinition(name: "Base", type: .dark, vibrancy: .window)
        let child = ThemeDefinition(name: "Child", type: .dark, include: "Base")
        let loader: (String) throws -> ThemeDefinition? = { $0 == "Base" ? base : nil }
        #expect(try ThemeResolver.resolve(child, id: "child", includeLoader: loader, overrides: ThemeOverrides()).vibrancy == .window)
        var own = child
        own.vibrancy = ThemeVibrancy.none
        #expect(try ThemeResolver.resolve(own, id: "child", includeLoader: loader, overrides: ThemeOverrides()).vibrancy == .none)
        #expect(try ThemeResolver.resolve(own, id: "child", includeLoader: loader, overrides: ThemeOverrides(vibrancy: .sidebar)).vibrancy == .sidebar)
    }

    @Test func auditMeasuresVibrantSurfacesOverTheStandIn() throws {
        // Grey sidebar text on a barely-there sidebar tint: fine on the
        // black window, unreadable over a bright desktop.
        var definition = ThemeDefinition(name: "Faint", type: .dark, colors: [
            "window.background": "#000000",
            "sidebar.background": "#00000020",
            "sidebar.foreground": "#888888",
        ])
        func sidebarCheck(_ theme: ResolvedTheme) throws -> ThemeAudit.Finding {
            try #require(ThemeAudit.audit(theme).first {
                $0.foreground == ThemeKey.sidebarForeground && $0.background == ThemeKey.sidebarBackground
            })
        }
        let opaque = try sidebarCheck(try resolve(definition))
        #expect(opaque.passes)
        definition.vibrancy = .sidebar
        let vibrant = try sidebarCheck(try resolve(definition))
        #expect(!vibrant.passes)
        let expected = hex("#888888").contrastRatio(against: hex("#00000020").composited(over: ThemeVibrancy.materialStandIn(for: .dark)))
        #expect(abs(vibrant.ratio - expected) < 0.001)
    }

    @Test func auditLeavesContentAloneWithSidebarVibrancy() throws {
        let palenight = try #require(try ThemeLoader.builtInDefinition(named: "Palenight"))
        var glass = palenight
        glass.vibrancy = .sidebar
        let opaque = try ThemeResolver.resolve(palenight, id: "p", includeLoader: { _ in nil }, overrides: ThemeOverrides())
        let vibrant = try ThemeResolver.resolve(glass, id: "p", includeLoader: { _ in nil }, overrides: ThemeOverrides())
        func ratio(_ theme: ResolvedTheme, _ foreground: String, _ background: String) -> Double? {
            ThemeAudit.audit(theme).first { $0.foreground == foreground && $0.background == background }?.ratio
        }
        // The conversation isn't on a material with "sidebar".
        #expect(ratio(opaque, ThemeKey.chatForeground, ThemeKey.chatBackground) == ratio(vibrant, ThemeKey.chatForeground, ThemeKey.chatBackground))
        // The sidebar is, and Palenight's tint keeps it readable.
        #expect(ratio(opaque, ThemeKey.sidebarForeground, ThemeKey.sidebarBackground) != ratio(vibrant, ThemeKey.sidebarForeground, ThemeKey.sidebarBackground))
        #expect(ThemeAudit.audit(vibrant).filter { $0.background == ThemeKey.sidebarBackground }.allSatisfy { $0.passes })
    }

    @Test func windowVibrancyTintsMessageRowsToo() throws {
        let theme = try resolve(ThemeDefinition(name: "W", type: .dark, colors: [
            "chat.background": "#202020",
            "chat.foreground": "#EEEEEE",
            "chat.highlightBackground": "#403020",
        ], vibrancy: .window))
        let finding = try #require(ThemeAudit.audit(theme).first {
            $0.foreground == ThemeKey.chatForeground && $0.background == ThemeKey.chatHighlightBackground
        })
        let chat = ThemeVibrancy.tint(hex("#202020")).composited(over: ThemeVibrancy.materialStandIn(for: .dark))
        let expected = hex("#EEEEEE").contrastRatio(against: ThemeVibrancy.tint(hex("#403020")).composited(over: chat))
        #expect(abs(finding.ratio - expected) < 0.001)
    }
}
