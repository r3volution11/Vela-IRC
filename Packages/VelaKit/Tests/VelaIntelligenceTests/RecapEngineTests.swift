// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
@testable import VelaIntelligence

@Suite("Recap engine")
struct RecapEngineTests {
    typealias F = RecapFixtures

    /// A part's reply naming its own first and last lines, and a decision.

    nonisolated static func partReply(_ prompt: String) -> String {
        if prompt.hasPrefix("Recaps of consecutive parts") {
            return "OVERVIEW: Merged.\nTOPIC: T1, T2 | Merged | Combined. | alice"
        }
        let numbers = lineNumbers(in: prompt)
        guard let first = numbers.first, let last = numbers.last else { return "OVERVIEW: Nothing." }
        return """
        OVERVIEW: Part \(first).
        TOPIC: [\(first)-\(last)] | Part \(first) | Talked about the build. | alice, bob
        DECISION: [\(first)] | Item \(first + 1000) is approved.
        """
    }

    // MARK: One pass

    @Test func aShortStretchIsOnePassStreamed() async throws {
        let lines = [
            F.line("kenji", "the new theme engine landed on main", minute: 0),
            F.line("ada", "Palenight looks great with it", minute: 1),
            F.line("wren", "doug: can you review the sidebar PR?", minute: 2),
            F.line("priya", "I'll do the contrast pass tonight", minute: 3),
        ]
        let full = """
        Here's the recap:
        OVERVIEW: kenji landed the theme engine.
        OVERVIEW: wren wants your review.
        TOPIC: [1-2] | Theme engine | It landed; ada likes Palenight. | kenji, ada
        TOPIC: [3] | Review | wren asked for a review. | wren
        DECISION: [2] | Palenight is the look.
        QUESTION: [3] | Who reviews the sidebar PR?
        TODO: [4] | priya | do the contrast pass tonight
        YOU: [3] | wren | asked you to review the sidebar PR
        """
        let model = FakeCatchUpModel(finalText: { _ in
            ["OVERVIEW: kenji landed the theme engine.\n", "OVERVIEW: kenji landed the theme engine.\nTOPIC: [1-2] | Theme engine | It landed. | kenji, ada\n", full]
        })
        let snapshots = Recorder<[RecapSummary]>([])
        let summary = try await RecapEngine(model: model).run(F.input([F.conversation("#vela", lines)])) { snapshot in
            snapshots.update { $0.append(snapshot) }
        }

        #expect(model.digestCalls.isEmpty)
        #expect(model.summarizeCalls.count == 1)
        let prompt = try #require(model.summarizeCalls.first?.prompt)
        #expect(lineNumbers(in: prompt) == [1, 2, 3, 4])
        #expect(prompt.contains("[3] wren: doug: can you review the sidebar PR?"))
        #expect(!prompt.contains("Conversation 1:"))

        #expect(summary.isComplete)
        #expect(summary.overview == ["kenji landed the theme engine.", "wren wants your review."])
        #expect(summary.topics.map(\.title) == ["Theme engine", "Review"])
        #expect(summary.topics[0].lineIDs == [lines[0].id, lines[1].id])
        #expect(summary.topics[0].start?.lineID == lines[0].id)
        #expect(summary.topics[0].participants == ["kenji", "ada"])
        // A topic given only its first line runs to the end of the part.
        #expect(summary.topics[1].lineIDs == [lines[2].id, lines[3].id])
        #expect(summary.notes(.decision).map(\.reference?.lineID) == [lines[1].id])
        #expect(summary.notes(.question).first?.text == "Who reviews the sidebar PR?")
        #expect(summary.notes(.followUp).first?.owner == "priya")
        #expect(summary.notes(.followUp).first?.reference?.lineID == lines[3].id)
        #expect(summary.notesForYou[lines[2].id] == "wren asked you to review the sidebar PR.")

        // Words stream in: the overview before the topics.
        let firstWords = try #require(snapshots.value.first { !$0.overview.isEmpty })
        #expect(firstWords.topics.isEmpty)
        #expect(snapshots.value.contains { $0.topics.count == 1 })
        #expect(snapshots.value.allSatisfy { !$0.isComplete })
    }

    @Test func severalConversationsAreNumberedNotNamed() async throws {
        let input = F.input([
            F.conversation("#vela", [F.line("kenji", "hello from vela")]),
            F.conversation("#swift", [F.line("mina", "hello from swift", minute: 1)]),
        ], place: .network(F.network))
        let model = FakeCatchUpModel(finalText: { _ in ["OVERVIEW: Two hellos.\nTOPIC: [2] | Swift | mina said hello. | mina"] })
        let summary = try await RecapEngine(model: model).run(input)
        let prompt = try #require(model.summarizeCalls.first?.prompt)
        #expect(prompt.contains("Conversation 1:\n[1] kenji: hello from vela\nConversation 2:\n[2] mina: hello from swift"))
        #expect(prompt.contains("in 2 conversations"))
        #expect(!prompt.contains("#vela") && !prompt.contains("#swift"))
        // Line 2 is in #swift: the topic jumps there.
        #expect(summary.topics.first?.start?.conversation == F.id("#swift"))
    }

