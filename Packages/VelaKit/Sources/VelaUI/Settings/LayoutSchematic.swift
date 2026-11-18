// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaFoundation
import VelaStore
import VelaTheme

/// The layout choices a schematic illustration reflects.
struct LayoutSchematicConfig: Equatable {
    var navigation: NavigationStyle = .sidebar
    /// The sidebar is collapsed to the rail (`sidebar.collapsed`).
    var sidebarCollapsed = false
    var tabPlacement: TabStackPlacement = .top
    var tabRoundness: Double = 0.35
    var chatLayout: ChatLayout = .grouped
    var showAvatars = false
    var showTimestamps = true
    var colorNicks = true
    var memberList = true
    var monospace = false
    var linkPreviewSize: LinkPreviewSize = .standard
    var videoStyle: VideoEmbedStyle = .player
    var imageSize: InlineImageSize = .full
    /// Off: page links get no preview. Videos and images still show.
    var showLinkCards = true
    /// Off: no media at all, for illustrations about something else.
    var showMedia = true
    var messageBoxBorder: MessageBoxBorder = .subtle

    init() {}

    /// The current settings, with `overrides` (raw settings.json values,
    /// e.g. a preset's) layered on top.
    init(settings: SettingsStore, overrides: [String: JSONValue] = [:]) {
        func read<Value>(_ key: SettingKey<Value>) -> Value {
            key.value(from: overrides[key.key] ?? settings.value(forKey: key.key))
        }
        navigation = read(.navigationStyle)
        sidebarCollapsed = read(.sidebarCollapsed)
        tabPlacement = read(.tabsPlacement)
        tabRoundness = read(.tabsRoundness)
        chatLayout = read(.chatLayout)
        showAvatars = read(.chatShowAvatars)
        showTimestamps = read(.chatShowTimestamps)
        colorNicks = read(.chatColorNicks)
        memberList = read(.memberListVisible)
        monospace = read(.chatMonospace)
        linkPreviewSize = read(.mediaLinkPreviewSize)
        videoStyle = read(.mediaVideos)
        imageSize = read(.mediaImageSize)
        showLinkCards = read(.mediaShowLinkCards)
        messageBoxBorder = read(.appearanceMessageBoxBorder)
    }

    init(preset: SettingsPreset, settings: SettingsStore) {
        self.init(settings: settings, overrides: preset.values)
    }
}

/// A miniature, schematic drawing of Vela's window (or part of it) in a
/// given theme. Text is drawn as bars so it reads at any size.
///
/// The window drawing shows what sets a theme apart: the sidebar's
/// selected row and unread and mention badges (or the rail), tabs in the
/// `tab.*` colors, nick colors, a link, a message that mentions you, the
/// New line, and with `vibrancy`, translucent surfaces over a stand-in
/// desktop. One `Canvas`, cheap enough for a gallery of cards.
struct LayoutSchematic: View {
    enum Scope {
        /// The whole window: navigation, title strip, chat, input, members.
        case window
        /// Only the message area, zoomed in.
        case messages
        /// One message with a link preview, zoomed in further.
        case media
        /// One message with a video link, zoomed in further.
        case video
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let config: LayoutSchematicConfig
    let theme: ResolvedTheme
    var scope: Scope = .window

    var body: some View {
        let design = SchematicPainter.designSize(for: scope)
        let painter = SchematicPainter(
            config: config,
            theme: theme,
            vibrancy: theme.vibrancy.effective(reduceTransparency: reduceTransparency)
        )
        Canvas { context, size in
            let scale = min(size.width / design.width, size.height / design.height)
            context.translateBy(
                x: (size.width - design.width * scale) / 2,
                y: (size.height - design.height * scale) / 2
            )
            context.scaleBy(x: scale, y: scale)
            painter.draw(scope, in: &context)
        }
        .aspectRatio(design.width / design.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Draws the schematic in a fixed design space; `LayoutSchematic` scales it.
struct SchematicPainter {
    let config: LayoutSchematicConfig
    let theme: ResolvedTheme
    /// The vibrancy drawn (`none` with Reduce Transparency on).
    var vibrancy: ThemeVibrancy = .none

    static func designSize(for scope: LayoutSchematic.Scope) -> CGSize {
        switch scope {
        case .window: CGSize(width: 320, height: 200)
        case .messages: CGSize(width: 220, height: 110)
        case .media, .video: CGSize(width: 190, height: 100)
        }
    }

    private static let widths: [Double] = [0.84, 0.56, 0.72, 0.4, 0.92, 0.63, 0.48, 0.77, 0.59, 0.69]

    func draw(_ scope: LayoutSchematic.Scope, in context: inout GraphicsContext) {
        let size = Self.designSize(for: scope)
        let bounds = CGRect(origin: .zero, size: size)
        switch scope {
        case .window:
            context.clip(to: Path(roundedRect: bounds, cornerRadius: 10, style: .continuous))
            drawWindow(in: &context, bounds: bounds)
        case .messages:
            context.clip(to: Path(roundedRect: bounds, cornerRadius: 8, style: .continuous))
            surface(&context, bounds, ThemeKey.chatBackground, on: .content, desktop: bounds)
            drawMessages(in: &context, rect: bounds.insetBy(dx: 10, dy: 9), bleed: 10)
        case .media, .video:
            context.clip(to: Path(roundedRect: bounds, cornerRadius: 8, style: .continuous))
            surface(&context, bounds, ThemeKey.chatBackground, on: .content, desktop: bounds)
            drawMediaMessage(in: &context, rect: bounds.insetBy(dx: 10, dy: 10), video: scope == .video)
        }
    }

    // MARK: Primitives

    private func color(_ key: String) -> Color { theme[key] }

    private func fill(_ context: inout GraphicsContext, _ rect: CGRect, _ key: String, radius: Double = 0, opacity: Double = 1) {
        fill(&context, rect, color(key).opacity(opacity), radius: radius)
    }

    private func fill(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color, radius: Double = 0) {
        let path = radius > 0
            ? Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            : Path(rect)
        context.fill(path, with: .color(color))
    }

    private func stroke(_ context: inout GraphicsContext, _ rect: CGRect, _ key: String, radius: Double = 0, width: Double = 0.75) {
        let inset = rect.insetBy(dx: width / 2, dy: width / 2)
        context.stroke(Path(roundedRect: inset, cornerRadius: radius, style: .continuous), with: .color(color(key)), lineWidth: width)
    }

    private func bar(_ context: inout GraphicsContext, _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: Color) {
        guard width > 0.5 else { return }
        fill(&context, CGRect(x: x, y: y, width: width, height: height), color, radius: height / 2)
    }

    private func dot(_ context: inout GraphicsContext, center: CGPoint, diameter: Double, _ color: Color) {
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)),
            with: .color(color)
        )
    }

