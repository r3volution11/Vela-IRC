// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Settings → Updates: whether Vela is up to date, Check for Updates, the
/// last check, and the automatic settings (`updates.checkAutomatically`,
/// `updates.installAutomatically`). In Vela Dev everything is disabled,
/// with the reason.
struct UpdatesPane: View {
    @Environment(AppModel.self) private var app
    @Environment(AppUpdates.self) private var updates
    @Environment(\.openURL) private var openURL

    static let privacyURL = URL(string: "https://velairc.app/help/privacy#updates")!

    var body: some View {
        @Bindable var settings = app.settings
        let available = updates.isAvailable
        let checks = settings[.updatesCheckAutomatically]

        SettingsPage("Updates", subtitle: "New versions of Vela when you want them, without interruptions.", pane: .updates) {
            if updates.updater.unavailableReason == .developmentBuild {
                SettingsCallout(
                    .info, UpdateStatusText.developmentBuild,
                    message: "Vela Dev never checks for or installs updates, so it can't replace itself with a release. The release from velairc.app updates itself."
                )
            }

            SettingsSection("Vela \(AppModel.appVersion)") {
                HStack(alignment: .center, spacing: 16) {
                    UpdateStatusLabel(showsLastCheck: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Check for Updates") { updates.checkForUpdates() }
                        .buttonStyle(ThemedButtonStyle())
                        .themedDisabled(!updates.canCheck)
                        .accessibilityHint(available ? "Looks for a new version of Vela now." : updates.statusLine)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 40)
            }

            SettingsSection(
                "Automatic updates",
                footer: "An update check asks velairc.app for the newest version and sends only Vela's version. Updates download from GitHub. Nothing about you or how you use Vela is sent."
            ) {
                SettingsToggle(
                    "Check for updates automatically",
                    detail: "Once a day. A new version is offered when you open Vela or come back to your Mac after a while, not while you're chatting. Off, Vela checks only when you choose Check for Updates.",
                    isOn: $settings[.updatesCheckAutomatically]
                )
                .themedDisabled(!available)
                SettingsToggle(
                    "Install updates automatically",
                    detail: "Download new versions in the background and install them the next time you quit Vela, without asking.",
                    isOn: $settings[.updatesInstallAutomatically]
                )
                .themedDisabled(!available || !checks)
            }

            HStack(spacing: 16) {
                SettingsLinkButton("What an update check sends", systemImage: "hand.raised") { openURL(Self.privacyURL) }
                    .help(Self.privacyURL.absoluteString)
            }
            .padding(.horizontal, 4)
        }
    }
}
