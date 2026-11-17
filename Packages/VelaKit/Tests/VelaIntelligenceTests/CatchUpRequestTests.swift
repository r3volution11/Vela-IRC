// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
@testable import VelaIntelligence

@Suite("Intelligence status")
struct IntelligenceStatusTests {
    @Test func onlyAvailableIsAvailable() {
        #expect(IntelligenceStatus.available.isAvailable)
        #expect(!IntelligenceStatus.turnedOff.isAvailable)
        #expect(!IntelligenceStatus.modelNotReady.isAvailable)
    }

    @Test func turnedOffLinksToSystemSettings() {
        #expect(IntelligenceStatus.turnedOff.settingsURL != nil)
        #expect(IntelligenceStatus.deviceNotEligible.settingsURL == nil)
    }

    @Test func fixedAvailabilityKeepsItsStatus() {
        let availability = IntelligenceAvailability.fixed(.modelNotReady)
        availability.refresh()
        #expect(availability.status == .modelNotReady)
    }
}
