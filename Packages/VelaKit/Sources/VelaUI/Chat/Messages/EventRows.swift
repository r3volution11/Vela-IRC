// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

// MARK: Event rows

/// A join/part/quit/nick/mode/topic/kick/invite line or a server message:
/// compact, dimmed, with an SF Symbol in the layout's nick/avatar column.
struct EventRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(MessageListController.self) private var controller
    let line: ChatLine

    var body: some View {
        EventRowLayout(time: line.time, symbol: line.kind.eventSymbol, symbolColorKey: line.kind.eventSymbolColorKey) {
            LinkPointerText(eventText) { text in
                text
                    .font(line.kind == .motd ? style.monospaceFont(size: max(10, style.fontSize - 1)) : style.font(size: max(10, style.fontSize - 1)))
                    .foregroundStyle(theme[line.kind.eventTextColorKey])
            }
            .lineSpacing(style.lineSpacing)
            .tint(theme[ThemeKey.chatLink])
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.time.formatted(date: .omitted, time: .shortened)), \(IRCFormatting.strip(line.text))")
    }

    /// Membership events stay plain (no link-colored channel names); other
    /// events keep formatting and clickable links. The leading nick is bold
    /// and a `(user@host)` is dimmed.
    private var eventText: AttributedString {
        var text: AttributedString
        if line.kind.isMembershipEvent {
            text = AttributedString(IRCFormatting.strip(line.text))
        } else {
            text = controller.textCache.rendered(line).attributed
        }
        if let nick = line.nick, text.characters.starts(with: nick) {
            let end = text.characters.index(text.startIndex, offsetBy: nick.count)
            text[text.startIndex..<end].inlinePresentationIntent = .stronglyEmphasized
        }
        if let userHost = line.userHost, let range = text.range(of: "(\(userHost))") {
            text[range].foregroundColor = theme[ThemeKey.chatTimestamp]
        }
        return text
    }
}

/// Positions an event's time, symbol and text to match the active layout.
struct EventRowLayout<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let time: Date
    let symbol: String
    let symbolColorKey: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            switch style.layout {
            case .classic: classic
            case .grouped: grouped
            case .columns: columns
            }
        }
        .padding(.leading, style.layout == .grouped ? GroupedMetrics(style: style).leading : style.rowHorizontalPadding)
        .padding(.trailing, style.rowHorizontalPadding)
        .padding(.vertical, style.layout == .grouped ? 3 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if style.layout == .columns { ColumnsSeparator() }
        }
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: max(9, style.fontSize - 3), weight: .semibold))
            .foregroundStyle(theme[symbolColorKey])
            .accessibilityHidden(true)
    }

    private var classic: some View {
        let timeWidth = TimestampMetrics.columnWidth(style: style, bracketed: true)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if style.showTimestamps {
                Text("[\(style.timestamp(time))]")
                    .font(style.timestampFont)
                    .foregroundStyle(theme[ThemeKey.chatTimestamp])
                    .frame(width: timeWidth, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                icon
                content()
            }
        }
    }

    /// The icon in the gutter (centered under avatars, otherwise against the
    /// text column), the text in the message column, then the time.
    private var grouped: some View {
        let metrics = GroupedMetrics(style: style)
        return HStack(alignment: .firstTextBaseline, spacing: metrics.spacing) {
            icon.frame(width: metrics.gutter, alignment: style.showAvatars ? .center : .trailing)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                content()
                if style.showTimestamps {
                    Text(style.timestamp(time))
                        .font(style.gutterTimestampFont)
                        .foregroundStyle(theme[ThemeKey.chatTimestamp])
                        .fixedSize()
                }
            }
        }
    }

    private var columns: some View {
        let metrics = ColumnsMetrics(style: style)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            if metrics.timeWidth > 0 {
                Text(style.timestamp(time))
                    .font(style.timestampFont)
                    .foregroundStyle(theme[ThemeKey.chatTimestamp])
                    .frame(width: metrics.timeWidth, alignment: .leading)
                    .padding(.trailing, metrics.timeGap)
            }
            icon
                .frame(width: metrics.nickWidth, alignment: .trailing)
                .padding(.trailing, metrics.textX - metrics.nickX - metrics.nickWidth)
            content()
        }
    }
}

