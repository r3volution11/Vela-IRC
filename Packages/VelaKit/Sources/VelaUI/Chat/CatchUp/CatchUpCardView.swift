// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// The message list's row for the open Catch me up card, under the New
/// marker, lined up with the message text.
struct CatchUpCardRow: View {
    @Environment(\.chatStyle) private var style
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(MessageListController.self) private var controller

    var body: some View {
        if app.settings[.intelligenceCatchUp], let card = intelligence.catchUp.cards[controller.buffer.id] {
            CatchUpCardView(card: card)
                .padding(.leading, leadingInset)
                .padding(.trailing, style.rowHorizontalPadding)
                .padding(.top, 2)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var leadingInset: CGFloat {
        switch style.layout {
        case .grouped: GroupedMetrics(style: style).textX
        case .columns: ColumnsMetrics(style: style).textX
        case .classic: style.rowHorizontalPadding
        }
    }
}

/// "While you were away · N messages": the streamed overview, the topics
/// (each jumps to where it starts), notes on where you were mentioned, and
/// Copy / Regenerate / Dismiss. Drawn like a link card.
struct CatchUpCardView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(MessageListController.self) private var controller
    @Environment(UIState.self) private var uiState
    @Environment(\.openWindow) private var openWindow
    let card: CatchUpCard

    static let maxWidth: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            switch card.phase {
            case .running(let partial):
                if let partial, partial.hasText {
                    // Words being redone stay, dimmed, until new ones arrive.
                    VStack(alignment: .leading, spacing: 9) { content(partial) }
                        .opacity(partial.isRevising ? 0.5 : 1)
                    if partial.isRevising { status(Self.revisingText(partial)) }
                } else {
                    status(Self.statusText(partial, messageCount: card.messageCount, summariesAhead: card.summariesAhead))
                }
            case .done(let summary):
                content(summary)
            case .failed(.nothingToSummarize):
                nothingNew
            case .failed(let error):
                failure(error)
            }
            if !isFailed { footer }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .embedCard(accent: theme[ThemeKey.accent])
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: layoutKey)
        .onChange(of: isDone) { _, done in
            if done { AccessibilityNotification.Announcement("Summary ready").post() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Catch me up")
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: max(10, style.fontSize - 2), weight: .semibold))
                .foregroundStyle(theme[ThemeKey.accentText])
                .accessibilityHidden(true)
            Text(card.isNothingNew ? "Catch me up" : "While you were away · \(CatchUpActions.messagesLabel(card.messageCount))")
                .font(style.font(size: max(9, style.fontSize - 2), weight: .medium))
                .foregroundStyle(theme[ThemeKey.embedSiteName])
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if case .running(let partial?) = card.phase, partial.hasText, !partial.isRevising {
                // Still writing; otherwise the body has its own spinner.
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Summarizing")
            }
            if !card.isNothingNew {
                CatchUpCardButton(systemImage: "doc.on.doc", label: "Copy Summary") { copy() }
                    .disabled(!isDone)
                CatchUpCardButton(systemImage: "arrow.clockwise", label: "Regenerate") { regenerate() }
                    .disabled(card.isRunning)
            }
            CatchUpCardButton(systemImage: "xmark", label: "Dismiss") { dismiss() }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.footerText(card.summary, messageCount: card.messageCount))
                .font(style.font(size: max(9, style.fontSize - 3)))
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
            if !card.isNothingNew, RecapActions.isOffered(app.settings) {
                Button("Open Full Recap") { openFullRecap() }
                    .buttonStyle(CatchUpCapsuleButtonStyle())
                    .help(Self.fullRecapHelp(messageCount: card.messageCount))
                    .accessibilityHint("Opens a fuller report of these messages in a window of its own")
            }
        }
    }

    /// The card covers the latest 600 messages, six topics and three
    /// mentions; a Recap goes further.
    nonisolated static func fullRecapHelp(messageCount: Int) -> String {
        messageCount > CatchUpRequest.maximumLines
            ? "This card covers the latest \(CatchUpRequest.maximumLines) of \(messageCount.formatted()) messages. A Recap covers more, with decisions, follow-ups and links."
            : "A fuller report of these messages, with decisions, follow-ups and links, in a window of its own."
    }

    /// A Recap of the card's stretch: since the first unread message, or,
    /// with the New marker gone, back to the stretch's first message.
    private func openFullRecap() {
        let buffer = controller.buffer
        var scope = RecapActions.scope(for: buffer, intelligence: intelligence)
        if buffer.unreadMarkerAfter == nil {
            let start = card.request.lines.first?.time ?? card.anchor
            let minutes = Int((Date().timeIntervalSince(start) / 60).rounded(.up)) + 1
            scope.span = .last(minutes: max(1, min(minutes, 60 * 24 * 30)))
        }
        RecapActions.open(scope, openWindow: openWindow)
    }

    /// The note under the summary: how much it covers, what was left out,
    /// and where it was made (on this Mac, or with Private Cloud Compute).
    nonisolated static func footerText(_ summary: CatchUpSummary?, messageCount: Int) -> String {
        var parts: [String] = []
        if let summary, summary.messageCount < messageCount, summary.messageCount >= CatchUpRequest.maximumLines {
            parts.append("Covers the latest \(CatchUpActions.messagesLabel(summary.messageCount)).")
        }
        if let skipped = summary?.skippedMessages, skipped > 0 {
            parts.append("Skipped \(CatchUpActions.messagesLabel(skipped)) that Apple Intelligence wouldn't summarize.")
        }
        parts.append(summary?.provenance ?? CatchUpSummary.onDeviceProvenance)
        parts.append("May contain mistakes.")
        return parts.joined(separator: " ")
    }

    /// While there are no words to show: "Waiting… 1 summary ahead" while
    /// other summaries are written first, "Reading 250 messages…", or for
    /// a stretch read in parts "Reading… 3 of 8", then "Writing the
    /// summary…".
    nonisolated static func statusText(_ partial: CatchUpSummary?, messageCount: Int, summariesAhead: Int? = nil) -> String {
        if let ahead = summariesAhead, ahead > 0 {
            return ahead == 1 ? "Waiting… 1 summary ahead" : "Waiting… \(ahead) summaries ahead"
        }
        guard let progress = partial?.progress else {
            return "Reading \(CatchUpActions.messagesLabel(messageCount))…"
        }
        if progress.isFinished { return "Writing the summary…" }
        return "Reading… \(progress.completed + 1) of \(progress.total)"
    }

    /// Under words that are being redone.
    nonisolated static func revisingText(_ partial: CatchUpSummary) -> String {
        guard let progress = partial.progress, !progress.isFinished else { return "Finishing…" }
        return "Finishing… \(progress.completed + 1) of \(progress.total)"
    }

    // MARK: States

    private func status(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            Text(text)
                .font(style.font(size: max(10, style.fontSize - 1)))
                .foregroundStyle(theme[ThemeKey.embedDescription])
                .contentTransition(.numericText())
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Asked for with nothing new: says so, and when the button comes back.
    private var nothingNew: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: max(10, style.fontSize - 1), weight: .semibold))
                .foregroundStyle(theme[ThemeKey.embedSiteName])
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing new in \(controller.buffer.name) since you last read it.")
                    .font(style.font(size: max(10, style.fontSize - 1)))
                    .foregroundStyle(theme[ThemeKey.chatForeground])
                Text(CatchUpEligibility.nothingNewDetail(
                    threshold: app.settings[.intelligenceCatchUpThreshold],
                    showsNewLine: style.showUnreadMarker
                ))
                .font(style.font(size: max(9, style.fontSize - 2)))
                .foregroundStyle(theme[ThemeKey.embedDescription])
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(_ summary: CatchUpSummary) -> some View {
        Text(summary.overview)
            .font(style.font(size: style.fontSize))
            .foregroundStyle(theme[ThemeKey.chatForeground])
            .lineSpacing(style.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)

        if !summary.topics.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(summary.topics) { topic in
                    CatchUpTopicRow(topic: topic) { jump(to: topic) }
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, -8)
        }

        if !summary.addressedToYou.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Label("You were mentioned", systemImage: "at")
                    .font(style.font(size: max(9, style.fontSize - 2), weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.chatMention])
                    .accessibilityAddTraits(.isHeader)
                ForEach(summary.addressedToYou, id: \.self) { note in
                    Text(note)
                        .font(style.font(size: max(10, style.fontSize - 1)))
                        .foregroundStyle(theme[ThemeKey.chatForeground])
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 1)
            .transition(.opacity)
        }
    }

    private func failure(_ error: CatchUpError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: max(10, style.fontSize - 1), weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.embedSiteName])
                    .accessibilityHidden(true)
                Text(error.errorDescription ?? "Apple Intelligence couldn't summarize this conversation.")
                    .font(style.font(size: max(10, style.fontSize - 1)))
                    .foregroundStyle(theme[ThemeKey.chatForeground])
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Try Again") { regenerate() }
                    .buttonStyle(CatchUpCapsuleButtonStyle())
                if case .unavailable(let status) = error, let url = status.settingsURL {
                    Button("Open System Settings") { NSWorkspace.shared.open(url) }
                        .buttonStyle(CatchUpCapsuleButtonStyle())
                }
            }
        }
    }

    // MARK: Actions

    private var isDone: Bool {
        if case .done = card.phase { true } else { false }
    }

    private var isFailed: Bool {
        if case .failed = card.phase { true } else { false }
    }

    /// Changes that resize the card, for its animation.
    private var layoutKey: [Int] {
        switch card.phase {
        case .running(let partial):
            [0, partial?.topics.count ?? -1, partial?.addressedToYou.count ?? 0, partial?.hasText == true ? 1 : 0, partial?.isRevising == true ? 1 : 0]
        case .done(let summary): [1, summary.topics.count, summary.addressedToYou.count]
        case .failed: [2]
        }
    }

    private func copy() {
        guard let summary = card.summary else { return }
        CatchUpActions.copy(summary, bufferName: controller.buffer.name, messageCount: card.messageCount)
    }

    private func regenerate() {
        CatchUpActions.regenerate(card, buffer: controller.buffer, session: controller.session, store: intelligence.catchUp)
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            intelligence.catchUp.dismiss(controller.buffer.id)
        }
    }

    private func jump(to topic: CatchUpTopic) {
        guard let lineID = topic.firstLineID else { return }
        uiState.scrollTarget = lineID
    }
}

