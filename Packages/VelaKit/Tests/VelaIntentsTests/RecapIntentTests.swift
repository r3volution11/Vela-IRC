// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIntelligence
@testable import VelaIntents
import VelaStore

/// Open Recap from Siri and Shortcuts, and Catch Me Up handing a very long
/// stretch over to a Recap.
@MainActor
@Suite("Recap intent")
struct RecapIntentTests {
    private func demo() async throws -> (AppModel, NetworkSession, BufferModel) {
        let app = AppModel.demo()
        await app.ready()
        let libera = try #require(app.sessions.first { $0.displayName == "Libera.Chat" })
        return (app, libera, try #require(libera.buffer(named: "#vela")))
    }

    @Test func theScopeAskedFor() async throws {
        let (app, libera, vela) = try await demo()
        let services = IntelligenceServices.demo()
        let channel = ChannelEntity(buffer: vela, session: libera)

        let one = try RecapIntent.scope(channel: channel, person: nil, network: nil, span: .lastHour, app: app, services: services)
        #expect(one == RecapScope(place: .buffer(vela.id), span: .last(minutes: 60), output: .summary))
        #expect(RecapIntent.dialog(for: one, app: app) == "Opening a Recap of #vela in Vela.")

        // A person's Recap covers the channel's network: your private
        // conversation with them too.
        let person = try RecapIntent.scope(channel: channel, person: "@wren ", network: nil, span: .sinceUnread, app: app, services: services)
        #expect(person == RecapScope(place: .network(libera.id), person: "wren"))
        #expect(RecapIntent.dialog(for: person, app: app) == "Opening a Recap of wren in Vela.")

        let network = try RecapIntent.scope(channel: nil, person: nil, network: NetworkEntity(session: libera), span: .today, app: app, services: services)
        #expect(network.place == .network(libera.id))
        #expect(network.span == .today)

        let everything = try RecapIntent.scope(channel: nil, person: nil, network: nil, span: .lastWeek, app: app, services: services)
        #expect(everything.place == .everywhere)
        #expect(everything.span == .last(minutes: 10_080))
        #expect(RecapIntent.dialog(for: everything, app: app) == "Opening a Recap of all your networks in Vela.")
    }

    @Test func withoutAppleIntelligenceItsALog() async throws {
        let (app, _, _) = try await demo()
        let services = IntelligenceServices(availability: .fixed(.turnedOff), summarizer: CannedSummarizer())
        let scope = try RecapIntent.scope(channel: nil, person: nil, network: nil, span: .today, app: app, services: services)
        #expect(scope.output == .log)
    }

    @Test func turnedOffSiriSaysSo() async throws {
        let (app, _, _) = try await demo()
        #expect(RecapIntent.refusal(app.settings) == nil)
        app.settings[.intelligenceRecap] = false
        defer { app.settings[.intelligenceRecap] = true }
        #expect(RecapIntent.refusal(app.settings) == "Recap is turned off in Vela's settings.")
    }

    @Test func everySpanMapsToTheWindowsQuickPicks() {
        let spans = RecapSpanOption.allCases.map(\.span)
        #expect(spans == [.sinceUnread] + RecapScope.Span.quickPicks)
    }

    @Test func aStretchLongerThanACardOpensARecap() {
        let id = BufferID(networkID: UUID(), foldedName: "#vela")
        func request(_ count: Int) -> CatchUpRequest {
            CatchUpRequest(bufferID: id, bufferName: "#vela", networkName: "Libera.Chat", ownNick: "doug", lines: (0..<count).map {
                CatchUpLine(id: UUID(), time: Date(timeIntervalSince1970: Double($0)), nick: "a", text: "x")
            })
        }
        #expect(SiriCatchUp(request(601)).handsToRecap(recapOffered: true))
        #expect(!SiriCatchUp(request(601)).handsToRecap(recapOffered: false))
        #expect(!SiriCatchUp(request(600)).handsToRecap(recapOffered: true))
        #expect(SiriCatchUp(request(1_240)).recapOpeningDialog == "That's 1240 messages in #vela. Opening a Recap in Vela.")
    }
}
