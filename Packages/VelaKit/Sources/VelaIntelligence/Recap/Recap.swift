// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore

// Recap: a report of a stretch of conversation, in a window of its own.
// Catch me up is a small card for one channel's unread messages; a Recap
// covers a channel, a network or everything, for anyone or one person,
// since your first unread message or over any span, as an Apple
// Intelligence summary or as a plain log. Everything here lives in memory
// only: nothing about a Recap is written to disk.

// MARK: - Scope

/// What a Recap covers: where, who, when and how it's shown. It's the value
/// a Recap window is opened for, so it's Codable and Hashable.
nonisolated public struct RecapScope: Codable, Hashable, Sendable {
    /// Where the messages come from.
    public enum Place: Codable, Hashable, Sendable {
        /// One channel or private conversation.
        case buffer(BufferID)
        /// Every channel and conversation on one network.
        case network(UUID)
        /// Every network.
        case everywhere
    }

    /// How far back.
    public enum Span: Codable, Hashable, Sendable {
        /// Each conversation's unread messages: from its New marker on.
        case sinceUnread
        /// The last `minutes` minutes.
        case last(minutes: Int)
        /// Since midnight.
        case today
    }

    /// How it's shown.
    public enum Output: String, Codable, Hashable, Sendable, CaseIterable {
        /// Apple Intelligence's report: topics, what's for you, decisions
        /// and follow-ups, with the links shared.
        case summary
        /// The matching messages as they were written, without Apple
        /// Intelligence.
        case log
    }

    public var place: Place
    /// One person's nick: their messages, messages that name them or reply
    /// to them, and your private conversation with them. Nil for anyone.
    public var person: String?
    public var span: Span
    public var output: Output

    public init(place: Place, person: String? = nil, span: Span = .sinceUnread, output: Output = .summary) {
        self.place = place
        let trimmed = person?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.person = trimmed?.isEmpty == false ? trimmed : nil
        self.span = span
        self.output = output
    }
}

nonisolated extension RecapScope.Span {
    /// The quick picks offered when there's nothing unread, and in the
    /// window's When menu.
    public static let quickPicks: [RecapScope.Span] = [
        .last(minutes: 30), .last(minutes: 60), .last(minutes: 240), .today,
        .last(minutes: 1_440), .last(minutes: 4_320), .last(minutes: 10_080),
    ]

    /// "Since your first unread", "Last 30 minutes", "Last 4 hours",
    /// "Today", "Last day", "Last 3 days", "Last week".
    public var title: String {
        switch self {
        case .sinceUnread: "Since your first unread"
        case .today: "Today"
        case .last(let minutes): "Last \(Self.durationTitle(minutes: minutes, singularArticle: false))"
        }
    }

    /// "30 minutes", "hour", "4 hours", "day", "3 days", "week", "2 weeks".
    public static func durationTitle(minutes: Int, singularArticle: Bool) -> String {
        let minutes = max(1, minutes)
        func unit(_ count: Int, _ singular: String, _ plural: String) -> String {
            count == 1 ? (singularArticle ? "1 \(singular)" : singular) : "\(count.formatted()) \(plural)"
        }
        if minutes % 10_080 == 0 { return unit(minutes / 10_080, "week", "weeks") }
        if minutes % 1_440 == 0 { return unit(minutes / 1_440, "day", "days") }
        if minutes % 60 == 0 { return unit(minutes / 60, "hour", "hours") }
        return unit(minutes, "minute", "minutes")
    }

    /// When the span starts, or nil for ``sinceUnread`` (each conversation
    /// has its own start).
    public func start(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .sinceUnread: nil
        case .today: calendar.startOfDay(for: now)
        case .last(let minutes): now.addingTimeInterval(-Double(max(1, minutes)) * 60)
        }
    }

    /// A span of `count` `unit`s, for the window's "number plus unit" field.
    public static func last(_ count: Int, _ unit: Unit) -> RecapScope.Span {
        .last(minutes: max(1, count) * unit.minutes)
    }

    /// The units the span field offers.
    public enum Unit: String, CaseIterable, Sendable {
        case minutes, hours, days

        public var minutes: Int {
            switch self {
            case .minutes: 1
            case .hours: 60
            case .days: 1_440
            }
        }
    }
}