    @Test func atMostTheNewestTwoThousandMessagesAreRead() {
        let lines = F.chatter(2_500)
        let transcript = RecapTranscript(F.input([F.conversation("#vela", lines)]))
        #expect(transcript.entries.count == RecapLimits.summaryLines)
        #expect(transcript.omittedLines == 500)
        #expect(transcript.entries.first?.lineID == lines[500].id)
    }

    // MARK: Map and reduce

    @Test func aLongStretchIsReadInPartsThenCombined() async throws {
        let lines = F.chatter(300)
        let model = FakeCatchUpModel(
            context: 2048,
            digestText: { Self.partReply($0) },
            finalText: { prompt in
                // The parts' topics are numbered for the merge.
                #expect(prompt.contains("T1: Part 1 | Talked about the build. | alice, bob"))
                #expect(prompt.contains("T2: Part"))
                return ["OVERVIEW: Release planning.\nOVERVIEW: The build.\nTOPIC: T1, T2 | Release | Planned the release. | bob\nTOPIC: T3 | Build | Talked. | carol"]
            }
        )
        let snapshots = Recorder<[RecapSummary]>([])
        let summary = try await RecapEngine(model: model).run(F.input([F.conversation("#vela", lines)])) { snapshot in
            snapshots.update { $0.append(snapshot) }
        }

        #expect(model.digestCalls.count >= 3)
        #expect(model.summarizeCalls.count == 1)
        #expect(summary.isComplete)
        #expect(summary.overview == ["Release planning.", "The build."])
        // Its topics first; a merge that kept few of the parts' topics is
        // filled in with the others, in order.
        #expect(Array(summary.topics.map(\.title).prefix(2)) == ["Release", "Build"])
        #expect(summary.topics.count == RecapPrompts.maximumTopics)
        #expect(summary.topics[2].title.hasPrefix("Part "))

        // The merged topic keeps both parts' lines: its jump goes to the
        // first, and More detail reads them all.
        let parts = model.digestCalls.map { lineNumbers(in: $0.prompt) }
        let firstTwo = (parts[0] + parts[1]).map { lines[$0 - 1].id }
        #expect(summary.topics[0].lineIDs == firstTwo)
        #expect(summary.topics[0].start?.lineID == lines[0].id)

        // Decisions are combined here, one per part, in order.
        let decisions = summary.notes(.decision)
        #expect(decisions.count == min(parts.count, RecapPrompts.maximumNotes))
        #expect(decisions.first?.reference?.lineID == lines[0].id)

        // Progress: messages read go up, and the parts' topics show first.
        let reads = snapshots.value.compactMap { $0.progress?.messagesRead }
        #expect(reads == reads.sorted())
        #expect(reads.last == 300)
        #expect(snapshots.value.contains { $0.topicsAreProvisional && !$0.topics.isEmpty })
        #expect(snapshots.value.contains { $0.progress?.isWriting == true })
    }

    @Test func manyPartsAreCombinedInStages() async throws {
        let lines = F.chatter(1_200)
        let model = FakeCatchUpModel(
            context: 2048,
            digestText: { Self.partReply($0) },
            finalText: { _ in ["OVERVIEW: All of it.\nTOPIC: T1 | Everything | Talked. | alice"] }
        )
        let summary = try await RecapEngine(model: model).run(F.input([F.conversation("#vela", lines)]))
        let merges = model.digestCalls.filter { $0.prompt.hasPrefix("Recaps of consecutive parts") }
        #expect(!merges.isEmpty)
        #expect(summary.isComplete)
        #expect(summary.topics.first?.title == "Everything")
        #expect(!(summary.topics.first?.lineIDs.isEmpty ?? true))
    }

    @Test func aDeclinedPartIsSkipped() async throws {
        let lines = F.chatter(300)
        let model = FakeCatchUpModel(
            context: 2048,
            digestText: { prompt in
                if lineNumbers(in: prompt).first == 1 { throw CatchUpModelError.declined }
                return Self.partReply(prompt)
            },
            finalText: { _ in ["OVERVIEW: Most of it.\nTOPIC: T1 | Rest | Talked. | bob"] }
        )
        let summary = try await RecapEngine(model: model).run(F.input([F.conversation("#vela", lines)]))
        let firstPart = lineNumbers(in: try #require(model.digestCalls.first?.prompt)).count
        #expect(summary.skippedMessages == firstPart)
        #expect(summary.isComplete)
    }

    @Test func aRefusalWrittenOutCountsAsDeclined() async throws {
        let model = FakeCatchUpModel(finalText: { _ in ["I'm sorry, but I can't help with that."] })
        await #expect(throws: CatchUpError.declined) {
            try await RecapEngine(model: model).run(F.input([F.conversation("#vela", [F.line("a", "x")])]))
        }
    }

