// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
@testable import VelaIntelligence

/// Summaries are written one at a time, in the order they're asked for,
/// with Siri's first.
@MainActor
@Suite("Catch me up queue")
struct CatchUpQueueTests {
    typealias F = CatchUpFixtures

    private func buffer(_ name: String) -> BufferID {
        BufferID(networkID: F.bufferID.networkID, foldedName: name)
    }

    /// The same stretch every time it's asked for (in one test), as when
    /// a card and Siri ask for one channel's new messages.
    private let requests: [String: CatchUpRequest] = {
        var requests: [String: CatchUpRequest] = [:]
        for name in ["#vela", "#swift", "#rust"] {
            let id = BufferID(networkID: CatchUpFixtures.bufferID.networkID, foldedName: name)
            requests[name] = CatchUpFixtures.request(CatchUpFixtures.chatter(30), bufferID: id, name: name)
        }
        return requests
    }()

    private func request(_ name: String) -> CatchUpRequest {
        requests[name]!
    }

    private func overview(_ card: CatchUpCard?) -> String? {
        if case .done(let summary) = card?.phase { summary.overview } else { nil }
    }

    /// The buffer of each summarizer call, in the order they started.
    private func started(_ summarizer: ManualSummarizer) -> [String] {
        summarizer.calls.value.map(\.request.bufferName)
    }

