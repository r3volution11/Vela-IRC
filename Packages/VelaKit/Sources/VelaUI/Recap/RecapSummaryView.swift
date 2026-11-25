// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// A summary Recap's sections: where the summary has got (or why there's
/// none), then Overview, Topics, For you, Decisions and follow-ups, and
/// Links shared. For you and the links are found on this Mac and show at
/// once; the rest fill in as Apple Intelligence writes them.
struct RecapSummaryView: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(UIState.self) private var uiState: UIState?
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    @Environment(\.openSettings) private var openSettings
    @Environment(\.askForAIConsent) private var askForAIConsent
    let session: RecapSession
    let format: RecapFormat

    var body: some View {
        let summary = session.summary
        // The sections are the document's lazy stack's own rows, so only
        // those on screen are laid out.
        Group {
            state
            if let summary, !summary.overview.isEmpty {
                RecapSection(title: "Overview") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(summary.overview.enumerated()), id: \.offset) { _, sentence in
                            RecapBullet(text: sentence)
                        }
                    }
                }
            }
            if let summary, !summary.topics.isEmpty {
                RecapSection(title: summary.topicsAreProvisional ? "Topics so far" : "Topics", count: summary.topics.count) {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(summary.topics) { topic in
                            RecapTopicView(topic: topic, session: session, format: format)
                        }
                    }
                }
            }
            if !session.findings.forYou.isEmpty {
                RecapSection(title: "For you", count: session.findings.forYou.count, note: unansweredNote) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(session.findings.forYou) { item in
                            RecapForYouRow(item: item, note: summary?.notesForYou[item.id], format: format, conversationNames: names)
                        }
                    }
                }
            }
            if let summary, !summary.notes.isEmpty {
                RecapSection(title: "Decisions and follow-ups", count: summary.notes.count) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(RecapNote.Kind.allCases, id: \.self) { kind in
                            let notes = summary.notes(kind)
                            if !notes.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(RecapMarkdown.title(kind))
                                        .font(type.subheading)
                                        .foregroundStyle(theme[ThemeKey.chatForeground])
                                        .accessibilityAddTraits(.isHeader)
                                    ForEach(notes) { note in
                                        RecapNoteRow(note: note, session: session, format: format, conversationNames: names)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if !session.findings.links.isEmpty {
                RecapSection(title: "Links shared", count: session.findings.linkCount) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(session.findings.links) { group in
                            RecapLinkGroupView(group: group, format: format, conversationNames: names)
                        }
                    }
                }
            }
            if let summary, summary.isComplete || session.summaryPhase == .stopped {
                footer(summary)
            }
        }
    }

    private var names: [BufferID: String] {
        guard let input = session.input, input.conversations.count > 1 else { return [:] }
        return RecapActions.conversationNames(input)
    }

    private var unansweredNote: String? {
        let count = session.findings.unansweredCount
        return count == 0 ? nil : count == 1 ? "1 not answered" : "\(count) not answered"
    }

    // MARK: State

    @ViewBuilder
    private var state: some View {
        switch session.summaryPhase {
        case .idle:
            EmptyView()
        case .unavailable(let status):
            RecapNoteCallout(
                systemImage: "apple.intelligence",
                text: "Summaries need Apple Intelligence, or a model of your own.",
                detail: "\(status.detail) You can also add a provider such as OpenAI, Anthropic, Google Gemini or Ollama in Settings → AI Providers."
            ) {
                HStack(spacing: 8) {
                    Button("Show Log") { showLog() }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                    if let url = status.settingsURL {
                        Button("Open System Settings") { NSWorkspace.shared.open(url) }
                            .buttonStyle(ThemedButtonStyle())
                    }
                    if let uiState {
                        Button("Manage Providers…") { AIModelActions.openSettings(uiState: uiState, openSettings: openSettings) }
                            .buttonStyle(ThemedButtonStyle())
                    }
                }
            }
            .padding(.bottom, 8)
        case .estimating:
            RecapStatusLine(text: "Getting ready…")
        case .confirming(let plan):
            RecapNoteCallout(
                systemImage: "clock",
                text: estimate(plan),
                detail: Self.confirmationDetail(plan, messages: min(session.input?.lineCount ?? 0, RecapLimits.summaryLines))
            ) {
                HStack(spacing: 8) {
                    Button("Start") { session.confirm() }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                    Button("Show Log") { showLog() }
                        .buttonStyle(ThemedButtonStyle())
                }
            }
            .padding(.bottom, 8)
        case .running:
            RecapStatusLine(text: progressText, fraction: progressFraction)
                .padding(.bottom, 4)
        case .done:
            EmptyView()
        case .stopped:
            RecapNoteCallout(systemImage: "stop.circle", text: "Stopped. What was written so far is below; Regenerate starts again.")
                .padding(.bottom, 8)
        case .failed(let error) where error.needsConsent:
            RecapNoteCallout(systemImage: "hand.raised", text: error.errorDescription ?? "") {
                HStack(spacing: 8) {
                    Button("Review…") { askForAIConsent?() }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                        .accessibilityHint("Shows what would be sent, and asks to allow it")
                    if intelligence.models.isAppleAvailable {
                        Button("Use Apple Intelligence") { session.rerun(with: .automatic) }
                            .buttonStyle(ThemedButtonStyle())
                    }
                    Button("Show Log") { showLog() }
                        .buttonStyle(ThemedButtonStyle())
                }
            }
            .padding(.bottom, 8)
        case .failed(let error):
            RecapNoteCallout(
                systemImage: "exclamationmark.circle",
                text: error.errorDescription ?? "Apple Intelligence couldn't write this Recap."
            ) {
                HStack(spacing: 8) {
                    Button("Try Again") { session.regenerate() }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                    if error.providerFailure != nil, intelligence.models.isAppleAvailable {
                        Button("Try with Apple Intelligence") { session.rerun(with: .automatic) }
                            .buttonStyle(ThemedButtonStyle())
                            .accessibilityHint("Writes the Recap on this Mac instead")
                    }
                    if error.providerFailure?.isFixedInSettings == true, let uiState {
                        Button("Open Settings") { AIModelActions.openSettings(uiState: uiState, openSettings: openSettings) }
                            .buttonStyle(ThemedButtonStyle())
                    }
                    Button("Show Log") { showLog() }
                        .buttonStyle(ThemedButtonStyle())
                }
            }
            .padding(.bottom, 8)
        }
    }

    /// The model asked for in this window, or the one Recap uses.
    private var currentModel: AIModelChoice {
        session.model ?? intelligence.models.modelSettings.choice(for: .recap)
    }

    /// "About 2 minutes on this Mac", with Private Cloud Compute, or with
    /// one of your providers.
    /// What asking before a long Recap says: the model that will read it,
    /// Apple Intelligence or yours ("Claude Opus 5.5 (Anthropic) reads
    /// 2,000 messages in 3 passes…").
    static func confirmationDetail(_ plan: RecapPlan, messages: Int) -> String {
        let reader = switch plan.venue {
        case .onDevice, .privateCloudCompute: "Apple Intelligence"
        case .provider(let label): label.title
        }
        let passes = plan.passes == 1 ? "in one pass" : "in \(plan.passes) passes"
        return "\(reader) reads \(RecapFormat.messages(messages)) \(passes). You can keep using Vela meanwhile, and Stop any time. The log is ready now."
    }

    private func estimate(_ plan: RecapPlan) -> String {
        let place = switch plan.venue {
        case .onDevice: "on this Mac"
        case .privateCloudCompute: "with Private Cloud Compute"
        case .provider(let label): "with \(label.providerName)"
        }
        return "\(RecapFormat.duration(plan.estimatedSeconds)) \(place)."
    }

    /// "Reading 340 of 1,200 messages · About 2 minutes left",
    /// "Writing the Recap…", "Waiting for another summary to finish…".
    private var progressText: String {
        guard let progress = session.summary?.progress else { return "Reading messages…" }
        if progress.isWaiting { return "Waiting for another summary to finish…" }
        var text = progress.isWriting
            ? "Writing the Recap…"
            : "Reading \(progress.messagesRead.formatted()) of \(RecapFormat.messages(progress.messagesTotal))"
        if let left = progress.secondsLeft, left >= 15 {
            text += " · \(RecapFormat.duration(left)) left"
        }
        return text
    }

    private var progressFraction: Double? {
        guard let progress = session.summary?.progress, progress.messagesTotal > 0, !progress.isWaiting else { return nil }
        if progress.isWriting { return 0.95 }
        return Double(progress.messagesRead) / Double(progress.messagesTotal) * 0.9
    }

    private func footer(_ summary: RecapSummary) -> some View {
        var parts: [String] = []
        if summary.skippedMessages > 0 {
            parts.append("Skipped \(RecapFormat.messages(summary.skippedMessages)) that \(summary.writerName) wouldn't summarize.")
        }
        parts.append(summary.provenance)
        parts.append("May contain mistakes, so check the messages behind anything you act on.")
        let models = intelligence.models
        return VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(theme[ThemeKey.chatSecondaryForeground].opacity(0.18)).frame(height: 1)
            Text(parts.joined(separator: " "))
                .font(type.small)
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
            if models.hasChoices || currentModel != .automatic {
                AIModelChangeMenu(current: currentModel, title: "Change Model") { choice in
                    session.rerun(with: choice)
                }
                .foregroundStyle(theme[ThemeKey.accentText])
                .disabled(session.summaryPhase == .running)
            }
        }
        .padding(.top, 34)
    }

    private func showLog() {
        var scope = session.scope
        scope.output = .log
        session.update(scope)
    }
}

