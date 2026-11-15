// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore

/// All of Vela's scenes. The app target only instantiates this.
public struct VelaScenes: Scene {
    public init() {}

    public var body: some Scene {
        WindowGroup("Vela") {
            PlaceholderRootView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct PlaceholderRootView: View {
    var body: some View {
        ZStack {
            Color(red: 0.13, green: 0.14, blue: 0.16).ignoresSafeArea()
            Text("Vela")
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
