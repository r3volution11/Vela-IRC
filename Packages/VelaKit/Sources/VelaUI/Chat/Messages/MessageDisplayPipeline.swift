// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaStore

// MARK: Display items

/// Stable identity of a row in the message list. Also the scroll-target id.
nonisolated enum DisplayItemID: Hashable, Sendable {
    /// A day divider, keyed by `year * 10_000 + month * 100 + day`.
    case day(Int)
    case unreadMarker
    /// The Catch me up card, right under the unread marker.
    case catchUpCard
    case line(UUID)
    /// A collapsed membership run, keyed by its first line.
    case membershipRun(UUID)
    /// The spacer after the last row; see `MessageListView.scrollToBottom`.
    case end
}

/// What a reply points at.
nonisolated enum ReplyTarget: Hashable, Sendable {
    case resolved(ChatLine)
    /// The parent message isn't loaded (or never existed here).
    case unresolved
}

/// One chat line plus everything the row needs to know about its neighbors.
nonisolated struct LineItem: Hashable, Sendable {
    var line: ChatLine
    /// Grouped layout: same sender as the previous row, so no header.
    var isContinuation: Bool
    var reply: ReplyTarget?
}

/// A run of consecutive join/part/quit/nick events shown as one summary row.
nonisolated struct MembershipRun: Hashable, Sendable {
    var lines: [ChatLine]
    var id: UUID { lines[0].id }
    var summary: String { MembershipSummary.text(for: lines) }
}

nonisolated enum DisplayItem: Identifiable, Hashable, Sendable {
    /// The first moment of a calendar day.
    case dayDivider(Date, key: Int)
    case unreadMarker
    /// The Catch me up summary, right after the unread marker while it's open.
    case catchUpCard
    case line(LineItem)
    case membershipRun(MembershipRun)

    var id: DisplayItemID {
        switch self {
        case .dayDivider(_, let key): .day(key)
        case .unreadMarker: .unreadMarker
        case .catchUpCard: .catchUpCard
        case .line(let item): .line(item.line.id)
        case .membershipRun(let run): .membershipRun(run.id)
        }
    }
}

/// Inputs that change how lines become rows. A change rebuilds the list.
nonisolated struct MessageDisplayOptions: Equatable, Sendable {
    var joinPart: JoinPartDisplay = .collapse
    var groupingInterval: TimeInterval = 300
    var unreadMarkerAfter: Date?
    /// Show the Catch me up card under the unread marker.
    var showsCatchUpCard = false
    var calendar: Calendar = .current
}

// MARK: Builder

