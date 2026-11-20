// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

// Fit first, then scroll: a row of tabs that's too long for its strip
// shrinks its unselected tabs, longest first, before it scrolls. Their
// titles fade out on the right where they're cut.
//
// It's all layout: `TabStripLayout` sizes the tabs in one pass from what
// each tab says its natural and narrowest widths are, `TabLabelLayout`
// gives a tab's width up from its title only, and `TabTitle` fades a title
// narrower than its text. Nothing is measured into state, so nothing lays
// out twice, and only what changes a tab's width (its name, its badge, the
// selection, the strip's width) lays the row out again.

// MARK: Planning

/// One item of a tab row, as `TabFit.plan` sees it.
nonisolated struct TabFitItem: Equatable {
    /// Its width with nothing trimmed.
    var natural: CGFloat
    /// The narrowest it gets when trimmed: the row's minimum tab width,
    /// or what its glyph slot, padding and badge take if that's more, but
    /// never more than `natural`.
    var floor: CGFloat
    /// Trimmed with the others: an unselected tab. The selected tab and
    /// the row's buttons always get their natural width.
    var isTrimmable: Bool

    init(natural: CGFloat, floor: CGFloat? = nil, isTrimmable: Bool = true) {
        self.natural = natural
        self.floor = min(natural, floor ?? natural)
        self.isTrimmable = isTrimmable
    }
}

/// The widths `TabFit.plan` gives a row's items.
nonisolated struct TabFitPlan: Equatable {
    /// Too many tabs to fit even at their narrowest: every item has its
    /// natural width and the row scrolls.
    var isScrolling: Bool
    /// The common cap on unselected tabs, when some are trimmed.
    var cap: CGFloat?
    var widths: [CGFloat]
    var naturals: [CGFloat]
    /// The items' widths and the gaps between them.
    var totalWidth: CGFloat
    /// The narrowest the row gets without scrolling: unselected tabs at
    /// their floors, everything else natural, and the gaps.
    var required: CGFloat

    /// Whether item `index` is narrower than its natural width.
    func isTrimmed(_ index: Int) -> Bool {
        widths[index] < naturals[index] - 0.5
    }
}

nonisolated enum TabFit {
    /// How much room a row that scrolls needs beyond its tabs' narrowest
    /// widths before it fits them again, so a window resized across the
    /// boundary, or a name a point longer, doesn't flip it back and forth.
    /// The » menu a scrolling row shows takes more on top of this.
    static let hysteresis: CGFloat = 12

    /// Widths for `items`, `spacing` apart, in `available` points (nil:
    /// not known yet, so everything is natural).
    ///
    /// When the natural widths don't fit, unselected tabs share the room
    /// that's left, longest first: each is `min(natural, W)` for the
    /// largest common `W` that fits, so short names stay whole and long
    /// ones are cut to the same width. No tab goes below its floor; when
    /// even the floors don't fit, the row scrolls at natural widths.
    /// `wasScrolling`: the row scrolled last time, so it needs
    /// `hysteresis` more room to fit again.
    static func plan(
        _ items: [TabFitItem],
        spacing: CGFloat,
        available: CGFloat?,
        wasScrolling: Bool = false,
        hysteresis: CGFloat = TabFit.hysteresis
    ) -> TabFitPlan {
        let gaps = spacing * CGFloat(max(0, items.count - 1))
        let naturals = items.map(\.natural)
        let naturalTotal = naturals.reduce(gaps, +)
        let fixed = items.reduce(gaps) { $1.isTrimmable ? $0 : $0 + $1.natural }
        let trimmable = items.filter(\.isTrimmable)
        let required = trimmable.reduce(fixed) { $0 + $1.floor }
        var plan = TabFitPlan(
            isScrolling: false, cap: nil, widths: naturals, naturals: naturals, totalWidth: naturalTotal, required: required
        )
        guard let available, naturalTotal > available + tolerance else { return plan }

        let room = wasScrolling ? available - hysteresis : available
        guard !trimmable.isEmpty, required <= room + tolerance else {
            plan.isScrolling = true
            return plan
        }

        // Whole points, so trimmed tabs end on pixel boundaries and the
        // row never ends up a fraction wider than the strip.
        let cap = waterLevel(trimmable, budget: available - fixed).rounded(.down)
        plan.cap = cap
        plan.widths = items.map { $0.isTrimmable ? min($0.natural, max($0.floor, cap)) : $0.natural }
        plan.totalWidth = plan.widths.reduce(gaps, +)
        return plan
    }

    /// The largest `W` with `Σ min(natural, max(floor, W)) ≤ budget`. The
    /// sum only bends at the items' floors and naturals, so it's found
    /// between the two of those it falls between, by bisection.
    static func waterLevel(_ items: [TabFitItem], budget: CGFloat) -> CGFloat {
        func filled(_ level: CGFloat) -> CGFloat {
            items.reduce(0) { $0 + min($1.natural, max($1.floor, level)) }
        }
        let points = items.flatMap { [$0.floor, $0.natural] }.sorted()
        guard let first = points.first, let last = points.last else { return 0 }
        guard filled(first) <= budget + tolerance else { return first }
        if filled(last) <= budget + tolerance { return last }
        var low = 0
        var high = points.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if filled(points[middle]) <= budget + tolerance { low = middle } else { high = middle }
        }
        let a = points[low]
        let b = points[high]
        let filledA = filled(a)
        let filledB = filled(b)
        guard filledB > filledA else { return a }
        return a + (b - a) * (budget - filledA) / (filledB - filledA)
    }

    private static let tolerance: CGFloat = 0.01
}

