// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaIRC

// Shared "Catch me up" types. The in-channel card (VelaUI) and the Siri /
// Shortcuts intent (VelaIntents) both go through `ConversationSummarizer`.

/// One thing someone said, as handed to the summarizer.
nonisolated public struct CatchUpLine: Sendable, Hashable {
    /// The `ChatLine.id` it came from, so a topic can link back to it.
    public var id: UUID
    public var time: Date
    public var nick: String
    /// Plain text: IRC formatting removed.
    public var text: String
    /// A `/me` action ("* nick waves").
    public var isAction: Bool

    public init(id: UUID, time: Date, nick: String, text: String, isAction: Bool = false) {
        self.id = id
        self.time = time
        self.nick = nick
        self.text = text
        self.isAction = isAction
    }
}

/// What to summarize.
nonisolated public struct CatchUpRequest: Sendable, Hashable {
    /// The buffer it came from.
    public var bufferID: BufferID
    /// Display name, e.g. `#vela`.
    public var bufferName: String
    public var networkName: String
    /// The reader's nick, so the summary can say when they were addressed.
    public var ownNick: String
    /// Oldest first.
    public var lines: [CatchUpLine]

    public init(bufferID: BufferID, bufferName: String, networkName: String, ownNick: String, lines: [CatchUpLine]) {
        self.bufferID = bufferID
        self.bufferName = bufferName
        self.networkName = networkName
        self.ownNick = ownNick
        self.lines = lines
    }
}

extension CatchUpRequest {
    /// The conversation in `buffer` newer than `since` (by default, the
    /// buffer's New marker or last-read time): messages, actions and
    /// notices only, with formatting stripped. Your own lines are kept for
    /// context.
    @MainActor
    public init(buffer: BufferModel, session: NetworkSession, since: Date? = nil) {
        let cutoff = since ?? buffer.unreadMarkerAfter ?? buffer.lastReadAt ?? .distantPast
        let lines = buffer.lines.lazy
            .filter { $0.kind.isConversation && $0.time > cutoff }
            .map { line in
                CatchUpLine(
                    id: line.id,
                    time: line.time,
                    nick: line.nick ?? "",
                    text: IRCFormatting.strip(line.text),
                    isAction: line.kind == .action
                )
            }
        self.init(
            bufferID: buffer.id,
            bufferName: buffer.name,
            networkName: session.displayName,
            ownNick: session.nick,
            lines: Array(lines)
        )
    }
}

/// One thread of conversation in a summary.
nonisolated public struct CatchUpTopic: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var summary: String
    /// Nicks, as written in the channel.
    public var participants: [String]
    /// The first message of this topic (a ``CatchUpLine/id``), if known.
    public var firstLineID: UUID?

    public init(id: UUID = UUID(), title: String, summary: String, participants: [String], firstLineID: UUID?) {
        self.id = id
        self.title = title
        self.summary = summary
        self.participants = participants
        self.firstLineID = firstLineID
    }
}

/// A (possibly still streaming) summary.
nonisolated public struct CatchUpSummary: Sendable, Hashable {
    /// One or two sentences on the whole stretch.
    public var overview: String
    public var topics: [CatchUpTopic]
    /// Short notes on where the reader was addressed or mentioned.
    public var addressedToYou: [String]
    /// How many lines were summarized.
    public var messageCount: Int
    /// False while the summarizer is still producing it.
    public var isComplete: Bool

    public init(overview: String, topics: [CatchUpTopic], addressedToYou: [String], messageCount: Int, isComplete: Bool) {
        self.overview = overview
        self.topics = topics
        self.addressedToYou = addressedToYou
        self.messageCount = messageCount
        self.isComplete = isComplete
    }
}

nonisolated public enum CatchUpError: Error, Equatable, LocalizedError {
    case unavailable(IntelligenceStatus)
    case nothingToSummarize
    /// The model's safety guardrails declined the conversation.
    case declined
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let status): status.detail
        case .nothingToSummarize: "There's nothing new to summarize."
        case .declined: "Apple Intelligence couldn't summarize this conversation."
        case .failed(let message): message
        }
    }
}

/// Summarizes a stretch of conversation.
public protocol ConversationSummarizer: AnyObject, Sendable {
    /// Progressively more complete summaries; the last one has
    /// `isComplete == true`. Errors are ``CatchUpError``s.
    func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error>
}

extension ConversationSummarizer {
    /// The finished summary.
    public func summary(for request: CatchUpRequest) async throws -> CatchUpSummary {
        var last: CatchUpSummary?
        for try await snapshot in summarize(request) { last = snapshot }
        guard let last else { throw CatchUpError.nothingToSummarize }
        return last
    }
}
