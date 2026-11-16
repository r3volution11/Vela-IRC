// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaStore
import VelaTheme

/// A short sample conversation rendered with the live chat style (layout,
/// fonts, spacing, timestamps, join/part display, nick colors, avatars,
/// formatting and large emoji), so Messages settings preview instantly.
struct MessageSamplePreview: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style

    private enum Kind {
        case message, mention, link, join, quit, formatted, emoji
    }

    private struct Line: Identifiable {
        let id: Int
        let kind: Kind
        let nick: String
        let text: String
        let minute: Int
        var isSelf = false
        var isEvent: Bool { kind == .join || kind == .quit }
    }

    private static let selfNick = "doug"

    private static let lines: [Line] = [
        Line(id: 0, kind: .mention, nick: "alice", text: "doug: have you tried the new tab stacks?", minute: 2),
        Line(id: 1, kind: .message, nick: "bob", text: "pill tabs in the title bar are lovely", minute: 3),
        Line(id: 2, kind: .link, nick: "bob", text: "theme docs: ", minute: 3),
        Line(id: 3, kind: .join, nick: "carol", text: "", minute: 4),
        Line(id: 4, kind: .quit, nick: "dave", text: "Ping timeout", minute: 4),
        Line(id: 5, kind: .formatted, nick: selfNick, text: "", minute: 5, isSelf: true),
        Line(id: 6, kind: .emoji, nick: "alice", text: "🎉", minute: 5),
    ]

    private static let baseDate: Date = {
        Calendar.current.date(bySettingHour: 14, minute: 0, second: 9, of: Date()) ?? Date()
    }()

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme[ThemeKey.chatBackground])
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(theme[ThemeKey.settingsBorder])
            )
            .animation(.snappy(duration: 0.18), value: style)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of chat messages with the current settings")
    }

    @ViewBuilder
    private var content: some View {
        switch style.layout {
        case .classic:
            VStack(alignment: .leading, spacing: max(1, style.messageSpacing / 2)) {
                ForEach(rows) { row in classicRow(row) }
            }
        case .columns:
            VStack(alignment: .leading, spacing: max(1, style.messageSpacing / 2)) {
                ForEach(rows) { row in columnsRow(row) }
            }
        case .grouped:
            VStack(alignment: .leading, spacing: style.messageSpacing) {
                ForEach(groups, id: \.first?.id) { group in groupedBlock(group) }
            }
        }
    }

    // MARK: Rows

    /// Lines after applying the join/part setting: events are shown, folded
    /// into one summary line (id -1), or dropped.
    private var rows: [Line] {
        var result: [Line] = []
        for line in Self.lines {
            guard line.isEvent else { result.append(line); continue }
            switch style.joinPart {
            case .show: result.append(line)
            case .hide: continue
            case .collapse:
                if !result.contains(where: { $0.id == -1 }) {
                    result.append(Line(id: -1, kind: .join, nick: "", text: "", minute: line.minute))
                }
            }
        }
        return result
    }

    /// Consecutive messages from one sender become a group; events stand alone.
    private var groups: [[Line]] {
        var groups: [[Line]] = []
        for line in rows {
            if !line.isEvent, let last = groups.last?.last, !last.isEvent, last.nick == line.nick,
               Double(line.minute - last.minute) * 60 <= style.groupingInterval {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups
    }

    private func classicRow(_ line: Line) -> some View {
        let time = style.showTimestamps
            ? Text(verbatim: timestamp(line) + " ").font(style.timestampFont).foregroundStyle(theme[ThemeKey.chatTimestamp])
            : Text(verbatim: "")
        let content: Text
        if line.isEvent || line.id == -1 {
            content = eventText(line)
        } else {
            let nick = Text(verbatim: "<\(line.nick)> ").font(style.nickFont).foregroundStyle(nickColor(line))
            content = Text("\(nick)\(messageText(line))")
        }
        return Text("\(time)\(content)")
            .font(style.bodyFont)
            .lineSpacing(style.lineSpacing)
            .foregroundStyle(theme[ThemeKey.chatForeground])
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
            .background(highlight(line))
    }

    private func columnsRow(_ line: Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if style.showTimestamps {
                Text(timestamp(line))
                    .font(style.timestampFont)
                    .foregroundStyle(theme[ThemeKey.chatTimestamp])
                    .fixedSize()
            }
            Group {
                if line.isEvent || line.id == -1 {
                    Text(line.id == -1 ? "" : (line.kind == .join ? "→" : "←"))
                        .foregroundStyle(theme[ThemeKey.chatEvent])
                } else {
                    Text(line.nick).font(style.nickFont).foregroundStyle(nickColor(line))
                }
            }
            .lineLimit(1)
            .frame(width: min(style.columnsNickWidth, 200), alignment: .trailing)
            Group {
                if line.isEvent || line.id == -1 {
                    eventText(line, includeArrow: false)
                } else {
                    messageText(line)
                }
            }
            .lineSpacing(style.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(style.bodyFont)
        .foregroundStyle(theme[ThemeKey.chatForeground])
        .padding(.vertical, 1)
        .background(highlight(line))
    }

    @ViewBuilder
    private func groupedBlock(_ group: [Line]) -> some View {
        let first = group[0]
        let avatarSize = max(26, style.fontSize * 2.3)
        // Without avatars, match the message list's slim time gutter.
        let metrics = GroupedMetrics(style: style)
        let textInset = style.showAvatars ? avatarSize + 10 : metrics.gutter + metrics.spacing
        if first.isEvent || first.id == -1 {
            eventText(first)
                .font(style.metaFont)
                .padding(.leading, textInset)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 10) {
                if style.showAvatars {
                    AvatarView(nick: first.nick, size: avatarSize)
                } else {
                    Color.clear.frame(width: max(0, textInset - 10), height: 1)
                }
                VStack(alignment: .leading, spacing: style.lineSpacing + 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(first.nick)
                            .font(style.nickFont)
                            .foregroundStyle(nickColor(first))
                        if style.showTimestamps {
                            Text(timestamp(first))
                                .font(style.timestampFont)
                                .foregroundStyle(theme[ThemeKey.chatTimestamp])
                        }
                    }
                    ForEach(group) { line in
                        messageText(line)
                            .font(style.bodyFont)
                            .lineSpacing(style.lineSpacing)
                            .foregroundStyle(theme[ThemeKey.chatForeground])
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(highlight(line))
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func timestamp(_ line: Line) -> String {
        let date = Self.baseDate.addingTimeInterval(Double(line.minute) * 60)
        let text = style.timestamp(date)
        return style.layout == .classic ? "[\(text)]" : text
    }

    private func nickColor(_ line: Line) -> Color {
        if line.isSelf { return theme[ThemeKey.chatSelfNick] }
        return style.colorNicks ? theme.nickColor(for: line.nick).color : theme[ThemeKey.chatForeground]
    }

    private func messageText(_ line: Line) -> Text {
        switch line.kind {
        case .mention:
            let mention = Text(verbatim: "doug").foregroundStyle(theme[ThemeKey.chatMention]).bold()
            return Text("\(mention)\(Text(verbatim: String(line.text.dropFirst(4))))")
        case .link:
            let link = Text(verbatim: "vela.chat/themes").foregroundStyle(theme[ThemeKey.chatLink]).underline()
            return Text("\(Text(verbatim: line.text))\(link)")
        case .formatted:
            if style.renderFormatting {
                let red = theme.ircColor(4)?.color ?? theme[ThemeKey.chatError]
                let bold = Text(verbatim: "Vela 0.1").bold()
                let colored = Text(verbatim: "out").foregroundStyle(red).italic()
                return Text("\(bold) is \(colored) 🚀")
            }
            return Text(verbatim: "Vela 0.1 is out 🚀")
        case .emoji:
            return Text(verbatim: line.text).font(style.font(size: style.largeEmoji ? style.fontSize * 2.2 : style.fontSize))
        default:
            return Text(verbatim: line.text)
        }
    }

    private func eventText(_ line: Line, includeArrow: Bool = true) -> Text {
        let text: String
        let key: String
        if line.id == -1 {
            text = (includeArrow ? "⇄ " : "") + "carol joined, dave quit"
            key = ThemeKey.chatEvent
        } else if line.kind == .join {
            text = (includeArrow ? "→ " : "") + "\(line.nick) joined #vela"
            key = ThemeKey.chatEventJoin
        } else {
            text = (includeArrow ? "← " : "") + "\(line.nick) quit (\(line.text))"
            key = ThemeKey.chatEventQuit
        }
        return Text(verbatim: text).foregroundStyle(theme[key])
    }

    @ViewBuilder
    private func highlight(_ line: Line) -> some View {
        if line.kind == .mention {
            HStack(spacing: 0) {
                Rectangle().fill(theme[ThemeKey.chatHighlightBorder]).frame(width: 2)
                Rectangle().fill(theme[ThemeKey.chatHighlightBackground])
            }
            .padding(.horizontal, -6)
            .padding(.vertical, -2)
        }
    }
}
