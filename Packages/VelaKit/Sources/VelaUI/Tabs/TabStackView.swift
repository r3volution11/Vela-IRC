// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

// STUB — owned by the tabs agent. Vivaldi-style two-level tab stacks:
// a server row (hidden in `.auto` mode with one network) and the selected
// server's channel/query tabs. `placement` decides chrome: `.titleBar`
// replaces the title strip (traffic-light inset, window drag, accessory
// buttons via HeaderAccessoryButtons), `.top` sits under the header, and
// `.bottom` sits above the input.
struct TabStackView: View {
    @Environment(\.theme) private var theme
    let placement: TabStackPlacement

    var body: some View {
        theme[ThemeKey.titleBarBackground].frame(height: placement == .titleBar ? 52 : 34)
    }
}
