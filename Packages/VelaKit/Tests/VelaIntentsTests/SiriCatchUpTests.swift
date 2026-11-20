// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization
import Testing
@testable import VelaCore
@testable import VelaIntelligence
@testable import VelaIntents

/// A summarizer that remembers how many lines it was asked to summarize,
/// answers with a fixed overview (or, `waits`, only when told to), and
/// plans as told.
nonisolated final class CountingSummarizer: ConversationSummarizer {
    private struct State {
        var requests: [Int] = []
        var pending: [AsyncThrowingStream<CatchUpSummary, Error>.Continuation] = []
        var terminated = 0
    }

    private let state = Mutex(State())
    let overview: String
    let plan: CatchUpPlan
    /// Summaries finish only when ``finishAll()`` says.
    let waits: Bool

    init(overview: String = "Kenji landed the theme engine.", plan: CatchUpPlan = CatchUpPlan(passes: 1, transcriptTokens: 900), waits: Bool = false) {
        self.overview = overview
        self.plan = plan
        self.waits = waits
    }

    var requestedLineCounts: [Int] { state.withLock { $0.requests } }
    /// Summaries stopped before they finished.
    var terminatedCount: Int { state.withLock { $0.terminated } }

    func plan(_ request: CatchUpRequest) async -> CatchUpPlan { plan }

    func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error> {
        let summary = CatchUpSummary(overview: overview, topics: [], addressedToYou: [], messageCount: request.lines.count, isComplete: true)
        let (stream, continuation) = AsyncThrowingStream<CatchUpSummary, Error>.makeStream()
        continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination { self?.state.withLock { $0.terminated += 1 } }
        }
        state.withLock { $0.requests.append(request.lines.count) }
        if waits {
            state.withLock { $0.pending.append(continuation) }
        } else {
            continuation.yield(summary)
            continuation.finish()
        }
        return stream
    }

    /// Finishes every summary that's waiting.
    func finishAll() {
        let pending = state.withLock { state in
            defer { state.pending.removeAll() }
            return state.pending
        }
        for continuation in pending {
            continuation.yield(CatchUpSummary(overview: overview, topics: [], addressedToYou: [], messageCount: 0, isComplete: true))
            continuation.finish()
        }
    }
}

/// What Catch Me Up summarizes and says for Siri and Shortcuts.
@MainActor
@Suite("Siri's Catch Me Up")
struct SiriCatchUpTests {
    private let bufferID = BufferID(networkID: UUID(), foldedName: "#vela")

    private func request(_ count: Int) -> CatchUpRequest {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let lines = (0..<count).map { index in
            CatchUpLine(id: UUID(), time: start.addingTimeInterval(TimeInterval(index)), nick: "ada", text: "message \(index)")
        }
        return CatchUpRequest(bufferID: bufferID, bufferName: "#vela", networkName: "Libera.Chat", ownNick: "doug", lines: lines)
    }

