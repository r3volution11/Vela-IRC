// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
@testable import VelaUI

/// Fit first, then scroll: how a row of tabs shares the strip
/// (`TabFit.plan`), how a tab gives up width (`TabLabelLayout`), where a
/// title fades (`TabTitleFadeLayout`) and the sizes that go into them.
/// Pure; the hosted rows are in `TabFitHostedTests`.
@Suite("Fitting tabs")
struct TabFitTests {
    private static let minWidth: CGFloat = 58

    /// An unselected tab.
    private func tab(_ natural: CGFloat, floor: CGFloat = minWidth) -> TabFitItem {
        TabFitItem(natural: natural, floor: max(floor, Self.minWidth))
    }

    /// The selected tab, or a button: always natural.
    private func fixed(_ natural: CGFloat) -> TabFitItem {
        TabFitItem(natural: natural, isTrimmable: false)
    }

    // MARK: Fit first

    @Test func everythingIsNaturalWhenItFits() {
        let items = [tab(58), tab(120), fixed(150), fixed(23)]
        let plan = TabFit.plan(items, spacing: 2, available: 400)
        #expect(!plan.isScrolling)
        #expect(plan.cap == nil)
        #expect(plan.widths == [58, 120, 150, 23])
        #expect(plan.totalWidth == 357)
        #expect((0..<4).allSatisfy { !plan.isTrimmed($0) })
    }

    @Test func shortNamesStayWholeAndLongOnesAreCappedEqually() {
        // #dn and #vela, three long names, the selected tab and the +.
        let items = [tab(58), tab(70), tab(200), tab(160), tab(240), fixed(100), fixed(23)]
        let plan = TabFit.plan(items, spacing: 0, available: 58 + 70 + 100 + 23 + 3 * 120)
        #expect(!plan.isScrolling)
        #expect(plan.cap == 120)
        #expect(plan.widths == [58, 70, 120, 120, 120, 100, 23])
        #expect((0..<7).map(plan.isTrimmed) == [false, false, true, true, true, false, false])
    }

    @Test func theCapIsTheLargestThatFits() {
        // 90 stays whole, and so does 150 once the cap passes it: 90 + 150 + W = 400.
        let plan = TabFit.plan([tab(90), tab(150), tab(300)], spacing: 0, available: 400)
        #expect(plan.cap == 160)
        #expect(plan.widths == [90, 150, 160])
        // A fraction short of a whole point: rounded down, never over.
        let fraction = TabFit.plan([tab(200), tab(200), tab(200)], spacing: 0, available: 400)
        #expect(fraction.cap == 133)
        #expect(fraction.widths == [133, 133, 133])
        #expect(fraction.totalWidth <= 400)
    }

    @Test func theSelectedTabKeepsItsNaturalWidth() {
        let items = [tab(200), fixed(260), tab(200), tab(200)]
        let plan = TabFit.plan(items, spacing: 0, available: 260 + 3 * 80)
        #expect(plan.widths == [80, 260, 80, 80])
        #expect(!plan.isTrimmed(1))
        // Its neighbors go down to their floor before it gives anything up.
        let tight = TabFit.plan(items, spacing: 0, available: 260 + 3 * 58)
        #expect(tight.widths == [58, 260, 58, 58])
        #expect(!tight.isScrolling)
    }

    @Test func noTabGoesBelowTheMinimumWidth() {
        let items = (0..<6).map { _ in tab(150) } + [fixed(120)]
        let floors = 6 * Self.minWidth + 120
        let atFloor = TabFit.plan(items, spacing: 0, available: floors)
        #expect(!atFloor.isScrolling)
        #expect(atFloor.widths.prefix(6).allSatisfy { $0 == Self.minWidth })
        // A point less and they'd have to: the row scrolls, every tab whole.
        let short = TabFit.plan(items, spacing: 0, available: floors - 1)
        #expect(short.isScrolling)
        #expect(short.cap == nil)
        #expect(short.widths == items.map(\.natural))
    }

    @Test func aGlyphSlotOrBadgeRaisesATabsFloor() {
        // A short tab with a big badge can't go below what its slot,
        // padding and badge take, though the others go to 60.
        let items = [tab(140, floor: 75), tab(140), tab(140), fixed(23)]
        let plan = TabFit.plan(items, spacing: 0, available: 75 + 60 + 60 + 23)
        #expect(plan.widths == [75, 60, 60, 23])
        #expect(TabFit.plan(items, spacing: 0, available: 75 + 58 + 58 + 23 - 1).isScrolling)
        // A floor is never above the tab's natural width.
        #expect(TabFitItem(natural: 50, floor: 58).floor == 50)
    }

