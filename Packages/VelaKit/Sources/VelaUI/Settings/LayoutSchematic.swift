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
    var tabPlacement: TabStackPlacement = .top
    var tabRoundness: Double = 0.35
    var chatLayout: ChatLayout = .grouped
    var showAvatars = false
    var showTimestamps = true
    var colorNicks = true
    var memberList = true
    var monospace = false
    var mediaPresentation: MediaPresentation = .full
    var showMedia = true

    init() {}

    /// The current settings, with `overrides` (raw settings.json values,
    /// e.g. a preset's) layered on top.
    init(settings: SettingsStore, overrides: [String: JSONValue] = [:]) {
        func read<Value>(_ key: SettingKey<Value>) -> Value {
            key.value(from: overrides[key.key] ?? settings.value(forKey: key.key))
        }
        navigation = read(.navigationStyle)
        tabPlacement = read(.tabsPlacement)
        tabRoundness = read(.tabsRoundness)
        chatLayout = read(.chatLayout)
        showAvatars = read(.chatShowAvatars)
        showTimestamps = read(.chatShowTimestamps)
        colorNicks = read(.chatColorNicks)
        memberList = read(.memberListVisible)
        monospace = read(.chatMonospace)
        mediaPresentation = read(.mediaPresentation)
    }

    init(preset: SettingsPreset, settings: SettingsStore) {
        self.init(settings: settings, overrides: preset.values)
    }
}

/// A miniature, schematic drawing of Vela's window (or part of it) in a
/// given theme. Text is drawn as bars so it reads at any size.
struct LayoutSchematic: View {
    enum Scope {
        /// The whole window: navigation, title strip, chat, input, members.
        case window
        /// Only the message area, zoomed in.
        case messages
        /// One message with a link preview, zoomed in further.
        case media
    }

    let config: LayoutSchematicConfig
    let theme: ResolvedTheme
    var scope: Scope = .window

