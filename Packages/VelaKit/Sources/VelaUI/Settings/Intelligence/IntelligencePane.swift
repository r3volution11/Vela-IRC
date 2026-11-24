// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// Settings → Intelligence: Apple Intelligence's status, your own models
/// (providers and the default model), Catch me up, Recap, translation,
/// Writing Tools, and Siri & Shortcuts, which links to Settings →
/// Integrations, where Siri, Shortcuts and Spotlight are. Each feature owns
/// its section view.
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
            "Intelligence",
            subtitle: Self.subtitle(privateCloudCompute: usesPrivateCloudCompute, providerModels: providerModelTitles),
            pane: .intelligence
        ) {
            status
            IntelligenceModelsSection()
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
            SettingsSection("Siri & Shortcuts") {
                SettingsRow(
                    "Siri, Shortcuts and Spotlight",
                    detail: "What to ask Siri, Vela's actions in Shortcuts, and what Spotlight shows, with Alfred, Raycast and AppleScript."
                ) {
                    SettingsLinkButton("Integrations", systemImage: SettingsPane.integrations.systemImage) { navigate(.integrations) }
                        .accessibilityHint("Opens Settings → Integrations.")
                }
            }
        }
    }

    /// The providers' models Catch me up and Recap use, by name, for the
    /// subtitle.
    private var providerModelTitles: [String] {
        let models = intelligence.models
        let settings = models.modelSettings
        var titles: [String] = []
        for feature in AIFeature.allCases {
            let choice = settings.choice(for: feature)
            guard !choice.isApple else { continue }
            let title = models.title(for: choice)
            if !titles.contains(title) { titles.append(title) }
        }
        return titles
    }

    /// The status callout's words while a feature uses a provider's model:
    /// where its summaries go, so "nothing is sent anywhere" is never said.
    static func providerDetail(_ providerModels: [String]) -> String {
        "Summaries you chose a model for are written by \(providerModels.joined(separator: " and ")), which gets the messages you ask about and their nicks, never channel or network names. Translation stays on this Mac."
    }

    /// Under the pane's title: what's here, and where summaries are made.
    static func subtitle(privateCloudCompute: Bool, providerModels: [String] = []) -> String {
        if !providerModels.isEmpty {
            return "Summaries, translation, Writing Tools and Siri. Summaries use \(providerModels.joined(separator: " and ")) where you chose it; translation runs on this Mac."
        }
        return privateCloudCompute
            ? "Summaries, translation, Writing Tools and Siri. Translation and short summaries run on this Mac; long summaries use Private Cloud Compute."
            : "Summaries, translation, Writing Tools and Siri. Summaries and translation run on this Mac."
    }

    @ViewBuilder
    private var status: some View {
        let status = intelligence.availability.status
        let providers = providerModelTitles
        if status.isAvailable {
            SettingsCallout(
                .success,
                status.title,
                message: providers.isEmpty
                    ? status.detail(privateCloudCompute: usesPrivateCloudCompute)
                    : Self.providerDetail(providers)
            )
        } else {
            SettingsCallout(.info, status.title, message: providers.isEmpty ? status.detail : "\(status.detail) \(Self.providerDetail(providers))") {
                if let url = status.settingsURL {
                    Button("Open System Settings") { NSWorkspace.shared.open(url) }
                        .buttonStyle(ThemedButtonStyle())
                }
            }
        }
    }
}
