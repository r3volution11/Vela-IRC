// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore

/// What demo mode starts with: the sample networks on #vela, or (for
/// screenshots of the welcome screen) no networks, or nothing selected.
@MainActor
@Suite("Demo mode's start")
struct DemoStartTests {
    @Test func sampleNetworksOnVela() {
        let app = AppModel.demo()
        #expect(app.sessions.map(\.displayName) == ["Libera.Chat", "OFTC", "Ergo Testnet"])
        #expect(app.selectedBuffer?.name == "#vela")
    }

    /// `--no-networks`: a first launch's welcome screen.
    @Test func noNetworks() {
        let app = AppModel.demo(networks: false)
        #expect(app.sessions.isEmpty)
        #expect(app.selectedBufferID == nil)
    }

    /// `--no-selection`: the networks, with no conversation open.
    @Test func nothingSelected() {
        let app = AppModel.demo(selectsChannel: false)
        #expect(app.sessions.count == 3)
        #expect(app.selectedBufferID == nil)
    }
}
