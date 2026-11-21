// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization

/// Writes a Recap with a language model, on Catch me up's model protocol
/// (``CatchUpLanguageModel``), budgets and chunking:
///
/// 1. **One pass** when the whole transcript fits one request, streamed.
/// 2. Otherwise **map**: the transcript is read in parts that fit (never
///    more than the model's context), each part's reply giving its topics
///    with the lines they cover, its decisions, open questions and
///    follow-ups, and notes on messages that named the reader, all tied to
///    line numbers. Each part's findings show as soon as it's read.
/// 3. Then **reduce**: the parts' overviews and topics (numbered T1, T2…)
///    are combined into the report's overview and topics, streamed. A
///    merged topic names the parts' topics it combines, so it keeps their
///    lines: what its jump link and More detail use. Decisions, questions,
///    follow-ups and notes for you are combined on this Mac, without
///    another request.
///
/// A part the model declines is left out (the report says how many
/// messages), and one too long is read in halves. Nothing here names a
/// channel, network or person: see ``RecapPrompts``.
nonisolated struct RecapEngine: Sendable {
    let model: any CatchUpLanguageModel
    var venue: CatchUpVenue = .onDevice
    var cloudFallback: CatchUpCloudFallback?
    var timings = RecapTimings()

    // MARK: Measuring

    /// A transcript sized up for this engine's model.
    struct Measurement: Sendable {
        let transcript: RecapTranscript
        /// Each entry's tokens, with its line break (and a conversation
        /// heading before it, where there is one).
        let costs: [Int]
        let singleBudget: CatchUpBudget
        let partBudget: CatchUpBudget

        var totalTokens: Int { costs.reduce(0, +) }
        var fitsOnePass: Bool { totalTokens <= singleBudget.transcriptTokens }

        /// Parts it's read in (1 when one request holds it).
        var parts: Int {
            fitsOnePass ? 1 : max(2, CatchUpChunker.chunks(costs, budget: partBudget.transcriptTokens) { $0 }.count)
        }

        /// Requests: the parts, plus combining them (one merge per eight
        /// parts or so, and the last).
        var passes: Int {
            fitsOnePass ? 1 : parts + max(1, Int((Double(parts) / 8).rounded(.up)))
        }
    }

    func measure(_ transcript: RecapTranscript) async -> Measurement {
        Measurement(
            transcript: transcript,
            costs: await lineCosts(transcript),
            singleBudget: await budget(for: .single, ownNick: transcript.ownNick),
            partBudget: await budget(for: .part, ownNick: transcript.ownNick)
        )
    }

    /// How `input` would be summarized here, and about how long it takes.
    func plan(_ input: RecapInput, measured: Measurement? = nil) async -> RecapPlan {
        let measurement = if let measured { measured } else { await measure(RecapTranscript(input)) }
        return RecapPlan(
            passes: measurement.passes,
            transcriptTokens: measurement.totalTokens,
            estimatedSeconds: timings.estimatedSeconds(passes: measurement.passes, venue: venue),
            venue: venue
        )
    }

    // MARK: Running

    /// The Recap of `input`, calling `progress` with each snapshot.
    /// Throws ``CatchUpError``s (or `CancellationError`); a Private Cloud
    /// Compute model's ``CatchUpModelError/cloudUnavailable(_:)`` comes
    /// through as it is, for ``RecapRouter``.
    func run(
        _ input: RecapInput,
        measured: Measurement? = nil,
        progress: @escaping @Sendable (RecapSummary) -> Void = { _ in }
    ) async throws -> RecapSummary {
        let transcript = measured?.transcript ?? RecapTranscript(input)
        guard !transcript.isEmpty else { throw CatchUpError.nothingToSummarize }
        let measurement = if let measured { measured } else { await measure(transcript) }
        let reporter = RecapReporter(
            transcript: transcript,
            venue: venue,
            cloudFallback: cloudFallback,
            timings: timings,
            send: progress
        )
        do {
            return try await summarize(measurement, reporter: reporter)
        } catch let error as CatchUpModelError {
            if case .cloudUnavailable = error { throw error }
            throw error.catchUpError
        }
    }

    private func summarize(_ measurement: Measurement, reporter: RecapReporter) async throws -> RecapSummary {
        let transcript = measurement.transcript
        var partTokens = measurement.partBudget.transcriptTokens
        if measurement.fitsOnePass {
            reporter.plan(passes: 1, messages: transcript.entries.count)
            do {
                return try await single(transcript, reporter: reporter)
            } catch CatchUpModelError.contextExceeded {
                partTokens = measurement.partBudget.shrunk(by: 0.6).transcriptTokens
            } catch CatchUpModelError.declined where transcript.entries.count > 1 {
                // Something in it trips the guardrails: read it in halves,
                // so only the half that does is left out.
                partTokens = min(partTokens, max(1, (measurement.totalTokens + 1) / 2))
            }
        }

        try Task.checkCancellation()
        let pieces = CatchUpChunker.balanced(Array(zip(transcript.entries, measurement.costs)), budget: partTokens) { $0.1 }
        reporter.plan(passes: pieces.count + max(1, Int((Double(pieces.count) / 8).rounded(.up))), messages: transcript.entries.count, restart: true)
        var parts: [RecapMergePart] = []
        for piece in pieces {
            parts += try await part(piece.map(\.0)[...], of: transcript, reporter: reporter)
        }
        guard !parts.isEmpty else { throw CatchUpModelError.declined }
        return try await merge(parts, transcript: transcript, reporter: reporter)
    }

    // MARK: One pass

    private func single(_ transcript: RecapTranscript, reporter: RecapReporter) async throws -> RecapSummary {
        let all = 1...transcript.entries.count
        var reply: String?
        var reader = RecapReply.Reader(nicks: transcript.nicks)
        var shown: RecapDraft?
        let started = ContinuousClock.now
        let replies = model.summarize(
            prompt: RecapPrompts.single(transcript),
            instructions: RecapPrompts.instructions(ownNick: transcript.ownNick, pass: .single),
            maximumResponseTokens: RecapPrompts.responseTokens(for: .single)
        )
        for try await text in replies {
            try Task.checkCancellation()
            reply = text
            let draft = reader.read(text, isComplete: false)
            guard draft != shown else { continue }
            shown = draft
            reporter.wroteSingle(draft, covering: all)
        }
        try Task.checkCancellation()
        guard let reply else { throw CatchUpModelError.failed("Apple Intelligence didn't return a recap.") }
        let draft = RecapReply.parse(reply, nicks: transcript.nicks)
        guard !RecapReply.isDeclined(draft) else { throw CatchUpModelError.declined }
        reporter.passDone(since: started)
        return reporter.finishSingle(draft, covering: all)
    }

    // MARK: Map

    /// One part's notes, in halves (and again) when it didn't fit. A part
    /// the model declines is left out.
    private func part(
        _ entries: ArraySlice<CatchUpTranscript.Entry>,
        of transcript: RecapTranscript,
        reporter: RecapReporter
    ) async throws -> [RecapMergePart] {
        try Task.checkCancellation()
        guard let first = entries.first?.number, let last = entries.last?.number else { return [] }
        let started = ContinuousClock.now
        do {
            let reply = try await model.digest(
                prompt: RecapPrompts.part(entries, of: transcript),
                instructions: RecapPrompts.instructions(ownNick: transcript.ownNick, pass: .part),
                maximumResponseTokens: RecapPrompts.responseTokens(for: .part),
                until: RecapReplyLimit(nicks: transcript.nicks, topics: RecapPrompts.maximumPartTopics, notes: RecapPrompts.maximumPartNotes).isReached
            )
            let draft = RecapReply.parse(reply, nicks: transcript.nicks)
            guard !RecapReply.isDeclined(draft) else { throw CatchUpModelError.declined }
            reporter.passDone(since: started)
            return [reporter.read(draft, covering: first...last)]
        } catch CatchUpModelError.contextExceeded where entries.count > 1 {
            reporter.plan(passes: 1)
            let middle = entries.startIndex + entries.count / 2
            let left = try await part(entries[..<middle], of: transcript, reporter: reporter)
            let right = try await part(entries[middle...], of: transcript, reporter: reporter)
            return left + right
        } catch CatchUpModelError.declined {
            reporter.skipped(entries.count)
            return []
        }
    }

    // MARK: Reduce

    /// Combines the parts' overviews and topics into the report's.
    private func merge(_ parts: [RecapMergePart], transcript: RecapTranscript, reporter: RecapReporter) async throws -> RecapSummary {
        guard parts.count > 1 else { return reporter.finish(using: parts[0]) }
        let budget = await budget(for: .merge, ownNick: transcript.ownNick)
        var level = parts
        while level.count > 1, await cost(of: RecapPrompts.merge(RecapMergePart.numbered(level), transcript: transcript)) > budget.transcriptTokens {
            level = try await mergeNeighbors(level, budget: budget, transcript: transcript, reporter: reporter)
        }
        guard level.count > 1 else { return reporter.finish(using: level[0]) }
        let numbered = RecapMergePart.numbered(level)
        do {
            return try await streamMerge(numbered, transcript: transcript, reporter: reporter)
        } catch CatchUpModelError.contextExceeded {
            let fewer = try await mergeNeighbors(level, budget: budget.shrunk(by: 0.5), transcript: transcript, reporter: reporter)
            return try await merge(fewer, transcript: transcript, reporter: reporter)
        } catch CatchUpModelError.declined {
            // The parts' own topics and overviews stand in for the report's.
            return reporter.finishUnmerged(level)
        }
    }

    private func streamMerge(_ parts: [RecapMergePart], transcript: RecapTranscript, reporter: RecapReporter) async throws -> RecapSummary {
        reporter.writing()
        var reply: String?
        var reader = RecapReply.Reader(nicks: transcript.nicks)
        var shown: RecapDraft?
        let replies = model.summarize(
            prompt: RecapPrompts.merge(parts, transcript: transcript),
            instructions: RecapPrompts.instructions(ownNick: transcript.ownNick, pass: .merge),
            maximumResponseTokens: RecapPrompts.responseTokens(for: .merge)
        )
        for try await text in replies {
            try Task.checkCancellation()
            reply = text
            let draft = reader.read(text, isComplete: false)
            guard draft != shown, !draft.overview.isEmpty || !draft.topics.isEmpty else { continue }
            shown = draft
            reporter.wroteMerge(draft, parts: parts)
        }
        try Task.checkCancellation()
        guard let reply else { throw CatchUpModelError.failed("Apple Intelligence didn't return a recap.") }
        let draft = RecapReply.parse(reply, nicks: transcript.nicks)
        guard !draft.topics.isEmpty || !draft.overview.isEmpty else { throw CatchUpModelError.declined }
        return reporter.finishMerge(draft, parts: parts)
    }

    /// One reduce level: neighbors that fit together are combined into
    /// one part each. Always shrinks the list.
    private func mergeNeighbors(
        _ parts: [RecapMergePart],
        budget: CatchUpBudget,
        transcript: RecapTranscript,
        reporter: RecapReporter
    ) async throws -> [RecapMergePart] {
        var costs: [Int] = []
        for part in RecapMergePart.numbered(parts) {
            costs.append(await cost(of: RecapPrompts.render(part, transcript: transcript)))
        }
        var groups = CatchUpChunker.chunks(Array(parts.indices), budget: budget.transcriptTokens) { costs[$0] }
        if groups.count >= parts.count {
            groups = stride(from: 0, to: parts.count, by: 2).map { Array(parts.indices)[$0..<min($0 + 2, parts.count)] }
        }
        var merged: [RecapMergePart] = []
        for group in groups {
            try Task.checkCancellation()
            let members = RecapMergePart.numbered(group.map { parts[$0] })
            guard members.count > 1, let first = members.first, let last = members.last else {
                merged += members
                continue
            }
            let started = ContinuousClock.now
            do {
                let reply = try await model.digest(
                    prompt: RecapPrompts.merge(members, transcript: transcript),
                    instructions: RecapPrompts.instructions(ownNick: transcript.ownNick, pass: .merge),
                    maximumResponseTokens: RecapPrompts.responseTokens(for: .part),
                    until: RecapReplyLimit(nicks: transcript.nicks, topics: RecapPrompts.maximumTopics, notes: RecapPrompts.maximumPartNotes).isReached
                )
                let draft = RecapReply.parse(reply, nicks: transcript.nicks)
                reporter.passDone(since: started)
                guard !draft.topics.isEmpty else {
                    merged += members
                    continue
                }
                merged.append(RecapMergePart(
                    lines: first.lines.lowerBound...last.lines.upperBound,
                    overview: Array(draft.overview.prefix(2)),
                    topics: reporter.mergedTopics(draft, parts: members),
                    summarizedLines: members.reduce(0) { $0 + $1.summarizedLines }
                ))
            } catch CatchUpModelError.declined {
                // Keep the group as it was, only shorter: one overview line
                // and its longest topics each.
                merged.append(contentsOf: members.map { member in
                    var copy = member
                    copy.overview = Array(copy.overview.prefix(1))
                    copy.topics = Array(copy.topics.prefix(3))
                    return copy
                })
            }
        }
        // Make sure each level shrinks, so the loop above ends.
        if merged.count >= parts.count, parts.count > 1 {
            return [RecapMergePart(
                lines: parts[0].lines.lowerBound...parts[parts.count - 1].lines.upperBound,
                overview: Array(parts.flatMap(\.overview).prefix(RecapPrompts.maximumOverview)),
                topics: Array(parts.flatMap(\.topics).prefix(RecapPrompts.maximumTopics)),
                summarizedLines: parts.reduce(0) { $0 + $1.summarizedLines }
            )]
        }
        return merged
    }

    // MARK: More detail

    /// A closer look at the messages behind one topic or note, streamed to
    /// `progress`. Reads as many of them as one request holds, oldest first.
    func detail(
        _ request: RecapDetailRequest,
        progress: @escaping @Sendable (RecapDetail) -> Void = { _ in }
    ) async throws -> RecapDetail {
        let lines = request.lines.map { CatchUpLine(id: $0.id, time: $0.time, nick: $0.nick, text: $0.text, isAction: $0.isAction) }
        var transcript = CatchUpTranscript(lines: lines, ownNick: request.ownNick, maximumLines: .max)
        guard !transcript.isEmpty else { throw CatchUpError.nothingToSummarize }
        let budget = await budget(for: .detail, ownNick: request.ownNick)
        let room = budget.transcriptTokens - CatchUpChunker.estimatedTokens(request.focus)
        let estimates = transcript.entries.map { CatchUpChunker.estimatedTokens($0.text) + 1 }
        if estimates.reduce(0, +) > room {
            // Too many for one request: the oldest that fit.
            var used = 0
            var keep = Set<UUID>()
            for (entry, cost) in zip(transcript.entries, estimates) {
                used += cost
                if used > room, !keep.isEmpty { break }
                keep.insert(entry.lineID)
            }
            transcript = CatchUpTranscript(lines: lines.filter { keep.contains($0.id) }, ownNick: request.ownNick, maximumLines: .max)
        }
        do {
            var reader = RecapReply.Reader(nicks: transcript.nicks, bulletsArePoints: true)
            var reply: String?
            var shown: [String] = []
            let replies = model.summarize(
                prompt: RecapPrompts.detail(transcript, focus: request.focus),
                instructions: RecapPrompts.instructions(ownNick: request.ownNick, pass: .detail),
                maximumResponseTokens: RecapPrompts.responseTokens(for: .detail)
            )
            for try await text in replies {
                try Task.checkCancellation()
                reply = text
                let points = Self.points(reader.read(text, isComplete: false), transcript: transcript)
                guard points != shown else { continue }
                shown = points
                progress(RecapDetail(points: points))
                if points.count >= RecapPrompts.maximumPoints { break }
            }
            try Task.checkCancellation()
            let points = Self.points(RecapReply.parse(reply ?? "", nicks: transcript.nicks, bulletsArePoints: true), transcript: transcript)
            guard !points.isEmpty else { throw CatchUpModelError.declined }
            return RecapDetail(points: points, isComplete: true)
        } catch let error as CatchUpModelError {
            throw error.catchUpError
        }
    }

    private static func points(_ draft: RecapDraft, transcript: CatchUpTranscript) -> [String] {
        var seen = Set<String>()
        let points = (draft.points + draft.overview).map { transcript.restoringNickCase(in: $0) }
        return Array(points.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(RecapPrompts.maximumPoints))
    }

    // MARK: Budgets

    private func budget(for pass: RecapPrompts.Pass, ownNick: String) async -> CatchUpBudget {
        CatchUpBudget(
            contextSize: await model.contextSize(),
            instructionTokens: await cost(of: RecapPrompts.instructions(ownNick: ownNick, pass: pass)),
            responseTokens: RecapPrompts.responseTokens(for: pass)
        )
    }

    private func cost(of text: String) async -> Int {
        await model.tokenCount(text) ?? CatchUpChunker.estimatedTokens(text)
    }

    /// Each line's tokens, calibrated by one count of the whole transcript
    /// where the system can count. A conversation's heading adds a few.
    private func lineCosts(_ transcript: RecapTranscript) async -> [Int] {
        let estimates = transcript.entries.map { entry in
            CatchUpChunker.estimatedTokens(entry.text) + 1 + (transcript.startsConversation(entry.number) ? 6 : 0)
        }
        guard !estimates.isEmpty, let counted = await model.tokenCount(transcript.text(of: transcript.entries[...])) else { return estimates }
        let ratio = Double(counted) / Double(max(1, estimates.reduce(0, +)))
        return estimates.map { Int((Double($0) * ratio * 1.08).rounded(.up)) }
    }
}

