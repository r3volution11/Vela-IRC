// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaMedia

/// The parts of the composer's text that macOS must never change: autocorrect,
/// text replacements, smart quotes and dashes and Writing Tools all leave
/// them alone, so IRC syntax survives.
///
/// - A leading `/command` (a line starting with `//` is plain text).
/// - The target of `/msg`, `/notice` and `/query`, and the optional channel
///   of `/topic` and `/part`. What follows is prose and stays checkable, as
///   in `/me`, `/say`, `/away` and `/quit`.
/// - Everything after any other command (`/join`, `/mode`, `/kick`…).
/// - Links, `#channels`, member nicks, a `nick: ` address at the start of a
///   line, `:emoji:` codes and `` `code` `` spans.
///
/// Ranges are UTF-16 (`NSRange`), as AppKit uses them. Spans may overlap.
nonisolated struct ProtectedTextRanges: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The `/command` itself.
        case command
        /// Who a `/msg`, `/notice` or `/query` goes to; the channel of `/topic` or `/part`.
        case target
        /// The rest of a command whose arguments aren't prose.
        case arguments
        case link
        case channel
        case nick
        /// `nick:` at the start of a line.
        case address
        /// `:code:`, or a `:code` still being typed.
        case emoji
        /// A `` `code` `` span (to the end of the line while it's unclosed).
        case code

        /// Whether spelling underlines are hidden here too. Command arguments
        /// keep theirs (a kick reason is prose), but the nicks, channels and
        /// links inside them are spans of their own.
        var hidesSpelling: Bool { self != .arguments }
    }

    struct Span: Equatable, Sendable {
        var range: NSRange
        var kind: Kind
    }

    /// Sorted by location.
    private(set) var spans: [Span]

    init(spans: [Span]) {
        self.spans = spans.sorted { ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length) }
    }

    /// Commands whose text after the command (and target) is prose.
    static let proseCommands: Set<String> = [
        "me", "say", "msg", "privmsg", "notice", "query", "q", "away", "topic", "part", "leave", "quit",
    ]
    /// Prose commands whose first argument is always a target.
    static let targetCommands: Set<String> = ["msg", "privmsg", "notice", "query", "q"]
    /// Prose commands whose first argument is a target when it's a channel.
    static let optionalChannelCommands: Set<String> = ["topic", "part", "leave"]

    // MARK: Queries

    /// Whether `range` touches any protected text.
    func intersects(_ range: NSRange) -> Bool {
        spans.contains { Self.overlaps(range, $0.range) }
    }

    /// Whether a spelling underline over `range` should be hidden.
    func hidesSpelling(in range: NSRange) -> Bool {
        spans.contains { $0.kind.hidesSpelling && Self.overlaps(range, $0.range) }
    }

    /// The protected text as sorted, non-overlapping ranges.
    var mergedRanges: [NSRange] {
        var merged: [NSRange] = []
        for span in spans where span.range.length > 0 {
            if let last = merged.last, span.range.location <= NSMaxRange(last) {
                let end = max(NSMaxRange(last), NSMaxRange(span.range))
                merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                merged.append(span.range)
            }
        }
        return merged
    }

    /// The merged ranges clipped to `enclosing` (for Writing Tools).
    func ranges(in enclosing: NSRange) -> [NSRange] {
        mergedRanges.compactMap { range in
            let clipped = NSIntersectionRange(range, enclosing)
            return clipped.length > 0 ? clipped : nil
        }
    }

    /// True when the ranges share at least one character. An empty `a`
    /// counts when it sits strictly inside `b`.
    static func overlaps(_ a: NSRange, _ b: NSRange) -> Bool {
        guard b.length > 0 else { return false }
        if a.length == 0 { return a.location > b.location && a.location < NSMaxRange(b) }
        return a.location < NSMaxRange(b) && b.location < NSMaxRange(a)
    }

    // MARK: Computing

    /// - Parameters:
    ///   - text: The composer's text.
    ///   - nicks: Nicks to protect wherever they appear as whole words.
    ///   - channelTypes: Characters that start a channel name (ISUPPORT CHANTYPES).
    static func compute(text: String, nicks: NickSet, channelTypes: Set<Character> = ["#", "&"]) -> ProtectedTextRanges {
        let string = text as NSString
        var spans: [Span] = []
        let prose = commandSpans(in: string, into: &spans)
        for region in prose {
            addressSpans(in: string, region: region, into: &spans)
        }
        codeSpans(in: string, into: &spans)
        for link in LinkDetector.links(in: text) {
            spans.append(Span(range: NSRange(link.range, in: text), kind: .link))
        }
        channelSpans(in: string, channelTypes: channelTypes, into: &spans)
        emojiSpans(in: string, into: &spans)
        nickSpans(in: string, nicks: nicks, into: &spans)
        return ProtectedTextRanges(spans: spans)
    }

    static func compute(text: String, nicks: [String] = [], channelTypes: Set<Character> = ["#", "&"]) -> ProtectedTextRanges {
        compute(text: text, nicks: NickSet(nicks), channelTypes: channelTypes)
    }

    /// Adds the command spans and returns the prose regions (where a
    /// `nick:` address may start a line).
    private static func commandSpans(in string: NSString, into spans: inout [Span]) -> [NSRange] {
        let length = string.length
        var start = 0
        // Like the input parser: leading newlines don't count.
        while start < length, isNewline(string.character(at: start)) { start += 1 }
        guard start < length, string.character(at: start) == slash else {
            return [NSRange(location: 0, length: length)]
        }
        if start + 1 < length, string.character(at: start + 1) == slash {
            // `//text` sends "/text" as a message.
            return [NSRange(location: start + 1, length: length - start - 1)]
        }
        let commandEnd = wordEnd(in: string, from: start)
        spans.append(Span(range: NSRange(location: start, length: commandEnd - start), kind: .command))
        let name = string.substring(with: NSRange(location: start + 1, length: commandEnd - start - 1)).lowercased()
        let argumentStart = skipSpaces(in: string, from: commandEnd)

        guard proseCommands.contains(name) else {
            if commandEnd < length {
                spans.append(Span(range: NSRange(location: commandEnd, length: length - commandEnd), kind: .arguments))
            }
            return []
        }
        var proseStart = argumentStart
        if argumentStart < length {
            let targetEnd = wordEnd(in: string, from: argumentStart)
            let first = string.character(at: argumentStart)
            let isTarget = targetCommands.contains(name)
                || (optionalChannelCommands.contains(name) && "#&+!".utf16.contains(first))
            if isTarget, targetEnd > argumentStart {
                spans.append(Span(range: NSRange(location: argumentStart, length: targetEnd - argumentStart), kind: .target))
                proseStart = skipSpaces(in: string, from: targetEnd)
            }
        }
        return proseStart < length ? [NSRange(location: proseStart, length: length - proseStart)] : []
    }

    /// `nick:` (followed by a space or the end) at the start of each line in `region`.
    private static func addressSpans(in string: NSString, region: NSRange, into spans: inout [Span]) {
        var lineStart = region.location
        let end = NSMaxRange(region)
        while lineStart < end {
            var index = lineStart
            while index < end, isSpace(string.character(at: index)) { index += 1 }
            var tokenEnd = index
            while tokenEnd < end, isNickCharacter(string.character(at: tokenEnd)) { tokenEnd += 1 }
            if tokenEnd > index, tokenEnd < end, string.character(at: tokenEnd) == colon,
               tokenEnd + 1 == end || isWhitespace(string.character(at: tokenEnd + 1)) {
                spans.append(Span(range: NSRange(location: index, length: tokenEnd + 1 - index), kind: .address))
            }
            // Next line.
            var next = tokenEnd
            while next < end, !isNewline(string.character(at: next)) { next += 1 }
            lineStart = next + 1
        }
    }

    /// `` `code` `` spans, with any number of backticks; an unclosed one runs to the end of its line.
    private static func codeSpans(in string: NSString, into spans: inout [Span]) {
        let length = string.length
        var index = 0
        while index < length {
            guard string.character(at: index) == backtick else {
                index += 1
                continue
            }
            var fenceEnd = index
            while fenceEnd < length, string.character(at: fenceEnd) == backtick { fenceEnd += 1 }
            let fence = fenceEnd - index
            // Find a closing run of the same length.
            var scan = fenceEnd
            var closeEnd: Int?
            var lineEnd = length
            while scan < length {
                let character = string.character(at: scan)
                if fence == 1, isNewline(character) {
                    lineEnd = scan
                    break
                }
                if character == backtick {
                    var runEnd = scan
                    while runEnd < length, string.character(at: runEnd) == backtick { runEnd += 1 }
                    if runEnd - scan == fence {
                        closeEnd = runEnd
                        break
                    }
                    scan = runEnd
                } else {
                    scan += 1
                }
            }
            let end = closeEnd ?? (fence == 1 ? lineEnd : length)
            spans.append(Span(range: NSRange(location: index, length: end - index), kind: .code))
            index = max(end, fenceEnd)
        }
    }

    /// `#channel` (any of `channelTypes`) starting a word, without trailing sentence punctuation.
    private static func channelSpans(in string: NSString, channelTypes: Set<Character>, into spans: inout [Span]) {
        let prefixes = Set(channelTypes.flatMap { String($0).utf16 })
        let length = string.length
        var index = 0
        while index < length {
            let character = string.character(at: index)
            guard prefixes.contains(character), index == 0 || !isWordCharacter(string.character(at: index - 1)) else {
                index += 1
                continue
            }
            var end = index + 1
            while end < length {
                let next = string.character(at: end)
                if isWhitespace(next) || next == comma || next == 0x07 { break }
                end += 1
            }
            while end > index + 1, isTrailingPunctuation(string.character(at: end - 1)) { end -= 1 }
            if end > index + 1 {
                spans.append(Span(range: NSRange(location: index, length: end - index), kind: .channel))
            }
            index = max(end, index + 1)
        }
    }

    /// `:code:` or a `:code` being typed, starting a word.
    private static func emojiSpans(in string: NSString, into spans: inout [Span]) {
        let length = string.length
        var index = 0
        while index < length {
            guard string.character(at: index) == colon, index == 0 || isWhitespace(string.character(at: index - 1)) else {
                index += 1
                continue
            }
            var end = index + 1
            while end < length, isShortcodeCharacter(string.character(at: end)) { end += 1 }
            guard end > index + 1 else {
                index += 1
                continue
            }
            if end < length, string.character(at: end) == colon { end += 1 }
            spans.append(Span(range: NSRange(location: index, length: end - index), kind: .emoji))
            index = end
        }
    }

    /// Whole-word occurrences of `nicks`, ignoring case.
    private static func nickSpans(in string: NSString, nicks: NickSet, into spans: inout [Span]) {
        guard !nicks.isEmpty else { return }
        let length = string.length
        var index = 0
        while index < length {
            guard isNickCharacter(string.character(at: index)) else {
                index += 1
                continue
            }
            var end = index
            while end < length, isNickCharacter(string.character(at: end)) { end += 1 }
            let word = NSRange(location: index, length: end - index)
            if nicks.contains(string.substring(with: word)) {
                spans.append(Span(range: word, kind: .nick))
            } else {
                // "[doug]" or "doug_" when only "doug" is here: try without
                // the bracket and separator characters at either end.
                var start = index, stop = end
                while start < stop, !isAlphanumeric(string.character(at: start)) { start += 1 }
                while stop > start, !isAlphanumeric(string.character(at: stop - 1)) { stop -= 1 }
                let trimmed = NSRange(location: start, length: stop - start)
                if stop > start, trimmed != word, nicks.contains(string.substring(with: trimmed)) {
                    spans.append(Span(range: trimmed, kind: .nick))
                }
            }
            index = end
        }
    }

    // MARK: Characters

    private static let slash: unichar = 0x2F
    private static let colon: unichar = 0x3A
    private static let comma: unichar = 0x2C
    private static let backtick: unichar = 0x60

    private static func wordEnd(in string: NSString, from start: Int) -> Int {
        var end = start
        while end < string.length, !isWhitespace(string.character(at: end)) { end += 1 }
        return end
    }

    private static func skipSpaces(in string: NSString, from start: Int) -> Int {
        var index = start
        while index < string.length, isSpace(string.character(at: index)) { index += 1 }
        return index
    }

    static func isNewline(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x2028 || character == 0x2029
    }

    static func isSpace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09 || character == 0xA0
    }

    static func isWhitespace(_ character: unichar) -> Bool {
        isSpace(character) || isNewline(character)
    }

    /// ASCII letters and digits, and letters and digits of other scripts
    /// (outside the surrogate range, so emoji don't join words).
    static func isAlphanumeric(_ character: unichar) -> Bool {
        switch character {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        case 0x80...:
            guard let scalar = Unicode.Scalar(character) else { return false }
            return CharacterSet.alphanumerics.contains(scalar)
        default: return false
        }
    }

    /// Letters, digits and the special characters IRC allows in nicks
    /// (`[ ] \ ` _ ^ { | } -`). Other scripts count as letters.
    static func isNickCharacter(_ character: unichar) -> Bool {
        switch character {
        case 0x5B, 0x5C, 0x5D, 0x60, 0x5F, 0x5E, 0x7B, 0x7C, 0x7D, 0x2D: true
        default: isAlphanumeric(character)
        }
    }

    private static func isWordCharacter(_ character: unichar) -> Bool {
        isAlphanumeric(character) || character == 0x5F
    }

    private static func isShortcodeCharacter(_ character: unichar) -> Bool {
        switch character {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2B, 0x2D: true // 0-9 A-Z a-z _ + -
        default: false
        }
    }

    /// Sentence punctuation that ends a channel name in prose.
    private static func isTrailingPunctuation(_ character: unichar) -> Bool {
        switch character {
        case 0x2E, 0x2C, 0x3B, 0x3A, 0x21, 0x3F, 0x29, 0x5D, 0x7D, 0x22, 0x27: true // . , ; : ! ? ) ] } " '
        case 0x2026, 0x201D, 0x2019, 0x00BB: true // … ” ’ »
        default: false
        }
    }
}

