// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// What the Catch me up engine needs from a language model. The live one
/// wraps Foundation Models (`FoundationModelsCatchUpModel`); tests use a fake.
/// Replies are plain text in ``CatchUpReply``'s format, which the engine
/// reads.
nonisolated protocol CatchUpLanguageModel: Sendable {
    /// Tokens one request can hold: instructions, prompt and response.
    func contextSize() async -> Int
    /// The exact token count of `text`, or nil where the system can't
    /// count (before macOS 26.4); the engine estimates instead.
    func tokenCount(_ text: String) async -> Int?
    /// The reply to a digest of one chunk (or a merge of digests), all at
    /// once. The response stops after `maximumResponseTokens`, or as soon
    /// as the reply so far is `enough` (it's written everything that will
    /// be kept). Errors are ``CatchUpModelError``s.
    func digest(
        prompt: String,
        instructions: String,
        maximumResponseTokens: Int,
        until enough: @escaping @Sendable (String) -> Bool
    ) async throws -> String
    /// The reply with the final summary, streamed: each element is the
    /// reply so far. The response stops after `maximumResponseTokens`.
    /// Errors are ``CatchUpModelError``s.
    func summarize(prompt: String, instructions: String, maximumResponseTokens: Int) -> AsyncThrowingStream<String, Error>
}

/// Model failures the engine reacts to.
nonisolated enum CatchUpModelError: Error, Equatable {
    /// The request didn't fit the context window: retry with less.
    case contextExceeded
    /// Guardrails or a refusal (thrown, or written out instead of a
    /// summary): that part is left out.
    case declined
    /// The model can't read the conversation's language.
    case unsupportedLanguage
    /// The model's assets aren't there (still downloading, say).
    case unavailable
    /// Too many requests for now (long stretches make many in the background).
    case rateLimited
    /// Private Cloud Compute can't take it (unreachable, over its daily
    /// limit, or anything else it reports): ``CatchUpRouter`` summarizes
    /// on this Mac instead. Never reaches the reader.
    case cloudUnavailable(CatchUpCloudFallback)
    case failed(String)

    var catchUpError: CatchUpError {
        switch self {
        case .contextExceeded: .failed("This conversation is too long to summarize.")
        case .declined: .declined
        // About what people wrote, not the Mac's language (that's checked
        // before summarizing), so nothing in System Settings fixes it.
        case .unsupportedLanguage: .conversationLanguageUnsupported
        case .unavailable: .unavailable(.modelNotReady)
        case .rateLimited: .rateLimited
        case .cloudUnavailable: .failed("Private Cloud Compute isn't available.")
        case .failed(let message): .failed(message)
        }
    }
}

