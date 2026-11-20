// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization
import Testing
@testable import VelaCore
@testable import VelaIntelligence
@testable import VelaIntents

/// A summarizer that remembers how many lines it was asked to summarize
/// and answers with a fixed overview.
nonisolated final class CountingSummarizer: ConversationSummarizer {
    private let requests = Mutex<[Int]>([])
    let overview: String

    init(overview: String = "Kenji landed the theme engine.") {
        self.overview = overview
    }

    var requestedLineCounts: [Int] { requests.withLock { $0 } }

    func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error> {
        requests.withLock { $0.append(request.lines.count) }
        let summary = CatchUpSummary(overview: overview, topics: [], addressedToYou: [], messageCount: request.lines.count, isComplete: true)
        return AsyncThrowingStream { continuation in
            continuation.yield(summary)
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

    @Test func aShortStretchIsSummarizedWhole() async throws {
        let summarizer = CountingSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let catchUp = SiriCatchUp(request(40))
        #expect(catchUp.request == catchUp.full)

        let result = try await catchUp.summarize(with: store)
        #expect(summarizer.requestedLineCounts == [40])
        #expect(!result.isPartial)
        #expect(catchUp.dialog(for: result) == "Kenji landed the theme engine.")
    }

    @Test func aLongStretchIsCutToTheNewestLines() async throws {
        let summarizer = CountingSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let full = request(412)
        let catchUp = SiriCatchUp(full)
        #expect(catchUp.request.lines.count == SiriCatchUp.maximumLines)
        // The newest ones, in order.
        #expect(catchUp.request.lines == Array(full.lines.suffix(SiriCatchUp.maximumLines)))

        let result = try await catchUp.summarize(with: store)
        #expect(summarizer.requestedLineCounts == [SiriCatchUp.maximumLines])
        #expect(result.isPartial)
        #expect(result.summarized == 100)
        #expect(result.available == 412)
        #expect(catchUp.dialog(for: result) == "From the latest 100 of 412 messages in #vela: Kenji landed the theme engine.")
    }

    @Test func withoutAnOverviewItStillSaysWhatItCovers() {
        let empty = CatchUpSummary(overview: "  ", topics: [], addressedToYou: [], messageCount: 0, isComplete: true)
        let whole = SiriCatchUp(request(10))
        #expect(whole.dialog(for: .init(summary: empty, summarized: 10, available: 10)) == "Here's what you missed in #vela.")
        let cut = SiriCatchUp(request(150))
        #expect(cut.dialog(for: .init(summary: empty, summarized: 100, available: 150))
            == "Here's what happened in the latest 100 of 150 messages in #vela.")
    }

    @Test func aSummaryOfTheWholeStretchIsUsedAsItIs() async throws {
        let summarizer = CountingSummarizer()
        let store = CatchUpStore(summarizer: summarizer)
        let full = request(300)
        // The card in the channel already summarized all of it.
        _ = try await store.summary(for: full)
        #expect(summarizer.requestedLineCounts == [300])

        let catchUp = SiriCatchUp(full)
        let result = try await catchUp.summarize(with: store)
        #expect(summarizer.requestedLineCounts == [300])
        #expect(!result.isPartial)
        #expect(catchUp.dialog(for: result) == "Kenji landed the theme engine.")
    }

    @Test func theCapKeepsOnePassOfTheModel() {
        // Siri's stretch is far smaller than what the card summarizes.
        #expect(SiriCatchUp.maximumLines < CatchUpRequest.maximumLines)
        #expect(SiriCatchUp.maximumLines == 100)
    }
}
