// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntelligence
@testable import VelaIntents
import VelaStore

/// Stands in for the window: records what automation asked of it.
@MainActor
final class FakeAutomationPresenter: AutomationPresenter {
    enum Call: Equatable {
        case activate
        case search(String, BufferID?, UUID?)
        case offerToJoin(String, UUID)
        case notice(String)
    }

    private(set) var calls: [Call] = []

    var notices: [String] {
        calls.compactMap { if case .notice(let message) = $0 { message } else { nil } }
    }

    func activate() { calls.append(.activate) }
    func openSearch(_ request: MessageSearchRequest) { calls.append(.search(request.query, request.bufferID, request.networkID)) }
    func offerToJoin(_ channel: String, networkID: UUID) { calls.append(.offerToJoin(channel, networkID)) }
    func notice(_ message: String) { calls.append(.notice(message)) }
}

/// The demo (Libera.Chat and Ergo Testnet connected, OFTC not), with
/// automation over it and a fake window.
@MainActor
struct AutomationFixture {
    let app: AppModel
    let services: IntelligenceServices
    let presenter: FakeAutomationPresenter
    let automation: VelaAutomation
    let libera: NetworkSession
    let oftc: NetworkSession
    let ergo: NetworkSession

    static func make() async throws -> AutomationFixture {
        try await make { _ in IntelligenceServices.demo() }
    }

    /// A Mac without Apple Intelligence, with Catch me up and Recap set to
    /// one of your own providers' models (Anthropic's).
    static func withProviderOnly() async throws -> AutomationFixture {
        try await make { app in
            let availability = IntelligenceAvailability.fixed(.deviceNotEligible)
            let models = AIModels(settings: app.settings, keys: AIKeyStore(keychain: .inMemory()), availability: availability)
            let provider = try #require(models.addProvider(.anthropic))
            app.settings[.intelligenceCatchUpModel] = "\(provider.id)/claude-opus-5-5"
            app.settings[.intelligenceRecapModel] = "\(provider.id)/claude-opus-5-5"
            return IntelligenceServices(availability: availability, summarizer: CannedSummarizer(stepDelay: .zero), models: models)
        }
    }

    static func make(services makeServices: (AppModel) throws -> IntelligenceServices) async throws -> AutomationFixture {
        let app = AppModel.demo()
        await app.ready()
        let services = try makeServices(app)
        let presenter = FakeAutomationPresenter()
        let automation = VelaAutomation(app: app, services: services, presenter: presenter)
        return AutomationFixture(
            app: app, services: services, presenter: presenter, automation: automation,
            libera: try #require(app.sessions.first { $0.displayName == "Libera.Chat" }),
            oftc: try #require(app.sessions.first { $0.displayName == "OFTC" }),
            ergo: try #require(app.sessions.first { $0.displayName == "Ergo Testnet" })
        )
    }

    func buffer(_ name: String, on session: NetworkSession) throws -> BufferModel {
        try #require(session.buffer(named: name))
    }
}

@MainActor
@Suite("vela:// link router")
struct VelaLinkRouterTests {
    private func router(_ fixture: AutomationFixture) -> VelaLinkRouter {
        // A clock that moves a second each time, so no link is ever "the same link again".
        var tick = ContinuousClock.now
        return VelaLinkRouter(automation: fixture.automation) {
            tick = tick.advanced(by: .seconds(2))
            return tick
        }
    }

    private func open(_ string: String, _ router: VelaLinkRouter) -> VelaLinkRouter.Outcome {
        router.open(URL(string: string)!)
    }

    // MARK: Showing

    @Test func opensAChannel() async throws {
        let fixture = try await AutomationFixture.make()
        let swift = try fixture.buffer("#swift", on: fixture.libera)
        #expect(open("vela://open?network=Libera.Chat&channel=%23swift", router(fixture)) == .shown)
        #expect(fixture.app.showRequest?.bufferID == swift.id)
        #expect(fixture.app.showRequest?.draft == nil)
    }