    private func summary(_ outcome: SiriCatchUp.Outcome) -> CatchUpSummary? {
        if case .summary(let summary) = outcome { summary } else { nil }
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<600 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: Answering in Siri

    @Test func aQuickStretchIsAnsweredWhole() async throws {
        let summarizer = CountingSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let catchUp = SiriCatchUp(request(40))

        let outcome = try await catchUp.summarize(with: store)
        #expect(summarizer.requestedLineCounts == [40])
        let answer = try #require(summary(outcome))
        #expect(catchUp.dialog(for: answer) == "Kenji landed the theme engine.")
    }

    /// No more "the latest 100 of 412": a stretch too long for one quick
    /// pass opens Vela, where the card summarizes all of it.
    @Test func aLongStretchOpensVelaInsteadOfBeingCut() async throws {
        let summarizer = CountingSummarizer(plan: CatchUpPlan(passes: 4, transcriptTokens: 11_000))
        let store = CatchUpStore(summarizer: summarizer)
        let catchUp = SiriCatchUp(request(412))
        #expect(catchUp.request.lines.count == 412)

        let outcome = try await catchUp.summarize(with: store)
        #expect(outcome == .openInVela(held: false))
        // Siri started nothing; the card will.
        #expect(summarizer.requestedLineCounts.isEmpty)
        #expect(catchUp.openingDialog == "That's 412 messages in #vela. Opening Vela to catch you up.")
    }

    @Test func whatSiriWaitsFor() {
        // On this Mac: one pass, and short.
        #expect(SiriCatchUp.answersInSiri(CatchUpPlan(passes: 1, transcriptTokens: 2_000)))
        #expect(SiriCatchUp.answersInSiri(CatchUpPlan(passes: 1, transcriptTokens: SiriCatchUp.onDeviceTokenLimit)))
        #expect(!SiriCatchUp.answersInSiri(CatchUpPlan(passes: 1, transcriptTokens: SiriCatchUp.onDeviceTokenLimit + 1)))
        #expect(!SiriCatchUp.answersInSiri(CatchUpPlan(passes: 2, transcriptTokens: 2_000)))
        // Private Cloud Compute: one pass, expected within Siri's patience.
        #expect(SiriCatchUp.answersInSiri(CatchUpPlan(venue: .privateCloudCompute, passes: 1, transcriptTokens: 20_000, estimatedSeconds: 12)))
        #expect(!SiriCatchUp.answersInSiri(CatchUpPlan(venue: .privateCloudCompute, passes: 1, transcriptTokens: 20_000, estimatedSeconds: 40)))
        #expect(!SiriCatchUp.answersInSiri(CatchUpPlan(venue: .privateCloudCompute, passes: 2, transcriptTokens: 40_000, estimatedSeconds: 12)))
        #expect(!SiriCatchUp.answersInSiri(CatchUpPlan(venue: .privateCloudCompute, passes: 1, transcriptTokens: 20_000)))
        // Private Cloud Compute on but unavailable: planned on this Mac.
        #expect(!SiriCatchUp.answersInSiri(CatchUpPlan(passes: 5, transcriptTokens: 20_000, cloudFallback: .unavailable)))
    }

    @Test func privateCloudComputeAnswersALongStretchInSiri() async throws {
        let plan = CatchUpPlan(venue: .privateCloudCompute, passes: 1, transcriptTokens: 14_000, estimatedSeconds: 9)
        let summarizer = CountingSummarizer(plan: plan)
        let store = CatchUpStore(summarizer: summarizer)
        let outcome = try await SiriCatchUp(request(412)).summarize(with: store)
        #expect(summary(outcome) != nil)
        #expect(summarizer.requestedLineCounts == [412])
    }

    @Test func aSummaryOfTheWholeStretchIsUsedAsItIs() async throws {
        let summarizer = CountingSummarizer(plan: CatchUpPlan(passes: 6, transcriptTokens: 20_000))
        let store = CatchUpStore(summarizer: summarizer)
        let full = request(300)
        // The card in the channel already summarized all of it.
        _ = try await store.summary(for: full)
        #expect(summarizer.requestedLineCounts == [300])

        let catchUp = SiriCatchUp(full)
        let answer = try #require(summary(try await catchUp.summarize(with: store)))
        #expect(summarizer.requestedLineCounts == [300])
        #expect(catchUp.dialog(for: answer) == "Kenji landed the theme engine.")
    }

    // MARK: Handing over to the card

    /// Siri waits only so long. The summary it started keeps going, held
    /// for the card that Vela opens to, which takes it over.
    @Test func aSlowSummaryIsHandedToTheCard() async throws {
        let summarizer = CountingSummarizer(waits: true)
        let store = CatchUpStore(summarizer: summarizer)
        let full = request(40)
        let catchUp = SiriCatchUp(full)

        let outcome = try await catchUp.summarize(with: store, patience: .milliseconds(50))
        #expect(outcome == .openInVela(held: true))
        #expect(summarizer.requestedLineCounts == [40])

        // Vela opens the card, then Siri lets go: nothing starts over.
        store.open(full, reveal: false)
        store.release(full)
        let card = try #require(store.card(for: bufferID))
        #expect(card.isRunning)
        try await Task.sleep(for: .milliseconds(30))
        #expect(summarizer.terminatedCount == 0)

        summarizer.finishAll()
        #expect(await eventually { !card.isRunning })
        #expect(card.summary?.overview == "Kenji landed the theme engine.")
        #expect(summarizer.requestedLineCounts == [40])
    }

    /// Vela didn't open after all (the person said no): the held summary stops.
    @Test func aHeldSummaryStopsWhenVelaDoesNotOpen() async throws {
        let summarizer = CountingSummarizer(waits: true)
        let store = CatchUpStore(summarizer: summarizer)
        let full = request(40)
        let outcome = try await SiriCatchUp(full).summarize(with: store, patience: .milliseconds(50))
        #expect(outcome == .openInVela(held: true))
        store.release(full)
        #expect(await eventually { summarizer.terminatedCount == 1 })
        #expect(store.cachedSummary(for: full) == nil)
    }

    // MARK: What Siri says

    @Test func aSummaryCappedAtTheLatest600SaysSo() {
        let catchUp = SiriCatchUp(request(900))
        let capped = CatchUpSummary(overview: "Lots happened.", topics: [], addressedToYou: [], messageCount: 600, isComplete: true)
        #expect(catchUp.dialog(for: capped) == "From the latest 600 of 900 messages in #vela: Lots happened.")
        var empty = capped
        empty.overview = " "
        #expect(catchUp.dialog(for: empty) == "Here's what happened in the latest 600 of 900 messages in #vela.")
    }

    @Test func withoutAnOverviewItStillSaysWhere() {
        let empty = CatchUpSummary(overview: "  ", topics: [], addressedToYou: [], messageCount: 10, isComplete: true)
        #expect(SiriCatchUp(request(10)).dialog(for: empty) == "Here's what you missed in #vela.")
    }

    @Test func openingAndBackgroundDialogs() {
        let catchUp = SiriCatchUp(request(1))
        #expect(catchUp.openingDialog == "That's 1 message in #vela. Opening Vela to catch you up.")
        #expect(SiriCatchUp(request(412)).backgroundDialog
            == "That's 412 messages in #vela, too many to summarize here. Vela is summarizing them now; open #vela in Vela to read it.")
        #expect(catchUp.openedDialog == "Here's #vela. Its summary is on the way.")
    }
}
