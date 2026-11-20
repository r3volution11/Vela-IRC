// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

/// The panes of the Settings window, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case presets
    case appearance
    case layout
    case messages
    case media
    case networks
    case notifications
    case intelligence
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presets: "Presets"
        case .appearance: "Appearance"
        case .layout: "Layout"
        case .messages: "Messages"
        case .media: "Media"
        case .networks: "Networks"
        case .notifications: "Notifications"
        case .intelligence: "Apple Intelligence"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .presets: "sparkles.rectangle.stack"
        case .appearance: "paintpalette"
        case .layout: "rectangle.split.3x1"
        case .messages: "text.bubble"
        case .media: "photo.on.rectangle.angled"
        case .networks: "network"
        case .notifications: "bell.badge"
        case .intelligence: "apple.intelligence"
        case .advanced: "gearshape.2"
        }
    }

    /// Sidebar groups; a gap is drawn between them.
    static let groups: [[SettingsPane]] = [
        [.presets],
        [.appearance, .layout, .messages, .media],
        [.networks, .notifications, .intelligence],
        [.advanced],
    ]
}

/// The Settings window: a themed pane list on the left and a scrolling,
/// themed content area on the right. Every control writes settings.json
/// immediately, so changes apply live in the main window.
struct SettingsRootView: View {
    @Environment(\.theme) private var theme
    @Environment(UIState.self) private var uiState
    @State private var selection: SettingsPane

    private static let paneDefaultsKey = "Vela.settingsPane"

    init(initialPane: SettingsPane? = nil) {
        let saved = UserDefaults.standard.string(forKey: Self.paneDefaultsKey).flatMap(SettingsPane.init(rawValue:))
        _selection = State(initialValue: initialPane ?? saved ?? .presets)
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
                .frame(width: 200)
            SettingsHairline(vertical: true)
                .ignoresSafeArea()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selection)
        }
        .themedWindowBorder()
        .background(theme[ThemeKey.settingsBackground])
        .background(ThemedWindowConfigurator(theme: theme, title: "\(selection.title) — Vela Settings"))
        .frame(minWidth: 720, idealWidth: 820, maxWidth: .infinity, minHeight: 480, idealHeight: 600, maxHeight: .infinity)
        .onChange(of: selection) { _, pane in
            UserDefaults.standard.set(pane.rawValue, forKey: Self.paneDefaultsKey)
        }
        // The palette's "Settings: Search…", the sidebar search and "Show
        // in settings editor" links ask for a pane through shared state.
        .onChange(of: uiState.settingsEditor.requestedPane, initial: true) { _, pane in
            guard let pane else { return }
            selection = pane
            uiState.settingsEditor.requestedPane = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        let navigate: (SettingsPane) -> Void = { pane in selection = pane }
        switch selection {
        case .presets: PresetsPane(navigate: navigate)
        case .appearance: AppearancePane(navigate: navigate)
        case .layout: LayoutPane()
        case .messages: MessagesPane()
        case .media: MediaPane()
        case .networks: NetworksPane()
        case .notifications: NotificationsPane()
        case .intelligence: IntelligencePane(navigate: navigate)
        case .advanced: AdvancedPane()
        }
    }
}

/// The custom pane list with a search field on top. Arrow keys move the
/// selection when the list has focus.
private struct SettingsSidebar: View {
    @Environment(\.theme) private var theme
    @Environment(UIState.self) private var uiState
    @Binding var selection: SettingsPane

    var body: some View {
        let editor = uiState.settingsEditor
        VStack(alignment: .leading, spacing: 12) {
            // Typing searches every setting in Advanced; focus stays here,
            // and Return moves it to the results' search field.
            ThemedSuggestionField(
                text: Binding(get: { editor.query }, set: { editor.searchFromSidebar($0) }),
                placeholder: "Search",
                accessibilityLabel: "Search all settings",
                leadingSystemImage: "magnifyingglass",
                onSubmit: { editor.showInEditor(editor.query) },
                onCancel: {
                    guard !editor.query.isEmpty else { return false }
                    editor.query = ""
                    return true
                }
            )
            .help("Search every setting. Results show in Advanced.")
            .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(SettingsPane.groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        Spacer().frame(height: 12)
                    }
                    ForEach(group) { pane in
                        SettingsSidebarItem(pane: pane, isSelected: pane == selection) {
                            selection = pane
                        }
                    }
                }
                Spacer(minLength: 12)
                Text("Vela \(AppModel.appVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .padding(.horizontal, 10)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity, alignment: .top)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { move(by: -1) }
            .onKeyPress(.downArrow) { move(by: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings sections")
        }
        .background { sectionShortcuts }
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme[ThemeKey.settingsSidebarBackground])
    }

    /// ⌘[ / ⌘]: the previous or next section, wherever the focus is in
    /// Settings, like the arrows in the list.
    private var sectionShortcuts: some View {
        ZStack {
            Button("Previous Section") { _ = move(by: -1) }
                .keyboardShortcut("[", modifiers: .command)
            Button("Next Section") { _ = move(by: 1) }
                .keyboardShortcut("]", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func move(by offset: Int) -> KeyPress.Result {
        let panes = SettingsPane.allCases
        guard let index = panes.firstIndex(of: selection) else { return .ignored }
        let next = min(panes.count - 1, max(0, index + offset))
        selection = panes[next]
        return .handled
    }
}

private struct SettingsSidebarItem: View {
    @Environment(\.theme) private var theme
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? theme[ThemeKey.accentForeground] : theme[ThemeKey.accent])
                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme[ThemeKey.accentForeground] : theme[ThemeKey.settingsForeground])
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(pane.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var background: Color {
        if isSelected { return theme[ThemeKey.accent] }
        if isHovered { return theme[ThemeKey.settingsForeground].opacity(0.07) }
        return .clear
    }
}
