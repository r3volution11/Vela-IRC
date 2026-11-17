// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
@testable import VelaIntelligence

/// A summarizer the test drives by hand: each `summarize` call gets a
/// stream whose continuation the test yields to and finishes.
nonisolated final class ManualSummarizer: ConversationSummarizer {
    struct Call: @unchecked Sendable {
        let request: CatchUpRequest
        let continuation: AsyncThrowingStream<CatchUpSummary, Error>.Continuation
        let terminated: Recorder<Bool>
    }

    let calls = Recorder<[Call]>([])

    var callCount: Int { calls.value.count }

    func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error> {
        let (stream, continuation) = AsyncThrowingStream<CatchUpSummary, Error>.makeStream()
        let terminated = Recorder(false)
        continuation.onTermination = { _ in terminated.update { $0 = true } }
        calls.update { $0.append(Call(request: request, continuation: continuation, terminated: terminated)) }
        return stream
    }

    func call(_ index: Int) -> Call { calls.value[index] }

    /// Streams a partial summary, then the finished one.
    func complete(_ index: Int, overview: String = "Done.") {
        let call = call(index)
        let count = call.request.lines.count
        call.continuation.yield(CatchUpSummary(overview: "Do", topics: [], addressedToYou: [], messageCount: count, isComplete: false))
        call.continuation.yield(CatchUpSummary(overview: overview, topics: [], addressedToYou: [], messageCount: count, isComplete: true))
        call.continuation.finish()
    }
}

@MainActor
@Suite("Catch me up store")
struct CatchUpStoreTests {
    typealias F = CatchUpFixtures

    private func overview(_ card: CatchUpCard?) -> String? {
        if case .done(let summary) = card?.phase { summary.overview } else { nil }
    }

    @Test func opensACardThatStreamsToDone() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let request = F.request(F.chatter(30))
        store.open(request, marker: Date(timeIntervalSince1970: 5))

        let card = try #require(store.card(for: F.bufferID))
        #expect(card.phase == .running(nil))
        #expect(card.messageCount == 30)
        #expect(card.marker == Date(timeIntervalSince1970: 5))
        #expect(store.reveal?.bufferID == F.bufferID)

        #expect(await eventually { summarizer.callCount == 1 })
        summarizer.call(0).continuation.yield(CatchUpSummary(overview: "Part", topics: [], addressedToYou: [], messageCount: 30, isComplete: false))
        #expect(await eventually { card.summary?.overview == "Part" })
        #expect(card.isRunning)
        summarizer.complete(0)
        #expect(await eventually { overview(card) == "Done." })
    }

    @Test func reopeningTheSameStretchUsesTheCache() async {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let request = F.request(F.chatter(30))
        store.open(request)
        #expect(await eventually { summarizer.callCount == 1 })
        summarizer.complete(0)
        #expect(await eventually { overview(store.card(for: F.bufferID)) == "Done." })

        store.dismiss(F.bufferID)
        #expect(store.card(for: F.bufferID) == nil)
        store.open(request)
        #expect(overview(store.card(for: F.bufferID)) == "Done.")
        #expect(summarizer.callCount == 1)

        // Siri gets the same summary without another run.
        let summary = try? await store.summary(for: request)
        #expect(summary?.overview == "Done.")
        #expect(summarizer.callCount == 1)
    }

    @Test func aNewerStretchIsSummarizedAgain() async {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        var lines = F.chatter(30)
        store.open(F.request(lines))
        #expect(await eventually { summarizer.callCount == 1 })
        summarizer.complete(0)
        #expect(await eventually { overview(store.card(for: F.bufferID)) == "Done." })

        lines.append(F.line("erin", "one more"))
        store.open(F.request(lines))
        #expect(store.card(for: F.bufferID)?.isRunning == true)
        #expect(await eventually { summarizer.callCount == 2 })
    }

    @Test func dismissingCancelsTheRun() async {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(F.request(F.chatter(30)))
        #expect(await eventually { summarizer.callCount == 1 })

        store.dismiss(F.bufferID)
        #expect(store.card(for: F.bufferID) == nil)
        #expect(await eventually { summarizer.call(0).terminated.value })

        // Nothing was cached, so opening again starts over.
        store.open(F.request(F.chatter(30)))
        #expect(store.card(for: F.bufferID)?.isRunning == true)
    }

    @Test func regenerateIgnoresTheCache() async {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let request = F.request(F.chatter(30))
        store.open(request)
        #expect(await eventually { summarizer.callCount == 1 })
        summarizer.complete(0, overview: "First.")
        #expect(await eventually { overview(store.card(for: F.bufferID)) == "First." })

        store.regenerate(request)
        #expect(store.card(for: F.bufferID)?.isRunning == true)
        #expect(await eventually { summarizer.callCount == 2 })
        summarizer.complete(1, overview: "Second.")
        #expect(await eventually { overview(store.card(for: F.bufferID)) == "Second." })
    }

    @Test func failuresShowOnTheCardAndTryAgainRecovers() async {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let request = F.request(F.chatter(30))
        store.open(request)
        #expect(await eventually { summarizer.callCount == 1 })
        summarizer.call(0).continuation.finish(throwing: CatchUpError.declined)
        #expect(await eventually { store.card(for: F.bufferID)?.phase == .failed(.declined) })

        store.regenerate(request)
        #expect(await eventually { summarizer.callCount == 2 })
        summarizer.complete(1)
        #expect(await eventually { overview(store.card(for: F.bufferID)) == "Done." })
    }

    @Test func siriSharesARunningCard() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let request = F.request(F.chatter(30))
        store.open(request)
        #expect(await eventually { summarizer.callCount == 1 })

        async let siri = store.summary(for: request)
        try await Task.sleep(for: .milliseconds(20))
        summarizer.complete(0, overview: "Shared.")
        let summary = try await siri
        #expect(summary.overview == "Shared.")
        #expect(summary.isComplete)
        #expect(summarizer.callCount == 1)
    }

    @Test func dismissingKeepsARunSiriIsWaitingFor() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let request = F.request(F.chatter(30))
        store.open(request)
        #expect(await eventually { summarizer.callCount == 1 })

        async let siri = store.summary(for: request)
        try await Task.sleep(for: .milliseconds(20))
        store.dismiss(F.bufferID)
        #expect(!summarizer.call(0).terminated.value)
        summarizer.complete(0, overview: "Still here.")
        #expect(try await siri.overview == "Still here.")
    }

    @Test func siriWithNothingNewThrows() async {
        let store = CatchUpStore(summarizer: ManualSummarizer())
        await #expect(throws: CatchUpError.nothingToSummarize) {
            try await store.summary(for: F.request([]))
        }
    }
}