    var body: some View {
        let design = SchematicPainter.designSize(for: scope)
        Canvas { context, size in
            let scale = min(size.width / design.width, size.height / design.height)
            context.translateBy(
                x: (size.width - design.width * scale) / 2,
                y: (size.height - design.height * scale) / 2
            )
            context.scaleBy(x: scale, y: scale)
            SchematicPainter(config: config, theme: theme).draw(scope, in: &context)
        }
        .aspectRatio(design.width / design.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Draws the schematic in a fixed design space; `LayoutSchematic` scales it.
private struct SchematicPainter {
    let config: LayoutSchematicConfig
    let theme: ResolvedTheme

    static func designSize(for scope: LayoutSchematic.Scope) -> CGSize {
        switch scope {
        case .window: CGSize(width: 320, height: 200)
        case .messages: CGSize(width: 220, height: 110)
        case .media: CGSize(width: 190, height: 100)
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
            fill(&context, bounds, ThemeKey.chatBackground)
            drawMessages(in: &context, rect: bounds.insetBy(dx: 10, dy: 9))
        case .media:
            context.clip(to: Path(roundedRect: bounds, cornerRadius: 8, style: .continuous))
            fill(&context, bounds, ThemeKey.chatBackground)
            drawMediaMessage(in: &context, rect: bounds.insetBy(dx: 10, dy: 10))
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
        let palette = theme.nickColors
        return palette[(index * 5 + 2) % palette.count].color
    }

    private var bodyText: Color { color(ThemeKey.chatForeground).opacity(0.62) }

    // MARK: Window

    private func drawWindow(in context: inout GraphicsContext, bounds: CGRect) {
        let width = bounds.width, height = bounds.height
        fill(&context, bounds, ThemeKey.windowBackground)

        var left = 0.0
        var right = width
        if config.navigation == .sidebar {
            let sidebarWidth = 78.0
            drawSidebar(in: &context, rect: CGRect(x: 0, y: 0, width: sidebarWidth, height: height))
            fill(&context, CGRect(x: sidebarWidth, y: 0, width: 1, height: height), ThemeKey.paneDivider)
            left = sidebarWidth + 1
        }
        if config.memberList {
            let memberWidth = 60.0
            drawMembers(in: &context, rect: CGRect(x: width - memberWidth, y: 0, width: memberWidth, height: height))
            fill(&context, CGRect(x: width - memberWidth - 1, y: 0, width: 1, height: height), ThemeKey.paneDivider)
            right = width - memberWidth - 1
        }

        let chat = CGRect(x: left, y: 0, width: right - left, height: height)
        fill(&context, chat, ThemeKey.chatBackground)

        // Title strip (or title-bar tabs).
        let titleHeight = 26.0
        fill(&context, CGRect(x: chat.minX, y: 0, width: chat.width, height: titleHeight), ThemeKey.titleBarBackground)
        fill(&context, CGRect(x: chat.minX, y: titleHeight - 1, width: chat.width, height: 1), ThemeKey.titleBarBorder)
        let titleX = chat.minX + (config.navigation == .tabs ? 40 : 10)
        let usesTabs = config.navigation == .tabs
        if usesTabs && config.tabPlacement == .titleBar {
            drawTabs(in: &context, x: titleX, y: 6.5, height: 13, maxX: chat.maxX - 22)
        } else {
            bar(&context, titleX, 7.5, 34, 4.5, color(ThemeKey.titleBarForeground))
            bar(&context, titleX, 15, 66, 3, color(ThemeKey.titleBarSecondaryForeground).opacity(0.8))
        }
        for index in 0..<2 {
            let x = chat.maxX - 12 - Double(index) * 9
            fill(&context, CGRect(x: x - 3, y: 10, width: 6, height: 6), ThemeKey.titleBarSecondaryForeground, radius: 1.5, opacity: 0.7)
        }

        var top = titleHeight
        if usesTabs && config.tabPlacement == .top {
            fill(&context, CGRect(x: chat.minX, y: top, width: chat.width, height: 21), ThemeKey.titleBarBackground)
            fill(&context, CGRect(x: chat.minX, y: top + 20, width: chat.width, height: 1), ThemeKey.titleBarBorder)
            drawTabs(in: &context, x: chat.minX + 8, y: top + 4, height: 13, maxX: chat.maxX - 6)
            top += 21
        }

        // Input.
        let inputArea = 28.0
        var bottom = height - inputArea
        fill(&context, CGRect(x: chat.minX, y: bottom, width: chat.width, height: inputArea), ThemeKey.inputContainerBackground)
        let field = CGRect(x: chat.minX + 8, y: bottom + 6, width: chat.width - 16, height: 16)
        fill(&context, field, ThemeKey.inputBackground, radius: 5)
        stroke(&context, field, ThemeKey.inputBorder, radius: 5)
        bar(&context, field.minX + 7, field.midY - 1.5, min(70, field.width * 0.4), 3, color(ThemeKey.inputPlaceholder))

        if usesTabs && config.tabPlacement == .bottom {
            fill(&context, CGRect(x: chat.minX, y: bottom - 21, width: chat.width, height: 21), ThemeKey.titleBarBackground)
            fill(&context, CGRect(x: chat.minX, y: bottom - 21, width: chat.width, height: 1), ThemeKey.titleBarBorder)
            drawTabs(in: &context, x: chat.minX + 8, y: bottom - 17, height: 13, maxX: chat.maxX - 6)
            bottom -= 21
        }

        let messages = CGRect(x: chat.minX + 9, y: top + 7, width: chat.width - 18, height: bottom - top - 10)
        drawMessages(in: &context, rect: messages)

        // Traffic lights.
        for (index, key) in [ThemeKey.statusError, ThemeKey.statusWarning, ThemeKey.statusSuccess].enumerated() {
            let center = CGPoint(x: 10 + Double(index) * 9, y: 12)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 3.2, y: center.y - 3.2, width: 6.4, height: 6.4)),
                with: .color(color(key))
            )
        }
    }

    private func drawSidebar(in context: inout GraphicsContext, rect: CGRect) {
        fill(&context, rect, ThemeKey.sidebarBackground)
        var y = 30.0
        let rows: [(width: Double, state: Int)] = [(26, 1), (22, 2), (30, 0), (18, 0)]
        let more: [(width: Double, state: Int)] = [(24, 0), (28, 2)]
        for (header, items) in [(36.0, rows), (28.0, more)] {
            bar(&context, rect.minX + 9, y, header, 3.5, color(ThemeKey.sidebarHeaderForeground))
            y += 10
            for item in items {
                if item.state == 1 {
                    fill(&context, CGRect(x: rect.minX + 5, y: y - 3.5, width: rect.width - 10, height: 11), ThemeKey.sidebarActiveBackground, radius: 3)
                    bar(&context, rect.minX + 12, y, item.width, 4, color(ThemeKey.sidebarActiveForeground))
                } else if item.state == 2 {
                    bar(&context, rect.minX + 12, y, item.width, 4, color(ThemeKey.sidebarUnreadForeground))
                    fill(&context, CGRect(x: rect.maxX - 18, y: y - 1.5, width: 10, height: 7), ThemeKey.sidebarBadgeBackground, radius: 3.5)
                } else {
                    bar(&context, rect.minX + 12, y, item.width, 4, color(ThemeKey.sidebarForeground).opacity(0.8))
                }
                y += 13
            }
            y += 5
        }
    }

    private func drawMembers(in context: inout GraphicsContext, rect: CGRect) {
        fill(&context, rect, ThemeKey.memberListBackground)
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

    private func drawTabs(in context: inout GraphicsContext, x: Double, y: Double, height: Double, maxX: Double) {
        let widths: [Double] = [34, 28, 38, 24]
        let radius = max(0, min(1, config.tabRoundness)) * height / 2
        var cursor = x
        for (index, width) in widths.enumerated() {
            guard cursor + width <= maxX else { break }
            let rect = CGRect(x: cursor, y: y, width: width, height: height)
            if index == 0 {
                fill(&context, rect, ThemeKey.accent, radius: radius)
                bar(&context, cursor + 6, y + height / 2 - 1.5, width - 12, 3, color(ThemeKey.accentForeground))
            } else {
                fill(&context, rect, ThemeKey.buttonSecondaryBackground, radius: radius)
                bar(&context, cursor + 6, y + height / 2 - 1.5, width - 12, 3, color(ThemeKey.buttonSecondaryForeground).opacity(0.7))
            }
            cursor += width + 4
        }
    }

    // MARK: Messages

    private func drawMessages(in context: inout GraphicsContext, rect: CGRect) {
        var layer = context
        layer.clip(to: Path(rect))
        switch config.chatLayout {
        case .classic: drawClassic(in: &layer, rect: rect)
        case .grouped: drawGrouped(in: &layer, rect: rect)
        case .columns: drawColumns(in: &layer, rect: rect)
        }
    }

    private func drawClassic(in context: inout GraphicsContext, rect: CGRect) {
        let step = config.monospace ? 9.5 : 10.5
        var y = rect.minY + 1
        var index = 0
        while y + 4 <= rect.maxY {
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
                text(&context, x: x, y: y, width: (rect.maxX - x) * Self.widths[index % Self.widths.count], height: 4, color: bodyText, seed: index)
            }
            y += step
            if index == 1 && config.showMedia {
                let indent = rect.minX + (config.showTimestamps ? 17 : 0) + 23
                y += drawEmbed(in: &context, x: indent, y: y, maxWidth: rect.maxX - indent) + 3
            }
            index += 1
        }
    }

    private func drawGrouped(in context: inout GraphicsContext, rect: CGRect) {
        let groups: [Int] = [2, 1, 3, 1, 2, 2]
        var y = rect.minY + 1
        for (group, lines) in groups.enumerated() {
            // Only draw groups whose header and first line fit.
            guard y + 16 <= rect.maxY else { break }
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
                text(&context, x: textX, y: y, width: (rect.maxX - textX) * Self.widths[seed % Self.widths.count], height: 4, color: bodyText, seed: seed)
                y += 7.5
            }
            if group == 1 && config.showMedia {
                y += drawEmbed(in: &context, x: textX, y: y + 1, maxWidth: rect.maxX - textX) + 2
            }
            y += 7
        }
    }

