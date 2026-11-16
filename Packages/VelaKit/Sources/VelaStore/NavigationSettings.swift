// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// How servers and channels are navigated.
public enum NavigationStyle: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// Compact tree (collapsible to an icon rail).
    case sidebar
    /// Vivaldi-style two-level tab stacks: servers, then the selected server's channels.
    case tabs
}

/// Where the tab stacks are drawn when `navigation.style` is `tabs`.
public enum TabStackPlacement: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// Below the channel title strip.
    case top
    /// In the window's title bar, next to the traffic lights (the topic moves to a popover).
    case titleBar
    /// Just above the message input.
    case bottom
}

/// When the server row of the two-level tab stack is shown.
public enum ServerTabRowMode: String, Codable, Sendable, CaseIterable, SettingValueConvertible {
    /// Hidden when there's only one network.
    case auto
    case always
}

// MARK: Keys

extension SettingKey where Value == NavigationStyle {
    public static var navigationStyle: SettingKey<NavigationStyle> {
        .init("navigation.style", default: .sidebar,
              summary: "Navigate servers and channels with the sidebar or with tab stacks.")
    }
}

extension SettingKey where Value == TabStackPlacement {
    public static var tabsPlacement: SettingKey<TabStackPlacement> {
        .init("tabs.placement", default: .top,
              summary: "Where tab stacks appear: top (below the title strip), titleBar or bottom (above the input).")
    }
}

extension SettingKey where Value == ServerTabRowMode {
    public static var tabsServerRow: SettingKey<ServerTabRowMode> {
        .init("tabs.serverRow", default: .auto,
              summary: "Show the server tab row always, or only when connected to more than one network (auto).")
    }
}

extension SettingKey where Value == Double {
    public static var tabsRoundness: SettingKey<Double> {
        .init("tabs.roundness", default: 0.35,
              summary: "Tab corner roundness from 0 (square) to 1 (pill).")
    }
    public static var tabsHeight: SettingKey<Double> {
        .init("tabs.height", default: 28, summary: "Tab height in points.")
    }
}

extension SettingKey where Value == Bool {
    public static var tabsShowUnreadBadges: SettingKey<Bool> {
        .init("tabs.showUnreadBadges", default: true, summary: "Show unread counts on tabs.")
    }
    public static var tabsShowCloseButtons: SettingKey<Bool> {
        .init("tabs.showCloseButtons", default: true, summary: "Show a close button on hover for channel and query tabs.")
    }
    public static var chatMonospace: SettingKey<Bool> {
        .init("chat.monospace", default: false,
              summary: "Render chat text in chat.monospaceFontFamily, like a terminal client.")
    }
}

/// Keys added for navigation and presets, for `SettingsCatalog`.
enum NavigationSettingsCatalog {
    static var descriptors: [SettingDescriptor] {
        [
            SettingKey.navigationStyle.descriptor,
            SettingKey.tabsPlacement.descriptor,
            SettingKey.tabsServerRow.descriptor,
            SettingKey.tabsRoundness.descriptor,
            SettingKey.tabsHeight.descriptor,
            SettingKey.tabsShowUnreadBadges.descriptor,
            SettingKey.tabsShowCloseButtons.descriptor,
            SettingKey.chatMonospace.descriptor,
        ]
    }
}

// MARK: Presets

