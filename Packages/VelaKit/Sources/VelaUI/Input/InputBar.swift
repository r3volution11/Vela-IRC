// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

// STUB — owned by the embeds/input agent.
struct InputBar: View {
    @Environment(\.theme) private var theme
    let buffer: BufferModel
    let session: NetworkSession
    @State private var text = ""

    var body: some View {
        TextField("Message \(buffer.name)", text: $text)
            .onSubmit { session.submit(text, in: buffer); text = "" }
            .padding(12)
            .background(theme[ThemeKey.inputContainerBackground])
    }
}
