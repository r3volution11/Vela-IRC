// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// Vela → About Vela (Vela's own window, in place of the standard panel),
/// then Check for Updates….
struct AboutCommands: Commands {
    let updates: AppUpdates

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            AboutMenuItems(updates: updates)
        }
    }
}

private struct AboutMenuItems: View {
    @Environment(\.openWindow) private var openWindow
    let updates: AppUpdates

    var body: some View {
        Button(AboutCommandTitles.about) { openWindow(id: WindowID.about) }
        // Disabled in Vela Dev, and while an update downloads in the
        // background.
        Button(AboutCommandTitles.checkForUpdates) { updates.checkForUpdates() }
            .disabled(!updates.canCheck)
    }
}

/// The menu's and the palette's titles, in one place.
enum AboutCommandTitles {
    static let about = "About Vela"
    static let checkForUpdates = "Check for Updates…"
}

extension VelaCommandCatalog {
    /// "Help: About Vela" and "Help: Check for Updates…" for the palette.
    var aboutCommands: [VelaCommand] {
        let openWindow = context.openWindow
        var commands = [
            VelaCommand(
                id: "help.about", category: .help, title: AboutCommandTitles.about,
                keywords: ["version", "build", "credits", "license", "acknowledgements", "info"]
            ) { openWindow(id: WindowID.about) },
        ]
        if let updates = context.updates {
            commands.append(VelaCommand(
                id: "help.checkForUpdates", category: .help, title: AboutCommandTitles.checkForUpdates,
                keywords: ["update", "upgrade", "new version", "sparkle", "download", "install", "latest"],
                isEnabled: updates.canCheck
            ) { updates.checkForUpdates() })
        }
        return commands
    }
}
