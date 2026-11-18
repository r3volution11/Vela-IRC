// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaIRC

/// A section of the member list: everyone sharing a top membership prefix.
struct MemberGroup: Identifiable, Equatable {
    /// The prefix symbol, or `""` for members without one.
    let id: String
    let title: String
    let members: [Member]

    /// Groups `members` (already sorted by rank, then nick) into rank
    /// sections in `prefixes` order, keeping only nicks containing `filter`.
    /// Runs in one pass, so it stays cheap for channels with thousands of users.
    static func groups(
        for members: [Member],
        prefixes: [(mode: Character, symbol: Character)],
        filter: String = ""
    ) -> [MemberGroup] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        let symbols = prefixes.map(\.symbol)
        var buckets: [[Member]] = Array(repeating: [], count: symbols.count + 1)
        for member in members {
            if !query.isEmpty, member.nick.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                continue
            }
            let index = member.topPrefix.flatMap { symbols.firstIndex(of: $0) } ?? symbols.count
            buckets[index].append(member)
        }
        var groups: [MemberGroup] = []
        for (index, bucket) in buckets.enumerated() where !bucket.isEmpty {
            if index < prefixes.count {
                let prefix = prefixes[index]
                groups.append(MemberGroup(id: String(prefix.symbol), title: title(mode: prefix.mode, symbol: prefix.symbol), members: bucket))
            } else {
                groups.append(MemberGroup(id: "", title: "Members", members: bucket))
            }
        }
        return groups
    }

    /// A readable name for a rank, by mode letter first (servers agree on
    /// those more than on symbols), then by symbol.
    static func title(mode: Character, symbol: Character) -> String {
        switch mode {
        case "q": return "Owners"
        case "a": return "Admins"
        case "o": return "Operators"
        case "h": return "Half-ops"
        case "v": return "Voiced"
        default: break
        }
        switch symbol {
        case "~": return "Owners"
        case "&": return "Admins"
        case "@": return "Operators"
        case "%": return "Half-ops"
        case "+": return "Voiced"
        default: return "Mode +\(mode)"
        }
    }

    /// Singular rank name for VoiceOver, e.g. "operator".
    static func rankName(mode: Character?, symbol: Character?) -> String? {
        guard let mode, let symbol else { return nil }
        switch title(mode: mode, symbol: symbol) {
        case "Owners": return "owner"
        case "Admins": return "admin"
        case "Operators": return "operator"
        case "Half-ops": return "half-op"
        case "Voiced": return "voiced"
        default: return "mode +\(mode)"
        }
    }
}
