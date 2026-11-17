// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

extension VelaCommandCatalog {
    /// Message translation for the selected buffer.
    var translationCommands: [VelaCommand] {
        let app = context.app
        guard let buffer = app.selectedBuffer, buffer.kind != .server else { return [] }
        return [Self.autoTranslateCommand(app: app, bufferID: buffer.id)]
    }

    /// "Translate Messages Automatically" for one buffer, in the palette
    /// (the selected buffer) and buffer context menus. Checked while lines
    /// in other languages are translated as they appear; disabled (and
    /// checked) while its whole network is, which this can't undo.
    static func autoTranslateCommand(app: AppModel, bufferID: BufferID) -> VelaCommand {
        let inherited = app.isAutoTranslated(network: bufferID.networkID)
        let on = app.isAutoTranslated(bufferID)
        return VelaCommand(
            id: "buffer.toggleAutoTranslate", category: .buffer, title: "Translate Messages Automatically",
            keywords: ["translate", "translation", "language", "foreign", "channel"],
            isEnabled: !inherited, isChecked: on
        ) { app.setAutoTranslated(!on, for: bufferID) }
    }

    /// "Translate Messages Automatically" for every buffer of a network,
    /// in network context menus.
    static func networkAutoTranslateCommand(app: AppModel, networkID: UUID) -> VelaCommand {
        let on = app.isAutoTranslated(network: networkID)
        return VelaCommand(
            id: "network.toggleAutoTranslate.\(networkID.uuidString)", category: .network,
            title: "Translate Messages Automatically",
            keywords: ["translate", "translation", "language"],
            isChecked: on, showsInPalette: false
        ) { app.setAutoTranslated(!on, network: networkID) }
    }
}