    private func drawColumns(in context: inout GraphicsContext, rect: CGRect) {
        let timeWidth = config.showTimestamps ? 18.0 : 0
        let nickColumn = 36.0
        let textX = rect.minX + timeWidth + nickColumn + 9
        fill(&context, CGRect(x: textX - 5, y: rect.minY, width: 0.75, height: rect.height), color(ThemeKey.chatSecondaryForeground).opacity(0.25))
        var y = rect.minY + 1
        var index = 0
        while y + 4 <= rect.maxY {
            if config.showTimestamps {
                bar(&context, rect.minX, y + 0.25, 13, 3.5, color(ThemeKey.chatTimestamp))
            }
            if index == 4 {
                bar(&context, textX, y + 0.25, 58, 3.5, color(ThemeKey.chatEvent).opacity(0.85))
            } else {
                let nickWidth = min(nickColumn, [16.0, 22, 13, 28][index % 4])
                bar(&context, rect.minX + timeWidth + nickColumn - nickWidth, y, nickWidth, 4, nickColor(index))
                text(&context, x: textX, y: y, width: (rect.maxX - textX) * Self.widths[index % Self.widths.count], height: 4, color: bodyText, seed: index)
            }
            y += 9.5
            if index == 1 && config.showMedia {
                y += drawEmbed(in: &context, x: textX, y: y, maxWidth: rect.maxX - textX) + 3
            }
            index += 1
        }
    }