/// One topic: its title, who took part and a chevron, with its one-line
/// summary underneath. Clicking it scrolls to where it starts.
private struct CatchUpTopicRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let topic: CatchUpTopic
    let action: () -> Void

    @State private var hovering = false

    private var canJump: Bool { topic.firstLineID != nil }

    var body: some View {
        if canJump {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help("Show where this starts")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityHint("Scrolls to where this topic starts")
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(topic.title)
                    .font(style.font(size: max(10, style.fontSize - 1), weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.embedTitle])
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !topic.participants.isEmpty {
                    Text(CatchUpActions.participantsLabel(topic.participants))
                        .font(style.font(size: max(9, style.fontSize - 2)))
                        .foregroundStyle(theme[ThemeKey.embedSiteName])
                        .lineLimit(1)
                }
                if canJump {
                    Image(systemName: "chevron.right")
                        .font(.system(size: max(8, style.fontSize - 4), weight: .bold))
                        .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                        .opacity(hovering ? 1 : 0.6)
                }
            }
            if !topic.summary.isEmpty {
                Text(topic.summary)
                    .font(style.font(size: max(10, style.fontSize - 1)))
                    .foregroundStyle(theme[ThemeKey.embedDescription])
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? theme[ThemeKey.chatHoverBackground] : .clear)
        )
        .contentShape(Rectangle())
    }

    private var accessibilityText: String {
        var parts = [topic.title]
        if !topic.summary.isEmpty { parts.append(topic.summary) }
        if !topic.participants.isEmpty { parts.append("With \(CatchUpActions.participantsLabel(topic.participants))") }
        return parts.joined(separator: ". ")
    }
}

/// A small borderless icon button in the card's header.
private struct CatchUpCardButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.isEnabled) private var isEnabled
    let systemImage: String
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: max(9, style.fontSize - 3), weight: .semibold))
                .foregroundStyle(theme[ThemeKey.embedSiteName])
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering && isEnabled ? theme[ThemeKey.chatHoverBackground] : .clear)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The accent capsule used by "Catch me up" and the card's inline buttons.
struct CatchUpCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CatchUpCapsuleBody(configuration: configuration)
    }
}

private struct CatchUpCapsuleBody: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let configuration: ButtonStyleConfiguration

    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: max(10, style.fontSize - 2), weight: .semibold))
            .foregroundStyle(theme[ThemeKey.accentText])
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(theme[ThemeKey.accent].opacity(configuration.isPressed ? 0.28 : hovering ? 0.2 : 0.12)))
            .contentShape(Capsule())
            .fixedSize()
            .onHover { hovering = $0 }
    }
}
