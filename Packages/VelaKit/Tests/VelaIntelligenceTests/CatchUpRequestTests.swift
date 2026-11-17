// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
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

@MainActor
@Suite("Catch me up requests")
struct CatchUpBufferRequestTests {
    /// A deleted message's text stays in memory; it never reaches the model.
    @Test func deletedMessagesAreLeftOut() async throws {
        let app = AppModel.demo()
        await app.ready()
        let session = try #require(app.sessions.first { $0.displayName == "Libera.Chat" })
        let vela = try #require(session.buffer(named: "#vela"))
        let before = CatchUpRequest(buffer: vela, session: session, since: .distantPast)
        let index = try #require(vela.lines.lastIndex { $0.kind == .message && !$0.isSelf })
        let deleted = vela.lines[index]
        vela.lines[index].isRedacted = true

        let request = CatchUpRequest(buffer: vela, session: session, since: .distantPast)
        #expect(request.lines.count == before.lines.count - 1)
        #expect(!request.lines.contains { $0.id == deleted.id })
    }
}
