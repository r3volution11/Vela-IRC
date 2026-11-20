// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import FoundationModels
import Testing
@testable import VelaIntelligence

@Suite("Catch me up engine")
struct CatchUpEngineTests {
    typealias F = CatchUpFixtures

    // MARK: Single pass

    @Test func aShortConversationTakesOnePass() async throws {
        let lines = [
            F.line("kenji", "the new theme engine landed on main"),
            F.line("ada", "Palenight looks great"),
            F.line("wren", "doug: can you review the sidebar PR?"),
        ]
        let model = FakeCatchUpModel(final: { _ in
            [
                CatchUpDraft(overview: "Theme"),
                CatchUpDraft(overview: "Theme talk.", topics: [.init(title: "Theme engine", participants: ["kenji"], firstLine: 1)]),
                CatchUpDraft(
                    overview: "Theme talk and a review request.",
                    topics: [
                        .init(title: "Theme engine", summary: "It landed.", participants: ["kenji", "ada"], firstLine: 1),
                        .init(title: "Review", summary: "wren asked for one.", participants: ["wren"], firstLine: 3),
                    ],
                    addressedToYou: ["wren asked you to review the sidebar PR."]
                ),
            ]
        })
        let partials = Recorder<[CatchUpSummary]>([])
        let summary = try await CatchUpEngine(model: model).run(F.request(lines)) { snapshot in
            partials.update { $0.append(snapshot) }
        }

        #expect(model.digestCalls.isEmpty)
        #expect(model.summarizeCalls.count == 1)
        let prompt = try #require(model.summarizeCalls.first?.prompt)
        #expect(lineNumbers(in: prompt) == [1, 2, 3])
        #expect(prompt.contains("[3] wren: doug: can you review the sidebar PR?"))

        #expect(partials.value.map(\.overview) == ["Theme", "Theme talk.", "Theme talk and a review request."])
        #expect(partials.value.allSatisfy { !$0.isComplete })
        #expect(summary.isComplete)
        #expect(summary.messageCount == 3)
        #expect(summary.topics.map(\.title) == ["Theme engine", "Review"])
        #expect(summary.topics.map(\.firstLineID) == [lines[0].id, lines[2].id])
        #expect(summary.addressedToYou == ["wren asked you to review the sidebar PR."])
    }

    @Test func instructionsNameTheReaderAndTheRules() throws {
        let instructions = CatchUpPrompts.instructions(ownNick: "doug", pass: .single)
        #expect(instructions.contains("“doug”"))
        #expect(instructions.contains("Call the reader “you”"))
        #expect(instructions.contains("Never invent"))
        #expect(instructions.contains("neutrally, without taking sides or repeating insults"))
        #expect(instructions.contains("exactly as they appear"))
        #expect(instructions.contains("OVERVIEW: <one or two sentences on the whole conversation>"))
        #expect(instructions.contains("TOPIC: [<number of the first transcript line about it>] | <short title> | <one sentence on what was said> | <nicks involved, comma-separated>"))
        #expect(instructions.contains("YOU: <nick> <what they asked or told you>"))
        #expect(instructions.contains("names “doug”"))
        #expect(instructions.contains("at most 6 TOPIC lines"))
        #expect(CatchUpPrompts.instructions(ownNick: "doug", pass: .digest).contains("at most 4 TOPIC lines"))
        #expect(CatchUpPrompts.instructions(ownNick: "doug", pass: .merge).contains("TOPIC: [<the smallest number of the parts' topics it combines>]"))
        // The example's line parses as the format says.
        let example = try #require(instructions.split(separator: "\n").first { $0.hasPrefix("TOPIC: [17]") })
        #expect(CatchUpReply.parse(String(example)).topics.first?.firstLine == 17)
        // The format is part of the instructions, and counted with them.
        #expect(instructions.hasSuffix(CatchUpPrompts.format(ownNick: "doug", pass: .single)))
        // The transcript never goes in the instructions.
        #expect(!instructions.contains("[1]"))
    }

