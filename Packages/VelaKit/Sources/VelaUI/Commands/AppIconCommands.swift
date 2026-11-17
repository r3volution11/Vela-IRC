// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

extension VelaCommandCatalog {
    /// The Dock icon (`appearance.appIcon`), for the palette.
    var appIconCommands: [VelaCommand] { Self.appIconCommands(context.app.settings) }

    /// Static so tests can build them from a bare settings store.
    static func appIconCommands(_ settings: SettingsStore) -> [VelaCommand] {
        let current = settings[.appearanceAppIcon]
        let keywords = ["dock", "dock icon", "app icon", "icon", "colorway", "colourway"]
        let next = VelaCommand(
            id: "appearance.nextAppIcon", category: .appearance, title: "Next App Icon",
            keywords: keywords + ["cycle", "change"]
        ) { settings[.appearanceAppIcon] = DockIcon.next(after: current) }
        return [next] + AppIcon.allCases.map { icon in
            VelaCommand(
                id: "appearance.appIcon.\(icon.rawValue)", category: .appearance, title: "App Icon: \(DockIcon.title(icon))",
                keywords: keywords + (icon == .vela ? ["default", "standard", "reset"] : []),
                isChecked: current == icon
            ) { settings[.appearanceAppIcon] = icon }
        }
    }
}
