// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaStore

extension VelaCommandCatalog {
    /// Where channels open and whether the New line shows, for the palette.
    var unreadCommands: [VelaCommand] { Self.unreadCommands(context.app.settings) }

    /// Static so tests can build them from a bare settings store.
    static func unreadCommands(_ settings: SettingsStore) -> [VelaCommand] {
        let opensAtNewest = settings[.chatOpenAt] == .newest
        let showsNewLine = settings[.chatShowUnreadMarker]
        return [
            VelaCommand(
                id: "chat.toggleOpenAtNewest", category: .chat, title: "Open Channels at Newest Messages",
                keywords: ["unread", "first unread", "jump", "scroll", "bottom", "stick", "latest", "classic", "toggle"],
                isChecked: opensAtNewest
            ) { settings[.chatOpenAt] = opensAtNewest ? .firstUnread : .newest },
            VelaCommand(
                id: "chat.toggleNewLine", category: .chat, title: "Show New Line",
                keywords: ["unread marker", "new messages", "divider", "separator", "classic", "toggle"],
                isChecked: showsNewLine
            ) { settings[.chatShowUnreadMarker].toggle() },
        ]
    }
}
