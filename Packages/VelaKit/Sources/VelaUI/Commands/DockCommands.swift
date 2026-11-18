// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

extension VelaCommandCatalog {
    /// The Dock badge switch (`dock.showBadge`), for the palette.
    var dockCommands: [VelaCommand] { Self.dockCommands(context.app.settings) }

    /// Static so tests can build them from a bare settings store.
    static func dockCommands(_ settings: SettingsStore) -> [VelaCommand] {
        let isOn = settings[.dockShowBadge]
        return [
            VelaCommand(
                id: "dock.toggleBadge", category: .notifications, title: "Show Dock Badge",
                keywords: ["dock", "badge", "dock icon", "unread count", "red badge", "number", "toggle"],
                isChecked: isOn
            ) { settings[.dockShowBadge] = !isOn },
        ]
    }
}
