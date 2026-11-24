// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaIRC
import VelaStore

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

/// Whose lines may go to an AI model: people's, never the server's or the
/// network's. A server can send a notice or message to a channel itself,
/// and its name stands where a nick would (`irc.example.org: …`); its
/// words are often about the server or network too. Prompts carry message
/// text and nicks only, never a channel's, network's or server's name, so
/// Catch me up and Recap leave those lines out (they aren't conversation).
nonisolated public enum PromptSpeaker {
    /// Whether `nick` is a person's: not empty, without the dot every
    /// server name has and no nick can (`irc.libera.chat`), not starting
    /// with `*` (the server, or a bouncer module such as ZNC's
    /// `*buffextras`), and not one of `serverNames` (folded with
    /// `caseMapping`), the names a network and its server go by
    /// (`NetworkSession.serverNames`), such as a server called `ircd`.
    public static func isPerson(_ nick: String, serverNames: Set<String> = [], caseMapping: CaseMapping = .rfc1459) -> Bool {
        guard !nick.isEmpty, !nick.contains("."), !nick.hasPrefix("*") else { return false }
        return serverNames.isEmpty || !serverNames.contains(caseMapping.fold(nick))
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
    /// The model to summarize with, when it isn't the one Catch me up's
    /// setting picks: chosen on the card ("Change") or in the palette
    /// ("Catch Me Up With…"). Nil follows the settings.
    public var model: AIModelChoice?

    public init(
        bufferID: BufferID,
        bufferName: String,
        networkName: String,
        ownNick: String,
        lines: [CatchUpLine],
        model: AIModelChoice? = nil
    ) {
        self.bufferID = bufferID
        self.bufferName = bufferName
        self.networkName = networkName
        self.ownNick = ownNick
        self.lines = lines
        self.model = model
    }
}

extension CatchUpRequest {
    /// The conversation in `buffer` newer than `since` (by default, the
    /// buffer's New marker or last-read time): messages, actions and
    /// notices only, with formatting stripped. Your own lines are kept for
    /// context; deleted (redacted) ones are left out, and so is anything
    /// the server or network sent rather than a person (``PromptSpeaker``).
    @MainActor
    public init(buffer: BufferModel, session: NetworkSession, since: Date? = nil) {
        let cutoff = since ?? buffer.unreadMarkerAfter ?? buffer.lastReadAt ?? .distantPast
        let serverNames = session.serverNames
        let caseMapping = session.isupport.caseMapping
        let lines = buffer.lines.lazy
            .filter { $0.kind.isConversation && !$0.isRedacted && $0.time > cutoff }
            .filter { $0.isSelf || PromptSpeaker.isPerson($0.nick ?? "", serverNames: serverNames, caseMapping: caseMapping) }
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

extension CatchUpRequest {
    /// Summaries cover at most this many of the newest lines; older ones
    /// in a longer stretch are left out.
    nonisolated public static let maximumLines = 600
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

/// How far a long summary has got before its words are written: a long
/// stretch is read in parts, and the parts' notes are combined.
nonisolated public struct CatchUpProgress: Sendable, Hashable {
    /// Parts read so far.
    public var completed: Int
    /// Every part, combining steps included. It can grow while summarizing,
    /// when a part turns out too long and is read in halves.
    public var total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    /// Every part is read: what's left is writing the summary.
    public var isFinished: Bool { completed >= total }
}

/// Where a summary is written.
nonisolated public enum CatchUpVenue: Sendable, Hashable {
    /// By Apple Intelligence on this Mac.
    case onDevice
    /// By Apple Intelligence on Apple's Private Cloud Compute: a long
    /// stretch, with `intelligence.privateCloudCompute` on (macOS 27+).
    case privateCloudCompute
    /// By one of your own providers' models (`intelligence.providers`).
    case provider(AIModelLabel)

    /// Who writes it, for "…that Apple Intelligence wouldn't summarize".
    public var writerName: String {
        switch self {
        case .onDevice, .privateCloudCompute: "Apple Intelligence"
        case .provider(let label): label.providerName
        }
    }

    /// The provider's model, when it's one.
    public var providerModel: AIModelLabel? {
        if case .provider(let label) = self { label } else { nil }
    }
}

/// A provider's model as a summary names it.
nonisolated public struct AIModelLabel: Sendable, Hashable {
    public var providerID: String
    /// "Anthropic", or a custom server's name.
    public var providerName: String
    public var modelID: String
    /// "Claude Opus 5.5", or the id when there's no nicer name.
    public var modelName: String

    public init(providerID: String, providerName: String, modelID: String, modelName: String) {
        self.providerID = providerID
        self.providerName = providerName
        self.modelID = modelID
        self.modelName = modelName
    }

    public var choice: AIModelChoice { .provider(providerID: providerID, modelID: modelID) }

    /// "Claude Opus 5.5 (Anthropic)".
    public var title: String { "\(modelName) (\(providerName))" }
}

/// Why a summary meant for Private Cloud Compute was written on this Mac.
nonisolated public enum CatchUpCloudFallback: Sendable, Hashable {
    /// It couldn't be reached, or wasn't ready.
    case unavailable
    /// The Mac's daily Private Cloud Compute limit was reached.
    case limitReached
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
    /// While a long stretch is read in parts, how many are done. Nil for a
    /// stretch read in one go, and once the summary itself is being written.
    public var progress: CatchUpProgress?
    /// The words shown are from an attempt that's being redone (it ran out
    /// of room, say). They stay, dimmed, until the new attempt writes:
    /// text that has appeared is never taken away.
    public var isRevising: Bool
    /// Messages left out because Apple Intelligence declined to summarize
    /// the part they were in.
    public var skippedMessages: Int
    /// Where it's written.
    public var venue: CatchUpVenue
    /// Set when it was meant for Private Cloud Compute but is written on
    /// this Mac instead, and why.
    public var cloudFallback: CatchUpCloudFallback?

    public init(
        overview: String,
        topics: [CatchUpTopic],
        addressedToYou: [String],
        messageCount: Int,
        isComplete: Bool,
        progress: CatchUpProgress? = nil,
        isRevising: Bool = false,
        skippedMessages: Int = 0,
        venue: CatchUpVenue = .onDevice,
        cloudFallback: CatchUpCloudFallback? = nil
    ) {
        self.overview = overview
        self.topics = topics
        self.addressedToYou = addressedToYou
        self.messageCount = messageCount
        self.isComplete = isComplete
        self.progress = progress
        self.isRevising = isRevising
        self.skippedMessages = skippedMessages
        self.venue = venue
        self.cloudFallback = cloudFallback
    }

    /// Whether there are words to show yet.
    public var hasText: Bool { !overview.isEmpty }

    /// Where it was written, for the card's footer and Siri's snippet:
    /// "Summarized on this Mac by Apple Intelligence.", with Private Cloud
    /// Compute, or on this Mac because Private Cloud Compute wasn't there.
    public var provenance: String {
        switch (venue, cloudFallback) {
        case (.provider(let label), _):
            "Summarized by \(label.title)."
        case (.privateCloudCompute, _):
            "Summarized by Apple Intelligence with Private Cloud Compute."
        case (.onDevice, .limitReached?):
            "Summarized on this Mac by Apple Intelligence: today's Private Cloud Compute limit was reached."
        case (.onDevice, .unavailable?):
            "Summarized on this Mac by Apple Intelligence: Private Cloud Compute wasn't available."
        case (.onDevice, nil):
            Self.onDeviceProvenance
        }
    }

    /// ``provenance`` before there's a summary to go by.
    public static let onDeviceProvenance = "Summarized on this Mac by Apple Intelligence."
}

/// How a stretch will be summarized: where, and in how many passes.
/// Siri uses it to decide whether to answer itself or open Vela.
nonisolated public struct CatchUpPlan: Sendable, Hashable {
    public var venue: CatchUpVenue
    /// Parts the transcript is read in: 1 when one request holds it all.
    public var passes: Int
    /// The transcript's size in tokens: counted where the system can,
    /// otherwise estimated.
    public var transcriptTokens: Int
    /// Roughly how long it takes, when there's a measurement or estimate
    /// to go by (Private Cloud Compute); nil otherwise.
    public var estimatedSeconds: Double?
    /// Private Cloud Compute is on but won't be used, and why.
    public var cloudFallback: CatchUpCloudFallback?

    public init(
        venue: CatchUpVenue = .onDevice,
        passes: Int,
        transcriptTokens: Int,
        estimatedSeconds: Double? = nil,
        cloudFallback: CatchUpCloudFallback? = nil
    ) {
        self.venue = venue
        self.passes = passes
        self.transcriptTokens = transcriptTokens
        self.estimatedSeconds = estimatedSeconds
        self.cloudFallback = cloudFallback
    }

    /// One request summarizes the whole stretch.
    public var isOnePass: Bool { passes <= 1 }
}

nonisolated public enum CatchUpError: Error, Equatable, LocalizedError {
    case unavailable(IntelligenceStatus)
    case nothingToSummarize
    /// The model's safety guardrails declined the conversation (every part
    /// of it; parts it declines are otherwise skipped).
    case declined
    /// Apple Intelligence turned the request away for now; it limits how
    /// much an app asks of it, more so in the background (Siri, Shortcuts).
    case rateLimited
    /// The conversation is in a language the model can't summarize. Not
    /// ``IntelligenceStatus/unsupportedLanguage``, which is about the
    /// Mac's own language and has a fix in System Settings; this has none.
    case conversationLanguageUnsupported
    /// One of your providers couldn't do it, or isn't ready to (no key,
    /// turned off, or waiting for your OK to send it messages).
    case provider(AIProviderFailure)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let status): status.detail
        case .provider(let failure): failure.message
        case .nothingToSummarize: "There's nothing new to summarize."
        case .declined: "Apple Intelligence couldn't summarize this conversation."
        case .rateLimited: "Apple Intelligence is busy. Try again in a moment."
        case .conversationLanguageUnsupported: "This conversation's language isn't supported for summaries yet."
        case .failed(let message): message
        }
    }
}

/// Summarizes a stretch of conversation.
public protocol ConversationSummarizer: AnyObject, Sendable {
    /// Progressively more complete summaries; the last one has
    /// `isComplete == true`. Errors are ``CatchUpError``s.
    func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error>

    /// How `request` would be summarized, without summarizing it. Cheap:
    /// at most a token count.
    func plan(_ request: CatchUpRequest) async -> CatchUpPlan
}

extension ConversationSummarizer {
    /// One pass on this Mac: summarizers without a model to measure
    /// against (canned ones, for demo mode and tests).
    public func plan(_ request: CatchUpRequest) async -> CatchUpPlan {
        CatchUpPlan(passes: 1, transcriptTokens: 0)
    }

    /// The finished summary.
    public func summary(for request: CatchUpRequest) async throws -> CatchUpSummary {
        var last: CatchUpSummary?
        for try await snapshot in summarize(request) { last = snapshot }
        guard let last else { throw CatchUpError.nothingToSummarize }
        return last
    }
}
