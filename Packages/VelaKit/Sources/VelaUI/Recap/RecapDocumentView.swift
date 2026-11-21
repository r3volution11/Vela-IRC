// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// Type sizes for a Recap, from the chat text size, so ⌘+ and ⌘− (and
/// larger text in Settings) make the document bigger too.
struct RecapTypography {
    let base: Double

    init(_ style: ChatStyle) {
        base = max(11, style.fontSize)
    }

    var body: Font { .system(size: base + 1) }
    var bodyLineSpacing: Double { (base + 1) * 0.32 }
    var title: Font { .system(size: (base * 1.85).rounded(), weight: .bold) }
    var heading: Font { .system(size: base + 5, weight: .semibold) }
    var subheading: Font { .system(size: base + 2, weight: .semibold) }
    var meta: Font { .system(size: max(10, base - 1)) }
    var metaStrong: Font { .system(size: max(10, base - 1), weight: .semibold) }
    var small: Font { .system(size: max(9.5, base - 2)) }
}

/// The document: the header (what, where, when, who), then, for a
/// summary, the overview, topics, what's for you, decisions and
/// follow-ups and the links shared, filling in as they're written; or the
/// log. A readable column, centered, drawn lazily.
struct RecapDocumentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let session: RecapSession
    let title: String

    static let columnWidth: CGFloat = 680

    var body: some View {
        let type = RecapTypography(style)
        let format = RecapFormat()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                RecapHeaderView(session: session, title: title, format: format)
                    .padding(.bottom, 18)
                switch session.phase {
                case .gathering:
                    RecapStatusLine(text: "Reading messages…")
                case .needsSpan:
                    RecapSpanPrompt(session: session)
                case .empty:
                    RecapEmptyView(session: session)
                case .ready:
                    if session.scope.output == .log, let input = session.input {
                        RecapLogView(input: input, format: format)
                    } else {
                        RecapSummaryView(session: session, format: format)
                    }
                }
            }
            .frame(maxWidth: Self.columnWidth, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 28)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
            .environment(\.recapTypography, type)
        }
        .scrollIndicators(.automatic)
        .themedScrollers()
        .background(theme[ThemeKey.chatBackground])
    }
}

extension EnvironmentValues {
    @Entry var recapTypography = RecapTypography(ChatStyle())
}

// MARK: - Header

private struct RecapHeaderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.recapTypography) private var type
    let session: RecapSession
    let title: String
    let format: RecapFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(type.title)
                .foregroundStyle(theme[ThemeKey.chatForeground])
                .accessibilityAddTraits(.isHeader)
            Text(RecapActions.subtitle(session.scope, input: session.input, speakers: session.findings.speakers.count, app: app, format: format))
                .font(type.meta)
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
            if session.phase == .ready, !session.findings.speakers.isEmpty {
                Text(peopleLine)
                    .font(type.meta)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("People: \(session.findings.speakers.map(\.nick).joined(separator: ", "))")
            }
            if let input = session.input, session.phase != .gathering {
                ForEach(RecapActions.notes(for: input, output: session.scope.output, format: format), id: \.self) { note in
                    RecapNoteCallout(systemImage: "info.circle", text: note)
                }
            }
        }
        .textSelection(.enabled)
    }

    /// The people who spoke, most first, each in their nick color.
    private var peopleLine: AttributedString {
        let speakers = session.findings.speakers
        let shown = speakers.prefix(10)
        var line = AttributedString()
        for (index, speaker) in shown.enumerated() {
            if index > 0 { line += plain(index == shown.count - 1 && speakers.count == shown.count ? " and " : ", ") }
            var nick = AttributedString(speaker.nick)
            nick.foregroundColor = nickColor(speaker.nick)
            nick.font = type.metaStrong
            line += nick
        }
        if speakers.count > shown.count { line += plain(" and \(speakers.count - shown.count) others") }
        return line
    }

    private func plain(_ text: String) -> AttributedString {
        var part = AttributedString(text)
        part.foregroundColor = theme[ThemeKey.chatSecondaryForeground]
        return part
    }

    private func nickColor(_ nick: String) -> Color {
        let buffer = session.input?.conversations.first.flatMap { app.lookup($0.id)?.buffer }
        return theme.nickDisplayColor(nick, isSelf: false, colorNicks: style.colorNicks, in: buffer)
    }
}

/// A note in a soft box: what's missing, why there's no summary.
struct RecapNoteCallout<Actions: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    let systemImage: String
    let text: String
    var detail: String?
    @ViewBuilder var actions: () -> Actions

    init(systemImage: String, text: String, detail: String? = nil, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.systemImage = systemImage
        self.text = text
        self.detail = detail
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: systemImage)
                .font(type.metaStrong)
                .foregroundStyle(theme[ThemeKey.accentText])
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(type.meta)
                    .foregroundStyle(theme[ThemeKey.chatForeground])
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(type.small)
                        .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme[ThemeKey.embedBackground]))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// A spinner and what's happening.
struct RecapStatusLine: View {
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    let text: String
    var fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(text)
                    .font(type.meta)
                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                    .contentTransition(.numericText())
            }
            if let fraction {
                ProgressView(value: min(1, max(0, fraction)))
                    .progressViewStyle(.linear)
                    .tint(theme[ThemeKey.accent])
                    .frame(maxWidth: 320)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Nothing to read

/// Nothing unread: how far back should it go?
private struct RecapSpanPrompt: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    let session: RecapSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing is unread in \(RecapActions.placeName(session.scope.place, app: app))\(session.scope.person.map { " from or about \($0)" } ?? "").")
                .font(type.subheading)
                .foregroundStyle(theme[ThemeKey.chatForeground])
            Text("How far back should the Recap go?")
                .font(type.body)
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
            RecapFlow(spacing: 8) {
                ForEach(RecapScope.Span.quickPicks, id: \.self) { span in
                    Button(span == .today ? "Today" : RecapScope.Span.durationTitle(span)) { choose(span) }
                        .buttonStyle(ThemedButtonStyle())
                }
            }
            RecapSpanField(initial: .last(minutes: 120)) { choose($0) }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme[ThemeKey.embedBackground]))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1))
    }

    private func choose(_ span: RecapScope.Span) {
        var scope = session.scope
        scope.span = span
        session.update(scope)
    }
}

extension RecapScope.Span {
    /// "30 minutes", "1 hour", "1 day", "1 week": a quick pick's button.
    static func durationTitle(_ span: RecapScope.Span) -> String {
        switch span {
        case .sinceUnread: "Since your first unread"
        case .today: "Today"
        case .last(let minutes): durationTitle(minutes: minutes, singularArticle: true)
        }
    }
}

private struct RecapEmptyView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    let session: RecapSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(type.subheading)
                .foregroundStyle(theme[ThemeKey.chatForeground])
            Text("Try a longer span with When, or a wider one with Where.")
                .font(type.body)
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
        }
    }

    private var message: String {
        let place = RecapActions.placeName(session.scope.place, app: app)
        let span = session.scope.span.title.lowercased()
        if let person = session.scope.person { return "Nothing from or about \(person) in \(place), \(span)." }
        return "No messages in \(place), \(span)."
    }
}

/// Lays its children out in rows that wrap.
struct RecapFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
