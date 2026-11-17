// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// The main window: sidebar | chat | member list, all drawn with theme
/// tokens. A custom split (not NavigationSplitView) keeps the system glass
/// sidebar from overriding the theme; themes can opt back into vibrancy.
struct MainWindowView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.theme) private var theme
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.chatStyle) private var style

    /// Stacked vertically inside the narrow rail, side by side whenever the
    /// sidebar (or the hover-expanded rail) is wide enough.
    private var trafficLightLayout: TrafficLightLayout {
        let usesRail = style.navigationStyle == .sidebar
            && app.settings[.sidebarCollapsed]
            && !uiState.isRailHoverExpanded
        return usesRail ? .vertical(columnWidth: SidebarMetrics.railWidth) : .horizontal(stripHeight: 52)
    }

    var body: some View {
        @Bindable var uiState = uiState
        let settings = app.settings
        let selectedBuffer = app.selectedBuffer
        let showMembers = settings[.memberListVisible] && selectedBuffer?.kind == .channel

        HStack(spacing: 0) {
            if style.navigationStyle == .sidebar {
                SidebarContainer()
            }

            ChatColumnView()
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

            if showMembers, let buffer = selectedBuffer, let session = app.selectedSession {
                PaneDivider(
                    width: settings[.memberListWidth],
                    range: 120...320,
                    edge: .trailing,
                    colorKey: ThemeKey.memberListBorder
                ) { settings[.memberListWidth] = $0 }
                MemberListView(buffer: buffer, session: session)
                    .frame(width: settings[.memberListWidth])
                    .transition(.move(edge: .trailing))
            }
        }
        // An expanded video fills the window, below the command palette.
        .overlay {
            ExpandedVideoOverlay()
        }
        .overlay(alignment: .top) {
            if let mode = uiState.commandPalette {
                CommandPaletteView(mode: mode)
                    .id(mode)
            }
        }
        .background(theme[ThemeKey.windowBackground])
        .background(WindowConfigurator(theme: theme, trafficLights: trafficLightLayout))
        .ignoresSafeArea()
        .frame(minWidth: 640, minHeight: 420)
        .animation(.snappy(duration: 0.2), value: showMembers)
        .animation(.snappy(duration: 0.2), value: style.navigationStyle)
        .onChange(of: appearsActive, initial: true) { _, active in
            app.isWindowActive = active
        }
        // Switching conversations pauses (and un-expands) videos; closing
        // the window stops them.
        .onChange(of: app.selectedBufferID) { _, _ in
            // The expanded player had the keyboard focus.
            if EmbedPlayerStore.shared.selectedBufferChanged() { uiState.focusInput() }
        }
        // A Catch me up card lasts while its buffer is on screen; leaving
        // or closing the buffer closes it (the summary stays cached).
        .onChange(of: app.selectedBufferID, initial: true) { _, selected in
            intelligence.catchUp.dismissAll(except: selected)
        }
        .onDisappear {
            EmbedPlayerStore.shared.stopAll()
        }
        .sheet(item: $uiState.networkEditor) { target in
            NetworkEditorView(target: target)
        }
        .sheet(item: $uiState.joinChannelNetwork) { networkID in
            JoinChannelSheet(networkID: networkID)
        }
        .confirmationDialog(
            "Remove \(uiState.networkPendingRemoval.flatMap { app.session(for: $0)?.displayName } ?? "network")?",
            isPresented: Binding(
                get: { uiState.networkPendingRemoval != nil },
                set: { if !$0 { uiState.networkPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Network", role: .destructive) {
                if let id = uiState.networkPendingRemoval { app.removeNetwork(id: id) }
                uiState.networkPendingRemoval = nil
            }
        } message: {
            Text("Its settings, saved passwords and message history on this Mac will be deleted.")
        }
    }
}

/// Applies theme-driven window chrome: transparent title bar, background
/// color and light/dark appearance for system-drawn controls.
struct WindowConfigurator: NSViewRepresentable {
    let theme: ResolvedTheme
    var trafficLights: TrafficLightLayout = .horizontal(stripHeight: 52)

    func makeCoordinator() -> TrafficLightPositioner { TrafficLightPositioner() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let positioner = context.coordinator
        let layout = trafficLights
        DispatchQueue.main.async {
            configure(view.window)
            if let window = view.window {
                positioner.update(layout)
                positioner.attach(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
        context.coordinator.update(trafficLights)
        if let window = nsView.window { context.coordinator.attach(to: window) }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: TrafficLightPositioner) {
        coordinator.detach()
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        WindowChrome.apply(
            to: window,
            backgroundColor: theme.vibrancy == .window ? .clear : theme.color(ThemeKey.windowBackground).nsColor,
            isOpaque: theme.vibrancy != .window,
            appearanceName: theme.appearanceName
        )
    }
}

/// A themed 1-pt divider with a wider invisible grab area for resizing.
struct PaneDivider: View {
    @Environment(\.theme) private var theme
    let width: Double
    let range: ClosedRange<Double>
    /// The side of the divider the resized pane is on.
    let edge: HorizontalEdge
    var colorKey: String = ThemeKey.paneDivider
    let onChange: (Double) -> Void

    @State private var dragStartWidth: Double?

    var body: some View {
        Rectangle()
            .fill(theme[colorKey])
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .pointerStyle(.frameResize(position: edge == .leading ? .trailing : .leading))
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStartWidth ?? width
                                if dragStartWidth == nil { dragStartWidth = width }
                                let delta = edge == .leading ? value.translation.width : -value.translation.width
                                onChange(min(range.upperBound, max(range.lowerBound, start + delta)))
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
            .zIndex(1)
    }
}

/// Shown when no buffer is selected (first launch).
struct EmptyStateView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sailboat")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme[ThemeKey.accent])
            Text(app.sessions.isEmpty ? "Welcome to Vela" : "Pick a conversation")
                .font(style.font(size: 22, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.chatForeground])
            Text(app.sessions.isEmpty
                 ? "Add an IRC network or bouncer to get started."
                 : "Choose a channel or conversation from the sidebar.")
                .font(style.bodyFont)
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
            if app.sessions.isEmpty {
                Button("Add Network…") { uiState.networkEditor = .new }
                    .buttonStyle(ThemedButtonStyle(prominent: true))
                    .padding(.top, 6)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .windowTitleBarArea()
    }
}
