// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Navigation style, tab stacks, sidebar and member list.
struct LayoutPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var settings = app.settings
        let navigation = settings[.navigationStyle]
        let usesTabs = navigation == .tabs
        let usesSidebar = navigation == .sidebar

        SettingsPage("Layout", subtitle: "Choose how you move between networks and channels, and how much room each pane gets.", pane: .layout) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Navigation")
                HStack(alignment: .top, spacing: 14) {
                    navigationCard(.sidebar, title: "Sidebar", subtitle: "A compact tree of networks and channels that can collapse to an icon rail.")
                    navigationCard(.tabs, title: "Tabs", subtitle: "Vivaldi-style tab stacks: one row for networks, one for the selected network's channels.")
                    navigationCard(.focus, title: "Focus", subtitle: "Neither: just the conversation. Switch with Go to Conversation (⌘P) or ⌘1\u{2060}–\u{2060}⌘9.")
                }
            }

            SettingsSection(
                "Tabs",
                footer: usesTabs ? nil : "These apply when navigation is set to Tabs."
            ) {
                SettingsSegmentedRow(
                    title: "Placement",
                    detail: "Title bar puts tabs beside the window buttons; the topic moves to a popover. You can also right-click the channel title bar to hide it.",
                    selection: $settings[.tabsPlacement],
                    options: [(.top, "Top"), (.titleBar, "Title bar"), (.bottom, "Bottom")]
                )
                VStack(alignment: .leading, spacing: 0) {
                    SettingsSliderRow(
                        title: "Roundness",
                        value: $settings[.tabsRoundness],
                        range: 0...1,
                        step: 0.05,
                        minimumLabel: "Square",
                        maximumLabel: "Pill",
                        width: 150,
                        format: { "\(Int(($0 * 100).rounded()))%" }
                    )
                    TabRoundnessPreview()
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }
                SettingsSegmentedRow(
                    title: "Network row",
                    detail: "Auto hides the row of network tabs while you're connected to just one network.",
                    selection: $settings[.tabsServerRow],
                    options: [(.auto, "Auto"), (.always, "Always")]
                )
                SettingsSliderRow(
                    title: "Tab height",
                    value: $settings[.tabsHeight],
                    range: 22...40,
                    format: SettingsFormat.points
                )
                SettingsToggle("Unread badges", detail: "Show unread and mention counts on tabs.", isOn: $settings[.tabsShowUnreadBadges])
                SettingsToggle("Close buttons", detail: "A × takes the place of a tab's # or avatar when you point at it.", isOn: $settings[.tabsShowCloseButtons])
            }
            .opacity(usesTabs ? 1 : 0.6)

            SettingsSection(
                "Sidebar",
                footer: usesSidebar ? nil : "These apply when navigation is set to Sidebar."
            ) {
                SettingsToggle(
                    "Collapse to icon rail",
                    detail: "Show only network icons; hover to expand.",
                    isOn: $settings[.sidebarCollapsed]
                )
                SettingsSliderRow(
                    title: "Row height",
                    value: $settings[.sidebarRowHeight],
                    range: 18...34,
                    format: SettingsFormat.points
                )
                SettingsSliderRow(
                    title: "Font size",
                    value: $settings[.sidebarFontSize],
                    range: 10...17,
                    step: 0.5,
                    format: SettingsFormat.points
                )
                SettingsToggle("Unread counts", detail: "Show the number of unread messages next to each channel.", isOn: $settings[.sidebarShowUnreadCounts])
            }
            .opacity(usesSidebar ? 1 : 0.6)

            SettingsSection("Member list") {
                SettingsToggle("Show member list", detail: "The list of people in the current channel, on the right.", isOn: $settings[.memberListVisible])
                SettingsSliderRow(
                    title: "Width",
                    value: $settings[.memberListWidth],
                    range: 120...320,
                    step: 5,
                    format: SettingsFormat.points
                )
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme[ThemeKey.settingsForeground])
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
    }

    private func navigationCard(_ style: NavigationStyle, title: String, subtitle: String) -> some View {
        var config = LayoutSchematicConfig(settings: app.settings)
        config.navigation = style
        config.showMedia = false
        return SettingsChoiceCard(
            title,
            subtitle: subtitle,
            isSelected: app.settings[.navigationStyle] == style,
            // Not animated: switching lays the whole main window out once,
            // not on every frame of an animation (see MainWindowView).
            action: { app.settings[.navigationStyle] = style },
            preview: {
                LayoutSchematic(config: config, theme: theme)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme[ThemeKey.settingsBorder])
                    )
            }
        )
    }
}

/// A few real-size tabs drawn at the current roundness and height.
private struct TabRoundnessPreview: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style

    /// Three channels and a conversation (no `#`, an avatar). The third
    /// shows its close button, as when the pointer is on its `#`.
    private let tabs: [(isChannel: Bool, name: String, unread: Int)] = [(true, "vela", 0), (true, "swift", 3), (true, "macdev", 0), (false, "alice", 1)]

    var body: some View {
        let height = style.tabHeight
        let radius = style.tabCornerRadius(forHeight: height)
        HStack(spacing: 6) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                let isActive = index == 0
                let foreground = isActive ? theme[ThemeKey.accentForeground] : theme[ThemeKey.buttonSecondaryForeground]
                HStack(spacing: 4) {
                    Group {
                        if style.tabsShowCloseButtons, index == 2 {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(foreground)
                                .frame(width: 16, height: 16)
                                .background(
                                    RoundedRectangle(cornerRadius: max(3, style.tabCornerRadius(forHeight: 16)), style: .continuous)
                                        .fill(foreground.opacity(0.14))
                                )
                        } else if tab.isChannel {
                            Text("#")
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(foreground)
                        } else {
                            AvatarView(nick: tab.name, size: 15)
                        }
                    }
                    .frame(width: 16, height: 16)
                    Text(tab.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(foreground)
                    if style.tabsShowUnreadBadges, tab.unread > 0 {
                        UnreadBadge(count: tab.unread, isHighlight: tab.unread == 1)
                    }
                }
                .padding(.horizontal, max(10, radius * 0.6 + 8))
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(isActive ? theme[ThemeKey.accent] : theme[ThemeKey.buttonSecondaryBackground])
                )
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme[ThemeKey.titleBarBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme[ThemeKey.settingsBorder])
        )
        .animation(.snappy(duration: 0.15), value: radius)
        .animation(.snappy(duration: 0.15), value: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of tabs with \(Int((style.tabRoundness * 100).rounded())) percent roundness")
    }
}
