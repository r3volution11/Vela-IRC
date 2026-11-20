// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The conversation as the model reads it: one numbered line per message,
/// `[12] nick: text`, or `[13] * nick waves` for an action.
///
/// Numbers start at 1 and map back to ``CatchUpLine/id``, so a topic's
/// `firstLine` can link to its message. Links are reduced to their host
/// (`(link to youtube.com)`), long lines are cut at
/// ``maximumLineLength`` characters, and only the newest
/// ``maximumLines`` lines are kept.
nonisolated struct CatchUpTranscript: Sendable, Equatable {
    struct Entry: Sendable, Equatable {
        /// 1-based, as written in the prompt.
        let number: Int
        let lineID: UUID
        let nick: String
        /// The cleaned message, without number or nick.
        let message: String
        let isAction: Bool
        /// `[12] nick: message`, as in the prompt.
        let text: String
    }

    static let maximumLines = CatchUpRequest.maximumLines
    static let maximumLineLength = 300

    let entries: [Entry]
    /// Lines in the request with something to say, before the cap.
    let availableLines: Int
    let ownNick: String

    init(
        lines: [CatchUpLine],
        ownNick: String,
        maximumLines: Int = Self.maximumLines,
        maximumLineLength: Int = Self.maximumLineLength
    ) {
        let usable = lines.compactMap { line -> (CatchUpLine, String)? in
            let nick = line.nick.trimmingCharacters(in: .whitespaces)
            let text = Self.clean(line.text, maximumLength: maximumLineLength)
            guard !nick.isEmpty, !text.isEmpty else { return nil }
            var copy = line
            copy.nick = nick
            return (copy, text)
        }
        self.availableLines = usable.count
        self.ownNick = ownNick
        self.entries = usable.suffix(max(0, maximumLines)).enumerated().map { offset, pair in
            let (line, text) = pair
            let number = offset + 1
            let rendered = line.isAction ? "[\(number)] * \(line.nick) \(text)" : "[\(number)] \(line.nick): \(text)"
            return Entry(number: number, lineID: line.id, nick: line.nick, message: text, isAction: line.isAction, text: rendered)
        }
    }

    init(_ request: CatchUpRequest) {
        self.init(lines: request.lines, ownNick: request.ownNick)
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Older lines were left out to stay under ``maximumLines``.
    var isCapped: Bool { entries.count < availableLines }

    /// The message behind line `number` of the prompt.
    func lineID(forNumber number: Int) -> UUID? {
        guard number >= 1, number <= entries.count else { return nil }
        return entries[number - 1].lineID
    }

    /// The prompt text for `entries`, one per line.
    static func text<S: Sequence>(of entries: S) -> String where S.Element == Entry {
        entries.map(\.text).joined(separator: "\n")
    }

    var text: String { Self.text(of: entries) }

    /// Everyone who spoke, in order of their first line.
    var nicks: [String] {
        var seen = Set<String>()
        return entries.compactMap { seen.insert($0.nick.lowercased()).inserted ? $0.nick : nil }
    }

    /// `nick` as it's written in the transcript (matched case-insensitively,
    /// ignoring a leading `@`, `+` or similar), or nil when nobody by that
    /// name spoke. Keeps the summary from naming people who weren't there.
    func canonicalNick(_ nick: String) -> String? {
        let trimmed = nick.trimmingCharacters(in: CharacterSet(charactersIn: "~&@%+ \t:,"))
        guard !trimmed.isEmpty else { return nil }
        let key = trimmed.lowercased()
        if let match = entries.first(where: { $0.nick.lowercased() == key }) { return match.nick }
        if !ownNick.isEmpty, key == ownNick.lowercased() { return ownNick }
        return nil
    }

    /// Whether anyone else's line mentions ``ownNick`` (as a whole word).
    var mentionsOwnNick: Bool {
        entries.contains(where: mentionsOwnNick)
    }

    /// Other people's lines that mention ``ownNick``.
    var mentionsOfOwnNick: [Entry] {
        entries.filter(mentionsOwnNick)
    }

    private func mentionsOwnNick(_ entry: Entry) -> Bool {
        guard !ownNick.isEmpty else { return false }
        let own = ownNick.lowercased()
        return entry.nick.lowercased() != own && Self.containsWord(own, in: entry.message.lowercased())
    }

    /// The nicks (other than ``ownNick``) that `text` names, as written
    /// in the transcript.
    func nicksNamed(in text: String) -> [String] {
        let lowered = text.lowercased()
        let own = ownNick.lowercased()
        return nicks.filter { nick in
            let key = nick.lowercased()
            return key != own && Self.containsWord(key, in: lowered)
        }
    }

    /// `text` with every nick written as it is in the transcript: the
    /// model tends to capitalize them at the start of a sentence ("Wren
    /// asked…" for wren).
    func restoringNickCase(in text: String) -> String {
        var result = text
        for nick in nicks + (ownNick.isEmpty ? [] : [ownNick]) {
            let escaped = NSRegularExpression.escapedPattern(for: nick)
            let pattern = "(?<![\\p{L}\\p{N}_\\-\\[\\]\\\\`^{}|])\(escaped)(?![\\p{L}\\p{N}_\\-\\[\\]\\\\`^{}|])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: nick)
            )
        }
        return result
    }

    // MARK: Cleaning

    /// One line of plain text: whitespace collapsed, links reduced to their
    /// host, and at most `maximumLength` characters.
    static func clean(_ text: String, maximumLength: Int = maximumLineLength) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let linked = reducingLinks(in: collapsed)
        guard linked.count > maximumLength else { return linked }
        let cut = linked.prefix(max(1, maximumLength - 1))
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Replaces each URL with `(link to host)`; the path and query are
    /// noise to the model and cost tokens.
    static func reducingLinks(in text: String) -> String {
        guard text.contains("://") || text.localizedCaseInsensitiveContains("www.") else { return text }
        let pattern = /(?i)\b(?:(?:https?|ftp):\/\/|www\.)[^\s<>"]+/
        return text.replacing(pattern) { match in
            // Sentence punctuation after a link isn't part of it.
            var link = Substring(match.output)
            var trailing = ""
            while let last = link.last, ".,;:!?)]'".contains(last) {
                trailing = String(last) + trailing
                link.removeLast()
            }
            return "(link to \(host(of: String(link))))\(trailing)"
        }
    }

    static func host(of link: String) -> String {
        var candidate = link
        if !candidate.contains("://") { candidate = "https://" + candidate }
        guard var host = URL(string: candidate)?.host(percentEncoded: false), !host.isEmpty else { return "a website" }
        host = host.lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Whether `text` contains `word` (both lowercased) as a whole nick.
    static func containsWord(_ word: String, in text: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: word, range: searchRange) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !isNickCharacter(before), !isNickCharacter(after) { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    private static func isNickCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || "_-[]\\`^{}|".contains(character)
    }
}
