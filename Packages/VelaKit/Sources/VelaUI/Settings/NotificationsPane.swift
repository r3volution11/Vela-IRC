// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// What notifies you, plus app-wide highlight words.
struct NotificationsPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings

        SettingsPage("Notifications", subtitle: "Decide what deserves your attention while Vela is in the background.") {
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
