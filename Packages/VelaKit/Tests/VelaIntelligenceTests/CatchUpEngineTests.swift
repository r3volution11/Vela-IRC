// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
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

    @Test func instructionsNameTheReaderAndTheRules() {
        let instructions = CatchUpPrompts.instructions(ownNick: "doug", pass: .single)
        #expect(instructions.contains("“doug”"))
        #expect(instructions.contains("Never invent"))
        #expect(instructions.contains("exactly as they appear"))
        #expect(instructions.contains("at most two sentences"))
        #expect(instructions.contains("at most 6 topics"))
        // The transcript never goes in the instructions.
        #expect(!instructions.contains("[1]"))
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
            final: { _ in [CatchUpDraft(overview: "Release planning.", topics: [.init(title: "Release", participants: ["bob"], firstLine: 2)])] }
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
        #expect(merge.contains("Part 1 (lines 1–\(digests[0].last!))"))
        #expect(merge.contains("[line 1] Part from 1"))
        #expect(summary.overview == "Release planning.")
        #expect(summary.topics.first?.firstLineID == lines[1].id)
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

    // MARK: Errors

    @Test func guardrailsBecomeDeclined() async {
        let model = FakeCatchUpModel(final: { _ in throw CatchUpModelError.declined })
        await #expect(throws: CatchUpError.declined) {
            try await CatchUpEngine(model: model).run(F.request(F.chatter(3)))
        }
    }

    @Test func anUnsupportedLanguageIsReportedAsUnavailable() async {
        let model = FakeCatchUpModel(final: { _ in throw CatchUpModelError.unsupportedLanguage })
        await #expect(throws: CatchUpError.unavailable(.unsupportedLanguage)) {
            try await CatchUpEngine(model: model).run(F.request(F.chatter(3)))
        }
    }

    // MARK: Results

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
                // A line number that doesn't exist: falls back to the first participant's line.
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
        #expect(summary.topics[1].firstLineID == lines[2].id)
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
