// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntents
import VelaStore

@MainActor
@Suite("Catch Me Up intent")
struct CatchMeUpIntentTests {
    /// With Catch me up turned off in Vela's settings, Siri says so
    /// instead of summarizing.
    @Test func answersThatItIsTurnedOff() {
        let app = AppModel.demo()
        #expect(CatchMeUpIntent.refusal(app.settings) == nil)
        app.settings[.intelligenceCatchUp] = false
        #expect(CatchMeUpIntent.refusal(app.settings) == "Catch me up is turned off in Vela's settings.")
    }

    /// It runs in the background, and can bring Vela forward to the card
    /// when a stretch is too long to wait for.
    @Test func canContinueInVela() {
        #expect(CatchMeUpIntent.supportedModes.contains(.background))
        #expect(CatchMeUpIntent.supportedModes.contains(.foreground(.dynamic)))
    }
}