    /// No prompt or instruction names the channel or the network: a name
    /// alone can read as a subject Apple Intelligence turns down.
    @Test func promptsNeverNameTheChannelOrNetwork() async throws {
        for (channel, network) in [("##politicalfun", "PoliticsNet"), ("#vela", "Libera.Chat"), ("mallory", "Example IRC")] {
            for lines in [F.chatter(3), F.chatter(240)] {
                let model = FakeCatchUpModel(
                    context: 2048,
                    digest: { prompt in
                        CatchUpDraft(overview: "A part.", topics: [.init(title: "Part", participants: ["alice"], firstLine: lineNumbers(in: prompt).first)])
                    },
                    final: { _ in [CatchUpDraft(overview: "All of it.")] }
                )
                var request = F.request(lines, name: channel)
                request.networkName = network
                _ = try await CatchUpEngine(model: model).run(request)
                #expect(!model.calls.value.isEmpty)
                for call in model.calls.value {
                    let (prompt, instructions) = switch call {
                    case .digest(let prompt, let instructions, _), .summarize(let prompt, let instructions, _): (prompt, instructions)
                    }
                    for text in [prompt, instructions] {
                        #expect(!text.localizedCaseInsensitiveContains(channel), "\(channel) in \(text)")
                        #expect(!text.localizedCaseInsensitiveContains(network), "\(network) in \(text)")
                    }
                }
                // Including the merges of a long stretch.
                if lines.count > 3 { #expect(!model.digestCalls.isEmpty) }
            }
        }
        // Planning measures the same prompts.
        let router = CatchUpRouter(onDevice: FakeCatchUpModel(), cloud: nil)
        _ = await router.plan(F.request(F.chatter(30), name: "##politicalfun"))
    }

    @Test func nothingToSummarize() async {
        let model = FakeCatchUpModel()
        await #expect(throws: CatchUpError.nothingToSummarize) {
            try await CatchUpEngine(model: model).run(F.request([F.line("alice", "   ")]))
        }
        #expect(model.calls.value.isEmpty)
    }

    // MARK: Map / reduce

    @Test func aLongConversationIsDigestedInChunksThenMerged() async throws {
        let lines = F.chatter(240)
        let model = FakeCatchUpModel(
            context: 2048,
            digest: { prompt in
                let numbers = lineNumbers(in: prompt)
                return CatchUpDraft(
                    overview: "Lines \(numbers.first!)–\(numbers.last!).",
                    topics: [.init(title: "Part from \(numbers.first!)", participants: ["alice"], firstLine: numbers.first!)]
                )
            },
            final: { prompt in
                // The second part's line, as its digest cites it, and one made up.
                let second = prompt.split(separator: "\n").first { $0.hasPrefix("Part 2, lines ") }
                let line = second.flatMap { Int($0.dropFirst("Part 2, lines ".count).prefix { $0.isNumber }) }
                return [CatchUpDraft(overview: "Release planning.", topics: [
                    .init(title: "Release", participants: ["bob"], firstLine: line),
                    .init(title: "Invented", participants: ["bob"], firstLine: 2),
                ])]
            }
        )
        let summary = try await CatchUpEngine(model: model).run(F.request(lines))

        let digests = model.digestCalls.map { lineNumbers(in: $0.prompt) }
        #expect(digests.count > 1)
        // Every line exactly once, in order.
        #expect(digests.flatMap { $0 } == Array(1...240))
        // Chunks are about even.
        let sizes = digests.map(\.count)
        #expect(sizes.max()! - sizes.min()! <= 3)

        #expect(model.summarizeCalls.count == 1)
        let merge = try #require(model.summarizeCalls.first?.prompt)
        #expect(merge.contains("Part 1, lines 1–\(digests[0].last!):\nOVERVIEW: Lines 1–\(digests[0].last!).\nTOPIC: [1] | Part from 1 |  | alice"))
        #expect(summary.overview == "Release planning.")
        // A merge can only cite the lines its parts cited.
        #expect(summary.topics.map(\.firstLineID) == [lines[digests[1][0] - 1].id, nil])
        #expect(summary.messageCount == 240)
    }

    @Test func countedTokensCalibrateTheChunks() async throws {
        // With exact counts (4 characters a token) lines cost less than the
        // 3-bytes estimate, so fewer chunks are needed.
        let lines = F.chatter(240)
        let estimated = FakeCatchUpModel(context: 2048)
        _ = try await CatchUpEngine(model: estimated).run(F.request(lines))
        let counted = FakeCatchUpModel(context: 2048, counts: true)
        _ = try await CatchUpEngine(model: counted).run(F.request(lines))
        #expect(counted.digestCalls.count < estimated.digestCalls.count)
    }

    @Test func anExceededContextSplitsTheChunk() async throws {
        let lines = F.chatter(240)
        // The model can only take 20 lines at a time, whatever the estimate says.
        let model = FakeCatchUpModel(
            context: 4096,
            digest: { prompt in
                if lineNumbers(in: prompt).count > 20 { throw CatchUpModelError.contextExceeded }
                return CatchUpDraft(overview: "ok")
            },
            final: { prompt in
                if lineNumbers(in: prompt).count > 20 { throw CatchUpModelError.contextExceeded }
                return [CatchUpDraft(overview: "Merged.")]
            }
        )
        let summary = try await CatchUpEngine(model: model).run(F.request(lines))
        #expect(summary.overview == "Merged.")
        let accepted = model.digestCalls.map { lineNumbers(in: $0.prompt) }.filter { !$0.isEmpty && $0.count <= 20 }
        #expect(accepted.flatMap { $0 } == Array(1...240))
    }

