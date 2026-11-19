// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Vivaldi-style two-level tab stacks: a row of networks (hidden in `auto`
/// mode with a single network) and the selected network's server console,
/// channels and queries.
///
/// `placement` decides the chrome:
/// - `.titleBar` replaces the title strip. Networks become a compact
///   segmented group next to the traffic lights, the channel tabs follow,
///   and the header's accessory buttons (with a topic popover) sit trailing.
///   Empty space drags the window.
/// - `.top` sits under the header; the selected channel tab merges into the
///   conversation below it like a browser tab.
/// - `.bottom` sits above the input, with tabs hanging from the conversation.
///
/// Pill roundness (≥ 0.8) switches the strip to free-standing pills, since a
/// pill can't attach to an edge.
struct TabStackView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.chatStyle) private var style
    let placement: TabStackPlacement

    @State private var interaction = TabInteraction()

    var body: some View {
        let session = app.selectedSession ?? app.sessions.first
        let showsServers = style.serverTabRow == .always || app.sessions.count > 1

        Group {
            switch placement {
            case .titleBar:
                TitleBarTabStack(session: session, showsServers: showsServers)
            case .top, .bottom:
                if let session {
                    StripTabStack(placement: placement, session: session, showsServers: showsServers)
                }
            }
        }
        .environment(interaction)
        .background { TabShortcutButtons(session: session) }
        .onChange(of: app.selectedBufferID, initial: true) { _, id in
            TabMemory.record(id)
        }
        .onAppear {
            interaction.installMiddleClickMonitor { [app] key in
                TabActions.middleClick(key, app: app)
            }
        }
        .onDisappear { interaction.removeMiddleClickMonitor() }
    }
}

/// `tabs.placement = titleBar`: the whole stack lives in the title strip.
private struct TitleBarTabStack: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let session: NetworkSession?
    let showsServers: Bool

    var body: some View {
        let tabHeight = TabMetrics.channelHeight(style)
        let barHeight = max(52, tabHeight + 20)
        let palette = TabPalette.channels(on: .titleBar, appearance: .floating)

        HStack(spacing: 8) {
            if showsServers {
                ServerTabRow(surface: .titleBar, isSegmented: true, tabHeight: tabHeight, rowHeight: barHeight)
                    .layoutPriority(1)
                Rectangle()
                    .fill(theme[palette.separator])
                    .frame(width: 1, height: (tabHeight * 0.6).rounded())
                    .accessibilityHidden(true)
            }
            if let session {
                ChannelTabRow(
                    session: session,
                    surface: .titleBar,
                    appearance: .floating,
                    showsNetworkName: !showsServers,
                    rowHeight: barHeight,
                    dragsWindow: true,
                    leadingInset: showsServers ? 0 : 2
                )
            } else {
                Spacer(minLength: 0)
                TabAddMenu(session: nil, height: tabHeight, palette: palette)
            }
            if let buffer = app.selectedBuffer, let selected = app.selectedSession {
                ConnectionPill(session: selected)
                HeaderAccessoryButtons(buffer: buffer, session: selected, showsTopicButton: true)
            }
        }
        .padding(.leading, trafficLightInset(style: style, sidebarCollapsed: app.settings[.sidebarCollapsed]))
        .padding(.trailing, 12)
        .frame(height: barHeight)
        .background {
            SurfaceFill(palette.background, on: .tabs)
                .windowTitleBarArea()
                .allowsWindowActivationEvents(true)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme[palette.border]).frame(height: 1)
        }
    }
}

/// `tabs.placement = top | bottom`: a strip between the header and the
/// conversation, or between the conversation and the input.
private struct StripTabStack: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let placement: TabStackPlacement
    let session: NetworkSession
    let showsServers: Bool

    var body: some View {
        let isTop = placement == .top
        // The edge facing the conversation.
        let conversationEdge: VerticalEdge = isTop ? .bottom : .top
        let isPill = style.tabRoundness >= 0.8
        let appearance: TabAppearance = isPill ? .floating : .attached(conversationEdge)
        let palette = TabPalette.channels(on: .strip, appearance: appearance)
        let channelHeight = TabMetrics.channelHeight(style)
        let serverHeight = TabMetrics.serverHeight(style)
        // Attached tabs touch the conversation; floating ones get even padding.
        let inset = max(4, (channelHeight * 0.2).rounded())
        let channelRowHeight = channelHeight + (isPill ? inset * 2 : inset)
        let serverRowHeight = serverHeight + max(6, (serverHeight * 0.3).rounded())

        VStack(spacing: 0) {
            if !isTop {
                channelRow(appearance: appearance, height: channelRowHeight)
            }
            if showsServers {
                ServerTabRow(surface: .strip, isSegmented: false, tabHeight: serverHeight, rowHeight: serverRowHeight)
                    .padding(isTop ? .top : .bottom, isPill ? 0 : 2)
                    .surfaceBackground(ThemeKey.tabServerBackground, on: .tabs)
            }
            if isTop {
                channelRow(appearance: appearance, height: channelRowHeight)
            }
        }
        // The conversation-side border sits under the tabs, so the selected
        // tab can cover it and open into the conversation.
        .background(alignment: isTop ? .bottom : .top) {
            Rectangle().fill(theme[palette.border]).frame(height: 1)
        }
        .surfaceBackground(palette.background, on: .tabs)
        .overlay(alignment: .bottom) {
            // Above the input, also close the strip off from the input bar.
            if !isTop {
                Rectangle().fill(theme[palette.border]).frame(height: 1)
            }
        }
    }

    private func channelRow(appearance: TabAppearance, height: CGFloat) -> some View {
        ChannelTabRow(
            session: session,
            surface: .strip,
            appearance: appearance,
            showsNetworkName: !showsServers,
            rowHeight: height
        )
    }
}
