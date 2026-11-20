// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// "What's New in Vela <version>": important notices for this Mac first,
/// then the release's changelog section, and a link to the full
/// changelog. Opens on the first launch of a new version
/// (``WhatsNewLaunch``) and from Help → What's New in Vela. Esc, Return or
/// ⌘W closes it.
struct WhatsNewView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    /// Parsed once per window, not on every redraw.
    @State private var content = WhatsNewContent.load(version: AppModel.appVersion)

    var body: some View {
        let notices = WhatsNewNotice.current(in: WhatsNewContext(
            version: content.version,
            settings: app.settings,
            record: app.launchRecord
        ))

        VStack(spacing: 0) {
            header
            SettingsHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !notices.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(notices) { notice in noticeView(notice) }
                        }
                    }
                    if content.blocks.isEmpty {
                        Text("The release notes aren't available. See the full changelog on the website.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    } else {
                        ChangelogBlocksView(blocks: content.displayBlocks)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            SettingsHairline()
            footer
        }
        .ignoresSafeArea(.container, edges: .top)
        .themedWindowBorder()
        .background(theme[ThemeKey.settingsBackground])
        .background(ThemedWindowConfigurator(theme: theme, title: "What's New in Vela", resizable: true))
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 760, minHeight: 420, idealHeight: 620)
        // Esc closes, like a sheet. (⌘W is the window's own Close.)
        .background {
            Button("Close") { dismissWindow(id: WindowID.whatsNew) }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("What's New in Vela \(content.version)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        // Clear of the traffic lights in the hidden title bar.
        .padding(.top, 40)
        .padding(.bottom, 16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            SettingsLinkButton("Full changelog", systemImage: "arrow.up.right.square") {
                openURL(Changelog.fullChangelogURL)
            }
            .help(Changelog.fullChangelogURL.absoluteString)
            .accessibilityHint("Opens velairc.app/changelog in your browser.")
            Spacer()
            Button("Continue") { dismissWindow(id: WindowID.whatsNew) }
                .buttonStyle(ThemedButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    // MARK: Notices

    private func noticeView(_ notice: WhatsNewNotice) -> some View {
        SettingsCallout(.info, notice.title, message: notice.message) {
            if let paneID = notice.settingsPane, let pane = SettingsPane(rawValue: paneID) {
                Button(notice.settingsButtonTitle ?? "Open Settings") {
                    uiState.settingsEditor.requestedPane = pane
                    openSettings()
                }
                .buttonStyle(ThemedButtonStyle())
            }
        }
    }
}

/// What the window shows, read from the bundled changelog.
struct WhatsNewContent {
    var version: String
    /// "November 18, 2026", or which release the notes are from when this
    /// version has none of its own.
    var subtitle: String?
    var blocks: [Changelog.Block]
    /// `blocks` with their inline markdown parsed, once.
    var displayBlocks: [ChangelogDisplayBlock]

    init(version: String, subtitle: String?, blocks: [Changelog.Block]) {
        self.version = version
        self.subtitle = subtitle
        self.blocks = blocks
        displayBlocks = blocks.enumerated().map { ChangelogDisplayBlock(id: $0, block: $1) }
    }

    static func load(version: String) -> WhatsNewContent {
        make(version: version, changelog: Changelog.bundledText())
    }

    static func make(version: String, changelog: String?) -> WhatsNewContent {
        guard let changelog, let section = Changelog.section(for: version, in: changelog) else {
            return WhatsNewContent(version: version, subtitle: nil, blocks: [])
        }
        let subtitle: String?
        if section.version == version {
            subtitle = section.date.flatMap(formattedDate) ?? section.date
        } else if section.version == "Unreleased" {
            subtitle = "Changes since the last release"
        } else {
            subtitle = "Notes from Vela \(section.version)"
        }
        return WhatsNewContent(version: version, subtitle: subtitle, blocks: Changelog.blocks(from: section.body))
    }

    /// `2026-11-18` → "November 18, 2026".
    private static func formattedDate(_ text: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: text) else { return nil }
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC")!))
    }
}

/// One block with its text ready to draw.
struct ChangelogDisplayBlock: Identifiable {
    let id: Int
    let block: Changelog.Block
    let text: AttributedString

    init(id: Int, block: Changelog.Block) {
        self.id = id
        self.block = block
        switch block {
        case .heading(_, let text), .paragraph(let text), .item(_, _, let text):
            self.text = Changelog.inline(text)
        }
    }
}

/// A changelog section's headings, paragraphs and lists.
private struct ChangelogBlocksView: View {
    @Environment(\.theme) private var theme
    let blocks: [ChangelogDisplayBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                blockView(block)
                    .padding(.top, block.id > 0 && block.isHeading ? 12 : 0)
            }
        }
        .tint(theme[ThemeKey.accentText])
    }

    @ViewBuilder
    private func blockView(_ display: ChangelogDisplayBlock) -> some View {
        switch display.block {
        case .heading(let level, _):
            Text(display.text)
                .font(.system(size: level <= 3 ? 15 : 13, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(display.text)
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .fixedSize(horizontal: false, vertical: true)
        case .item(let level, let marker, _):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker ?? (level == 0 ? "•" : "◦"))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .accessibilityHidden(marker == nil)
                Text(display.text)
                    .font(.system(size: 13))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(level) * 18)
        }
    }
}

private extension ChangelogDisplayBlock {
    var isHeading: Bool {
        if case .heading = block { true } else { false }
    }
}
