// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

extension VelaCommandCatalog {
    /// "Save Message History" (`history.save`) and "Delete Saved History…"
    /// for the palette. Questions are asked in the main window, where the
    /// palette is.
    var historyCommands: [VelaCommand] {
        let app = context.app
        let uiState = context.uiState
        let saves = app.settings[.historySave]
        return [
            VelaCommand(
                id: "history.toggleSave", category: .chat, title: "Save Message History",
                keywords: ["history", "privacy", "messages", "database", "scrollback", "keep", "store", "toggle"],
                isEnabled: app.database != nil, isChecked: saves
            ) {
                HistorySaving.setSaving(!saves, app: app) { uiState.historyDialog = .stopSaving }
            },
            VelaCommand(
                id: "history.delete", category: .chat, title: "Delete Saved History…",
                keywords: ["history", "privacy", "messages", "clear", "erase", "remove", "database"],
                isEnabled: HistorySaving.canDelete(app)
            ) { uiState.historyDialog = .delete },
        ]
    }
}
