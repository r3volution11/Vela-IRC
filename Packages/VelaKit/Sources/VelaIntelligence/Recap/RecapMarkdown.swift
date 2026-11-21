// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore

/// Dates and counts as a Recap writes them, in the window and in its
/// Markdown. Locale and time zone are parameters so tests can fix them.
nonisolated public struct RecapFormat: Sendable {
    public var now: Date
    public var locale: Locale
    public var timeZone: TimeZone

    public init(now: Date = Date(), locale: Locale = .current, timeZone: TimeZone = .current) {
        self.now = now
        self.locale = locale
        self.timeZone = timeZone
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }

    /// "2:14 PM" today; "Yesterday 2:14 PM"; "Nov 20, 2:14 PM" before that.
    public func time(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
        let clock = date.formatted(style)
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(clock)"
        }
        style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
        return date.formatted(style)
    }

    /// Just the clock: "2:14 PM".
    public func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone))
    }

    /// "Today", "Yesterday", "Thursday, November 19, 2026".
    public func day(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone))
    }

    /// The start of `date`'s day, for grouping a log.
    public func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// "2:14 PM – 4:40 PM", or with days when it spans more than today.
    public func range(_ range: ClosedRange<Date>) -> String {
        let start = time(range.lowerBound)
        let end = calendar.isDate(range.lowerBound, inSameDayAs: range.upperBound) ? clock(range.upperBound) : time(range.upperBound)
        return start == end ? start : "\(start) – \(end)"
    }

    /// "1 message", "1,240 messages".
    public static func messages(_ count: Int) -> String {
        count == 1 ? "1 message" : "\(count.formatted()) messages"
    }

    /// "1 person", "9 people".
    public static func people(_ count: Int) -> String {
        count == 1 ? "1 person" : "\(count.formatted()) people"
    }

    /// "About 2 minutes", "About 40 seconds", "Under a minute".
    public static func duration(_ seconds: Double) -> String {
        if seconds < 45 { return seconds < 15 ? "A few seconds" : "Under a minute" }
        let minutes = Int((seconds / 60).rounded())
        return minutes <= 1 ? "About a minute" : "About \(minutes) minutes"
    }
}