/// Turns a ``CatchUpRequest`` into a ``CatchUpSummary``: builds the
/// transcript, summarizes it in one pass when it fits the model's context,
/// and otherwise digests it chunk by chunk and merges the digests (map /
/// reduce). The final pass streams, so the overview appears as it's
/// written. Exceeded context windows retry with smaller pieces, and parts
/// the model declines are left out (the summary says how many messages).
///
/// Prompts carry the transcript and the reader's nick, never the
/// channel's or the network's name (see ``CatchUpPrompts``).
nonisolated struct CatchUpEngine: Sendable {
    let model: any CatchUpLanguageModel

    /// Room left for each kind of response, which is also the most a
    /// response may write: one that runs on (repeating itself, say) is cut
    /// off there instead of filling the context window.
    static func responseTokens(for pass: CatchUpPrompts.Pass) -> Int {
        switch pass {
        case .single, .merge: 750
        case .digest: 500
        }
    }

    /// Summarizes `request`, calling `progress` with each snapshot: how
    /// many parts of a long stretch are read, then the summary as it's
    /// written. Words in one snapshot are never missing from the next (see
    /// ``CatchUpSummary/isRevising``). Returns the complete summary.
    /// Throws ``CatchUpError``s (or `CancellationError`); only a stretch
    /// the model declines in full fails as declined. A Private Cloud
    /// Compute model's ``CatchUpModelError/cloudUnavailable(_:)`` comes
    /// through as it is, for ``CatchUpRouter``.
    ///
    /// - Parameters:
    ///   - venue: Where the model runs, stamped on every snapshot.
    ///   - cloudFallback: Why Private Cloud Compute isn't the venue, when
    ///     it was meant to be.
    ///   - measured: ``measure(_:)`` of the same transcript, if it's at
    ///     hand, so the tokens aren't counted twice.
    func run(
        _ request: CatchUpRequest,
        venue: CatchUpVenue = .onDevice,
        cloudFallback: CatchUpCloudFallback? = nil,
        measured: Measurement? = nil,
        progress: @escaping @Sendable (CatchUpSummary) -> Void = { _ in }
    ) async throws -> CatchUpSummary {
        let transcript = measured?.transcript ?? CatchUpTranscript(request)
        guard !transcript.isEmpty else { throw CatchUpError.nothingToSummarize }
        let reporter = CatchUpReporter(transcript: transcript, venue: venue, cloudFallback: cloudFallback, send: progress)
        do {
            let measurement = if let measured { measured } else { await measure(transcript) }
            return try await summarize(measurement, reporter: reporter)
        } catch let error as CatchUpModelError {
            if case .cloudUnavailable = error { throw error }
            throw error.catchUpError
        }
    }

    // MARK: Planning

    /// A transcript sized up for one model: each line's tokens and the
    /// room one request has for them.
    struct Measurement: Sendable {
        let transcript: CatchUpTranscript
        /// Each entry's tokens, with its line break.
        let costs: [Int]
        /// Room for the transcript in a request that summarizes it whole.
        let singleBudget: CatchUpBudget
        /// Room for it in one part's request.
        let digestBudget: CatchUpBudget

        var totalTokens: Int { costs.reduce(0, +) }

        /// One request holds the whole transcript.
        var fitsOnePass: Bool { totalTokens <= singleBudget.transcriptTokens }

        /// Parts it's read in: 1 when it fits one pass, otherwise the
        /// chunks it's split into (merging them takes a few requests more).
        var passes: Int {
            guard !fitsOnePass else { return 1 }
            return max(2, CatchUpChunker.chunks(costs, budget: digestBudget.transcriptTokens) { $0 }.count)
        }
    }

    /// Sizes up `transcript` for this engine's model: one token count of
    /// the whole transcript where the system can count, else estimates.
    func measure(_ transcript: CatchUpTranscript) async -> Measurement {
        Measurement(
            transcript: transcript,
            costs: await lineCosts(transcript),
            singleBudget: await budget(for: .single, ownNick: transcript.ownNick),
            digestBudget: await budget(for: .digest, ownNick: transcript.ownNick)
        )
    }

    private func summarize(
        _ measurement: Measurement,
        reporter: CatchUpReporter
    ) async throws -> CatchUpSummary {
        let transcript = measurement.transcript
        let costs = measurement.costs
        let total = measurement.totalTokens
        let digestBudget = measurement.digestBudget
        var chunkTokens = digestBudget.transcriptTokens

        if measurement.fitsOnePass {
            do {
                return try await stream(
                    prompt: CatchUpPrompts.single(transcript),
                    instructions: CatchUpPrompts.instructions(ownNick: transcript.ownNick, pass: .single),
                    pass: .single,
                    transcript: transcript,
                    cites: { 1...transcript.entries.count ~= $0 },
                    reporter: reporter
                )
            } catch CatchUpModelError.contextExceeded {
                // The estimate was off: chunk it, with a safety margin.
                chunkTokens = digestBudget.shrunk(by: 0.6).transcriptTokens
                reporter.redo()
            } catch CatchUpModelError.declined where transcript.entries.count > 1 {
                // Something in it trips the guardrails: read it in halves,
                // so only the half that does is left out.
                chunkTokens = min(chunkTokens, max(1, (total + 1) / 2))
                reporter.redo()
            }
        }

        try Task.checkCancellation()
        var digests: [CatchUpDigest] = []
        let pieces = CatchUpChunker.balanced(Array(zip(transcript.entries, costs)), budget: chunkTokens) { $0.1 }
        reporter.plan(pieces.count)
        for piece in pieces {
            digests += try await digest(piece.map(\.0)[...], of: transcript, reporter: reporter)
        }
        return try await merge(digests, transcript: transcript, reporter: reporter)
    }

    // MARK: Map

    /// Digests `entries`, splitting them in half (and again) whenever the
    /// model reports they didn't fit. A part the model declines is left out.
    private func digest(
        _ entries: ArraySlice<CatchUpTranscript.Entry>,
        of transcript: CatchUpTranscript,
        reporter: CatchUpReporter
    ) async throws -> [CatchUpDigest] {
        try Task.checkCancellation()
        guard let first = entries.first?.number, let last = entries.last?.number else { return [] }
        do {
            let reply = try await model.digest(
                prompt: CatchUpPrompts.digest(entries, of: transcript),
                instructions: CatchUpPrompts.instructions(ownNick: transcript.ownNick, pass: .digest),
                maximumResponseTokens: Self.responseTokens(for: .digest),
                until: CatchUpReplyLimit(nicks: transcript.nicks, topics: CatchUpPrompts.maximumDigestTopics).isReached
            )
            let draft = try Self.draft(from: reply, transcript: transcript, cites: { first...last ~= $0 })
            reporter.partRead()
            return [CatchUpDigest(lines: first...last, draft: draft.limited(topics: CatchUpPrompts.maximumDigestTopics))]
        } catch CatchUpModelError.contextExceeded where entries.count > 1 {
            // One part becomes two.
            reporter.plan(1)
            let middle = entries.startIndex + entries.count / 2
            let left = try await digest(entries[..<middle], of: transcript, reporter: reporter)
            let right = try await digest(entries[middle...], of: transcript, reporter: reporter)
            return left + right
        } catch CatchUpModelError.declined {
            // Its guardrails, or a refusal: one part shouldn't sink the
            // whole summary, which says how much it left out.
            reporter.skipped(entries.count)
            return []
        }
    }

    // MARK: Reduce

    /// Merges digests into the final summary. When they don't fit one
    /// request, neighbors are merged into bigger digests first. Throws
    /// `declined` when every part was declined.
    private func merge(
        _ digests: [CatchUpDigest],
        transcript: CatchUpTranscript,
        reporter: CatchUpReporter
    ) async throws -> CatchUpSummary {
        let mergeBudget = await budget(for: .merge, ownNick: transcript.ownNick)
        var level = digests
        while level.count > 1, await cost(of: CatchUpPrompts.merge(level)) > mergeBudget.transcriptTokens {
            level = try await mergeNeighbors(level, budget: mergeBudget, transcript: transcript, reporter: reporter)
        }
        guard let only = level.first else { throw CatchUpModelError.declined }
        do {
            let cited = Self.citedLines(level)
            return try await stream(
                prompt: CatchUpPrompts.merge(level),
                instructions: CatchUpPrompts.instructions(ownNick: transcript.ownNick, pass: .merge),
                pass: .merge,
                transcript: transcript,
                cites: { cited.contains($0) },
                reporter: reporter
            )
        } catch CatchUpModelError.contextExceeded where level.count > 1 {
            reporter.redo()
            let fewer = try await mergeNeighbors(level, budget: mergeBudget.shrunk(by: 0.5), transcript: transcript, reporter: reporter)
            return try await merge(fewer, transcript: transcript, reporter: reporter)
        } catch CatchUpModelError.declined where level.count > 1 {
            // Something in the notes trips the guardrails: combine them in
            // smaller groups, leaving out any group it declines.
            reporter.redo()
            let fewer = try await mergeNeighbors(level, budget: mergeBudget.shrunk(by: 0.5), transcript: transcript, reporter: reporter)
            return try await merge(fewer, transcript: transcript, reporter: reporter)
        } catch CatchUpModelError.declined {
            // One digest left, covering everything that wasn't skipped:
            // it's the summary.
            return reporter.finish(only.draft)
        }
    }

    /// One reduce level: groups neighbors that fit `budget` together and
    /// merges each group into one digest. Always shrinks the list (pairs
    /// up when even two don't fit by estimate). A group the model declines
    /// is left out.
    private func mergeNeighbors(
        _ digests: [CatchUpDigest],
        budget: CatchUpBudget,
        transcript: CatchUpTranscript,
        reporter: CatchUpReporter
    ) async throws -> [CatchUpDigest] {
        var costs: [Int] = []
        for (index, digest) in digests.enumerated() {
            costs.append(await cost(of: CatchUpPrompts.render(digest, part: index + 1)))
        }
        var groups = CatchUpChunker.chunks(Array(digests.indices), budget: budget.transcriptTokens) { costs[$0] }
        if groups.count >= digests.count {
            groups = stride(from: 0, to: digests.count, by: 2).map { start in
                Array(digests.indices)[start..<min(start + 2, digests.count)]
            }
        }
        reporter.plan(groups.count { $0.count > 1 })
        var merged: [CatchUpDigest] = []
        for group in groups {
            try Task.checkCancellation()
            let members = group.map { digests[$0] }
            guard members.count > 1, let first = members.first, let last = members.last else {
                merged += members
                continue
            }
            let summarized = members.reduce(0) { $0 + $1.summarizedLines }
            do {
                // The result is a digest, so it gets a digest's room.
                let reply = try await model.digest(
                    prompt: CatchUpPrompts.merge(members),
                    instructions: CatchUpPrompts.instructions(ownNick: transcript.ownNick, pass: .merge),
                    maximumResponseTokens: Self.responseTokens(for: .digest),
                    until: CatchUpReplyLimit(nicks: transcript.nicks, topics: CatchUpPrompts.maximumDigestTopics).isReached
                )
                let cited = Self.citedLines(members)
                let draft = try Self.draft(from: reply, transcript: transcript, cites: { cited.contains($0) })
                reporter.partRead()
                merged.append(CatchUpDigest(
                    lines: first.lines.lowerBound...last.lines.upperBound,
                    draft: draft.limited(topics: CatchUpPrompts.maximumDigestTopics),
                    summarizedLines: summarized
                ))
            } catch CatchUpModelError.declined {
                reporter.skipped(summarized)
            }
        }
        return merged
    }

    /// The line numbers `digests` cite: the only ones a merge of them can
    /// cite, since it never sees the transcript.
    private static func citedLines(_ digests: [CatchUpDigest]) -> Set<Int> {
        Set(digests.flatMap { $0.draft.topics.compactMap(\.firstLine) })
    }

    // MARK: Replies

    /// A finished reply as a draft, keeping only line numbers it `cites`
    /// legitimately. A reply with nothing usable, such as a refusal written
    /// out instead of thrown, counts as declined.
    static func draft(from reply: String, transcript: CatchUpTranscript, cites: (Int) -> Bool) throws -> CatchUpDraft {
        let draft = CatchUpReply.parse(reply, isComplete: true, nicks: transcript.nicks)
        guard !CatchUpReply.isDeclined(draft) else { throw CatchUpModelError.declined }
        return draft.citing(cites)
    }

    // MARK: Streaming

    /// The final pass, read as it streams: the overview as it's written,
    /// each topic once its line is done. A snapshot that reads the same as
    /// the last one isn't passed on, so a topic's line being written costs
    /// the card nothing. A reply that runs past the topics and notes the
    /// card shows is stopped there (mentions it didn't get to are quoted
    /// from the transcript).
    private func stream(
        prompt: String,
        instructions: String,
        pass: CatchUpPrompts.Pass,
        transcript: CatchUpTranscript,
        cites: (Int) -> Bool,
        reporter: CatchUpReporter
    ) async throws -> CatchUpSummary {
        var reply: String?
        var shown: CatchUpDraft?
        var reader = CatchUpReply.Reader(nicks: transcript.nicks)
        let replies = model.summarize(prompt: prompt, instructions: instructions, maximumResponseTokens: Self.responseTokens(for: pass))
        for try await text in replies {
            reply = text
            let draft = reader.read(text, isComplete: false).citing(cites)
            // Past what the card shows, the rest would be dropped: stop
            // writing it.
            if CatchUpReply.isPastLimits(draft, topics: CatchUpPrompts.maximumTopics) { break }
            guard draft != shown else { continue }
            shown = draft
            reporter.wrote(draft)
        }
        try Task.checkCancellation()
        guard let reply else { throw CatchUpModelError.failed("Apple Intelligence didn't return a summary.") }
        return reporter.finish(try Self.draft(from: reply, transcript: transcript, cites: cites))
    }

    // MARK: Budgets

    /// The room in one request. The instructions include the reply format,
    /// which takes the place a guided-generation schema had.
    private func budget(for pass: CatchUpPrompts.Pass, ownNick: String) async -> CatchUpBudget {
        let instructions = CatchUpPrompts.instructions(ownNick: ownNick, pass: pass)
        return CatchUpBudget(
            contextSize: await model.contextSize(),
            instructionTokens: await cost(of: instructions),
            responseTokens: Self.responseTokens(for: pass)
        )
    }

    private func cost(of text: String) async -> Int {
        await model.tokenCount(text) ?? CatchUpChunker.estimatedTokens(text)
    }

    /// Each transcript line's tokens (plus its line break). Counting every
    /// line separately would take hundreds of calls, so one count of the
    /// whole transcript calibrates the per-line estimates.
    private func lineCosts(_ transcript: CatchUpTranscript) async -> [Int] {
        let estimates = transcript.entries.map { CatchUpChunker.estimatedTokens($0.text) + 1 }
        guard let counted = await model.tokenCount(transcript.text) else { return estimates }
        let ratio = Double(counted) / Double(max(1, estimates.reduce(0, +)))
        return estimates.map { Int((Double($0) * ratio * 1.08).rounded(.up)) }
    }

    // MARK: Results

    /// A draft as the reader sees it: line numbers become message ids (a
    /// topic without a valid one links nowhere), participants are limited
    /// to people who spoke (written as they wrote them), and notes about
    /// the reader are kept only when someone actually mentioned them.
    static func summary(from draft: CatchUpDraft, transcript: CatchUpTranscript, isComplete: Bool) -> CatchUpSummary {
        var topics: [CatchUpTopic] = []
        for topic in draft.topics {
            guard topics.count < CatchUpPrompts.maximumTopics else { break }
            let title = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            var seen = Set<String>()
            let participants = topic.participants
                .compactMap(transcript.canonicalNick)
                .filter { seen.insert($0.lowercased()).inserted }
                .prefix(CatchUpPrompts.maximumParticipants)
            topics.append(CatchUpTopic(
                id: topicID(topics.count),
                title: title,
                summary: transcript.restoringNickCase(in: topic.summary.trimmingCharacters(in: .whitespacesAndNewlines)),
                participants: Array(participants),
                firstLineID: topic.firstLine.flatMap(transcript.lineID(forNumber:))
            ))
        }

        var mentions: [String] = []
        let mentioners = Set(transcript.mentionsOfOwnNick.map { $0.nick.lowercased() })
        if !mentioners.isEmpty {
            var seen = Set<String>()
            mentions = draft.addressedToYou
                .map { cleanNote($0, transcript: transcript) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
                // Each note should name who mentioned the reader. One that
                // names nobody who did is the model reading too much into a
                // message to everyone, or into the reader's own.
                .filter { note in
                    transcript.nicksNamed(in: note).contains { mentioners.contains($0.lowercased()) }
                }
            // Near repeats ("…the PR" and "…the PR when you get a sec").
            mentions = mentions.filter { note in
                let key = note.lowercased()
                return !mentions.contains { other in
                    let otherKey = other.lowercased()
                    return otherKey != key && otherKey.hasPrefix(key)
                }
            }
            if mentions.isEmpty, isComplete {
                mentions = mentionNotes(in: transcript)
            }
            mentions = Array(mentions.prefix(CatchUpPrompts.maximumMentions))
        }

        return CatchUpSummary(
            overview: transcript.restoringNickCase(in: draft.overview.trimmingCharacters(in: .whitespacesAndNewlines)),
            topics: topics,
            addressedToYou: mentions,
            messageCount: transcript.entries.count,
            isComplete: isComplete
        )
    }

    /// A note as shown: trimmed, nicks in their written case, and without
    /// the "doug: " the model sometimes puts first.
    static func cleanNote(_ note: String, transcript: CatchUpTranscript) -> String {
        var text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let own = transcript.ownNick
        if !own.isEmpty, let range = text.range(of: own, options: [.caseInsensitive, .anchored]) {
            let rest = text[range.upperBound...]
            if rest.first == ":" || rest.first == "," {
                text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            }
        }
        // A message quoted as written, "maple_: doug: are you hosting?",
        // reads like the notes Vela quotes itself: maple_: “are you hosting?”.
        if !own.isEmpty, let colon = text.firstIndex(of: ":"), transcript.canonicalNick(String(text[..<colon])) != nil {
            let message = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let range = message.range(of: own, options: [.caseInsensitive, .anchored]) {
                let rest = message[range.upperBound...]
                if rest.first == ":" || rest.first == "," {
                    let quote = rest.dropFirst().trimmingCharacters(in: .whitespaces)
                    if !quote.isEmpty { text = "\(text[..<colon]): “\(quote)”" }
                }
            }
        }
        text = transcript.restoringNickCase(in: text)
        if let first = text.first, first.isLowercase, !transcript.nicks.contains(where: { text.hasPrefix($0) }) {
            text = first.uppercased() + text.dropFirst()
        }
        return text
    }

    /// Notes quoting the lines that mention the reader, for when the model
    /// missed them: `wren: “can you review the sidebar rail PR…”`.
    static func mentionNotes(in transcript: CatchUpTranscript, limit: Int = CatchUpPrompts.maximumMentions) -> [String] {
        transcript.mentionsOfOwnNick.prefix(limit).map { entry in
            var message = entry.message
            // "doug: can you…" → "can you…"
            if let address = message.range(of: transcript.ownNick, options: [.caseInsensitive, .anchored]) {
                let rest = message[address.upperBound...]
                if rest.first == ":" || rest.first == "," {
                    message = rest.dropFirst().trimmingCharacters(in: .whitespaces)
                }
            }
            let snippet = message.count > 90 ? message.prefix(89).trimmingCharacters(in: .whitespaces) + "…" : message
            return entry.isAction ? "* \(entry.nick) \(snippet)" : "\(entry.nick): “\(snippet)”"
        }
    }

    /// Stable per position, so a topic keeps its identity (and its row)
    /// while the summary streams in.
    static func topicID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "C47C0B00-0000-4000-8000-%012d", index)) ?? UUID()
    }
}