// MARK: - What's read

/// One thing someone said, as a Recap reads it.
nonisolated public struct RecapLine: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case message, action, notice
    }

    /// The `ChatLine.id` (or saved message's id) it came from.
    public var id: UUID
    public var time: Date
    public var nick: String
    /// Plain text: IRC formatting removed. Links are kept whole.
    public var text: String
    public var kind: Kind
    /// Your own line.
    public var isSelf: Bool
    /// It named you or one of your highlight words.
    public var isHighlight: Bool
    public var msgid: String?
    /// The `msgid` it replies to.
    public var replyTo: String?

    public init(
        id: UUID = UUID(),
        time: Date,
        nick: String,
        text: String,
        kind: Kind = .message,
        isSelf: Bool = false,
        isHighlight: Bool = false,
        msgid: String? = nil,
        replyTo: String? = nil
    ) {
        self.id = id
        self.time = time
        self.nick = nick
        self.text = text
        self.kind = kind
        self.isSelf = isSelf
        self.isHighlight = isHighlight
        self.msgid = msgid
        self.replyTo = replyTo
    }

    public var isAction: Bool { kind == .action }
}

/// The lines a Recap read from one channel or conversation.
nonisolated public struct RecapConversation: Sendable, Hashable, Identifiable {
    public var id: BufferID
    /// `#vela`, or the nick of the person a private conversation is with.
    public var name: String
    public var networkName: String
    public var isChannel: Bool
    /// Your nick on its network.
    public var ownNick: String
    /// The matching lines, oldest first.
    public var lines: [RecapLine]
    /// Everything you said here in the stretch, whether or not it matched
    /// (the Who filter can leave it out): to tell whether you answered.
    public var yourLines: [RecapLine]
    /// The oldest message Vela has here, in memory or saved history.
    public var availableSince: Date?
    /// The stretch asked for starts before ``availableSince``.
    public var startsBeforeHistory: Bool
    /// Unread messages among ``lines``.
    public var unreadLines: Int

    public init(
        id: BufferID,
        name: String,
        networkName: String,
        isChannel: Bool,
        ownNick: String,
        lines: [RecapLine],
        yourLines: [RecapLine] = [],
        availableSince: Date? = nil,
        startsBeforeHistory: Bool = false,
        unreadLines: Int = 0
    ) {
        self.id = id
        self.name = name
        self.networkName = networkName
        self.isChannel = isChannel
        self.ownNick = ownNick
        self.lines = lines
        self.yourLines = yourLines
        self.availableSince = availableSince
        self.startsBeforeHistory = startsBeforeHistory
        self.unreadLines = unreadLines
    }
}

/// Everything a Recap read: the matching lines, conversation by
/// conversation, and how much of the stretch Vela has.
nonisolated public struct RecapInput: Sendable, Hashable {
    public var scope: RecapScope
    /// Conversations with matching lines, in sidebar order.
    public var conversations: [RecapConversation]
    /// When the stretch asked for starts: nil for "since your first
    /// unread", where each conversation starts at its own New marker.
    public var requestedStart: Date?
    /// When it was read.
    public var end: Date
    /// Matching messages, before ``RecapLimits/gatheredLines`` left any out.
    public var matchingLines: Int
    /// Message history is read from disk (`history.save` on, or kept).
    public var readsSavedHistory: Bool

    public init(
        scope: RecapScope,
        conversations: [RecapConversation],
        requestedStart: Date?,
        end: Date,
        matchingLines: Int? = nil,
        readsSavedHistory: Bool = false
    ) {
        self.scope = scope
        self.conversations = conversations
        self.requestedStart = requestedStart
        self.end = end
        self.matchingLines = matchingLines ?? conversations.reduce(0) { $0 + $1.lines.count }
        self.readsSavedHistory = readsSavedHistory
    }

    /// Lines read, across every conversation.
    public var lineCount: Int { conversations.reduce(0) { $0 + $1.lines.count } }

    /// Unread lines, for "Since your first unread (N messages)".
    public var unreadLines: Int { conversations.reduce(0) { $0 + $1.unreadLines } }

    public var isEmpty: Bool { lineCount == 0 }

    /// Matching messages left out because there were more than Vela reads.
    public var droppedLines: Int { max(0, matchingLines - lineCount) }

    /// The oldest and newest line read.
    public var timeRange: ClosedRange<Date>? {
        let firsts = conversations.compactMap { $0.lines.first?.time }
        let lasts = conversations.compactMap { $0.lines.last?.time }
        guard let first = firsts.min(), let last = lasts.max() else { return nil }
        return first...max(first, last)
    }

    /// The conversation with `id`.
    public func conversation(_ id: BufferID) -> RecapConversation? {
        conversations.first { $0.id == id }
    }

    /// The line with `id`, and where it is.
    public func line(_ id: UUID) -> (conversation: RecapConversation, line: RecapLine)? {
        for conversation in conversations {
            if let line = conversation.lines.first(where: { $0.id == id }) { return (conversation, line) }
        }
        return nil
    }
}