    @Test func aSinglePassThatDoesNotFitFallsBackToChunks() async throws {
        let lines = F.chatter(30)
        let model = FakeCatchUpModel(
            digest: { _ in CatchUpDraft(overview: "part") },
            final: { prompt in
                if !lineNumbers(in: prompt).isEmpty { throw CatchUpModelError.contextExceeded }
                return [CatchUpDraft(overview: "Merged from parts.")]
            }
        )
        let summary = try await CatchUpEngine(model: model).run(F.request(lines))
        #expect(summary.overview == "Merged from parts.")
        #expect(!model.digestCalls.isEmpty)
        #expect(model.summarizeCalls.count == 2)
    }

    @Test func digestsThatDoNotFitOneMergeAreMergedInLevels() async throws {
        let lines = F.chatter(400)
        let padding = String(repeating: "Long digest text about many things. ", count: 12)
        let model = FakeCatchUpModel(
            context: 2048,
            digest: { prompt in
                CatchUpDraft(overview: prompt.contains("Summaries of consecutive parts") ? "merged" : padding)
            },
            final: { _ in [CatchUpDraft(overview: "Done.")] }
        )
        let summary = try await CatchUpEngine(model: model).run(F.request(lines))
        #expect(summary.overview == "Done.")
        let intermediate = model.digestCalls.filter { $0.prompt.contains("Summaries of consecutive parts") }
        #expect(!intermediate.isEmpty)
    }

    // MARK: Progress

    /// A long stretch is read in parts before any words appear: each part
    /// is reported, so the card can say "Reading… 3 of 8".
    @Test func chunkPassesReportProgress() async throws {
        let model = FakeCatchUpModel(context: 2048)
        let partials = Recorder<[CatchUpSummary]>([])
        let summary = try await CatchUpEngine(model: model).run(F.request(F.chatter(240))) { snapshot in
            partials.update { $0.append(snapshot) }
        }
        let parts = model.digestCalls.count
        #expect(parts > 1)
        let reading = partials.value.filter { !$0.hasText }
        #expect(reading.map(\.progress) == (0...parts).map { CatchUpProgress(completed: $0, total: parts) })
        #expect(reading.allSatisfy { !$0.isComplete && !$0.isRevising && $0.messageCount == 240 })
        // Then the summary is written.
        #expect(partials.value.last?.overview == "All of it.")
        #expect(partials.value.last?.progress == nil)
        #expect(summary.overview == "All of it.")
    }

    /// A part that turns out too long is read in halves: one more part.
    @Test func aSplitPartAddsToTheTotal() async throws {
        let model = FakeCatchUpModel(
            context: 4096,
            digest: { prompt in
                if lineNumbers(in: prompt).count > 20 { throw CatchUpModelError.contextExceeded }
                return CatchUpDraft(overview: "ok")
            },
            final: { prompt in
                if lineNumbers(in: prompt).count > 20 { throw CatchUpModelError.contextExceeded }
                return [CatchUpDraft(overview: "Merged.")]
            }
        )
        let partials = Recorder<[CatchUpSummary]>([])
        _ = try await CatchUpEngine(model: model).run(F.request(F.chatter(240))) { snapshot in
            partials.update { $0.append(snapshot) }
        }
        let progress = partials.value.compactMap(\.progress)
        #expect(progress.map(\.total) == progress.map(\.total).sorted())
        #expect(progress.map(\.completed) == progress.map(\.completed).sorted())
        #expect(progress.last?.isFinished == true)
        // Every request that answered is a part read.
        let answered = model.digestCalls.filter { lineNumbers(in: $0.prompt).count <= 20 }.count
        #expect(progress.last?.completed == answered)
    }

    // MARK: Response limits

    @Test func everyRequestCapsItsResponse() async throws {
        let long = FakeCatchUpModel(context: 2048)
        _ = try await CatchUpEngine(model: long).run(F.request(F.chatter(240)))
        #expect(!long.digestCalls.isEmpty)
        #expect(long.digestCalls.allSatisfy { $0.limit == CatchUpEngine.responseTokens(for: .digest) })
        #expect(long.summarizeCalls.map(\.limit) == [CatchUpEngine.responseTokens(for: .merge)])

        let short = FakeCatchUpModel()
        _ = try await CatchUpEngine(model: short).run(F.request(F.chatter(3)))
        #expect(short.summarizeCalls.map(\.limit) == [CatchUpEngine.responseTokens(for: .single)])
        #expect(CatchUpEngine.responseTokens(for: .single) == 750)
        #expect(CatchUpEngine.responseTokens(for: .digest) == 500)
    }

