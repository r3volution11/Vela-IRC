// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore

// STUB — owned by the embeds/input agent. Renders inline media for the links
// in one chat line (images, link cards, video facades). Empty when the line
// has no links or media is disabled for the buffer.
struct MessageEmbedsView: View {
    let line: ChatLine
    let bufferID: BufferID

    var body: some View {
        EmptyView()
    }
}
