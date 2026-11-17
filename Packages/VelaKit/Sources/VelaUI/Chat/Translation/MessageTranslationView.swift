// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaTheme

/// A message's translation, under its text: the translated text in the
/// quieter secondary color, then a small "Translated from Japanese" caption
/// whose menu hides it or translates it again. Shows nothing until the line
/// is translated, or once its message is deleted.
struct MessageTranslationView: View {
    @Environment(TranslationStore.self) private var store
    let line: ChatLine

    var body: some View {
        if !line.isRedacted, let state = store.state(for: line.id), state.isShowing {
            TranslationContent(line: line, state: state)
        }
    }
}

private struct TranslationContent: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let line: ChatLine
    let state: LineTranslationState

    var body: some View {
        switch state {
        case .translating(let source):
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("Translating from \(source.translationDisplayName())…")
            }
            .font(captionFont)
            .foregroundStyle(theme[ThemeKey.chatTimestamp])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Translating from \(source.translationDisplayName())")
        case .translated(let text, let source):
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(style.bodyFont)
                    .italic(line.kind == .action)
                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                    .lineSpacing(style.lineSpacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Translated from \(source.translationDisplayName()): \(text)")
                    .accessibilityActions { TranslationOptions(line: line) }
                TranslationCaption(line: line, title: "Translated from \(source.translationDisplayName())", systemImage: "translate")
            }
        case .failed(let reason, let source):
            TranslationCaption(
                line: line,
                title: "Couldn't translate from \(source.translationDisplayName())",
                systemImage: "exclamationmark.triangle",
                detail: reason
            )
        case .hidden:
            EmptyView()
        }
    }

    private var captionFont: Font { style.font(size: max(9, style.fontSize - 2.5)) }
}

/// "Translated from Japanese ⌄": a quiet caption that opens the
/// translation's menu.
private struct TranslationCaption: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let line: ChatLine
    let title: String
    let systemImage: String
    var detail: String?

    @State private var hovering = false

    var body: some View {
        Menu {
            TranslationOptions(line: line)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: max(7, style.fontSize - 6), weight: .semibold))
                    .opacity(hovering ? 1 : 0.6)
            }
            .font(style.font(size: max(9, style.fontSize - 2.5)))
            .foregroundStyle(theme[hovering ? ThemeKey.chatSecondaryForeground : ThemeKey.chatTimestamp])
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(detail ?? title)
        .accessibilityLabel(detail.map { "\(title). \($0)" } ?? title)
        .accessibilityHint("Shows translation options")
    }
}

/// Hide Translation and Translate Again (Try Again after a failure), for
/// the caption's menu and VoiceOver.
private struct TranslationOptions: View {
    @Environment(TranslationStore.self) private var store
    @Environment(\.translationContext) private var context
    @Environment(MessageListController.self) private var controller
    let line: ChatLine

    var body: some View {
        let failed = if case .failed = store.state(for: line.id) { true } else { false }
        Button(failed ? "Try Again" : "Translate Again") {
            guard let context else { return }
            store.translateAgain(line, in: controller.buffer, context: context)
        }
        .disabled(context == nil)
        Button("Hide Translation") { store.hide(line.id) }
    }
}

// MARK: Message menus

/// "Translate" (or "Hide Translation") in a message's context menu and its
/// hover "More" menu. Only for other people's lines detected in another
/// language than the one translated into.
struct TranslationMessageMenuItems: View {
    @Environment(TranslationStore.self) private var store
    @Environment(\.translationContext) private var context
    @Environment(MessageListController.self) private var controller
    let line: ChatLine

    var body: some View {
        if let context, !line.isRedacted {
            if store.state(for: line.id)?.isShowing == true {
                Button {
                    store.hide(line.id)
                } label: {
                    Label("Hide Translation", systemImage: "translate")
                }
            } else if let source = store.offer(for: line, in: controller.buffer, context: context) {
                Button {
                    store.translate(line, from: source, context: context)
                } label: {
                    Label("Translate", systemImage: "translate")
                }
            }
        }
    }
}

/// The same, as VoiceOver actions on the message. Like menu content, it's
/// only built when asked for, so rows don't detect languages up front.
struct TranslationAccessibilityActions: View {
    let line: ChatLine

    var body: some View {
        TranslationMessageMenuItems(line: line)
    }
}

// MARK: Automatic translation

extension View {
    /// Translates `line` when it appears in a buffer that translates
    /// automatically, or when the buffer starts to. Rows only exist near
    /// the visible part of the list, so this never reaches far back into
    /// history. Also tells the store which rows are on screen (a new target
    /// redoes only those at once) and drops the translation of a message
    /// that gets deleted.
    func autoTranslation(for line: ChatLine) -> some View {
        modifier(AutoTranslationModifier(line: line))
    }
}

private struct AutoTranslationModifier: ViewModifier {
    @Environment(TranslationStore.self) private var store
    @Environment(\.translationContext) private var context
    @Environment(MessageListController.self) private var controller
    let line: ChatLine

    func body(content: Content) -> some View {
        content
            .onChange(of: context?.isAutomatic == true ? context : nil, initial: true) { _, context in
                guard let context else { return }
                store.autoTranslate(line, in: controller.buffer, context: context)
            }
            .onAppear { store.rowAppeared(line, context: context) }
            .onDisappear { store.rowDisappeared(line.id) }
            .onChange(of: line.isRedacted) { _, redacted in
                if redacted { store.forget(line.id) }
            }
    }
}
