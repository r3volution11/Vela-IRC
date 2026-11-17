// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIntelligence

/// Runs the real on-device model. Opt in with `VELA_LIVE_MODEL=1` on a Mac
/// with Apple Intelligence turned on:
///
///     VELA_LIVE_MODEL=1 swift test --package-path Packages/VelaKit --filter CatchUpLiveModel
///
/// Prints each summary and how long it took.
@MainActor
@Suite("Catch me up with the live model", .enabled(if: ProcessInfo.processInfo.environment["VELA_LIVE_MODEL"] == "1"), .serialized)
struct CatchUpLiveModelTests {
    typealias F = CatchUpFixtures

    /// A demo-like #vela afternoon.
    static let script: [(String, String)] = [
        ("marisol", "morning all ☕"),
        ("kenji", "o/ — the new theme engine landed on main last night"),
        ("kenji", "every surface reads from tokens now, even the title bar"),
        ("ada", "Palenight looks *so* good with the grouped layout"),
        ("theo", "here's the reference shot of the Crab Nebula I was talking about"),
        ("theo", "https://upload.wikimedia.org/wikipedia/commons/thumb/0/00/Crab_Nebula.jpg/1280px-Crab_Nebula.jpg"),
        ("priya", "gorgeous. that's the vibe for the Ocean theme"),
        ("doug", "pushed the IRCv3 spec notes → https://ircv3.net/irc/"),
        ("lukas", "nice, chathistory + reactions are the big ones for me"),
        ("marisol", "has anyone tried the Blender open movie embed? https://www.youtube.com/watch?v=aqz-KE-bpKQ"),
        ("kenji", "plays inline, and the facade means no web view until you click ▶"),
        ("ada", "spinning earth for no reason https://upload.wikimedia.org/wikipedia/commons/thumb/e/e1/Rotating_earth_animated.gif/250px-Rotating_earth_animated.gif"),
        ("wren", "doug: can you review the sidebar rail PR when you get a sec?"),
        ("theo", "also the Swift blog has a post on the new concurrency defaults: https://www.swift.org/blog/"),
        ("lukas", "does the rail remember its width per window or globally?"),
        ("wren", "per window right now, but I could make it a setting"),
        ("kenji", "global feels more mac-like to me"),
        ("ada", "agreed, global"),
        ("priya", "any chance the Ocean theme ships with the next build?"),
        ("marisol", "if someone reviews the contrast pass, yes"),
        ("priya", "I can do that tonight"),
        ("nadia", "the release notes draft is up, please add your bits"),
        ("theo", "added the media section"),
        ("lukas", "added chathistory notes"),
    ]

    private func lines(repeating times: Int) -> [CatchUpLine] {
        var lines: [CatchUpLine] = []
        for round in 0..<times {
            for (index, pair) in Self.script.enumerated() {
                let text = round == 0 ? pair.1 : "\(pair.1) (round \(round + 1))"
                lines.append(F.line(pair.0, text, minute: round * 100 + index))
            }
        }
        return lines
    }

    /// The live model, counting the requests the engine makes.
    nonisolated final class CountingModel: CatchUpLanguageModel {
        let base: FoundationModelsCatchUpModel
        let digests = Recorder(0)

        init(_ base: FoundationModelsCatchUpModel) {
            self.base = base
        }

        func contextSize() async -> Int { await base.contextSize() }
        func tokenCount(_ text: String) async -> Int? { await base.tokenCount(text) }
        func schemaTokenCount(for pass: CatchUpPrompts.Pass) async -> Int? { await base.schemaTokenCount(for: pass) }

        func digest(prompt: String, instructions: String) async throws -> CatchUpDraft {
            digests.update { $0 += 1 }
            return try await base.digest(prompt: prompt, instructions: instructions)
        }

        func summarize(prompt: String, instructions: String) -> AsyncThrowingStream<CatchUpDraft, Error> {
            base.summarize(prompt: prompt, instructions: instructions)
        }
    }