    @Test func gapsTakeRoomToo() {
        let items = (0..<5).map { _ in tab(100) }
        let floors = 5 * Self.minWidth
        #expect(!TabFit.plan(items, spacing: 4, available: floors + 16).isScrolling)
        #expect(TabFit.plan(items, spacing: 4, available: floors + 15).isScrolling)
        let plan = TabFit.plan(items, spacing: 4, available: 5 * 80 + 16)
        #expect(plan.cap == 80)
        #expect(plan.totalWidth == 416)
    }

    // MARK: Then scroll

    @Test func scrollingNeedsMoreRoomToStop() {
        let items = (0..<8).map { _ in tab(140) } + [fixed(160), fixed(23)]
        let required = 8 * Self.minWidth + 160 + 23
        let h = TabFit.hysteresis
        #expect(h > 0)
        // Fitting: until the floors don't fit.
        #expect(!TabFit.plan(items, spacing: 0, available: required, wasScrolling: false).isScrolling)
        #expect(TabFit.plan(items, spacing: 0, available: required - 1, wasScrolling: false).isScrolling)
        // Scrolling: until there's `hysteresis` to spare.
        #expect(TabFit.plan(items, spacing: 0, available: required, wasScrolling: true).isScrolling)
        #expect(TabFit.plan(items, spacing: 0, available: required + h - 1, wasScrolling: true).isScrolling)
        #expect(!TabFit.plan(items, spacing: 0, available: required + h, wasScrolling: true).isScrolling)
        // A name a point longer either way doesn't flip it.
        var longer = items
        longer[0].natural += 1
        #expect(TabFit.plan(longer, spacing: 0, available: required + 1, wasScrolling: true).isScrolling)
        // With room for every tab whole, there's nothing to scroll or trim.
        let roomy = TabFit.plan(items, spacing: 0, available: 8 * 140 + 183, wasScrolling: true)
        #expect(!roomy.isScrolling)
        #expect(roomy.cap == nil)
    }

    @Test func manyTabsScroll() {
        let many = (0..<500).map { tab(CGFloat(60 + $0 % 140)) } + [fixed(120), fixed(23)]
        let clock = ContinuousClock()
        var plan: TabFitPlan?
        let elapsed = clock.measure {
            for _ in 0..<20 { plan = TabFit.plan(many, spacing: 2, available: 1400) }
        }
        #expect(plan?.isScrolling == true)
        #expect(plan?.widths == many.map(\.natural))
        // Laid out on every frame of a window resize: well under a millisecond each.
        #expect(elapsed < .milliseconds(100), "\(elapsed) for 20")

        // Twenty fit, and share the room evenly.
        let twenty = (0..<20).map { _ in tab(120) } + [fixed(120)]
        let fitted = TabFit.plan(twenty, spacing: 0, available: 1400)
        #expect(!fitted.isScrolling)
        #expect(fitted.cap == ((1400 - 120) / 20).rounded(.down))
    }

    @Test func oneTab() {
        // Selected, it's whole, and scrolls when it's longer than the strip.
        #expect(TabFit.plan([fixed(300)], spacing: 0, available: 1000).widths == [300])
        let long = TabFit.plan([fixed(300), fixed(23)], spacing: 2, available: 200)
        #expect(long.isScrolling)
        #expect(long.widths == [300, 23])
        // Unselected, it's trimmed to the strip.
        let trimmed = TabFit.plan([tab(300)], spacing: 0, available: 200)
        #expect(trimmed.widths == [200])
        #expect(trimmed.isTrimmed(0))
        // Nothing measured yet: natural.
        #expect(TabFit.plan([tab(300)], spacing: 0, available: nil).widths == [300])
    }

    @Test func theSelectedTabLongerThanTheStripScrolls() {
        let items = [tab(80), fixed(900), tab(120)]
        let plan = TabFit.plan(items, spacing: 0, available: 800)
        #expect(plan.isScrolling)
        #expect(plan.widths == [80, 900, 120])
    }

    @Test func theWaterLevelIsTheHighestThatFits() {
        var random = SeededRandom(seed: 7)
        for _ in 0..<200 {
            let items = (0..<Int.random(in: 1...12, using: &random)).map { _ in
                let floor = CGFloat(Int.random(in: 58...90, using: &random))
                return TabFitItem(natural: floor + CGFloat(Int.random(in: 0...200, using: &random)), floor: floor)
            }
            let floors = items.reduce(0) { $0 + $1.floor }
            let naturals = items.reduce(0) { $0 + $1.natural }
            let budget = CGFloat.random(in: floors...naturals, using: &random)
            let level = TabFit.waterLevel(items, budget: budget)
            func filled(_ w: CGFloat) -> CGFloat { items.reduce(0) { $0 + min($1.natural, max($1.floor, w)) } }
            #expect(filled(level) <= budget + 0.02)
            #expect(level >= (items.map(\.natural).max() ?? 0) - 0.01 || filled(level + 0.05) > budget)
        }
    }