// MARK: - Pieces

/// A section: a subtle rule, a heading with a count, and its content.
struct RecapSection<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    let title: String
    var count: Int?
    var note: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(theme[ThemeKey.chatSecondaryForeground].opacity(0.16))
                .frame(height: 1)
                .padding(.bottom, 6)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(type.heading)
                    .foregroundStyle(theme[ThemeKey.chatForeground])
                    .accessibilityAddTraits(.isHeader)
                if let count, count > 0 {
                    Text(count.formatted())
                        .font(type.metaStrong)
                        .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                }
                if let note {
                    Text(note)
                        .font(type.metaStrong)
                        .foregroundStyle(theme[ThemeKey.chatMention])
                }
            }
            content
        }
        .padding(.top, 26)
        .textSelection(.enabled)
    }
}

/// "•  text", the bullet in the accent color.
struct RecapBullet: View {
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    let text: String
    var font: Font?
    var color: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("•")
                .font(font ?? type.body)
                .foregroundStyle(theme[ThemeKey.accent])
                .accessibilityHidden(true)
            Text(text)
                .font(font ?? type.body)
                .foregroundStyle(color ?? theme[ThemeKey.chatForeground])
                .lineSpacing(type.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "2:14 PM in #vela ↗": shows the message in the main window.
struct RecapJumpLink: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    let reference: RecapReference
    let format: RecapFormat
    var conversationName: String?

    @State private var hovering = false

    var body: some View {
        Button {
            RecapActions.jump(to: reference, app: app, uiState: uiState, openWindow: openWindow)
        } label: {
            HStack(spacing: 3) {
                Text(label)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: max(8, type.base - 4), weight: .bold))
            }
            .font(type.meta)
            .foregroundStyle(theme[ThemeKey.chatLink])
            .underline(hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show this message in \(conversationName ?? "its conversation")")
        .accessibilityLabel("Show message from \(label)")
    }

    private var label: String {
        let time = format.time(reference.time)
        return conversationName.map { "\(time) in \($0)" } ?? time
    }
}

/// "More detail" under a topic or note, then its points as they're written.
struct RecapMoreDetail: View {
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    let id: String
    let session: RecapSession
    let ask: () -> Void