/// How much a Recap reads.
nonisolated public enum RecapLimits {
    /// The most matching messages a Recap gathers (and a log shows); the
    /// newest are kept.
    public static let gatheredLines = 10_000
    /// The most messages Apple Intelligence reads for one summary, the
    /// newest of the gathered ones: about 15 to 20 passes of the model on
    /// a Mac whose model reads 4,096 tokens at a time, a few minutes on a
    /// base M1. Narrow the scope to cover the rest.
    public static let summaryLines = 2_000
}

// MARK: - Where things are

/// The message an item of a Recap points at: where its jump link goes.
nonisolated public struct RecapReference: Sendable, Hashable {
    public var conversation: BufferID
    public var lineID: UUID
    public var time: Date

    public init(conversation: BufferID, lineID: UUID, time: Date) {
        self.conversation = conversation
        self.lineID = lineID
        self.time = time
    }
}

// MARK: - What Apple Intelligence writes

/// One subject people talked about.
nonisolated public struct RecapTopic: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// One or two short sentences.
    public var summary: String
    public var participants: [String]
    /// Where it starts, when that's known.
    public var start: RecapReference?
    /// The messages it covers, oldest first: what More detail reads.
    public var lineIDs: [UUID]

    public init(id: String, title: String, summary: String, participants: [String], start: RecapReference?, lineIDs: [UUID]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.participants = participants
        self.start = start
        self.lineIDs = lineIDs
    }
}

/// A decision, an open question or a follow-up.
nonisolated public struct RecapNote: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// What was agreed or decided.
        case decision
        /// A question nobody answered.
        case question
        /// Something someone said they'd do.
        case followUp
    }

    public var id: String
    public var kind: Kind
    public var text: String
    /// Who said they'd do it (a follow-up).
    public var owner: String?
    public var reference: RecapReference?

    public init(id: String, kind: Kind, text: String, owner: String? = nil, reference: RecapReference?) {
        self.id = id
        self.kind = kind
        self.text = text
        self.owner = owner
        self.reference = reference
    }
}

/// How far a summary has got.
nonisolated public struct RecapProgress: Sendable, Hashable {
    /// Messages read so far.
    public var messagesRead: Int
    /// Every message it reads.
    public var messagesTotal: Int
    /// Every message is read: the report is being written.
    public var isWriting: Bool
    /// Roughly how long is left, once there's a pass to go by.
    public var secondsLeft: Double?
    /// Another summary is using Apple Intelligence: this one waits its turn.
    public var isWaiting: Bool

    public init(messagesRead: Int, messagesTotal: Int, isWriting: Bool = false, secondsLeft: Double? = nil, isWaiting: Bool = false) {
        self.messagesRead = messagesRead
        self.messagesTotal = messagesTotal
        self.isWriting = isWriting
        self.secondsLeft = secondsLeft
        self.isWaiting = isWaiting
    }
}