// MARK: - Timings

/// How long one request to the model takes, measured this session, so a
/// Recap can say about how long it will take ("About 2 minutes on this
/// Mac") and how long is left.
nonisolated public final class RecapTimings: Sendable {
    /// Before anything's measured: a part of about 2,500 tokens and its
    /// notes. Measured at about 9.5 seconds on an M5 Pro (288 lines on a
    /// 4,096-token context: 3 parts and a merge in 38 seconds); a base M1
    /// takes two to three times as long. Errs long; the first part read
    /// corrects it.
    static let defaultOnDeviceSeconds = 25.0
    /// Private Cloud Compute reads more at once, and quicker.
    static let defaultCloudSeconds = 12.0

    private let state = Mutex<[CatchUpVenue: Double]>([:])

    public init() {}

    func secondsPerPass(_ venue: CatchUpVenue) -> Double {
        state.withLock { $0[venue] } ?? (venue == .onDevice ? Self.defaultOnDeviceSeconds : Self.defaultCloudSeconds)
    }

    func estimatedSeconds(passes: Int, venue: CatchUpVenue) -> Double {
        secondsPerPass(venue) * Double(max(1, passes))
    }

    /// One request took `seconds`; averaged in, weighted to the latest.
    func record(_ seconds: Double, venue: CatchUpVenue) {
        guard seconds > 0 else { return }
        state.withLock { state in
            state[venue] = state[venue].map { ($0 + seconds) / 2 } ?? seconds
        }
    }
}

