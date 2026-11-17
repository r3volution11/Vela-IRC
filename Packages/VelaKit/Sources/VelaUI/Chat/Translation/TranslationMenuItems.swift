// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore

/// Translation items in a channel's or conversation's context menu.
struct TranslationBufferMenuItems: View {
    @Environment(AppModel.self) private var app
    let buffer: BufferModel

    var body: some View {
        if buffer.kind != .server {
            CommandMenuToggle(VelaCommandCatalog.autoTranslateCommand(app: app, bufferID: buffer.id))
        }
    }
}

/// Translation items in a network's context menu.
struct TranslationNetworkMenuItems: View {
    @Environment(AppModel.self) private var app
    let session: NetworkSession

    var body: some View {
        CommandMenuToggle(VelaCommandCatalog.networkAutoTranslateCommand(app: app, networkID: session.id))
    }
}
