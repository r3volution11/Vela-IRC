// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore

// STUB — owned by the settings agent. Presented as a sheet from the main window.
struct NetworkEditorView: View {
    let target: NetworkEditorTarget
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Network editor")
            Button("Close") { dismiss() }
        }
        .frame(width: 480, height: 360)
    }
}
