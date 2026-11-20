// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaTheme

// Geometry, colors and shapes shared by both rows of the tab stack.

/// How a row draws its selected tab.
enum TabAppearance: Equatable {
    /// Free-standing chips; the selected one is filled. Used in the title bar,
    /// for the server row, and for pill-shaped tabs.
    case floating
    /// Browser-style tabs: the selected tab is drawn in the conversation's
    /// color and merges into the conversation on `edge`.
    case attached(VerticalEdge)

    var attachedEdge: VerticalEdge? {
        if case .attached(let edge) = self { edge } else { nil }
    }
}

/// The surface a row sits on, which picks its tokens.
enum TabSurface {
    /// Inside the title strip (`tabs.placement = titleBar`).
    case titleBar
    /// The tab strip above or below the conversation.
    case strip
}

/// Every size of a tab row, derived from `tabs.height` and `tabs.roundness`
/// so padding, type and corner shapes scale together.
struct TabMetrics: Equatable {
    var height: CGFloat
    var radius: CGFloat
    var fontSize: CGFloat
    var badgeFontSize: CGFloat
    var iconSize: CGFloat
    var horizontalPadding: CGFloat
    /// Space between the icon, title and badge inside a tab.
    var spacing: CGFloat
    /// Space between neighboring tabs.
    var gap: CGFloat
    /// Inverse corners where an attached tab meets the conversation.
    var flare: CGFloat
    /// Side of the square slot at the start of a channel or query tab. It
    /// holds the tab's `#`, `##` or avatar, and is the tab's close button:
    /// the × replaces the glyph in it, so nothing moves.
    var closeSlot: CGFloat
    /// Narrowest a tab gets, whether its name is short (`#dn`) or trimmed
    /// to fit the strip (`TabStripLayout`): still plenty of tab to click
    /// that isn't the close slot.
    var minWidth: CGFloat
    var maxLabelWidth: CGFloat
    /// The fade at the end of a title that's cut (`TabTitle`).
    var titleFade: CGFloat

    init(style: ChatStyle, height: CGFloat, appearance: TabAppearance) {
        self.height = height
        radius = style.tabCornerRadius(forHeight: height)
        fontSize = (min(15, max(10.5, height * 0.43)) * 2).rounded() / 2
        badgeFontSize = max(9, fontSize - 2.5)
        iconSize = (fontSize * 1.2).rounded()
        horizontalPadding = max(height * 0.34, radius * 0.72 + 3).rounded()
        spacing = max(4, (height * 0.18).rounded())
        if appearance == .floating {
            flare = 0
            gap = max(2, (height * 0.1).rounded())
        } else {
            flare = min(radius, (height * 0.3).rounded())
            gap = 0
        }
        // Fits `##` at the tab's type and is an easy target, but no bigger:
        // 16 pt at the smallest tabs, 18 from about 30 pt tall.
        closeSlot = min(18, max(16, (fontSize * 1.4).rounded()))
        // The tab's padding on both sides, its slot, and about a slot more
        // of title: 58 pt at the default size, so more than half of even
        // the narrowest tab is past the slot, and selects. The padding
        // grows with the corner radius, so rounder tabs (and pills) keep
        // the same clear area inside their curves.
        minWidth = (horizontalPadding * 2 + closeSlot * 2.25).rounded()
        maxLabelWidth = max(120, height * 6)
        titleFade = min(16, max(12, (fontSize * 1.2).rounded()))
    }

    /// Padding before the close slot and the space after it, for a glyph
    /// `glyphWidth` wide. The slot is wider than most glyphs (a `#` is about
    /// half of it), so the slack around the glyph comes out of the tab's
    /// padding and spacing, and the glyph sits where it would without a slot.
    func closeSlotInsets(glyphWidth: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let slack = max(0, (closeSlot - glyphWidth) / 2)
        return (max(3, (horizontalPadding - slack).rounded()), max(2, (spacing - slack).rounded()))
    }

    /// About how wide a channel's `#` or `##` is at the tab's type, capped
    /// at the slot (`##` at the largest sizes is drawn a little smaller).
    func channelGlyphWidth(_ prefix: String) -> CGFloat {
        min(closeSlot, CGFloat(max(1, prefix.count)) * fontSize * 0.64)
    }

    /// Tab height for channel tabs, from `tabs.height`.
    static func channelHeight(_ style: ChatStyle) -> CGFloat {
        min(48, max(18, style.tabHeight))
    }