    var body: some View {
        let state = session.details[id]
        VStack(alignment: .leading, spacing: 7) {
            switch state {
            case nil:
                button("More detail", systemImage: "text.magnifyingglass", action: ask)
                    .disabled(session.summaryPhase == .running)
                    .help(session.summaryPhase == .running ? "Available once the Recap is written" : "A closer look at just these messages")
            case .loading(let detail):
                if let detail, !detail.points.isEmpty { points(detail.points) }
                RecapStatusLine(text: detail == nil ? "Looking closer…" : "Writing…")
            case .done(let detail):
                points(detail.points)
                button("Less detail", systemImage: "chevron.up") { session.clearDetail(id) }
            case .failed(let message):
                Text(message)
                    .font(type.meta)
                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                button("Try Again", systemImage: "arrow.clockwise") {
                    session.clearDetail(id)
                    ask()
                }
            }
        }
    }

    private func points(_ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                RecapBullet(text: point, font: type.meta, color: theme[ThemeKey.chatForeground])
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme[ThemeKey.accent].opacity(0.35)).frame(width: 2)
        }
        .transition(.opacity)
    }

    private func button(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(type.metaStrong)
                .foregroundStyle(theme[ThemeKey.accentText])
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Topics

private struct RecapTopicView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.recapTypography) private var type
    let topic: RecapTopic
    let session: RecapSession
    let format: RecapFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(topic.title)
                .font(type.subheading)
                .foregroundStyle(theme[ThemeKey.chatForeground])
                .accessibilityAddTraits(.isHeader)
            if !topic.summary.isEmpty {
                Text(topic.summary)
                    .font(type.body)
                    .foregroundStyle(theme[ThemeKey.chatForeground])
                    .lineSpacing(type.bodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if !topic.participants.isEmpty {
                    Text(participants)
                        .font(type.meta)
                        .lineLimit(1)
                }
                if let start = topic.start {
                    RecapJumpLink(reference: start, format: format, conversationName: conversationName(start.conversation))
                }
            }
            if !topic.lineIDs.isEmpty, !session.summaryIsProvisional {
                RecapMoreDetail(id: topic.id, session: session) { session.moreDetail(on: topic) }
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var participants: AttributedString {
        let conversation = topic.start.flatMap { app.lookup($0.conversation) }
        var line = AttributedString()
        for (index, nick) in topic.participants.enumerated() {
            if index > 0 {
                var comma = AttributedString(", ")
                comma.foregroundColor = theme[ThemeKey.chatSecondaryForeground]
                line += comma
            }
            var part = AttributedString(nick)
            part.foregroundColor = theme.recapNickColor(nick, colorNicks: style.colorNicks, in: conversation)
            line += part
        }
        return line
    }

    private func conversationName(_ id: BufferID) -> String? {
        guard let input = session.input, input.conversations.count > 1 else { return nil }
        return RecapActions.conversationNames(input)[id]
    }
}

extension RecapSession {
    /// The topics shown are each part's, before they're combined.
    var summaryIsProvisional: Bool { summary?.topicsAreProvisional == true }
}

// MARK: - For you

private struct RecapForYouRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.recapTypography) private var type
    let item: RecapForYou
    let note: String?
    let format: RecapFormat
    let conversationNames: [BufferID: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(type.body)
                .lineSpacing(type.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                RecapJumpLink(
                    reference: item.reference,
                    format: format,
                    conversationName: conversationNames[item.reference.conversation] ?? (item.isPrivate ? "your conversation" : nil)
                )
                if !item.isAnswered {
                    Text(item.isRequest ? "No reply yet" : "Not answered")
                        .font(type.metaStrong)
                        .foregroundStyle(theme[ThemeKey.chatMention])
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme[ThemeKey.chatMention].opacity(0.13)))
                }
                if item.followingMessages > 0 {
                    Text("+\(item.followingMessages) more")
                        .font(type.meta)
                        .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// **wren** asked you to review the PR. — or their own words, quoted.
    private var text: AttributedString {
        var nick = AttributedString(item.nick)
        nick.foregroundColor = theme.recapNickColor(item.nick, colorNicks: style.colorNicks, in: app.lookup(item.reference.conversation))
        nick.font = type.body.weight(.semibold)
        let rest: String
        if let note {
            rest = " " + RecapMarkdown.dropLeadingNick(note, nick: item.nick)
        } else {
            rest = ": “\(item.quote)”"
        }
        var body = AttributedString(rest)
        body.foregroundColor = theme[ThemeKey.chatForeground]
        return nick + body
    }
}