// MARK: - Reporting

/// What one run tells the window: progress, each part's findings as it's
/// read, then the report as it's written. Used by one run, from one task.
nonisolated private final class RecapReporter {
    private let transcript: RecapTranscript
    private let venue: CatchUpVenue
    private let cloudFallback: CatchUpCloudFallback?
    private let timings: RecapTimings
    private let send: @Sendable (RecapSummary) -> Void

    private var parts: [RecapMergePart] = []
    private var notes: [RecapNote] = []
    private var notesForYou: [UUID: String] = [:]
    private var messagesTotal = 0
    private var messagesRead = 0
    private var skippedMessages = 0
    private var passesPlanned = 0
    private var passesDone = 0
    private var isWriting = false
    /// The latest report snapshot with words in it.
    private var shown = RecapSummary()

    init(
        transcript: RecapTranscript,
        venue: CatchUpVenue,
        cloudFallback: CatchUpCloudFallback?,
        timings: RecapTimings,
        send: @escaping @Sendable (RecapSummary) -> Void
    ) {
        self.transcript = transcript
        self.venue = venue
        self.cloudFallback = cloudFallback
        self.timings = timings
        self.send = send
    }

    // MARK: Progress

    func plan(passes: Int, messages: Int? = nil, restart: Bool = false) {
        if restart { passesPlanned = 0 }
        passesPlanned += passes
        if let messages { messagesTotal = messages }
        report()
    }

    func passDone(since start: ContinuousClock.Instant) {
        passesDone += 1
        let elapsed = ContinuousClock.now - start
        timings.record(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, venue: venue)
    }

    func skipped(_ messages: Int) {
        skippedMessages += messages
        messagesRead += messages
        report()
    }

    func writing() {
        isWriting = true
        report()
    }

    private var progress: RecapProgress {
        let left = max(0, passesPlanned - passesDone)
        return RecapProgress(
            messagesRead: min(messagesRead, messagesTotal),
            messagesTotal: messagesTotal,
            isWriting: isWriting,
            secondsLeft: left > 0 ? timings.estimatedSeconds(passes: left, venue: venue) : nil
        )
    }

    private func report() {
        var snapshot = shown
        snapshot.progress = progress
        stamp(&snapshot)
        send(snapshot)
    }

    private func stamp(_ summary: inout RecapSummary) {
        summary.messageCount = transcript.entries.count
        summary.skippedMessages = skippedMessages
        summary.venue = venue
        summary.cloudFallback = cloudFallback
        summary.notes = Self.limited(notes)
        summary.notesForYou = notesForYou
    }

    // MARK: One pass

    func wroteSingle(_ draft: RecapDraft, covering lines: ClosedRange<Int>) {
        absorbNotes(draft, covering: lines)
        var summary = RecapSummary(
            overview: overview(draft.overview),
            topics: topics(from: partTopics(draft, covering: lines))
        )
        guard summary.hasContent || !notes.isEmpty else { return }
        messagesRead = lines.count
        isWriting = true
        summary.progress = progress
        shown = summary
        stamp(&summary)
        send(summary)
    }

    func finishSingle(_ draft: RecapDraft, covering lines: ClosedRange<Int>) -> RecapSummary {
        notes = []
        notesForYou = [:]
        absorbNotes(draft, covering: lines)
        var summary = RecapSummary(
            overview: overview(draft.overview),
            topics: topics(from: partTopics(draft, covering: lines)),
            isComplete: true
        )
        stamp(&summary)
        return summary
    }

    // MARK: Parts

    /// A part's reply: its notes are kept, its topics shown for now.
    func read(_ draft: RecapDraft, covering lines: ClosedRange<Int>) -> RecapMergePart {
        absorbNotes(draft, covering: lines)
        let part = RecapMergePart(
            lines: lines,
            overview: overview(draft.overview),
            topics: partTopics(draft, covering: lines),
            summarizedLines: lines.count
        )
        parts.append(part)
        messagesRead += lines.count
        var summary = shown
        summary.topics = topics(from: parts.flatMap(\.topics), limit: 40)
        summary.topicsAreProvisional = true
        shown = summary
        report()
        return part
    }

    /// The topics of a part's reply, each with the lines it covers: from
    /// its first line to its last, or to where the next topic starts when
    /// the reply gave only one; never past the part, or out of the
    /// conversation it starts in.
    private func partTopics(_ draft: RecapDraft, covering part: ClosedRange<Int>) -> [RecapMergePart.Topic] {
        let starts = draft.topics.compactMap { $0.lines?.lowerBound }.filter { part.contains($0) }.sorted()
        return draft.topics.prefix(RecapPrompts.maximumTopics).map { topic in
            var ranges: [ClosedRange<Int>] = []
            if let lines = topic.lines, part.contains(lines.lowerBound) {
                var upper = min(lines.upperBound, part.upperBound)
                if lines.count == 1 {
                    let next = starts.first { $0 > lines.lowerBound }
                    upper = (next.map { $0 - 1 } ?? part.upperBound)
                }
                if let range = transcript.withinConversation(lines.lowerBound...max(lines.lowerBound, upper)) {
                    ranges = [range]
                }
            }
            return RecapMergePart.Topic(
                title: topic.title,
                summary: transcript.base.restoringNickCase(in: topic.summary),
                participants: participants(topic.participants, in: ranges),
                ranges: ranges
            )
        }
    }

    /// The nicks a topic names that spoke (as they wrote them), or those
    /// who spoke most in its lines when it names none.
    private func participants(_ named: [String], in ranges: [ClosedRange<Int>]) -> [String] {
        var seen = Set<String>()
        var nicks = named.compactMap(transcript.base.canonicalNick).filter { seen.insert($0.lowercased()).inserted }
        if nicks.isEmpty {
            var counts: [String: Int] = [:]
            for range in ranges {
                for number in range { counts[transcript.entries[number - 1].nick, default: 0] += 1 }
            }
            nicks = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key).prefix(3).map { $0 }
        }
        return Array(nicks.prefix(RecapPrompts.maximumParticipants))
    }

    /// Decisions, questions, follow-ups and notes for you from a part,
    /// with their lines checked against it.
    private func absorbNotes(_ draft: RecapDraft, covering part: ClosedRange<Int>) {
        var counts: [RecapNote.Kind: Int] = [:]
        for note in draft.notes {
            guard counts[note.kind, default: 0] < RecapPrompts.maximumPartNotes else { continue }
            counts[note.kind, default: 0] += 1
            let line = note.line.flatMap { part.contains($0) ? $0 : nil }
            let text = transcript.base.restoringNickCase(in: note.text)
            let owner = note.owner.flatMap(transcript.base.canonicalNick)
            let candidate = RecapNote(
                id: "\(note.kind.rawValue)-\(line.map(String.init) ?? "\(part.lowerBound)-\(notes.count)")",
                kind: note.kind,
                text: text,
                owner: owner,
                reference: line.flatMap(transcript.reference)
            )
            if !Self.isRepeat(candidate, of: notes) { notes.append(candidate) }
        }
        for you in draft.you {
            guard let number = youLine(you, in: part), let reference = transcript.reference(number),
                  notesForYou[reference.lineID] == nil
            else { continue }
            let entry = transcript.entries[number - 1]
            // The model mixes up who asked whom ("doug asked to review…"):
            // a note that starts with the reader, or doesn't say "you", is
            // left out, and the window quotes the message instead.
            let own = transcript.ownNick.lowercased()
            let raw = you.text.lowercased()
            guard own.isEmpty || !raw.hasPrefix(own), CatchUpTranscript.containsWord("you", in: raw) || CatchUpTranscript.containsWord("your", in: raw) else { continue }
            var text = RecapEngine.cleanYouNote(transcript.base.restoringNickCase(in: you.text), ownNick: transcript.ownNick)
            // Their message copied out: the window quotes it itself.
            let words = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .“”\""))
            guard !words.isEmpty, !entry.message.lowercased().contains(words) else { continue }
            if !text.lowercased().hasPrefix(entry.nick.lowercased()) { text = "\(entry.nick) \(text.prefix(1).lowercased() + text.dropFirst())" }
            notesForYou[reference.lineID] = text
        }
    }

    /// The line a note for you is about: the one it cites, when someone
    /// else's line there names the reader, or else the first line in the
    /// part by the nick it names that does.
    private func youLine(_ note: RecapDraft.YouNote, in part: ClosedRange<Int>) -> Int? {
        let own = transcript.ownNick.lowercased()
        func names(_ number: Int) -> Bool {
            let entry = transcript.entries[number - 1]
            return entry.nick.lowercased() != own && CatchUpTranscript.containsWord(own, in: entry.message.lowercased())
        }
        if let line = note.line, part.contains(line), names(line) { return line }
        let nick = note.nick?.lowercased() ?? note.text.split(separator: " ").first.map { $0.lowercased() }
        return part.first { number in
            names(number) && (nick == nil || transcript.entries[number - 1].nick.lowercased() == nick)
        }
    }

    // MARK: Merging

    func wroteMerge(_ draft: RecapDraft, parts: [RecapMergePart]) {
        var summary = shown
        summary.overview = overview(draft.overview)
        if !draft.topics.isEmpty {
            summary.topics = topics(from: mergedTopics(draft, parts: parts))
            summary.topicsAreProvisional = false
        }
        shown = summary
        isWriting = true
        report()
    }

    func finishMerge(_ draft: RecapDraft, parts: [RecapMergePart]) -> RecapSummary {
        var merged = mergedTopics(draft, parts: parts).filter { !$0.ranges.isEmpty || !$0.summary.isEmpty }
        // A merge that kept few of the parts' topics (or named none of
        // them) is filled in with the rest, so nothing big goes missing.
        let partTopics = parts.flatMap(\.topics)
        if merged.count < min(4, partTopics.count) {
            let referenced = Set(draft.topics.flatMap(\.parts))
            let rest = partTopics.filter { topic in
                !referenced.contains(topic.reference) && !merged.contains { Self.overlap($0.title, topic.title) >= 0.5 }
            }
            merged += rest.prefix(RecapPrompts.maximumTopics - merged.count)
            merged.sort { ($0.firstLine ?? .max) < ($1.firstLine ?? .max) }
        }
        var overview = overview(draft.overview)
        if overview.isEmpty { overview = self.overview(parts.compactMap(\.overview.first)) }
        var summary = RecapSummary(overview: overview, topics: topics(from: merged), isComplete: true)
        stamp(&summary)
        summary.progress = nil
        return summary
    }

    /// Only one part was read (or the rest were declined): it's the report.
    func finish(using part: RecapMergePart) -> RecapSummary {
        var summary = RecapSummary(overview: part.overview, topics: topics(from: part.topics), isComplete: true)
        stamp(&summary)
        return summary
    }

    /// Combining the parts was declined: their own topics and overviews.
    func finishUnmerged(_ parts: [RecapMergePart]) -> RecapSummary {
        var summary = RecapSummary(
            overview: overview(parts.compactMap(\.overview.first)),
            topics: topics(from: parts.flatMap(\.topics).sorted { ($0.firstLine ?? .max) < ($1.firstLine ?? .max) }, limit: RecapPrompts.maximumTopics * 2),
            isComplete: true
        )
        stamp(&summary)
        return summary
    }

    /// A merge reply's topics, each with the lines of the parts' topics it
    /// combines (`T2, T5`). One that names none is matched to a part's
    /// topic by its title.
    func mergedTopics(_ draft: RecapDraft, parts: [RecapMergePart]) -> [RecapMergePart.Topic] {
        let partTopics = parts.flatMap(\.topics)
        let byReference = Dictionary(partTopics.map { ($0.reference, $0) }, uniquingKeysWith: { first, _ in first })
        return draft.topics.prefix(RecapPrompts.maximumTopics).map { topic in
            var sources = topic.parts.compactMap { byReference[$0] }
            if sources.isEmpty, let match = partTopics.max(by: { Self.overlap($0.title, topic.title) < Self.overlap($1.title, topic.title) }),
               Self.overlap(match.title, topic.title) >= 0.5 {
                sources = [match]
            }
            let ranges = sources.flatMap(\.ranges).sorted { $0.lowerBound < $1.lowerBound }
            var named = topic.participants
            if named.isEmpty { named = sources.flatMap(\.participants) }
            return RecapMergePart.Topic(
                title: topic.title,
                summary: transcript.base.restoringNickCase(in: topic.summary.isEmpty ? (sources.first?.summary ?? "") : topic.summary),
                participants: participants(named, in: ranges),
                ranges: ranges
            )
        }
    }

    // MARK: Results

    private func overview(_ sentences: [String]) -> [String] {
        var seen = Set<String>()
        return sentences
            .map { transcript.base.restoringNickCase(in: $0) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(RecapPrompts.maximumOverview)
            .map { $0 }
    }

    /// Topics as the window shows them: their lines become messages, in
    /// the order they came up. Ids are by position, so a topic keeps its
    /// row while the report streams in.
    private func topics(from topics: [RecapMergePart.Topic], limit: Int = RecapPrompts.maximumTopics) -> [RecapTopic] {
        topics.prefix(limit).enumerated().map { index, topic in
            var numbers = Set<Int>()
            for range in topic.ranges { numbers.formUnion(range) }
            let sorted = numbers.sorted()
            return RecapTopic(
                id: "topic-\(index)",
                title: topic.title,
                summary: topic.summary,
                participants: topic.participants,
                start: sorted.first.flatMap(transcript.reference),
                lineIDs: sorted.map { transcript.entries[$0 - 1].lineID }
            )
        }
    }

    /// Notes in the order they came up, at most so many of each kind.
    private static func limited(_ notes: [RecapNote]) -> [RecapNote] {
        var counts: [RecapNote.Kind: Int] = [:]
        return notes
            .enumerated()
            .sorted { ($0.element.reference?.time ?? .distantFuture, $0.offset) < ($1.element.reference?.time ?? .distantFuture, $1.offset) }
            .map(\.element)
            .filter { note in
                counts[note.kind, default: 0] += 1
                return counts[note.kind, default: 0] <= RecapPrompts.maximumNotes
            }
    }

    /// The same note again: same kind and line, or mostly the same words.
    static func isRepeat(_ note: RecapNote, of notes: [RecapNote]) -> Bool {
        notes.contains { other in
            guard other.kind == note.kind else { return false }
            if let line = note.reference?.lineID, line == other.reference?.lineID { return true }
            return overlap(other.text, note.text) >= 0.7
        }
    }

    /// How much two texts share, by their words (0 to 1).
    static func overlap(_ first: String, _ second: String) -> Double {
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        }
        let a = words(first)
        let b = words(second)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }
}