    @Test func networksByNameIgnoringCaseOrById() async throws {
        let fixture = try await AutomationFixture.make()
        let debian = try fixture.buffer("#debian", on: fixture.oftc)
        let router = router(fixture)
        #expect(open("vela://open?network=oftc&channel=debian", router) == .shown)
        #expect(fixture.app.showRequest?.bufferID == debian.id)
        #expect(open("vela://open?network=\(fixture.oftc.id.uuidString)&channel=%23debian", router) == .shown)
        #expect(fixture.app.showRequest?.bufferID == debian.id)
        #expect(open("vela://open?id=\(debian.id.description.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.replacingOccurrences(of: "#", with: "%23"))", router) == .shown)
    }

    @Test func opensAnExistingPrivateConversation() async throws {
        let fixture = try await AutomationFixture.make()
        let marisol = try fixture.buffer("marisol", on: fixture.libera)
        #expect(open("vela://open?nick=Marisol", router(fixture)) == .shown)
        #expect(fixture.app.showRequest?.bufferID == marisol.id)
    }

    /// A nick with no conversation gets one, as /query does: nothing sent.
    @Test func startsAPrivateConversation() async throws {
        let fixture = try await AutomationFixture.make()
        #expect(open("vela://open?nick=newfriend&network=Libera.Chat", router(fixture)) == .shown)
        let query = try fixture.buffer("newfriend", on: fixture.libera)
        #expect(query.kind == .query)
        #expect(query.lines.isEmpty)
        #expect(fixture.app.showRequest?.bufferID == query.id)
    }

    @Test func unknownTargetsShowANoticeAndNothingElse() async throws {
        let fixture = try await AutomationFixture.make()
        let before = fixture.app.showRequest
        let outcome = open("vela://open?network=Libera.Chat&channel=%23nowhere", router(fixture))
        guard case .refused = outcome else {
            Issue.record("Expected a refusal, got \(outcome)")
            return
        }
        #expect(fixture.app.showRequest == before)
        #expect(fixture.presenter.calls.first == .activate)
        #expect(fixture.presenter.notices == ["Vela couldn't find #nowhere on Libera.Chat."])
        #expect(fixture.libera.buffer(named: "#nowhere") == nil)
    }

    @Test func unknownNetwork() async throws {
        let fixture = try await AutomationFixture.make()
        _ = open("vela://open?network=EFnet&channel=%23vela", router(fixture))
        #expect(fixture.presenter.notices == ["Vela doesn't have a network called “EFnet”."])
    }

    @Test func malformedLinksShowANotice() async throws {
        let fixture = try await AutomationFixture.make()
        _ = open("vela://open?channel=%23a&channel=%23b", router(fixture))
        #expect(fixture.presenter.notices == ["Vela doesn't know what to do with that link."])
    }

    /// A name on two networks: the one you're looking at wins; from
    /// elsewhere, it's ambiguous.
    @Test func ambiguousNames() async throws {
        let fixture = try await AutomationFixture.make()
        let ergoVela = fixture.ergo.ensureBuffer(name: "#vela", kind: .channel, persist: false)
        let liberaVela = try fixture.buffer("#vela", on: fixture.libera)
        let router = router(fixture)
        // Looking at Libera.Chat.
        #expect(open("vela://open?channel=%23vela", router) == .shown)
        #expect(fixture.app.showRequest?.bufferID == liberaVela.id)
        // Looking at OFTC, which has no #vela.
        fixture.app.select(try fixture.buffer("#debian", on: fixture.oftc))
        let before = fixture.app.showRequest
        guard case .refused = open("vela://open?channel=%23vela", router) else {
            Issue.record("Expected a refusal")
            return
        }
        #expect(fixture.app.showRequest == before)
        #expect(fixture.presenter.notices.last == "#vela is on more than one network: say which.")
        #expect(open("vela://open?channel=%23vela&network=Ergo%20Testnet", router) == .shown)
        #expect(fixture.app.showRequest?.bufferID == ergoVela.id)
    }

    @Test func repeatedLinksAreIgnoredForAMoment() async throws {
        let fixture = try await AutomationFixture.make()
        var now = ContinuousClock.now
        let router = VelaLinkRouter(automation: fixture.automation) { now }
        let url = URL(string: "vela://recap")!
        #expect(router.open(url) == .shown)
        #expect(router.open(url) == .throttled)
        now = now.advanced(by: .seconds(2))
        #expect(router.open(url) == .shown)
    }