// MARK: The row

/// What an item of a `TabStripLayout` is.
nonisolated enum TabStripRole: Equatable {
    /// A button or anything else that keeps its natural width.
    case fixed
    /// A tab; unselected tabs are trimmed when the row is short of room.
    case tab(id: AnyHashable, isSelected: Bool)
    /// `TabStripWidthProbe`: where the row learns how wide its strip is.
    case widthProbe
}

nonisolated private struct TabStripRoleKey: LayoutValueKey {
    static var defaultValue: TabStripRole { .fixed }
}

extension View {
    /// This view's part in the `TabStripLayout` around it.
    func tabStripRole(_ role: TabStripRole) -> some View {
        layoutValue(key: TabStripRoleKey.self, value: role)
    }
}

/// A row of tabs inside a `TabScroller`: like an `HStack`, except that when
/// its tabs are too wide for the strip, unselected tabs are trimmed to fit
/// (`TabFit.plan`), and only when they'd have to go below `minWidth` does
/// the row lay out at natural widths and scroll.
///
/// A scroll view offers its content unlimited width, so the row reads the
/// strip's width from a `TabStripWidthProbe` among its items, which takes
/// the scroll view's width at layout time. The mode is kept in the layout's
/// cache, for the hysteresis, and only changes when the row is placed, so
/// a parent asking what size it would be at other widths doesn't move it.
nonisolated struct TabStripLayout: Layout {
    var spacing: CGFloat
    /// The narrowest a trimmed tab gets (`TabMetrics.minWidth`).
    var minWidth: CGFloat
    /// Space around this layout inside the scroll view (insets, padding),
    /// which the probe's width includes.
    var outsideWidth: CGFloat = 0
    /// False lays out every item at its natural width, like an `HStack`.
    var fitsFirst = true
    var hysteresis: CGFloat = TabFit.hysteresis
    /// Names the row for `probe`.
    var name = "tabs"
    var probe: TabStripProbe?

    struct Cache {
        var isScrolling = false
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    /// Keeps the mode as tabs come and go, for the hysteresis.
    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let row = arrange(proposal, subviews, wasScrolling: cache.isScrolling)
        return CGSize(width: row.plan.totalWidth, height: row.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let row = arrange(proposal, subviews, wasScrolling: cache.isScrolling)
        // The same plan as `sizeThatFits` worked out from the same mode:
        // `TabFit.plan` agrees with itself once it has switched.
        if row.usesProbe { cache.isScrolling = row.plan.isScrolling }
        var x = bounds.minX
        var frames: [AnyHashable: CGRect] = [:]
        for (position, index) in row.indices.enumerated() {
            let width = row.plan.widths[position]
            let height = row.heights[position]
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: height)
            )
            if probe != nil, let id = row.ids[position] {
                frames[id] = CGRect(x: x, y: bounds.midY - height / 2, width: width, height: height)
            }
            x += width + spacing
        }
        for index in subviews.indices where subviews[index][TabStripRoleKey.self] == .widthProbe {
            subviews[index].place(at: bounds.origin, proposal: ProposedViewSize(width: 0, height: 0))
        }
        if let probe {
            // Layout runs on the main thread; the probe is only there in tests.
            let name = name
            let plan = row.plan
            let available = row.available
            nonisolated(unsafe) let frames = frames
            MainActor.assumeIsolated {
                probe.record(name, plan: plan, available: available, frames: frames)
            }
        }
    }

    private struct Row {
        var plan: TabFitPlan
        var available: CGFloat?
        /// Per item: its subview, its height and its tab id.
        var indices: [Int] = []
        var heights: [CGFloat] = []
        var ids: [AnyHashable?] = []
        var height: CGFloat = 0
        /// Fitted to the strip's width (not an offered one).
        var usesProbe = false
    }

    private func arrange(_ proposal: ProposedViewSize, _ subviews: Subviews, wasScrolling: Bool) -> Row {
        var items: [TabFitItem] = []
        var row = Row(plan: TabFit.plan([], spacing: 0, available: nil))
        var probed: CGFloat?
        for index in subviews.indices {
            let subview = subviews[index]
            let role = subview[TabStripRoleKey.self]
            if role == .widthProbe {
                if fitsFirst {
                    let width = subview.sizeThatFits(.unspecified).width
                    if width.isFinite, width > 0 { probed = max(0, width - outsideWidth) }
                }
                continue
            }
            let size = subview.sizeThatFits(.unspecified)
            switch role {
            case .tab(let id, let isSelected) where fitsFirst && !isSelected:
                // Offered nothing, a tab answers with its narrowest.
                let narrowest = subview.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
                items.append(TabFitItem(natural: size.width, floor: max(narrowest, minWidth)))
                row.ids.append(id)
            case .tab(let id, _):
                items.append(TabFitItem(natural: size.width, isTrimmable: false))
                row.ids.append(id)
            default:
                items.append(TabFitItem(natural: size.width, isTrimmable: false))
                row.ids.append(nil)
            }
            row.indices.append(index)
            row.heights.append(size.height)
            row.height = max(row.height, size.height)
        }
        // Without a probe (outside a scroll view), the offered width; the
        // hysteresis only applies to the strip's own width, since a parent
        // probing a few widths in one pass would otherwise leave it stuck.
        if fitsFirst, probed == nil, let width = proposal.width, width.isFinite {
            row.available = width
            row.plan = TabFit.plan(items, spacing: spacing, available: width, hysteresis: hysteresis)
            return row
        }
        row.available = probed
        row.usesProbe = probed != nil
        row.plan = TabFit.plan(items, spacing: spacing, available: probed, wasScrolling: wasScrolling, hysteresis: hysteresis)
        return row
    }
}

