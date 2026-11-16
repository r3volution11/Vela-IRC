// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaIRC

/// Tab-completion candidates for the word before the caret. Each candidate is
/// the full replacement text, including any trailing separator.
///
/// - `/com` at the start of a line → `/command ` from `InputCommand.knownCommands`
/// - `#ch` → channels on this network, joined ones first
/// - `:emo` → emoji from `EmojiShortcodes`
/// - anything else → nicks in the buffer, people who spoke most recently
///   first; a nick completed at the start of a line gets `: ` appended.
///   A leading `@` (a Discord/Slack habit) is dropped.
enum TabCompletion {
    /// How far back to look for recent speakers.
    static let recentSpeakerWindow = 500

    static func candidates(
        for word: String,
        atLineStart: Bool,
        buffer: BufferModel,
        session: NetworkSession
    ) -> [String] {
        guard !word.isEmpty else { return [] }

        if word.hasPrefix("/") {
            guard atLineStart, !word.hasPrefix("//") else { return [] }
            let stem = word.dropFirst().lowercased()
            return InputCommand.knownCommands
                .filter { $0.hasPrefix(stem) }
                .map { "/\($0) " }
        }

        if word.hasPrefix(":") {
            guard word.count >= 2 else { return [] }
            return EmojiShortcodes.completions(forPrefix: String(word.dropFirst())).map(\.emoji)
        }

        if session.isupport.isChannel(word) || word.hasPrefix("#") {
            return channelCandidates(prefix: word, session: session)
        }

        return nickCandidates(prefix: word, atLineStart: atLineStart, buffer: buffer, session: session)
    }

    static func channelCandidates(prefix: String, session: NetworkSession) -> [String] {
        let mapping = session.isupport.caseMapping
        let stem = mapping.fold(prefix)
        return session.channels
            .filter { mapping.fold($0.name).hasPrefix(stem) }
            .sorted { lhs, rhs in
                if lhs.isJoined != rhs.isJoined { return lhs.isJoined }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { "\($0.name) " }
    }

    static func nickCandidates(prefix: String, atLineStart: Bool, buffer: BufferModel, session: NetworkSession) -> [String] {
        let mapping = session.isupport.caseMapping
        var stem = prefix
        if stem.hasPrefix("@") { stem.removeFirst() }
        let foldedStem = mapping.fold(stem)
        let selfFolded = mapping.fold(session.nick)

        let pool: [String] = switch buffer.kind {
        case .channel: buffer.members.map(\.nick)
        case .query: [buffer.name]
        case .server: []
        }

        // Rank people by how recently they spoke here.
        var recency: [String: Int] = [:]
        for line in buffer.lines.reversed().prefix(recentSpeakerWindow) {
            guard line.kind.isConversation, !line.isSelf, let nick = line.nick else { continue }
            let folded = mapping.fold(nick)
            if recency[folded] == nil { recency[folded] = recency.count }
        }

        var matches: [(nick: String, folded: String)] = []
        var includesSelf = false
        for nick in pool {
            let folded = mapping.fold(nick)
            guard folded.hasPrefix(foldedStem) else { continue }
            if folded == selfFolded {
                includesSelf = true
            } else {
                matches.append((nick, folded))
            }
        }
        matches.sort { lhs, rhs in
            switch (recency[lhs.folded], recency[rhs.folded]) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.nick.localizedCaseInsensitiveCompare(rhs.nick) == .orderedAscending
            }
        }
        var nicks = matches.map(\.nick)
        // Your own nick is a last resort (people rarely address themselves).
        if includesSelf { nicks.append(session.nick) }
        let suffix = atLineStart ? ": " : " "
        return nicks.map { $0 + suffix }
    }
}