    /// A line of "words"; monospace text gets square character cells.
    private func text(_ context: inout GraphicsContext, x: Double, y: Double, width: Double, height: Double, color: Color, seed: Int) {
        let words: [Double] = config.monospace ? [3, 5, 4, 2, 6, 3, 4] : [9, 14, 6, 17, 11, 7, 15]
        let unit = config.monospace ? 2.5 : 0.9
        let gap = config.monospace ? 2.5 : 2.4
        var cursor = x
        var index = seed
        while cursor < x + width - 2 {
            let wordWidth = min(words[index % words.count] * unit, x + width - cursor)
            let rect = CGRect(x: cursor, y: y, width: wordWidth, height: height)
            fill(&context, rect, color, radius: config.monospace ? 0.6 : height / 2)
            cursor += wordWidth + gap
            index += 1
        }
    }

    private func nickColor(_ index: Int) -> Color {
        guard config.colorNicks else { return color(ThemeKey.chatForeground) }
        let palette = theme.nickPalette
        return palette[(index * 5 + 2) % palette.count].color
    }

    private var bodyText: Color { color(ThemeKey.chatForeground).opacity(0.62) }

    // MARK: Surfaces and vibrancy

    /// Paints a surface token, as `SurfaceFill` does in the app: on a
    /// material, a stand-in desktop under a material wash, then the token
    /// as a tint. `desktop` is the area the stand-in desktop spans, so it
    /// lines up across surfaces.
    private func surface(_ context: inout GraphicsContext, _ rect: CGRect, _ key: String, on surface: ThemeSurface, desktop: CGRect) {
        if let material = vibrancy.material(for: surface) {
            drawDesktop(&context, rect, desktop: desktop)
            fill(&context, rect, materialWash(material))
        }
        fill(&context, rect, theme.surfaceColor(key, on: surface, vibrancy: vibrancy).color)
    }

