// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore

/// A Recap's messages as Apple Intelligence reads them: Catch me up's
/// numbered transcript (``CatchUpTranscript``: `[12] nick: text`, links
/// reduced to their site, long lines cut) over every conversation in turn,
/// numbered from 1 across all of them, so a line number names one message.
/// Conversations are told apart by number ("Conversation 2:"), never by
/// name.
nonisolated struct RecapTranscript: Sendable {
    struct Conversation: Sendable, Equatable {
        let id: BufferID
        let ownNick: String
    }

    let base: CatchUpTranscript
    let conversations: [Conversation]
    /// Each entry's conversation, by entry index.
    let conversationOfEntry: [Int]
    /// When each entry's message was sent, by entry index.
    let times: [Date]
    /// Messages left out to stay under the limit (the oldest).
    let omittedLines: Int

    var entries: [CatchUpTranscript.Entry] { base.entries }
    var isEmpty: Bool { base.isEmpty }
    var conversationCount: Int { conversations.count }
    /// Everyone who spoke.
    var nicks: [String] { base.nicks }
    /// The reader's nick: the one used on most of these lines' networks.
    var ownNick: String { base.ownNick }

    init(_ input: RecapInput, maximumLines: Int = RecapLimits.summaryLines) {
        let kept = input.lineCount > maximumLines
            ? RecapGatherer.keepNewest(maximumLines, of: input.conversations)
            : input.conversations
        var lines: [CatchUpLine] = []
        var conversationOf: [UUID: Int] = [:]
        var timeOf: [UUID: Date] = [:]
        var ownNickCounts: [String: Int] = [:]
        for (index, conversation) in kept.enumerated() {
            ownNickCounts[conversation.ownNick, default: 0] += conversation.lines.count
            for line in conversation.lines {
                lines.append(CatchUpLine(id: line.id, time: line.time, nick: line.nick, text: line.text, isAction: line.isAction))
                conversationOf[line.id] = index
                timeOf[line.id] = line.time
            }
        }
        let ownNick = ownNickCounts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? ""
        base = CatchUpTranscript(lines: lines, ownNick: ownNick, maximumLines: .max)
        conversations = kept.map { Conversation(id: $0.id, ownNick: $0.ownNick) }
        conversationOfEntry = base.entries.map { conversationOf[$0.lineID] ?? 0 }
        times = base.entries.map { timeOf[$0.lineID] ?? .distantPast }
        omittedLines = max(0, input.lineCount - kept.reduce(0) { $0 + $1.lines.count })
    }

    /// `entries` as written in a prompt: one line each, under a
    /// "Conversation 2:" line wherever the conversation changes (when
    /// there's more than one).
    func text(of entries: ArraySlice<CatchUpTranscript.Entry>) -> String {
        guard conversationCount > 1 else { return CatchUpTranscript.text(of: entries) }
        var lines: [String] = []
        var current = -1
        for entry in entries {
            let conversation = conversationOfEntry[entry.number - 1]
            if conversation != current {
                lines.append("Conversation \(conversation + 1):")
                current = conversation
            }
            lines.append(entry.text)
        }
        return lines.joined(separator: "\n")
    }

    /// Whether entry `number` starts a conversation's run in a prompt.
    func startsConversation(_ number: Int) -> Bool {
        guard conversationCount > 1, number > 1 else { return conversationCount > 1 }
        return conversationOfEntry[number - 1] != conversationOfEntry[number - 2]
    }

    /// The conversations (1-based, as prompts number them) lines in `range` are in.
    func conversationNumbers(in range: ClosedRange<Int>) -> [Int] {
        guard isValid(range.lowerBound), isValid(range.upperBound) else { return [] }
        var numbers: [Int] = []
        for number in range {
            let conversation = conversationOfEntry[number - 1] + 1
            if numbers.last != conversation { numbers.append(conversation) }
        }
        return numbers
    }

    func isValid(_ number: Int) -> Bool {
        number >= 1 && number <= entries.count
    }

    /// The message behind line `number`, and where it is.
    func reference(_ number: Int) -> RecapReference? {
        guard isValid(number) else { return nil }
        let entry = entries[number - 1]
        return RecapReference(
            conversation: conversations[conversationOfEntry[number - 1]].id,
            lineID: entry.lineID,
            time: times[number - 1]
        )
    }

    /// `range` cut to the conversation its first line is in.
    func withinConversation(_ range: ClosedRange<Int>) -> ClosedRange<Int>? {
        let lower = max(1, range.lowerBound)
        let upper = min(entries.count, range.upperBound)
        guard lower <= upper else { return nil }
        let conversation = conversationOfEntry[lower - 1]
        var end = lower
        while end < upper, conversationOfEntry[end] == conversation { end += 1 }
        return lower...end
    }
}

/// One part's notes, as a merge reads them: its overview and topics, each
/// topic with the lines it covers.
nonisolated struct RecapMergePart: Sendable, Equatable {
    struct Topic: Sendable, Equatable {
        /// `T3` in the merge prompt: assigned when the prompt is written.
        var reference = 0
        var title: String
        var summary: String
        var participants: [String]
        /// Transcript lines it covers.
        var ranges: [ClosedRange<Int>]

        var firstLine: Int? { ranges.map(\.lowerBound).min() }
    }

    /// `Part 2` in the merge prompt.
    var number = 0
    /// Transcript lines the part covers.
    var lines: ClosedRange<Int>
    var overview: [String]
    var topics: [Topic]
    /// Lines it summarizes: fewer than `lines` holds when a part in
    /// between was declined and left out.
    var summarizedLines: Int

    /// `parts` numbered for one merge prompt: parts from 1, and their
    /// topics T1, T2… across all of them.
    static func numbered(_ parts: [RecapMergePart]) -> [RecapMergePart] {
        var reference = 0
        return parts.enumerated().map { index, part in
            var copy = part
            copy.number = index + 1
            for topic in copy.topics.indices {
                reference += 1
                copy.topics[topic].reference = reference
            }
            return copy
        }
    }
}
