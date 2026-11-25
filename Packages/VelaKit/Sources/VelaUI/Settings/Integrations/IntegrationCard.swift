// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaTheme

/// One tool on Settings → Integrations: its icon, name, what it does and
/// whether it's ready, its buttons and a "Learn more" link, then any rows
/// of its own (settings, examples) on the same card, and a footer.
struct IntegrationCard<Actions: View, Rows: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    let title: String
    let icon: IntegrationIcon
    let summary: String
    var status: IntegrationStatus?
    let learnMore: URL
    var footer: String?
    let actions: Actions
    let rows: Rows

    init(
        _ title: String,
        icon: IntegrationIcon,
        summary: String,
        status: IntegrationStatus? = nil,
        learnMore: URL,
        footer: String? = nil,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder rows: () -> Rows
    ) {
        self.title = title
        self.icon = icon
        self.summary = summary
        self.status = status
        self.learnMore = learnMore
        self.footer = footer
        self.actions = actions()
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCard {
                header
                rows
            }
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            IntegrationIconView(icon: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                if let status {
                    IntegrationStatusLabel(status: status)
                        .padding(.top, 2)
                }
                HStack(spacing: 12) {
                    actions
                    SettingsLinkButton("Learn more", systemImage: "book") { openURL(learnMore) }
                        .help(learnMore.absoluteString)
                        .accessibilityLabel("Learn more about \(title)")
                        .accessibilityHint("Opens the guide on velairc.app in your browser.")
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .accessibilityElement(children: .contain)
        .devTag(
            "Integration",
            tokens: [ThemeKey.settingsForeground, ThemeKey.settingsSecondaryForeground],
            font: .system(size: 14, weight: .semibold),
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        )
    }
}

extension IntegrationCard where Rows == EmptyView {
    init(
        _ title: String,
        icon: IntegrationIcon,
        summary: String,
        status: IntegrationStatus? = nil,
        learnMore: URL,
        footer: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(title, icon: icon, summary: summary, status: status, learnMore: learnMore, footer: footer, actions: actions, rows: { EmptyView() })
    }
}

// MARK: - Icon

/// A card's icon: the app's own icon when it's installed, otherwise a
/// symbol on an accent tile.
enum IntegrationIcon: Equatable {
    case app(URL)
    case symbol(String)

    /// `app`'s icon, or `symbol` when it isn't installed.
    static func of(_ app: InstalledApp?, or symbol: String) -> IntegrationIcon {
        app.map { .app($0.url) } ?? .symbol(symbol)
    }
}

struct IntegrationIconView: View {
    @Environment(\.theme) private var theme
    let icon: IntegrationIcon

    static let size: CGFloat = 36

    var body: some View {
        Group {
            switch icon {
            case .app(let url):
                Image(nsImage: AppIconCache.icon(for: url))
                    .resizable()
                    .interpolation(.high)
            case .symbol(let name):
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme[ThemeKey.accent].opacity(0.14))
                    .overlay(
                        Image(systemName: name)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(theme[ThemeKey.accentText])
                    )
                    .padding(2)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }
}

/// Apps' icons, fetched from the workspace once per app.
@MainActor
enum AppIconCache {
    private static var icons: [URL: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let icon = icons[url] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[url] = icon
        return icon
    }
}

// MARK: - Status

struct IntegrationStatusLabel: View {
    @Environment(\.theme) private var theme
    let status: IntegrationStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(status.text)
                .foregroundStyle(theme[ThemeKey.settingsForeground])
            if let detail = status.detail {
                Text("·")
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                Text(detail)
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            }
        }
        .font(.system(size: 11.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([status.text, status.detail].compactMap { $0 }.joined(separator: ". "))
    }

    private var dotColor: Color {
        switch status.kind {
        case .ready: theme[ThemeKey.statusSuccess]
        case .missing: theme[ThemeKey.settingsSecondaryForeground].opacity(0.6)
        case .attention: theme[ThemeKey.statusWarning]
        case .info: theme[ThemeKey.accent]
        }
    }
}
