// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaStore

extension VelaCommandCatalog {
    /// "Chat: Timestamps on the Left" and so on, for the current layout.
    var timestampPositionCommands: [VelaCommand] { Self.timestampPositionCommands(context.app.settings) }

    /// Static so tests can build them from a bare settings store. Each
    /// layout keeps its own position, so these set the current one's.
    /// Choosing one also turns timestamps on.
    static func timestampPositionCommands(_ settings: SettingsStore) -> [VelaCommand] {
        let layout = settings[.chatLayout]
        let key = SettingKey<TimestampPosition>.chatTimestampPosition(for: layout)
        let current = settings[.chatShowTimestamps] ? settings[key] : nil
        let layoutWords: [String] = switch layout {
        case .classic: ["classic"]
        case .grouped: ["modern", "grouped"]
        case .columns: ["compact", "columns"]
        }
        func command(_ position: TimestampPosition, _ title: String, keywords: [String]) -> VelaCommand {
            VelaCommand(
                id: "chat.timestampPosition.\(position.rawValue)", category: .chat, title: title,
                keywords: ["time", "timestamps", "clock", "position", "move", "layout"] + layoutWords + keywords,
                isChecked: current == position
            ) {
                settings[key] = position
                if !settings[.chatShowTimestamps] { settings[.chatShowTimestamps] = true }
            }
        }
        return [
            command(.left, "Timestamps on the Left", keywords: ["left", "before", "margin", "gutter"]),
            command(.right, "Timestamps on the Right", keywords: ["right", "after", "end", "edge"]),
            command(.top, "Timestamps at the Top", keywords: ["top", "above", "header", "name"]),
            command(.bottom, "Timestamps at the Bottom", keywords: ["bottom", "below", "under"]),
        ]
    }
}
