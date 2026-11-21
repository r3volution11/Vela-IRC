// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// The matching messages as a readable transcript, by conversation and
/// day, in nick colors, each one a link to it in the main window. No Apple
/// Intelligence: it's there the moment the messages are read. The rows
/// are worked out once per Recap (``RecapLogRows``) and drawn lazily, so
/// a log of thousands of lines costs only what's on screen.
struct RecapLogView: View {
    let input: RecapInput
    let format: RecapFormat

    @State private var rows: RecapLogRows?

    var body: some View {
        Group {
            if let rows, rows.end == input.end {
                ForEach(rows.rows) { row in
                    RecapLogRowView(row: row, format: format, manyNetworks: rows.manyNetworks)
                }
            } else {
                RecapStatusLine(text: "Laying out \(RecapFormat.messages(input.lineCount))…")
            }
        }
        .task(id: input.end) {
            let input = input
            let format = format
            rows = await Task.detached(priority: .userInitiated) { RecapLogRows(input, format: format) }.value
        }
    }
}

/// A log, flattened into rows: a heading for each conversation and day,
/// then its lines.
struct RecapLogRows: Sendable {
    enum Kind: Sendable {
        case conversation(name: String, network: String)
        case day(String)
        case line(RecapLine, conversation: BufferID)
    }

    struct Row: Identifiable, Sendable {
        let id: String
        let kind: Kind
    }

    /// When the Recap's messages were read: which reading these rows are for.
    let end: Date
    let rows: [Row]
    let manyNetworks: Bool

    nonisolated init(_ input: RecapInput, format: RecapFormat) {
        end = input.end
        manyNetworks = Set(input.conversations.map(\.networkName)).count > 1
        var rows: [Row] = []
        rows.reserveCapacity(input.lineCount + input.conversations.count * 3)
        for conversation in input.conversations {
            rows.append(Row(id: "c-\(conversation.id)", kind: .conversation(name: conversation.name, network: conversation.networkName)))
            var day: Date?
            for line in conversation.lines {
                let lineDay = format.startOfDay(line.time)
                if lineDay != day {
                    day = lineDay
                    rows.append(Row(id: "d-\(conversation.id)-\(lineDay.timeIntervalSince1970)", kind: .day(format.day(line.time))))
                }
                rows.append(Row(id: line.id.uuidString, kind: .line(line, conversation: conversation.id)))
            }
        }
        self.rows = rows
    }
}

private struct RecapLogRowView: View {
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    let row: RecapLogRows.Row
    let format: RecapFormat
    let manyNetworks: Bool

    var body: some View {
        switch row.kind {
        case .conversation(let name, let network):
            VStack(alignment: .leading, spacing: 10) {
                Rectangle()
                    .fill(theme[ThemeKey.chatSecondaryForeground].opacity(0.16))
                    .frame(height: 1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(type.heading)
                        .foregroundStyle(theme[ThemeKey.chatForeground])
                    if manyNetworks {
                        Text(network)
                            .font(type.meta)
                            .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, 22)
            .padding(.bottom, 4)
        case .day(let title):
            Text(title)
                .font(type.metaStrong)
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                .textCase(.uppercase)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
        case .line(let line, let conversation):
            RecapLogLine(line: line, conversation: conversation, format: format)
        }
    }
}

/// One message: its time, its nick in color and its text. Clicking it
/// shows it in the main window.
private struct RecapLogLine: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.recapTypography) private var type
    let line: RecapLine
    let conversation: BufferID
    let format: RecapFormat

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(format.clock(line.time))
                .font(type.meta.monospacedDigit())
                .foregroundStyle(theme[ThemeKey.chatTimestamp])
                .frame(width: type.base * 5.2, alignment: .trailing)
            Text(text)
                .font(type.body)
                .lineSpacing(type.bodyLineSpacing * 0.6)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if hovering {
                Button(action: jump) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: max(8, type.base - 3), weight: .bold))
                        .foregroundStyle(theme[ThemeKey.chatLink])
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show in \(app.lookup(conversation)?.buffer.name ?? "its conversation")")
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2.5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hovering ? theme[ThemeKey.chatHoverBackground] : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { jump() }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Show in Conversation") { jump() }
    }

    private var text: AttributedString {
        let buffer = app.lookup(conversation)?.buffer
        var nick = AttributedString(line.nick)
        nick.foregroundColor = theme.nickDisplayColor(line.nick, isSelf: line.isSelf, colorNicks: style.colorNicks, in: buffer)
        nick.font = type.body.weight(.semibold)
        var body = AttributedString(line.text)
        body.foregroundColor = theme[line.kind == .notice ? ThemeKey.chatNotice : ThemeKey.chatForeground]
        switch line.kind {
        case .message, .notice:
            var colon = AttributedString(": ")
            colon.foregroundColor = theme[ThemeKey.chatSecondaryForeground]
            return nick + colon + body
        case .action:
            var star = AttributedString("* ")
            star.foregroundColor = theme[ThemeKey.chatAction]
            body.foregroundColor = theme[ThemeKey.chatAction]
            return star + nick + AttributedString(" ") + body
        }
    }

    private func jump() {
        RecapActions.jump(
            to: RecapReference(conversation: conversation, lineID: line.id, time: line.time),
            app: app, uiState: uiState, openWindow: openWindow
        )
    }
}
