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

        SettingsPage("Media", subtitle: "Inline images, link previews and video players, and where they're allowed to load from.", pane: .media) {
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
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Link previews")
                SettingsCard {
                    SettingsToggle(
                        "Show link previews",
                        detail: "Title, description and image for web pages.",
                        isOn: $settings[.mediaShowLinkCards]
                    )
                }
                HStack(alignment: .top, spacing: 12) {
                    linkSizeCard(.minimal, title: "Minimal", subtitle: "One line: site, title and a tiny thumbnail.")
                    linkSizeCard(.standard, title: "Standard", subtitle: "Title and description beside a thumbnail.")
                    linkSizeCard(.large, title: "Large", subtitle: "A full card with a large image underneath.")
                }
                .padding(.top, 2)
                .opacity(showsLinkCards ? 1 : 0.6)
                if !showsLinkCards {
                    footnote("Sizes apply when link previews are on.")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Videos")
                HStack(alignment: .top, spacing: 12) {
                    videoStyleCard(.player, title: "Player", subtitle: "A large thumbnail with ▶ that plays in place.")
                    videoStyleCard(.compact, title: "Compact", subtitle: "One line with ▶; the player opens underneath.")
                    videoStyleCard(
                        .off,
                        title: "Off",
                        subtitle: showsLinkCards
                            ? "No player: video links get a link preview."
                            : "No player. With link previews off, video links stay plain links."
                    )
                }
                // What Off shows is on its card, which follows the link
                // previews switch.
                footnote("The player loads from the video site only when you press ▶.")
            }

            SettingsSection("Images") {
                SettingsSegmentedRow(
                    title: "Size",
                    detail: "Thumbnails keep images and GIFs small; click one to see it full size.",
                    selection: $settings[.mediaImageSize],
                    options: [(.full, "Full size"), (.thumbnail, "Thumbnail")]
                )
                SettingsSliderRow(
                    title: "Maximum image height",
                    detail: showsThumbnails ? "Applies to full-size images." : "Taller images are scaled down to fit.",
                    value: $settings[.mediaMaxImageHeight],
                    range: 120...800,
                    step: 10,
                    format: SettingsFormat.points
                )
                .disabled(showsThumbnails)
                .opacity(showsThumbnails ? 0.5 : 1)
                SettingsRow("Largest image to load automatically", detail: "Bigger images show a link to open them in your browser instead.", labelsControl: true) {
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
                SettingsToggle(
                    "Blur images until clicked",
                    detail: "Images, GIFs and video thumbnails stay blurred until you click them. To blur only some channels, use a channel's right-click menu.",
                    isOn: $settings[.mediaBlurImages]
                )
                let blurred = settings[.mediaBlurredBuffers]
                if !blurred.isEmpty {
                    SettingsRow(
                        Self.blurredTitle(blurred),
                        detail: settings[.mediaBlurImages]
                            ? "Images are blurred everywhere while the switch above is on."
                            : "Set from a channel's or network's right-click menu."
                    ) {
                        Button("Clear") { settings[.mediaBlurredBuffers] = [] }
                            .buttonStyle(ThemedButtonStyle())
                            .accessibilityLabel("Stop blurring images in these channels")
                    }
                }
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

    /// "Blurred in 2 channels", counting whole networks (`"<uuid>/*"`) apart.
    static func blurredTitle(_ entries: [String]) -> String {
        let networks = entries.count(where: { $0.hasSuffix("/*") })
        let channels = entries.count - networks
        func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        let parts = [channels > 0 ? count(channels, "channel") : nil, networks > 0 ? count(networks, "network") : nil]
        return "Blurred in " + parts.compactMap { $0 }.joined(separator: " and ")
    }

    private var showsLinkCards: Bool { app.settings[.mediaShowLinkCards] }
    private var showsThumbnails: Bool { app.settings[.mediaImageSize] == .thumbnail }

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

    // MARK: Sizes

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme[ThemeKey.settingsForeground])
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
    }

    /// Small print under a group, like a section footer.
    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    /// The illustration drawn with the user's theme, in the Modern layout so
    /// the cards compare only the preview.
    private func sizePreviewConfig() -> LayoutSchematicConfig {
        var config = LayoutSchematicConfig(settings: app.settings)
        config.chatLayout = .grouped
        config.monospace = false
        return config
    }

    private func linkSizeCard(_ size: LinkPreviewSize, title: String, subtitle: String) -> some View {
        var config = sizePreviewConfig()
        config.linkPreviewSize = size
        // Show the size even while previews are off; the cards are dimmed.
        config.showLinkCards = true
        return choiceCard(
            title,
            subtitle: subtitle,
            isSelected: app.settings[.mediaLinkPreviewSize] == size,
            select: { app.settings[.mediaLinkPreviewSize] = size },
            preview: LayoutSchematic(config: config, theme: theme, scope: .media)
        )
    }

    private func videoStyleCard(_ style: VideoEmbedStyle, title: String, subtitle: String) -> some View {
        var config = sizePreviewConfig()
        config.videoStyle = style
        return choiceCard(
            title,
            subtitle: subtitle,
            isSelected: app.settings[.mediaVideos] == style,
            select: { app.settings[.mediaVideos] = style },
            preview: LayoutSchematic(config: config, theme: theme, scope: .video)
        )
    }

    private func choiceCard(
        _ title: String,
        subtitle: String,
        isSelected: Bool,
        select: @escaping () -> Void,
        preview: LayoutSchematic
    ) -> some View {
        SettingsChoiceCard(
            title,
            subtitle: subtitle,
            isSelected: isSelected,
            action: { withAnimation(.snappy(duration: 0.2)) { select() } },
            preview: {
                preview
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme[ThemeKey.settingsBorder])
                    )
            }
        )
    }
}