    // MARK: Joining

    @Test func joinShowsAChannelYoureIn() async throws {
        let fixture = try await AutomationFixture.make()
        let vela = try fixture.buffer("#vela", on: fixture.libera)
        #expect(open("vela://join/%23vela", router(fixture)) == .shown)
        #expect(fixture.app.showRequest?.bufferID == vela.id)
        #expect(fixture.presenter.calls.isEmpty)
    }

    /// Never joins: it opens Join Channel, filled in.
    @Test func joinOffersToJoinOtherwise() async throws {
        let fixture = try await AutomationFixture.make()
        #expect(open("vela://join?channel=newchan&network=Libera.Chat", router(fixture)) == .shown)
        #expect(fixture.presenter.calls == [.offerToJoin("#newchan", fixture.libera.id)])
        #expect(fixture.libera.buffer(named: "#newchan") == nil)
        // A channel left: offered, not rejoined.
        let debian = try fixture.buffer("#debian", on: fixture.oftc)
        #expect(open("vela://join?channel=%23debian&network=OFTC", router(fixture)) == .shown)
        #expect(debian.isJoined == false)
        #expect(fixture.presenter.calls.last == .offerToJoin("#debian", fixture.oftc.id))
    }

    // MARK: Catch me up, Recap, drafts, search

    @Test func catchUpOpensTheCard() async throws {
        let fixture = try await AutomationFixture.make()
        let swift = try fixture.buffer("#swift", on: fixture.libera)
        #expect(open("vela://catchup?channel=%23swift&network=Libera.Chat", router(fixture)) == .shown)
        #expect(fixture.services.catchUp.card(for: swift.id) != nil)
        #expect(fixture.app.showRequest?.bufferID == swift.id)
    }

    /// Without Apple Intelligence, Catch me up runs on your own provider's
    /// model when it's set to one, as it does in the window and for Siri.
    @Test func catchUpUsesYourProviderWithoutAppleIntelligence() async throws {
        let fixture = try await AutomationFixture.withProviderOnly()
        let swift = try fixture.buffer("#swift", on: fixture.libera)
        #expect(open("vela://catchup?channel=%23swift&network=Libera.Chat", router(fixture)) == .shown)
        #expect(fixture.services.catchUp.card(for: swift.id) != nil)
        #expect(fixture.presenter.notices.isEmpty)

        // Back on Apple's model, which can't run here: refused, and why.
        fixture.app.settings.reset(.intelligenceCatchUpModel)
        fixture.services.catchUp.closeAll()
        guard case .refused(let reason) = open("vela://catchup?channel=%23swift&network=Libera.Chat", router(fixture)) else {
            Issue.record("Expected a refusal")
            return
        }
        #expect(reason == IntelligenceStatus.deviceNotEligible.detail)
        #expect(fixture.services.catchUp.card(for: swift.id) == nil)
    }

    @Test func catchUpWhileTurnedOffStillShowsTheConversation() async throws {
        let fixture = try await AutomationFixture.make()
        fixture.app.settings[.intelligenceCatchUp] = false
        let swift = try fixture.buffer("#swift", on: fixture.libera)
        guard case .refused = open("vela://catchup?channel=%23swift", router(fixture)) else {
            Issue.record("Expected a refusal")
            return
        }
        #expect(fixture.services.catchUp.card(for: swift.id) == nil)
        #expect(fixture.app.showRequest?.bufferID == swift.id)
        #expect(fixture.presenter.notices == ["Catch me up is turned off in Vela's settings."])
    }

    @Test func recapIsFilledIn() async throws {
        let fixture = try await AutomationFixture.make()
        let vela = try fixture.buffer("#vela", on: fixture.libera)
        let router = router(fixture)
        #expect(open("vela://recap?network=Libera.Chat&channel=%23vela&span=today", router) == .shown)
        #expect(fixture.services.recaps.latest?.scope == RecapScope(place: .buffer(vela.id), span: .today, output: .summary))
        #expect(open("vela://recap?network=OFTC&person=bea", router) == .shown)
        #expect(fixture.services.recaps.latest?.scope == RecapScope(place: .network(fixture.oftc.id), person: "bea", span: .sinceUnread, output: .summary))
        #expect(open("vela://recap", router) == .shown)
        #expect(fixture.services.recaps.latest?.scope.place == .everywhere)
    }

