// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import VelaIntents

/// Vela's App Intents live in the VelaIntents package module; this brings
/// them into the app's App Intents metadata.
struct VelaAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [VelaIntentsPackage.self]
    }
}

/// Phrases Siri and Spotlight know without any setup. Each one names the
/// app; channel phrases list your channels (refreshed as they change).
struct VelaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CatchMeUpIntent(),
            phrases: [
                "Catch me up in \(.applicationName)",
                "Catch me up on \(\.$channel) in \(.applicationName)",
                "What did I miss in \(.applicationName)",
                "Summarize \(\.$channel) in \(.applicationName)",
            ],
            shortTitle: "Catch Me Up",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: RecapIntent(),
            phrases: [
                "Open a recap in \(.applicationName)",
                "Recap my channels in \(.applicationName)",
                "Recap \(\.$channel) in \(.applicationName)",
                "Recap \(\.$span) in \(.applicationName)",
            ],
            shortTitle: "Recap",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: CheckMentionsIntent(),
            phrases: [
                "Check my \(.applicationName) mentions",
                "Check mentions in \(.applicationName)",
                "Who mentioned me in \(.applicationName)",
            ],
            shortTitle: "Check Mentions",
            systemImageName: "at"
        )
        AppShortcut(
            intent: SendMessageIntent(),
            phrases: [
                "Send a message with \(.applicationName)",
                "Send a message to \(\.$channel) with \(.applicationName)",
                "Message \(\.$channel) in \(.applicationName)",
            ],
            shortTitle: "Send Message",
            systemImageName: "paperplane"
        )
        AppShortcut(
            intent: OpenChannelIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)",
                "Go to \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Channel",
            systemImageName: "number"
        )
        AppShortcut(
            intent: SetAwayIntent(),
            phrases: [
                "Set me away in \(.applicationName)",
                "Mark me away in \(.applicationName)",
            ],
            shortTitle: "Set Away",
            systemImageName: "moon"
        )
        AppShortcut(
            intent: SetBackIntent(),
            phrases: [
                "Set me back in \(.applicationName)",
                "I'm back in \(.applicationName)",
            ],
            shortTitle: "Set Back",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: MarkAllAsReadIntent(),
            phrases: [
                "Mark everything as read in \(.applicationName)",
                "Mark all as read in \(.applicationName)",
            ],
            shortTitle: "Mark All as Read",
            systemImageName: "checkmark.circle"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .navy
}
