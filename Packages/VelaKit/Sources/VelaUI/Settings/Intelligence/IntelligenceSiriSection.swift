// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Settings → Apple Intelligence → Siri & Shortcuts.
struct IntelligenceSiriSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        SettingsSection(
            "Siri & Shortcuts",
            footer: "On macOS 27 or later, Siri can also send and draft messages, and knows which channel is open, so “reply to this” works."
        ) {
            SettingsToggle(
                "Show channels in Spotlight",
                detail: "Channel and conversation names in Spotlight's results, never messages. Siri still finds them by name when this is off.",
                isOn: $settings[.intelligenceSpotlightChannels]
            )
            SiriPhrasesRow(phrases: Self.phrases)
            SettingsRow("Shortcuts", detail: "Use Vela's actions in your own shortcuts and automations.") {
                Button("Open Shortcuts", action: Self.openShortcuts)
                    .buttonStyle(ThemedButtonStyle())
            }
        }
    }

    /// What to say. The example channel is Vela's own, #vela on Libera.Chat,
    /// never one of the user's: an example sends people to the channel it
    /// names.
    static let phrases = [
        "Catch me up in Vela",
        "Check my Vela mentions",
        "Send a message with Vela",
        "Open #vela on Libera.Chat in Vela",
        "Set me away in Vela",
    ]

    static let shortcutsBundleID = "com.apple.shortcuts"

    private static func openShortcuts() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: shortcutsBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// "Ask Siri" and a few example phrases.
private struct SiriPhrasesRow: View {
    @Environment(\.theme) private var theme
    let phrases: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask Siri")
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
            VStack(alignment: .leading, spacing: 3) {
                ForEach(phrases, id: \.self) { phrase in
                    Label("“\(phrase)”", systemImage: "waveform")
                        .labelStyle(SiriPhraseLabelStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

private struct SiriPhraseLabelStyle: LabelStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme[ThemeKey.accentText])
                .accessibilityHidden(true)
            configuration.title
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .textSelection(.enabled)
        }
    }
}