    /// The server row is a little smaller than the channel row.
    static func serverHeight(_ style: ChatStyle) -> CGFloat {
        max(16, channelHeight(style) - 6)
    }

    /// Corner radius for any other control in the row (the + and » buttons),
    /// so it follows the tab roundness.
    static func radius(_ style: ChatStyle, forHeight height: CGFloat) -> CGFloat {
        style.tabCornerRadius(forHeight: height)
    }

    /// Leading space of strip rows. Leaves room for an attached tab's flare,
    /// and is shared so the server and channel rows line up.
    static let stripInset: CGFloat = 10
}

/// Theme tokens for one row: the `tab.*` tokens, with the title bar's
/// background, text and border in the title-bar placement.
struct TabPalette {
    var background: String
    var border: String
    var text: String
    var unreadText: String
    var highlightText: String
    var dimText: String
    var hoverFill: String
    var selectedFill: String
    var selectedText: String
    var selectedBorder: String
    var indicator: String
    var separator: String
    /// Fill behind the segmented server group in the title bar.
    var groupFill: String
    /// What the row's tabs sit on, bottom layer first. A dragged tab is
    /// backed with it, so the tabs it passes over don't show through.
    var liftBacking: [String]

    static func channels(on surface: TabSurface, appearance: TabAppearance) -> TabPalette {
        switch surface {
        case .titleBar:
            TabPalette(
                background: ThemeKey.titleBarBackground,
                border: ThemeKey.titleBarBorder,
                text: ThemeKey.titleBarSecondaryForeground,
                unreadText: ThemeKey.titleBarForeground,
                highlightText: ThemeKey.tabHighlightForeground,
                dimText: ThemeKey.tabInactiveForeground,
                hoverFill: ThemeKey.tabHoverBackground,
                selectedFill: ThemeKey.tabPillBackground,
                selectedText: ThemeKey.tabPillForeground,
                selectedBorder: ThemeKey.titleBarBorder,
                indicator: ThemeKey.tabActiveIndicator,
                separator: ThemeKey.tabSeparator,
                groupFill: ThemeKey.tabGroupBackground,
                liftBacking: [ThemeKey.titleBarBackground]
            )
        case .strip:
            TabPalette(
                background: ThemeKey.tabBarBackground,
                border: ThemeKey.tabBorder,
                text: ThemeKey.tabForeground,
                unreadText: ThemeKey.tabUnreadForeground,
                highlightText: ThemeKey.tabHighlightForeground,
                dimText: ThemeKey.tabInactiveForeground,
                hoverFill: ThemeKey.tabHoverBackground,
                selectedFill: appearance == .floating ? ThemeKey.tabPillBackground : ThemeKey.tabActiveBackground,
                selectedText: appearance == .floating ? ThemeKey.tabPillForeground : ThemeKey.tabActiveForeground,
                selectedBorder: ThemeKey.tabBorder,
                indicator: ThemeKey.tabActiveIndicator,
                separator: ThemeKey.tabSeparator,
                groupFill: ThemeKey.tabGroupBackground,
                liftBacking: [ThemeKey.tabBarBackground]
            )
        }
    }

    static func servers(on surface: TabSurface) -> TabPalette {
        var palette = channels(on: surface, appearance: .floating)
        palette.selectedFill = ThemeKey.tabServerActiveBackground
        switch surface {
        case .strip:
            palette.background = ThemeKey.tabServerBackground
            palette.liftBacking = [ThemeKey.tabServerBackground]
        case .titleBar:
            // Title-bar networks sit in the segmented group.
            palette.liftBacking.append(palette.groupFill)
        }
        return palette
    }
}

// MARK: Shapes

