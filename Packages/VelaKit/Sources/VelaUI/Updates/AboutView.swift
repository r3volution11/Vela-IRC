// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Vela → About Vela: the icon, version and build, whether Vela is up to
/// date with Check for Updates and the automatic-check switch, then links
/// and credits. Drawn in the theme like Settings and What's New. Esc or ⌘W
/// closes it.
struct AboutView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 40)
                .padding(.bottom, 18)
            SettingsHairline()
            UpdateStatusPanel()
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
            SettingsHairline()
            links
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
            SettingsHairline()
            credits
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 20)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .ignoresSafeArea(.container, edges: .top)
        .themedWindowBorder()
        .background(theme[ThemeKey.settingsBackground])
        .background(ThemedWindowConfigurator(theme: theme, title: "About Vela", resizable: false))
        // Esc closes, like a panel. (⌘W is the window's own Close.)
        .background {
            Button("Close") { dismissWindow(id: WindowID.about) }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(AboutInfo.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .accessibilityAddTraits(.isHeader)
            Text(AboutInfo.versionLine)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Links

    private var links: some View {
        HStack(spacing: 14) {
            SettingsLinkButton("velairc.app") { openURL(AboutInfo.websiteURL) }
                .help(AboutInfo.websiteURL.absoluteString)
            SettingsLinkButton("What's New") { openWindow(id: WindowID.whatsNew) }
                .help("This version's release notes")
            SettingsLinkButton("License") { openURL(AboutInfo.licenseURL) }
                .help(AboutInfo.licenseURL.absoluteString)
            SettingsLinkButton("Acknowledgements") { openURL(AboutInfo.acknowledgementsURL) }
                .help(AboutInfo.acknowledgementsURL.absoluteString)
        }
        .fixedSize()
        .frame(maxWidth: .infinity)
    }

    // MARK: Credits

    private var credits: some View {
        VStack(spacing: 4) {
            ForEach(AboutInfo.credits, id: \.self) { line in
                Text(line)
            }
            if let copyright = AboutInfo.copyright {
                Text(copyright)
                    .padding(.top, 6)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }
}

/// Whether Vela is up to date, Check for Updates, and the automatic-check
/// switch (`updates.checkAutomatically`). In Vela Dev it says updates are
/// off, with the controls disabled.
private struct UpdateStatusPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(AppUpdates.self) private var updates
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var settings = app.settings
        VStack(spacing: 12) {
            UpdateStatusLabel(centered: true)
            Button("Check for Updates") { updates.checkForUpdates() }
                .buttonStyle(ThemedButtonStyle(prominent: true))
                .disabled(!updates.canCheck)
                .accessibilityHint(updates.isAvailable ? "Looks for a new version of Vela now." : updates.statusLine)
            HStack(spacing: 8) {
                Text("Check for updates automatically")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityHidden(true)
                Toggle("Check for updates automatically", isOn: $settings[.updatesCheckAutomatically])
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityHint("Once a day. A new version is offered when you open Vela, not while you're chatting.")
            }
            .disabled(!updates.isAvailable)
            .opacity(updates.isAvailable ? 1 : 0.45)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The status line: a symbol and "Vela is up to date.", "Checking for
/// updates…", "Version 1.2.0 is available." and so on. Kept current while
/// it shows (the time since the last check, too).
struct UpdateStatusLabel: View {
    @Environment(AppUpdates.self) private var updates
    @Environment(\.theme) private var theme
    var centered = false
    /// Adds "Last checked …" under a status that doesn't already say it.
    var showsLastCheck = false

    var body: some View {
        // Re-reads "Last checked 3 minutes ago" once a minute while visible.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let updater = updates.updater
            VStack(alignment: centered ? .center : .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if updater.status == .checking, updates.isAvailable {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: UpdateStatusText.systemImage(for: updater))
                            .foregroundStyle(theme[symbolColorKey(updater)])
                            .accessibilityHidden(true)
                    }
                    // Not selectable: selectable text drops out of the
                    // combined element VoiceOver reads.
                    Text(UpdateStatusText.line(for: updater, now: context.date))
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                        .multilineTextAlignment(centered ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 13))
                if showsLastCheck, updater.status != .idle, updates.isAvailable, let date = updater.lastCheckDate {
                    Text(UpdateStatusText.lastChecked(date, now: context.date))
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .padding(.leading, centered ? 0 : 22)
                }
            }
            .frame(maxWidth: centered ? .infinity : nil, alignment: centered ? .center : .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func symbolColorKey(_ updater: any AppUpdater) -> String {
        guard updater.unavailableReason == nil else { return ThemeKey.settingsSecondaryForeground }
        switch updater.status {
        case .upToDate: return ThemeKey.statusSuccess
        case .available, .readyToInstall: return ThemeKey.accent
        case .failed, .needsNewerMacOS: return ThemeKey.statusWarning
        case .idle, .checking: return ThemeKey.settingsSecondaryForeground
        }
    }
}

/// The About window's facts and links.
enum AboutInfo {
    static let name = "Vela"
    static let websiteURL = URL(string: "https://velairc.app")!
    static let licenseURL = URL(string: "https://velairc.app/help/license")!
    static let acknowledgementsURL = URL(string: "https://velairc.app/help/license#built-with")!

    /// "Version 1.1.0 (2)".
    static var versionLine: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "Version \(AppModel.appVersion)" + (build.map { " (\($0))" } ?? "")
    }

    /// What the standard About panel's credits said, plus Sparkle and the
    /// note about AI.
    static let credits = [
        "Free and open source under the Mozilla Public License 2.0.",
        "Written in Swift and SwiftUI, with GRDB.swift, ZIPFoundation and Sparkle.",
        "With thanks to ircdocs, IRCv3 and the authors of the themes Vela ports.",
        "Vela was made with the help of AI.",
    ]

    /// The app's copyright line (`NSHumanReadableCopyright`).
    static var copyright: String? {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }
}
