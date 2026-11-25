// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// The message composer under the chat: a rounded multi-line field in a
/// padded container, with a reply bar, a confirmation bar for large pastes,
/// and connection/channel status when sending isn't possible.
///
/// Return sends, ⇧Return/⌥Return add a line, Tab completes nicks, channels,
/// `/commands` and `:emoji:`, ↑/↓ recall this buffer's history, Escape
/// cancels a pending reply (with nothing to cancel, it jumps to the newest
/// message), Page Up/Down, Home and End scroll the messages. Drafts are
/// kept per buffer in `UIState`.
///
/// At its end: the emoji and GIF picker's smiley (⇧⌘E), and a send button
/// (`input.showSendButton`) that does what Return does. A GIF picked there
/// shows as a chip above the text and is sent as its link after it.
struct InputBar: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.messageListLink) private var messageListLink
    @Environment(\.openSettings) private var openSettings
    @Environment(\.gifSearchServices) private var injectedGIFServices
    let buffer: BufferModel
    let session: NetworkSession

    /// More pasted lines than this ask for confirmation before sending.
    static let pasteConfirmationThreshold = 3

    @State private var text = ""
    @State private var editorHeight: CGFloat = 30
    @State private var isFocused = false
    @State private var history = InputHistoryCursor()
    @State private var pendingPaste: String?
    @State private var insertion: ComposerInsertion?
    @State private var rejectCount = 0
    @State private var didRestoreDraft = false
    /// The emoji and GIF picker's popover.
    @State private var isPickerShown = false
    /// The picker's views outlive the popover only through its closing
    /// animation, then go (with their previews): SwiftUI keeps a closed
    /// popover's content otherwise.
    @State private var keepsPickerContent = false

    // MARK: State

    private enum Availability: Equatable {
        case ready
        case connecting
        case offline
        case notJoined
        /// Left here but kept on the bouncer.
        case detached
    }

    private var availability: Availability {
        switch session.connectionState {
        case .disconnected: return .offline
        case .connecting, .registering: return .connecting
        case .connected: break
        }
        if buffer.kind == .channel && !buffer.isJoined { return buffer.isDetached ? .detached : .notJoined }
        return .ready
    }

    private var placeholder: String {
        switch availability {
        case .offline: return "Offline — reconnect to send"
        case .connecting: return "Connecting to \(session.displayName)…"
        case .notJoined: return "Not in channel — /join to rejoin"
        case .detached: return "Left here, still on your bouncer — join to catch up"
        case .ready:
            switch buffer.kind {
            case .channel, .query: return "Message \(buffer.name)"
            case .server: return "Type /commands for the server"
            }
        }
    }

    private var replyTarget: ChatLine? {
        uiState.replyTargets[buffer.id]
    }

    /// The GIF picked for this message, if any.
    private var composerGIF: ComposerGIF? {
        uiState.composerGIFs[buffer.id]
    }

    /// Something to send: text, a GIF, or a paste waiting for confirmation.
    private var hasSomethingToSend: Bool {
        pendingPaste != nil || composerGIF != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// One line of the editor, insets included: the trailing buttons sit
    /// centered on it however tall the text grows.
    static func singleLineHeight(for font: NSFont) -> CGFloat {
        if let cached = lineHeights[font] { return cached }
        let height = (NSLayoutManager().defaultLineHeight(for: font) + ComposerTextView.verticalInset * 2).rounded(.up)
        lineHeights[font] = height
        return height
    }

    private static var lineHeights: [NSFont: CGFloat] = [:]

    private var appearance: ComposerAppearance {
        ComposerAppearance(
            font: style.bodyNSFont,
            textColor: theme.color(ThemeKey.inputForeground).nsColor,
            placeholderColor: theme.color(ThemeKey.inputPlaceholder).nsColor,
            caretColor: theme.color(ThemeKey.inputForeground).nsColor,
            selectionColor: theme.color(ThemeKey.chatSelectionBackground).nsColor,
            placeholder: placeholder,
            textChecking: TextCheckingOptions(settings: app.settings, system: SystemTextSettings.shared.values),
            accessibilityLabel: buffer.kind == .server ? "Command for \(session.displayName)" : "Message \(buffer.name)"
        )
    }

    /// Words text checking leaves alone: everyone here (and you) and the
    /// network's channel prefixes. Read when text is checked, so the bar
    /// doesn't redraw on every join and part.
    private static func textContext(buffer: BufferModel, session: NetworkSession) -> ComposerTextContext {
        let nicks: [String] = switch buffer.kind {
        case .channel: buffer.members.map(\.nick)
        case .query: [buffer.name, session.nick]
        case .server: [session.nick]
        }
        let channelTypes = session.isupport.channelTypes
        return ComposerTextContext(nicks: nicks, channelTypes: channelTypes.isEmpty ? ["#", "&"] : channelTypes)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme[ThemeKey.paneDivider])
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                if let pendingPaste {
                    PasteConfirmationBar(
                        text: pendingPaste,
                        target: buffer.kind == .server ? session.displayName : buffer.name,
                        onSend: confirmPaste,
                        onEdit: editPaste,
                        onCancel: cancelPaste
                    )
                    .transition(barTransition)
                }
                field
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .surfaceBackground(ThemeKey.inputContainerBackground, on: .content)
        .devTag(
            "Message box area",
            tokens: [ThemeKey.inputContainerBackground, ThemeKey.paneDivider],
            padding: EdgeInsets(top: 11, leading: 14, bottom: 12, trailing: 14)
        )
        .fixedSize(horizontal: false, vertical: true)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: pendingPaste != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: replyTarget?.id)
        .onAppear(perform: restoreDraft)
        .onChange(of: text) { _, newValue in saveDraft(newValue) }
        // For F6, which goes on from the area that has the focus.
        .onChange(of: isFocused) { _, focused in uiState.setFocused(.messageBox, focused) }
        // A draft put in from outside (Siri's "draft a message") while this
        // channel is already open.
        .onChange(of: uiState.drafts[buffer.id]) { _, draft in
            if let draft, draft != text { text = draft }
        }
        // Mention from a user menu.
        .onChange(of: uiState.mentionRequest, initial: true) { _, request in
            guard let request, request.bufferID == buffer.id else { return }
            uiState.mentionRequest = nil
            insertion = ComposerInsertion(text: request.nick, isMention: true)
            uiState.focusInput()
        }
        // ⇧⌘E.
        .onChange(of: uiState.composerPickerToken) { _, _ in
            isPickerShown.toggle()
        }
        // Closed, however it closed: GIF previews and searches stop (if
        // GIFs were ever used).
        .onChange(of: isPickerShown) { _, shown in
            guard !shown else {
                keepsPickerContent = true
                return
            }
            (injectedGIFServices ?? GIFSearchServices.made)?.pickerClosed()
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !isPickerShown { keepsPickerContent = false }
            }
        }
    }

    private var barTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let border = app.settings[.appearanceMessageBoxBorder]
        return VStack(alignment: .leading, spacing: 0) {
            if let replyTarget {
                ReplyBar(line: replyTarget, supportsReplies: session.supportsReplies) {
                    uiState.replyTargets[buffer.id] = nil
                }
                .transition(barTransition)
                Rectangle()
                    .fill(theme[ThemeKey.inputBorder])
                    .frame(height: 1)
            }
            if let composerGIF {
                ComposerGIFChip(gif: composerGIF) {
                    uiState.composerGIFs[buffer.id] = nil
                    uiState.focusInput()
                }
                .transition(barTransition)
                Rectangle()
                    .fill(theme[ThemeKey.inputBorder])
                    .frame(height: 1)
            }
            HStack(alignment: .bottom, spacing: 6) {
                AttachmentSlot(session: session)
                ComposerTextView(
                    text: $text,
                    height: $editorHeight,
                    isFocused: $isFocused,
                    appearance: appearance,
                    focusRequest: uiState.focusInputToken,
                    yieldsFocus: { [uiState] in uiState.focusedArea.map { $0 != .messageBox } ?? false },
                    insertion: insertion,
                    actions: actions
                )
                .frame(height: editorHeight)
                .frame(maxWidth: .infinity)
                // Centered on the first line, however tall the text grows.
                trailingAccessory
                    .frame(height: Self.singleLineHeight(for: style.bodyNSFont))
                    .frame(minHeight: editorHeight, alignment: .top)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
        }
        .background(shape.fill(theme[ThemeKey.inputBackground]))
        .clipShape(shape)
        .overlay {
            // Settings → Appearance → Message box → Border.
            if let stroke = border.stroke(isFocused: isFocused) {
                shape.strokeBorder(theme[stroke.token], lineWidth: stroke.width)
            }
        }
        .devTag(
            "Message box",
            tokens: [
                ThemeKey.inputBackground, ThemeKey.inputForeground, ThemeKey.inputPlaceholder,
                border.stroke(isFocused: isFocused)?.token,
            ].compactMap { $0 },
            font: style.bodyFont,
            padding: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 8)
        )
        .modifier(ShakeEffect(shakes: reduceMotion ? 0 : CGFloat(rejectCount)))
        .animation(reduceMotion ? nil : .linear(duration: 0.32), value: rejectCount)
        .animation(reduceMotion || !border.changesWithFocus ? nil : .easeOut(duration: 0.12), value: isFocused)
    }

    /// Left to right: the split hint ("2 messages"), the emoji and GIF
    /// picker's smiley (always: emoji go in offline too), then the send
    /// button, or Reconnect, Join or a spinner while chatting isn't possible.
    private var trailingAccessory: some View {
        HStack(spacing: 4) {
            if availability == .ready {
                MessageSplitHint(text: text, target: buffer.name)
                    .padding(.trailing, 2)
            }
            ComposerPickerButton(isPresented: $isPickerShown, isActive: isFocused || isPickerShown)
                .popover(isPresented: $isPickerShown, arrowEdge: .top) {
                    if isPickerShown || keepsPickerContent {
                        picker
                    }
                }
            switch availability {
            case .offline:
                StatusActionButton(title: "Reconnect", systemImage: "bolt.horizontal.circle", help: "Connect to \(session.displayName)") {
                    session.connect()
                }
            case .notJoined, .detached:
                StatusActionButton(title: "Join", systemImage: "arrow.right.circle", help: "Join \(buffer.name)") {
                    app.rejoin(buffer)
                }
            case .connecting:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Connecting")
            case .ready:
                if app.settings[.inputShowSendButton] {
                    ComposerSendButton(canSend: hasSomethingToSend, isActive: isFocused || isPickerShown) {
                        submit()
                        uiState.focusInput()
                    }
                }
            }
        }
    }

    /// The popover's content.
    private var picker: some View {
        ComposerPickerView(
            onEmoji: { emoji in
                insertion = ComposerInsertion(text: emoji)
                closePicker()
            },
            onGIF: { result, provider in
                uiState.composerGIFs[buffer.id] = ComposerGIF(result: result, provider: provider)
                closePicker()
            },
            onClose: closePicker,
            onOpenSettings: {
                isPickerShown = false
                uiState.settingsSectionReveal = .gifs
                uiState.settingsEditor.requestedPane = .media
                openSettings()
            }
        )
    }

    /// Closes the picker and gives the message box the focus back.
    private func closePicker() {
        isPickerShown = false
        uiState.focusInput()
    }

    // MARK: Actions

    private var actions: ComposerActions {
        ComposerActions(
            submit: submit,
            userEdited: { value in
                session.inputChanged(value, in: buffer)
            },
            historyPrevious: {
                guard let entry = history.previous(in: InputHistoryStore.shared.entries(for: buffer.id), current: text) else {
                    return false
                }
                text = entry
                return true
            },
            historyNext: {
                guard let entry = history.next(in: InputHistoryStore.shared.entries(for: buffer.id)) else { return false }
                text = entry
                return true
            },
            escape: {
                if pendingPaste != nil {
                    cancelPaste()
                    return true
                }
                if replyTarget != nil {
                    uiState.replyTargets[buffer.id] = nil
                    return true
                }
                return false
            },
            scrollMessages: { [messageListLink, buffer] scroll in
                messageListLink?.scroll(scroll, in: buffer.id) ?? false
            },
            interceptPaste: { pasted in
                let lines = Self.messageLineCount(pasted)
                guard lines > Self.pasteConfirmationThreshold else { return false }
                pendingPaste = pasted
                return true
            },
            completions: { word, atLineStart in
                TabCompletion.candidates(for: word, atLineStart: atLineStart, buffer: buffer, session: session)
            },
            textCheckingToggled: { [settings = app.settings] toggle, isOn in
                toggle.write(isOn, to: settings)
            },
            textContext: { [buffer, session] in
                Self.textContext(buffer: buffer, session: session)
            },
            deleteBackwardAtStart: { [uiState, buffer] in
                // Delete before the text takes out the GIF, like a token.
                guard uiState.composerGIFs[buffer.id] != nil else { return false }
                uiState.composerGIFs[buffer.id] = nil
                return true
            }
        )
    }

    private func submit() {
        if pendingPaste != nil {
            confirmPaste()
            return
        }
        let gif = composerGIF
        guard gif != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // A GIF goes out as its link, after the text.
        let message = ComposerGIF.message(text: text, gif: gif)
        guard canSend(message) else {
            reject()
            return
        }
        // Before the message's row is drawn, so its "via KLIPY" caption
        // opens the GIF's page.
        gif?.recordSent()
        send(message)
        InputHistoryStore.shared.push(message, for: buffer.id)
        history.reset()
        text = ""
        if gif != nil { uiState.composerGIFs[buffer.id] = nil }
    }

    private func send(_ message: String) {
        session.submit(message, in: buffer, replyTo: replyTarget)
        uiState.replyTargets[buffer.id] = nil
        session.inputChanged("", in: buffer)
    }

    /// Commands always go through (`/connect`, `/join`…); chat needs a
    /// connection and, in a channel, membership.
    private func canSend(_ message: String) -> Bool {
        Self.isCommand(message) || availability == .ready
    }

    private func reject() {
        Beep.play()
        rejectCount += 1
        AccessibilityNotification.Announcement(placeholder).post()
    }

    private func confirmPaste() {
        guard let paste = pendingPaste else { return }
        var payload = paste.trimmingCharacters(in: .newlines)
        guard availability == .ready else {
            reject()
            return
        }
        // Pasted text is sent literally, even if it starts with "/".
        if payload.hasPrefix("/") { payload = "/" + payload }
        send(payload)
        pendingPaste = nil
    }

    private func editPaste() {
        guard let paste = pendingPaste else { return }
        pendingPaste = nil
        insertion = ComposerInsertion(text: paste)
        uiState.focusInput()
    }

    private func cancelPaste() {
        pendingPaste = nil
    }

    // MARK: Drafts

    private func restoreDraft() {
        guard !didRestoreDraft else { return }
        didRestoreDraft = true
        if let draft = uiState.drafts[buffer.id], !draft.isEmpty {
            text = draft
        }
    }

    private func saveDraft(_ value: String) {
        guard didRestoreDraft else { return }
        if value.isEmpty {
            if uiState.drafts[buffer.id] != nil { uiState.drafts[buffer.id] = nil }
        } else if uiState.drafts[buffer.id] != value {
            uiState.drafts[buffer.id] = value
        }
    }

    // MARK: Helpers

    static func isCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/") && !trimmed.hasPrefix("//")
    }

    /// Non-empty lines, i.e. how many messages a paste becomes before splitting.
    static func messageLineCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline)
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .count
    }
}