    // MARK: A tab's label

    @Test func onlyTheTitleGivesWay() {
        // A channel tab at the default size: slot and its insets lead (5 +
        // 17 + 2), 10 trails, and a badge 18 wide follows the title.
        let layout = TabLabelLayout(leading: 24, trailing: 10, spacing: 5, minWidth: 58)
        let span = layout.span(parts: [18], title: 120)
        #expect(span.fixed == 57)
        #expect(span.natural == 177)
        #expect(span.narrowest == 58)
        #expect(span.titleWidth(in: span.natural) == 120)
        #expect(span.titleWidth(in: 100) == 43)
        #expect(span.titleWidth(in: 40) == 0)
        // A badge too wide for the minimum: the slot and badge stay whole.
        let wide = layout.span(parts: [30], title: 120)
        #expect(wide.narrowest == 69)
        // A short name is padded out to the minimum after its title.
        #expect(layout.span(parts: [], title: 15).natural == 58)
        // No title: an icon-only console.
        let icon = TabLabelLayout(leading: 8, trailing: 8, spacing: 5, minWidth: 35, centers: true).span(parts: [12], title: nil)
        #expect(icon.natural == 35)
        #expect(icon.narrowest == icon.natural)
    }

    @Test func onlyACutTitleFades() {
        #expect(TabTitleFadeLayout.fade(width: 100, textWidth: 100, fadeLength: 14) == 0)
        #expect(TabTitleFadeLayout.fade(width: 120, textWidth: 100, fadeLength: 14) == 0)
        #expect(TabTitleFadeLayout.fade(width: 99.6, textWidth: 100, fadeLength: 14) == 0)
        #expect(TabTitleFadeLayout.fade(width: 99, textWidth: 100, fadeLength: 14) == 14)
        // Never more than half of what's left of it.
        #expect(TabTitleFadeLayout.fade(width: 20, textWidth: 100, fadeLength: 14) == 10)
    }

    // MARK: Sizes

    private static func metrics(height: Double = 28, roundness: Double = 0.35, appearance: TabAppearance = .floating) -> TabMetrics {
        var style = ChatStyle()
        style.tabHeight = height
        style.tabRoundness = roundness
        return TabMetrics(style: style, height: TabMetrics.channelHeight(style), appearance: appearance)
    }

    @Test func theMinimumWidthIsAboutAQuarterLess() {
        let metrics = Self.metrics()
        #expect(metrics.minWidth == 58)
        // It was the padding and four slots: 78.
        let before = (metrics.horizontalPadding + metrics.closeSlot * 4).rounded()
        #expect(abs(1 - metrics.minWidth / before - 0.25) < 0.02)
        // Still scaling with the tab's size and roundness.
        #expect(Self.metrics(height: 40).minWidth > metrics.minWidth)
        #expect(Self.metrics(height: 22).minWidth < metrics.minWidth)
        #expect(Self.metrics(roundness: 1).minWidth > Self.metrics(roundness: 0).minWidth)
    }

    @Test func theFadeIsTwelveToSixteenPoints() {
        for height in [18.0, 22, 28, 36, 48] {
            let fade = Self.metrics(height: height).titleFade
            #expect((12...16).contains(fade), "height \(height): \(fade)")
        }
        #expect(Self.metrics().titleFade == 14)
    }

    @Test func titleWidthsAreMeasuredOnceAndMatchTheirText() {
        let widths = TabTextWidths()
        for (text, size, weight) in [("vela", 12.0, Font.Weight.semibold), ("a-channel-with-a-long-name", 12, .regular), ("Libera.Chat", 10.5, .medium), ("ñandú 🌍", 15, .semibold)] {
            let measured = widths.width(of: text, size: size, weight: weight)
            let host = NSHostingView(rootView: Text(text).font(.system(size: size, weight: weight)).fixedSize())
            let drawn = host.fittingSize.width
            #expect(abs(measured - drawn) <= 1, "\(text) at \(size): \(measured) vs \(drawn)")
            #expect(measured >= drawn - 0.01, "\(text) at \(size): \(measured) vs \(drawn)")
        }
        let count = widths.count
        _ = widths.width(of: "vela", size: 12, weight: .semibold)
        #expect(widths.count == count)
    }
}

/// A small deterministic generator, so a failure can be repeated.
private struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
