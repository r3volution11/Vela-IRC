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
///
/// A row too long for its strip shrinks its unselected tabs to fit, and
/// only scrolls when they'd go below the minimum width (`TabStripLayout`).
///
/// It's the window's `.navigation` area with tabs: ⌥⌘1 or F6 put the
/// keyboard on the selected channel tab. ← and → select the tab beside it,
/// ↑ and ↓ go between the network and channel rows, and Return or Esc go
/// back to the message box.
struct TabStackView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.chatStyle) private var style
    let placement: TabStackPlacement

    @State private var interaction: TabInteraction

    init(placement: TabStackPlacement) {
        self.placement = placement
        _interaction = State(initialValue: TabInteraction(placement: placement))
    }

    var body: some View {
        let session = TabActions.shownSession(app: app)

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
        .background {
            KeyboardFocusArea(handle: interaction.keyboardFocus, onFocusChange: keyboardFocusChanged, onKey: handleKey)
        }
        .onChange(of: uiState.focusRequest, initial: true) { _, request in
            guard request?.area == .navigation else { return }
            uiState.takeFocusRequest(for: .navigation)
            interaction.keyboardFocus.focus()
        }
        .onAppear {
            interaction.installMiddleClickMonitor { [app, uiState] key in
                TabActions.middleClick(key, app: app, uiState: uiState)
            }
        }
        .onDisappear { interaction.removeMiddleClickMonitor() }
    }

    private var showsServers: Bool {
        style.serverTabRow == .always || app.sessions.count > 1
    }

    // MARK: Keyboard

    /// Told at once, before ← or → can select another tab and bring in its
    /// message box, which then leaves the focus here.
    private func keyboardFocusChanged(_ focused: Bool) {
        uiState.setFocused(.navigation, focused || interaction.hasKeyboardFocus)
        if focused {
            let row = interaction.nextKeyboardRow ?? .channels
            interaction.nextKeyboardRow = nil
            interaction.activeKeyboardRow = showsServers ? row : .channels
            announceRow()
        }
        // Drawn after this update: the focus can move in the middle of one.
        let row: TabKeyboardRow? = focused ? interaction.activeKeyboardRow : nil
        Task { @MainActor in interaction.keyboardRow = row }
    }

    private func handleKey(_ key: NavigationKey, at _: TimeInterval) -> Bool {
        let row = showsServers ? interaction.activeKeyboardRow : .channels
        switch key {
        case .left, .right, .home, .end:
            switch row {
            case .channels:
                guard let session = TabActions.shownSession(app: app) else { return true }
                let tabs = TabActions.tabs(of: session)
                let index = tabs.firstIndex { $0.id == app.selectedBufferID }
                guard let target = TabActions.keyboardTarget(key, from: index, count: tabs.count), target != index else { return true }
                app.select(tabs[target])
                KeyboardAnnouncement.post(TabDescriptions.spoken(tabs[target], in: session))
            case .networks:
                let sessions = app.sessions
                let index = sessions.firstIndex { $0.id == app.selectedBufferID?.networkID }
                guard let target = TabActions.keyboardTarget(key, from: index, count: sessions.count), target != index else { return true }
                TabActions.select(sessions[target], app: app)
                KeyboardAnnouncement.post(sessions[target].displayName)
            }
            return true
        case .up, .down:
            let next = TabActions.keyboardRow(after: row, up: key == .up, showsNetworks: showsServers, placement: placement)
            guard next != row else { return true }
            interaction.activeKeyboardRow = next
            interaction.keyboardRow = next
            announceRow()
            return true
        case .return, .escape:
            uiState.focusInput()
            return true
        case .pageUp, .pageDown, .space, .menu, .text:
            return false
        }
    }

    /// "Networks, Libera.Chat" or "Channels, #vela", for VoiceOver.
    private func announceRow() {
        switch interaction.activeKeyboardRow {
        case .networks:
            KeyboardAnnouncement.post(["Networks", app.selectedSession?.displayName].compactMap { $0 }.joined(separator: ", "))
        case .channels:
            let current = app.selectedBuffer.flatMap { buffer in app.selectedSession.map { TabDescriptions.spoken(buffer, in: $0) } }
            KeyboardAnnouncement.post(["Channels", current].compactMap { $0 }.joined(separator: ", "))
        }
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