// MARK: - Reply bar

/// "Replying to nick — snippet" with a ×, attached to the top of the field.
private struct ReplyBar: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.nickColorBuffer) private var buffer
    let line: ChatLine
    let supportsReplies: Bool
    let onCancel: () -> Void

    var body: some View {
        let nick = line.nick ?? "message"
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(theme[ThemeKey.replyQuoteBar])
                .frame(width: 3)
                .padding(.vertical, 2)
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.replyForeground])
            Text("Replying to \(Text(nick).fontWeight(.semibold).foregroundStyle(nickColor(nick))) — \(snippet)")
                .font(style.font(size: max(10, style.fontSize - 1)))
                .foregroundStyle(theme[ThemeKey.replyForeground])
                .lineLimit(1)
                .truncationMode(.tail)
            if !supportsReplies {
                Text("sent as a normal message")
                    .font(style.font(size: max(9, style.fontSize - 2)))
                    .foregroundStyle(theme[ThemeKey.inputPlaceholder])
                    .lineLimit(1)
                    .layoutPriority(-1)
                    .help("This server doesn't support IRCv3 replies")
            }
            Spacer(minLength: 4)
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(theme[ThemeKey.inputIconForeground])
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel reply (Esc)")
            .accessibilityLabel("Cancel reply")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .background(theme[ThemeKey.replyBackground])
        .devTag(
            "Reply bar",
            tokens: [ThemeKey.replyBackground, ThemeKey.replyForeground, ThemeKey.replyQuoteBar],
            padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        )
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Replying to \(nick): \(snippet)")
    }

    private var snippet: String {
        let plain = IRCFormatting.strip(line.text)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return plain.count > 140 ? String(plain.prefix(140)) + "…" : plain
    }

    /// As in the message (your own nick in `chat.selfNick`).
    private func nickColor(_ nick: String) -> Color {
        if line.isSelf { return theme[ThemeKey.chatSelfNick] }
        return style.colorNicks ? theme.nickColor(for: nick, in: buffer).color : theme[ThemeKey.replyForeground]
    }
}