    /// A soft wallpaper standing in for whatever is behind the window: two
    /// of the theme's own hues, so the material visibly takes them on.
    private func drawDesktop(_ context: inout GraphicsContext, _ rect: CGRect, desktop: CGRect) {
        var layer = context
        layer.clip(to: Path(rect))
        let first = theme.color(ThemeKey.accent).color
        let second = theme.nickPalette[min(3, theme.nickPalette.count - 1)].color
        layer.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [first, second]),
            startPoint: CGPoint(x: desktop.minX, y: desktop.minY),
            endPoint: CGPoint(x: desktop.maxX, y: desktop.maxY)
        ))
        let glow = CGPoint(x: desktop.minX + desktop.width * 0.18, y: desktop.minY + desktop.height * 0.72)
        layer.fill(Path(rect), with: .radialGradient(
            Gradient(colors: [Color.white.opacity(theme.kind == .dark ? 0.35 : 0.6), .clear]),
            center: glow,
            startRadius: 0,
            endRadius: desktop.height * 0.55
        ))
    }

    /// The material itself, lighter than the contrast checks' worst case so
    /// the preview shows what translucency usually looks like.
    private func materialWash(_ material: ThemeMaterial) -> Color {
        let opacity = material == .sidebar ? 0.32 : 0.4
        return (theme.kind == .dark ? Color.black : Color.white).opacity(opacity)
    }

    // MARK: Window

    private func drawWindow(in context: inout GraphicsContext, bounds: CGRect) {
        let width = bounds.width, height = bounds.height
        if vibrancy.material(for: .content) == .window {
            // The window material behind everything; surfaces tint it.
            drawDesktop(&context, bounds, desktop: bounds)
            fill(&context, bounds, materialWash(.window))
        } else {
            fill(&context, bounds, ThemeKey.windowBackground)
        }

        let usesRail = config.navigation == .sidebar && config.sidebarCollapsed
        var left = 0.0
        var right = width
        if config.navigation == .sidebar {
            if usesRail {
                let railWidth = 22.0
                drawRail(in: &context, rect: CGRect(x: 0, y: 0, width: railWidth, height: height), desktop: bounds)
                fill(&context, CGRect(x: railWidth, y: 0, width: 1, height: height), ThemeKey.railBorder)
                left = railWidth + 1
            } else {
                let sidebarWidth = 78.0
                drawSidebar(in: &context, rect: CGRect(x: 0, y: 0, width: sidebarWidth, height: height), desktop: bounds)
                fill(&context, CGRect(x: sidebarWidth, y: 0, width: 1, height: height), ThemeKey.sidebarBorder)
                left = sidebarWidth + 1
            }
        }
        if config.memberList {
            let memberWidth = 60.0
            drawMembers(in: &context, rect: CGRect(x: width - memberWidth, y: 0, width: memberWidth, height: height), desktop: bounds)
            fill(&context, CGRect(x: width - memberWidth - 1, y: 0, width: 1, height: height), ThemeKey.memberListBorder)
            right = width - memberWidth - 1
        }

        let chat = CGRect(x: left, y: 0, width: right - left, height: height)
        let usesTabs = config.navigation == .tabs

        // Title strip (or title-bar tabs).
        let titleHeight = 26.0
        let titleRect = CGRect(x: chat.minX, y: 0, width: chat.width, height: titleHeight)
        let titleX = chat.minX + (usesTabs ? 40 : 10)
        if usesTabs && config.tabPlacement == .titleBar {
            surface(&context, titleRect, ThemeKey.titleBarBackground, on: .tabs, desktop: bounds)
            fill(&context, CGRect(x: chat.minX, y: titleHeight - 1, width: chat.width, height: 1), ThemeKey.titleBarBorder)
            drawTitleBarTabs(in: &context, x: titleX, y: 6.5, height: 13, maxX: chat.maxX - 24)
        } else {
            surface(&context, titleRect, ThemeKey.titleBarBackground, on: .content, desktop: bounds)
            fill(&context, CGRect(x: chat.minX, y: titleHeight - 1, width: chat.width, height: 1), ThemeKey.titleBarBorder)
            bar(&context, titleX, 7.5, 34, 4.5, color(ThemeKey.titleBarForeground))
            bar(&context, titleX, 15, 66, 3, color(ThemeKey.titleBarSecondaryForeground).opacity(0.8))
        }
        for index in 0..<2 {
            let x = chat.maxX - 12 - Double(index) * 9
            fill(&context, CGRect(x: x - 3, y: 10, width: 6, height: 6), ThemeKey.titleBarSecondaryForeground, radius: 1.5, opacity: 0.7)
        }

        let stripHeight = 25.0
        var top = titleHeight
        if usesTabs && config.tabPlacement == .top {
            drawStripTabs(in: &context, rect: CGRect(x: chat.minX, y: top, width: chat.width, height: stripHeight), conversationEdge: .bottom, desktop: bounds)
            top += stripHeight
        }

        // Input.
        let inputArea = 28.0
        var bottom = height - inputArea
        surface(&context, CGRect(x: chat.minX, y: bottom, width: chat.width, height: inputArea), ThemeKey.inputContainerBackground, on: .content, desktop: bounds)
        fill(&context, CGRect(x: chat.minX, y: bottom, width: chat.width, height: 0.75), ThemeKey.paneDivider)
        let field = CGRect(x: chat.minX + 8, y: bottom + 6, width: chat.width - 16, height: 16)
        fill(&context, field, ThemeKey.inputBackground, radius: 5)
        if config.messageBoxBorder != MessageBoxBorder.none {
            stroke(&context, field, ThemeKey.inputBorder, radius: 5)
        }
        bar(&context, field.minX + 7, field.midY - 1.5, min(70, field.width * 0.4), 3, color(ThemeKey.inputPlaceholder))

        if usesTabs && config.tabPlacement == .bottom {
            drawStripTabs(in: &context, rect: CGRect(x: chat.minX, y: bottom - stripHeight, width: chat.width, height: stripHeight), conversationEdge: .top, desktop: bounds)
            bottom -= stripHeight
        }

        // The conversation, under the strips' attached tabs.
        let conversation = CGRect(x: chat.minX, y: top, width: chat.width, height: bottom - top)
        surface(&context, conversation, ThemeKey.chatBackground, on: .content, desktop: bounds)
        if usesTabs && config.tabPlacement != .titleBar {
            let edge: VerticalEdge = config.tabPlacement == .top ? .bottom : .top
            let stripRect = config.tabPlacement == .top
                ? CGRect(x: chat.minX, y: titleHeight, width: chat.width, height: stripHeight)
                : CGRect(x: chat.minX, y: bottom, width: chat.width, height: stripHeight)
            drawSelectedAttachedTab(in: &context, rect: stripRect, conversationEdge: edge)
        }
        let messages = CGRect(x: chat.minX + 9, y: top + 7, width: chat.width - 18, height: bottom - top - 10)
        drawMessages(in: &context, rect: messages, bleed: 9)

        drawTrafficLights(in: &context, vertical: usesRail)
    }

    private func drawTrafficLights(in context: inout GraphicsContext, vertical: Bool) {
        for (index, key) in [ThemeKey.statusError, ThemeKey.statusWarning, ThemeKey.statusSuccess].enumerated() {
            let center = vertical
                ? CGPoint(x: 11, y: 9 + Double(index) * 8.5)
                : CGPoint(x: 10 + Double(index) * 9, y: 12)
            dot(&context, center: center, diameter: 6.4, color(key))
        }
    }

    private func drawSidebar(in context: inout GraphicsContext, rect: CGRect, desktop: CGRect) {
        surface(&context, rect, ThemeKey.sidebarBackground, on: .sidebar, desktop: desktop)
        enum Row { case read, selected, unread, mention }
        var y = 30.0
        let rows: [(width: Double, state: Row)] = [(26, .selected), (22, .unread), (30, .mention), (18, .read)]
        let more: [(width: Double, state: Row)] = [(24, .read), (28, .unread)]
        for (header, items) in [(36.0, rows), (28.0, more)] {
            bar(&context, rect.minX + 9, y, header, 3.5, color(ThemeKey.sidebarHeaderForeground))
            y += 10
            for item in items {
                let badge = CGRect(x: rect.maxX - 18, y: y - 1.5, width: 10, height: 7)
                switch item.state {
                case .selected:
                    fill(&context, CGRect(x: rect.minX + 5, y: y - 3.5, width: rect.width - 10, height: 11), ThemeKey.sidebarActiveBackground, radius: 3)
                    bar(&context, rect.minX + 12, y, item.width, 4, color(ThemeKey.sidebarActiveForeground))
                case .unread:
                    bar(&context, rect.minX + 12, y, item.width, 4, color(ThemeKey.sidebarUnreadForeground))
                    fill(&context, badge, ThemeKey.sidebarBadgeBackground, radius: 3.5)
                    bar(&context, badge.midX - 1.5, badge.midY - 1, 3, 2, color(ThemeKey.sidebarBadgeForeground))
                case .mention:
                    bar(&context, rect.minX + 12, y, item.width, 4, color(ThemeKey.sidebarHighlightForeground))
                    fill(&context, badge, ThemeKey.sidebarHighlightBadgeBackground, radius: 3.5)
                    bar(&context, badge.midX - 1.5, badge.midY - 1, 3, 2, color(ThemeKey.sidebarHighlightBadgeForeground))
                case .read:
                    bar(&context, rect.minX + 12, y, item.width, 4, color(ThemeKey.sidebarForeground).opacity(0.8))
                }
                y += 13
            }
            y += 5
        }
    }

    /// The collapsed sidebar: network glyphs and channel tiles, one
    /// selected with its indicator, one with a mention badge.
    private func drawRail(in context: inout GraphicsContext, rect: CGRect, desktop: CGRect) {
        surface(&context, rect, ThemeKey.railBackground, on: .sidebar, desktop: desktop)
        let centerX = rect.midX
        let wash = color(ThemeKey.railForeground).opacity(0.07)
        var y = 36.0
        // (isNetwork, state): 0 rest, 1 selected, 2 mention badge.
        let items: [[(isNetwork: Bool, state: Int)]] = [
            [(true, 0), (false, 1), (false, 2), (false, 0)],
            [(true, 0), (false, 0), (false, 0)],
        ]
        for (groupIndex, group) in items.enumerated() {
            if groupIndex > 0 {
                fill(&context, CGRect(x: centerX - 5, y: y - 3.5, width: 10, height: 0.75), color(ThemeKey.railForeground).opacity(0.2))
                y += 1
            }
            for item in group {
                let side = 12.0
                let tile = CGRect(x: centerX - side / 2, y: y, width: side, height: side)
                guard tile.maxY < rect.maxY - 6 else { break }
                if item.isNetwork {
                    context.fill(Path(ellipseIn: tile), with: .color(wash))
                    bar(&context, tile.midX - 2, tile.midY - 2, 4, 4, color(ThemeKey.railForeground))
                } else {
                    fill(&context, tile, item.state == 1 ? color(ThemeKey.railActiveBackground) : wash, radius: 3.5)
                    bar(&context, tile.midX - 3, tile.midY - 1.25, 6, 2.5, color(item.state == 1 ? ThemeKey.sidebarActiveForeground : ThemeKey.railForeground).opacity(0.85))
                    if item.state == 1 {
                        fill(&context, CGRect(x: rect.minX, y: tile.midY - 4, width: 2, height: 8), ThemeKey.railActiveIndicator, radius: 1)
                    }
                    if item.state == 2 {
                        let center = CGPoint(x: tile.maxX - 0.5, y: tile.minY + 0.5)
                        dot(&context, center: center, diameter: 7, theme.surfaceColor(ThemeKey.railBackground, on: .sidebar, vibrancy: vibrancy).color)
                        dot(&context, center: center, diameter: 5.5, color(ThemeKey.railBadgeBackground))
                    }
                }
                y += side + 4
            }
            y += 3
        }
    }

    private func drawMembers(in context: inout GraphicsContext, rect: CGRect, desktop: CGRect) {
        surface(&context, rect, ThemeKey.memberListBackground, on: .content, desktop: desktop)
        bar(&context, rect.minX + 8, 32, 26, 3, color(ThemeKey.memberListHeaderForeground))
        var y = 42.0
        let widths: [Double] = [26, 20, 30, 22, 17, 27, 23, 19, 25]
        for (index, width) in widths.enumerated() {
            if index < 2 {
                bar(&context, rect.minX + 8, y, 3, 4, color(ThemeKey.memberListPrefixForeground))
            }
            let key = index == 6 ? ThemeKey.memberListAwayForeground : ThemeKey.memberListForeground
            bar(&context, rect.minX + 14, y, width, 4, color(key).opacity(0.85))
            y += 11
            if y > rect.maxY - 8 { break }
        }
    }

    // MARK: Tabs

    private enum TabState { case selected, unread, mention, read }

    private static let tabs: [(width: Double, state: TabState)] = [(34, .selected), (28, .unread), (38, .mention), (24, .read)]

    private var tabRadiusFraction: Double { max(0, min(1, config.tabRoundness)) }

    /// Tabs in the title strip: the networks as a segmented group, then
    /// free-standing channel tabs, as `TitleBarTabStack` draws them.
    private func drawTitleBarTabs(in context: inout GraphicsContext, x: Double, y: Double, height: Double, maxX: Double) {
        var cursor = x
        // Networks: a segmented group with the selected network filled.
        let group = CGRect(x: cursor, y: y, width: 30, height: height)
        let radius = tabRadiusFraction * height / 2
        fill(&context, group, ThemeKey.tabGroupBackground, radius: radius)
        let segment = CGRect(x: group.minX + 1.5, y: group.minY + 1.5, width: 14, height: height - 3)
        fill(&context, segment, ThemeKey.tabServerActiveBackground, radius: max(0, radius - 1.5))
        bar(&context, segment.minX + 3.5, segment.midY - 1.25, 7, 2.5, color(ThemeKey.tabPillForeground))
        bar(&context, segment.maxX + 3, segment.midY - 1.25, 8, 2.5, color(ThemeKey.titleBarSecondaryForeground))
        cursor = group.maxX + 6
        for tab in Self.tabs {
            guard cursor + tab.width <= maxX else { break }
            let rect = CGRect(x: cursor, y: y, width: tab.width, height: height)
            let label: String
            switch tab.state {
            case .selected:
                fill(&context, rect, ThemeKey.tabPillBackground, radius: radius)
                label = ThemeKey.tabPillForeground
            case .unread: label = ThemeKey.titleBarForeground
            case .mention: label = ThemeKey.tabHighlightForeground
            case .read: label = ThemeKey.titleBarSecondaryForeground
            }
            bar(&context, cursor + 6, y + height / 2 - 1.5, tab.width - 12, 3, color(label))
            cursor += tab.width + 3
        }
    }

    /// A strip above or below the conversation: the network row on the
    /// far side, then the channel row. The selected channel tab is drawn
    /// after the conversation (`drawSelectedAttachedTab`) so it opens into it.
    private func drawStripTabs(in context: inout GraphicsContext, rect: CGRect, conversationEdge: VerticalEdge, desktop: CGRect) {
        let serverHeight = 9.0
        let isTop = conversationEdge == .bottom
        surface(&context, rect, ThemeKey.tabBarBackground, on: .tabs, desktop: desktop)
        let serverRow = CGRect(x: rect.minX, y: isTop ? rect.minY : rect.maxY - serverHeight, width: rect.width, height: serverHeight)
        surface(&context, serverRow, ThemeKey.tabServerBackground, on: .tabs, desktop: desktop)
        // Networks: the selected one filled.
        let chipHeight = 6.0
        let chip = CGRect(x: serverRow.minX + 8, y: serverRow.midY - chipHeight / 2, width: 22, height: chipHeight)
        fill(&context, chip, ThemeKey.tabServerActiveBackground, radius: tabRadiusFraction * chipHeight / 2)
        bar(&context, chip.minX + 4, chip.midY - 1, chip.width - 8, 2, color(ThemeKey.tabPillForeground))
        bar(&context, chip.maxX + 5, chip.midY - 1, 16, 2, color(ThemeKey.tabForeground))

        // Channels.
        let row = CGRect(x: rect.minX, y: isTop ? serverRow.maxY : rect.minY, width: rect.width, height: rect.height - serverHeight)
        let isPill = config.tabRoundness >= 0.8
        let tabHeight = isPill ? 11.0 : row.height - 2
        let tabY = isPill ? row.midY - tabHeight / 2 : (isTop ? row.maxY - tabHeight : row.minY)
        // The conversation-side border; an attached selected tab covers it.
        fill(&context, CGRect(x: rect.minX, y: isTop ? rect.maxY - 0.75 : rect.minY, width: rect.width, height: 0.75), ThemeKey.tabBorder)
        var cursor = rect.minX + 8
        for (index, tab) in Self.tabs.enumerated() {
            guard cursor + tab.width <= rect.maxX - 6 else { break }
            let tabRect = CGRect(x: cursor, y: tabY, width: tab.width, height: tabHeight)
            let label: String
            switch tab.state {
            case .selected:
                if isPill {
                    fill(&context, tabRect, ThemeKey.tabPillBackground, radius: tabHeight / 2)
                    label = ThemeKey.tabPillForeground
                } else {
                    label = ThemeKey.tabActiveForeground
                }
            case .unread: label = ThemeKey.tabUnreadForeground
            case .mention: label = ThemeKey.tabHighlightForeground
            case .read: label = ThemeKey.tabForeground
            }
            if tab.state != .selected || isPill {
                bar(&context, cursor + 6, tabRect.midY - 1.5, tab.width - 12, 3, color(label))
            }
            // Rules between neighbors that aren't selected.
            if !isPill, index >= 2 {
                fill(&context, CGRect(x: cursor - 1.5, y: tabRect.minY + 3, width: 0.75, height: tabHeight - 6), ThemeKey.tabSeparator)
            }
            cursor += tab.width + (isPill ? 3 : 0)
        }
    }

    /// The selected attached tab, in the conversation's color, merging into
    /// it, with the accent indicator on its far edge.
    private func drawSelectedAttachedTab(in context: inout GraphicsContext, rect: CGRect, conversationEdge: VerticalEdge) {
        guard config.tabRoundness < 0.8, let first = Self.tabs.first else { return }
        let isTop = conversationEdge == .bottom
        let serverHeight = 9.0
        let rowHeight = rect.height - serverHeight
        let height = rowHeight - 2
        let tab = CGRect(x: rect.minX + 8, y: isTop ? rect.maxY - height : rect.minY, width: first.width, height: height + 0.75)
        let radius = min(tabRadiusFraction * height, height / 2, 5)
        var path = Path()
        if isTop {
            path.addRoundedRect(in: tab, cornerRadii: RectangleCornerRadii(topLeading: radius, bottomLeading: 0, bottomTrailing: 0, topTrailing: radius), style: .continuous)
        } else {
            path.addRoundedRect(in: tab, cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0), style: .continuous)
        }
        context.fill(path, with: .color(theme.surfaceColor(ThemeKey.tabActiveBackground, on: .content, vibrancy: vibrancy).color))
        context.stroke(path, with: .color(color(ThemeKey.tabBorder)), lineWidth: 0.6)
        // Reopen the side that merges into the conversation.
        let seam = CGRect(x: tab.minX + 0.6, y: isTop ? tab.maxY - 1.2 : tab.minY, width: tab.width - 1.2, height: 1.2)
        fill(&context, seam, theme.surfaceColor(ThemeKey.tabActiveBackground, on: .content, vibrancy: vibrancy).color)
        let indicatorY = isTop ? tab.minY + 1.2 : tab.maxY - 2.4
        bar(&context, tab.minX + 4, indicatorY, tab.width - 8, 1.2, color(ThemeKey.tabActiveIndicator))
        bar(&context, tab.minX + 6, tab.midY - 1.5, tab.width - 12, 3, color(ThemeKey.tabActiveForeground))
    }

    // MARK: Messages

    /// Draws the message area. `bleed` is how far rows extend past `rect`
    /// on each side (a mention's band reaches the conversation's edges).
    private func drawMessages(in context: inout GraphicsContext, rect: CGRect, bleed: Double) {
        var layer = context
        layer.clip(to: Path(rect.insetBy(dx: -bleed, dy: 0)))
        switch config.chatLayout {
        case .classic: drawClassic(in: &layer, rect: rect, bleed: bleed)
        case .grouped: drawGrouped(in: &layer, rect: rect, bleed: bleed)
        case .columns: drawColumns(in: &layer, rect: rect, bleed: bleed)
        }
    }

    /// A message that mentions you: the highlight band across the row with
    /// its bar on the leading edge.
    private func mentionBand(_ context: inout GraphicsContext, rect: CGRect, bleed: Double, y: Double, height: Double) {
        let band = CGRect(x: rect.minX - bleed, y: y, width: rect.width + bleed * 2, height: height)
        fill(&context, band, ThemeKey.chatHighlightBackground)
        fill(&context, CGRect(x: band.minX, y: band.minY, width: 1.5, height: band.height), ThemeKey.chatHighlightBorder)
    }

    /// The New line: a rule and its label in `chat.unreadMarker`.
    private func unreadMarker(_ context: inout GraphicsContext, rect: CGRect, y: Double) {
        let labelWidth = 9.0
        fill(&context, CGRect(x: rect.minX, y: y, width: rect.width - labelWidth - 3, height: 0.75), ThemeKey.chatUnreadMarker)
        bar(&context, rect.maxX - labelWidth, y - 1.1, labelWidth, 3, color(ThemeKey.chatUnreadMarker))
    }

    /// Message text with a link (in `chat.link`) after the first words.
    private func textWithLink(_ context: inout GraphicsContext, x: Double, y: Double, width: Double, seed: Int) {
        let lead = min(width * 0.35, 30)
        text(&context, x: x, y: y, width: lead, height: 4, color: bodyText, seed: seed)
        bar(&context, x + lead + 2.4, y, max(0, min(width - lead - 2.4, 34)), 4, color(ThemeKey.chatLink))
    }

    /// Message text that mentions you: a word in `chat.mention`, then text.
    private func textWithMention(_ context: inout GraphicsContext, x: Double, y: Double, width: Double, seed: Int) {
        let mention = min(16, width * 0.3)
        bar(&context, x, y, mention, 4, color(ThemeKey.chatMention))
        text(&context, x: x + mention + 2.4, y: y, width: max(0, width - mention - 2.4), height: 4, color: bodyText, seed: seed)
    }

    /// Which line of the Classic and Columns layouts shows a link, a
    /// mention, and the New line above it.
    private static let linkLine = 2
    private static let mentionLine = 6
    private static let unreadLine = 5

    private func drawClassic(in context: inout GraphicsContext, rect: CGRect, bleed: Double) {
        let step = config.monospace ? 9.5 : 10.5
        var y = rect.minY + 1
        var index = 0
        while y + 4 <= rect.maxY {
            if index == Self.unreadLine {
                unreadMarker(&context, rect: rect, y: y + 1.5)
                y += 5
                guard y + 4 <= rect.maxY else { break }
            }
            if index == Self.mentionLine {
                mentionBand(&context, rect: rect, bleed: bleed, y: y - 3, height: step)
            }
            var x = rect.minX
            if config.showTimestamps {
                bar(&context, x, y + 0.25, 13, 3.5, color(ThemeKey.chatTimestamp))
                x += 17
            }
            if index == 3 {
                bar(&context, x, y + 0.25, 64, 3.5, color(ThemeKey.chatEvent).opacity(0.85))
            } else {
                let nickWidth = [14.0, 19, 12, 17][index % 4]
                bar(&context, x, y, nickWidth, 4, nickColor(index))
                x += nickWidth + 4
                let width = (rect.maxX - x) * Self.widths[index % Self.widths.count]
                if index == Self.linkLine {
                    textWithLink(&context, x: x, y: y, width: width, seed: index)
                } else if index == Self.mentionLine {
                    textWithMention(&context, x: x, y: y, width: width, seed: index)
                } else {
                    text(&context, x: x, y: y, width: width, height: 4, color: bodyText, seed: index)
                }
            }
            y += step
            if let slot = Self.attachmentLines.firstIndex(of: index) {
                let indent = rect.minX + (config.showTimestamps ? 17 : 0) + 23
                let height = drawAttachment(slot, in: &context, x: indent, y: y, maxWidth: rect.maxX - indent, maxY: rect.maxY)
                if height > 0 { y += height + 3 }
            }
            index += 1
        }
    }

    private func drawGrouped(in context: inout GraphicsContext, rect: CGRect, bleed: Double) {
        let groups: [Int] = [2, 1, 3, 1, 2, 2]
        let linkGroup = 1, mentionGroup = 3, unreadGroup = 3
        var y = rect.minY + 1
        for (group, lines) in groups.enumerated() {
            if group == unreadGroup {
                // Only when the group under it fits too.
                guard y + 22 <= rect.maxY else { break }
                unreadMarker(&context, rect: rect, y: y - 1.5)
                y += 5
            }
            // Only draw groups whose header and first line fit.
            guard y + 16 <= rect.maxY else { break }
            if group == mentionGroup {
                mentionBand(&context, rect: rect, bleed: bleed, y: y - 3, height: 9.5 + Double(lines) * 7.5 + 2)
            }
            let textX = rect.minX + (config.showAvatars ? 19 : 0)
            if config.showAvatars {
                let avatar = CGRect(x: rect.minX, y: y, width: 14, height: 14)
                context.fill(Path(ellipseIn: avatar), with: .color(nickColor(group).opacity(0.35)))
                context.stroke(Path(ellipseIn: avatar.insetBy(dx: 0.4, dy: 0.4)), with: .color(nickColor(group).opacity(0.6)), lineWidth: 0.8)
            }
            let nickWidth = [18.0, 24, 15, 21][group % 4]
            bar(&context, textX, y + 1, nickWidth, 4.5, nickColor(group))
            if config.showTimestamps {
                bar(&context, textX + nickWidth + 4, y + 1.75, 12, 3, color(ThemeKey.chatTimestamp))
            }
            y += 9.5
            for line in 0..<lines {
                let seed = group * 3 + line
                let width = (rect.maxX - textX) * Self.widths[seed % Self.widths.count]
                if group == linkGroup && line == 0 {
                    textWithLink(&context, x: textX, y: y, width: max(width, 60), seed: seed)
                } else if group == mentionGroup && line == 0 {
                    textWithMention(&context, x: textX, y: y, width: width, seed: seed)
                } else {
                    text(&context, x: textX, y: y, width: width, height: 4, color: bodyText, seed: seed)
                }
                y += 7.5
            }
            if group < Self.attachments.count {
                let height = drawAttachment(group, in: &context, x: textX, y: y + 1, maxWidth: rect.maxX - textX, maxY: rect.maxY)
                if height > 0 { y += height + 3 }
            }
            y += 7
        }
    }

    private func drawColumns(in context: inout GraphicsContext, rect: CGRect, bleed: Double) {
        let timeWidth = config.showTimestamps ? 18.0 : 0
        let nickColumn = 36.0
        let textX = rect.minX + timeWidth + nickColumn + 9
        fill(&context, CGRect(x: textX - 5, y: rect.minY, width: 0.75, height: rect.height), color(ThemeKey.chatSecondaryForeground).opacity(0.25))
        var y = rect.minY + 1
        var index = 0
        while y + 4 <= rect.maxY {
            if index == Self.unreadLine {
                unreadMarker(&context, rect: rect, y: y + 1)
                y += 5
                guard y + 4 <= rect.maxY else { break }
            }
            if index == Self.mentionLine {
                mentionBand(&context, rect: rect, bleed: bleed, y: y - 2.75, height: 9.5)
            }
            if config.showTimestamps {
                bar(&context, rect.minX, y + 0.25, 13, 3.5, color(ThemeKey.chatTimestamp))
            }
            if index == 4 {
                bar(&context, textX, y + 0.25, 58, 3.5, color(ThemeKey.chatEvent).opacity(0.85))
            } else {
                let nickWidth = min(nickColumn, [16.0, 22, 13, 28][index % 4])
                bar(&context, rect.minX + timeWidth + nickColumn - nickWidth, y, nickWidth, 4, nickColor(index))
                let width = (rect.maxX - textX) * Self.widths[index % Self.widths.count]
                if index == Self.linkLine {
                    textWithLink(&context, x: textX, y: y, width: width, seed: index)
                } else if index == Self.mentionLine {
                    textWithMention(&context, x: textX, y: y, width: width, seed: index)
                } else {
                    text(&context, x: textX, y: y, width: width, height: 4, color: bodyText, seed: index)
                }
            }
            y += 9.5
            if let slot = Self.attachmentLines.firstIndex(of: index) {
                let height = drawAttachment(slot, in: &context, x: textX, y: y, maxWidth: rect.maxX - textX, maxY: rect.maxY)
                if height > 0 { y += height + 3 }
            }
            index += 1
        }
    }

    // MARK: Media

    private enum Attachment {
        case video, link, image
    }

    /// What the window and message-area drawings show under a few messages,
    /// in order. Each is skipped when it doesn't fit, so a tight layout keeps
    /// the first and drops the rest.
    private static let attachments: [Attachment] = [.video, .link, .image]
    /// The Classic and Columns lines the attachments follow; Grouped puts
    /// one under each of its first groups.
    private static let attachmentLines = [1, 5, 8]

    /// Draws attachment `slot` if it fits above `maxY` and returns its height
    /// (0 when nothing was drawn).
    private func drawAttachment(_ slot: Int, in context: inout GraphicsContext, x: Double, y: Double, maxWidth: Double, maxY: Double) -> Double {
        guard config.showMedia, slot < Self.attachments.count else { return 0 }
        let origin = CGPoint(x: x, y: y)
        switch Self.attachments[slot] {
        case .video:
            // The player is drawn small here so a link preview still fits under it.
            let scale = config.videoStyle == .player ? 0.6 : 1
            guard videoHeight(config.videoStyle, maxWidth: maxWidth, scale: scale) <= maxY - y else { return 0 }
            return drawVideo(config.videoStyle, in: &context, at: origin, maxWidth: maxWidth, scale: scale)
        case .link:
            guard config.showLinkCards, linkHeight(config.linkPreviewSize, scale: 1) <= maxY - y else { return 0 }
            return drawLinkPreview(config.linkPreviewSize, in: &context, at: origin, maxWidth: maxWidth, scale: 1)
        case .image:
            guard imageHeight(config.imageSize, scale: 1) <= maxY - y else { return 0 }
            return drawImage(config.imageSize, in: &context, at: origin, maxWidth: maxWidth, scale: 1)
        }
    }

    /// An embed card's background, border and accent stripe.
    private func card(_ context: inout GraphicsContext, _ rect: CGRect, radius: Double, scale: Double) {
        fill(&context, rect, ThemeKey.embedBackground, radius: radius)
        stroke(&context, rect, ThemeKey.embedBorder, radius: radius, width: 0.6 * scale)
        fill(&context, CGRect(x: rect.minX, y: rect.minY, width: 2.5 * scale, height: rect.height), ThemeKey.embedAccent, radius: 1.2 * scale)
    }

    /// An image placeholder with a little landscape glyph.
    private func picture(_ context: inout GraphicsContext, _ rect: CGRect, radius: Double) {
        fill(&context, rect, ThemeKey.embedPlaceholderBackground, radius: radius)
        let width = rect.width, height = rect.height
        var mountain = Path()
        mountain.move(to: CGPoint(x: rect.minX + width * 0.1, y: rect.maxY - height * 0.19))
        mountain.addLine(to: CGPoint(x: rect.minX + width * 0.32, y: rect.minY + height * 0.35))
        mountain.addLine(to: CGPoint(x: rect.minX + width * 0.48, y: rect.maxY - height * 0.42))
        mountain.addLine(to: CGPoint(x: rect.minX + width * 0.6, y: rect.minY + height * 0.5))
        mountain.addLine(to: CGPoint(x: rect.maxX - width * 0.1, y: rect.maxY - height * 0.19))
        mountain.closeSubpath()
        context.fill(mountain, with: .color(color(ThemeKey.embedAccent).opacity(0.45)))
        let sun = min(width, height) * 0.23
        context.fill(
            Path(ellipseIn: CGRect(x: rect.maxX - width * 0.24 - sun / 2, y: rect.minY + height * 0.15, width: sun, height: sun)),
            with: .color(color(ThemeKey.embedAccent).opacity(0.7))
        )
    }

    /// The accent ▶ button, like the real player's.
    private func playButton(_ context: inout GraphicsContext, center: CGPoint, diameter: Double) {
        let radius = diameter / 2
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)),
            with: .color(color(ThemeKey.accent))
        )
        let side = diameter * 0.38
        var triangle = Path()
        triangle.move(to: CGPoint(x: center.x - side * 0.36, y: center.y - side / 2))
        triangle.addLine(to: CGPoint(x: center.x + side * 0.56, y: center.y))
        triangle.addLine(to: CGPoint(x: center.x - side * 0.36, y: center.y + side / 2))
        triangle.closeSubpath()
        context.fill(triangle, with: .color(color(ThemeKey.accentForeground)))
    }

    // MARK: Link previews

    private func linkHeight(_ size: LinkPreviewSize, scale: Double) -> Double {
        switch size {
        case .minimal: 11 * scale
        case .standard: 32 * scale
        case .large: 56 * scale
        }
    }

    /// Draws a link preview and returns its height.
    @discardableResult
    private func drawLinkPreview(_ size: LinkPreviewSize, in context: inout GraphicsContext, at origin: CGPoint, maxWidth: Double, scale s: Double) -> Double {
        let x = origin.x, y = origin.y
        let height = linkHeight(size, scale: s)
        switch size {
        case .minimal:
            // Favicon, site and title on one line, a tiny thumbnail at the end.
            let row = CGRect(x: x, y: y, width: min(maxWidth, 96 * s), height: height)
            card(&context, row, radius: 3 * s, scale: s)
            context.fill(
                Path(ellipseIn: CGRect(x: x + 5.5 * s, y: row.midY - 2.25 * s, width: 4.5 * s, height: 4.5 * s)),
                with: .color(color(ThemeKey.embedSiteName).opacity(0.7))
            )
            bar(&context, x + 12.5 * s, row.midY - 1.4 * s, 14 * s, 2.75 * s, color(ThemeKey.embedSiteName))
            let thumb = CGRect(x: row.maxX - 14.5 * s, y: y + 1.75 * s, width: 12 * s, height: height - 3.5 * s)
            bar(&context, x + 29.5 * s, row.midY - 1.75 * s, thumb.minX - 4 * s - (x + 29.5 * s), 3.5 * s, color(ThemeKey.embedTitle))
            picture(&context, thumb, radius: 1.5 * s)
        case .standard:
            // Text on the left, a 4:3 thumbnail on the right.
            let box = CGRect(x: x, y: y, width: min(maxWidth, 124 * s), height: height)
            card(&context, box, radius: 4 * s, scale: s)
            let thumb = CGRect(x: box.maxX - 36 * s, y: y + 4 * s, width: 32 * s, height: 24 * s)
            picture(&context, thumb, radius: 2.5 * s)
            let textX = x + 7 * s
            let textWidth = thumb.minX - 5 * s - textX
            bar(&context, textX, y + 5 * s, min(textWidth, 22 * s), 2.75 * s, color(ThemeKey.embedSiteName))
            bar(&context, textX, y + 10 * s, textWidth * 0.95, 3.75 * s, color(ThemeKey.embedTitle))
            bar(&context, textX, y + 15.5 * s, textWidth * 0.6, 3.75 * s, color(ThemeKey.embedTitle))
            bar(&context, textX, y + 22 * s, textWidth * 0.9, 2.75 * s, color(ThemeKey.embedDescription).opacity(0.85))
            bar(&context, textX, y + 26.5 * s, textWidth * 0.7, 2.75 * s, color(ThemeKey.embedDescription).opacity(0.85))
        case .large:
            // Site, title, description and a big image underneath.
            let box = CGRect(x: x, y: y, width: min(maxWidth, 112 * s), height: height)
            card(&context, box, radius: 4 * s, scale: s)
            let inner = x + 7 * s
            bar(&context, inner, y + 5 * s, 26 * s, 2.75 * s, color(ThemeKey.embedSiteName))
            bar(&context, inner, y + 10.5 * s, min(box.width - 14 * s, 64 * s), 4 * s, color(ThemeKey.embedTitle))
            bar(&context, inner, y + 17.5 * s, min(box.width - 14 * s, 84 * s), 3 * s, color(ThemeKey.embedDescription).opacity(0.85))
            let image = CGRect(x: inner, y: y + 24 * s, width: min(box.width - 14 * s, 62 * s), height: 26 * s)
            picture(&context, image, radius: 2.5 * s)
        }
        return height
    }

    // MARK: Videos

    private func playerWidth(maxWidth: Double, scale s: Double) -> Double { min(maxWidth, 100 * s) }

    private func videoHeight(_ style: VideoEmbedStyle, maxWidth: Double, scale s: Double) -> Double {
        switch style {
        case .player: 18 * s + (playerWidth(maxWidth: maxWidth, scale: s) - 13 * s) * 9 / 16 + 5 * s
        case .compact: 11 * s
        case .off: config.showLinkCards ? linkHeight(config.linkPreviewSize, scale: s) : 0
        }
    }

    /// Draws a video embed and returns its height. Off is a link preview.
    @discardableResult
    private func drawVideo(_ style: VideoEmbedStyle, in context: inout GraphicsContext, at origin: CGPoint, maxWidth: Double, scale s: Double) -> Double {
        let x = origin.x, y = origin.y
        switch style {
        case .player:
            // Provider and title, then a 16:9 dark area with ▶.
            let box = CGRect(x: x, y: y, width: playerWidth(maxWidth: maxWidth, scale: s), height: videoHeight(.player, maxWidth: maxWidth, scale: s))
            card(&context, box, radius: 4 * s, scale: s)
            let inner = x + 7 * s
            fill(&context, CGRect(x: inner, y: y + 4.25 * s, width: 7 * s, height: 3.75 * s), ThemeKey.embedAccent, radius: 1 * s)
            bar(&context, inner + 10 * s, y + 4.75 * s, min(box.width - 24 * s, 20 * s), 2.75 * s, color(ThemeKey.embedSiteName))
            bar(&context, inner, y + 10.5 * s, min(box.width - 14 * s, 58 * s), 3.75 * s, color(ThemeKey.embedTitle))
            let screenWidth = box.width - 13 * s
            let screen = CGRect(x: inner, y: y + 18 * s, width: screenWidth, height: screenWidth * 9 / 16)
            // Letterboxing is always black in the app.
            fill(&context, screen, Color.black, radius: 2.5 * s)
            playButton(&context, center: CGPoint(x: screen.midX, y: screen.midY), diameter: screen.height * 0.36)
            return box.height
        case .compact:
            // ▶, provider and title on one line, a tiny thumbnail at the end.
            let row = CGRect(x: x, y: y, width: min(maxWidth, 100 * s), height: videoHeight(.compact, maxWidth: maxWidth, scale: s))
            card(&context, row, radius: 3 * s, scale: s)
            playButton(&context, center: CGPoint(x: x + 8.75 * s, y: row.midY), diameter: 7 * s)
            fill(&context, CGRect(x: x + 15 * s, y: row.midY - 1.75 * s, width: 6 * s, height: 3.5 * s), ThemeKey.embedAccent, radius: 0.9 * s)
            let thumb = CGRect(x: row.maxX - 14.5 * s, y: y + 1.75 * s, width: 12 * s, height: row.height - 3.5 * s)
            bar(&context, x + 24 * s, row.midY - 1.75 * s, thumb.minX - 4 * s - (x + 24 * s), 3.5 * s, color(ThemeKey.embedTitle))
            picture(&context, thumb, radius: 1.5 * s)
            return row.height
        case .off:
            guard config.showLinkCards else { return 0 }
            return drawLinkPreview(config.linkPreviewSize, in: &context, at: origin, maxWidth: maxWidth, scale: s)
        }
    }

    // MARK: Images

    private func imageHeight(_ size: InlineImageSize, scale s: Double) -> Double {
        switch size {
        case .full: 40 * s
        case .thumbnail: 16 * s
        }
    }

    @discardableResult
    private func drawImage(_ size: InlineImageSize, in context: inout GraphicsContext, at origin: CGPoint, maxWidth: Double, scale s: Double) -> Double {
        let height = imageHeight(size, scale: s)
        let width = size == .full ? 64 * s : 21 * s
        picture(&context, CGRect(x: origin.x, y: origin.y, width: min(maxWidth, width), height: height), radius: 3 * s)
        return height
    }

    // MARK: Zoomed-in message

    /// One message with a link (or video link) and its preview, then the
    /// start of the next message.
    private func drawMediaMessage(in context: inout GraphicsContext, rect: CGRect, video: Bool) {
        var y = rect.minY
        let avatar = CGRect(x: rect.minX, y: y, width: 16, height: 16)
        context.fill(Path(ellipseIn: avatar), with: .color(nickColor(1).opacity(0.35)))
        context.stroke(Path(ellipseIn: avatar.insetBy(dx: 0.4, dy: 0.4)), with: .color(nickColor(1).opacity(0.6)), lineWidth: 0.8)
        let textX = rect.minX + 22
        bar(&context, textX, y + 1, 22, 5, nickColor(1))
        bar(&context, textX + 26, y + 2, 13, 3.5, color(ThemeKey.chatTimestamp))
        y += 10.5
        text(&context, x: textX, y: y, width: 52, height: 4.5, color: bodyText, seed: 2)
        bar(&context, textX + 56, y, min(rect.maxX - textX - 56, 70), 4.5, color(ThemeKey.chatLink))
        y += 9
        let origin = CGPoint(x: textX, y: y)
        let maxWidth = rect.maxX - textX
        var height = 0.0
        if video {
            let scale = switch config.videoStyle {
            case .player: 0.9
            case .compact: 1.25
            case .off: Self.zoomedLinkScale(config.linkPreviewSize)
            }
            height = drawVideo(config.videoStyle, in: &context, at: origin, maxWidth: maxWidth, scale: scale)
        } else if config.showLinkCards {
            height = drawLinkPreview(config.linkPreviewSize, in: &context, at: origin, maxWidth: maxWidth, scale: Self.zoomedLinkScale(config.linkPreviewSize))
        }
        y += height > 0 ? height + 9 : 3
        if y + 5 < rect.maxY {
            let avatar2 = CGRect(x: rect.minX, y: y, width: 16, height: 16)
            context.fill(Path(ellipseIn: avatar2), with: .color(nickColor(3).opacity(0.35)))
            bar(&context, textX, y + 1, 18, 5, nickColor(3))
            text(&context, x: textX, y: y + 10.5, width: rect.maxX - textX - 20, height: 4.5, color: bodyText, seed: 5)
        }
    }

    private static func zoomedLinkScale(_ size: LinkPreviewSize) -> Double {
        switch size {
        case .minimal: 1.25
        case .standard: 1.1
        case .large: 1.15
        }
    }
}