// MARK: - Decisions and follow-ups

private struct RecapNoteRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.recapTypography) private var type
    let note: RecapNote
    let session: RecapSession
    let format: RecapFormat
    let conversationNames: [BufferID: String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol)
                .font(type.meta)
                .foregroundStyle(theme[ThemeKey.accent])
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(text)
                    .font(type.body)
                    .lineSpacing(type.bodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                if let reference = note.reference {
                    RecapJumpLink(reference: reference, format: format, conversationName: conversationNames[reference.conversation])
                    RecapMoreDetail(id: note.id, session: session) { session.moreDetail(on: note) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch note.kind {
        case .decision: "checkmark.circle"
        case .question: "questionmark.circle"
        case .followUp: "arrow.turn.down.right"
        }
    }

    private var text: AttributedString {
        var text = AttributedString(note.text)
        text.foregroundColor = theme[ThemeKey.chatForeground]
        guard let owner = note.owner else { return text }
        var name = AttributedString(owner + ": ")
        name.foregroundColor = theme.recapNickColor(owner, colorNicks: style.colorNicks, in: note.reference.flatMap { app.lookup($0.conversation) })
        name.font = type.body.weight(.semibold)
        return name + text
    }
}

// MARK: - Links

private struct RecapLinkGroupView: View {
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    let group: RecapLinkGroup
    let format: RecapFormat
    let conversationNames: [BufferID: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(group.title)
                .font(type.subheading)
                .foregroundStyle(theme[ThemeKey.chatForeground])
                .accessibilityAddTraits(.isHeader)
            ForEach(group.links) { link in
                RecapLinkRow(link: link, format: format, conversationName: conversationNames[link.reference.conversation])
            }
        }
    }
}