// MARK: Membership runs

/// "alice, bob and 3 others joined · carol left", expandable to the
/// individual events.
struct MembershipRunRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(MessageListController.self) private var controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let run: MembershipRun

    @State private var hovering = false

    var body: some View {
        let expanded = controller.expandedRuns.contains(run.id)
        let summary = run.summary
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { controller.toggleRun(run.id) }
            } label: {
                EventRowLayout(time: run.lines[0].time, symbol: "person.2", symbolColorKey: ThemeKey.chatEvent) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(summary)
                            .font(style.font(size: max(10, style.fontSize - 1)))
                            .foregroundStyle(theme[ThemeKey.chatEvent])
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right")
                            .font(.system(size: max(8, style.fontSize - 4), weight: .bold))
                            .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .opacity(hovering || expanded ? 1 : 0.6)
                    }
                }
                .background(hovering ? theme[ThemeKey.chatHoverBackground] : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(expanded ? "Hide \(run.lines.count) events" : "Show \(run.lines.count) events")
            .accessibilityLabel(summary)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the individual events" : "Shows the \(run.lines.count) individual events")

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(run.lines) { line in
                        EventRow(line: line)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

// MARK: Dividers

struct DayDividerRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let date: Date

    var body: some View {
        let label = DayLabel.text(for: date)
        HStack(spacing: 12) {
            rule
            Text(label)
                .font(style.font(size: max(10, style.fontSize - 2), weight: .semibold))
                .foregroundStyle(theme[ThemeKey.chatDayDividerForeground])
                .fixedSize()
            rule
        }
        .padding(.horizontal, style.rowHorizontalPadding)
        .padding(.top, style.layout == .grouped ? 16 : 10)
        .padding(.bottom, style.layout == .grouped ? 4 : 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isHeader)
    }

    private var rule: some View {
        Rectangle()
            .fill(theme[ThemeKey.chatDayDivider])
            .frame(height: 1)
    }
}

/// The "New" line above the first unread message, with "Catch me up" at
/// its end when a summary is on offer (`CatchUpMarkerButton`).
struct UnreadMarkerRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(theme[ThemeKey.chatUnreadMarker])
                    .frame(height: 1)
                Text("New")
                    .font(.system(size: max(9, style.fontSize - 3), weight: .bold))
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(theme[ThemeKey.chatUnreadMarker])
                    .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("New messages")
            .accessibilityAddTraits(.isHeader)
            CatchUpMarkerButton()
        }
        .padding(.horizontal, style.rowHorizontalPadding)
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }
}

// MARK: Event styling

extension ChatLineKind {
    var eventSymbol: String {
        switch self {
        case .join: "arrow.right"
        case .part: "arrow.left"
        case .quit: "arrow.left.to.line"
        case .kick: "xmark"
        case .nick: "pencil"
        case .mode: "shield.lefthalf.filled"
        case .topic: "text.quote"
        case .invite: "envelope"
        case .error: "exclamationmark.triangle.fill"
        case .motd: "text.alignleft"
        case .ctcp: "bolt.horizontal"
        default: "info.circle"
        }
    }

    var eventSymbolColorKey: String {
        switch self {
        case .join: ThemeKey.chatEventJoin
        case .part, .kick: ThemeKey.chatEventPart
        case .quit: ThemeKey.chatEventQuit
        case .nick: ThemeKey.chatEventNick
        case .mode: ThemeKey.chatEventMode
        case .topic: ThemeKey.chatEventTopic
        case .error: ThemeKey.chatError
        case .info, .motd, .ctcp: ThemeKey.chatServerMessage
        default: ThemeKey.chatEvent
        }
    }

    var eventTextColorKey: String {
        switch self {
        case .error: ThemeKey.chatError
        case .info, .motd, .ctcp: ThemeKey.chatServerMessage
        default: ThemeKey.chatEvent
        }
    }
}
