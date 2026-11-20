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
        let topics = try #require(model.summarizeCalls.last?.prompt).split(separator: "\n").filter { $0.hasPrefix("- Part from") }
        #expect(!topics.isEmpty)
        #expect(!topics.contains("- Part from 1"))
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
