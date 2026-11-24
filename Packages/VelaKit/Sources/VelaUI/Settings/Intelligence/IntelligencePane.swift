// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// Settings → Intelligence: what the features do. Catch me up, Recap (each
/// with its own model, once there's a choice), translation and Writing
/// Tools, then links to AI Providers (where models come from), AI Privacy
/// (what's sent where) and Integrations (Siri, Shortcuts and Spotlight).
/// Each feature owns its section view. While Apple Intelligence can't run
/// and a feature uses it, a callout says why.
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
            appleStatus
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
            SettingsSection("Models and privacy") {
                SettingsRow("AI Providers", detail: "Apple Intelligence, models on this Mac, and OpenAI, Anthropic or Google Gemini with your own key.") {
                    SettingsLinkButton("AI Providers", systemImage: SettingsPane.aiProviders.systemImage) { navigate(.aiProviders) }
                        .accessibilityHint("Opens Settings → AI Providers.")
                }
                SettingsRow("AI Privacy", detail: "What each model is sent, where it goes, and which providers may be sent anything.") {
                    SettingsLinkButton("AI Privacy", systemImage: SettingsPane.aiPrivacy.systemImage) { navigate(.aiPrivacy) }
                        .accessibilityHint("Opens Settings → AI Privacy.")
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

    /// Under the pane's title: what's here, and where summaries are made.
    static func subtitle(privateCloudCompute: Bool, providerModels: [String] = []) -> String {
        if !providerModels.isEmpty {
            return "Summaries, translation and Writing Tools. Summaries use \(providerModels.joined(separator: " and ")) where you chose it; translation runs on this Mac."
        }
        return privateCloudCompute
            ? "Summaries, translation and Writing Tools. Translation and short summaries run on this Mac; long summaries use Private Cloud Compute."
            : "Summaries, translation and Writing Tools. Summaries and translation run on this Mac."
    }

    /// While Apple Intelligence can't run and Catch me up or Recap uses it:
    /// why, and what to do. Its status otherwise is on AI Providers.
    @ViewBuilder
    private var appleStatus: some View {
        let status = intelligence.availability.status
        let usesApple = AIFeature.allCases.contains { app.settings.usesAppleModel(for: $0) }
        if !status.isAvailable, usesApple {
            SettingsCallout(.info, status.title, message: "\(status.detail) \(Self.unavailableHint)") {
                if let url = status.settingsURL {
                    Button("Open System Settings") { NSWorkspace.shared.open(url) }
                        .buttonStyle(ThemedButtonStyle())
                }
                Button("AI Providers") { navigate(.aiProviders) }
                    .buttonStyle(ThemedButtonStyle())
                    .accessibilityHint("Opens Settings → AI Providers, where you can choose a model of your own.")
            }
        }
    }

    static let unavailableHint = "Catch me up and Recap can use a model of your own instead, set up in AI Providers."
}