/// A browser-style tab: rounded on the far side, square where it meets the
/// conversation on `edge`, with inverse "flare" corners joining the strip's
/// border. `isOutline` leaves the attached side open for stroking.
nonisolated struct AttachedTabShape: Shape {
    var edge: VerticalEdge
    var radius: CGFloat
    var flare: CGFloat
    var isOutline = false

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let r = max(0, min(radius, width / 2, height - flare))
        let f = max(0, min(flare, height - r))
        // Outlines end on the center of the strip's 1-pt border.
        let base = isOutline ? height - 0.5 : height

        var path = Path()
        path.move(to: CGPoint(x: -f, y: base))
        if f > 0 { path.addTabCorner(to: CGPoint(x: 0, y: base - f), via: CGPoint(x: 0, y: base)) }
        path.addLine(to: CGPoint(x: 0, y: r))
        if r > 0 { path.addTabCorner(to: CGPoint(x: r, y: 0), via: .zero) }
        path.addLine(to: CGPoint(x: width - r, y: 0))
        if r > 0 { path.addTabCorner(to: CGPoint(x: width, y: r), via: CGPoint(x: width, y: 0)) }
        path.addLine(to: CGPoint(x: width, y: base - f))
        if f > 0 { path.addTabCorner(to: CGPoint(x: width + f, y: base), via: CGPoint(x: width, y: base)) }
        if !isOutline { path.closeSubpath() }

        // Drawn attached to the bottom; flip for tabs that hang from the top.
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        if edge == .top {
            transform = transform.translatedBy(x: 0, y: height).scaledBy(x: 1, y: -1)
        }
        return path.applying(transform)
    }
}

nonisolated extension Path {
    /// A circular quarter corner from the current point to `end`, bending
    /// around the square corner `via`.
    fileprivate mutating func addTabCorner(to end: CGPoint, via corner: CGPoint) {
        guard let start = currentPoint else {
            move(to: end)
            return
        }
        let k: CGFloat = 0.552_284_75
        addCurve(
            to: end,
            control1: CGPoint(x: start.x + (corner.x - start.x) * k, y: start.y + (corner.y - start.y) * k),
            control2: CGPoint(x: end.x + (corner.x - end.x) * k, y: end.y + (corner.y - end.y) * k)
        )
    }
}

/// The selected tab of an attached row: conversation-colored fill, a hairline
/// outline that continues the strip border, and an accent indicator on the
/// far edge.
struct AttachedSelectionChrome: View {
    @Environment(\.theme) private var theme
    @Environment(\.effectiveVibrancy) private var vibrancy
    let edge: VerticalEdge
    let metrics: TabMetrics
    let palette: TabPalette

    var body: some View {
        ZStack(alignment: edge == .bottom ? .top : .bottom) {
            // Drawn like the conversation it opens into, translucent too
            // when the conversation is on a material.
            AttachedTabShape(edge: edge, radius: metrics.radius, flare: metrics.flare)
                .fill(theme.surfaceColor(palette.selectedFill, on: .content, vibrancy: vibrancy).color)
            AttachedTabShape(edge: edge, radius: metrics.radius, flare: metrics.flare, isOutline: true)
                .stroke(theme[palette.selectedBorder], lineWidth: 1)
            Capsule()
                .fill(theme[palette.indicator])
                .frame(height: 2)
                .padding(.horizontal, max(metrics.radius, 4) + 2)
                .padding(edge == .bottom ? .top : .bottom, 1)
        }
    }
}

/// Fill of a floating tab (selected, hovered or dragged).
struct FloatingTabFill: View {
    @Environment(\.theme) private var theme
    let key: String
    let radius: CGFloat
    /// While the tab is dragged: the row's surface to back the fill with
    /// (`TabPalette.liftBacking`), under a soft shadow.
    var liftBacking: [String]? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(theme[key])
            .background {
                if let liftBacking {
                    ZStack {
                        ForEach(liftBacking, id: \.self) { key in
                            shape.fill(theme[key])
                        }
                    }
                    .compositingGroup()
                    .shadow(color: liftShadow, radius: 3, y: 1)
                    .transition(.opacity)
                }
            }
    }

    private var liftShadow: Color {
        theme.kind == .dark
            ? theme[ThemeKey.windowBackground].opacity(0.6)
            : theme[ThemeKey.popoverForeground].opacity(0.2)
    }
}

/// A short vertical rule between unselected tabs.
struct TabSeparator: View {
    @Environment(\.theme) private var theme
    let key: String
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(theme[key])
            .frame(width: 1, height: height)
            .accessibilityHidden(true)
    }
}

/// Dims the label while pressed; tabs draw their own chrome.
struct TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

/// Square-ish icon control used at the end of a row (+, »).
struct TabToolLabel: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let systemImage: String
    let size: CGFloat
    let foreground: String
    let hoverFill: String
    var isHovering = false
    var weight: Font.Weight = .semibold

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: (size * 0.46).rounded(), weight: weight))
            .foregroundStyle(theme[foreground])
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: max(3, TabMetrics.radius(style, forHeight: size)), style: .continuous)
                    .fill(isHovering ? theme[hoverFill] : .clear)
            )
            .contentShape(Rectangle())
    }
}
