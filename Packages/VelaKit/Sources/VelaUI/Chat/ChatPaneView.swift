// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// The center column: header (or title-bar tabs), optional tab stacks,
/// scrollback, typing line and input. Tab stacks live here rather than in
/// the per-buffer views so they persist while switching buffers.
struct ChatColumnView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.chatStyle) private var style
    @Environment(\.theme) private var theme

    var body: some View {
        let usesTabs = style.navigationStyle == .tabs
        let buffer = app.selectedBuffer
        let session = app.selectedSession

        VStack(spacing: 0) {
            if usesTabs && style.tabPlacement == .titleBar {
                TabStackView(placement: .titleBar)
            } else if let buffer, let session {
                ChatHeaderView(buffer: buffer, session: session)
            } else {
                Color.clear.frame(height: 52).gesture(WindowDragGesture())
            }

            if usesTabs && style.tabPlacement == .top {
                TabStackView(placement: .top)
            }

            if let buffer, let session {
                MessageListView(buffer: buffer, session: session)
                    .id(buffer.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                TypingIndicatorView(buffer: buffer)
                    .id(buffer.id)
                if usesTabs && style.tabPlacement == .bottom {
                    TabStackView(placement: .bottom)
                }
                InputBar(buffer: buffer, session: session)
                    .id(buffer.id)
            } else {
                EmptyStateView()
                if usesTabs && style.tabPlacement == .bottom {
                    TabStackView(placement: .bottom)
                }
            }
        }
        .background(theme[ThemeKey.chatBackground])
    }
}

/// Points the title strip must leave free for the traffic-light buttons when
/// nothing (or only the rail) sits to its left.
@MainActor
func trafficLightInset(style: ChatStyle, sidebarCollapsed: Bool) -> CGFloat {
    // With tabs there's no sidebar, so the traffic lights sit over this strip.
    // With the rail they stack vertically inside it; with the sidebar they sit
    // in its title strip — either way the header needs only its normal margin.
    style.navigationStyle == .tabs ? 80 : 16
}

/// The themed title strip. It doubles as the window's drag area, since the
/// system title bar is hidden.
struct ChatHeaderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let buffer: BufferModel
    let session: NetworkSession

    @State private var showTopic = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(BufferTitle.title(for: buffer, in: session))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.titleBarForeground])
                        .lineLimit(1)
                    if buffer.kind == .channel {
                        Text("\(buffer.memberCount)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(theme[ThemeKey.titleBarSecondaryForeground])
                            .help("\(buffer.memberCount) members")
                    }
                    ConnectionPill(session: session)
                }
                if let subtitle = BufferTitle.subtitle(for: buffer, in: session) {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme[ThemeKey.titleBarSecondaryForeground])
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(subtitle)
                        .onTapGesture { if buffer.topic != nil { showTopic.toggle() } }
                        .popover(isPresented: $showTopic, arrowEdge: .bottom) {
                            TopicPopover(topic: buffer.topic ?? "", setBy: buffer.topicSetBy)
                        }
                }
            }
            Spacer(minLength: 8)
            HeaderAccessoryButtons(buffer: buffer, session: session, showsTopicButton: false)
        }
        .padding(.leading, trafficLightInset(style: style, sidebarCollapsed: app.settings[.sidebarCollapsed]))
        .padding(.trailing, 12)
        .frame(height: 52)
        .background(theme[ThemeKey.titleBarBackground])
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme[ThemeKey.titleBarBorder]).frame(height: 1)
        }
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }
}

/// Buffer title/subtitle text shared by the header and the tab stacks.
enum BufferTitle {
    @MainActor
    static func title(for buffer: BufferModel, in session: NetworkSession) -> String {
        buffer.kind == .server ? session.displayName : buffer.name
    }

    @MainActor
    static func subtitle(for buffer: BufferModel, in session: NetworkSession) -> String? {
        switch buffer.kind {
        case .channel:
            buffer.topic.map { IRCFormatting.strip($0) } ?? (buffer.isJoined ? "No topic" : "Not joined")
        case .query:
            buffer.member(named: buffer.name)?.userHost ?? session.displayName
        case .server:
            "\(session.config.host):\(session.config.port)\(session.config.useTLS ? " · TLS" : "")"
        }
    }
}

/// Media toggle, member-list toggle and (in title-bar tab mode) a topic button.
struct HeaderAccessoryButtons: View {
    @Environment(AppModel.self) private var app
    let buffer: BufferModel
    let session: NetworkSession
    var showsTopicButton: Bool

    @State private var showTopic = false

    var body: some View {
        let settings = app.settings
        HStack(spacing: 2) {
            if showsTopicButton, buffer.kind == .channel {
                IconButton(systemImage: "info.circle", help: "Topic and channel info") { showTopic.toggle() }
                    .popover(isPresented: $showTopic, arrowEdge: .bottom) {
                        TopicPopover(topic: buffer.topic ?? "No topic", setBy: buffer.topicSetBy)
                    }
            }
            if buffer.kind != .server {
                let enabled = app.isMediaEnabled(for: buffer.id)
                IconButton(
                    systemImage: enabled ? "photo.on.rectangle" : "photo.on.rectangle.angled",
                    help: enabled ? "Disable inline media in \(buffer.name)" : "Enable inline media in \(buffer.name)",
                    isActive: !enabled
                ) {
                    app.setMediaEnabled(!enabled, for: buffer.id)
                }
            }
            if buffer.kind == .channel {
                IconButton(
                    systemImage: "person.2",
                    help: settings[.memberListVisible] ? "Hide Member List" : "Show Member List",
                    isActive: settings[.memberListVisible]
                ) {
                    settings[.memberListVisible].toggle()
                }
            }
        }
    }
}

/// Connection status shown next to the buffer title when not connected.
struct ConnectionPill: View {
    @Environment(\.theme) private var theme
    let session: NetworkSession

    var body: some View {
        switch session.connectionState {
        case .connected:
            EmptyView()
        case .connecting, .registering:
            label("Connecting…", systemImage: "arrow.triangle.2.circlepath", key: ThemeKey.titleBarSecondaryForeground)
        case .disconnected:
            label("Offline", systemImage: "bolt.horizontal.circle", key: ThemeKey.chatError)
        }
    }

    private func label(_ text: String, systemImage: String, key: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme[key])
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme[key].opacity(0.12)))
    }
}

struct TopicPopover: View {
    @Environment(\.theme) private var theme
    let topic: String
    let setBy: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(IRCFormatting.strip(topic))
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.popoverForeground])
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let setBy {
                Text("Set by \(setBy)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(theme[ThemeKey.popoverBackground])
    }
}
