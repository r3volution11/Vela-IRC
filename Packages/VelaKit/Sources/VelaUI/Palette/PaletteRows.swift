// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

enum PaletteMetrics {
    static let width: CGFloat = 600
    static let rowHeight: CGFloat = 30
    static let maxVisibleRows = 12
    static let cornerRadius: CGFloat = 10
    static let rowCornerRadius: CGFloat = 5
    static let listPadding: CGFloat = 5
    /// Distance from the top of the window (below the title strip).
    static let topInset: CGFloat = 46
}

/// One palette row: content for its item kind, selection and hover
/// backgrounds, and the VS Code-style section separator.
struct PaletteRowView: View {
    @Environment(\.theme) private var theme
    let row: PaletteRow
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 8) {
            switch row.item.payload {
            case .buffer(let buffer, let session):
                PaletteBufferRowContent(row: row, buffer: buffer, session: session)
            case .command(let command):
                PaletteCommandRowContent(row: row, command: command)
            case .theme(let info):
                PaletteThemeRowContent(row: row, info: info)
            }
            if let label = row.sectionLabel {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(theme[ThemeKey.popoverForeground].opacity(0.55))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: PaletteMetrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: PaletteMetrics.rowCornerRadius, style: .continuous)
                .fill(background)
        )
        .overlay(alignment: .top) {
            if row.startsSection {
                Rectangle()
                    .fill(theme[ThemeKey.popoverBorder])
                    .frame(height: 1)
                    .padding(.horizontal, 4)
                    .offset(y: -0.5)
            }
        }
        .contentShape(Rectangle())
    }

    private var background: Color {
        if isSelected { return theme[ThemeKey.chatSelectionBackground] }
        if isHovered { return theme[ThemeKey.chatHoverBackground] }
        return .clear
    }
}

// MARK: - Content

private struct PaletteBufferRowContent: View {
    @Environment(\.theme) private var theme
    let row: PaletteRow
    let buffer: BufferModel
    let session: NetworkSession

    var body: some View {
        let inactive = !session.isConnected || (buffer.kind == .channel && !buffer.isJoined)
        let primary = theme[ThemeKey.popoverForeground]
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 16)
            .foregroundStyle(primary.opacity(inactive ? 0.4 : 0.65))
        PaletteHighlightedText(
            text: row.item.label.text,
            matches: row.labelMatches,
            font: .system(size: 13, weight: .medium),
            color: primary.opacity(inactive ? 0.6 : 1)
        )
        if let detail = row.item.detail {
            PaletteHighlightedText(
                text: detail,
                matches: row.detailMatches,
                font: .system(size: 12),
                color: primary.opacity(0.55)
            )
            .layoutPriority(-1)
        }
        Spacer(minLength: 8)
        if row.item.isCurrent {
            Text("current")
                .font(.system(size: 11))
                .foregroundStyle(primary.opacity(0.55))
        }
        if buffer.highlightCount > 0 {
            UnreadBadge(count: buffer.highlightCount, isHighlight: true)
        } else if buffer.unreadCount > 0, !buffer.isMuted {
            UnreadBadge(count: buffer.unreadCount)
        }
    }

    private var icon: String {
        switch buffer.kind {
        case .server: "server.rack"
        case .channel: "number"
        case .query: "bubble.left"
        }
    }
}

private struct PaletteCommandRowContent: View {
    @Environment(\.theme) private var theme
    let row: PaletteRow
    let command: VelaCommand

    var body: some View {
        let primary = theme[ThemeKey.popoverForeground]
        PaletteHighlightedText(
            text: row.item.label.text,
            matches: row.labelMatches,
            dimmedPrefix: command.category.rawValue.count + 2,
            font: .system(size: 13),
            color: primary
        )
        Spacer(minLength: 8)
        if command.isChecked == true {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.accentText])
                .accessibilityHidden(true)
        }
        if !command.shortcutGlyphs.isEmpty {
            PaletteKeycaps(glyphs: command.shortcutGlyphs)
        }
    }
}

private struct PaletteThemeRowContent: View {
    @Environment(\.theme) private var theme
    @Environment(ThemeStore.self) private var themeStore
    let row: PaletteRow
    let info: ThemeInfo

    var body: some View {
        let primary = theme[ThemeKey.popoverForeground]
        ThemeSwatchStrip(theme: themeStore.resolvedTheme(for: info))
        PaletteHighlightedText(
            text: row.item.label.text,
            matches: row.labelMatches,
            font: .system(size: 13),
            color: primary
        )
        Spacer(minLength: 8)
        if info.source == .user {
            Text("custom")
                .font(.system(size: 11))
                .foregroundStyle(primary.opacity(0.55))
        }
        if row.item.isCurrent {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.accentText])
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Pieces

/// A label with the query's matched characters emphasized, and optionally
/// a dimmed prefix (a command's "View: " category).
struct PaletteHighlightedText: View {
    @Environment(\.theme) private var theme
    let text: String
    let matches: [Int]
    var dimmedPrefix = 0
    let font: Font
    let color: Color

    var body: some View {
        Text(attributed)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var attributed: AttributedString {
        let highlight = theme[ThemeKey.accentText]
        let dimmed = color.opacity(0.62)
        let boldFont = font.weight(.bold)
        let matched = Set(matches)

        var result = AttributedString()
        var run = ""
        var runStyle = 0
        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            switch runStyle {
            case 2:
                piece.foregroundColor = highlight
                piece.font = boldFont
            case 1:
                piece.foregroundColor = dimmed
                piece.font = font
            default:
                piece.foregroundColor = color
                piece.font = font
            }
            result += piece
            run = ""
        }
        for (offset, character) in text.enumerated() {
            let style = matched.contains(offset) ? 2 : (offset < dimmedPrefix ? 1 : 0)
            if style != runStyle {
                flush()
                runStyle = style
            }
            run.append(character)
        }
        flush()
        return result
    }
}

/// Shortcut glyphs drawn as small key caps (⇧ ⌘ P).
struct PaletteKeycaps: View {
    @Environment(\.theme) private var theme
    let glyphs: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(glyphs.enumerated()), id: \.offset) { _, glyph in
                Text(glyph)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme[ThemeKey.popoverForeground].opacity(0.8))
                    .padding(.horizontal, 4)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(theme[ThemeKey.popoverBorder])
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

/// A strip of a theme's key colors: sidebar, chat background, accent and
/// the first nick colors.
struct ThemeSwatchStrip: View {
    @Environment(\.theme) private var theme
    let swatchTheme: ResolvedTheme?

    init(theme: ResolvedTheme?) {
        swatchTheme = theme
    }

    var body: some View {
        HStack(spacing: 0) {
            if let swatches = swatchTheme {
                ForEach(Array(Self.colors(of: swatches).enumerated()), id: \.offset) { _, color in
                    Rectangle().fill(color)
                }
            } else {
                Rectangle().fill(theme[ThemeKey.popoverBorder])
            }
        }
        .frame(width: 66, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(theme[ThemeKey.popoverBorder], lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    static func colors(of theme: ResolvedTheme) -> [Color] {
        [
            theme[ThemeKey.sidebarBackground],
            theme[ThemeKey.chatBackground],
            theme[ThemeKey.accent],
        ] + theme.nickColors.prefix(3).map(\.color)
    }
}
