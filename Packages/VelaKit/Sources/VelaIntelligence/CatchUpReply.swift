// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization

/// The plain-text reply Catch me up asks Apple Intelligence for, one item
/// per line, and a tolerant parser for it:
///
///     OVERVIEW: redfern and bluejay argued about the minimum wage; maple_ asked you about the polls.
///     TOPIC: [2] | Minimum wage | redfern said a $20 minimum hurts small businesses; bluejay disagreed. | redfern, bluejay
///     YOU: maple_ asked whether ID was ever an issue when you worked the polls.
///
/// A TOPIC starts with the number of the transcript line it starts at,
/// bracketed as the transcript writes it, which links it to that message.
///
/// Text, not guided generation (`@Generable`): Apple Intelligence's safety
/// checks turned down a structured summary of a heated conversation whole,
/// every time, where the same summary asked for as text went through, and
/// only text requests get `.permissiveContentTransformations`. Text is
/// lighter too: no schema in the context, and no constrained decoding.
///
/// The parser takes what models write besides: labels in any case, in
/// bold, after bullets or numbers, or on a line of their own; extra
/// whitespace and blank lines; fields missing, labeled or out of order;
/// line numbers as `12`, `[12]`, `line 12` or `lines 12–15`; a preamble;
/// a refusal written out instead of thrown; and, while streaming, a last
/// line that's still being written.
nonisolated enum CatchUpReply {
    // MARK: Writing

    /// `draft` in the reply format: how a part's digest is shown to the
    /// model when parts are combined.
    static func render(_ draft: CatchUpDraft) -> String {
        var lines: [String] = []
        let overview = oneLine(draft.overview)
        if !overview.isEmpty { lines.append("OVERVIEW: \(overview)") }
        for topic in draft.topics {
            var fields: [String] = []
            if let first = topic.firstLine { fields.append("[\(first)]") }
            fields.append(oneLine(topic.title).replacingOccurrences(of: "|", with: "/"))
            fields.append(oneLine(topic.summary).replacingOccurrences(of: "|", with: "/"))
            if !topic.participants.isEmpty { fields.append(topic.participants.joined(separator: ", ")) }
            lines.append("TOPIC: " + fields.joined(separator: " | "))
        }
        for note in draft.addressedToYou {
            let note = oneLine(note)
            if !note.isEmpty { lines.append("YOU: \(note)") }
        }
        return lines.joined(separator: "\n")
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: Reading

    /// The draft in `text`. While the reply streams (`isComplete` false)
    /// its last line may be unfinished: only the overview is read from
    /// it, so the overview appears as it's written and each topic once
    /// its line is done. Nothing read from a partial reply is missing
    /// from a longer one, and a refusal is never read as an overview.
    ///
    /// - Parameter nicks: Who spoke, to tell a list of nicks from a
    ///   summary when a topic's fields are out of order.
    static func parse(_ text: String, isComplete: Bool = true, nicks: [String] = []) -> CatchUpDraft {
        var reader = Reader(nicks: nicks)
        return reader.read(text, isComplete: isComplete)
    }

    /// Reads a reply as it streams. Each snapshot is the reply so far, so
    /// lines already done are read once and kept: a snapshot costs its new
    /// text and the line being written, not the whole reply again.
    struct Reader: Sendable {
        private let knownNicks: Set<String>
        /// State after the last finished line.
        private var parser: Parser
        /// The text that state was read from: up to its last line break.
        private var consumed = ""

        init(nicks: [String]) {
            knownNicks = Set(nicks.map { $0.lowercased() })
            parser = Parser(knownNicks: knownNicks)
        }

        /// The draft in `text`; see ``CatchUpReply/parse(_:isComplete:nicks:)``.
        mutating func read(_ text: String, isComplete: Bool) -> CatchUpDraft {
            var text = text
            if text.utf8.contains(13) {
                text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            }
            // Not a continuation of the last snapshot: start over.
            if !text.utf8.starts(with: consumed.utf8) {
                parser = Parser(knownNicks: knownNicks)
                consumed = ""
            }
            let resume = text.utf8.index(text.startIndex, offsetBy: consumed.utf8.count)
            var start = resume
            while let newline = text.utf8[start...].firstIndex(of: 10) {
                parser.read(text[start..<newline])
                start = text.utf8.index(after: newline)
            }
            if start != resume { consumed = String(text[..<start]) }

            var draft = parser
            if start < text.endIndex {
                if isComplete { draft.read(text[start...]) } else { draft.readPartial(text[start...]) }
            }
            if !isComplete, isRefusal(draft.draft.overview) { draft.draft.overview = "" }
            return draft.draft
        }
    }

    /// Whether a reply has written more than will be kept: past `topics`
    /// topics, or past ``CatchUpPrompts/maximumMentions`` notes with all
    /// the topics written. Guided generation capped these in its schema; a
    /// text reply is stopped here instead, so it doesn't run on to its
    /// token limit (a digest listing one topic per message, say).
    static func isPastLimits(_ draft: CatchUpDraft, topics limit: Int) -> Bool {
        draft.topics.count > limit || (draft.topics.count >= limit && draft.addressedToYou.count > CatchUpPrompts.maximumMentions)
    }

    /// Nothing to use: no topics, and no overview or one that refuses.
    /// The model wrote a refusal instead of throwing one, or nothing.
    static func isDeclined(_ draft: CatchUpDraft) -> Bool {
        draft.topics.isEmpty && (draft.overview.trimmingCharacters(in: .whitespaces).isEmpty || isRefusal(draft.overview))
    }

    // MARK: Refusals

    private static let refusalOpenings = [
        "i'm sorry", "i am sorry", "sorry,", "sorry but", "sorry, but", "i apologize",
        "i can't", "i cannot", "i can not", "i won't", "i will not", "i must decline",
        "i'm unable", "i am unable", "i'm not able", "i am not able",
        "i'm not comfortable", "i am not comfortable", "as an ai", "unfortunately, i",
    ]

    /// Starts like a refusal ("I'm sorry, but I can't…").
    static func isRefusal(_ text: String) -> Bool {
        let key = refusalKey(text)
        return refusalOpenings.contains { key.hasPrefix($0) }
    }

    /// Could still turn out to be a refusal: so far it's the start of one.
    static func mightBeRefusal(_ text: String) -> Bool {
        let key = refusalKey(text)
        guard !key.isEmpty else { return true }
        return refusalOpenings.contains { key.hasPrefix($0) || $0.hasPrefix(key) }
    }

    private static func refusalKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "’", with: "'")
    }

    // MARK: Labels

    enum Label: Sendable {
        case overview, topic, topics, you
        /// Fields of a topic written on lines of their own.
        case title, summary, participants, line
    }

    private static let labels: [String: Label] = [
        "overview": .overview, "overall": .overview, "tldr": .overview, "tl;dr": .overview, "in short": .overview,
        "topic": .topic, "thread": .topic, "subject": .topic,
        "topics": .topics, "threads": .topics,
        "you": .you, "for you": .you, "to you": .you, "addressed to you": .you, "mention": .you, "mentions": .you, "@you": .you,
        "title": .title,
        "summary": .summary, "what": .summary, "details": .summary, "description": .summary,
        "nicks": .participants, "people": .participants, "participants": .participants, "who": .participants,
        "involved": .participants, "speakers": .participants, "nicks involved": .participants, "people involved": .participants,
        "line": .line, "lines": .line, "first line": .line, "start": .line, "starts": .line, "line number": .line,
    ]

    /// The longest label written before its colon, to tell "TOPIC: …" from
    /// a sentence with a colon in it.
    private static let longestLabel = 24

    /// The label `line` starts with (`OVERVIEW:`, `**Topic 2** -`, a bare
    /// `TOPICS`), and what follows it. A topic's field (`isField`) has a
    /// label only before a colon or dash: a field that's just "Summary."
    /// or "Overview" is a title or a summary.
    static func label(of line: Substring, isField: Bool = false) -> (Label, Substring)? {
        // "LABEL:", or "LABEL -" / "LABEL —".
        var separator: Range<Substring.Index>?
        if let colon = line.firstIndex(of: ":"), line.distance(from: line.startIndex, to: colon) <= longestLabel {
            separator = colon..<line.index(after: colon)
        }
        for dash in [" - ", " – ", " — "] {
            if let range = line.range(of: dash), line.distance(from: line.startIndex, to: range.lowerBound) <= longestLabel,
               separator.map({ range.lowerBound < $0.lowerBound }) ?? true {
                separator = range
            }
        }
        if let separator, let label = knownLabel(line[..<separator.lowerBound]) {
            return (label, line[separator.upperBound...].trimmingCharacters(in: .whitespaces)[...])
        }
        guard !isField else { return nil }
        // A label alone: "TOPICS", "**Overview**".
        if line.count <= longestLabel, let label = knownLabel(line) {
            return (label, "")
        }
        // A capitalized label without a colon: "OVERVIEW kenji and ada…",
        // "TOPIC 2 | …" (where 2 numbers the topic, as in "TOPIC 2:").
        let word = line.prefix { $0.isLetter }
        if word.count >= 3, word.allSatisfy(\.isUppercase), word.endIndex < line.endIndex, line[word.endIndex] == " ",
           let label = labels[word.lowercased()], label == .overview || label == .topic || label == .you {
            var rest = line[word.endIndex...].drop { $0 == " " }
            let ordinal = rest.prefix { $0.isNumber }
            if !ordinal.isEmpty, ordinal.count <= 2 {
                let after = rest[ordinal.endIndex...].drop { $0 == "." || $0 == " " }
                if after.first == "|" || after.first == ":" { rest = after.dropFirst() }
            }
            return (label, rest.trimmingCharacters(in: .whitespaces)[...])
        }
        return nil
    }

    /// The label `text` names, if any. "Line 12" isn't a label but a
    /// title's line number ("Line 12: Minimum wage").
    private static func knownLabel(_ text: Substring) -> Label? {
        guard let label = labels[labelKey(text)] else { return nil }
        if label == .line, text.contains(where: \.isNumber) { return nil }
        return label
    }

    /// `**Topic 2**` → `topic`: markup, numbering and case removed.
    private static func labelKey(_ text: Substring) -> String {
        var key = text.lowercased().filter { !"*_#`[]()".contains($0) }
        key = key.trimmingCharacters(in: .whitespaces)
        // "topic 2", "topic #2", "you 1"
        while let last = key.last, last.isNumber || last == " " || last == "." { key.removeLast() }
        return key.split(separator: " ").joined(separator: " ")
    }

    /// Whether `text`, a line still being written, may be a label not yet
    /// finished ("OVERV", "**TOP"): then it isn't shown yet.
    static func mightBeLabel(_ text: Substring) -> Bool {
        let key = labelKey(text)
        guard !key.isEmpty else { return true }
        return labels.keys.contains { $0.hasPrefix(key) }
    }

    // MARK: Lines

    /// `line` without its bullet or numbering (`- `, `• `, `1. `, `2) `,
    /// `### `, `> `), bold markers and surrounding whitespace. Also says
    /// whether it had a bullet: an unlabeled bulleted line is a list item.
    static func stripMarkers(_ line: Substring) -> (text: Substring, isListItem: Bool) {
        var text = line.trimmingCharacters(in: .whitespaces)[...]
        if text.contains("**") { text = text.replacingOccurrences(of: "**", with: "")[...] }
        var isListItem = false
        while true {
            let before = text
            if let first = text.first, "-*•·+–—>".contains(first) {
                let rest = text.dropFirst()
                if rest.first == " " { text = rest.drop { $0 == " " }; isListItem = true }
            } else if text.first == "#" {
                let rest = text.drop { $0 == "#" }
                if rest.first == " " { text = rest.drop { $0 == " " } }
            } else if let first = text.first, first.isNumber {
                // "1. ", "2) ", but not "12 | Title" or "3 cases".
                let digits = text.prefix { $0.isNumber }
                let rest = text[digits.endIndex...]
                if digits.count <= 2, let mark = rest.first, mark == "." || mark == ")", rest.dropFirst().first == " " {
                    text = rest.dropFirst().drop { $0 == " " }
                    isListItem = true
                }
            }
            if text == before { break }
        }
        return (text, isListItem)
    }

    // MARK: Fields

    /// A topic's fields: split at pipes with a space on either side, so a
    /// nick like `doug|away` stays whole. A reply that never spaces its
    /// pipes is split at every pipe.
    static func fields(_ text: Substring) -> [Substring] {
        var fields: [Substring] = []
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "|" {
                let before = index > text.startIndex ? text[text.index(before: index)] : " "
                let afterIndex = text.index(after: index)
                let after = afterIndex < text.endIndex ? text[afterIndex] : " "
                if before.isWhitespace || after.isWhitespace {
                    fields.append(text[start..<index])
                    start = afterIndex
                }
            }
            index = text.index(after: index)
        }
        fields.append(text[start...])
        if fields.count == 1, text.contains("|") {
            fields = text.split(separator: "|", omittingEmptySubsequences: false)
        }
        var trimmed = fields.map { $0.trimmingCharacters(in: .whitespaces)[...] }
        while trimmed.last?.isEmpty == true { trimmed.removeLast() }
        return trimmed
    }

    /// The line number when `field` is nothing but one: `12`, `[12]`,
    /// `(12)`, `#12`, `L12`, `line 12`, `lines 12–15`, `12-15`.
    static func lineNumber(_ field: Substring) -> Int? {
        var text = field.trimmingCharacters(in: .whitespaces).lowercased()[...]
        if let first = text.first, let last = text.last, (first == "[" && last == "]") || (first == "(" && last == ")") {
            text = text.dropFirst().dropLast()
        }
        text = text.trimmingCharacters(in: .whitespaces)[...]
        for prefix in ["first line", "starts at", "start", "lines", "line", "ln", "l.", "l", "#"] where text.hasPrefix(prefix) {
            let rest = text.dropFirst(prefix.count)
            // "l" and "line" must be followed by the number, not a word ("later").
            guard rest.first.map({ $0.isNumber || $0 == " " || $0 == ":" || $0 == "." || $0 == "#" }) ?? false else { continue }
            text = rest.drop { $0 == " " || $0 == ":" || $0 == "." || $0 == "#" }
            break
        }
        let digits = text.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 6, let number = Int(digits) else { return nil }
        // Nothing after it but a range's end: "12", "12-15", "12 to 15".
        var rest = text[digits.endIndex...].trimmingCharacters(in: .whitespaces)[...]
        for separator in ["-", "–", "—", "to", ","] where rest.hasPrefix(separator) {
            rest = rest.dropFirst(separator.count).drop { $0 == " " }
            rest = rest.drop { $0.isNumber }
            break
        }
        return rest.isEmpty ? number : nil
    }

    /// A title's leading line number: `[12] Title`, `(line 12) Title`,
    /// `line 12: Title`. A bare `12.` is numbering, not a line.
    static func leadingLineNumber(_ text: Substring) -> (Int, Substring)? {
        guard let first = text.first else { return nil }
        if first == "[" || first == "(" {
            let close: Character = first == "[" ? "]" : ")"
            guard let end = text.firstIndex(of: close), let number = lineNumber(text[...end]) else { return nil }
            return (number, text[text.index(after: end)...].drop { " :-–—".contains($0) })
        }
        let lowered = text.lowercased()
        guard lowered.hasPrefix("line ") || lowered.hasPrefix("lines ") else { return nil }
        let end = text.firstIndex { ":|-–—,".contains($0) } ?? text.endIndex
        guard let number = lineNumber(text[..<end]) else { return nil }
        return (number, text[end...].drop { " :-–—,".contains($0) })
    }

    /// Whether `field` is a list of people rather than a sentence: every
    /// word could be a nick, and most are nicks from the transcript.
    static func isNickList(_ field: Substring, knownNicks: Set<String>) -> Bool {
        guard !knownNicks.isEmpty else { return false }
        let items = nickItems(field)
        guard !items.isEmpty, items.count <= 12 else { return false }
        guard items.allSatisfy({ $0.allSatisfy(isNickCharacter) }) else { return false }
        let known = items.count { knownNicks.contains($0.lowercased()) }
        return known * 2 > items.count
    }

    /// `kenji, @ada and wren.` → kenji, ada, wren.
    static func nickItems(_ field: Substring) -> [Substring] {
        field
            .split { $0 == "," || $0 == ";" || $0 == "/" || $0 == "&" || $0.isWhitespace }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "~&@%+.!?:\"'“”()*")) [...] }
            .filter { !$0.isEmpty && $0.lowercased() != "and" }
    }

    private static func isNickCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "_-[]\\`^{}|".contains(character)
    }

    private static let preambleOpenings = [
        "here's", "here is", "here are", "sure", "certainly", "of course", "okay", "ok,", "ok.", "below is", "the following",
    ]

    private static let emptyNotes: Set<String> = ["none", "n/a", "na", "nobody", "no one", "nothing", "-", "—", "(none)", "none."]

    // MARK: Cleaning

    /// Model text as shown: bold markers, backticks and line references
    /// (`[12]`, `(lines 3–5)`) removed, whitespace collapsed.
    static func clean(_ text: Substring) -> String {
        var result = String(text)
        if result.contains("**") { result = result.replacingOccurrences(of: "**", with: "") }
        if result.contains("`") { result = result.replacingOccurrences(of: "`", with: "") }
        result = removingLineReferences(result)
        if result.contains("  ") { result = result.split(separator: " ").joined(separator: " ") }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// `text` without bracketed line references: "kenji [12] said" →
    /// "kenji said".
    static func removingLineReferences(_ text: String) -> String {
        guard text.contains("[") || text.contains("(") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "[" || character == "(" {
                let close: Character = character == "[" ? "]" : ")"
                // "[12]" is a line; "(1996)" may be anything, "(line 12)" is one.
                if let end = text[index...].firstIndex(of: close), lineNumber(text[index...end]) != nil,
                   character == "[" || text[text.index(after: index)..<end].contains(where: \.isLetter) {
                    while result.last == " " { result.removeLast() }
                    index = text.index(after: end)
                    // "said [12]." → "said."
                    if index < text.endIndex, !".,;:!?".contains(text[index]), !result.isEmpty { result.append(" ") }
                    continue
                }
            }
            result.append(character)
            index = text.index(after: index)
        }
        return result
    }

    /// A title as shown: also without quotes, trailing punctuation or
    /// surrounding emphasis.
    static func cleanTitle(_ text: Substring) -> String {
        var title = clean(text)
        let wrappers = CharacterSet(charactersIn: "\"“”'*_")
        title = title.trimmingCharacters(in: wrappers).trimmingCharacters(in: .whitespaces)
        while let last = title.last, ".:;,".contains(last) { title.removeLast() }
        return title.trimmingCharacters(in: .whitespaces)
    }

    /// Partial text as shown while streaming: up to any bracket that's
    /// still open (it may turn out to be a line reference, which is
    /// removed), without trailing emphasis markers.
    static func cleanPartial(_ text: Substring) -> String {
        var cut = text
        if let open = cut.lastIndex(where: { $0 == "[" || $0 == "(" }) {
            let close: Character = cut[open] == "[" ? "]" : ")"
            if !cut[open...].contains(close) { cut = cut[..<open] }
        }
        var result = clean(cut)
        while let last = result.last, "*_`".contains(last) { result.removeLast() }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Parser

    private struct Parser {
        let knownNicks: Set<String>
        var draft = CatchUpDraft()
        var section = Section.start
        /// The last topic can still take fields on lines of their own.
        var topicIsOpen = false

        enum Section {
            /// Nothing read yet.
            case start
            case overview
            /// A `TOPICS` heading: the lines after it are topics.
            case topics
            /// After a `TOPIC` line.
            case topic
            case you
        }

        mutating func read(_ raw: Substring) {
            let (line, isListItem) = stripMarkers(raw)
            guard line.contains(where: { $0.isLetter || $0.isNumber }) else { return }
            if let (label, content) = label(of: line) {
                read(label: label, content: content)
                return
            }
            // An unlabeled line.
            let hasPipes = line.contains("|")
            switch section {
            case .start, .overview:
                if hasPipes || (isListItem && !draft.overview.isEmpty) {
                    addTopic(line)
                } else if line.hasSuffix(":") || (section == .start && isPreamble(line)) {
                    // A preamble or heading: "Here's the summary:", "Part 2, lines 41–80:".
                    return
                } else if draft.topics.isEmpty {
                    addOverview(line)
                }
            case .topics:
                addTopic(line)
            case .topic:
                if hasPipes || isListItem {
                    addTopic(line)
                } else if topicIsOpen, let last = draft.topics.indices.last, draft.topics[last].summary.isEmpty, !line.hasSuffix(":") {
                    draft.topics[last].summary = clean(line)
                }
            case .you:
                if !line.hasSuffix(":") { addNote(line) }
            }
        }

        mutating func read(label: Label, content: Substring) {
            switch label {
            case .overview:
                section = .overview
                topicIsOpen = false
                if !content.isEmpty, draft.topics.isEmpty { addOverview(content) }
            case .topic, .topics:
                if content.isEmpty {
                    section = .topics
                    topicIsOpen = false
                } else {
                    addTopic(content)
                }
            case .you:
                section = .you
                topicIsOpen = false
                if !content.isEmpty { addNote(content) }
            case .title:
                if !content.isEmpty { addTopic(content, titleOnly: true) }
            case .summary:
                if topicIsOpen, let last = draft.topics.indices.last, draft.topics[last].summary.isEmpty {
                    draft.topics[last].summary = clean(content)
                } else if draft.overview.isEmpty, draft.topics.isEmpty, !content.isEmpty {
                    section = .overview
                    addOverview(content)
                }
            case .participants:
                if topicIsOpen, let last = draft.topics.indices.last, draft.topics[last].participants.isEmpty {
                    draft.topics[last].participants = nickItems(content).map(String.init)
                }
            case .line:
                if topicIsOpen, let last = draft.topics.indices.last, draft.topics[last].firstLine == nil {
                    draft.topics[last].firstLine = lineNumber(content) ?? leadingLineNumber(content)?.0
                }
            }
        }

        /// The last line, still being written: only the overview grows
        /// from it.
        mutating func readPartial(_ raw: Substring) {
            let (line, isListItem) = stripMarkers(raw)
            guard !line.isEmpty else { return }
            if let (label, content) = label(of: line) {
                guard label == .overview || (label == .summary && draft.overview.isEmpty && draft.topics.isEmpty) else { return }
                guard draft.topics.isEmpty, !content.isEmpty else { return }
                addPartialOverview(content)
                return
            }
            // The overview on the line after its label. A further line
            // shows once it's done: it may be a heading.
            guard section == .overview, draft.overview.isEmpty, !isListItem, !line.contains("|"), !mightBeLabel(line) else { return }
            addPartialOverview(line)
        }

        /// "Sure! Here's the summary.", "Part 2 (lines 41–80)".
        private func isPreamble(_ line: Substring) -> Bool {
            let key = refusalKey(String(line))
            if key.hasPrefix("part "), key.dropFirst(5).first?.isNumber == true { return true }
            return preambleOpenings.contains { key.hasPrefix($0) }
        }

        private mutating func addOverview(_ text: Substring) {
            let sentence = clean(beforeFields(text))
            guard !sentence.isEmpty else { return }
            draft.overview = draft.overview.isEmpty ? sentence : draft.overview + " " + sentence
            section = .overview
        }

        /// An overview or note written like a topic ("OVERVIEW: … | … |
        /// kenji") keeps its first part.
        private func beforeFields(_ text: Substring) -> Substring {
            guard let pipe = text.range(of: " |") else { return text }
            return text[..<pipe.lowerBound]
        }

        private mutating func addPartialOverview(_ text: Substring) {
            let partial = cleanPartial(beforeFields(text))
            guard !partial.isEmpty else { return }
            // Hold back what may become "I'm sorry, but…".
            if draft.overview.isEmpty, mightBeRefusal(partial) { return }
            draft.overview = draft.overview.isEmpty ? partial : draft.overview + " " + partial
        }

        private mutating func addNote(_ text: Substring) {
            let note = clean(beforeFields(text))
            guard !note.isEmpty, !emptyNotes.contains(note.lowercased()) else { return }
            draft.addressedToYou.append(note)
        }

        private mutating func addTopic(_ text: Substring, titleOnly: Bool = false) {
            var topic = CatchUpDraft.Topic(title: "")
            var unlabeled: [Substring] = []
            let parts = titleOnly ? [text] : fields(text)
            for field in parts {
                if !titleOnly, let (label, value) = label(of: field, isField: true) {
                    switch label {
                    case .title: topic.title = cleanTitle(value)
                    case .summary: topic.summary = clean(value)
                    case .participants: topic.participants = nickItems(value).map(String.init)
                    case .line: topic.firstLine = topic.firstLine ?? lineNumber(value) ?? leadingLineNumber(value)?.0
                    case .overview, .topic, .topics, .you: unlabeled.append(value)
                    }
                    continue
                }
                if topic.firstLine == nil, parts.count > 1, let number = lineNumber(field) {
                    topic.firstLine = number
                    continue
                }
                unlabeled.append(field)
            }

            if topic.title.isEmpty, var first = unlabeled.first {
                unlabeled.removeFirst()
                if let (number, rest) = leadingLineNumber(first) {
                    topic.firstLine = topic.firstLine ?? number
                    first = rest
                }
                // One field: "Title: what was said", "Title — what was said".
                if unlabeled.isEmpty, topic.summary.isEmpty, parts.count == 1 {
                    let (title, summary) = splitTitle(first)
                    first = title
                    if let summary { unlabeled.append(summary) }
                }
                topic.title = cleanTitle(first)
            }
            unlabeled.removeAll { $0.isEmpty }

            // The rest: a summary and who took part, in either order.
            if !unlabeled.isEmpty {
                let nickIndex = topic.participants.isEmpty
                    ? unlabeled.lastIndex { isNickList($0, knownNicks: knownNicks) } ?? (unlabeled.count >= 2 ? unlabeled.count - 1 : nil)
                    : nil
                if let nickIndex {
                    topic.participants = nickItems(unlabeled[nickIndex]).map(String.init)
                    unlabeled.remove(at: nickIndex)
                }
                if topic.summary.isEmpty, !unlabeled.isEmpty {
                    topic.summary = clean(unlabeled.joined(separator: " ")[...])
                }
            }
            // "…said it landed (kenji, ada)."
            if topic.participants.isEmpty, let (summary, nicks) = trailingNicks(topic.summary) {
                topic.summary = summary
                topic.participants = nicks
            }
            topic.participants = Array(topic.participants.prefix(CatchUpPrompts.maximumParticipants * 2))

            section = .topic
            guard !topic.title.isEmpty else {
                topicIsOpen = false
                return
            }
            // A topic written twice (merges repeat them) is kept once.
            guard !draft.topics.contains(where: { $0.title.lowercased() == topic.title.lowercased() }) else {
                topicIsOpen = false
                return
            }
            draft.topics.append(topic)
            topicIsOpen = true
        }

        /// "Title: summary" when the part before the colon or dash reads
        /// like a title (a few words).
        private func splitTitle(_ text: Substring) -> (Substring, Substring?) {
            for separator in [": ", " — ", " – ", " - "] {
                guard let range = text.range(of: separator) else { continue }
                let title = text[..<range.lowerBound]
                let summary = text[range.upperBound...]
                if title.split(separator: " ").count <= 8, !summary.isEmpty { return (title, summary) }
            }
            return (text, nil)
        }

        /// A summary that ends with "(kenji, ada)": the summary, and the nicks.
        private func trailingNicks(_ summary: String) -> (String, [String])? {
            var text = summary[...]
            while let last = text.last, ".".contains(last) { text.removeLast() }
            guard text.last == ")", let open = text.lastIndex(of: "(") else { return nil }
            let inside = text[text.index(after: open)..<text.index(before: text.endIndex)]
            guard isNickList(inside, knownNicks: knownNicks) else { return nil }
            var rest = String(text[..<open]).trimmingCharacters(in: .whitespaces)
            if let last = summary.trimmingCharacters(in: .whitespaces).last, last == ".", !rest.hasSuffix(".") { rest += "." }
            return (rest, nickItems(inside).map(String.init))
        }
    }
}

/// Watches one streamed reply for ``CatchUpReply/isPastLimits(_:topics:)``,
/// reading each snapshot incrementally: what a digest request stops on.
nonisolated final class CatchUpReplyLimit: Sendable {
    private let reader: Mutex<CatchUpReply.Reader>
    private let topics: Int

    init(nicks: [String], topics: Int) {
        reader = Mutex(CatchUpReply.Reader(nicks: nicks))
        self.topics = topics
    }

    /// Whether `reply`, the reply so far, has written all that's kept.
    @Sendable func isReached(_ reply: String) -> Bool {
        let draft = reader.withLock { $0.read(reply, isComplete: false) }
        return CatchUpReply.isPastLimits(draft, topics: topics)
    }
}
