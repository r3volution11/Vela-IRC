// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// How many tokens one request may spend on the transcript: the model's
/// context, minus the instructions (with the reply format), the response
/// itself and a little framing.
nonisolated struct CatchUpBudget: Sendable, Equatable {
    var contextSize: Int
    /// The session instructions: the rules and the reply format.
    var instructionTokens: Int
    var responseTokens: Int
    /// The prompt's own words around the transcript ("The conversation, …").
    var framingTokens = 60
    /// Share of the room actually used: below 1 after the model reported an
    /// exceeded context window.
    var fill = 1.0

    /// Never plan chunks smaller than this; a context that tight fails
    /// anyway and is reported.
    static let minimumTranscriptTokens = 200

    var transcriptTokens: Int {
        let room = contextSize - instructionTokens - responseTokens - framingTokens
        return max(Self.minimumTranscriptTokens, Int(Double(room) * fill))
    }

    /// The same budget using only `fraction` of what it uses now.
    func shrunk(by fraction: Double) -> CatchUpBudget {
        var copy = self
        copy.fill *= fraction
        return copy
    }
}

/// Splits a transcript into consecutive chunks that each fit a token
/// budget. Pure, so it's tested without a model.
nonisolated enum CatchUpChunker {
    /// Consecutive runs of `entries` whose summed `cost` stays within
    /// `budget`. A single line over budget still gets a chunk of its own
    /// (lines are already truncated, so it can only be slightly over).
    static func chunks<Element>(_ entries: [Element], budget: Int, cost: (Element) -> Int) -> [ArraySlice<Element>] {
        guard !entries.isEmpty else { return [] }
        var result: [ArraySlice<Element>] = []
        var start = entries.startIndex
        var used = 0
        for index in entries.indices {
            let itemCost = max(1, cost(entries[index]))
            if index > start, used + itemCost > budget {
                result.append(entries[start..<index])
                start = index
                used = 0
            }
            used += itemCost
        }
        result.append(entries[start..<entries.endIndex])
        return result
    }

    /// As many chunks as ``chunks(_:budget:cost:)`` makes, but evenly
    /// filled, so the last one isn't a sliver: cuts fall at the nearest
    /// line to each equal share of the total. Falls back to the greedy
    /// chunks if an even cut would overflow the budget.
    static func balanced<Element>(_ entries: [Element], budget: Int, cost: (Element) -> Int) -> [ArraySlice<Element>] {
        let greedy = chunks(entries, budget: budget, cost: cost)
        let count = greedy.count
        guard count > 1 else { return greedy }
        let costs = entries.map { max(1, cost($0)) }
        let total = Double(costs.reduce(0, +))
        var result: [ArraySlice<Element>] = []
        var start = entries.startIndex
        var cumulative = 0.0
        for index in entries.indices {
            let before = cumulative
            cumulative += Double(costs[index - entries.startIndex])
            let boundary = total * Double(result.count + 1) / Double(count)
            guard result.count < count - 1, cumulative >= boundary else { continue }
            // Cut before or after this line, whichever lands nearer the share.
            let cutAfter = cumulative - boundary <= boundary - before || index == start
            let end = cutAfter ? index + 1 : index
            result.append(entries[start..<end])
            start = end
        }
        result.append(entries[start..<entries.endIndex])
        let fits = result.allSatisfy { chunk in
            !chunk.isEmpty && chunk.reduce(0) { $0 + max(1, cost($1)) } <= budget
        }
        return fits ? result : greedy
    }

    /// Rough tokens for `text` when the system can't count them (macOS
    /// before 26.4). About three bytes of UTF-8 per token: English runs
    /// three to four characters a token, and CJK about one character
    /// (three bytes), so this errs on the safe side for both.
    static func estimatedTokens(_ text: String) -> Int {
        text.utf8.count / 3 + 1
    }
}
