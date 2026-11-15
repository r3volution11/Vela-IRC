// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

// STUB — owned by the sidebar agent. Contract: reads AppModel/settings from the
// environment, renders the compact tree or the collapsed rail, manages its own
// width (settings `sidebar.width`) and divider.
struct SidebarContainer: View {
    @Environment(\.theme) private var theme

    var body: some View {
        theme[ThemeKey.sidebarBackground].frame(width: 200)
    }
}
