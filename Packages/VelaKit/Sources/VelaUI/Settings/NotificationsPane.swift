// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// What notifies you, the Dock icon's badge, offline mark and bouncing,
/// plus app-wide highlight words.
struct NotificationsPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings

        SettingsPage("Notifications", subtitle: "Decide what deserves your attention while Vela is in the background.", pane: .notifications) {
            SettingsSection("Notify me about") {
                SettingsToggle(
                    "Highlights",
                    detail: "When someone mentions your nick or a highlight word.",
                    isOn: $settings[.notifyHighlights]
                )
                SettingsToggle(
                    "Private messages",
                    detail: "Every message in a one-to-one conversation.",
                    isOn: $settings[.notifyPrivateMessages]
                )
                SettingsToggle("Play a sound", isOn: $settings[.notifySound])
            }

            DockSettingsSection()

            SettingsSection(
                "Highlight words",
                footer: "Your nick always counts as a highlight. Words here apply on every network; add network-specific words in that network's settings."
            ) {
                StringListEditor(
                    items: $settings[.highlightWords],
                    placeholder: "Add a word or phrase",
                    itemName: "highlight word",
                    emptyMessage: "No extra highlight words.",
                    monospaced: false
                )
            }

            SettingsSection(footer: "Banners, alerts, badges and Focus filters are managed by macOS.") {
                SettingsRow("System notification settings", detail: "Choose banner style, lock screen previews and more.") {
                    Button("Open Notification Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(ThemedButtonStyle())
                }
            }
        }
    }
}

/// The Dock icon: its badge (`dock.showBadge`, `dock.badgeCounts`,
/// `dock.badgeStyle`), the offline mark (`dock.showOffline`) and bouncing
/// (`dock.bounce`, `dock.bounceFor`).
private struct DockSettingsSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        let showsBadge = settings[.dockShowBadge]
        let bounces = settings[.dockBounce] != .off

        SettingsSection(
            "Dock",
            footer: "Muted channels and conversations never count toward the badge or bounce the icon. Each message counts once, so a mention isn't counted twice with All channel messages on."
        ) {
            SettingsToggle(
                "Show a badge on the Dock icon",
                detail: "Counts the unread messages you choose below.",
                isOn: $settings[.dockShowBadge]
            )
            SettingsRow("Count", detail: "Messages you haven't read yet. Joins, parts and other events never count.") {
                DockChoiceList(
                    title: "Count",
                    options: [
                        (.mentions, "Mentions and highlight words"),
                        (.privateMessages, "Private messages"),
                        (.channels, "All channel messages"),
                    ],
                    selection: $settings[.dockBadgeCounts]
                )
            }
            .themedDisabled(!showsBadge)
            SettingsSegmentedRow(
                title: "Style",
                detail: "99+ stops counting at 99. Dot shows that something's new, without a number.",
                selection: $settings[.dockBadgeStyle],
                options: [(.capped, "99+"), (.exact, "Exact"), (.dot, "Dot")]
            )
            .themedDisabled(!showsBadge)
            SettingsRow(
                "Show when a network is offline",
                detail: "A small amber mark on the Dock icon when a network drops and isn't back within about 10 seconds. Networks you disconnect don't count.",
                labelsControl: true
            ) {
                HStack(spacing: 12) {
                    OfflineMarkPreview(icon: settings[.appearanceAppIcon])
                    Toggle("Show when a network is offline", isOn: $settings[.dockShowOffline])
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityHint("A small amber mark on the Dock icon when a network drops and isn't back within about 10 seconds.")
                }
            }
            SettingsMenuRow(
                title: "Bounce the Dock icon",
                detail: "For new messages while Vela is in the background.",
                selection: $settings[.dockBounce],
                options: [(.off, "Off"), (.once, "Once"), (.untilActive, "Until you switch to Vela")]
            )
            SettingsRow("Bounce for", detail: "Which messages bounce the icon.") {
                DockChoiceList(
                    title: "Bounce for",
                    options: [
                        (.mentions, "Mentions and highlight words"),
                        (.privateMessages, "Private messages"),
                    ],
                    selection: $settings[.dockBounceFor]
                )
            }
            .themedDisabled(!bounces)
        }
    }
}

/// Checkboxes for a list setting with a fixed set of values, kept in the
/// order of `options`.
private struct DockChoiceList<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: [Value]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(options, id: \.value) { option in
                Toggle(option.label, isOn: binding(for: option.value))
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .accessibilityLabel("\(title): \(option.label)")
            }
        }
        .fixedSize()
    }

    private func binding(for value: Value) -> Binding<Bool> {
        Binding(
            get: { selection.contains(value) },
            set: { isOn in
                var chosen = Set(selection)
                if isOn { chosen.insert(value) } else { chosen.remove(value) }
                selection = options.map(\.value).filter(chosen.contains)
            }
        )
    }
}

/// The current Dock icon with the offline mark, small, beside its switch.
private struct OfflineMarkPreview: View {
    let icon: AppIcon

    var body: some View {
        if let image = DockIcon.offlineMarkPreview(for: icon) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 46, height: 46)
                .help("The offline mark on the Dock icon")
                .accessibilityHidden(true)
        }
    }
}