/// What one run tells the card (``CatchUpEngine/run(_:progress:)``): how
/// many parts of a long stretch are read, then the summary as it's
/// written. Words that have appeared are never taken back: while a pass is
/// redone they stay, marked ``CatchUpSummary/isRevising``, until the next
/// pass writes. Used by one run, from one task.
nonisolated private final class CatchUpReporter {
    private let transcript: CatchUpTranscript
    private let venue: CatchUpVenue
    private let cloudFallback: CatchUpCloudFallback?
    private let send: @Sendable (CatchUpSummary) -> Void
    private var completed = 0
    private var total = 0
    private var skippedMessages = 0
    /// The latest snapshot with words in it.
    private var written: CatchUpSummary?

    init(
        transcript: CatchUpTranscript,
        venue: CatchUpVenue,
        cloudFallback: CatchUpCloudFallback?,
        send: @escaping @Sendable (CatchUpSummary) -> Void
    ) {
        self.transcript = transcript
        self.venue = venue
        self.cloudFallback = cloudFallback
        self.send = send
    }

    /// Where it's written, on every snapshot.
    private func stamp(_ summary: inout CatchUpSummary) {
        summary.skippedMessages = skippedMessages
        summary.venue = venue
        summary.cloudFallback = cloudFallback
    }

    /// `count` more parts to read: chunks, halves of one, or merges.
    func plan(_ count: Int) {
        guard count > 0 else { return }
        total += count
        report()
    }

    func partRead() {
        completed += 1
        report()
    }

    /// A part was declined: its `messages` are left out.
    func skipped(_ messages: Int) {
        skippedMessages += messages
        completed += 1
        report()
    }

    /// A pass failed and is being redone: what it wrote stays, dimmed.
    func redo() {
        if written != nil { report() }
    }

    /// A snapshot of the summary being written. Until it has words, the
    /// card keeps showing what it had.
    func wrote(_ draft: CatchUpDraft) {
        var summary = CatchUpEngine.summary(from: draft, transcript: transcript, isComplete: false)
        guard summary.hasText else { return }
        stamp(&summary)
        written = summary
        send(summary)
    }

    /// The finished summary.
    func finish(_ draft: CatchUpDraft) -> CatchUpSummary {
        var summary = CatchUpEngine.summary(from: draft, transcript: transcript, isComplete: true)
        stamp(&summary)
        return summary
    }

    private func report() {
        var snapshot = written ?? CatchUpSummary(
            overview: "", topics: [], addressedToYou: [], messageCount: transcript.entries.count, isComplete: false
        )
        snapshot.isRevising = written != nil
        snapshot.progress = total > 0 ? CatchUpProgress(completed: min(completed, total), total: total) : nil
        stamp(&snapshot)
        send(snapshot)
    }
}