// MARK: - Paste confirmation

/// Shown instead of sending when a paste would become many messages.
private struct PasteConfirmationBar: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let text: String
    let target: String
    let onSend: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let lines = InputBar.messageLineCount(text)
        let messages = IRCMessage.chatLines(target: target, text: text).count
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme[ThemeKey.accent])
            VStack(alignment: .leading, spacing: 2) {
                Text("Send \(lines) lines to \(target)?")
                    .font(style.font(size: style.fontSize, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.inputForeground])
                Text(firstLine + (messages > lines ? "  ·  \(messages) messages after splitting long lines" : ""))
                    .font(style.font(size: max(9, style.fontSize - 2)))
                    .foregroundStyle(theme[ThemeKey.inputPlaceholder])
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button("Cancel", action: onCancel)
                .buttonStyle(ThemedButtonStyle())
                .help("Discard the paste (Esc)")
            Button("Edit", action: onEdit)
                .buttonStyle(ThemedButtonStyle())
                .help("Put the text in the message field instead")
            Button("Send", action: onSend)
                .buttonStyle(ThemedButtonStyle(prominent: true))
                .help("Send all lines (Return)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme[ThemeKey.inputBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme[ThemeKey.inputBorder], lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Send \(lines) pasted lines to \(target)?")
    }

    private var firstLine: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return "“\(first.trimmingCharacters(in: .whitespaces))”…"
    }
}

// MARK: - Accessories

/// "Reconnect" / "Join" inside the field when chatting isn't possible yet.
private struct StatusActionButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.accentForeground])
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(theme[ThemeKey.accent].opacity(hovering ? 0.85 : 1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// "2 messages" when the text will be split to fit IRC's line length.
private struct MessageSplitHint: View {
    @Environment(\.theme) private var theme
    let text: String
    let target: String

    var body: some View {
        // Cheap check first: short single lines are always one message.
        if text.utf8.count > 300 || text.contains(where: \.isNewline) {
            let count = IRCMessage.chatLines(target: target, text: text).count
            if count > 1 {
                Text("\(count) messages")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme[ThemeKey.inputPlaceholder])
                    .help("Long or multi-line text is sent as \(count) separate IRC messages")
                    .accessibilityLabel("Will send as \(count) messages")
            }
        }
    }
}

/// Horizontal shake for a refused send (skipped under Reduce Motion).
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(shakes * .pi * 4), y: 0))
    }
}