    /// Draws a link preview and returns its height.
    @discardableResult
    private func drawEmbed(in context: inout GraphicsContext, x: Double, y: Double, maxWidth: Double, scale: Double = 1) -> Double {
        if config.mediaPresentation == .compact {
            let thumb = CGRect(x: x, y: y, width: 8 * scale, height: 8 * scale)
            fill(&context, thumb, ThemeKey.embedPlaceholderBackground, radius: 1.5 * scale)
            fill(&context, thumb.insetBy(dx: 2 * scale, dy: 2 * scale), ThemeKey.embedAccent, radius: 1 * scale, opacity: 0.6)
            bar(&context, x + 11 * scale, y + 2.25 * scale, min(maxWidth - 11 * scale, 72 * scale), 3.5 * scale, color(ThemeKey.chatLink))
            return 8 * scale
        }
        let width = min(maxWidth, 112 * scale)
        let height = 56 * scale
        let card = CGRect(x: x, y: y, width: width, height: height)
        fill(&context, card, ThemeKey.embedBackground, radius: 4 * scale)
        stroke(&context, card, ThemeKey.embedBorder, radius: 4 * scale, width: 0.6 * scale)
        fill(&context, CGRect(x: x, y: y, width: 2.5 * scale, height: height), ThemeKey.embedAccent, radius: 1.2 * scale)
        let inner = x + 7 * scale
        bar(&context, inner, y + 5 * scale, 26 * scale, 2.75 * scale, color(ThemeKey.embedSiteName))
        bar(&context, inner, y + 10.5 * scale, min(width - 14 * scale, 64 * scale), 4 * scale, color(ThemeKey.embedTitle))
        bar(&context, inner, y + 17.5 * scale, min(width - 14 * scale, 84 * scale), 3 * scale, color(ThemeKey.embedDescription).opacity(0.85))
        let image = CGRect(x: inner, y: y + 24 * scale, width: min(width - 14 * scale, 62 * scale), height: 26 * scale)
        fill(&context, image, ThemeKey.embedPlaceholderBackground, radius: 2.5 * scale)
        // A little landscape glyph.
        var mountain = Path()
        mountain.move(to: CGPoint(x: image.minX + 6 * scale, y: image.maxY - 5 * scale))
        mountain.addLine(to: CGPoint(x: image.minX + 20 * scale, y: image.minY + 9 * scale))
        mountain.addLine(to: CGPoint(x: image.minX + 30 * scale, y: image.maxY - 11 * scale))
        mountain.addLine(to: CGPoint(x: image.minX + 37 * scale, y: image.minY + 13 * scale))
        mountain.addLine(to: CGPoint(x: image.maxX - 6 * scale, y: image.maxY - 5 * scale))
        mountain.closeSubpath()
        context.fill(mountain, with: .color(color(ThemeKey.embedAccent).opacity(0.45)))
        context.fill(
            Path(ellipseIn: CGRect(x: image.maxX - 15 * scale, y: image.minY + 4 * scale, width: 6 * scale, height: 6 * scale)),
            with: .color(color(ThemeKey.embedAccent).opacity(0.7))
        )
        return height
    }

    private func drawMediaMessage(in context: inout GraphicsContext, rect: CGRect) {
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
        let height = drawEmbed(in: &context, x: textX, y: y, maxWidth: rect.maxX - textX, scale: config.mediaPresentation == .compact ? 1.25 : 1.15)
        y += height + 9
        if y + 5 < rect.maxY {
            let avatar2 = CGRect(x: rect.minX, y: y, width: 16, height: 16)
            context.fill(Path(ellipseIn: avatar2), with: .color(nickColor(3).opacity(0.35)))
            bar(&context, textX, y + 1, 18, 5, nickColor(3))
            text(&context, x: textX, y: y + 10.5, width: rect.maxX - textX - 20, height: 4.5, color: bodyText, seed: 5)
        }
    }
}
