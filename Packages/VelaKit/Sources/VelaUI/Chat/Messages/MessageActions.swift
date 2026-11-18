// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

/// Slack-style actions floating at the top-right of the hovered message.
struct MessageHoverToolbar: View {
    @Environment(\.theme) private var theme
    @Environment(MessageListController.self) private var controller
    @Environment(UIState.self) private var uiState
    let line: ChatLine
    let links: [URL]
    @Binding var isPickerOpen: Bool

    var body: some View {
        HStack(spacing: 0) {
            if controller.canReact(to: line) {
                ForEach(EmojiRecents.frequent(count: 3), id: \.self) { emoji in
                    ToolbarButton(help: "React with \(emoji)") {
                        controller.addReaction(emoji, to: line)
                    } label: {
                        Text(emoji).font(.system(size: 14))
                    }
                }
                ToolbarButton(help: "Add Reaction") {
                    isPickerOpen.toggle()
                } label: {
                    Image(systemName: "face.smiling")
                }
                .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
                    EmojiPickerView { controller.addReaction($0, to: line) }
                }
            }
            if controller.canReply(to: line) {
                ToolbarButton(help: "Reply") {
                    controller.reply(to: line, uiState: uiState)
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                }
            }
            Menu {
                MessageMenuItems(line: line, links: links, includesReactions: false)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme[ThemeKey.popoverForeground])
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More actions")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme[ThemeKey.popoverBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme[ThemeKey.popoverBorder], lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 5, y: 2)
    }

    private var shadowColor: Color {
        theme.kind == .dark
            ? theme[ThemeKey.windowBackground].opacity(0.5)
            : theme[ThemeKey.popoverBorder].opacity(0.7)
    }
}

private struct ToolbarButton<Label: View>: View {
    @Environment(\.theme) private var theme
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme[ThemeKey.popoverForeground])
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? theme[ThemeKey.chatHoverBackground] : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Items shared by the "More" menu and the right-click context menu.
struct MessageMenuItems: View {
    @Environment(MessageListController.self) private var controller
    @Environment(UIState.self) private var uiState
    let line: ChatLine
    let links: [URL]
    var includesReactions = true

    var body: some View {
        if includesReactions, controller.canReact(to: line) {
            Menu {
                ForEach(EmojiRecents.frequent(count: 8), id: \.self) { emoji in
                    Button(emoji) { controller.addReaction(emoji, to: line) }
                }
            } label: {
                Label("Add Reaction", systemImage: "face.smiling")
            }
        }
        if includesReactions, controller.canReply(to: line) {
            Button {
                controller.reply(to: line, uiState: uiState)
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
        if includesReactions, controller.canReact(to: line) || controller.canReply(to: line) {
            Divider()
        }
        TranslationMessageMenuItems(line: line)
        if !line.isRedacted {
            Button {
                controller.copyText(of: line)
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
        if let link = links.first, !line.isRedacted {
            Button {
                // The link that was right-clicked, else the first.
                let copied = LinkClickMonitor.shared.contextLink(among: links) ?? link
                controller.copyToPasteboard(copied.absoluteString)
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        }
        if let nick = line.nick {
            Button {
                controller.copyToPasteboard(nick)
            } label: {
                Label("Copy Nick", systemImage: "person.text.rectangle")
            }
            if !line.isSelf {
                Divider()
                Button {
                    controller.message(nick)
                } label: {
                    Label("Message \(nick)", systemImage: "bubble.left")
                }
                Button {
                    controller.whois(nick)
                } label: {
                    Label("Whois \(nick)", systemImage: "person.crop.circle.badge.questionmark")
                }
                .disabled(!controller.session.isConnected)
            } else {
                Divider()
            }
            // Everything else you can do to them: the user menu.
            Menu {
                NickUserMenu(nick: nick, userHost: line.userHost)
            } label: {
                Label(nick, systemImage: "person")
            }
        }
        if controller.canDelete(line) {
            Divider()
            Button(role: .destructive) {
                controller.confirmDelete(line)
            } label: {
                Label("Delete Message", systemImage: "trash")
            }
        }
    }
}
