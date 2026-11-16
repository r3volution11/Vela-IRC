// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
import VelaStore
@testable import VelaUI

@MainActor
@Suite("Message display pipeline")
struct MessageDisplayPipelineTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11-15 12:00 UTC plus `minutes`.
    private func at(_ minutes: Double, day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!.addingTimeInterval(minutes * 60)
    }

    private func message(_ nick: String, _ text: String = "hi", _ minutes: Double, day: Int = 15,
                         kind: ChatLineKind = .message, msgid: String? = nil, replyTo: String? = nil, isSelf: Bool = false) -> ChatLine {
        ChatLine(msgid: msgid, time: at(minutes, day: day), kind: kind, nick: nick, text: text, isSelf: isSelf, replyTo: replyTo)
    }

    private func event(_ kind: ChatLineKind, _ nick: String, _ minutes: Double, text: String? = nil) -> ChatLine {
        ChatLine(time: at(minutes), kind: kind, nick: nick, text: text ?? "\(nick) \(kind.rawValue)")
    }

    private func build(_ lines: [ChatLine], joinPart: JoinPartDisplay = .collapse, interval: TimeInterval = 300,
                       marker: Date? = nil) -> [DisplayItem] {
        var builder = MessageDisplayBuilder(options: MessageDisplayOptions(
            joinPart: joinPart, groupingInterval: interval, unreadMarkerAfter: marker, calendar: calendar))
        builder.append(contentsOf: lines)
        return Array(builder.result)
    }

    private func lineItems(_ items: [DisplayItem]) -> [LineItem] {
        items.compactMap { if case .line(let item) = $0 { item } else { nil } }
    }

    // MARK: Dividers and markers

    @Test func dayDividersBeforeFirstLineAndOnEachNewDay() {
        let items = build([message("a", "1", 0, day: 14), message("a", "2", 5, day: 14), message("b", "3", 0)])
        let dividers = items.compactMap { if case .dayDivider(_, let key) = $0 { key } else { nil } }
        #expect(dividers == [20261114, 20261115])
        guard case .dayDivider = items[0] else { Issue.record("first item should be a divider"); return }
        // A new day starts a new group even for the same sender.
        #expect(lineItems(items).map(\.isContinuation) == [false, true, false])
    }

    @Test func unreadMarkerSitsAfterTheLastReadLine() {
        let lines = [message("a", "1", 0), message("b", "2", 1), message("c", "3", 2)]
        let items = build(lines, marker: at(1))
        let ids = items.map(\.id)
        let markerIndex = ids.firstIndex(of: .unreadMarker)
        #expect(markerIndex == ids.firstIndex(of: .line(lines[2].id)).map { $0 - 1 })
        #expect(build(lines, marker: at(5)).contains { $0.id == .unreadMarker } == false)
        #expect(build(lines).contains { $0.id == .unreadMarker } == false)
    }

    @Test func unreadMarkerBreaksGroups() {
        let lines = [message("a", "1", 0), message("a", "2", 1)]
        #expect(lineItems(build(lines, marker: at(0.5))).map(\.isContinuation) == [false, false])
    }

    // MARK: Membership events

    @Test func membershipRunsCollapse() {
        let lines = [
            message("a", "hi", 0),
            event(.join, "alice", 1), event(.join, "bob", 2), event(.part, "carol", 3),
            message("a", "again", 4),
            event(.join, "dave", 5),
        ]
        let items = build(lines, joinPart: .collapse)
        let runs = items.compactMap { if case .membershipRun(let run) = $0 { run } else { nil } }
        #expect(runs.count == 1)
        #expect(runs.first?.lines.count == 3)
        #expect(runs.first?.summary == "alice and bob joined · carol left")
        // A single event stays a plain row.
        #expect(lineItems(items).last?.line.kind == .join)
        // The run breaks the group.
        #expect(lineItems(items).filter { $0.line.kind == .message }.map(\.isContinuation) == [false, false])
    }

    @Test func membershipShowAndHide() {
        let lines = [message("a", "1", 0), event(.join, "x", 1), event(.quit, "y", 2), message("a", "2", 3)]
        let shown = build(lines, joinPart: .show)
        #expect(lineItems(shown).count == 4)
        #expect(!shown.contains { if case .membershipRun = $0 { true } else { false } })

        let hidden = build(lines, joinPart: .hide)
        #expect(lineItems(hidden).map(\.line.kind) == [.message, .message])
        // Hidden events don't break the group.
        #expect(lineItems(hidden).map(\.isContinuation) == [false, true])
    }

    @Test func membershipSummaryPhrasing() {
        func run(_ events: [ChatLine]) -> String { MembershipSummary.text(for: events) }
        #expect(run([event(.join, "a", 0), event(.join, "b", 1), event(.join, "c", 2), event(.join, "d", 3), event(.join, "e", 4)])
                == "a, b and 3 others joined")
        #expect(run([event(.join, "a", 0), event(.join, "b", 1), event(.join, "c", 2)]) == "a, b and c joined")
        #expect(run([event(.part, "w", 0), event(.join, "w", 1)]) == "w rejoined")
        #expect(run([event(.join, "w", 0), event(.quit, "w", 1)]) == "w joined and left")
        #expect(run([event(.nick, "old", 0, text: "old is now known as new"), event(.join, "z", 1)])
                == "z joined · old is now new")
        // A renamed nick keeps being tracked under its new name.
        #expect(run([event(.nick, "a", 0, text: "a is now known as b"), event(.part, "b", 1)]) == "a left · a is now b")
    }

    // MARK: Grouping

    @Test func groupingRules() {
        let lines = [
            message("Ana", "1", 0),
            message("ana", "2", 1),                   // same nick, case-insensitive
            message("ana", "3", 1.5, kind: .action),  // actions group with messages
            message("ana", "4", 20),                  // past the interval
            message("bob", "5", 21),                  // different sender
            message("bob", "6", 22, replyTo: "x"),    // replies always show a header
            message("bob", "7", 23, kind: .notice),   // notices don't group with messages
            event(.mode, "op", 24),
            message("bob", "8", 25),                  // after a visible event
        ]
        #expect(lineItems(build(lines)).filter { $0.line.kind.isConversation }.map(\.isContinuation)
                == [false, true, true, false, false, false, false, false])
        // Interval 0 disables grouping.
        #expect(lineItems(build(Array(lines.prefix(2)), interval: 0)).map(\.isContinuation) == [false, false])
    }

    @Test func repliesResolveAgainstEarlierLines() {
        let parent = message("a", "parent", 0, msgid: "p1")
        let lines = [parent, message("b", "child", 1, replyTo: "p1"), message("c", "orphan", 2, replyTo: "missing")]
        let replies = lineItems(build(lines)).map(\.reply)
        #expect(replies[0] == nil)
        #expect(replies[1] == .resolved(parent))
        #expect(replies[2] == .unresolved)
    }

    // MARK: Incremental updates

    @Test func appendingMatchesAFullBuild() {
        var lines: [ChatLine] = []
        for i in 0..<60 {
            switch i % 7 {
            case 3: lines.append(event(.join, "j\(i)", Double(i)))
            case 4: lines.append(event(.part, "p\(i)", Double(i)))
            default: lines.append(message(["a", "b"][i % 2 == 0 ? 0 : 1], "\(i)", Double(i), msgid: "m\(i)"))
            }
        }
        let options = MessageDisplayOptions(joinPart: .collapse, groupingInterval: 300, unreadMarkerAfter: at(30), calendar: calendar)
        var incremental = MessageDisplayBuilder(options: options)
        for chunk in stride(from: 0, to: lines.count, by: 5) {
            incremental.append(contentsOf: lines[chunk..<min(chunk + 5, lines.count)])
        }
        var full = MessageDisplayBuilder(options: options)
        full.append(contentsOf: lines)
        #expect(Array(incremental.result) == Array(full.result))
    }

    @Test func cacheExtendsOnAppendAndRebuildsOtherwise() {
        let cache = MessageDisplayCache()
        let options = MessageDisplayOptions(calendar: calendar)
        var lines = (0..<10).map { message("a", "\($0)", Double($0)) }
        _ = cache.items(for: lines, options: options)
        #expect(cache.rebuildCount == 1)

        _ = cache.items(for: lines, options: options)                 // unchanged
        lines.append(message("b", "new", 11))
        let appended = cache.items(for: lines, options: options)      // append
        #expect(cache.rebuildCount == 1)
        #expect(appended.last?.id == .line(lines.last!.id))

        lines.insert(message("z", "older", -10), at: 0)               // history prepended
        _ = cache.items(for: lines, options: options)
        #expect(cache.rebuildCount == 2)

        lines[3].isRedacted = true                                    // in-place change
        let redacted = cache.items(for: lines, options: options)
        #expect(cache.rebuildCount == 3)
        #expect(redacted.contains { if case .line(let item) = $0 { item.line.isRedacted } else { false } })

        var hidden = options
        hidden.joinPart = .hide                                       // option change
        _ = cache.items(for: lines, options: hidden)
        #expect(cache.rebuildCount == 4)
    }

    @Test func buildingThousandsOfLinesIsFast() {
        let lines = (0..<5_000).map { i in
            i % 10 == 0 ? event(.join, "j\(i)", Double(i) * 0.2) : message("n\(i % 7)", "line \(i)", Double(i) * 0.2, msgid: "m\(i)")
        }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = MessageDisplayCache().items(for: lines, options: MessageDisplayOptions(calendar: calendar))
        }
        #expect(elapsed < .milliseconds(250), "full build of 5,000 lines took \(elapsed)")

        let cache = MessageDisplayCache()
        _ = cache.items(for: lines, options: MessageDisplayOptions(calendar: calendar))
        let more = lines + [message("x", "new", 2_000)]
        let appendTime = clock.measure {
            _ = cache.items(for: more, options: MessageDisplayOptions(calendar: calendar))
        }
        #expect(appendTime < .milliseconds(20), "appending one line took \(appendTime)")
    }

    // MARK: Day labels

    @Test func dayLabels() {
        let now = at(0)
        let locale = Locale(identifier: "en_US")
        #expect(DayLabel.text(for: at(-60), now: now, calendar: calendar, locale: locale) == "Today")
        #expect(DayLabel.text(for: at(0, day: 14), now: now, calendar: calendar, locale: locale) == "Yesterday")
        #expect(DayLabel.text(for: at(0, day: 10), now: now, calendar: calendar, locale: locale) == "Tuesday, November 10")
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 3, day: 2, hour: 9))!
        #expect(DayLabel.text(for: lastYear, now: now, calendar: calendar, locale: locale) == "Sunday, March 2, 2025")
    }
}
