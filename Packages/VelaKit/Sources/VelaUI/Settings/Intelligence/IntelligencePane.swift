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
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    let navigate: (SettingsPane) -> Void

    /// Long catch-ups go to Private Cloud Compute (`intelligence.privateCloudCompute`).
    private var usesPrivateCloudCompute: Bool {
        IntelligenceCatchUpSection.offersPrivateCloudCompute && app.settings[.intelligencePrivateCloudCompute]
    }

    var body: some View {
        SettingsPage(
            "Apple Intelligence",
            subtitle: Self.subtitle(privateCloudCompute: usesPrivateCloudCompute),
            pane: .intelligence
        ) {
            status
            IntelligenceCatchUpSection()
            IntelligenceRecapSection()
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

    /// Under the pane's title: what's here, and what runs on this Mac.
    static func subtitle(privateCloudCompute: Bool) -> String {
        privateCloudCompute
            ? "Summaries, translation, Writing Tools and Siri. Translation and short summaries run on this Mac; long summaries use Private Cloud Compute."
            : "Summaries, translation, Writing Tools and Siri. Summaries and translation run on this Mac."
    }

    @ViewBuilder
    private var status: some View {
        let status = intelligence.availability.status
        if status.isAvailable {
            SettingsCallout(.success, status.title, message: status.detail(privateCloudCompute: usesPrivateCloudCompute))
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
