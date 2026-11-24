// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// Settings → AI Privacy: what Vela sends to AI models and where, plainly.
/// Apple Intelligence on this Mac; what any provider gets and never gets;
/// each provider you've added, where its messages go, whether it may be
/// sent them (Allow… shows the consent sheet; Withdraw makes Catch me up
/// and Recap ask again before using it) and its policies; and Spotlight,
/// whose settings are in Integrations.
struct AIPrivacyPane: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.theme) private var theme
    let navigate: (SettingsPane) -> Void

    @State private var consent: AIConsentRequest?

    static let subtitle = "What Vela sends to AI models, and where. Nothing is sent until you ask for a summary, and Vela has no server of its own."

    var body: some View {
        SettingsPage("AI Privacy", subtitle: Self.subtitle, pane: .aiPrivacy) {
            appleSection
            whatsSentSection
            providersSection
            spotlightSection
        }
        .sheet(item: $consent) { request in
            AIConsentSheet(request: request)
        }
    }

    // MARK: Apple

    private var appleSection: some View {
        let privateCloudCompute = IntelligenceCatchUpSection.offersPrivateCloudCompute && app.settings[.intelligencePrivateCloudCompute]
        return SettingsSection("Apple Intelligence") {
            info("Catch me up and Recap", Self.appleSummaries(privateCloudCompute: privateCloudCompute), systemImage: "apple.intelligence")
            info("Translation", "On this Mac, with Apple's Translation framework. macOS downloads each language from Apple once.", systemImage: "translate")
            info("Writing Tools", "Apple's own, in the message box: Apple Intelligence handles what you type as it does in any app.", systemImage: "pencil.and.outline")
        }
    }

    /// Where Apple's summaries are made.
    static func appleSummaries(privateCloudCompute: Bool) -> String {
        privateCloudCompute
            ? "Summarized on this Mac; long catch-ups go to Apple's Private Cloud Compute, encrypted, not stored, and not readable by Apple. Apple Intelligence gets the messages and your nick, never a channel's or network's name."
            : "Summarized on this Mac, unless you choose a model of your own. Apple Intelligence gets the messages and your nick, never a channel's or network's name."
    }

    // MARK: What's sent

    private var whatsSentSection: some View {
        SettingsSection("What a provider gets", footer: Self.sentFooter) {
            info("Sent", AIConsentText.sent, systemImage: "text.bubble")
            info("Never sent", AIConsentText.neverSent, systemImage: "eye.slash")
            info("Your keys", "Kept in your Keychain, and sent only to their own provider. Never in settings.json.", systemImage: "key")
        }
    }

    static let sentFooter = "Only for a Catch me up or a Recap you ask for, with the model you chose. Links are shortened to the site they point to. Vela keeps no record of what it sends or gets back."

    // MARK: Providers

    private var providersSection: some View {
        let providers = intelligence.models.providers
        return SettingsSection("Your providers", footer: providers.isEmpty ? nil : Self.providersFooter) {
            if providers.isEmpty {
                SettingsRow("No providers", detail: "Catch me up and Recap use Apple Intelligence on this Mac.") {
                    SettingsLinkButton("AI Providers", systemImage: SettingsPane.aiProviders.systemImage) { navigate(.aiProviders) }
                        .fixedSize()
                        .accessibilityHint("Opens Settings → AI Providers, where you add one")
                }
            }
            ForEach(providers) { entry in
                providerRow(entry)
            }
        }
    }

    static let providersFooter = "Withdraw stops Vela sending a provider anything: Catch me up and Recap ask again before they use it. What it already received is kept under its own policy."

    private func providerRow(_ entry: AIProviderEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind == .openAICompatible ? "server.rack" : "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.accentText])
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.system(size: 13))
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                    SettingsPill(text: Self.status(entry), tinted: entry.consented && entry.enabled)
                }
                Text(AIConsentText.destination(entry))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                if entry.kind.dataPolicyURL != nil || entry.kind.privacyPolicyURL != nil {
                    HStack(spacing: 14) {
                        if let url = entry.kind.dataPolicyURL {
                            policyLink("Data policy", url, entry)
                        }
                        if let url = entry.kind.privacyPolicyURL {
                            policyLink("Privacy policy", url, entry)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            if entry.consented {
                Button("Withdraw") { intelligence.models.withdrawConsent(entry.id) }
                    .buttonStyle(ThemedButtonStyle())
                    .accessibilityLabel("Withdraw permission for \(entry.name)")
                    .accessibilityHint("Vela sends \(entry.name) nothing until you allow it again")
            } else {
                Button("Allow…") {
                    consent = AIConsentRequest(providerID: entry.id, allowTitle: "Allow") {}
                }
                .buttonStyle(ThemedButtonStyle())
                .accessibilityLabel("Allow \(entry.name)")
                .accessibilityHint("Shows what it would be sent, and asks to allow it")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// "Allowed", "Asks first", or "Off" for a provider that's turned off.
    static func status(_ entry: AIProviderEntry) -> String {
        if !entry.enabled { return entry.consented ? "Off · allowed" : "Off" }
        return entry.consented ? "Allowed" : "Asks first"
    }

    private func policyLink(_ title: String, _ url: URL, _ entry: AIProviderEntry) -> some View {
        SettingsLinkButton(title, systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
            .fixedSize()
            .help(url.absoluteString)
            .accessibilityLabel("\(entry.kind.displayName)'s \(title.lowercased())")
            .accessibilityHint("Opens it in your browser")
    }

    // MARK: Spotlight

    private var spotlightSection: some View {
        SettingsSection("Spotlight") {
            SettingsRow(
                "Messages in Spotlight",
                detail: app.settings[.intelligenceSpotlightMessages]
                    ? "On: your saved messages are in this Mac's Spotlight index, which stays on this Mac."
                    : "Off unless you turn it on. Spotlight's index stays on this Mac."
            ) {
                SettingsLinkButton("Integrations", systemImage: SettingsPane.integrations.systemImage) { navigate(.integrations) }
                    .fixedSize()
                    .accessibilityHint("Opens Settings → Integrations, where Spotlight's settings are")
            }
        }
    }

    // MARK: Pieces

    /// A row that only explains: an icon, a title and a sentence or two.
    private func info(_ title: String, _ detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.accentText])
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