private struct RecapLinkRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.recapTypography) private var type
    @Environment(\.openURL) private var openURL
    let link: RecapLink
    let format: RecapFormat
    let conversationName: String?

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("•")
                .font(type.body)
                .foregroundStyle(theme[ThemeKey.accent])
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Button { openURL(link.url) } label: {
                    Text(link.displayTitle)
                        .font(type.body)
                        .foregroundStyle(theme[ThemeKey.chatLink])
                        .underline(hovering)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help(link.url.absoluteString)
                .accessibilityHint("Opens in your browser")
                HStack(spacing: 6) {
                    Text(link.title == nil ? link.nick : "\(link.host) · \(link.nick)")
                        .font(type.meta)
                        .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                    if link.shares > 1 {
                        Text("shared \(link.shares) times")
                            .font(type.meta)
                            .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                    }
                    RecapJumpLink(reference: link.reference, format: format, conversationName: conversationName)
                }
            }
        }
    }
}

extension ResolvedTheme {
    /// A nick a recap names, as on its messages in `conversation`: yours
    /// in `chat.selfNick`, anyone else's in their color there.
    func recapNickColor(_ nick: String, colorNicks: Bool, in conversation: (session: NetworkSession, buffer: BufferModel)?) -> Color {
        let isSelf = conversation?.session.isSelf(nick) ?? false
        return nickDisplayColor(nick, isSelf: isSelf, colorNicks: colorNicks, in: conversation?.buffer)
    }
}
