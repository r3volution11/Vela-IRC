// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
@testable import VelaIntelligence

/// A Recap window's states: reading, asking for a span, estimating,
/// asking before a long one, running, done, stopped, failed, and More
/// detail.
@Suite("Recap session")
struct RecapSessionTests {
    typealias F = RecapFixtures

    let lines = [
        F.line("kenji", "the theme engine landed", minute: 0),
        F.line("wren", "doug: can you review the PR?", minute: 1),
    ]

    func session(
        input: @escaping (RecapScope) -> RecapInput,
        summarizer: FakeRecapSummarizer,
        status: IntelligenceStatus = .available,
        gathers: Recorder<[RecapScope]>? = nil
    ) -> RecapSession {
        RecapSession(
            scope: RecapScope(place: .buffer(F.id("#vela"))),
            gather: { scope in
                gathers?.update { $0.append(scope) }
                return input(scope)
            },
            summarizer: summarizer,
            status: { status }
        )
    }

    func filled(_ scope: RecapScope) -> RecapInput {
        var input = F.input([F.conversation("#vela", lines)])
        input.scope = scope
        return input
    }

    @Test func readsThenSummarizes() async throws {
        let summarizer = FakeRecapSummarizer()
        summarizer.gate.close()
        let reference = RecapReference(conversation: F.id("#vela"), lineID: lines[0].id, time: lines[0].time)
        summarizer.steps = [
            .summary(RecapSummary(progress: RecapProgress(messagesRead: 1, messagesTotal: 2))),
            .summary(RecapSummary(overview: ["Theme talk."], topics: [RecapTopic(id: "topic-0", title: "Theme", summary: "", participants: ["kenji"], start: reference, lineIDs: [lines[0].id])])),
            // A progress-only snapshot keeps the words shown.
            .summary(RecapSummary(progress: RecapProgress(messagesRead: 2, messagesTotal: 2, isWriting: true))),
        ]
        let session = session(input: filled, summarizer: summarizer)
        #expect(session.phase == .gathering)
        session.start()
        #expect(await eventually { session.summaryPhase == .running })
        #expect(session.phase == .ready)
        #expect(session.findings.forYou.map(\.nick) == ["wren"])
        summarizer.gate.open()
        #expect(await eventually { session.summaryPhase == .done })
        #expect(session.summary?.overview == ["Theme talk."])
        #expect(session.summary?.isComplete == true)
        #expect(session.summary?.progress == nil)
        #expect(summarizer.recaps.value.count == 1)
    }

    @Test func nothingUnreadAsksForASpan() async {
        let empty: (RecapScope) -> RecapInput = { scope in RecapInput(scope: scope, conversations: [], requestedStart: nil, end: F.start) }
        let session = session(input: empty, summarizer: FakeRecapSummarizer())
        session.start()
        #expect(await eventually { session.phase == .needsSpan })
        // Picking a span with nothing in it says so instead.
        session.update(RecapScope(place: .buffer(F.id("#vela")), span: .last(minutes: 30)))
        #expect(await eventually { session.phase == .empty })
    }

    @Test func aLongOneAsksFirst() async {
        let summarizer = FakeRecapSummarizer()
        summarizer.nextPlan = RecapPlan(passes: 12, transcriptTokens: 30_000, estimatedSeconds: 240)
        let session = session(input: filled, summarizer: summarizer)
        session.start()
        #expect(await eventually { if case .confirming = session.summaryPhase { true } else { false } })
        #expect(summarizer.recaps.value.isEmpty)
        session.confirm()
        #expect(await eventually { session.summaryPhase == .done })
        #expect(summarizer.recaps.value.count == 1)
    }

    @Test func stopKeepsWhatWasWritten() async {
        let summarizer = FakeRecapSummarizer()
        summarizer.gate.close()
        let session = session(input: filled, summarizer: summarizer)
        session.start()
        #expect(await eventually { session.summaryPhase == .running })
        session.stop()
        #expect(session.summaryPhase == .stopped)
        #expect(await eventually { summarizer.terminations.value == 1 })
        summarizer.gate.open()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(session.summaryPhase == .stopped)
    }

    @Test func aFailureSaysWhy() async {
        let summarizer = FakeRecapSummarizer()
        summarizer.steps = [.fail(.rateLimited)]
        let session = session(input: filled, summarizer: summarizer)
        session.start()
        #expect(await eventually { session.summaryPhase == .failed(.rateLimited) })
    }

    @Test func withoutAppleIntelligenceTheLogStillWorks() async {
        let summarizer = FakeRecapSummarizer()
        let session = session(input: filled, summarizer: summarizer, status: .turnedOff)
        session.start()
        #expect(await eventually { session.summaryPhase == .unavailable(.turnedOff) })
        #expect(session.phase == .ready)
        var log = session.scope
        log.output = .log
        session.update(log)
        #expect(session.phase == .ready)
        #expect(session.input?.lineCount == 2)
        #expect(summarizer.recaps.value.isEmpty)
    }