/// Nicks to protect, matched without regard to case.
nonisolated struct NickSet: Equatable, Sendable {
    private let folded: Set<String>

    init(_ nicks: some Sequence<String>) {
        folded = Set(nicks.lazy.filter { !$0.isEmpty }.map { $0.lowercased() })
    }

    var isEmpty: Bool { folded.isEmpty }

    func contains(_ word: String) -> Bool {
        folded.contains(word.lowercased())
    }
}

// MARK: - Filtering text checking results

/// Drops the text checking results that would change protected text.
nonisolated enum TextCheckingFilter {
    /// Result types that change the text by themselves.
    static let substitutionTypes: NSTextCheckingResult.CheckingType = [.correction, .replacement, .quote, .dash]

    /// - Parameters:
    ///   - results: What the spell checker found.
    ///   - textLength: The text's current UTF-16 length; results that no
    ///     longer fit (the text changed, e.g. it was just sent) are dropped.
    ///   - protected: IRC syntax to leave alone.
    ///   - inserted: Text Vela put there itself (history, completion,
    ///     drafts), which is never corrected either.
    ///   - allowsSubstitutions: False drops every correction, e.g. while
    ///     Writing Tools is working on the text.
    static func filter(
        _ results: [NSTextCheckingResult],
        textLength: Int,
        protected: ProtectedTextRanges,
        inserted: [NSRange] = [],
        allowsSubstitutions: Bool = true
    ) -> [NSTextCheckingResult] {
        results.filter { result in
            let range = result.range
            guard range.location != NSNotFound, NSMaxRange(range) <= textLength else { return false }
            let type = result.resultType
            if substitutionTypes.contains(type) {
                guard allowsSubstitutions else { return false }
                if protected.intersects(range) { return false }
                return !inserted.contains { ProtectedTextRanges.overlaps(range, $0) }
            }
            if type == .spelling {
                return !protected.hidesSpelling(in: range)
            }
            return true
        }
    }
}