/// Apple Intelligence's part of a Recap, possibly still being written.
nonisolated public struct RecapSummary: Sendable, Hashable {
    /// Short bullets on the whole stretch, most important first.
    public var overview: [String]
    public var topics: [RecapTopic]
    public var notes: [RecapNote]
    /// What Apple Intelligence wrote about messages that named you, by the
    /// line it wrote about ("wren asked you to review the PR").
    public var notesForYou: [UUID: String]
    /// Messages it read.
    public var messageCount: Int
    /// Messages left out because Apple Intelligence declined the part
    /// they were in.
    public var skippedMessages: Int
    /// While it's being written.
    public var progress: RecapProgress?
    /// The topics are each part's, not yet combined into the report's.
    public var topicsAreProvisional: Bool
    public var isComplete: Bool
    public var venue: CatchUpVenue
    public var cloudFallback: CatchUpCloudFallback?

    public init(
        overview: [String] = [],
        topics: [RecapTopic] = [],
        notes: [RecapNote] = [],
        notesForYou: [UUID: String] = [:],
        messageCount: Int = 0,
        skippedMessages: Int = 0,
        progress: RecapProgress? = nil,
        topicsAreProvisional: Bool = false,
        isComplete: Bool = false,
        venue: CatchUpVenue = .onDevice,
        cloudFallback: CatchUpCloudFallback? = nil
    ) {
        self.overview = overview
        self.topics = topics
        self.notes = notes
        self.notesForYou = notesForYou
        self.messageCount = messageCount
        self.skippedMessages = skippedMessages
        self.progress = progress
        self.topicsAreProvisional = topicsAreProvisional
        self.isComplete = isComplete
        self.venue = venue
        self.cloudFallback = cloudFallback
    }

    public func notes(_ kind: RecapNote.Kind) -> [RecapNote] {
        notes.filter { $0.kind == kind }
    }

    /// Where it was written, as Catch me up says it.
    public var provenance: String {
        CatchUpSummary(
            overview: "", topics: [], addressedToYou: [], messageCount: 0, isComplete: true,
            venue: venue, cloudFallback: cloudFallback
        ).provenance
    }

    public var hasContent: Bool {
        !overview.isEmpty || !topics.isEmpty || !notes.isEmpty
    }
}

/// How a summary will be made: in how many passes, about how long, where.
nonisolated public struct RecapPlan: Sendable, Hashable {
    /// Requests to Apple Intelligence: parts read, plus combining them.
    public var passes: Int
    public var transcriptTokens: Int
    /// Roughly how long it takes on this Mac (or with Private Cloud Compute).
    public var estimatedSeconds: Double
    public var venue: CatchUpVenue

    public init(passes: Int, transcriptTokens: Int, estimatedSeconds: Double, venue: CatchUpVenue = .onDevice) {
        self.passes = passes
        self.transcriptTokens = transcriptTokens
        self.estimatedSeconds = estimatedSeconds
        self.venue = venue
    }

    /// Long enough to ask before starting ("About 2 minutes on this Mac · Start").
    public var asksFirst: Bool { estimatedSeconds >= RecapPlan.askAfterSeconds }

    /// Shorter summaries start right away.
    public static let askAfterSeconds = 45.0
}

/// A closer look at one topic or note: More detail.
nonisolated public struct RecapDetail: Sendable, Hashable {
    /// Short bullets.
    public var points: [String]
    public var isComplete: Bool

    public init(points: [String] = [], isComplete: Bool = false) {
        self.points = points
        self.isComplete = isComplete
    }
}

/// What More detail reads: the messages behind one topic or note, and what
/// it's about (the topic's title or the note, as Apple Intelligence wrote
/// it from those messages).
nonisolated public struct RecapDetailRequest: Sendable, Hashable {
    /// Oldest first, one conversation.
    public var lines: [RecapLine]
    public var ownNick: String
    public var focus: String

    public init(lines: [RecapLine], ownNick: String, focus: String) {
        self.lines = lines
        self.ownNick = ownNick
        self.focus = focus
    }
}

// MARK: - Summarizing

/// Writes Recaps with Apple Intelligence. The live one runs the
/// ``RecapEngine`` on Foundation Models; demo mode uses canned results.
public protocol RecapSummarizer: AnyObject, Sendable {
    /// How `input` would be summarized, without summarizing it. Cheap: at
    /// most a token count.
    func plan(_ input: RecapInput) async -> RecapPlan
    /// Progressively more complete summaries; the last has `isComplete`.
    /// Errors are ``CatchUpError``s.
    func recap(_ input: RecapInput) -> AsyncThrowingStream<RecapSummary, Error>
    /// A closer look at one topic or note, streamed. Errors are
    /// ``CatchUpError``s.
    func detail(_ request: RecapDetailRequest) -> AsyncThrowingStream<RecapDetail, Error>
}