    @Test func recapWhileTurnedOff() async throws {
        let fixture = try await AutomationFixture.make()
        fixture.app.settings[.intelligenceRecap] = false
        _ = open("vela://recap", router(fixture))
        #expect(fixture.services.recaps.latest == nil)
        #expect(fixture.presenter.notices == ["Recap is turned off in Vela's settings."])
    }

    @Test func draftFillsTheMessageBox() async throws {
        let fixture = try await AutomationFixture.make()
        let swift = try fixture.buffer("#swift", on: fixture.libera)
        #expect(open("vela://draft?channel=%23swift&text=%2Fquit%20now", router(fixture)) == .shown)
        let request = try #require(fixture.app.showRequest)
        #expect(request.bufferID == swift.id)
        #expect(request.draft == "/quit now")
        // Added after what's there, and escaped there (ShowRequest.composerText).
        #expect(request.appendsDraft)
    }

    @Test func searchOpensMessageSearch() async throws {
        let fixture = try await AutomationFixture.make()
        let vela = try fixture.buffer("#vela", on: fixture.libera)
        let router = router(fixture)
        #expect(open("vela://search?q=aurora", router) == .shown)
        #expect(open("vela://search?q=aurora&network=OFTC", router) == .shown)
        #expect(open("vela://search?q=aurora&channel=%23vela&network=Libera.Chat", router) == .shown)
        #expect(fixture.presenter.calls == [
            .search("aurora", nil, nil),
            .search("aurora", nil, fixture.oftc.id),
            .search("aurora", vela.id, nil),
        ])
    }

    // MARK: Never sends

    /// Whatever a link says, nothing is sent, joined or run: every buffer
    /// keeps its lines and its joined state, and the only buffer a link may
    /// add is an empty private conversation.
    @Test func linksNeverSendAnything() async throws {
        let fixture = try await AutomationFixture.make()
        let router = router(fixture)
        let debian = try fixture.buffer("#debian", on: fixture.oftc)
        func state() -> [BufferID: (lines: Int, joined: Bool)] {
            var result: [BufferID: (lines: Int, joined: Bool)] = [:]
            for session in fixture.app.sessions {
                for buffer in session.allBuffers { result[buffer.id] = (buffer.lines.count, buffer.isJoined) }
            }
            return result
        }
        let before = state()
        let links = [
            "vela://show",
            "vela://open?channel=%23vela",
            "vela://open?nick=marisol",
            "vela://open?nick=stranger&network=Libera.Chat",
            "vela://join/%23vela",
            "vela://join/%23brandnew",
            "vela://join?channel=%23debian&network=OFTC",
            "vela://catchup",
            "vela://catchup?channel=%23swift",
            "vela://recap?channel=%23vela&person=wren&span=1w",
            "vela://draft?channel=%23vela&text=%2Fmsg%20NickServ%20DROP%20doug",
            "vela://draft?nick=marisol&text=hello%0A%2Fquit",
            "vela://draft?channel=%23debian&network=OFTC&text=%2Fjoin%20%230",
            "vela://search?q=%2Fquit",
            "vela://open?channel=%23vela&text=%2Fquit",
            "vela://send?channel=%23vela&text=hi",
            "vela://say?channel=%23vela&text=hi",
            "vela://raw?line=QUIT",
        ]
        for link in links { _ = open(link, router) }
        let after = state()
        for (id, old) in before {
            #expect(after[id]?.lines == old.lines, "\(id) gained lines")
            #expect(after[id]?.joined == old.joined, "\(id) was joined or left")
        }
        for (id, new) in after where before[id] == nil {
            let buffer = try #require(fixture.app.lookup(id)?.buffer)
            #expect(buffer.kind == .query && new.lines == 0, "\(id) appeared")
        }
        #expect(debian.isJoined == false)
        #expect(fixture.libera.buffer(named: "#brandnew") == nil)
    }
}