    private func run(
        _ lines: [CatchUpLine],
        label: String,
        model: FoundationModelsCatchUpModel = FoundationModelsCatchUpModel()
    ) async throws -> CatchUpSummary {
        let availability = IntelligenceAvailability.live()
        try #require(availability.status.isAvailable, "Apple Intelligence isn't available: \(availability.status.title)")
        let counting = CountingModel(model)
        let engine = CatchUpEngine(model: counting)
        let request = F.request(lines)
        let clock = ContinuousClock()
        let start = clock.now
        let firstPartial = Recorder<Duration?>(nil)
        let partials = Recorder(0)
        let summary = try await engine.run(request) { snapshot in
            partials.update { $0 += 1 }
            if !snapshot.overview.isEmpty {
                firstPartial.update { if $0 == nil { $0 = clock.now - start } }
            }
        }
        let elapsed = clock.now - start
        func seconds(_ duration: Duration) -> String {
            duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
        }
        var report = "\n=== \(label): \(lines.count) lines, \(counting.digests.value) digest requests, \(seconds(elapsed)) total"
        if let first = firstPartial.value { report += ", overview began after \(seconds(first))" }
        report += ", \(partials.value) snapshots\n"
        report += "Overview: \(summary.overview)\n"
        for topic in summary.topics {
            let index = topic.firstLineID.flatMap { id in lines.firstIndex { $0.id == id } }
            report += "• \(topic.title) — \(topic.summary) [\(topic.participants.joined(separator: ", "))] → line \(index.map { "\($0 + 1)" } ?? "none")\n"
        }
        for note in summary.addressedToYou { report += "@ \(note)\n" }
        print(report)
        return summary
    }

    @Test func summarizesAShortConversation() async throws {
        let summary = try await run(lines(repeating: 1), label: "Single pass")
        #expect(summary.isComplete)
        #expect(!summary.overview.isEmpty)
        #expect(!summary.topics.isEmpty)
        #expect(summary.topics.count <= 6)
        #expect(!summary.addressedToYou.isEmpty)
    }

    @Test func summarizesSixHundredLinesInChunks() async throws {
        let summary = try await run(lines(repeating: 25), label: "Map/reduce, 600 lines")
        #expect(summary.isComplete)
        #expect(!summary.topics.isEmpty)
    }

    @Test func summarizesLikeMacOS26() async throws {
        // 4,096 tokens and estimated counts, as on macOS 26.0–26.3.
        let model = FoundationModelsCatchUpModel(contextLimit: 4096, countsTokens: false)
        let summary = try await run(lines(repeating: 10), label: "4K context, estimated tokens", model: model)
        #expect(summary.isComplete)
        #expect(!summary.topics.isEmpty)
    }

    @Test func goesThroughTheSummarizer() async throws {
        let availability = IntelligenceAvailability.live()
        let summarizer = FoundationModelSummarizer(availability: availability)
        var snapshots: [CatchUpSummary] = []
        for try await snapshot in summarizer.summarize(F.request(lines(repeating: 1))) { snapshots.append(snapshot) }
        #expect(snapshots.count > 2)
        #expect(snapshots.last?.isComplete == true)
        #expect(snapshots.dropLast().allSatisfy { !$0.isComplete })
    }

    @Test func reportsTokenCounts() async throws {
        let model = FoundationModelsCatchUpModel()
        let context = await model.contextSize()
        let schema = await model.schemaTokenCount(for: .single)
        let digestSchema = await model.schemaTokenCount(for: .digest)
        let instructions = await model.tokenCount(CatchUpPrompts.instructions(ownNick: "doug", pass: .single))
        let transcript = CatchUpTranscript(lines: lines(repeating: 1), ownNick: "doug")
        let counted = await model.tokenCount(transcript.text)
        let estimated = CatchUpChunker.estimatedTokens(transcript.text)
        print("\n=== Context \(context); schema \(schema.map(String.init) ?? "n/a") (digest \(digestSchema.map(String.init) ?? "n/a")); instructions \(instructions.map(String.init) ?? "n/a"); transcript counted \(counted.map(String.init) ?? "n/a") vs estimated \(estimated)\n")
        #expect(context >= 4096)
    }
}
