// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaCore
import VelaIRC
@testable import VelaIntelligence
import VelaStore

/// Which messages a Recap reads for its scope: where, who and when, from
/// memory and, when it's read, saved history.
@Suite("Recap scope")
struct RecapGathererTests {
    typealias G = RecapGatherer
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let network = RecapFixtures.network

    static func chat(_ nick: String, _ text: String, minutesAgo: Double, kind: ChatLineKind = .message, isSelf: Bool = false, msgid: String? = nil, replyTo: String? = nil, redacted: Bool = false) -> ChatLine {
        ChatLine(
            msgid: msgid,
            time: now.addingTimeInterval(-minutesAgo * 60),
            kind: kind,
            nick: nick,
            text: text,
            isSelf: isSelf,
            replyTo: replyTo,
            isRedacted: redacted
        )
    }

    static func buffer(_ name: String, _ lines: [ChatLine], unread: G.UnreadStart? = nil, network: UUID = network) -> G.BufferSnapshot {
        G.BufferSnapshot(
            id: BufferID(networkID: network, foldedName: name.lowercased()),
            name: name,
            networkName: "Libera.Chat",
            isChannel: name.hasPrefix("#"),
            ownNick: "doug",
            caseMapping: .rfc1459,
            lines: lines,
            unreadStart: unread
        )
    }

    static func collect(_ buffers: [G.BufferSnapshot], scope: RecapScope, database: VelaDatabase? = nil, limit: Int = RecapLimits.gatheredLines) async -> RecapInput {
        await G.collect(G.Request(scope: scope, buffers: buffers, database: database, now: now, limit: limit))
    }

    static let vela = [
        chat("kenji", "an hour and a half ago", minutesAgo: 90),
        chat("lukas", "lukas joined", minutesAgo: 55, kind: .join),
        chat("ada", "\u{02}bold\u{02} news", minutesAgo: 50),
        chat("mallory", "deleted", minutesAgo: 40, redacted: true),
        chat("nadia", "reads the notes", minutesAgo: 30, kind: .action),
        chat("doug", "on it", minutesAgo: 10, isSelf: true),
    ]

    // MARK: When

    @Test func aSpanKeepsWhatPeopleSaidInIt() async {
        let input = await Self.collect([Self.buffer("#vela", Self.vela)], scope: RecapScope(place: .buffer(RecapFixtures.id("#vela")), span: .last(minutes: 60)))
        let lines = input.conversations.first?.lines ?? []
        #expect(lines.map(\.nick) == ["ada", "nadia", "doug"])
        #expect(lines[0].text == "bold news")
        #expect(lines[1].kind == .action)
        #expect(input.conversations.first?.yourLines.map(\.text) == ["on it"])
        #expect(input.requestedStart == Self.now.addingTimeInterval(-3600))
    }

    @Test func sinceUnreadStartsAtEachNewMarker() async {
        let buffers = [
            Self.buffer("#vela", Self.vela, unread: .after(Self.now.addingTimeInterval(-45 * 60))),
            Self.buffer("#swift", [Self.chat("mina", "old", minutesAgo: 20), Self.chat("felix", "new", minutesAgo: 5)], unread: .lastLines(1)),
            Self.buffer("#macdev", [Self.chat("sam", "read already", minutesAgo: 5)]),
        ]
        let input = await Self.collect(buffers, scope: RecapScope(place: .network(Self.network)))
        #expect(input.conversations.map(\.name) == ["#vela", "#swift"])
        #expect(input.conversations[0].lines.map(\.nick) == ["nadia", "doug"])
        #expect(input.conversations[1].lines.map(\.text) == ["new"])
        // Your own lines aren't unread.
        #expect(input.unreadLines == 2)
        #expect(input.requestedStart == nil)
    }

    @Test func nothingUnreadIsEmpty() async {
        let input = await Self.collect([Self.buffer("#vela", Self.vela)], scope: RecapScope(place: .buffer(RecapFixtures.id("#vela"))))
        #expect(input.isEmpty)
    }

