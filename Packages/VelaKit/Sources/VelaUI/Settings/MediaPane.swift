// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaMedia
import VelaStore
import VelaTheme

/// Inline images, link previews, video players and the sites they may
/// come from.
struct MediaPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var settings = app.settings

        SettingsPage("Media", subtitle: "Inline images, link previews and video players, and where they're allowed to load from.") {
            SettingsSection("Loading") {
                SettingsToggle(
                    "Load previews automatically",
                    detail: "Show images and link previews as messages arrive. When off, click a link's preview button to load it.",
                    isOn: $settings[.mediaAutoLoad]
                )
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme[ThemeKey.statusWarning])
                        .accessibilityHidden(true)
                    Text("Loading previews contacts the linked site and reveals your IP address to it. Turn this off, or use Site rules below to limit previews to sites you trust, if that matters to you.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Privacy note: Loading previews contacts the linked site and reveals your IP address to it.")
                SettingsToggle("Link cards", detail: "Title, description and image for web pages.", isOn: $settings[.mediaShowLinkCards])
                SettingsToggle("Video players", detail: "Embedded players for YouTube, Vimeo and similar links.", isOn: $settings[.mediaLoadVideoEmbeds])
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Presentation")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
                HStack(alignment: .top, spacing: 14) {
                    presentationCard(.full, title: "Full", subtitle: "Cards, large images and players, like Discord or Slack.")
                    presentationCard(.compact, title: "Compact", subtitle: "One-line titles with small thumbnails; players open on demand.")
                }
            }

            SettingsSection("Images") {
                SettingsRow("Largest image to load automatically", detail: "Bigger images show a placeholder you can click.", labelsControl: true) {
                    HStack(spacing: 6) {
                        Stepper(value: $settings[.mediaMaxImageSizeMB], in: 1...100, step: 1) {
                            Text("\(Int(settings[.mediaMaxImageSizeMB])) MB")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                                .frame(minWidth: 48, alignment: .trailing)
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Largest image to load automatically")
                        .accessibilityValue("\(Int(settings[.mediaMaxImageSizeMB])) megabytes")
                    }
                }
                SettingsSliderRow(
                    title: "Maximum image height",
                    detail: "Taller images are scaled down to fit.",
                    value: $settings[.mediaMaxImageHeight],
                    range: 120...800,
                    step: 10,
                    format: SettingsFormat.points
                )
            }

            SettingsSection(
                "Restrictions",
                footer: "For exceptions, click “Show once” or “Always allow” on a blocked preview, or add a site rule below."
            ) {
                SettingsToggle(
                    "Hide previews of adult sites",
                    detail: "Blocks previews from sites on a list bundled with Vela (checked on your Mac, never online) and from pages that label themselves adult. Links stay clickable.",
                    isOn: $settings[.mediaFilterAdultSites]
                )
            }

            siteRulesSection(restrictToListed: $settings[.mediaRestrictToAllowed])

            if settings[.mediaDisabledBuffers].count > 0 {
                SettingsSection(footer: "Turn inline media back on from a channel's context menu.") {
                    SettingsRow(
                        "Channels without inline media",
                        detail: "\(settings[.mediaDisabledBuffers].count) \(settings[.mediaDisabledBuffers].count == 1 ? "channel or network has" : "channels or networks have") inline media turned off."
                    ) {
                        Button("Turn Media Back On") { settings[.mediaDisabledBuffers] = [] }
                            .buttonStyle(ThemedButtonStyle())
                    }
                }
            }
        }
    }

    /// The rules editor, then the switch that turns the rules into an allow
    /// list. `app.siteRules` still folds in the older blocked and allowed
    /// domain lists until they're migrated, so those show up here too.
    private func siteRulesSection(restrictToListed: Binding<Bool>) -> some View {
        let rules = app.siteRules.entries
        let listedCount = rules.values.count(where: { $0 != .block })
        return SettingsSection(
            "Site rules",
            footer: "Everything shows previews, images and players. Text only shows titles and descriptions, without images or players. Nothing never contacts the site. Most specific rule wins: a rule for i.example.com beats one for example.com."
        ) {
            SiteRulesEditor(
                rules: rules,
                emptyMessage: "No site rules. Add a site to always show, limit or block its previews.",
                setRule: { access, domain in app.setSiteRule(access, forDomain: domain) }
            )
            SettingsToggle(
                "Only load previews from sites listed here",
                detail: restrictToListed.wrappedValue && listedCount == 0
                    ? "No site is set to Everything or Text only yet, so no previews load."
                    : "Sites set to Everything or Text only count as listed. Previews from other sites are blocked.",
                isOn: restrictToListed
            )
        }
    }

    private func presentationCard(_ presentation: MediaPresentation, title: String, subtitle: String) -> some View {
        var config = LayoutSchematicConfig(settings: app.settings)
        config.mediaPresentation = presentation
        config.chatLayout = .grouped
        config.monospace = false
        return SettingsChoiceCard(
            title,
            subtitle: subtitle,
            isSelected: app.settings[.mediaPresentation] == presentation,
            action: { withAnimation(.snappy(duration: 0.2)) { app.settings[.mediaPresentation] = presentation } },
            preview: {
                LayoutSchematic(config: config, theme: theme, scope: .media)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme[ThemeKey.settingsBorder])
                    )
            }
        )
    }
}
