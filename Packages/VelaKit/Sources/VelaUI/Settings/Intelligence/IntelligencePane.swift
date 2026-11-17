// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// Settings → Apple Intelligence: Catch me up, translation, Writing Tools
/// and Siri & Shortcuts. Each feature owns its section view.
struct IntelligencePane: View {
    @Environment(IntelligenceServices.self) private var intelligence
    let navigate: (SettingsPane) -> Void

    var body: some View {
        SettingsPage(
            "Apple Intelligence",
            subtitle: "Summaries, translation, Writing Tools and Siri. Everything runs on this Mac."
        ) {
            status
            IntelligenceCatchUpSection()
            IntelligenceTranslationSection()
            SettingsSection(
                "Writing Tools",
                footer: "Proofread and rewrite in the message box. Commands, nicks and links are left alone."
            ) {
                SettingsRow("Writing Tools in the message box", detail: "Turn it on or off with the other typing options.") {
                    SettingsLinkButton("Messages → Typing", systemImage: "text.bubble") { navigate(.messages) }
                }
            }
            IntelligenceSiriSection()
        }
    }

    @ViewBuilder
    private var status: some View {
        let status = intelligence.availability.status
        if status.isAvailable {
            SettingsCallout(.success, status.title, message: status.detail)
        } else {
            SettingsCallout(.info, status.title, message: status.detail) {
                if let url = status.settingsURL {
                    Button("Open System Settings") { NSWorkspace.shared.open(url) }
                        .buttonStyle(ThemedButtonStyle())
                }
            }
        }
    }
}
