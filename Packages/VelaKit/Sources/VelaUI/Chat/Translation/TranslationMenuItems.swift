// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore

/// Translation items in a channel's or conversation's context menu.
struct TranslationBufferMenuItems: View {
    let buffer: BufferModel

    var body: some View {
        EmptyView()
    }
}

/// Translation items in a network's context menu.
struct TranslationNetworkMenuItems: View {
    let session: NetworkSession

    var body: some View {
        EmptyView()
    }
}
