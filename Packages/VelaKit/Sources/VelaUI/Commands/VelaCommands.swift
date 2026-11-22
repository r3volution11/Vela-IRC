// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// The app's menu bar: File, View, Theme, Go and Network (and, in Vela Dev,
/// Developer).
///
/// Every item comes from ``VelaCommandCatalog``, which the command palette
/// lists too. Menu contents live in small `View`s so they observe
/// `AppModel`, `SettingsStore` and `ThemeStore` and keep titles, checkmarks
/// and enabled states current.
struct VelaCommands: Commands {
    let app: AppModel
    let themeStore: ThemeStore
    let uiState: UIState

    init(app: AppModel, themeStore: ThemeStore, uiState: UIState) {
        self.app = app
        self.themeStore = themeStore
        self.uiState = uiState
        AlternateShortcuts.installIfNeeded()
        PaletteHistory.shared.startTracking(app)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            CommandItems(app: app, themeStore: themeStore, uiState: uiState) { commands in
                CommandMenuButton(commands.addNetwork)
                CommandMenuButton(commands.joinChannel)
                Divider()
                CommandMenuButton(commands.reopenClosed)
                RecentlyClosedMenu(commands: commands)
                Divider()
                CommandMenuButton(commands.showChatLogs)
            }
        }

        // Vela → Settings…, then Search Settings….
        CommandGroup(after: .appSettings) {
            CommandItems(app: app, themeStore: themeStore, uiState: uiState) { commands in
                CommandMenuButton(commands.searchSettings)
            }
        }

        // File → Close Tab (⌘W) and Close Window (⇧⌘W), as in a browser.
        CommandGroup(replacing: .saveItem) {
            CommandItems(app: app, themeStore: themeStore, uiState: uiState) { commands in
                CloseMenuItems(commands: commands)
            }
        }

        // An IRC client has nothing to print; this also frees ⌘P and ⇧⌘P
        // (Print… and Page Setup…) for the palette.
        CommandGroup(replacing: .printItem) {}

        // Edit → Emoji… (⇧⌘E; Emoji & GIFs… while the picker has GIF
        // search, GIFAvailability.isOn(in:)), then Spelling and Grammar and
        // Substitutions (typing settings).
        CommandGroup(replacing: .textEditing) {
            CommandItems(app: app, themeStore: themeStore, uiState: uiState) { commands in
                CommandMenuButton(commands.emojiAndGIFs)
                Divider()
                TypingMenuItems(commands: commands)
            }
        }

        CommandGroup(replacing: .sidebar) {
            CommandItems(app: app, themeStore: themeStore, uiState: uiState) { commands in
                ViewMenuItems(commands: commands)
            }
        }

        CommandMenu("Theme") {
            CommandItems(app: app, themeStore: themeStore, uiState: uiState) { commands in
                ThemeMenuItems(commands: commands)
            }
        }

        CommandMenu("Go") {
            CommandItems(app: app, themeStore: themeStore, uiState: uiState) { commands in
                GoMenuItems(commands: commands)
            }
        }

        CommandMenu("Network") {
            CommandItems(app: app, themeStore: themeStore, uiState: uiState) { commands in
                NetworkMenuItems(commands: commands)
            }
        }

        #if DEBUG
        // Vela Dev only: the developer tools and the state simulator, the
        // last of the app's menus (before Window and Help).
        CommandMenu("Developer") {
            CommandItems(app: app, themeStore: themeStore, uiState: uiState) { commands in
                DeveloperMenuItems(commands: commands)
            }
        }
        #endif

        // Help → What's New in Vela.
        CommandGroup(after: .help) {
            CommandItems(app: app, themeStore: themeStore, uiState: uiState) { commands in
                CommandMenuButton(commands.whatsNew)
            }
        }
    }
}

/// Builds the catalog from the environment and hands it to menu content.
private struct CommandItems<Content: View>: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    let app: AppModel
    let themeStore: ThemeStore
    let uiState: UIState
    @ViewBuilder let content: (VelaCommandCatalog) -> Content

    var body: some View {
        content(VelaCommandCatalog(VelaCommandContext(
            app: app,
            themeStore: themeStore,
            uiState: uiState,
            openWindow: openWindow,
            openSettings: openSettings
        )))
    }
}

// MARK: - File

