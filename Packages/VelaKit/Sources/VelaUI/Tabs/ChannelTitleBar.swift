// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

/// Hiding and showing the channel title bar (`ChatHeaderView`: the name,
/// member count and topic) with tabs.
///
/// It's not a setting of its own: hiding it moves the tabs into the title
/// bar (`tabs.placement = titleBar`), where the topic sits behind the ⓘ
/// button, and showing it puts them back at the top or the bottom, wherever
/// they were last shown this session (`UIState.stripTabPlacement`), or at
/// the top. So **Settings → Layout → Placement** shows the change. With the
/// sidebar the title bar always shows, and there's nothing to offer.
///
/// Offered by right-clicking the title bar (`channelTitleBarMenu()`), the
/// empty space in the title bar with tabs in it (`titleBarTabStripArea()`),
/// and **View → Show Channel Title Bar**.
@MainActor
enum ChannelTitleBar {
    static let hideTitle = "Hide Channel Title Bar"
    static let showTitle = "Show Channel Title Bar"

    /// Whether the channel title bar is on screen: always with the
    /// sidebar, and with tabs anywhere but the title bar.
    static func isShown(_ settings: SettingsStore) -> Bool {
        !(settings[.navigationStyle] == .tabs && settings[.tabsPlacement] == .titleBar)
    }

    /// Hide Channel Title Bar applies: tabs at the top or the bottom.
    static func canHide(_ settings: SettingsStore) -> Bool {
        settings[.navigationStyle] == .tabs && settings[.tabsPlacement] != .titleBar
    }

    /// Show Channel Title Bar applies: tabs in the title bar.
    static func canShow(_ settings: SettingsStore) -> Bool {
        settings[.navigationStyle] == .tabs && settings[.tabsPlacement] == .titleBar
    }

    /// Where showing the title bar puts the tabs: back where they were, or
    /// at the top when that isn't known.
    static func restoredPlacement(remembered: TabStackPlacement?) -> TabStackPlacement {
        guard let remembered, remembered != .titleBar else { return .top }
        return remembered
    }

    /// Moves the tabs into the title bar, remembering where they were.
    static func hide(settings: SettingsStore, uiState: UIState) {
        guard canHide(settings) else { return }
        uiState.noteStripTabPlacement(settings[.tabsPlacement])
        move(to: .titleBar, settings: settings, uiState: uiState)
    }

    /// Puts the tabs back at the top or the bottom.
    static func show(settings: SettingsStore, uiState: UIState) {
        guard canShow(settings) else { return }
        move(to: restoredPlacement(remembered: uiState.stripTabPlacement), settings: settings, uiState: uiState)
    }

    /// View → Show Channel Title Bar.
    static func toggle(settings: SettingsStore, uiState: UIState) {
        if isShown(settings) {
            hide(settings: settings, uiState: uiState)
        } else {
            show(settings: settings, uiState: uiState)
        }
    }

    /// No animation, like the other ways of moving the tabs: the message
    /// list keeps its place (pinned to the newest line, it stays there) and
    /// is laid out once, not on every frame of a transition.
    private static func move(to placement: TabStackPlacement, settings: SettingsStore, uiState: UIState) {
        // The tabs are drawn anew in their new place. The keyboard goes
        // with them if it was on them; anywhere else, nothing it's on moves.
        let keyboardOnTabs = uiState.focusedArea == .navigation
        settings[.tabsPlacement] = placement
        if keyboardOnTabs { uiState.focus(.navigation) }
    }
}

// MARK: - Menus

extension View {
    /// The channel title bar's right-click menu: **Hide Channel Title Bar**
    /// with tabs at the top or the bottom, nothing with the sidebar.
    func channelTitleBarMenu() -> some View {
        modifier(ChannelTitleBarMenu())
    }

    /// Empty space in the title bar with tabs in it (`tabs.placement =
    /// titleBar`), behind and between the tabs: it drags the window, a
    /// double-click zooms it, and right-clicking it offers **Show Channel
    /// Title Bar**. The tabs and buttons in front keep their own clicks and
    /// menus.
    func titleBarTabStripArea() -> some View {
        modifier(TitleBarTabStripArea())
    }
}

private struct ChannelTitleBarMenu: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState

    func body(content: Content) -> some View {
        content.contextMenu {
            if ChannelTitleBar.canHide(app.settings) {
                Button(ChannelTitleBar.hideTitle) {
                    ChannelTitleBar.hide(settings: app.settings, uiState: uiState)
                }
            }
        }
    }
}

private struct TitleBarTabStripArea: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState

    func body(content: Content) -> some View {
        content
            .windowTitleBarArea()
            .contextMenu {
                Button(ChannelTitleBar.showTitle) {
                    ChannelTitleBar.show(settings: app.settings, uiState: uiState)
                }
            }
    }
}
