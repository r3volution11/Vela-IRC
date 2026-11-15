// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

// STUB — owned by the sidebar agent (menus + keyboard shortcuts).
struct VelaCommands: Commands {
    let app: AppModel
    let themeStore: ThemeStore
    let uiState: UIState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Network…") { uiState.networkEditor = .new }
        }
    }
}
