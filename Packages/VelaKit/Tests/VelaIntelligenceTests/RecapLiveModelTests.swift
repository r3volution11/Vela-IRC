// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIntelligence

/// Runs a Recap on the real on-device model, to see what it writes and how
/// long it takes. Opt in with `VELA_LIVE_MODEL=1` on a Mac with Apple
/// Intelligence turned on:
///
///     VELA_LIVE_MODEL=1 swift test --package-path Packages/VelaKit --filter RecapLiveModel
@MainActor
@Suite("Recap with the live model", .enabled(if: ProcessInfo.processInfo.environment["VELA_LIVE_MODEL"] == "1"), .serialized)
struct RecapLiveModelTests {
    typealias F = RecapFixtures

    /// The Catch me up live test's afternoon in #vela, `times` over.
    private func lines(repeating times: Int) -> [RecapLine] {
        var lines: [RecapLine] = []
        for round in 0..<times {
            for (index, pair) in CatchUpLiveModelTests.script.enumerated() {
                let text = round == 0 ? pair.1 : "\(pair.1) (round \(round + 1))"
                lines.append(F.line(pair.0, text, minute: Double(round * 100 + index), isSelf: pair.0 == "doug"))
            }
        }
        return lines
    }

    /// The live model, keeping each raw reply for the report.
    nonisolated final class RawModel: CatchUpLanguageModel {
        let base: FoundationModelsCatchUpModel
        let replies = Recorder<[String]>([])
        let digests = Recorder(0)

        init(_ base: FoundationModelsCatchUpModel) {
            self.base = base
        }

        func contextSize() async -> Int { await base.contextSize() }
        func tokenCount(_ text: String) async -> Int? { await base.tokenCount(text) }

        func digest(prompt: String, instructions: String, maximumResponseTokens: Int, until enough: @escaping @Sendable (String) -> Bool) async throws -> String {
            digests.update { $0 += 1 }
            let reply = try await base.digest(prompt: prompt, instructions: instructions, maximumResponseTokens: maximumResponseTokens, until: enough)
            replies.update { $0.append(reply) }
            return reply
        }

        func summarize(prompt: String, instructions: String, maximumResponseTokens: Int) -> AsyncThrowingStream<String, Error> {
            let replies = replies
            let stream = base.summarize(prompt: prompt, instructions: instructions, maximumResponseTokens: maximumResponseTokens)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    var last = ""
                    do {
                        for try await text in stream {
                            last = text
                            continuation.yield(text)
                        }
                        replies.update { $0.append(last) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    private func run(_ lines: [RecapLine], contextLimit: Int?) async throws {
        let counting = RawModel(FoundationModelsCatchUpModel(contextLimit: contextLimit))
        let engine = RecapEngine(model: counting, timings: RecapTimings())
        let input = F.input([F.conversation("#vela", lines)])
        let plan = await engine.plan(input)
        let clock = ContinuousClock()
        var summary = RecapSummary()
        let elapsed = try await clock.measure {
            summary = try await engine.run(input)
        }
        let report = [
            "",
            "== Recap of \(lines.count) lines, context \(contextLimit.map(String.init) ?? "system"): \(elapsed), planned \(plan.passes) passes, \(counting.digests.value) part and merge requests, skipped \(summary.skippedMessages)",
            "Overview:",
        ] + summary.overview.map { "  - \($0)" }
            + ["Topics:"] + summary.topics.map { "  - \($0.title) [\($0.lineIDs.count) lines]: \($0.summary) (\($0.participants.joined(separator: ", ")))" }
            + ["Notes:"] + summary.notes.map { "  - \($0.kind): \($0.owner.map { "\($0): " } ?? "")\($0.text)" }
            + ["For you:"] + summary.notesForYou.values.map { "  - \($0)" }
        print(report.joined(separator: "\n"))
        if ProcessInfo.processInfo.environment["VELA_LIVE_RAW"] == "1" {
            print("-- Raw replies:\n" + counting.replies.value.joined(separator: "\n-----\n"))
        }
        #expect(summary.isComplete)
        #expect(!summary.topics.isEmpty)
    }

    @Test func aShortStretch() async throws {
        try await run(lines(repeating: 1), contextLimit: nil)
    }

    @Test func aLongStretchOnASmallContext() async throws {
        try await run(lines(repeating: 12), contextLimit: 4_096)
    }

    @Test func moreDetail() async throws {
        let model = FoundationModelsCatchUpModel(contextLimit: 4_096)
        let clock = ContinuousClock()
        var detail = RecapDetail()
        let elapsed = try await clock.measure {
            detail = try await RecapEngine(model: model).detail(
                RecapDetailRequest(lines: lines(repeating: 1), ownNick: "doug", focus: "Sidebar rail review")
            )
        }
        print("\n== More detail in \(elapsed):\n" + detail.points.map { "  - \($0)" }.joined(separator: "\n"))
        #expect(!detail.points.isEmpty)
    }
}