// MARK: - Text Vela inserted itself

/// Where the composer's text came from Vela rather than the keyboard
/// (history recall, Tab completion, a restored draft, an edited paste).
/// Automatic corrections never touch it. The ranges follow later edits.
nonisolated struct InsertedTextRanges: Equatable, Sendable {
    private(set) var ranges: [NSRange] = []

    /// Updates the ranges for one edit.
    /// - Parameters:
    ///   - editedRange: The changed characters, in the new text.
    ///   - changeInLength: How much longer the text got (negative when shorter).
    ///   - inserted: Whether Vela made the edit (rather than the user).
    mutating func record(editedRange: NSRange, changeInLength: Int, inserted: Bool) {
        let replaced = NSRange(location: editedRange.location, length: max(0, editedRange.length - changeInLength))
        var updated: [NSRange] = []
        for range in ranges {
            let end = NSMaxRange(range)
            if end <= replaced.location {
                updated.append(range)
            } else if range.location >= NSMaxRange(replaced) {
                updated.append(NSRange(location: range.location + changeInLength, length: range.length))
            } else {
                // Keep what's left on either side of the edit.
                if range.location < replaced.location {
                    updated.append(NSRange(location: range.location, length: replaced.location - range.location))
                }
                if end > NSMaxRange(replaced) {
                    let start = NSMaxRange(editedRange)
                    updated.append(NSRange(location: start, length: end - NSMaxRange(replaced)))
                }
            }
        }
        if inserted, editedRange.length > 0 {
            updated.append(editedRange)
        }
        ranges = Self.merged(updated)
    }

    mutating func removeAll() {
        ranges.removeAll()
    }

    private static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) where range.length > 0 {
            if let last = result.last, range.location <= NSMaxRange(last) {
                let end = max(NSMaxRange(last), NSMaxRange(range))
                result[result.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