    @Test func switchingOutputDoesntReadAgainButScopeDoes() async {
        let summarizer = FakeRecapSummarizer()
        let gathers = Recorder<[RecapScope]>([])
        let session = RecapSession(
            scope: RecapScope(place: .buffer(F.id("#vela")), output: .log),
            gather: { scope in
                gathers.update { $0.append(scope) }
                return self.filled(scope)
            },
            summarizer: summarizer,
            status: { .available }
        )
        session.start()
        #expect(await eventually { session.phase == .ready })
        // A log asks nothing of Apple Intelligence.
        #expect(session.summaryPhase == .idle)
        var summary = session.scope
        summary.output = .summary
        session.update(summary)
        #expect(await eventually { session.summaryPhase == .done })
        #expect(gathers.value.count == 1)
        var wider = session.scope
        wider.place = .network(F.network)
        session.update(wider)
        #expect(await eventually { gathers.value.count == 2 && session.summaryPhase == .done })
        #expect(gathers.value.last?.place == .network(F.network))
        #expect(summarizer.recaps.value.count == 2)
    }

    @Test func moreDetailReadsTheTopicsLines() async throws {
        let summarizer = FakeRecapSummarizer()
        let reference = RecapReference(conversation: F.id("#vela"), lineID: lines[0].id, time: lines[0].time)
        let topic = RecapTopic(id: "topic-0", title: "Theme", summary: "", participants: ["kenji"], start: reference, lineIDs: [lines[0].id])
        summarizer.steps = [.summary(RecapSummary(overview: ["x"], topics: [topic], isComplete: true))]
        let session = session(input: filled, summarizer: summarizer)
        session.start()
        #expect(await eventually { session.summaryPhase == .done })
        session.moreDetail(on: topic)
        #expect(await eventually { if case .done = session.details[topic.id] { true } else { false } })
        let request = try #require(summarizer.details.value.first)
        #expect(request.lines.map(\.id) == [lines[0].id])
        #expect(request.focus == "Theme")
        #expect(request.ownNick == "doug")
        #expect(session.details[topic.id]?.detail?.points == summarizer.detailPoints)
        session.clearDetail(topic.id)
        #expect(session.details[topic.id] == nil)

        // A note gets the messages around it.
        let note = RecapNote(id: "n", kind: .decision, text: "Palenight.", reference: RecapReference(conversation: F.id("#vela"), lineID: lines[1].id, time: lines[1].time))
        session.moreDetail(on: note)
        #expect(await eventually { summarizer.details.value.count == 2 })
        #expect(summarizer.details.value[1].lines.map(\.id) == lines.map(\.id))
    }

    @Test func moreDetailWaitsForTheRecap() async {
        let summarizer = FakeRecapSummarizer()
        summarizer.gate.close()
        let session = session(input: filled, summarizer: summarizer)
        session.start()
        #expect(await eventually { session.summaryPhase == .running })
        let topic = RecapTopic(id: "t", title: "T", summary: "", participants: [], start: nil, lineIDs: [lines[0].id])
        session.moreDetail(on: topic)
        #expect(session.details.isEmpty)
        summarizer.gate.open()
    }

    @Test func closingStopsEverything() async {
        let summarizer = FakeRecapSummarizer()
        summarizer.gate.close()
        let session = session(input: filled, summarizer: summarizer)
        session.start()
        #expect(await eventually { session.summaryPhase == .running })
        session.close()
        #expect(await eventually { summarizer.terminations.value == 1 })
        session.update(RecapScope(place: .everywhere))
        #expect(session.scope.place == .buffer(F.id("#vela")))
        summarizer.gate.open()
    }

    @Test func cannedRecapForTheDemo() async throws {
        let app = AppModel.demo()
        await app.ready()
        let libera = try #require(app.sessions.first { $0.displayName == "Libera.Chat" })
        let input = await RecapGatherer(app: app).gather(RecapScope(place: .network(libera.id), span: .last(minutes: 240)))
        let summary = try CannedSummarizer.recapSummary(for: input)
        #expect(!summary.overview.isEmpty)
        #expect(summary.topics.count <= RecapPrompts.maximumTopics)
        #expect(summary.topics.allSatisfy { !$0.lineIDs.isEmpty && $0.start != nil })
        #expect(!summary.notes(.decision).isEmpty)
        #expect(!summary.notes(.followUp).isEmpty)
        let findings = RecapFindings(input)
        #expect(findings.forYou.contains { $0.nick == "wren" })
        #expect(findings.forYou.contains { $0.isPrivate && $0.nick == "marisol" })
        #expect(!findings.links.isEmpty)
        #expect(summary.notesForYou.count == 2)
    }
}