    @Test func everyPartDeclinedFails() async throws {
        let model = FakeCatchUpModel(
            context: 2048,
            digestText: { _ in throw CatchUpModelError.declined },
            finalText: { _ in throw CatchUpModelError.declined }
        )
        await #expect(throws: CatchUpError.declined) {
            try await RecapEngine(model: model).run(F.input([F.conversation("#vela", F.chatter(300))]))
        }
    }

    @Test func aDeclinedCombineKeepsThePartsOwnTopics() async throws {
        let model = FakeCatchUpModel(
            context: 2048,
            digestText: { Self.partReply($0) },
            finalText: { _ in throw CatchUpModelError.declined }
        )
        let summary = try await RecapEngine(model: model).run(F.input([F.conversation("#vela", F.chatter(300))]))
        #expect(summary.isComplete)
        #expect(summary.topics.first?.title == "Part 1")
        #expect(summary.overview.first == "Part 1.")
    }

    @Test func aPartTooLongIsReadInHalves() async throws {
        let model = FakeCatchUpModel(
            context: 2048,
            digestText: { prompt in
                if lineNumbers(in: prompt).count > 12 { throw CatchUpModelError.contextExceeded }
                return Self.partReply(prompt)
            },
            finalText: { _ in ["OVERVIEW: Done.\nTOPIC: T1 | All | Talked. | alice"] }
        )
        let summary = try await RecapEngine(model: model).run(F.input([F.conversation("#vela", F.chatter(120))]))
        #expect(summary.isComplete)
        #expect(summary.skippedMessages == 0)
        #expect(model.digestCalls.contains { lineNumbers(in: $0.prompt).count <= 12 })
    }

    @Test func planningCountsPassesAndTime() async {
        let timings = RecapTimings()
        let engine = RecapEngine(model: FakeCatchUpModel(context: 2048), timings: timings)
        let short = await engine.plan(F.input([F.conversation("#vela", F.chatter(5))]))
        #expect(short.passes == 1)
        #expect(!short.asksFirst)
        let long = await engine.plan(F.input([F.conversation("#vela", F.chatter(600))]))
        #expect(long.passes > 5)
        #expect(long.estimatedSeconds == Double(long.passes) * RecapTimings.defaultOnDeviceSeconds)
        #expect(long.asksFirst)
        // A measured pass replaces the guess.
        timings.record(4, venue: .onDevice)
        let measured = await engine.plan(F.input([F.conversation("#vela", F.chatter(600))]))
        #expect(measured.estimatedSeconds == Double(measured.passes) * 4)
    }

    // MARK: More detail

    @Test func moreDetailReadsJustTheTopicsLines() async throws {
        let lines = [
            F.line("kenji", "the theme engine landed"),
            F.line("ada", "Palenight looks great", minute: 1),
        ]
        let model = FakeCatchUpModel(finalText: { _ in ["POINT: kenji landed the theme engine.\n- ada likes Palenight.\n"] })
        let progress = Recorder<[RecapDetail]>([])
        let detail = try await RecapEngine(model: model).detail(
            RecapDetailRequest(lines: lines, ownNick: "doug", focus: "Theme engine")
        ) { detail in progress.update { $0.append(detail) } }
        let call = try #require(model.summarizeCalls.first)
        #expect(call.prompt.contains("[1] kenji: the theme engine landed"))
        #expect(call.prompt.hasSuffix("Write a closer look at: Theme engine"))
        #expect(call.limit == RecapPrompts.responseTokens(for: .detail))
        #expect(detail.points == ["kenji landed the theme engine.", "ada likes Palenight."])
        #expect(detail.isComplete)
    }

    @Test func moreDetailOnAHugeTopicReadsWhatFits() async throws {
        let model = FakeCatchUpModel(context: 2048, finalText: { _ in ["POINT: Lots."] })
        _ = try await RecapEngine(model: model).detail(RecapDetailRequest(lines: F.chatter(400), ownNick: "doug", focus: "Build"))
        let numbers = lineNumbers(in: try #require(model.summarizeCalls.first?.prompt))
        #expect(numbers.first == 1)
        #expect(numbers.count < 400)
    }

    @Test func moreDetailThatsDeclinedSaysSo() async {
        let model = FakeCatchUpModel(finalText: { _ in throw CatchUpModelError.declined })
        await #expect(throws: CatchUpError.declined) {
            try await RecapEngine(model: model).detail(RecapDetailRequest(lines: [F.line("a", "b")], ownNick: "doug", focus: "x"))
        }
    }
}
