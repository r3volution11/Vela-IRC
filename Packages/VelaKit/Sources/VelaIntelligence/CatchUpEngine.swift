// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// What the Catch me up engine needs from a language model. The live one
/// wraps Foundation Models (`FoundationModelsCatchUpModel`); tests use a fake.
nonisolated protocol CatchUpLanguageModel: Sendable {
    /// Tokens one request can hold: instructions, prompt and response.
    func contextSize() async -> Int
    /// The exact token count of `text`, or nil where the system can't
    /// count (before macOS 26.4); the engine estimates instead.
    func tokenCount(_ text: String) async -> Int?
    /// The exact tokens the response format adds to a request, or nil.
    func schemaTokenCount(for pass: CatchUpPrompts.Pass) async -> Int?
    /// A digest of one chunk (or a merge of digests), all at once.
    /// Errors are ``CatchUpModelError``s.
    func digest(prompt: String, instructions: String) async throws -> CatchUpDraft
    /// The final summary, streamed: each element is the summary so far.
    /// Errors are ``CatchUpModelError``s.
    func summarize(prompt: String, instructions: String) -> AsyncThrowingStream<CatchUpDraft, Error>
}

/// Model failures the engine reacts to.
nonisolated enum CatchUpModelError: Error, Equatable {
    /// The request didn't fit the context window: retry with less.
    case contextExceeded
    /// Guardrails or a refusal.
    case declined
    case unsupportedLanguage
    /// The model's assets aren't there (still downloading, say).
    case unavailable
    case failed(String)

    var catchUpError: CatchUpError {
        switch self {
        case .contextExceeded: .failed("This conversation is too long to summarize.")
        case .declined: .declined
        case .unsupportedLanguage: .unavailable(.unsupportedLanguage)
        case .unavailable: .unavailable(.modelNotReady)
        case .failed(let message): .failed(message)
        }
    }
}

