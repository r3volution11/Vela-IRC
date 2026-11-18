// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// One display item. Equatable so unchanged rows skip body evaluation when
/// the list updates.
struct DisplayItemRow: View, Equatable {
    let item: DisplayItem

    var body: some View {
        switch item {
        case .dayDivider(let date, _):
            DayDividerRow(date: date)
        case .unreadMarker:
            UnreadMarkerRow()
        case .catchUpCard:
            CatchUpCardRow()
        case .line(let lineItem):
            if lineItem.line.kind.isConversation {
                MessageRow(item: lineItem)
            } else {
                EventRow(line: lineItem.line)
            }
        case .membershipRun(let run):
            MembershipRunRow(run: run)
        }
    }
}

// MARK: Message row

/// A message, action or notice in any layout, with hover, highlight,
/// context menu and the hover toolbar.
struct MessageRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.effectiveVibrancy) private var vibrancy
    @Environment(\.chatStyle) private var style
    @Environment(MessageListController.self) private var controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: LineItem

    @State private var isHovered = false
    @State private var isPickerOpen = false

    var body: some View {
        let line = item.line
        let rendered = line.isRedacted ? nil : controller.textCache.rendered(line)
        let links = rendered?.links ?? []

        content(rendered)
            .padding(.leading, leadingPadding)
            .padding(.trailing, style.rowHorizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { background(for: line) }
            .overlay(alignment: .leading) {
                if line.isHighlight {
                    Rectangle()
                        .fill(theme[ThemeKey.chatHighlightBorder])
                        .frame(width: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isHovered || isPickerOpen {
                    MessageHoverToolbar(line: line, links: links, isPickerOpen: $isPickerOpen)
                        .padding(.trailing, 14 + toolbarTimeInset)
                        .offset(y: -14)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.08)) { isHovered = hovering }
            }
            // Right-clicking the message's text opens it too.
            .selectableTextContextMenu {
                MessageMenuItems(line: line, links: links)
            }
            .autoTranslation(for: line)
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func content(_ rendered: RenderedText?) -> some View {
        switch style.layout {
        case .classic:
            ClassicMessageContent(item: item, rendered: rendered, isHovered: isHovered)
        case .grouped:
            GroupedMessageContent(item: item, rendered: rendered, isHovered: isHovered)
        case .columns:
            ColumnsMessageContent(item: item, rendered: rendered, isHovered: isHovered)
        }
    }

    private var leadingPadding: CGFloat {
        style.layout == .grouped ? GroupedMetrics(style: style).leading : style.rowHorizontalPadding
    }

    private var topPadding: CGFloat {
        let base: CGFloat = switch style.layout {
        case .grouped: item.isContinuation ? 1 : style.messageSpacing + 5
        case .classic, .columns: item.isContinuation ? 1 : max(1, style.messageSpacing / 2) + 1
        }
        return base + (timePlacement.slot == .above ? TimestampLine.rowInset : 0)
    }

    private var bottomPadding: CGFloat { 1 + (timePlacement.slot == .below ? TimestampLine.rowInset : 0) }

    /// Where the row's time goes, hovered or not (for the row's padding
    /// and the toolbar, which only care about the place).
    private var timePlacement: TimestampPlacement {
        TimestampPlacement.message(
            layout: style.layout,
            position: style.timestampPosition,
            isContinuation: item.isContinuation,
            isHovered: true,
            showTimestamps: style.showTimestamps
        )
    }

    /// With times at the right edge, the hover toolbar sits just left of
    /// them, so hovering a message shows its time rather than covering it.
    private var toolbarTimeInset: CGFloat {
        timePlacement.slot == .trailingColumn ? TimestampMetrics.toolbarInset(style: style) : 0
    }

    @ViewBuilder
    private func background(for line: ChatLine) -> some View {
        ZStack {
            // Full-width row colors are part of the conversation's
            // surface: on a material they tint it too, rather than
            // standing out as opaque bands.
            if line.isHighlight {
                theme.surfaceColor(ThemeKey.chatHighlightBackground, on: .content, vibrancy: vibrancy).color
            } else if line.isSelf, theme.color(ThemeKey.chatSelfMessageBackground) != theme.color(ThemeKey.chatBackground) {
                // (The default, chat.background, would tint it twice.)
                theme.surfaceColor(ThemeKey.chatSelfMessageBackground, on: .content, vibrancy: vibrancy).color
            }
            if isHovered {
                theme[ThemeKey.chatHoverBackground]
            }
            if controller.flashedLineID == line.id {
                theme[ThemeKey.chatSelectionBackground]
            }
            if style.layout == .columns {
                ColumnsSeparator()
            }
        }
    }
}

// MARK: Layouts

/// `[12:01] <nick> text`, wrapped lines hanging after the timestamp column.
/// `chat.timestampPosition.classic` can move the time to the right edge or
/// onto its own line above or below (without brackets there).
struct ClassicMessageContent: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(MessageListController.self) private var controller
    let item: LineItem
    let rendered: RenderedText?
    let isHovered: Bool

    var body: some View {
        let line = item.line
        let timeWidth = TimestampMetrics.columnWidth(style: style, bracketed: true)
        let placement = TimestampPlacement.message(
            layout: .classic,
            position: style.classicTimestampPosition,
            isContinuation: item.isContinuation,
            isHovered: isHovered,
            showTimestamps: style.showTimestamps
        )
        VStack(alignment: .leading, spacing: 2) {
            if let reply = item.reply {
                ReplyQuoteView(reply: reply)
                    .padding(.leading, placement.slot == .leadingColumn ? timeWidth + 8 : 0)
            }
            if placement.slot == .above {
                TimestampLine(time: line.time, edge: .top)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if placement.slot == .leadingColumn {
                    Text("[\(style.timestamp(line.time))]")
                        .font(style.timestampFont)
                        .foregroundStyle(theme[ThemeKey.chatTimestamp])
                        .frame(width: timeWidth, alignment: .leading)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    MessageBodyText(line: line, rendered: rendered, prefix: prefix(for: line))
                        .messageAccessibility(line: line, rendered: rendered)
                    MessageTranslationView(line: line)
                    if placement.slot == .below {
                        TimestampLine(time: line.time, edge: .bottom)
                    }
                    MessageExtras(line: line, bufferID: controller.buffer.id, isHovered: isHovered)
                }
                .trailingTimestamp(line.time, placement)
            }
        }
    }

    private func prefix(for line: ChatLine) -> AttributedString {
        let nick = line.nick ?? ""
        var nickRun = AttributedString(nick)
        nickRun.font = style.nickFont
        nickRun.foregroundColor = theme.nickDisplayColor(line.nick, isSelf: line.isSelf, colorNicks: style.colorNicks, in: controller.buffer)

        func punctuation(_ text: String, _ key: String) -> AttributedString {
            var run = AttributedString(text)
            run.font = style.bodyFont
            run.foregroundColor = theme[key]
            return run
        }

        switch line.kind {
        case .action:
            return punctuation("* ", ThemeKey.chatAction) + nickRun + punctuation(" ", ThemeKey.chatAction)
        case .notice:
            return punctuation("-", ThemeKey.chatNotice) + nickRun + punctuation("- ", ThemeKey.chatNotice)
        default:
            return punctuation("<", ThemeKey.chatSecondaryForeground) + nickRun + punctuation("> ", ThemeKey.chatSecondaryForeground)
        }
    }
}

/// Slack/Discord style: a header (name and time, plus the avatar when
/// enabled) for the first message of a group, bare text for continuations
/// with their time in the gutter on hover.
///
/// `chat.timestampPosition.grouped` moves the first message's time into the
/// gutter (Left), to the right edge (Right, where continuations then show
/// theirs on hover too) or below the message (Bottom).
struct GroupedMessageContent: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(MessageListController.self) private var controller
    let item: LineItem
    let rendered: RenderedText?
    let isHovered: Bool

    var body: some View {
        let line = item.line
        let metrics = GroupedMetrics(style: style)
        let placement = TimestampPlacement.message(
            layout: .grouped,
            position: style.groupedTimestampPosition,
            isContinuation: item.isContinuation,
            isHovered: isHovered,
            showTimestamps: style.showTimestamps
        )
        VStack(alignment: .leading, spacing: 4) {
            if let reply = item.reply {
                if style.showAvatars {
                    // A connector curls from the avatar up to the quote.
                    ReplyQuoteView(reply: reply, showsArrow: false)
                        .padding(.leading, metrics.gutter + metrics.spacing)
                        .background(alignment: .leading) {
                            ReplyConnector(overshoot: 7)
                                .stroke(theme[ThemeKey.replyQuoteBar], style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                                .frame(width: metrics.gutter)
                                .accessibilityHidden(true)
                        }
                } else {
                    ReplyQuoteView(reply: reply)
                        .padding(.leading, metrics.textX - metrics.leading)
                }
            }
            HStack(alignment: rowAlignment(placement), spacing: metrics.spacing) {
                gutterView(for: line, width: metrics.gutter, placement: placement)
                VStack(alignment: .leading, spacing: 2) {
                    VStack(alignment: .leading, spacing: 1) {
                        if !item.isContinuation {
                            header(for: line, showsTime: placement.slot == .header)
                        }
                        MessageBodyText(line: line, rendered: rendered)
                    }
                    .messageAccessibility(line: line, rendered: rendered)
                    MessageTranslationView(line: line)
                    if placement.slot == .below {
                        TimestampLine(time: line.time, edge: .bottom)
                    }
                    MessageExtras(line: line, bufferID: controller.buffer.id, isHovered: isHovered)
                }
                .trailingTimestamp(line.time, placement)
            }
        }
    }

    /// Continuations line their hover time up with the text. A first
    /// message's time in the margin (Left, without avatars) lines up with
    /// the name; otherwise the avatar hangs from the top.
    private func rowAlignment(_ placement: TimestampPlacement) -> VerticalAlignment {
        if item.isContinuation { return .firstTextBaseline }
        return placement.slot == .gutter && !style.showAvatars ? .firstTextBaseline : .top
    }

    @ViewBuilder
    private func gutterView(for line: ChatLine, width: CGFloat, placement: TimestampPlacement) -> some View {
        if item.isContinuation {
            // The time on hover, right-aligned against the text column.
            // Always laid out (invisible otherwise): it gives the gutter the
            // text's baseline.
            Text(style.timestamp(line.time))
                .font(style.gutterTimestampFont)
                .foregroundStyle(theme[ThemeKey.chatTimestamp])
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: width, alignment: .trailing)
                .opacity(placement.slot == .gutter && placement.isVisible ? 1 : 0)
                .accessibilityHidden(true)
        } else if style.showAvatars, placement.slot == .gutter {
            // Left with avatars: the time under the avatar, which then
            // sets the row's height so the time never runs into the next.
            VStack(spacing: 3) {
                AvatarView(nick: line.nick ?? "?", size: width, buffer: controller.buffer)
                    .nickContextMenu(line.nick, userHost: line.userHost)
                    .padding(.top, 1)
                avatarTime(line.time, width: width)
            }
            .frame(width: width)
        } else if placement.slot == .gutter {
            // Left: the time in the margin, where hover times go.
            Text(style.timestamp(line.time))
                .font(style.gutterTimestampFont)
                .foregroundStyle(theme[ThemeKey.chatTimestamp])
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: width, alignment: .trailing)
                .accessibilityHidden(true)
        } else if style.showAvatars {
            // The avatar hangs from the top without setting the row height,
            // so one-line groups are as tall as their text.
            Color.clear
                .frame(width: width, height: 1)
                .overlay(alignment: .top) {
                    AvatarView(nick: line.nick ?? "?", size: width, buffer: controller.buffer)
                        .nickContextMenu(line.nick, userHost: line.userHost)
                        .padding(.top, 1)
                }
        } else {
            Color.clear.frame(width: width, height: 1)
        }
    }

    /// A first message's time under its avatar (Left): centered when it
    /// fits, otherwise flush with the avatar's right edge, running into the
    /// row's leading inset rather than toward the text, and shrinking only
    /// if even that's too narrow (long 12-hour times with seconds).
    private func avatarTime(_ time: Date, width: CGFloat) -> some View {
        let text = Text(style.timestamp(time))
            .font(style.gutterTimestampFont)
            .foregroundStyle(theme[ThemeKey.chatTimestamp])
            .lineLimit(1)
        return ViewThatFits(in: .horizontal) {
            text.fixedSize()
            text
                .minimumScaleFactor(0.7)
                .frame(width: width + style.rowHorizontalPadding - 4, alignment: .trailing)
                .frame(width: width, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }

    private func header(for line: ChatLine, showsTime: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(line.nick ?? "")
                .font(style.nickFont)
                .foregroundStyle(theme.nickDisplayColor(line.nick, isSelf: line.isSelf, colorNicks: style.colorNicks, in: controller.buffer))
                .lineLimit(1)
                .nickContextMenu(line.nick, userHost: line.userHost)
            if line.kind == .notice {
                Text("notice")
                    .font(style.font(size: max(9, style.fontSize - 4), weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.chatNotice])
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(theme[ThemeKey.chatNotice].opacity(0.5), lineWidth: 1)
                    )
            }
            if showsTime {
                Text(style.timestamp(line.time))
                    .font(style.timestampFont)
                    .foregroundStyle(theme[ThemeKey.chatTimestamp])
            }
        }
        .accessibilityHidden(true)
    }
}

