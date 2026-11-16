// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

// STUB — owned by the command-palette agent. Shown as a top-aligned overlay of
// the main window while `uiState.commandPalette` is non-nil; dismiss by setting
// it to nil.
struct CommandPaletteView: View {
    @Environment(UIState.self) private var uiState
    let mode: CommandPaletteMode

    var body: some View {
        EmptyView()
    }
}