    @Test func foundationModelsRequestsAreCapped() {
        let options = FoundationModelsCatchUpModel.options(maximumResponseTokens: 750)
        #expect(options.maximumResponseTokens == 750)
        #expect(options.temperature == 0.3)
    }

    // MARK: Words are never taken back

    /// The single pass wrote something, then ran out of room: its words
    /// stay, dimmed, while the stretch is read in parts, until the retry
    /// writes.
    @Test func textIsNeverTakenBack() async throws {
        let model = FakeCatchUpModel(steps: { prompt in
            if !lineNumbers(in: prompt).isEmpty {
                return [.draft(CatchUpDraft(overview: "Theme talk")), .draft(CatchUpDraft(overview: "Theme talk and a review.")), .fail(.contextExceeded)]
            }
            return [.draft(CatchUpDraft(overview: "Merged")), .draft(CatchUpDraft(overview: "Merged from parts."))]
        })
        let partials = Recorder<[CatchUpSummary]>([])
        let summary = try await CatchUpEngine(model: model).run(F.request(F.chatter(30))) { snapshot in
            partials.update { $0.append(snapshot) }
        }
        let snapshots = partials.value
        let firstText = try #require(snapshots.firstIndex { $0.hasText })
        #expect(snapshots[firstText...].allSatisfy { $0.hasText })
        let redoing = snapshots.filter(\.isRevising)
        #expect(!redoing.isEmpty)
        #expect(redoing.allSatisfy { $0.overview == "Theme talk and a review." })
        #expect(redoing.contains { $0.progress != nil })
        // The retry's words replace them.
        #expect(snapshots.last?.overview == "Merged from parts.")
        #expect(snapshots.last?.isRevising == false)
        #expect(summary.overview == "Merged from parts.")
        #expect(!model.digestCalls.isEmpty)
    }

    // MARK: Declined parts

    @Test func aDeclinedPartIsSkipped() async throws {
        let model = FakeCatchUpModel(
            context: 2048,
            digest: { prompt in
                let numbers = lineNumbers(in: prompt)
                if numbers.first == 1 { throw CatchUpModelError.declined }
                return CatchUpDraft(overview: "Lines from \(numbers.first!).", topics: [.init(title: "Part from \(numbers.first!)")])
            },
            final: { _ in [CatchUpDraft(overview: "The rest of it.")] }
        )
        let summary = try await CatchUpEngine(model: model).run(F.request(F.chatter(240)))
        let declined = try #require(model.digestCalls.first { lineNumbers(in: $0.prompt).first == 1 })
        #expect(model.digestCalls.count > 1)
        #expect(summary.overview == "The rest of it.")
        #expect(summary.skippedMessages == lineNumbers(in: declined.prompt).count)
        let topics = try #require(model.summarizeCalls.last?.prompt).split(separator: "\n").filter { $0.hasPrefix("TOPIC: ") }
        #expect(!topics.isEmpty)
        #expect(!topics.contains { $0.hasSuffix("| Part from 1") })
    }

    /// A short stretch the model declines is read in halves, so only the
    /// half it declines is left out.
    @Test func aDeclinedSinglePassIsReadInHalves() async throws {
        let model = FakeCatchUpModel(
            digest: { prompt in
                if lineNumbers(in: prompt).contains(1) { throw CatchUpModelError.declined }
                return CatchUpDraft(overview: "The second half.")
            },
            final: { prompt in
                if !lineNumbers(in: prompt).isEmpty { throw CatchUpModelError.declined }
                return [CatchUpDraft(overview: "What's left.")]
            }
        )
        let summary = try await CatchUpEngine(model: model).run(F.request(F.chatter(30)))
        #expect(summary.overview == "What's left.")
        let declined = try #require(model.digestCalls.first { lineNumbers(in: $0.prompt).contains(1) })
        #expect(summary.skippedMessages == lineNumbers(in: declined.prompt).count)
        #expect((1..<30).contains(summary.skippedMessages))
    }

    /// The parts were fine but combining them was declined: the notes that
    /// cover everything become the summary.
    @Test func aDeclinedMergeFallsBackToTheNotes() async throws {
        let model = FakeCatchUpModel(
            context: 2048,
            digest: { prompt in
                CatchUpDraft(overview: prompt.contains("Summaries of consecutive parts") ? "Combined notes." : "A part.")
            },
            final: { _ in throw CatchUpModelError.declined }
        )
        let summary = try await CatchUpEngine(model: model).run(F.request(F.chatter(240)))
        #expect(summary.overview == "Combined notes.")
        #expect(summary.isComplete)
        #expect(summary.skippedMessages == 0)
    }