/// Put among a `TabStripLayout`'s items inside a `TabScroller`: its width
/// is the scroll view's, at layout time (`containerRelativeFrame`), so the
/// row knows how much it can show without measuring itself into state.
/// Draws nothing and takes no clicks.
struct TabStripWidthProbe: View {
    var body: some View {
        Color.clear
            .containerRelativeFrame(.horizontal)
            .frame(height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .tabStripRole(.widthProbe)
    }
}

// MARK: A tab's label

nonisolated private struct TabLabelTitleKey: LayoutValueKey {
    static var defaultValue: Bool { false }
}

extension View {
    /// Marks the title of a `TabLabelLayout`: the part that gives up width.
    func tabLabelTitle() -> some View {
        layoutValue(key: TabLabelTitleKey.self, value: true)
    }
}

/// A tab's label: its parts (an icon, the title, a muted bell, a badge)
/// side by side, `spacing` apart, inside `leading` and `trailing` padding,
/// at least `minWidth` wide. A channel tab's glyph slot is in its leading
/// padding (the slot is drawn over the label).
///
/// Offered less than its natural width, only the title (marked with
/// `tabLabelTitle()`) gives width up, down to nothing: the slot, icons and
/// badge stay whole, so a tab is never narrower than those. Offered more,
/// it stays at its natural width.
nonisolated struct TabLabelLayout: Layout {
    var leading: CGFloat
    var trailing: CGFloat
    var spacing: CGFloat
    var minWidth: CGFloat = 0
    /// Centers the parts in a label `minWidth` makes wider than they are
    /// (an icon-only tab). Otherwise they start at the leading edge, and a
    /// short name leaves the extra width after the title.
    var centers = false

    /// A label's widths, from its parts' (`span(parts:title:)`).
    struct Span: Equatable {
        /// Everything but the title: padding, slot, icons, badge, spacing.
        var fixed: CGFloat
        var title: CGFloat
        var minWidth: CGFloat

        var natural: CGFloat { max(minWidth, fixed + title) }
        var narrowest: CGFloat { max(minWidth, fixed) }

        /// What the title gets in a label `width` wide.
        func titleWidth(in width: CGFloat) -> CGFloat {
            max(0, min(title, width - fixed))
        }
    }

    /// The widths of a label whose parts other than the title are `parts`
    /// wide, and whose title (if it has one) is `title` wide.
    func span(parts: [CGFloat], title: CGFloat?) -> Span {
        let count = parts.count + (title == nil ? 0 : 1)
        let fixed = leading + trailing + parts.reduce(0, +) + spacing * CGFloat(max(0, count - 1))
        return Span(fixed: fixed, title: title ?? 0, minWidth: minWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measured = measure(subviews)
        let span = measured.span
        let width = proposal.width.map { min(max($0, span.narrowest), span.natural) } ?? span.natural
        return CGSize(width: width, height: measured.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measured = measure(subviews)
        let span = measured.span
        let titleWidth = span.titleWidth(in: bounds.width)
        var x = bounds.minX + leading
        if centers {
            x += max(0, (bounds.width - span.fixed - titleWidth) / 2)
        }
        for (index, subview) in subviews.enumerated() {
            let width = subview[TabLabelTitleKey.self] ? titleWidth : measured.widths[index]
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }

    private func measure(_ subviews: Subviews) -> (span: Span, widths: [CGFloat], height: CGFloat) {
        var parts: [CGFloat] = []
        var widths: [CGFloat] = []
        var title: CGFloat?
        var height: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            height = max(height, size.height)
            widths.append(size.width)
            if subview[TabLabelTitleKey.self] {
                title = size.width
            } else {
                parts.append(size.width)
            }
        }
        return (span(parts: parts, title: title), widths, height)
    }
}

// MARK: Titles

/// A tab's title. It reserves the width of its text in `reservedWeight`,
/// so a tab doesn't change width when its title's weight changes (unread,
/// selected), up to `maxWidth`. Given less, it's cut on the right with a
/// `fadeLength` fade, never an ellipsis; the tab's tooltip and VoiceOver
/// label carry the full name.
///
/// The fade is an alpha mask, so it works on any tab background (selected,
/// hovered, translucent). It's decided in layout (`TabTitleFadeLayout`),
/// so it costs no extra pass, and a title that isn't cut has none.
struct TabTitle: View {
    @Environment(\.tabStripProbe) private var probe
    let text: String
    let fontSize: CGFloat
    let weight: Font.Weight
    var reservedWeight: Font.Weight = .semibold
    let color: Color
    let maxWidth: CGFloat
    let fadeLength: CGFloat

    var body: some View {
        let widths = TabTextWidths.shared
        let reserved = widths.width(of: text, size: fontSize, weight: reservedWeight)
        let shown = weight == reservedWeight ? reserved : widths.width(of: text, size: fontSize, weight: weight)
        let natural = min(max(reserved, shown), maxWidth)
        Text(text)
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
            // Drawn whole, from the leading edge; the mask cuts it.
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 0, idealWidth: natural, maxWidth: natural, alignment: .leading)
            .mask(alignment: .leading) {
                TabTitleFadeLayout(textWidth: shown, fadeLength: fadeLength, probe: probe, key: text) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                }
            }
    }
}

/// The alpha mask over a `TabTitle`: opaque, with a fade at the trailing
/// edge only when the title is narrower than its text. The fade is never
/// more than half the title.
nonisolated struct TabTitleFadeLayout: Layout {
    var textWidth: CGFloat
    var fadeLength: CGFloat
    var probe: TabStripProbe?
    var key = ""

    static func isCut(width: CGFloat, textWidth: CGFloat) -> Bool {
        width < textWidth - 0.5
    }

    static func fade(width: CGFloat, textWidth: CGFloat, fadeLength: CGFloat) -> CGFloat {
        isCut(width: width, textWidth: textWidth) ? max(0, min(fadeLength, width / 2)) : 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fade = Self.fade(width: bounds.width, textWidth: textWidth, fadeLength: fadeLength)
        if subviews.indices.contains(0) {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width - fade, height: bounds.height))
        }
        if subviews.indices.contains(1) {
            subviews[1].place(at: CGPoint(x: bounds.maxX - fade, y: bounds.minY), proposal: ProposedViewSize(width: fade, height: bounds.height))
        }
        if let probe {
            let key = key
            MainActor.assumeIsolated { probe.fadedTitles[key] = fade > 0 }
        }
    }
}