    // MARK: Who

    @Test func aPersonsRecapHasTheirsMentionsRepliesAndYourConversation() async {
        let channel = [
            Self.chat("alice", "theme engine landed", minutesAgo: 30, msgid: "a1"),
            Self.chat("bob", "unrelated", minutesAgo: 29),
            Self.chat("carol", "alice: nice work", minutesAgo: 28),
            Self.chat("dave", "agreed", minutesAgo: 27, replyTo: "a1"),
            Self.chat("erin", "malice aforethought", minutesAgo: 26),
            Self.chat("doug", "lunch?", minutesAgo: 25, isSelf: true),
        ]
        let query = [Self.chat("ALICE", "hey", minutesAgo: 20), Self.chat("doug", "hi", minutesAgo: 19, isSelf: true)]
        let other = [Self.chat("bob", "did alice see it?", minutesAgo: 10), Self.chat("bob", "never mind", minutesAgo: 9)]
        let input = await Self.collect(
            [Self.buffer("#vela", channel), Self.buffer("alice", query), Self.buffer("bob", other)],
            scope: RecapScope(place: .network(Self.network), person: "Alice", span: .last(minutes: 60))
        )
        #expect(input.conversations.map(\.name) == ["#vela", "alice", "bob"])
        #expect(input.conversations[0].lines.map(\.nick) == ["alice", "carol", "dave"])
        // Your lines there still count for "did you answer".
        #expect(input.conversations[0].yourLines.map(\.text) == ["lunch?"])
        #expect(input.conversations[1].lines.count == 2)
        #expect(input.conversations[2].lines.map(\.text) == ["did alice see it?"])
    }

    // MARK: Where

    @Test func placesPickTheirBuffers() async throws {
        let app = AppModel.demo()
        await app.ready()
        let libera = try #require(app.sessions.first { $0.displayName == "Libera.Chat" })
        let vela = try #require(libera.buffer(named: "#vela"))
        let gatherer = RecapGatherer(app: app)
        let day = RecapScope.Span.last(minutes: 1_440)

        let one = await gatherer.gather(RecapScope(place: .buffer(vela.id), span: day))
        #expect(one.conversations.map(\.name) == ["#vela"])
        #expect(one.conversations[0].networkName == "Libera.Chat")
        #expect(one.conversations[0].ownNick == "doug")

        let network = await gatherer.gather(RecapScope(place: .network(libera.id), span: day))
        #expect(network.conversations.contains { $0.name == "#swift" })
        #expect(network.conversations.contains { $0.name == "marisol" })
        #expect(!network.conversations.contains { $0.name == "#debian" })
        #expect(network.conversations.allSatisfy { $0.id.networkID == libera.id })

        let everywhere = await gatherer.gather(RecapScope(place: .everywhere, span: day))
        #expect(everywhere.conversations.contains { $0.name == "#debian" })
        #expect(everywhere.lineCount > network.lineCount)
        // Network consoles aren't conversations.
        #expect(!everywhere.conversations.contains { $0.id.foldedName == BufferID.serverBufferName })
    }

    // MARK: Saved history