/// A Recap as Markdown, for Copy and Save as Markdown…: the same content
/// the window shows, as clean Markdown. Text from the conversation is
/// escaped, so a stray `*` or `#` stays a character.
nonisolated public enum RecapMarkdown {
    /// The parts of a Recap's header the window works out from the app.
    public struct Header: Sendable {
        /// "Recap of #vela".
        public var title: String
        /// "Libera.Chat · Since your first unread · 2:14 PM – 4:40 PM · 412 messages · 9 people".
        public var subtitle: String
        /// Notes on what's missing: "Vela has #vela back to 2:14 PM."
        public var notes: [String]
        /// How to name a conversation after an item, when the Recap has
        /// several: "#vela", or "#vela on Libera.Chat".
        public var conversationNames: [BufferID: String]

        public init(title: String, subtitle: String, notes: [String] = [], conversationNames: [BufferID: String] = [:]) {
            self.title = title
            self.subtitle = subtitle
            self.notes = notes
            self.conversationNames = conversationNames
        }
    }

    /// The summary: overview, topics, what's for you, decisions and
    /// follow-ups, and links, with any More detail that was asked for.
    public static func summary(
        header: Header,
        findings: RecapFindings,
        summary: RecapSummary?,
        details: [String: RecapDetail] = [:],
        format: RecapFormat
    ) -> String {
        var out = start(header)
        func place(_ reference: RecapReference?) -> String {
            guard let reference else { return "" }
            var text = format.time(reference.time)
            if header.conversationNames.count > 1, let name = header.conversationNames[reference.conversation] {
                text += " in \(inline(name))"
            }
            return text
        }

        if let summary, !summary.overview.isEmpty {
            out += "## Overview\n\n"
            out += summary.overview.map { "- \(escape($0))" }.joined(separator: "\n") + "\n\n"
        }

        if let summary, !summary.topics.isEmpty {
            out += "## Topics\n\n"
            for topic in summary.topics {
                out += "### \(inline(topic.title))\n\n"
                if !topic.summary.isEmpty { out += "\(escape(topic.summary))\n\n" }
                var meta: [String] = []
                if !topic.participants.isEmpty { meta.append(topic.participants.map(inline).joined(separator: ", ")) }
                let where_ = place(topic.start)
                if !where_.isEmpty { meta.append(where_) }
                if !meta.isEmpty { out += "*\(meta.joined(separator: " · "))*\n\n" }
                if let points = details[topic.id]?.points, !points.isEmpty {
                    out += points.map { "- \(escape($0))" }.joined(separator: "\n") + "\n\n"
                }
            }
        }

        if !findings.forYou.isEmpty {
            out += "## For you\n\n"
            for item in findings.forYou {
                let note = summary?.notesForYou[item.id]
                var line = "- **\(inline(item.nick))** "
                if let note {
                    line += inline(Self.dropLeadingNick(note, nick: item.nick))
                } else {
                    line += "“\(inline(item.quote))”"
                }
                var meta = [place(item.reference)]
                if !item.isAnswered { meta.append(item.isRequest ? "No reply yet" : "Not answered") }
                line += " (\(meta.filter { !$0.isEmpty }.joined(separator: " · ")))"
                out += line + "\n"
            }
            out += "\n"
        }

        if let summary, !summary.notes.isEmpty {
            out += "## Decisions and follow-ups\n\n"
            for kind in RecapNote.Kind.allCases {
                let notes = summary.notes(kind)
                guard !notes.isEmpty else { continue }
                out += "### \(title(kind))\n\n"
                for note in notes {
                    var line = "- "
                    if let owner = note.owner {
                        line += "**\(inline(owner))**: " + inline(note.text)
                    } else {
                        line += escape(note.text)
                    }
                    let where_ = place(note.reference)
                    if !where_.isEmpty { line += " (\(where_))" }
                    out += line + "\n"
                    if let points = details[note.id]?.points, !points.isEmpty {
                        out += points.map { "    - \(escape($0))" }.joined(separator: "\n") + "\n"
                    }
                }
                out += "\n"
            }
        }

        if !findings.links.isEmpty {
            out += "## Links shared\n\n"
            for group in findings.links {
                out += "### \(inline(group.title))\n\n"
                for link in group.links {
                    var line = "- [\(inline(link.displayTitle))](\(destination(link.url))) — \(inline(link.nick))"
                    let where_ = place(link.reference)
                    if !where_.isEmpty { line += ", \(where_)" }
                    if link.shares > 1 { line += " (shared \(link.shares) times)" }
                    out += line + "\n"
                }
                out += "\n"
            }
        }

        if let summary {
            var footer: [String] = []
            if summary.skippedMessages > 0 {
                footer.append("Skipped \(RecapFormat.messages(summary.skippedMessages)) that Apple Intelligence wouldn't summarize.")
            }
            footer.append(summary.provenance)
            footer.append("May contain mistakes.")
            out += "---\n\n\(footer.joined(separator: " "))\n"
        }
        return out.trimmingCharacters(in: .newlines) + "\n"
    }

    /// The log: every message, by conversation and day.
    public static func log(header: Header, input: RecapInput, format: RecapFormat) -> String {
        var out = start(header)
        let names = Dictionary(uniqueKeysWithValues: input.conversations.map { ($0.id, $0.networkName) })
        let manyNetworks = Set(names.values).count > 1
        for conversation in input.conversations {
            out += "## \(inline(conversation.name))\(manyNetworks ? " — \(inline(conversation.networkName))" : "")\n\n"
            var day: Date?
            for line in conversation.lines {
                let lineDay = format.startOfDay(line.time)
                if lineDay != day {
                    if day != nil { out += "\n" }
                    out += "### \(format.day(line.time))\n\n"
                    day = lineDay
                }
                out += "- \(format.clock(line.time)) \(logText(line))\n"
            }
            out += "\n"
        }
        return out.trimmingCharacters(in: .newlines) + "\n"
    }

    /// `**kenji**: text`, `\* **nadia** reads the notes`, or a notice.
    static func logText(_ line: RecapLine) -> String {
        let nick = "**\(inline(line.nick))**"
        let text = inline(line.text)
        switch line.kind {
        case .message: return "\(nick): \(text)"
        case .action: return "\\* \(nick) \(text)"
        case .notice: return "\(nick) (notice): \(text)"
        }
    }

    private static func start(_ header: Header) -> String {
        var out = "# \(inline(header.title))\n\n"
        if !header.subtitle.isEmpty { out += "\(escape(header.subtitle))\n\n" }
        for note in header.notes { out += "> \(escape(note))\n\n" }
        return out
    }

    public static func title(_ kind: RecapNote.Kind) -> String {
        switch kind {
        case .decision: "Decided"
        case .question: "Open questions"
        case .followUp: "Follow-ups"
        }
    }

    /// "wren asked you…" after **wren**: "asked you…".
    public static func dropLeadingNick(_ note: String, nick: String) -> String {
        guard let range = note.range(of: nick, options: [.caseInsensitive, .anchored]) else { return note }
        let rest = note[range.upperBound...]
        guard rest.first == " " else { return note }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// Text that starts a paragraph or list item, as literal Markdown:
    /// ``inline(_:)``, and a start that would make a heading, list or
    /// quote kept as text.
    public static func escape(_ text: String) -> String {
        var result = inline(text)
        if let first = result.first, "#+-".contains(first) { result = "\\" + result }
        if let dot = result.firstIndex(where: { !$0.isNumber }), dot > result.startIndex, result[dot] == "." || result[dot] == ")" {
            result.insert("\\", at: dot)
        }
        return result
    }

    /// Text inside a line (after other text, or in a heading), as literal
    /// Markdown: inline markup characters escaped, line breaks as spaces.
    public static func inline(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "\\", "*", "_", "`", "[", "]", "<", ">", "|", "~":
                result.append("\\")
                result.append(character)
            case "\n", "\r":
                result.append(" ")
            default:
                result.append(character)
            }
        }
        return result
    }

    /// A link's address as a Markdown link destination.
    static func destination(_ url: URL) -> String {
        url.absoluteString
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: " ", with: "%20")
    }
}