/// irssi/weechat style: time, right-aligned nick, then text, in columns.
/// `chat.timestampPosition.columns` can move the time column to the right
/// edge, or put the time on a small line above or below the text.
struct ColumnsMessageContent: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(MessageListController.self) private var controller
    let item: LineItem
    let rendered: RenderedText?
    let isHovered: Bool

    var body: some View {
        let line = item.line
        let metrics = ColumnsMetrics(style: style)
        let placement = TimestampPlacement.message(
            layout: .columns,
            position: style.columnsTimestampPosition,
            isContinuation: item.isContinuation,
            isHovered: isHovered,
            showTimestamps: style.showTimestamps
        )
        VStack(alignment: .leading, spacing: 2) {
            if let reply = item.reply {
                ReplyQuoteView(reply: reply)
                    .padding(.leading, metrics.textX)
            }
            if placement.slot == .above {
                // In the text column, so the nick stays level with the text.
                TimestampLine(time: line.time, edge: .top)
                    .padding(.leading, metrics.textX)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if metrics.timeWidth > 0 {
                    Text(style.timestamp(line.time))
                        .font(style.timestampFont)
                        .foregroundStyle(theme[ThemeKey.chatTimestamp])
                        .frame(width: metrics.timeWidth, alignment: .leading)
                        .padding(.trailing, metrics.timeGap)
                        .accessibilityHidden(true)
                }
                nickCell(for: line)
                    .nickContextMenu(line.nick, userHost: line.userHost)
                    .frame(width: metrics.nickWidth, alignment: .trailing)
                    .padding(.trailing, metrics.textX - metrics.nickX - metrics.nickWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    MessageBodyText(line: line, rendered: rendered, prefix: actionPrefix(for: line))
                        .messageAccessibility(line: line, rendered: rendered)
                    MessageTranslationView(line: line)
                    if placement.slot == .below {
                        TimestampLine(time: line.time, edge: .bottom)
                    }
                    MessageExtras(line: line, bufferID: controller.buffer.id, isHovered: isHovered)
                }
                .trailingTimestamp(line.time, placement)
            }
        }
    }

    @ViewBuilder
    private func nickCell(for line: ChatLine) -> some View {
        let nick = line.nick ?? ""
        switch line.kind {
        case .action:
            Text("*")
                .font(style.nickFont)
                .foregroundStyle(theme[ThemeKey.chatAction])
        case .notice:
            Text("-\(nick)-")
                .font(style.nickFont)
                .foregroundStyle(theme[ThemeKey.chatNotice])
                .lineLimit(1)
                .truncationMode(.tail)
        default:
            Text(nick)
                .font(style.nickFont)
                .foregroundStyle(theme.nickDisplayColor(line.nick, isSelf: line.isSelf, colorNicks: style.colorNicks, in: controller.buffer))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Actions read "nick waves" in the text column.
    private func actionPrefix(for line: ChatLine) -> AttributedString? {
        guard line.kind == .action, let nick = line.nick else { return nil }
        var run = AttributedString(nick + " ")
        run.font = style.nickFont
        run.foregroundColor = theme.nickDisplayColor(nick, isSelf: line.isSelf, colorNicks: style.colorNicks, in: controller.buffer)
        return run
    }
}

/// Column positions for the columns layout, measured from the row's content edge.
struct ColumnsMetrics {
    /// The time column before the nicks; 0 unless times are on the left.
    let timeWidth: CGFloat
    let timeGap: CGFloat = 10
    let nickWidth: CGFloat
    let separatorGap: CGFloat = 9

    @MainActor
    init(style: ChatStyle) {
        let leftTimes = style.showTimestamps && style.columnsTimestampPosition == .left
        timeWidth = leftTimes ? TimestampMetrics.columnWidth(style: style, bracketed: false) : 0
        nickWidth = max(40, style.columnsNickWidth)
    }

    var nickX: CGFloat { timeWidth > 0 ? timeWidth + timeGap : 0 }
    var separatorX: CGFloat { nickX + nickWidth + separatorGap }
    var textX: CGFloat { separatorX + 1 + separatorGap }
}

/// The hairline between the nick and text columns. Drawn full-height in
/// each row's background so consecutive rows form one continuous rule.
struct ColumnsSeparator: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style

    var body: some View {
        let metrics = ColumnsMetrics(style: style)
        HStack(spacing: 0) {
            Rectangle()
                .fill(theme[ThemeKey.chatDayDivider])
                .frame(width: 1)
                .padding(.leading, style.rowHorizontalPadding + metrics.separatorX)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

// MARK: Shared pieces

/// The message text itself (or "Message deleted"), with an optional prefix
/// such as `<nick> ` in the classic layout.
struct MessageBodyText: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(MessageListController.self) private var controller
    let line: ChatLine
    let rendered: RenderedText?
    var prefix: AttributedString?

    var body: some View {
        if let rendered {
            let large = style.largeEmoji && rendered.isEmojiOnly
            // The pointing hand over links, the I-beam elsewhere.
            LinkPointerText(compose(rendered.attributed)) { text in
                text
                    .font(large ? style.font(size: (style.fontSize * 2.2).rounded()) : style.bodyFont)
                    .italic(line.kind == .action)
                    .foregroundStyle(theme[baseColorKey])
            }
            .environment(\.wordContextMenu, nickMenu)
            .lineSpacing(style.lineSpacing)
            .tint(theme[ThemeKey.chatLink])
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, large ? 2 : 0)
        } else {
            Text(compose(deletedText))
                .font(style.bodyFont)
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Right-clicking a nick in the text: the author's `<nick>` in the
    /// prefix, or anyone in the channel, opens their user menu.
    private var nickMenu: WordContextMenu {
        let actions = UserMenuActions(app: app, uiState: uiState, session: controller.session, buffer: controller.buffer)
        let line = line
        let prefixLength = prefix.map { String($0.characters).utf16.count } ?? 0
        return WordContextMenu { word, range in
            actions.menu(forWord: word, range: range, in: line, prefixLength: prefixLength).map(actions.nsMenu)
        }
    }

    private var deletedText: AttributedString {
        var deleted = AttributedString(String(localized: "Message deleted"))
        deleted.inlinePresentationIntent = .emphasized
        deleted.foregroundColor = theme[ThemeKey.chatSecondaryForeground]
        return deleted
    }

    private func compose(_ text: AttributedString) -> AttributedString {
        guard let prefix else { return text }
        return prefix + text
    }

    private var baseColorKey: String {
        switch line.kind {
        case .action: ThemeKey.chatAction
        case .notice: ThemeKey.chatNotice
        default: ThemeKey.chatForeground
        }
    }
}

/// Inline media and reactions under a message.
struct MessageExtras: View {
    let line: ChatLine
    let bufferID: BufferID
    let isHovered: Bool

    var body: some View {
        if !line.isRedacted, line.kind.isConversation {
            MessageEmbedsView(line: line, bufferID: bufferID)
        }
        if line.msgid != nil, !line.isRedacted {
            ReactionBar(line: line, isRowHovered: isHovered)
        }
    }
}

// MARK: Accessibility

extension View {
    /// Makes the text block one VoiceOver element reading "nick, time,
    /// message", with the hover-toolbar actions as custom actions.
    func messageAccessibility(line: ChatLine, rendered: RenderedText?) -> some View {
        modifier(MessageAccessibilityModifier(line: line, rendered: rendered))
    }
}

private struct MessageAccessibilityModifier: ViewModifier {
    @Environment(MessageListController.self) private var controller
    @Environment(UIState.self) private var uiState
    let line: ChatLine
    let rendered: RenderedText?

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.label(for: line, rendered: rendered))
            .accessibilityActions {
                if controller.canReply(to: line) {
                    Button("Reply") { controller.reply(to: line, uiState: uiState) }
                }
                if !line.isRedacted {
                    Button("Copy Text") { controller.copyText(of: line) }
                }
                TranslationAccessibilityActions(line: line)
                if let rendered {
                    LinkAccessibilityActions(text: rendered.attributed)
                }
                if controller.canDelete(line) {
                    Button("Delete Message") { controller.confirmDelete(line) }
                }
            }
    }

    static func label(for line: ChatLine, rendered: RenderedText?) -> String {
        let nick = line.nick ?? ""
        let time = line.time.formatted(date: .omitted, time: .shortened)
        guard let rendered else { return "\(nick), \(time), message deleted" }
        var parts = [nick, time]
        switch line.kind {
        case .action: parts.append("\(nick) \(rendered.plain)")
        case .notice: parts.append("notice: \(rendered.plain)")
        default: parts.append(rendered.plain)
        }
        if line.isHighlight { parts.append("mentions you") }
        return parts.joined(separator: ", ")
    }
}
