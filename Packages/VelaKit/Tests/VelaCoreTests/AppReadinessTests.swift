// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore

/// Siri and Shortcuts wait on `ready()` before touching buffers.
@MainActor
@Suite("App readiness")
struct AppReadinessTests {
    @Test func demoIsReadyAfterStart() async {
        let app = AppModel.demo()
        #expect(!app.isReady)
        await app.ready()
        #expect(app.isReady)
        await app.ready()  // Already ready: returns at once.
    }

    @Test func showRequestsAreDistinct() {
        let app = AppModel.demo()
        let id = BufferID(networkID: UUID(), foldedName: "#vela")
        app.requestShow(id)
        let first = app.showRequest
        app.requestShow(id)
        #expect(app.showRequest?.bufferID == id)
        #expect(app.showRequest != first)
    }

    @Test func autoTranslateFollowsTheNetwork() {
        let app = AppModel.demo()
        let network = UUID()
        let buffer = BufferID(networkID: network, foldedName: "#vela")
        #expect(!app.isAutoTranslated(buffer))
        app.setAutoTranslated(true, network: network)
        #expect(app.isAutoTranslated(buffer))
        #expect(app.isAutoTranslated(network: network))
        app.setAutoTranslated(false, network: network)
        app.setAutoTranslated(true, for: buffer)
        #expect(app.isAutoTranslated(buffer))
        #expect(!app.isAutoTranslated(network: network))
    }
}