/// Widths of tab titles, measured once per text, size and weight: tabs
/// draw again on hover, selection and unread counts, but their names
/// rarely change. Rounded up to whole points, as text is laid out.
final class TabTextWidths {
    static let shared = TabTextWidths()

    private struct Key: Hashable {
        var text: String
        var size: CGFloat
        var weight: CGFloat
    }

    private var widths: [Key: CGFloat] = [:]
    /// Names come and go (nick changes, channels joined over months); past
    /// this many, start over rather than keep every one.
    private let limit = 2_000

    func width(of text: String, size: CGFloat, weight: Font.Weight) -> CGFloat {
        let fontWeight = Self.fontWeight(weight)
        let key = Key(text: text, size: size, weight: fontWeight.rawValue)
        if let width = widths[key] { return width }
        let font = NSFont.systemFont(ofSize: size, weight: fontWeight)
        let width = (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        if widths.count >= limit { widths.removeAll(keepingCapacity: true) }
        widths[key] = width
        return width
    }

    var count: Int { widths.count }

    private static func fontWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

// MARK: Testing

/// What tab rows last laid out, for tests. Rows record into the one in
/// their environment (`tabStripProbe`); without one, nothing is recorded.
final class TabStripProbe {
    struct Row {
        var plan: TabFitPlan
        /// The strip's width, less the row's insets.
        var available: CGFloat?
        /// Each tab's frame, by id, in the row.
        var frames: [AnyHashable: CGRect]
    }

    /// By row: "channels" or "networks".
    var rows: [String: Row] = [:]
    /// How many times each row has been laid out.
    var passes: [String: Int] = [:]
    /// Whether each title, by its text, was last drawn faded.
    var fadedTitles: [String: Bool] = [:]

    func record(_ name: String, plan: TabFitPlan, available: CGFloat?, frames: [AnyHashable: CGRect]) {
        rows[name] = Row(plan: plan, available: available, frames: frames)
        passes[name, default: 0] += 1
    }
}

extension EnvironmentValues {
    @Entry var tabStripProbe: TabStripProbe?
}
