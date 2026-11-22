// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaTheme

/// Look-alike nick colors are moved a little apart when a theme resolves,
/// within limits that keep the theme's look.
@Suite("Nick palette spreading")
struct NickPaletteSpreadTests {
    private let similar = NickPaletteGeometry.oklabSimilar

    private func builtIn(_ id: String, colors: [String: String] = [:]) throws -> ResolvedTheme {
        let definition = try #require(ThemeLoader.builtInDefinitions[id])
        return try ThemeResolver.resolve(
            definition, id: id,
            includeLoader: { try ThemeLoader.builtInDefinition(named: $0) },
            overrides: ThemeOverrides(colors: colors)
        )
    }

    private var builtInIDs: [String] { ThemeLoader.builtInDefinitions.keys.sorted() }

    /// The palette as the theme writes it, minus colors that read as text:
    /// what's spread.
    private func written(_ theme: ResolvedTheme) -> [ThemeColor] {
        ResolvedTheme.usableNickPalette(theme.nickColors, colors: theme.colors)
    }

    /// Indexes of the colors given to other people (all but yours).
    private func handedOut(_ theme: ResolvedTheme) -> [Int] {
        theme.nickPalette.indices.filter { !theme.nickPaletteGeometry.reserved.contains($0) }
    }

    /// The closest pair among `indexes` of `colors`.
    private func closest(_ colors: [ThemeColor], among indexes: [Int]? = nil) -> Double {
        let indexes = indexes ?? Array(colors.indices)
        var closest = Double.infinity
        for i in indexes {
            for j in indexes where j > i { closest = min(closest, colors[i].distance(to: colors[j])) }
        }
        return closest
    }

    /// Palenight's look-alikes: blue and lavender 0.058 apart, red and
    /// orange 0.070, teal and cyan 0.087. Everyone given a color now gets
    /// one clearly different from everyone else's.
    @Test func palenightsColorsAreToldApart() throws {
        let theme = try builtIn("palenight")
        let before = written(theme)
        #expect(closest(before) < 0.06)
        #expect(closest(theme.nickPalette, among: handedOut(theme)) >= similar)
        // Its yellow, cyan and your own purple are left as written.
        for hex in ["#FFCB6B", "#89DDFF", "#C792EA"] {
            #expect(theme.nickPalette.map(\.hex).contains(hex), "\(hex)")
        }
    }

    /// The report: two people in Palenight given its blue and its lavender,
    /// side by side. With your own color away from both (another accent),
    /// both are handed out, and now clearly different.
    @Test func theBlueAndLavenderFromTheReport() throws {
        for accent in ["#FFCB6B", "#F78C6C", "#C3E88D"] {
            let theme = try builtIn("palenight", colors: ["accent": accent, "accentText": accent, "chat.selfNick": accent])
            let blue = 6, lavender = 7
            #expect(written(theme)[blue].hex == "#82AAFF" && written(theme)[lavender].hex == "#A9B4FF")
            #expect(handedOut(theme).contains(blue) && handedOut(theme).contains(lavender), "\(accent)")
            #expect(theme.nickPalette[blue].distance(to: theme.nickPalette[lavender]) >= similar, "\(accent)")
        }
    }

    @Test func otherBuiltInsAreToldApartToo() throws {
        let ids = [
            "darker", "gruvbox-dark", "lighter", "ocean", "oceanic", "one-dark",
            "sandy-beach", "solarized-dark", "solarized-light",
        ]
        for id in ids {
            let theme = try builtIn(id)
            #expect(closest(theme.nickPalette, among: handedOut(theme)) >= similar, "\(id)")
        }
        // Nearly: Tokyo Night's orange and gold (0.061 apart as written) and
        // Dracula's two greens (0.034) end up as far apart as the limits
        // allow, a hair short.
        for id in ["tokyo-night", "dracula"] {
            let theme = try builtIn(id)
            #expect(closest(written(theme)) < 0.07, "\(id)")
            #expect(closest(theme.nickPalette, among: handedOut(theme)) >= 0.1, "\(id)")
        }
    }

