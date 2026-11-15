// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// The main window: sidebar | chat | member list, all drawn with theme
/// tokens. A custom split (not NavigationSplitView) keeps the system glass
/// sidebar from overriding the theme; themes can opt back into vibrancy.
struct MainWindowView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.chatStyle) private var style

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
                    edge: .trailing
                ) { settings[.memberListWidth] = $0 }
                MemberListView(buffer: buffer, session: session)
                    .frame(width: settings[.memberListWidth])
                    .transition(.move(edge: .trailing))
            }
        }
        .background(theme[ThemeKey.windowBackground])
        .background(WindowConfigurator(theme: theme))
        .ignoresSafeArea()
        .frame(minWidth: 640, minHeight: 420)
        .animation(.snappy(duration: 0.2), value: showMembers)
        .animation(.snappy(duration: 0.2), value: style.navigationStyle)
        .onChange(of: appearsActive, initial: true) { _, active in
            app.isWindowActive = active
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

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = theme.vibrancy != .window
        window.backgroundColor = theme.vibrancy == .window ? .clear : theme.color(ThemeKey.windowBackground).nsColor
        window.appearance = NSAppearance(named: theme.kind == .dark ? .darkAqua : .aqua)
        window.tabbingMode = .disallowed
    }
}

/// A themed 1-pt divider with a wider invisible grab area for resizing.
struct PaneDivider: View {
    @Environment(\.theme) private var theme
    let width: Double
    let range: ClosedRange<Double>
    /// The side of the divider the resized pane is on.
    let edge: HorizontalEdge
    let onChange: (Double) -> Void

    @State private var dragStartWidth: Double?

    var body: some View {
        Rectangle()
            .fill(theme[ThemeKey.paneDivider])
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
        .gesture(WindowDragGesture())
    }
}