/// Turns a ``CatchUpRequest`` into a ``CatchUpSummary``: builds the
/// transcript, summarizes it in one pass when it fits the model's context,
/// and otherwise digests it chunk by chunk and merges the digests (map /
/// reduce). The final pass streams, so the overview appears as it's
/// written. Exceeded context windows retry with smaller pieces.
nonisolated struct CatchUpEngine: Sendable {
    let model: any CatchUpLanguageModel

    /// Room left for each kind of response.
    static func responseTokens(for pass: CatchUpPrompts.Pass) -> Int {
        switch pass {
        case .single, .merge: 750
        case .digest: 500
        }
    }

    /// The response format's size when the system can't count it.
    static func estimatedSchemaTokens(for pass: CatchUpPrompts.Pass) -> Int {
        switch pass {
        case .single, .merge: 420
        case .digest: 380
        }
    }

    /// Summarizes `request`, calling `progress` with each partial summary.
    /// Returns the complete one. Throws ``CatchUpError``s (or
    /// `CancellationError`).
    func run(
        _ request: CatchUpRequest,
        progress: @Sendable (CatchUpSummary) -> Void = { _ in }
    ) async throws -> CatchUpSummary {
        let transcript = CatchUpTranscript(request)
        guard !transcript.isEmpty else { throw CatchUpError.nothingToSummarize }
        do {
            return try await summarize(transcript, bufferName: request.bufferName, progress: progress)
        } catch let error as CatchUpModelError {
            throw error.catchUpError
        }
    }

    private func summarize(
        _ transcript: CatchUpTranscript,
        bufferName: String,
        progress: @Sendable (CatchUpSummary) -> Void
    ) async throws -> CatchUpSummary {
        let costs = await lineCosts(transcript)
        let total = costs.reduce(0, +)
        var digestBudget = await budget(for: .digest, ownNick: transcript.ownNick)

        let single = await budget(for: .single, ownNick: transcript.ownNick)
        if total <= single.transcriptTokens {
            do {
                return try await stream(
                    prompt: CatchUpPrompts.single(transcript, bufferName: bufferName),
                    instructions: CatchUpPrompts.instructions(ownNick: transcript.ownNick, pass: .single),
                    transcript: transcript,
                    progress: progress
                )
            } catch CatchUpModelError.contextExceeded {
                // The estimate was off: chunk it, with a safety margin.
                digestBudget = digestBudget.shrunk(by: 0.6)
            }
        }

        try Task.checkCancellation()
        var digests: [CatchUpDigest] = []
        let pieces = CatchUpChunker.balanced(Array(zip(transcript.entries, costs)), budget: digestBudget.transcriptTokens) { $0.1 }
        for piece in pieces {
            digests += try await digest(piece.map(\.0)[...], of: transcript, bufferName: bufferName)
        }
        return try await merge(digests, transcript: transcript, bufferName: bufferName, progress: progress)
    }

    // MARK: Map

    /// Digests `entries`, splitting them in half (and again) whenever the
    /// model reports they didn't fit.
    private func digest(
        _ entries: ArraySlice<CatchUpTranscript.Entry>,
        of transcript: CatchUpTranscript,
        bufferName: String
    ) async throws -> [CatchUpDigest] {
        try Task.checkCancellation()
        guard let first = entries.first?.number, let last = entries.last?.number else { return [] }
        do {
            let draft = try await model.digest(
                prompt: CatchUpPrompts.digest(entries, of: transcript, bufferName: bufferName),
                instructions: CatchUpPrompts.instructions(ownNick: transcript.ownNick, pass: .digest)
            )
            return [CatchUpDigest(lines: first...last, draft: draft)]
        } catch CatchUpModelError.contextExceeded where entries.count > 1 {
            let middle = entries.startIndex + entries.count / 2
            let left = try await digest(entries[..<middle], of: transcript, bufferName: bufferName)
            let right = try await digest(entries[middle...], of: transcript, bufferName: bufferName)
            return left + right
        }
    }

    // MARK: Reduce

    /// Merges digests into the final summary. When they don't fit one
    /// request, neighbors are merged into bigger digests first.
    private func merge(
        _ digests: [CatchUpDigest],
        transcript: CatchUpTranscript,
        bufferName: String,
        progress: @Sendable (CatchUpSummary) -> Void
    ) async throws -> CatchUpSummary {
        let mergeBudget = await budget(for: .merge, ownNick: transcript.ownNick)
        var level = digests
        while level.count > 1, await cost(of: CatchUpPrompts.merge(level, bufferName: bufferName)) > mergeBudget.transcriptTokens {
            level = try await mergeNeighbors(level, budget: mergeBudget, transcript: transcript, bufferName: bufferName)
        }
        do {
            return try await stream(
                prompt: CatchUpPrompts.merge(level, bufferName: bufferName),
                instructions: CatchUpPrompts.instructions(ownNick: transcript.ownNick, pass: .merge),
                transcript: transcript,
                progress: progress
            )
        } catch CatchUpModelError.contextExceeded where level.count > 1 {
            let fewer = try await mergeNeighbors(level, budget: mergeBudget.shrunk(by: 0.5), transcript: transcript, bufferName: bufferName)
            return try await merge(fewer, transcript: transcript, bufferName: bufferName, progress: progress)
        }
    }

    /// One reduce level: groups neighbors that fit `budget` together and
    /// merges each group into one digest. Always shrinks the list (pairs
    /// up when even two don't fit by estimate).
    private func mergeNeighbors(
        _ digests: [CatchUpDigest],
        budget: CatchUpBudget,
        transcript: CatchUpTranscript,
        bufferName: String
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
        var merged: [CatchUpDigest] = []
        for group in groups {
            try Task.checkCancellation()
            let members = group.map { digests[$0] }
            guard members.count > 1, let first = members.first, let last = members.last else {
                merged += members
                continue
            }
            let draft = try await model.digest(
                prompt: CatchUpPrompts.merge(members, bufferName: bufferName),
                instructions: CatchUpPrompts.instructions(ownNick: transcript.ownNick, pass: .merge)
            )
            merged.append(CatchUpDigest(lines: first.lines.lowerBound...last.lines.upperBound, draft: draft))
        }
        return merged
    }

    // MARK: Streaming

    private func stream(
        prompt: String,
        instructions: String,
        transcript: CatchUpTranscript,
        progress: @Sendable (CatchUpSummary) -> Void
    ) async throws -> CatchUpSummary {
        var last: CatchUpDraft?
        for try await draft in model.summarize(prompt: prompt, instructions: instructions) {
            last = draft
            progress(Self.summary(from: draft, transcript: transcript, isComplete: false))
        }
        try Task.checkCancellation()
        guard let last else { throw CatchUpModelError.failed("Apple Intelligence didn't return a summary.") }
        return Self.summary(from: last, transcript: transcript, isComplete: true)
    }

    // MARK: Budgets

    private func budget(for pass: CatchUpPrompts.Pass, ownNick: String) async -> CatchUpBudget {
        let instructions = CatchUpPrompts.instructions(ownNick: ownNick, pass: pass)
        return CatchUpBudget(
            contextSize: await model.contextSize(),
            instructionTokens: await cost(of: instructions),
            schemaTokens: await model.schemaTokenCount(for: pass) ?? Self.estimatedSchemaTokens(for: pass),
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

    /// A draft as the reader sees it: line numbers become message ids,
    /// participants are limited to people who spoke (written as they
    /// wrote them), and notes about the reader are kept only when someone
    /// actually mentioned them.
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
            var lineID = topic.firstLine.flatMap(transcript.lineID(forNumber:))
            if lineID == nil, isComplete {
                lineID = transcript.firstLine(spokenBy: participants)?.lineID
            }
            topics.append(CatchUpTopic(
                id: topicID(topics.count),
                title: title,
                summary: transcript.restoringNickCase(in: topic.summary.trimmingCharacters(in: .whitespacesAndNewlines)),
                participants: participants,
                firstLineID: lineID
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