/// A one-click configuration of navigation, message layout, density and media.
/// Presets never change the theme; they only write the keys they list, so
/// anything else the user customized is kept.
public struct SettingsPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let systemImage: String
    public let values: [String: JSONValue]

    public init(id: String, name: String, summary: String, systemImage: String, values: [String: JSONValue]) {
        self.id = id
        self.name = name
        self.summary = summary
        self.systemImage = systemImage
        self.values = values
    }

    public static let classic = SettingsPreset(
        id: "classic",
        name: "Classic IRC",
        summary: "Sidebar tree, one-line messages in a monospace font, dense spacing and compact link titles. Feels like Textual or irssi.",
        systemImage: "terminal",
        values: [
            "navigation.style": "sidebar",
            "chat.layout": "classic",
            "chat.monospace": true,
            "chat.fontSize": 12,
            "chat.lineSpacing": 1,
            "chat.messageSpacing": 2,
            "chat.showAvatars": false,
            "chat.showJoinPart": "show",
            "chat.showTimestamps": true,
            "sidebar.rowHeight": 20,
            "sidebar.fontSize": 12,
            "memberList.visible": true,
            "media.linkPreviewSize": "minimal",
            "media.videos": "compact",
            "media.imageSize": "thumbnail",
        ]
    )

    public static let modern = SettingsPreset(
        id: "modern",
        name: "Modern Chat",
        summary: "Vela's defaults: sidebar, grouped messages (one name header per run of messages), link previews with thumbnails and inline video players.",
        systemImage: "bubble.left.and.text.bubble.right",
        values: [
            "navigation.style": "sidebar",
            "chat.layout": "grouped",
            "chat.monospace": false,
            "chat.fontSize": 13,
            "chat.lineSpacing": 2,
            "chat.messageSpacing": 6,
            "chat.showAvatars": false,
            "chat.showJoinPart": "collapse",
            "chat.showTimestamps": true,
            "sidebar.rowHeight": 22,
            "sidebar.fontSize": 12,
            "memberList.visible": true,
            "media.linkPreviewSize": "standard",
            "media.videos": "player",
            "media.imageSize": "full",
        ]
    )

    public static let tabbed = SettingsPreset(
        id: "tabbed",
        name: "Tabbed",
        summary: "Vivaldi-style tab stacks instead of a sidebar, grouped messages and rounded tabs. Great for one network and a few channels.",
        systemImage: "rectangle.stack",
        values: [
            "navigation.style": "tabs",
            "tabs.placement": "top",
            "tabs.roundness": 0.5,
            "tabs.serverRow": "auto",
            "chat.layout": "grouped",
            "chat.monospace": false,
            "chat.fontSize": 13,
            "chat.lineSpacing": 2,
            "chat.messageSpacing": 8,
            "chat.showAvatars": false,
            "chat.showJoinPart": "collapse",
            "memberList.visible": false,
            "media.linkPreviewSize": "standard",
            "media.videos": "player",
            "media.imageSize": "full",
        ]
    )

    public static let focus = SettingsPreset(
        id: "focus",
        name: "Focus",
        summary: "Pill tabs in the title bar, compact columns, no avatars or join/part noise, member list hidden, one-line link previews and small images. Maximum text, minimum chrome.",
        systemImage: "text.alignleft",
        values: [
            "navigation.style": "tabs",
            "tabs.placement": "titleBar",
            "tabs.roundness": 1,
            "tabs.serverRow": "auto",
            "chat.layout": "columns",
            "chat.monospace": false,
            "chat.fontSize": 13,
            "chat.lineSpacing": 2,
            "chat.messageSpacing": 3,
            "chat.showAvatars": false,
            "chat.showJoinPart": "hide",
            "memberList.visible": false,
            "media.linkPreviewSize": "minimal",
            "media.videos": "player",
            "media.imageSize": "thumbnail",
        ]
    )

    public static let all: [SettingsPreset] = [.classic, .modern, .tabbed, .focus]
}

extension SettingsStore {
    /// Writes every key of `preset`.
    public func apply(_ preset: SettingsPreset) {
        for (key, value) in preset.values {
            setValue(value, forKey: key)
        }
    }

    /// The preset whose values all match the current settings (defaults
    /// count), or nil when the configuration is custom.
    public func matchingPreset() -> SettingsPreset? {
        SettingsPreset.all.first { preset in
            SettingsPreset.valuesMatch(preset.values) {
                self.value(forKey: $0) ?? SettingsCatalog.descriptor(forKey: $0)?.defaultValue
            }
        }
    }
}

extension SettingsPreset {
    /// Whether every key in `presetValues` resolves to its value, where
    /// `resolve` gives the stored value or the default. Numbers compare
    /// loosely, so a stored `12.0` matches a preset's `12`.
    static func valuesMatch(_ presetValues: [String: JSONValue], resolving resolve: (String) -> JSONValue?) -> Bool {
        presetValues.allSatisfy { key, value in
            let current = resolve(key)
            if case .number(let a) = current, case .number(let b) = value { return abs(a - b) < 0.0001 }
            return current == value
        }
    }
}
