// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

// STUB — owned by the sidebar agent.
struct MemberListView: View {
    @Environment(\.theme) private var theme
    let buffer: BufferModel
    let session: NetworkSession

    var body: some View {
        theme[ThemeKey.memberListBackground]
    }
}
