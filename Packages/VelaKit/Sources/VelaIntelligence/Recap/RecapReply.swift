// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization

/// A Recap as Apple Intelligence writes it, before the engine ties its
/// line numbers to messages. Line numbers are the transcript's; topic
/// references (`T3`) are the merge prompt's.
nonisolated struct RecapDraft: Sendable, Equatable {
    struct Topic: Sendable, Equatable {
        /// `[17-42]`: the transcript lines it covers.
        var lines: ClosedRange<Int>?
        /// `T2, T5`: the parts' topics a merged topic combines.
        var parts: [Int] = []
        var title: String
        var summary: String = ""
        var participants: [String] = []
    }

    struct Note: Sendable, Equatable {
        var kind: RecapNote.Kind
        var line: Int?
        var text: String
        var owner: String?
    }

    struct YouNote: Sendable, Equatable {
        var line: Int?
        var nick: String?
        var text: String
    }

    var overview: [String] = []
    var topics: [Topic] = []
    var notes: [Note] = []
    var you: [YouNote] = []
    /// More detail's bullets.
    var points: [String] = []

    var isEmpty: Bool {
        overview.isEmpty && topics.isEmpty && notes.isEmpty && you.isEmpty && points.isEmpty
    }
}

/// Reads the plain-text reply a Recap asks for (see ``RecapPrompts``), one
/// item per line:
///
///     OVERVIEW: kenji landed the theme engine; wren is waiting on your review.
///     TOPIC: [2-9] | Theme engine | It's on main, down to the title bar. | kenji, ada
///     DECISION: [14] | The rail's width is remembered globally.
///     QUESTION: [20] | Does the Ocean theme ship in the next build?
///     TODO: [21] | priya | review the contrast pass tonight
///     YOU: [12] | wren | asked you to review the sidebar rail PR
///     POINT: kenji said every surface reads from tokens now.
///
/// As tolerant as ``CatchUpReply``, whose helpers it uses: labels in any
/// case, bold or after bullets; fields missing or out of order; line
/// numbers as `[12]`, `12`, `line 12` or ranges like `[12-40]`; a
/// preamble; and, while streaming, a last line still being written (only
/// finished lines are read, so nothing read is ever taken back).
nonisolated enum RecapReply {
    enum Label: Sendable {
        case overview, topic, decision, question, followUp, you, point
    }

    private static let labels: [String: Label] = [
        "overview": .overview, "summary": .overview, "tldr": .overview, "tl;dr": .overview, "in short": .overview, "highlights": .overview,
        "topic": .topic, "thread": .topic, "subject": .topic,
        "decision": .decision, "decisions": .decision, "decided": .decision, "agreed": .decision, "agreement": .decision,
        "question": .question, "questions": .question, "open question": .question, "open": .question, "unanswered": .question,
        "todo": .followUp, "to do": .followUp, "to-do": .followUp, "follow-up": .followUp, "follow up": .followUp,
        "followup": .followUp, "action": .followUp, "action item": .followUp, "task": .followUp, "will do": .followUp,
        "you": .you, "for you": .you, "to you": .you, "mention": .you, "mentions": .you, "@you": .you,
        "point": .point, "points": .point, "detail": .point, "details": .point,
    ]

    private static let longestLabel = 16

    /// The draft in `text`. Unless `isComplete`, its last line may still be
    /// being written and is left for the next snapshot.
    ///
    /// - Parameters:
    ///   - nicks: Who spoke, to tell a list of nicks from a sentence.
    ///   - bulletsArePoints: Unlabeled bullets are points (More detail).
    static func parse(_ text: String, isComplete: Bool = true, nicks: [String] = [], bulletsArePoints: Bool = false) -> RecapDraft {
        var reader = Reader(nicks: nicks, bulletsArePoints: bulletsArePoints)
        return reader.read(text, isComplete: isComplete)
    }

    /// Reads a streamed reply snapshot by snapshot, each finished line once.
    ///
    /// Lines are gathered into items first: a labeled line starts one; an
    /// unlabeled line that looks like another item of the same kind
    /// (`[4] | Ocean theme | …`, as models write a list after one label)
    /// starts another; and any other unlabeled line continues the item
    /// before it (a topic's summary on a line of its own). The item still
    /// open is read as it is so far, so it shows while it's written.
    struct Reader: Sendable {
        private let knownNicks: Set<String>
        private let bulletsArePoints: Bool
        /// The items that are finished.
        private var draft = RecapDraft()
        /// The item still open: its label and its lines so far.
        private var open: (label: Label, content: String)?
        /// The text read so far: up to its last line break.
        private var consumed = ""

        init(nicks: [String], bulletsArePoints: Bool = false) {
            knownNicks = Set(nicks.map { $0.lowercased() })
            self.bulletsArePoints = bulletsArePoints
        }

        mutating func read(_ text: String, isComplete: Bool) -> RecapDraft {
            // Not a continuation of the last snapshot: start over.
            if !text.utf8.starts(with: consumed.utf8) {
                draft = RecapDraft()
                open = nil
                consumed = ""
            }
            let utf8 = text.utf8
            let resume = utf8.index(utf8.startIndex, offsetBy: consumed.utf8.count)
            var start = resume
            while let newline = utf8[start...].firstIndex(where: { $0 == 10 || $0 == 13 }) {
                if newline > start { readLine(String(text[start..<newline])) }
                start = utf8.index(after: newline)
            }
            if start != resume { consumed = String(text[..<start]) }
            var snapshot = self
            if isComplete, start < text.endIndex { snapshot.readLine(String(text[start...])) }
            snapshot.close()
            return snapshot.draft
        }

        private mutating func readLine(_ raw: String) {
            let (text, _) = CatchUpReply.stripMarkers(raw[...])
            guard !text.isEmpty, !RecapReply.isClosing(text) else { return }
            if let (label, content) = RecapReply.label(of: text) {
                close()
                open = (label, String(content))
            } else if let current = open?.label {
                if current == .overview || current == .point || RecapReply.looksLikeItem(text) {
                    close()
                    open = (current, String(text))
                } else {
                    open?.content += " | " + text
                }
            } else if bulletsArePoints, !RecapReply.isPreamble(text), !CatchUpReply.isRefusal(String(text)) {
                // More detail's points written as plain bullets or lines.
                add(.point, text)
            }
        }

        /// Reads the open item into the draft.
        private mutating func close() {
            guard let item = open else { return }
            open = nil
            add(item.label, item.content[...])
        }

        private mutating func add(_ label: Label, _ content: Substring) {
            let content = content.trimmingCharacters(in: .whitespaces)[...]
            guard !content.isEmpty else { return }
            switch label {
            case .overview:
                let text = CatchUpReply.clean(beforeFields(content))
                guard !text.isEmpty, !CatchUpReply.isRefusal(text) else { return }
                draft.overview.append(text)
            case .point:
                let text = CatchUpReply.clean(content)
                guard !text.isEmpty, !CatchUpReply.isRefusal(text) else { return }
                draft.points.append(text)
            case .topic:
                if let topic = RecapReply.topic(content, knownNicks: knownNicks) { draft.topics.append(topic) }
            case .decision, .question, .followUp:
                let kind: RecapNote.Kind = label == .decision ? .decision : label == .question ? .question : .followUp
                if let note = RecapReply.note(kind, content, knownNicks: knownNicks) { draft.notes.append(note) }
            case .you:
                if let note = RecapReply.you(content, knownNicks: knownNicks) { draft.you.append(note) }
            }
        }

        /// An overview written like a topic keeps its first part.
        private func beforeFields(_ text: Substring) -> Substring {
            let fields = CatchUpReply.fields(text)
            return fields.count > 1 ? (fields.first { RecapReply.lineRange($0) == nil } ?? text) : text
        }
    }

    // MARK: Labels

    /// The label `line` starts with ("TOPIC:", "**Decision** -", "TODO 2:")
    /// and what follows it.
    static func label(of line: Substring) -> (Label, Substring)? {
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
        if let separator, let label = labels[key(line[..<separator.lowerBound])] {
            return (label, line[separator.upperBound...])
        }
        // A capitalized label without a colon: "TOPIC [2-9] | …".
        let word = line.prefix { $0.isLetter || $0 == "-" }
        if word.count >= 3, word.allSatisfy({ $0.isUppercase || $0 == "-" }), word.endIndex < line.endIndex,
           line[word.endIndex] == " ", let label = labels[word.lowercased()] {
            return (label, line[word.endIndex...].drop { $0 == " " })
        }
        return nil
    }

    /// `**Topic 2**` → `topic`.
    private static func key(_ text: Substring) -> String {
        var key = text.lowercased().filter { !"*_#`[]()".contains($0) }
        key = key.trimmingCharacters(in: .whitespaces)
        while let last = key.last, last.isNumber || last == " " || last == "." { key.removeLast() }
        return key.split(separator: " ").joined(separator: " ")
    }

    private static let preambles = ["here's", "here is", "here are", "sure", "certainly", "of course", "okay", "ok,", "below", "the following"]

    private static let closings = ["let me know", "i hope", "hope this", "note:", "please note", "feel free"]

    /// "Let me know if…": a closing line, not part of an item.
    static func isClosing(_ text: Substring) -> Bool {
        let lowered = text.lowercased()
        return closings.contains { lowered.hasPrefix($0) }
    }

    /// An unlabeled line that's an item of its own: it starts with a line
    /// number (`[4] | Ocean theme | …`) or has a topic's pipes.
    static func looksLikeItem(_ text: Substring) -> Bool {
        if text.first == "[", CatchUpReply.leadingLineNumber(text) != nil || lineRange(CatchUpReply.fields(text).first ?? "") != nil { return true }
        return CatchUpReply.fields(text).count >= 3
    }

    static func isPreamble(_ text: Substring) -> Bool {
        let lowered = text.lowercased()
        return preambles.contains { lowered.hasPrefix($0) } && (lowered.hasSuffix(":") || lowered.count < 60)
    }

    // MARK: Fields

    /// `[17-42]`, `17–42`, `lines 17 to 42`, `[17]`, `(line 17)`: the lines
    /// a field names, when that's all it is.
    static func lineRange(_ field: Substring) -> ClosedRange<Int>? {
        var text = field.trimmingCharacters(in: .whitespaces).lowercased()[...]
        if let first = text.first, let last = text.last, (first == "[" && last == "]") || (first == "(" && last == ")") {
            text = text.dropFirst().dropLast()
        }
        text = text.trimmingCharacters(in: .whitespaces)[...]
        for prefix in ["lines", "line", "ln", "l"] where text.hasPrefix(prefix) {
            let rest = text.dropFirst(prefix.count)
            guard rest.first.map({ $0.isNumber || $0 == " " || $0 == ":" || $0 == "." }) ?? false else { continue }
            text = rest.drop { $0 == " " || $0 == ":" || $0 == "." }
            break
        }
        let first = text.prefix { $0.isNumber }
        guard !first.isEmpty, first.count <= 6, let start = Int(first) else { return nil }
        var rest = text[first.endIndex...].trimmingCharacters(in: .whitespaces)[...]
        guard !rest.isEmpty else { return start...start }
        var matched = false
        for separator in ["-", "–", "—", "to", "..", ",", "through"] where rest.hasPrefix(separator) {
            rest = rest.dropFirst(separator.count).drop { $0 == " " }
            matched = true
            break
        }
        guard matched else { return nil }
        if rest.hasPrefix("l") { rest = rest.drop { $0.isLetter || $0 == " " } }
        let second = rest.prefix { $0.isNumber }
        guard !second.isEmpty, second.count <= 6, let end = Int(second),
              rest[second.endIndex...].trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return min(start, end)...max(start, end)
    }

    /// `T2, T5`, `[T2 and T5]`, `t3`: the topic references in a field,
    /// when that's all it is. Bare numbers count too (`2, 5`).
    static func topicReferences(_ field: Substring) -> [Int]? {
        let text = field.trimmingCharacters(in: CharacterSet(charactersIn: " []()")).lowercased()
        guard !text.isEmpty else { return nil }
        var numbers: [Int] = []
        var hasT = false
        for token in text.split(whereSeparator: { ", ;/&+".contains($0) }) {
            var token = token[...]
            if token == "and" { continue }
            if token.hasPrefix("topic") { token = token.dropFirst(5) }
            if token.hasPrefix("t") { token = token.dropFirst(); hasT = true }
            if token.hasPrefix("#") { token = token.dropFirst() }
            guard !token.isEmpty, token.allSatisfy(\.isNumber), let number = Int(token) else { return nil }
            numbers.append(number)
        }
        guard !numbers.isEmpty, hasT || numbers.count >= 1 else { return nil }
        return numbers
    }

    /// One TOPIC line: a reference (lines, or parts' topics), a title, a
    /// summary and who took part, in whatever order they came.
    static func topic(_ content: Substring, knownNicks: Set<String>) -> RecapDraft.Topic? {
        var fields = CatchUpReply.fields(content)
        var topic = RecapDraft.Topic(title: "")
        // "Title | [4] | …": the number written after the title.
        if let index = fields.indices.dropFirst().first(where: { lineRange(fields[$0]) != nil }), lineRange(fields[0]) == nil {
            topic.lines = lineRange(fields[index])
            fields.remove(at: index)
        }
        if topic.lines == nil, let first = fields.first {
            if let range = lineRange(first) {
                topic.lines = range
                fields.removeFirst()
            } else if first.lowercased().contains("t"), let parts = topicReferences(first) {
                topic.parts = parts
                fields.removeFirst()
            } else if let leading = leadingReference(first) {
                topic.lines = leading.range
                topic.parts = leading.parts
                fields[0] = leading.rest
            }
        }
        fields = fields.filter { !$0.isEmpty }
        // A transcript line copied out ("kenji: the theme engine landed"),
        // or a run of them, isn't a topic.
        guard fields.count <= 6, let firstField = fields.first, !isCopiedLine(firstField, knownNicks: knownNicks) else { return nil }
        let nickLists = fields.indices.filter { CatchUpReply.isNickList(fields[$0], knownNicks: knownNicks) }
        if let last = nickLists.last, fields.count > 1 {
            topic.participants = CatchUpReply.nickItems(fields[last]).map(String.init)
            for index in nickLists.reversed() where index > 0 { fields.remove(at: index) }
        }
        guard let titleField = fields.first else { return nil }
        if fields.count == 1, let colon = titleField.firstIndex(of: ":"),
           titleField[..<colon].split(separator: " ").count <= 8, titleField.index(after: colon) < titleField.endIndex {
            topic.title = CatchUpReply.cleanTitle(titleField[..<colon])
            topic.summary = CatchUpReply.clean(titleField[titleField.index(after: colon)...])
        } else {
            topic.title = CatchUpReply.cleanTitle(titleField)
            topic.summary = fields.dropFirst().map { CatchUpReply.clean($0) }.filter { !$0.isEmpty }.joined(separator: " ")
        }
        guard !topic.title.isEmpty, !CatchUpReply.isRefusal(topic.title) else { return nil }
        return topic
    }

    /// `[12-20] Title` or `T2, T4: Title`: a reference written before the
    /// title, without a pipe between.
    private static func leadingReference(_ field: Substring) -> (range: ClosedRange<Int>?, parts: [Int], rest: Substring)? {
        guard let first = field.first else { return nil }
        // "T1: Greetings", "T2, T5 - Release".
        if first == "T" || first == "t", field.dropFirst().first?.isNumber == true {
            let end = field.firstIndex(of: ":") ?? field.range(of: " - ")?.lowerBound ?? field.range(of: " – ")?.lowerBound
            if let end, let parts = topicReferences(field[..<end]) {
                return (nil, parts, field[end...].drop { " :-–—".contains($0) })
            }
        }
        if first == "[" || first == "(" {
            let close: Character = first == "[" ? "]" : ")"
            guard let end = field.firstIndex(of: close) else { return nil }
            let inside = field[...end]
            let rest = field[field.index(after: end)...].drop { " :-–—".contains($0) }
            if let range = lineRange(inside) { return (range, [], rest) }
            if let parts = topicReferences(inside), inside.lowercased().contains("t") { return (nil, parts, rest) }
        }
        return nil
    }

    /// A DECISION, QUESTION or TODO line: a line number, maybe who (for a
    /// follow-up), and the text.
    static func note(_ kind: RecapNote.Kind, _ content: Substring, knownNicks: Set<String>) -> RecapDraft.Note? {
        var fields = CatchUpReply.fields(content)
        var line: Int?
        if let first = fields.first, let range = lineRange(first) {
            line = range.lowerBound
            fields.removeFirst()
        } else if let first = fields.first, let (number, rest) = CatchUpReply.leadingLineNumber(first) {
            line = number
            fields[0] = rest
        }
        var owner: String?
        if fields.count > 1, let index = fields.firstIndex(where: { isSingleNick($0, knownNicks: knownNicks) }) {
            owner = CatchUpReply.nickItems(fields[index]).first.map(String.init)
            fields.remove(at: index)
        }
        // "… | ada, kenji": who said it, not what.
        if fields.count > 1 { fields.removeAll { CatchUpReply.isNickList($0, knownNicks: knownNicks) } }
        let text = noteText(fields, knownNicks: knownNicks)
        guard !text.isEmpty, !CatchUpReply.isRefusal(text), !isNothing(text),
              !CatchUpReply.isNickList(text[...], knownNicks: knownNicks)
        else { return nil }
        // Only a follow-up has someone to do it.
        return RecapDraft.Note(kind: kind, line: line, text: text, owner: kind == .followUp ? owner : nil)
    }

    /// A YOU line: a line number, who, and what they want.
    static func you(_ content: Substring, knownNicks: Set<String>) -> RecapDraft.YouNote? {
        var fields = CatchUpReply.fields(content)
        var line: Int?
        if let first = fields.first, let range = lineRange(first) {
            line = range.lowerBound
            fields.removeFirst()
        } else if let first = fields.first, let (number, rest) = CatchUpReply.leadingLineNumber(first) {
            line = number
            fields[0] = rest
        }
        var nick: String?
        if fields.count > 1, let index = fields.firstIndex(where: { isSingleNick($0, knownNicks: knownNicks) }) {
            nick = CatchUpReply.nickItems(fields[index]).first.map(String.init)
            fields.remove(at: index)
        }
        let text = noteText(fields.filter { !isSingleNick($0, knownNicks: knownNicks) }, knownNicks: knownNicks)
        // "wren asked you…" with the nick written into the sentence.
        if nick == nil, let first = text.split(separator: " ").first, knownNicks.contains(first.lowercased()) {
            nick = String(first)
        }
        guard !text.isEmpty, !CatchUpReply.isRefusal(text), !isNothing(text) else { return nil }
        return RecapDraft.YouNote(line: line, nick: nick, text: text)
    }

    /// A note's words: its first field when the reply ran several together
    /// (copied lines, often), without a copied line's "[12] nick: ".
    private static func noteText(_ fields: [Substring], knownNicks: Set<String>) -> String {
        let texts = fields.map { field -> String in
            var text = field
            if let (_, rest) = CatchUpReply.leadingLineNumber(text) { text = rest }
            if isCopiedLine(text, knownNicks: knownNicks), let colon = text.firstIndex(of: ":") {
                text = text[text.index(after: colon)...]
            }
            return CatchUpReply.clean(text)
        }.filter { !$0.isEmpty }
        // "Rail width | wren said it's per window now": a heading, then the note.
        if texts.count == 2, texts[0].split(separator: " ").count <= 5, texts[1].split(separator: " ").count > 3 {
            return withoutRepeats(texts[1])
        }
        return withoutRepeats(texts.count > 2 ? texts[0] : texts.joined(separator: " "))
    }

    /// `text` with a phrase the model wrote over and over kept once, and
    /// no longer than a note should be: "global setting agreed; global
    /// setting agreed; global…".
    static func withoutRepeats(_ text: String, maximumLength: Int = 220) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if ".;?!".contains(character) {
                let key = current.trimmingCharacters(in: .whitespaces).lowercased()
                if !key.isEmpty, seen.insert(key).inserted { parts.append(current) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces).lowercased()
        if !rest.isEmpty, !seen.contains(where: { $0.hasPrefix(rest) }) { parts.append(current) }
        var result = parts.joined().trimmingCharacters(in: .whitespaces)
        while result.hasSuffix(";") { result.removeLast() }
        guard result.count > maximumLength else { return result }
        return result.prefix(maximumLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// `kenji: the theme engine landed`: a transcript line, copied out.
    static func isCopiedLine(_ text: Substring, knownNicks: Set<String>) -> Bool {
        var text = text.trimmingCharacters(in: .whitespaces)[...]
        if let (_, rest) = CatchUpReply.leadingLineNumber(text) { text = rest }
        guard let colon = text.firstIndex(of: ":") else { return false }
        let nick = text[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: " *<>@+"))
        return !nick.isEmpty && knownNicks.contains(nick.lowercased())
    }

    private static func isSingleNick(_ field: Substring, knownNicks: Set<String>) -> Bool {
        let items = CatchUpReply.nickItems(field)
        return items.count == 1 && knownNicks.contains(items[0].lowercased())
    }

    private static let nothing: Set<String> = ["none", "n/a", "na", "nobody", "no one", "nothing", "-", "—", "(none)", "none."]

    private static func isNothing(_ text: String) -> Bool {
        nothing.contains(text.lowercased())
    }

    // MARK: Limits

    /// Whether a part's reply has written all that's kept: past
    /// `topics` topics with the rest of the notes written too. Stops a
    /// reply that runs on, one topic per message.
    static func isPastLimits(_ draft: RecapDraft, topics: Int, notes: Int) -> Bool {
        draft.topics.count > topics || draft.notes.count > notes * 3 || draft.you.count > notes * 2
    }

    /// A reply with nothing usable in it: a refusal written out, or nothing.
    static func isDeclined(_ draft: RecapDraft) -> Bool {
        draft.isEmpty
    }
}

/// Watches a streamed part's reply for ``RecapReply/isPastLimits(_:topics:notes:)``.
nonisolated final class RecapReplyLimit: Sendable {
    private let reader: Mutex<RecapReply.Reader>
    private let topics: Int
    private let notes: Int

    init(nicks: [String], topics: Int, notes: Int) {
        reader = Mutex(RecapReply.Reader(nicks: nicks))
        self.topics = topics
        self.notes = notes
    }

    @Sendable func isReached(_ reply: String) -> Bool {
        let draft = reader.withLock { $0.read(reply, isComplete: false) }
        return RecapReply.isPastLimits(draft, topics: topics, notes: notes)
    }
}