nonisolated extension RecapEngine {
    /// A note for you as shown: trimmed, without "doug: " in front, and
    /// with a capital letter unless it starts with a nick.
    static func cleanYouNote(_ note: String, ownNick: String) -> String {
        var text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ownNick.isEmpty, let range = text.range(of: ownNick, options: [.caseInsensitive, .anchored]) {
            let rest = text[range.upperBound...]
            if rest.first == ":" || rest.first == "," { text = rest.dropFirst().trimmingCharacters(in: .whitespaces) }
        }
        text = addressingTheReader(text, ownNick: ownNick)
        if !text.isEmpty, !text.hasSuffix("."), !text.hasSuffix("?"), !text.hasSuffix("!"), !text.hasSuffix("”") { text += "." }
        return text
    }

    /// "wren asked doug to review doug's PR" → "wren asked you to review
    /// your PR": the model names the reader despite being told not to.
    static func addressingTheReader(_ text: String, ownNick: String) -> String {
        guard !ownNick.isEmpty else { return text }
        let escaped = NSRegularExpression.escapedPattern(for: ownNick)
        let edge = "[\\p{L}\\p{N}_\\-\\[\\]\\\\`^{}|]"
        var result = text
        for (pattern, replacement) in [("(?<!\(edge))\(escaped)['’]s(?!\(edge))", "your"), ("(?<!\(edge))\(escaped)(?!\(edge))", "you")] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: replacement)
        }
        return result
    }
}