    /// Lets queued work settle, for checks that nothing (more) happened.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(30))
    }

    @Test func summariesAreWrittenOneAtATimeInOrder() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(request("#vela"), reveal: false)
        store.open(request("#swift"), reveal: false)
        store.open(request("#rust"), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })
        try await settle()
        #expect(summarizer.callCount == 1)

        let swift = try #require(store.card(for: buffer("#swift")))
        let rust = try #require(store.card(for: buffer("#rust")))
        #expect(store.card(for: buffer("#vela"))?.summariesAhead == nil)
        #expect(swift.summariesAhead == 1)
        #expect(rust.summariesAhead == 2)
        // Queued cards count as running: no button, no Regenerate.
        #expect(swift.isRunning && rust.isRunning)

        summarizer.complete(0, overview: "Vela.")
        #expect(await eventually { summarizer.callCount == 2 })
        #expect(swift.summariesAhead == nil)
        #expect(rust.summariesAhead == 1)

        summarizer.complete(1, overview: "Swift.")
        #expect(await eventually { summarizer.callCount == 3 })
        #expect(rust.summariesAhead == nil)
        summarizer.complete(2, overview: "Rust.")
        #expect(await eventually { overview(rust) == "Rust." })
        #expect(started(summarizer) == ["#vela", "#swift", "#rust"])
        #expect(overview(swift) == "Swift.")
    }

    /// Closing a card whose summary is waiting takes it out of the queue.
    @Test func closingAQueuedCardTakesItOut() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(request("#vela"), reveal: false)
        store.open(request("#swift"), reveal: false)
        store.open(request("#rust"), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })

        store.dismiss(buffer("#swift"))
        #expect(store.card(for: buffer("#rust"))?.summariesAhead == 1)
        summarizer.complete(0)
        #expect(await eventually { summarizer.callCount == 2 })
        try await settle()
        #expect(started(summarizer) == ["#vela", "#rust"])

        // Asked for again, it goes to the back and runs in turn.
        store.open(request("#swift"), reveal: false)
        #expect(store.card(for: buffer("#swift"))?.summariesAhead == 1)
        summarizer.complete(1)
        #expect(await eventually { summarizer.callCount == 3 })
        #expect(started(summarizer) == ["#vela", "#rust", "#swift"])
    }

    /// Closing the card being written lets the next one start.
    @Test func closingTheRunningCardStartsTheNext() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(request("#vela"), reveal: false)
        store.open(request("#swift"), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })

        store.dismiss(buffer("#vela"))
        #expect(await eventually { summarizer.call(0).terminated.value })
        #expect(await eventually { summarizer.callCount == 2 })
        #expect(started(summarizer) == ["#vela", "#swift"])
        #expect(store.card(for: buffer("#swift"))?.summariesAhead == nil)
    }

    /// A newer stretch in the same channel replaces the one being written,
    /// which stops: the new one doesn't wait for it.
    @Test func aNewerStretchTakesOverWithoutWaiting() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        var lines = request("#vela").lines
        store.open(F.request(lines), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })

        lines.append(F.line("erin", "one more"))
        store.open(F.request(lines), reveal: false)
        let card = try #require(store.card(for: F.bufferID))
        #expect((card.summariesAhead ?? 0) == 0)
        #expect(await eventually { summarizer.call(0).terminated.value })
        #expect(await eventually { summarizer.callCount == 2 })
        #expect(summarizer.call(1).request.lines.count == 31)
    }

    /// A failure frees the queue too.
    @Test func aFailureStartsTheNext() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(request("#vela"), reveal: false)
        store.open(request("#swift"), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })
        summarizer.call(0).continuation.finish(throwing: CatchUpError.declined)
        #expect(await eventually { summarizer.callCount == 2 })
        #expect(store.card(for: buffer("#vela"))?.phase == .failed(.declined))
    }

    /// Siri is waiting, so its request goes next, after the one being written.
    @Test func siriGoesToTheFront() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(request("#vela"), reveal: false)
        store.open(request("#swift"), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })

        let siri = Task { try await store.summary(for: request("#rust"), urgent: true) }
        #expect(await eventually { store.card(for: buffer("#swift"))?.summariesAhead == 2 })
        summarizer.complete(0)
        #expect(await eventually { summarizer.callCount == 2 })
        #expect(started(summarizer) == ["#vela", "#rust"])
        summarizer.complete(1, overview: "Rust for Siri.")
        #expect(try await siri.value.overview == "Rust for Siri.")
        #expect(await eventually { summarizer.callCount == 3 })
        #expect(started(summarizer) == ["#vela", "#rust", "#swift"])
    }

    /// Siri asking for a stretch whose card is waiting moves that card up.
    @Test func siriMovesAQueuedCardUp() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(request("#vela"), reveal: false)
        store.open(request("#swift"), reveal: false)
        store.open(request("#rust"), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })

        let siri = Task { try await store.summary(for: request("#rust"), urgent: true) }
        #expect(await eventually { store.card(for: buffer("#rust"))?.summariesAhead == 1 })
        #expect(store.card(for: buffer("#swift"))?.summariesAhead == 2)
        summarizer.complete(0)
        #expect(await eventually { summarizer.callCount == 2 })
        summarizer.complete(1, overview: "Rust.")
        // Shared: Siri and the card get the same summary from one run.
        #expect(try await siri.value.overview == "Rust.")
        #expect(await eventually { overview(store.card(for: buffer("#rust"))) == "Rust." })
        #expect(started(summarizer).prefix(2) == ["#vela", "#rust"])
    }

    /// The same stretch asked for twice is summarized once, and both get it.
    @Test func theSameStretchTwiceIsOneJob() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(request("#vela"), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })
        let first = Task { try await store.summary(for: request("#swift"), urgent: true) }
        let second = Task { try await store.summary(for: request("#swift"), urgent: true) }
        try await settle()
        store.open(request("#swift"), reveal: false)
        store.open(request("#swift"), reveal: false)
        summarizer.complete(0)
        #expect(await eventually { summarizer.callCount == 2 })
        summarizer.complete(1, overview: "Once.")
        #expect(try await first.value.overview == "Once.")
        #expect(try await second.value.overview == "Once.")
        try await settle()
        #expect(summarizer.callCount == 2)
        #expect(overview(store.card(for: buffer("#swift"))) == "Once.")
    }

    /// A card closed while its summary waits, with Siri waiting for the same
    /// summary: it stays queued for Siri, runs in turn, and nothing hangs.
    @Test func aQueuedCardClosedWhileSiriWaitsStillRunsForSiri() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(request("#vela"), reveal: false)
        store.open(request("#swift"), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })
        let siri = Task { try await store.summary(for: request("#swift")) }
        try await settle()

        store.dismiss(buffer("#swift"))
        summarizer.complete(0)
        #expect(await eventually { summarizer.callCount == 2 })
        summarizer.complete(1, overview: "For Siri.")
        #expect(try await siri.value.overview == "For Siri.")
    }

    /// Siri gives up on a summary that hasn't started: it leaves the queue.
    @Test func siriGivingUpOnAQueuedSummaryTakesItOut() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(request("#vela"), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })
        let siri = Task { try await store.summary(for: request("#rust"), urgent: true) }
        try await settle()
        siri.cancel()
        await #expect(throws: CancellationError.self) { try await siri.value }

        summarizer.complete(0)
        try await settle()
        #expect(summarizer.callCount == 1)
        // The queue still works.
        store.open(request("#swift"), reveal: false)
        #expect(await eventually { summarizer.callCount == 2 })
    }

    /// Siri's patience runs out on a queued summary: the card that Vela
    /// opens takes over its place, and nothing deadlocks.
    @Test func aHeldQueuedSummaryIsTakenOverByItsCard() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        store.open(request("#vela"), reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })
        let rust = request("#rust")
        let answer = try await store.summary(for: rust, urgent: true, patience: .milliseconds(30))
        #expect(answer == nil)

        store.open(rust, reveal: false)
        store.release(rust)
        let card = try #require(store.card(for: buffer("#rust")))
        #expect(card.summariesAhead == 1)
        summarizer.complete(0)
        #expect(await eventually { summarizer.callCount == 2 })
        summarizer.complete(1, overview: "Handed over.")
        #expect(await eventually { overview(card) == "Handed over." })
    }

    /// Regenerating queues a fresh summary at the back.
    @Test func regenerateQueuesBehindTheOneBeingWritten() async throws {
        let summarizer = ManualSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let vela = request("#vela")
        store.open(vela, reveal: false)
        #expect(await eventually { summarizer.callCount == 1 })
        summarizer.complete(0, overview: "First.")
        #expect(await eventually { overview(store.card(for: buffer("#vela"))) == "First." })

        store.open(request("#swift"), reveal: false)
        #expect(await eventually { summarizer.callCount == 2 })
        store.regenerate(vela)
        let card = try #require(store.card(for: buffer("#vela")))
        #expect(card.isRunning)
        #expect(card.summariesAhead == 1)
        summarizer.complete(1)
        #expect(await eventually { summarizer.callCount == 3 })
        summarizer.complete(2, overview: "Second.")
        #expect(await eventually { overview(card) == "Second." })
    }
}