    @Test func everythingDeclinedFails() async {
        let short = FakeCatchUpModel(
            digest: { _ in throw CatchUpModelError.declined },
            final: { _ in throw CatchUpModelError.declined }
        )
        await #expect(throws: CatchUpError.declined) {
            try await CatchUpEngine(model: short).run(F.request(F.chatter(3)))
        }
        let long = FakeCatchUpModel(
            context: 2048,
            digest: { _ in throw CatchUpModelError.declined },
            final: { _ in [CatchUpDraft(overview: "Never written.")] }
        )
        await #expect(throws: CatchUpError.declined) {
            try await CatchUpEngine(model: long).run(F.request(F.chatter(240)))
        }
        #expect(long.summarizeCalls.isEmpty)
    }

    // MARK: Plain-text replies

    /// The reply streams as text: the overview shows as it's written, each
    /// topic once its line is done, and nothing shown is taken back.
    @Test func aStreamedReplyIsReadAsItArrives() async throws {
        let lines = F.heatedPoliticsLines()
        let reply = """
        **OVERVIEW:** People argued about the minimum wage and voter ID; maple_ asked you about the polls.
        1. TOPIC: 1 | Minimum wage | redfern said a $20 minimum hurts small businesses; bluejay and libby disagreed. | redfern, bluejay, libby
        2. TOPIC: [14] | Voter ID | orwell_fan backed the bill and bluejay called it a solution looking for a problem. | orwell_fan, bluejay
        TOPIC: 999 | Made-up line | Nothing. | konrad
        YOU: maple_ asked whether ID was an issue when you worked the polls.
        """
        // Every few characters, as a model streams.
        let steps = stride(from: 6, to: reply.count, by: 6).map { String(reply.prefix($0)) } + [reply]
        let model = FakeCatchUpModel(context: 8192, finalText: { _ in steps })
        let partials = Recorder<[CatchUpSummary]>([])
        let summary = try await CatchUpEngine(model: model).run(F.request(lines)) { snapshot in
            partials.update { $0.append(snapshot) }
        }

        let snapshots = partials.value
        #expect(!snapshots.isEmpty)
        // Fewer snapshots than steps: a step that reads the same isn't passed on.
        #expect(snapshots.count < steps.count)
        for (earlier, later) in zip(snapshots, snapshots.dropFirst()) {
            #expect(later.overview.hasPrefix(earlier.overview), "\(earlier.overview) → \(later.overview)")
            #expect(later.topics.count >= earlier.topics.count)
            #expect(Array(later.topics.prefix(earlier.topics.count)) == earlier.topics)
        }
        // The overview streamed in pieces before the first topic.
        #expect(snapshots.filter { $0.topics.isEmpty }.count > 3)
        #expect(!snapshots.contains { $0.overview.contains("OVERVIEW") || $0.overview.contains("*") })

        #expect(summary.overview == "People argued about the minimum wage and voter ID; maple_ asked you about the polls.")
        #expect(summary.topics.map(\.title) == ["Minimum wage", "Voter ID", "Made-up line"])
        #expect(summary.topics[0].participants == ["redfern", "bluejay", "libby"])
        #expect(summary.topics[1].summary == "orwell_fan backed the bill and bluejay called it a solution looking for a problem.")
        // Valid line numbers link; one past the transcript doesn't.
        #expect(summary.topics.map(\.firstLineID) == [lines[0].id, lines[13].id, nil])
        #expect(summary.addressedToYou == ["maple_ asked whether ID was an issue when you worked the polls."])
    }

    /// A refusal written out as text, not thrown, counts as declined: the
    /// stretch is read in halves and the half that's refused is skipped.
    @Test func aWrittenRefusalIsDeclined() async throws {
        let model = FakeCatchUpModel(
            digestText: { prompt in
                lineNumbers(in: prompt).contains(1) ? "I'm sorry, but I can't help with that." : "OVERVIEW: The second half.\nTOPIC: 20 | Later | More talk. | bob"
            },
            finalText: { prompt in
                lineNumbers(in: prompt).isEmpty ? ["OVERVIEW: What's left."] : ["I", "I'm sorry, but I can't", "I'm sorry, but I can't summarize this conversation."]
            }
        )
        let partials = Recorder<[CatchUpSummary]>([])
        let summary = try await CatchUpEngine(model: model).run(F.request(F.chatter(30))) { snapshot in
            partials.update { $0.append(snapshot) }
        }
        // The refusal was never shown.
        #expect(!partials.value.contains { $0.overview.localizedCaseInsensitiveContains("sorry") || $0.overview == "I" })
        #expect(summary.overview == "What's left.")
        #expect((1..<30).contains(summary.skippedMessages))
    }

    /// A digest cites only lines in its own part.
    @Test func aDigestCitesOnlyItsOwnLines() async throws {
        let model = FakeCatchUpModel(
            context: 2048,
            digestText: { prompt in
                let numbers = lineNumbers(in: prompt)
                return """
                OVERVIEW: A part.
                TOPIC: \(numbers.first!) | Own line \(numbers.first!) | Fine. | alice
                TOPIC: \(numbers.last! + 1) | Next part's line \(numbers.first!) | Not this part's. | bob
                """
            },
            finalText: { _ in ["OVERVIEW: All of it."] }
        )
        _ = try await CatchUpEngine(model: model).run(F.request(F.chatter(240)))
        let merge = try #require(model.summarizeCalls.last?.prompt)
        let firsts = model.digestCalls.map { lineNumbers(in: $0.prompt).first! }
        #expect(firsts.count > 1)
        for first in firsts {
            #expect(merge.contains("TOPIC: [\(first)] | Own line \(first) | Fine. | alice"))
            #expect(merge.contains("TOPIC: Next part's line \(first) | Not this part's. | bob"))
        }
    }

    /// A reply that runs past the six topics the card shows is stopped
    /// there: what follows is never read.
    @Test func aReplyPastSixTopicsIsStopped() async throws {
        let lines = [F.line("wren", "doug: can you review the PR?")] + F.chatter(29)
        let topics = (1...10).map { "TOPIC: \($0 + 1) | Topic \($0) | Talk. | alice" }
        let reply = (["OVERVIEW: Lots of topics."] + topics + ["YOU: wren asked you to review the PR."]).joined(separator: "\n")
        let steps = reply.split(separator: "\n").indices.map { reply.split(separator: "\n")[...$0].joined(separator: "\n") + "\n" }
        let model = FakeCatchUpModel(finalText: { _ in steps })
        let summary = try await CatchUpEngine(model: model).run(F.request(lines))
        #expect(summary.topics.map(\.title) == (1...6).map { "Topic \($0)" })
        // The model's own note came after the stop: the mention is quoted instead.
        #expect(summary.addressedToYou == ["wren: “can you review the PR?”"])
    }

    /// A digest stops once it's past the four topics a part keeps, as the
    /// schema's limits used to stop it.
    @Test func aDigestPastFourTopicsIsStopped() async throws {
        let model = FakeCatchUpModel(
            context: 2048,
            digestText: { prompt in
                let first = lineNumbers(in: prompt).first ?? 1
                let topics = (0..<8).map { "TOPIC: [\(first + $0)] | Part \(first) topic \($0) | Talk. | alice" }
                return (["OVERVIEW: A part."] + topics + ["YOU: alice asked you something."]).joined(separator: "\n")
            },
            finalText: { _ in ["OVERVIEW: All of it."] }
        )
        _ = try await CatchUpEngine(model: model).run(F.request(F.chatter(240)))
        let merge = try #require(model.summarizeCalls.last?.prompt)
        #expect(merge.contains("topic 3 |"))
        #expect(!merge.contains("topic 4 |"))
        // What came after the stop was never read.
        #expect(!merge.contains("YOU:"))
    }

    @Test func theLimitWatchesAStreamedReply() {
        let limit = CatchUpReplyLimit(nicks: ["alice"], topics: 2)
        let reply = "OVERVIEW: x\nTOPIC: [1] | One\nTOPIC: [2] | Two\nYOU: a\nYOU: b\nYOU: c\nYOU: d\nTOPIC: [3] | Three\n"
        var stops: [Int] = []
        for end in 0...reply.count where limit.isReached(String(reply.prefix(end))) { stops.append(end) }
        // Stopped once a fourth note is done: the two topics were written.
        #expect(stops.first == reply.range(of: "YOU: d\n")!.upperBound.utf16Offset(in: reply))
    }

    /// A reply with no usable text, or nothing at all, is a declined part.
    @Test func anEmptyReplyIsDeclined() async throws {
        let model = FakeCatchUpModel(
            context: 2048,
            digestText: { prompt in lineNumbers(in: prompt).contains(1) ? "   \n" : "OVERVIEW: Fine." },
            finalText: { _ in ["OVERVIEW: The rest."] }
        )
        let summary = try await CatchUpEngine(model: model).run(F.request(F.chatter(240)))
        #expect(summary.overview == "The rest.")
        #expect(summary.skippedMessages > 0)
    }

    // MARK: Errors

    /// The model can't read what people wrote: that's the conversation's
    /// language, not the Mac's, so no System Settings fix is offered.
    @Test func aConversationInAnUnsupportedLanguageSaysSo() async {
        let model = FakeCatchUpModel(final: { _ in throw CatchUpModelError.unsupportedLanguage })
        await #expect(throws: CatchUpError.conversationLanguageUnsupported) {
            try await CatchUpEngine(model: model).run(F.request(F.chatter(3)))
        }
        #expect(CatchUpError.conversationLanguageUnsupported.errorDescription == "This conversation's language isn't supported for summaries yet.")
        #expect(CatchUpModelError.unsupportedLanguage.catchUpError != .unavailable(.unsupportedLanguage))

        let older = LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(.init(debugDescription: "xx"))
        #expect(FoundationModelsCatchUpModel.classify(older) as? CatchUpModelError == .unsupportedLanguage)
        if #available(macOS 27.0, *) {
            let current = LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: "xx", debugDescription: "xx"))
            #expect(FoundationModelsCatchUpModel.classify(current) as? CatchUpModelError == .unsupportedLanguage)
        }
    }

    /// Long stretches make many requests, which Siri runs in the background,
    /// where Apple Intelligence limits them sooner.
    @Test func aRateLimitSaysToTryAgain() async {
        let model = FakeCatchUpModel(
            context: 2048,
            digest: { _ in throw CatchUpModelError.rateLimited },
            final: { _ in throw CatchUpModelError.rateLimited }
        )
        await #expect(throws: CatchUpError.rateLimited) {
            try await CatchUpEngine(model: model).run(F.request(F.chatter(240)))
        }
        #expect(CatchUpError.rateLimited.errorDescription == "Apple Intelligence is busy. Try again in a moment.")
    }

    @Test func foundationModelsRateLimitsAreRecognized() {
        let older = LanguageModelSession.GenerationError.rateLimited(.init(debugDescription: "busy"))
        #expect(FoundationModelsCatchUpModel.classify(older) as? CatchUpModelError == .rateLimited)
        if #available(macOS 27.0, *) {
            let current = LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "busy"))
            #expect(FoundationModelsCatchUpModel.classify(current) as? CatchUpModelError == .rateLimited)
        }
    }

    // MARK: Results

    /// Line numbers that only count the topics (1, 2, 3…) link nowhere;
    /// real ones, and a first topic at line 1, still link.
    @Test func numbersThatCountTopicsAreNotLines() {
        let inRange: (Int) -> Bool = { 1...72 ~= $0 }
        let counted = CatchUpDraft(topics: (1...4).map { .init(title: "T\($0)", firstLine: $0) }).citing(inRange)
        #expect(counted.topics.allSatisfy { $0.firstLine == nil })
        let real = CatchUpDraft(topics: [.init(title: "A", firstLine: 1), .init(title: "B", firstLine: 14), .init(title: "C", firstLine: 99)]).citing(inRange)
        #expect(real.topics.map(\.firstLine) == [1, 14, nil])
        let one = CatchUpDraft(topics: [.init(title: "A", firstLine: 1)]).citing(inRange)
        #expect(one.topics.map(\.firstLine) == [1])
        // Seen in a live merge: 2, 3, 4, 5 for topics that started far apart.
        let offset = CatchUpDraft(topics: (2...5).map { .init(title: "T\($0)", firstLine: $0) }).citing(inRange)
        #expect(offset.topics.allSatisfy { $0.firstLine == nil })
        // Two neighbors that don't start at 1 may be real.
        let pair = CatchUpDraft(topics: [.init(title: "A", firstLine: 7), .init(title: "B", firstLine: 8)]).citing(inRange)
        #expect(pair.topics.map(\.firstLine) == [7, 8])
    }

    @Test func resultsKeepToWhatWasSaid() {
        let lines = [
            F.line("Kenji", "first"),
            F.line("ada", "second"),
            F.line("wren", "third"),
        ]
        let transcript = CatchUpTranscript(lines: lines, ownNick: "doug")
        let draft = CatchUpDraft(
            overview: "  Overview. ",
            topics: [
                // Invented and miscased nicks.
                .init(title: "One", participants: ["kenji", "Mallory", "@ada", "KENJI"], firstLine: 2),
                // A line number that doesn't exist: no link.
                .init(title: "Two", participants: ["wren"], firstLine: 99),
                .init(title: "   ", participants: ["ada"], firstLine: 1),
            ] + (3...9).map { .init(title: "Extra \($0)", firstLine: 1) },
            // Nobody mentioned doug, so these are dropped.
            addressedToYou: ["Someone asked you something."]
        )
        let summary = CatchUpEngine.summary(from: draft, transcript: transcript, isComplete: true)
        #expect(summary.overview == "Overview.")
        #expect(summary.topics.count == 6)
        #expect(summary.topics[0].participants == ["Kenji", "ada"])
        #expect(summary.topics[0].firstLineID == lines[1].id)
        #expect(summary.topics[1].firstLineID == nil)
        #expect(summary.topics.map(\.title).contains("   ") == false)
        #expect(summary.addressedToYou.isEmpty)
        // Topic ids are stable by position, for streaming.
        #expect(summary.topics[0].id == CatchUpEngine.topicID(0))
    }

    @Test func missedMentionsAreQuoted() {
        let transcript = CatchUpTranscript(lines: [
            F.line("wren", "doug: can you review the sidebar rail PR when you get a sec?"),
            F.line("ada", "hi all"),
        ], ownNick: "doug")
        let summary = CatchUpEngine.summary(from: CatchUpDraft(overview: "x"), transcript: transcript, isComplete: true)
        #expect(summary.addressedToYou == ["wren: “can you review the sidebar rail PR when you get a sec?”"])
        // Not while streaming: the model may still write its own.
        let partial = CatchUpEngine.summary(from: CatchUpDraft(overview: "x"), transcript: transcript, isComplete: false)
        #expect(partial.addressedToYou.isEmpty)
    }
}

