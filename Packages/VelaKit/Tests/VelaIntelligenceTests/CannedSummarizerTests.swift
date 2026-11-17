// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIntelligence

@Suite("Canned summarizer")
struct CannedSummarizerTests {
    typealias F = CatchUpFixtures

    /// The tail of the demo #vela conversation.
    private var velaLines: [CatchUpLine] {
        [
            F.line("marisol", "has anyone tried the Blender open movie embed? https://www.youtube.com/watch?v=aqz-KE-bpKQ"),
            F.line("kenji", "plays inline, and the facade means no web view until you click ▶"),
            F.line("nadia", "reads the release notes", action: true),
            F.line("wren", "doug: can you review the sidebar rail PR when you get a sec?"),
            F.line("doug", "on it 👍"),
            F.line("theo", "also the Swift blog has a post on the new concurrency defaults: https://www.swift.org/blog/"),
        ]
    }

    @Test func demoChannelsGetTheirScript() throws {
        let lines = velaLines
        let summary = try CannedSummarizer.summary(for: F.request(lines))
        // Only topics whose messages were asked about.
        #expect(summary.topics.map(\.title) == ["Inline video", "Sidebar rail review", "Swift concurrency post"])
        #expect(summary.topics.map(\.firstLineID) == [lines[0].id, lines[3].id, lines[5].id])
        #expect(summary.addressedToYou == ["wren asked you to review the sidebar rail PR."])
        #expect(summary.overview.hasPrefix("Talk was about inline video, a pull request review and Swift concurrency."))
        #expect(summary.isComplete)
    }

    @Test func otherChannelsGetAPlainSummary() throws {
        let lines = [
            F.line("alice", "hi"),
            F.line("bob", "doug, are you around?"),
            F.line("alice", "ship it"),
        ]
        let summary = try CannedSummarizer.summary(for: F.request(lines, name: "#elsewhere"))
        #expect(summary.overview == "3 messages from alice and bob.")
        #expect(summary.topics.count == 1)
        #expect(summary.topics[0].participants == ["alice", "bob"])
        #expect(summary.topics[0].firstLineID == lines[0].id)
        #expect(summary.addressedToYou == ["bob: “are you around?”"])
        #expect(summary.messageCount == 3)
    }

    @Test func nothingToSummarize() {
        #expect(throws: CatchUpError.nothingToSummarize) {
            try CannedSummarizer.summary(for: F.request([]))
        }
    }

    @Test func streamsInThreeSteps() async throws {
        let summarizer = CannedSummarizer(stepDelay: .zero)
        let request = F.request(velaLines)
        var steps: [CatchUpSummary] = []
        for try await step in summarizer.summarize(request) { steps.append(step) }
        #expect(steps.count == 3)
        #expect(steps[0].topics.isEmpty && !steps[0].overview.isEmpty)
        #expect(steps[0].overview.count < steps[2].overview.count)
        #expect(steps[1].topics.count == 3 && steps[1].addressedToYou.isEmpty)
        #expect(steps.map(\.isComplete) == [false, false, true])
        #expect(steps[2].addressedToYou.count == 1)

        let finished = try await summarizer.summary(for: request)
        #expect(finished == steps[2])
    }
}