/// Streams chat lines into display items. Lines must arrive in time order
/// (as `BufferModel.lines` keeps them). Appending more lines continues where
/// the last call left off, so new messages cost O(new lines), not O(buffer).
nonisolated struct MessageDisplayBuilder: Sendable {
    let options: MessageDisplayOptions
    /// Finished items. A trailing membership run that may still grow lives in
    /// `pendingRun` until something else arrives.
    private(set) var items: [DisplayItem] = []
    private(set) var pendingRun: [ChatLine] = []
    private(set) var processedCount = 0

    private var dayRange: Range<Date>?
    private var markerPlaced = false
    /// The previous conversational line, while grouping with it is possible.
    private var groupAnchor: ChatLine?
    private var linesByMsgid: [String: ChatLine] = [:]

    init(options: MessageDisplayOptions) {
        self.options = options
    }

    /// Finished items followed by the trailing run, without copying `items`.
    var result: DisplayItems {
        DisplayItems(head: items, tail: Self.flushed(pendingRun))
    }

    mutating func append<S: Sequence>(contentsOf lines: S) where S.Element == ChatLine {
        for line in lines { append(line) }
    }

    mutating func append(_ line: ChatLine) {
        processedCount += 1
        if let msgid = line.msgid { linesByMsgid[msgid] = line }
        if line.kind == .dayChange { return }   // day dividers are drawn from timestamps

        if let range = dayRange, range.contains(line.time) {
            // Same day as the previous line.
        } else {
            let start = options.calendar.startOfDay(for: line.time)
            let end = options.calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            dayRange = start..<max(end, start.addingTimeInterval(1))
            flushRun()
            items.append(.dayDivider(start, key: Self.dayKey(start, calendar: options.calendar)))
            groupAnchor = nil
        }

        if !markerPlaced, let marker = options.unreadMarkerAfter, line.time > marker {
            markerPlaced = true
            flushRun()
            items.append(.unreadMarker)
            if options.showsCatchUpCard { items.append(.catchUpCard) }
            groupAnchor = nil
        }

        if line.kind.isMembershipEvent {
            switch options.joinPart {
            case .hide:
                return   // invisible, so it doesn't break a group either
            case .show:
                flushRun()
                items.append(.line(LineItem(line: line, isContinuation: false)))
            case .collapse:
                pendingRun.append(line)
            }
            groupAnchor = nil
            return
        }

        flushRun()
        guard line.kind.isConversation else {
            items.append(.line(LineItem(line: line, isContinuation: false)))
            groupAnchor = nil
            return
        }
        let reply: ReplyTarget? = line.replyTo.map { msgid in
            linesByMsgid[msgid].map(ReplyTarget.resolved) ?? .unresolved
        }
        let continues = groupAnchor.map { Self.continues(line, after: $0, interval: options.groupingInterval) } ?? false
        items.append(.line(LineItem(line: line, isContinuation: continues, reply: reply)))
        groupAnchor = line
    }

    /// Whether `line` can sit under `previous`'s header in the grouped layout.
    static func continues(_ line: ChatLine, after previous: ChatLine, interval: TimeInterval) -> Bool {
        guard interval > 0, line.replyTo == nil,
              line.kind.isConversation, previous.kind.isConversation,
              (line.kind == .notice) == (previous.kind == .notice),
              line.isSelf == previous.isSelf,
              let nick = line.nick, let previousNick = previous.nick,
              nick.caseInsensitiveCompare(previousNick) == .orderedSame
        else { return false }
        let gap = line.time.timeIntervalSince(previous.time)
        return gap >= 0 && gap <= interval
    }

    private mutating func flushRun() {
        guard !pendingRun.isEmpty else { return }
        items.append(contentsOf: Self.flushed(pendingRun))
        pendingRun.removeAll(keepingCapacity: true)
    }

    private static func flushed(_ run: [ChatLine]) -> [DisplayItem] {
        switch run.count {
        case 0: []
        case 1: [.line(LineItem(line: run[0], isContinuation: false))]
        default: [.membershipRun(MembershipRun(lines: run))]
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }
}

/// The list's rows: the builder's finished items plus its trailing run,
/// presented as one collection without concatenating arrays.
nonisolated struct DisplayItems: RandomAccessCollection, Sendable {
    var head: [DisplayItem] = []
    var tail: [DisplayItem] = []

    var startIndex: Int { 0 }
    var endIndex: Int { head.count + tail.count }

    subscript(position: Int) -> DisplayItem {
        position < head.count ? head[position] : tail[position - head.count]
    }

    func index(after i: Int) -> Int { i + 1 }
    func index(before i: Int) -> Int { i - 1 }

    func contains(id: DisplayItemID) -> Bool {
        tail.contains { $0.id == id } || head.contains { $0.id == id }
    }

    var lastID: DisplayItemID? { last?.id }
}

/// Memoizes the builder between body evaluations. Appends extend the
/// previous result; anything else (history prepended, a redaction, an
/// option change) rebuilds from scratch, which is still linear and cheap.
@MainActor
final class MessageDisplayCache {
    private var builder: MessageDisplayBuilder?
    private var builtLines: [ChatLine] = []
    private(set) var items = DisplayItems()
    /// Number of full rebuilds, for tests and debugging.
    private(set) var rebuildCount = 0

    func items(for lines: [ChatLine], options: MessageDisplayOptions) -> DisplayItems {
        if let existing = builder, existing.options == options {
            // Unchanged array storage: nothing to do (Array == short-circuits on identity).
            if lines.count == builtLines.count, lines == builtLines { return items }
            if Self.isAppend(lines, to: builtLines) {
                // Drop our own references first so appending doesn't copy the
                // item arrays when nothing else holds them.
                var extended = existing
                builder = nil
                items = DisplayItems()
                extended.append(contentsOf: lines[builtLines.count...])
                commit(extended, lines)
                return items
            }
        }
        var fresh = MessageDisplayBuilder(options: options)
        fresh.append(contentsOf: lines)
        rebuildCount += 1
        commit(fresh, lines)
        return items
    }

    private func commit(_ builder: MessageDisplayBuilder, _ lines: [ChatLine]) {
        self.builder = builder
        builtLines = lines
        items = builder.result
    }

    nonisolated static func isAppend(_ lines: [ChatLine], to previous: [ChatLine]) -> Bool {
        guard let previousFirst = previous.first, let previousLast = previous.last,
              lines.count > previous.count else { return false }
        return lines[0].id == previousFirst.id && lines[previous.count - 1].id == previousLast.id
    }
}

// MARK: Membership summaries

/// "alice, bob and 3 others joined · carol left · dan is now dan_"
nonisolated enum MembershipSummary {
    private enum Presence { case joined, left }

    private struct Person {
        var firstNick: String
        var currentNick: String
        var presence: [Presence] = []
        var renamed = false
    }

    static func text(for lines: [ChatLine]) -> String {
        var people: [Person] = []
        var indexByNick: [String: Int] = [:]

        func index(for nick: String) -> Int {
            let key = nick.lowercased()
            if let existing = indexByNick[key] { return existing }
            people.append(Person(firstNick: nick, currentNick: nick))
            indexByNick[key] = people.count - 1
            return people.count - 1
        }

        for line in lines {
            guard let nick = line.nick else { continue }
            switch line.kind {
            case .join:
                people[index(for: nick)].presence.append(.joined)
            case .part, .quit:
                people[index(for: nick)].presence.append(.left)
            case .nick:
                guard let newNick = newNick(from: line), newNick != nick else { continue }
                let i = index(for: nick)
                people[i].currentNick = newNick
                people[i].renamed = true
                indexByNick[nick.lowercased()] = nil
                indexByNick[newNick.lowercased()] = i
            default:
                continue
            }
        }

        var verbs: [String] = []
        var namesByVerb: [String: [String]] = [:]
        var renames: [String] = []
        for person in people {
            if let verb = verb(for: person.presence) {
                if namesByVerb[verb] == nil { verbs.append(verb) }
                namesByVerb[verb, default: []].append(person.firstNick)
            }
            if person.renamed {
                renames.append("\(person.firstNick) is now \(person.currentNick)")
            }
        }

        var phrases = verbs.map { "\(list(namesByVerb[$0] ?? [])) \($0)" }
        if renames.count <= 2 {
            phrases += renames
        } else {
            phrases.append("\(renames.count) nick changes")
        }
        return phrases.joined(separator: " · ")
    }

    private static func verb(for presence: [Presence]) -> String? {
        guard let first = presence.first, let last = presence.last else { return nil }
        switch (first, last) {
        case (.joined, .joined): return "joined"
        case (.left, .left): return "left"
        case (.joined, .left): return "joined and left"
        case (.left, .joined): return "rejoined"
        }
    }

    /// "a", "a and b", "a, b and c", "a, b and 3 others".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        case 3: return "\(names[0]), \(names[1]) and \(names[2])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) others"
        }
    }

    /// The new nick from "x is now known as y" / "You are now known as y".
    static func newNick(from line: ChatLine) -> String? {
        guard line.kind == .nick, let range = line.text.range(of: " now known as ", options: .backwards) else { return nil }
        let nick = line.text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return nick.isEmpty ? nil : nick
    }
}

// MARK: Day labels

nonisolated enum DayLabel {
    /// "Today", "Yesterday", "Monday, November 10", or with the year when
    /// it isn't the current one.
    static func text(for date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEMMMMd" : "EEEEMMMMdyyyy")
        return formatter.string(from: date)
    }
}