@Suite("Catch me up mention notes")
struct CatchUpMentionNoteTests {
    typealias F = CatchUpFixtures

    @Test func notesMustNameSomeoneWhoMentionedTheReader() {
        let transcript = CatchUpTranscript(lines: [
            F.line("wren", "doug: can you review the sidebar rail PR?"),
            F.line("nadia", "the release notes draft is up, please add your bits"),
            F.line("doug", "pushed the IRCv3 notes"),
        ], ownNick: "doug")
        let draft = CatchUpDraft(overview: "x", addressedToYou: [
            "wren asked you to review the sidebar rail PR.",
            "nadia asked doug to add to the release notes.",
            "doug: pushed IRCv3 spec notes",
        ])
        let summary = CatchUpEngine.summary(from: draft, transcript: transcript, isComplete: true)
        #expect(summary.addressedToYou == ["wren asked you to review the sidebar rail PR."])
    }

    @Test func whenEveryNoteIsDroppedTheMentionsAreQuoted() {
        let transcript = CatchUpTranscript(lines: [
            F.line("wren", "doug, around?"),
            F.line("nadia", "hello all"),
        ], ownNick: "doug")
        let draft = CatchUpDraft(overview: "x", addressedToYou: ["nadia greeted you."])
        let summary = CatchUpEngine.summary(from: draft, transcript: transcript, isComplete: true)
        #expect(summary.addressedToYou == ["wren: “around?”"])
    }
}