    @Test func savedHistoryFillsInWhatMemoryDoesntHave() async throws {
        let database = try VelaDatabase.inMemory()
        let memory = [
            Self.chat("kenji", "in memory", minutesAgo: 30, msgid: "m1"),
            Self.chat("ada", "also in memory", minutesAgo: 20),
        ]
        let key = "#vela"
        try await database.append([
            MessageRecord(networkID: Self.network, bufferName: key, msgid: "s1", time: Self.now.addingTimeInterval(-300 * 60), kind: "message", nick: "wren", text: "saved long ago"),
            MessageRecord(networkID: Self.network, bufferName: key, msgid: "s2", time: Self.now.addingTimeInterval(-120 * 60), kind: "message", nick: "theo", text: "saved"),
            MessageRecord(networkID: Self.network, bufferName: key, msgid: "m1", time: Self.now.addingTimeInterval(-30 * 60), kind: "message", nick: "kenji", text: "in memory"),
            MessageRecord(id: memory[1].id, networkID: Self.network, bufferName: key, time: memory[1].time, kind: "message", nick: "ada", text: "also in memory"),
            MessageRecord(networkID: Self.network, bufferName: key, time: Self.now.addingTimeInterval(-100 * 60), kind: "join", nick: "x", text: "joined"),
            MessageRecord(networkID: Self.network, bufferName: key, time: Self.now.addingTimeInterval(-90 * 60), kind: "message", nick: "y", text: "gone", isRedacted: true),
        ])
        let scope = RecapScope(place: .buffer(RecapFixtures.id("#vela")), span: .last(minutes: 180))

        let withHistory = await Self.collect([Self.buffer("#vela", memory)], scope: scope, database: database)
        #expect(withHistory.conversations[0].lines.map(\.text) == ["saved", "in memory", "also in memory"])
        #expect(withHistory.readsSavedHistory)
        #expect(!withHistory.conversations[0].startsBeforeHistory)
        #expect(withHistory.conversations[0].availableSince == Self.now.addingTimeInterval(-300 * 60))

        // Without saved history, only what's in memory, and the Recap says
        // how far back that goes.
        let memoryOnly = await Self.collect([Self.buffer("#vela", memory)], scope: scope)
        #expect(memoryOnly.conversations[0].lines.map(\.text) == ["in memory", "also in memory"])
        #expect(memoryOnly.conversations[0].startsBeforeHistory)
        #expect(memoryOnly.conversations[0].availableSince == memory[0].time)

        // Vela running since before the span: a quiet channel isn't
        // missing anything, unless lines were dropped for the scrollback limit.
        let running = await G.collect(G.Request(
            scope: scope, buffers: [Self.buffer("#vela", memory)], database: nil, now: Self.now,
            collectingSince: Self.now.addingTimeInterval(-600 * 60)
        ))
        #expect(!running.conversations[0].startsBeforeHistory)
        var trimmed = Self.buffer("#vela", memory)
        trimmed.isTrimmed = true
        let dropped = await G.collect(G.Request(
            scope: scope, buffers: [trimmed], database: nil, now: Self.now,
            collectingSince: Self.now.addingTimeInterval(-600 * 60)
        ))
        #expect(dropped.conversations[0].startsBeforeHistory)
        #expect(G.processStart <= Date())
    }

    @Test func savedHistoryForAPersonIsNarrowedInTheQuery() async throws {
        let database = try VelaDatabase.inMemory()
        try await database.append((0..<50).map { index in
            MessageRecord(networkID: Self.network, bufferName: "#vela", time: Self.now.addingTimeInterval(-Double(100 + index) * 60), kind: "message", nick: index % 10 == 0 ? "alice" : "bob", text: "line \(index)")
        })
        let input = await Self.collect(
            [Self.buffer("#vela", [])],
            scope: RecapScope(place: .network(Self.network), person: "alice", span: .last(minutes: 1_440)),
            database: database
        )
        #expect(input.conversations.first?.lines.count == 5)
        #expect(input.conversations.first?.lines.allSatisfy { $0.nick == "alice" } == true)
    }

    // MARK: Limits

    @Test func theNewestAreKeptOverTheLimit() async {
        let first = (0..<6).map { Self.chat("a", "first \($0)", minutesAgo: Double(60 - $0 * 2)) }
        let second = (0..<6).map { Self.chat("b", "second \($0)", minutesAgo: Double(59 - $0 * 2)) }
        let input = await Self.collect(
            [Self.buffer("#one", first), Self.buffer("#two", second)],
            scope: RecapScope(place: .network(Self.network), span: .last(minutes: 120)),
            limit: 5
        )
        #expect(input.lineCount == 5)
        #expect(input.matchingLines == 12)
        #expect(input.droppedLines == 7)
        let kept = input.conversations.flatMap(\.lines).sorted { $0.time < $1.time }.map(\.text)
        #expect(kept == ["second 3", "first 4", "second 4", "first 5", "second 5"])
    }
}