/// File → Recently Closed: the channels you removed and conversations you
/// closed, newest first ("#vela — Libera.Chat"). Choosing one reopens it.
private struct RecentlyClosedMenu: View {
    let commands: VelaCommandCatalog

    var body: some View {
        let items = commands.recentlyClosedCommands
        Menu("Recently Closed") {
            ForEach(items) { CommandMenuButton($0) }
        }
        .disabled(items.isEmpty)
    }
}

/// Close Tab and Close Window. Close Tab is just Close (the window) when
/// the main window isn't the one in front.
private struct CloseMenuItems: View {
    @FocusedValue(\.isVelaMainWindow) private var isMainWindow
    let commands: VelaCommandCatalog

    var body: some View {
        CommandMenuButton(commands.closeTab(inMainWindow: isMainWindow == true))
        CommandMenuButton(commands.closeWindow)
    }
}

extension FocusedValues {
    /// Set by the main window's scene, so File → Close Tab knows it's in front.
    @Entry var isVelaMainWindow: Bool?
}

// MARK: - View

private struct ViewMenuItems: View {
    let commands: VelaCommandCatalog

    var body: some View {
        CommandMenuButton(commands.commandPalette)

        Divider()

        CommandMenuButton(commands.toggleSidebar)
        CommandMenuButton(commands.toggleMemberList)
        CommandMenuToggle(commands.toggleChannelTitleBar)

        Divider()

        // Settings → Presets' three rows.
        Menu("Layout") {
            ForEach(commands.presetCommands(for: .windowLayout)) { CommandMenuToggle($0) }
            Divider()
            CommandMenuToggle(commands.tabsAtBottom)
            CommandMenuToggle(commands.toggleServerTabRow)
        }

        Menu("Message Style") {
            ForEach(commands.presetCommands(for: .messageStyle)) { CommandMenuToggle($0) }
            Divider()
            ForEach(commands.joinPartModes) { CommandMenuToggle($0) }
        }

        Menu("Density") {
            ForEach(commands.presetCommands(for: .density)) { CommandMenuToggle($0) }
        }

        Divider()

        CommandMenuButton(commands.textBigger)
        CommandMenuButton(commands.textSmaller)
        CommandMenuButton(commands.textActualSize)
    }
}

// MARK: - Go

private struct GoMenuItems: View {
    let commands: VelaCommandCatalog

    var body: some View {
        CommandMenuButton(commands.goToConversation)

        Divider()

        CommandMenuButton(commands.previousBuffer)
        CommandMenuButton(commands.nextBuffer)
        CommandMenuButton(commands.previousTab)
        CommandMenuButton(commands.nextTab)
        CommandMenuButton(commands.previousNetwork)
        CommandMenuButton(commands.nextNetwork)

        Divider()

        CommandMenuButton(commands.previousUnread)
        CommandMenuButton(commands.nextUnread)
        CommandMenuButton(commands.markAllAsRead)
        CommandMenuButton(commands.recap)

        Divider()

        CommandMenuButton(commands.focusNavigation)
        CommandMenuButton(commands.focusMessages)
        CommandMenuButton(commands.focusInput)
        CommandMenuButton(commands.focusMembers)
        CommandMenuButton(commands.nextArea)
        CommandMenuButton(commands.previousArea)
    }
}

// MARK: - Network

private struct NetworkMenuItems: View {
    let commands: VelaCommandCatalog

    var body: some View {
        if let session = commands.context.app.selectedSession {
            let items = commands.networkCommands(for: session)
            ForEach(items.prefix(3)) { CommandMenuButton($0) }
            Divider()
            ForEach(items.dropFirst(3)) { CommandMenuButton($0) }
            Divider()
            CommandMenuButton(commands.sortChannels)
        } else {
            let titles = VelaCommandCatalog.placeholderNetworkTitles
            ForEach(titles.prefix(3), id: \.self) { Button($0) {}.disabled(true) }
            Divider()
            ForEach(titles.dropFirst(3), id: \.self) { Button($0) {}.disabled(true) }
            Divider()
            Button(commands.sortChannels.title) {}.disabled(true)
        }
        CommandMenuButton(commands.moveSelectedBuffer(forward: false))
        CommandMenuButton(commands.moveSelectedBuffer(forward: true))
        CommandMenuButton(commands.moveSelectedNetwork(forward: false))
        CommandMenuButton(commands.moveSelectedNetwork(forward: true))
    }
}
