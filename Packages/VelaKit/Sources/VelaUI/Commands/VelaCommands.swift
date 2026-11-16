// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// The app's menu bar: File, View, Theme, Go and Network.
///
/// Menu contents live in small `View`s so they observe `AppModel`,
/// `SettingsStore` and `ThemeStore` and keep titles, checkmarks and enabled
/// states current.
struct VelaCommands: Commands {
    let app: AppModel
    let themeStore: ThemeStore
    let uiState: UIState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            FileMenuItems(app: app, uiState: uiState)
        }

        CommandGroup(replacing: .sidebar) {
            ViewMenuItems(app: app)
        }

        CommandMenu("Theme") {
            ThemeMenuItems(app: app, themeStore: themeStore)
        }

        CommandMenu("Go") {
            GoMenuItems(app: app, uiState: uiState)
        }

        CommandMenu("Network") {
            NetworkMenuItems(app: app, uiState: uiState)
        }
    }
}

// MARK: - File

private struct FileMenuItems: View {
    let app: AppModel
    let uiState: UIState

    var body: some View {
        Button("Add Network…") { uiState.networkEditor = .new }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        let target = joinTarget
        Button("Join Channel…") {
            if let target { uiState.joinChannelNetwork = target.id }
        }
        .keyboardShortcut("j", modifiers: .command)
        .disabled(target == nil)
    }

    /// The selected network, when it's connected and can join channels.
    private var joinTarget: NetworkSession? {
        guard let session = app.selectedSession, session.isConnected, !session.isBouncerControl else { return nil }
        return session
    }
}

// MARK: - View

private struct ViewMenuItems: View {
    let app: AppModel

    var body: some View {
        let settings = app.settings
        let usesSidebar = settings[.navigationStyle] == .sidebar

        Button(settings[.sidebarCollapsed] ? "Expand Sidebar" : "Collapse Sidebar") {
            settings[.sidebarCollapsed].toggle()
        }
        .keyboardShortcut("s", modifiers: [.control, .command])
        .disabled(!usesSidebar)

        Button(settings[.memberListVisible] ? "Hide Member List" : "Show Member List") {
            settings[.memberListVisible].toggle()
        }
        .keyboardShortcut("m", modifiers: [.option, .command])

        Divider()

        Picker("Navigation", selection: binding(.navigationStyle)) {
            Text("Sidebar").tag(NavigationStyle.sidebar)
            Text("Tabs").tag(NavigationStyle.tabs)
        }

        Picker("Message Layout", selection: binding(.chatLayout)) {
            Text("Classic").tag(ChatLayout.classic)
            Text("Modern Grouped").tag(ChatLayout.grouped)
            Text("Compact Columns").tag(ChatLayout.columns)
        }

        Picker("Presets", selection: presetBinding) {
            ForEach(SettingsPreset.all) { preset in
                Label(preset.name, systemImage: preset.systemImage).tag(preset.id)
            }
        }

        Divider()

        let size = settings[.chatFontSize]
        Button("Bigger") { setFontSize(size + 1) }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(size >= Self.fontSizes.upperBound)
        Button("Smaller") { setFontSize(size - 1) }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(size <= Self.fontSizes.lowerBound)
        Button("Actual Size") { settings.reset(.chatFontSize) }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(size == SettingKey<Double>.chatFontSize.defaultValue)
    }

    static let fontSizes: ClosedRange<Double> = 9...28

    private func setFontSize(_ size: Double) {
        app.settings[.chatFontSize] = min(Self.fontSizes.upperBound, max(Self.fontSizes.lowerBound, size.rounded()))
    }

    private func binding<Value: Equatable>(_ key: SettingKey<Value>) -> Binding<Value> {
        let settings = app.settings
        return Binding(get: { settings[key] }, set: { settings[key] = $0 })
    }

    /// The matching preset's id, or `""` (no checkmark) for a custom setup.
    private var presetBinding: Binding<String> {
        let settings = app.settings
        return Binding(
            get: { settings.matchingPreset()?.id ?? "" },
            set: { id in
                guard let preset = SettingsPreset.all.first(where: { $0.id == id }) else { return }
                settings.apply(preset)
            }
        )
    }
}

// MARK: - Go

private struct GoMenuItems: View {
    let app: AppModel
    let uiState: UIState

    var body: some View {
        let hasBuffers = !app.sessions.isEmpty
        Button("Previous Buffer") { app.selectAdjacentBuffer(forward: false) }
            .keyboardShortcut(.upArrow, modifiers: [.option, .command])
            .disabled(!hasBuffers)
        Button("Next Buffer") { app.selectAdjacentBuffer(forward: true) }
            .keyboardShortcut(.downArrow, modifiers: [.option, .command])
            .disabled(!hasBuffers)

        Divider()

        Button("Previous Unread") { app.selectAdjacentBuffer(forward: false, unreadOnly: true) }
            .keyboardShortcut(.upArrow, modifiers: [.shift, .option, .command])
            .disabled(!hasUnread)
        Button("Next Unread") { app.selectAdjacentBuffer(forward: true, unreadOnly: true) }
            .keyboardShortcut(.downArrow, modifiers: [.shift, .option, .command])
            .disabled(!hasUnread)

        Divider()

        Button("Focus Input") { uiState.focusInput() }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(app.selectedBuffer == nil)
    }

    private var hasUnread: Bool {
        app.orderedBuffers.contains { $0.id != app.selectedBufferID && ($0.unreadCount > 0 || $0.highlightCount > 0) }
    }
}

// MARK: - Network

private struct NetworkMenuItems: View {
    let app: AppModel
    let uiState: UIState

    var body: some View {
        let session = app.selectedSession
        let state = session?.connectionState

        Button(session.map { "Connect to \($0.displayName)" } ?? "Connect") { session?.connect() }
            .disabled(state != .disconnected)
        Button("Disconnect") { session?.disconnect() }
            .disabled(state == nil || state == .disconnected)
        Button("Reconnect") { session?.reconnect() }
            .disabled(session == nil)

        Divider()

        Button("Edit Network…") {
            if let session { uiState.networkEditor = .existing(session.config.parentNetworkID ?? session.id) }
        }
        .disabled(session == nil)
        Button("Remove Network…") {
            if let session { uiState.networkPendingRemoval = session.config.parentNetworkID ?? session.id }
        }
        .disabled(session == nil)
    }
}
