// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A successful fuzzy match: higher scores rank first.
nonisolated struct FuzzyMatch: Equatable, Sendable {
    var score: Int
    /// Offsets, in `Character`s, of the matched characters in the target.
    var positions: [Int]
}

/// A string prepared for repeated fuzzy matching: folded (case- and
/// diacritic-insensitive) once, with a bonus per position for word starts.
nonisolated struct FuzzyTarget: Sendable {
    let text: String
    let count: Int
    fileprivate let keys: [UInt32]
    fileprivate let bonuses: [Int]

    init(_ text: String) {
        self.text = text
        var keys: [UInt32] = []
        var bonuses: [Int] = []
        keys.reserveCapacity(text.count)
        bonuses.reserveCapacity(text.count)
        var previous: Character?
        for character in text {
            keys.append(FuzzyMatcher.fold(character))
            bonuses.append(FuzzyMatcher.bonus(for: character, after: previous))
            previous = character
        }
        self.keys = keys
        self.bonuses = bonuses
        self.count = keys.count
    }
}

/// VS Code-style fuzzy matching: the query's characters must appear in order
/// (ignoring case, accents and spaces). Matches at the start, at word starts
/// (after a space, `:`, `#`, `-`… or a lower→upper case change) and in
/// unbroken runs score higher; gaps cost a little. So "tml" ranks
/// "Toggle Member List" above "Theme: Select Theme…", and a prefix beats a
/// match in the middle.
///
/// The best alignment is found with a small dynamic program (like fzf's),
/// O(query × target), after a cheap subsequence check rejects most targets.
nonisolated enum FuzzyMatcher {
    static let scoreMatch = 16
    static let bonusStart = 12
    static let bonusBoundary = 10
    static let bonusCamel = 8
    static let bonusConsecutive = 4
    static let gapStart = 3
    static let gapExtension = 1
    static let firstCharMultiplier = 2

    /// Folds a query once; reuse it for every target.
    static func prepareQuery(_ query: String) -> [UInt32] {
        query.filter { !$0.isWhitespace }.map(fold)
    }

    static func match(_ query: String, in target: String) -> FuzzyMatch? {
        match(prepareQuery(query), in: FuzzyTarget(target))
    }

    /// Matches a prepared query. An empty query matches everything with score 0.
    static func match(_ query: [UInt32], in target: FuzzyTarget) -> FuzzyMatch? {
        let m = query.count
        let n = target.count
        guard m > 0 else { return FuzzyMatch(score: 0, positions: []) }
        guard m <= n else { return nil }
        let keys = target.keys
        let bonuses = target.bonuses

        // Quick reject (and bounds): the earliest and latest feasible
        // position of each query character.
        var first = [Int](repeating: 0, count: m)
        var j = 0
        for i in 0..<m {
            while j < n, keys[j] != query[i] { j += 1 }
            guard j < n else { return nil }
            first[i] = j
            j += 1
        }
        var last = [Int](repeating: 0, count: m)
        j = n - 1
        for i in stride(from: m - 1, through: 0, by: -1) {
            while j >= 0, keys[j] != query[i] { j -= 1 }
            last[i] = j
            j -= 1
        }

        let none = Int.min / 4
        // score[i*n+j]: best score with query[i] matched at target[j].
        var score = [Int](repeating: none, count: m * n)
        // The bonus of the run that (i, j) continues, for consecutive matches.
        var runBonus = [Int](repeating: 0, count: m * n)
        // Where query[i-1] was matched on the best path to (i, j).
        var previous = [Int](repeating: -1, count: m * n)

        for i in 0..<m {
            let row = i * n
            let above = (i - 1) * n
            // Best of score[i-1][k] + k * gapExtension over k <= j - 2.
            var bestGap = none
            var bestGapIndex = -1
            // Start early enough that every earlier match of query[i-1] is
            // seen by the gap tracker before query[i] can match.
            let start = i == 0 ? first[0] : first[i - 1] + 1
            for j in start...last[i] {
                if i > 0, j >= 2 {
                    let k = j - 2
                    let candidate = score[above + k]
                    if candidate > none {
                        let adjusted = candidate + k * gapExtension
                        if adjusted > bestGap {
                            bestGap = adjusted
                            bestGapIndex = k
                        }
                    }
                }
                guard j >= first[i], keys[j] == query[i] else { continue }
                let bonus = bonuses[j]
                if i == 0 {
                    score[row + j] = scoreMatch + bonus * firstCharMultiplier
                    runBonus[row + j] = bonus
                    continue
                }
                var best = none
                var from = -1
                var run = bonus
                if j >= 1, score[above + j - 1] > none {
                    let carried = runBonus[above + j - 1]
                    let effective = max(carried, bonusConsecutive, bonus)
                    best = score[above + j - 1] + scoreMatch + effective
                    from = j - 1
                    run = (bonus >= bonusBoundary && bonus > carried) ? bonus : carried
                }
                if bestGap > none {
                    // Gap of (j - k - 1) characters: gapStart + extra * gapExtension.
                    let gapped = bestGap - gapStart - (j - 2) * gapExtension + scoreMatch + bonus
                    if gapped > best {
                        best = gapped
                        from = bestGapIndex
                        run = bonus
                    }
                }
                score[row + j] = best
                runBonus[row + j] = run
                previous[row + j] = from
            }
        }

        let lastRow = (m - 1) * n
        var bestScore = none
        var bestEnd = -1
        for j in first[m - 1]...last[m - 1] where score[lastRow + j] > bestScore {
            bestScore = score[lastRow + j]
            bestEnd = j
        }
        guard bestEnd >= 0 else { return nil }

        var positions = [Int](repeating: 0, count: m)
        var position = bestEnd
        for i in stride(from: m - 1, through: 0, by: -1) {
            positions[i] = position
            position = previous[i * n + position]
        }
        return FuzzyMatch(score: bestScore, positions: positions)
    }

    /// Whether `haystack` contains `needle` contiguously (both prepared).
    static func contains(_ haystack: [UInt32], _ needle: [UInt32]) -> Bool {
        guard !needle.isEmpty else { return true }
        guard needle.count <= haystack.count else { return false }
        outer: for start in 0...(haystack.count - needle.count) {
            for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
                continue outer
            }
            return true
        }
        return false
    }

    // MARK: Character classes

    static func fold(_ character: Character) -> UInt32 {
        if character.isASCII, let ascii = character.asciiValue {
            // Fast path: ASCII lowercase.
            return UInt32(ascii >= 65 && ascii <= 90 ? ascii + 32 : ascii)
        }
        let folded = String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.unicodeScalars.first?.value ?? 0
    }

    static func bonus(for character: Character, after previous: Character?) -> Int {
        guard let previous else { return bonusStart }
        if isSeparator(previous) { return isSeparator(character) ? 0 : bonusBoundary }
        if previous.isLowercase && character.isUppercase { return bonusCamel }
        if !previous.isNumber && character.isNumber { return bonusCamel / 2 }
        return 0
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || separators.contains(character)
    }

    private static let separators: Set<Character> = [
        ":", "#", "&", "-", "_", ".", ",", "/", "\\", "(", ")", "[", "]", "{", "}", "@", "'", "\"", "+", "!", "~", "*", "—", "…",
    ]
}
