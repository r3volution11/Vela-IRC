// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// "Did you mean …?" suggestions for misspelled names (settings keys,
/// theme tokens).
public enum EditDistance {
    /// Optimal string alignment distance (Levenshtein plus transpositions).
    public static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous2 = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], previous2[j - 2] + 1)
                }
            }
            (previous2, previous, current) = (previous, current, previous2)
        }
        return previous[b.count]
    }

    /// The candidate `text` most likely meant: an exact match ignoring case,
    /// or the closest one within `limit` edits (ignoring case; by default
    /// `max(2, text.count / 4)`). Ties go to the earlier candidate.
    public static func closest(to text: String, in candidates: [String], limit: Int? = nil) -> String? {
        let lowered = text.lowercased()
        if let exact = candidates.first(where: { $0.lowercased() == lowered }) { return exact }
        let limit = limit ?? max(2, text.count / 4)
        var best: (candidate: String, distance: Int)?
        for candidate in candidates {
            let distance = distance(lowered, candidate.lowercased())
            if distance <= limit, distance < best?.distance ?? .max {
                best = (candidate, distance)
            }
        }
        return best?.candidate
    }
}