@Suite("Catch me up nick case")
struct CatchUpNickCaseTests {
    typealias F = CatchUpFixtures

    private var transcript: CatchUpTranscript {
        CatchUpTranscript(lines: [F.line("wren", "doug: hi"), F.line("Kenji", "o/"), F.line("ada_", "yo")], ownNick: "doug")
    }

    @Test func nicksKeepTheirWrittenCase() {
        #expect(transcript.restoringNickCase(in: "Wren asked Doug; KENJI and Ada_ agreed.") == "wren asked doug; Kenji and ada_ agreed.")
        // Only whole nicks.
        #expect(transcript.restoringNickCase(in: "Wrenfield and Adam") == "Wrenfield and Adam")
    }

    @Test func notesLoseTheReadersNickUpFront() {
        #expect(CatchUpEngine.cleanNote("doug: Wren asked you to review the PR", transcript: transcript) == "wren asked you to review the PR")
        #expect(CatchUpEngine.cleanNote("  you were asked about the PR ", transcript: transcript) == "You were asked about the PR")
        // A message quoted as written, as the live model writes YOU lines.
        #expect(CatchUpEngine.cleanNote("wren: doug: can you review the PR?", transcript: transcript) == "wren: “can you review the PR?”")
        #expect(CatchUpEngine.cleanNote("Wren: Doug, around?", transcript: transcript) == "wren: “around?”")
        // Not a quote: left as it is.
        #expect(CatchUpEngine.cleanNote("wren: asked about the PR", transcript: transcript) == "wren: asked about the PR")
    }

    @Test func nearRepeatsAreDropped() {
        let draft = CatchUpDraft(overview: "x", addressedToYou: [
            "wren asked you to review the sidebar rail PR",
            "wren asked you to review the sidebar rail PR when you get a sec",
        ])
        let summary = CatchUpEngine.summary(from: draft, transcript: transcript, isComplete: true)
        #expect(summary.addressedToYou == ["wren asked you to review the sidebar rail PR when you get a sec"])
    }
}