    /// The limits, for every built-in theme: a color moves only when it
    /// looks like another (or like yours), never far, stays readable and
    /// apart from the text, and the colors handed out only get further
    /// apart.
    @Test func everyBuiltInKeepsItsLook() throws {
        for id in builtInIDs {
            let theme = try builtIn(id)
            let before = written(theme)
            let after = theme.nickPalette
            #expect(after.count == before.count, "\(id)")
            let text = theme.color(ThemeKey.chatForeground)
            let background = theme.color(ThemeKey.chatBackground)
            let me = theme.color(ThemeKey.chatSelfNick)
            for (index, (was, now)) in zip(before, after).enumerated() {
                #expect(now.distance(to: was) <= NickPaletteSpread.maximumChange, "\(id) \(was.hex) → \(now.hex)")
                #expect(now.chroma <= was.chroma + NickPaletteSpread.maximumChromaGain + 0.003, "\(id) \(was.hex) → \(now.hex)")
                #expect(now.chroma >= was.chroma * (1 - NickPaletteSpread.maximumChromaLoss) - 0.003, "\(id) \(was.hex) → \(now.hex)")
                if was.chroma > 0.02 && now.chroma > 0.02 {
                    let turn = abs(now.hue - was.hue)
                    #expect(min(turn, 360 - turn) <= NickPaletteSpread.maximumHueTurn + 0.5, "\(id) \(was.hex) → \(now.hex)")
                }
                #expect(now.contrastRatio(against: background) >= min(ThemeAudit.nickMinimum, was.contrastRatio(against: background)), "\(id) \(now.hex)")
                if ResolvedTheme.isDistinctNickColor(was, text: text, background: background) {
                    #expect(ResolvedTheme.isDistinctNickColor(now, text: text, background: background), "\(id) \(now.hex)")
                }
                // A color like no other, and not like yours, is as written.
                let alone = before.indices.allSatisfy { $0 == index || before[$0].distance(to: was) >= similar }
                if alone && was.distance(to: me) >= similar {
                    #expect(now == was, "\(id) \(was.hex) → \(now.hex)")
                }
            }
            // As many colors handed out as before, or more, and further apart.
            let reservedBefore = ResolvedTheme.selfLikeNickColors(before, selfNick: me)
            let handedBefore = before.indices.filter { !reservedBefore.contains($0) }
            #expect(handedOut(theme).count >= handedBefore.count, "\(id)")
            #expect(closest(after, among: handedOut(theme)) >= closest(before, among: handedBefore) - 1e-9, "\(id)")
            // Nobody else is given a color like yours.
            for index in handedOut(theme) {
                #expect(after[index].distance(to: me) >= similar, "\(id) \(after[index].hex)")
            }
            // The audit's contrast for nick colors holds for the spread ones.
            let chat = ThemeAudit.surface(ThemeKey.chatBackground, in: theme)
            for (was, now) in zip(before, after) where was.contrastRatio(against: chat) >= ThemeAudit.nickMinimum {
                #expect(now.contrastRatio(against: chat) >= ThemeAudit.nickMinimum, "\(id) \(now.hex)")
            }
        }
    }

    /// Colors all clearly different from each other, one of them your own:
    /// nothing moves.
    @Test func clearlyDifferentColorsAreLeftAlone() throws {
        let palette = try ["#F07178", "#C3E88D", "#89DDFF", "#C792EA"].map { try #require(ThemeColor(hex: $0)) }
        let spread = NickPaletteSpread.spread(
            palette, text: ThemeColor(hex: "#BFC7D5"), background: ThemeColor(hex: "#292D3E"),
            selfNick: ThemeColor(hex: "#C792EA"), accent: ThemeColor(hex: "#C792EA")
        )
        #expect(spread == palette)
    }

    /// The same palette always spreads the same way (each call here is
    /// worked out anew: the far-off accents make the inputs differ).
    @Test func deterministic() throws {
        let theme = try builtIn("vela-graphite")
        let palette = written(theme)
        func spread(accent: String) -> [ThemeColor] {
            NickPaletteSpread.spread(
                palette, text: theme.color(ThemeKey.chatForeground), background: theme.color(ThemeKey.chatBackground),
                selfNick: theme.color(ThemeKey.chatSelfNick), accent: ThemeColor(hex: accent)
            )
        }
        #expect(spread(accent: "#000001") == spread(accent: "#000002"))
        #expect(spread(accent: "#000001") == theme.nickPalette)
    }

    /// Of a look-alike pair, the theme's accent stays as it is while the
    /// other color can move instead.
    @Test func theAccentStaysPut() throws {
        let palette = try ["#82AAFF", "#A9B4FF", "#F07178", "#C3E88D"].map { try #require(ThemeColor(hex: $0)) }
        for (anchor, other) in [(0, 1), (1, 0)] {
            let spread = NickPaletteSpread.spread(
                palette, text: ThemeColor(hex: "#BFC7D5"), background: ThemeColor(hex: "#292D3E"),
                selfNick: nil, accent: palette[anchor]
            )
            #expect(spread[anchor] == palette[anchor])
            #expect(spread[other] != palette[other])
            #expect(spread[anchor].distance(to: spread[other]) >= similar)
            #expect(Array(spread[2...]) == Array(palette[2...]))
        }
    }

    /// A palette of pastels at one lightness can't all be told apart
    /// within the limits: it's spread as far as they allow.
    @Test func aCrowdedPaletteIsSpreadAsFarAsAllowed() throws {
        let theme = try builtIn("vela-graphite")
        let before = written(theme)
        #expect(closest(before) < 0.045)
        let after = closest(theme.nickPalette, among: handedOut(theme))
        #expect(after > 0.06 && after < similar)
    }

    /// Spreading is done once per palette and remembered, so the many
    /// resolves of one theme (previews, accent choices) don't repeat it.
    @Test func cheapOnceDone() throws {
        let theme = try builtIn("vela-paper")
        let palette = written(theme)
        let clock = ContinuousClock()
        let first = NickPaletteSpread.spread(palette, colors: theme.colors)
        let again = clock.measure {
            for _ in 0..<100 { _ = NickPaletteSpread.spread(palette, colors: theme.colors) }
        }
        #expect(first == theme.nickPalette)
        #expect(again < .milliseconds(50))
    }
}
