// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import Testing
@testable import VelaIntelligence

/// The live availability follows `SystemLanguageModel`, which is
/// observable; here an observable stand-in plays the system model.
@MainActor
@Suite("Intelligence availability")
struct IntelligenceAvailabilityTests {
    @Observable
    final class FakeModel {
        var status: IntelligenceStatus = .modelNotReady
        @ObservationIgnored var reads = 0

        func read() -> IntelligenceStatus {
            reads += 1
            return status
        }
    }

    /// Lets queued main-actor work run until `condition` holds (or gives up).
    private func settle(_ condition: () -> Bool) async {
        var tries = 0
        while !condition(), tries < 200 {
            tries += 1
            await Task.yield()
        }
    }

    @Test func followsTheModelWithoutBeingAsked() async {
        let model = FakeModel()
        let availability = IntelligenceAvailability(probe: model.read, tracksChanges: true)
        #expect(availability.status == .modelNotReady)

        // The download finishes while Vela is in front: no activation, no refresh() call.
        model.status = .available
        await settle { availability.status == .available }
        #expect(availability.status == .available)

        // And it keeps following.
        model.status = .turnedOff
        await settle { availability.status == .turnedOff }
        #expect(availability.status == .turnedOff)
    }

    @Test func readsOncePerChangeHoweverOftenItsRefreshed() async {
        let model = FakeModel()
        let availability = IntelligenceAvailability(probe: model.read, tracksChanges: true)
        // Activations and intents refresh too; they mustn't pile up observers.
        for _ in 0..<5 { availability.refresh() }
        let before = model.reads
        model.status = .available
        await settle { availability.status == .available }
        for _ in 0..<20 { await Task.yield() }
        #expect(model.reads == before + 1)
    }

    @Test func untrackedProbeOnlyChangesOnRefresh() async {
        let model = FakeModel()
        let availability = IntelligenceAvailability(probe: model.read)
        model.status = .available
        for _ in 0..<20 { await Task.yield() }
        #expect(availability.status == .modelNotReady)
        availability.refresh()
        #expect(availability.status == .available)
    }
}
