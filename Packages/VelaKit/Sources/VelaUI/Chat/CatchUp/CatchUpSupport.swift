// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import VelaCore
import VelaIntelligence
import VelaStore

/// When Catch me up is offered. Pure, so it's tested without views.
nonisolated enum CatchUpEligibility {
    /// Messages, actions and notices newer than `marker` (the buffer's New
    /// marker): what a summary would cover. Lines are in time order.
    static func unreadLineCount(_ lines: [ChatLine], after marker: Date?) -> Int {
        guard let marker else { return 0 }
        // Binary search for the first line after the marker.
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time > marker { high = middle } else { low = middle + 1 }
        }
        return lines[low...].reduce(0) { $0 + ($1.kind.isConversation ? 1 : 0) }
    }

    /// The button on the New marker: the feature is on, Apple Intelligence
    /// is ready, and enough is new.
    static func showsButton(isEnabled: Bool, status: IntelligenceStatus, unreadLines: Int, threshold: Int) -> Bool {
        isEnabled && status.isAvailable && unreadLines > 0 && unreadLines >= max(1, threshold)
    }

    /// Whether the buffer's open card takes the button's place: while it's
    /// summarizing, and while it covers the new messages. A card left from
    /// an earlier stretch (the New marker is past its last line) doesn't.
    static func cardHidesButton(isRunning: Bool, coversThrough: Date?, marker: Date?) -> Bool {
        if isRunning { return true }
        guard let coversThrough else { return false }
        guard let marker else { return true }
        return marker < coversThrough
    }

    /// The context menu and palette: asked for explicitly, so they're
    /// offered whenever Catch me up is on and Apple Intelligence is ready.
    /// With nothing new, choosing one shows the latest summary again or
    /// says why there's none (see ``CatchUpActions/open(_:session:app:store:)``).
    static func canOffer(isEnabled: Bool, status: IntelligenceStatus, kind: BufferKind) -> Bool {
        isEnabled && kind != .server && status.isAvailable
    }

    /// The palette's note on "Catch Me Up" when there's nothing new to
    /// summarize, so it says what choosing it will do.
    static func paletteDetail(hasUnread: Bool, hasEarlierSummary: Bool) -> String? {
        if hasUnread { return nil }
        return hasEarlierSummary ? "earlier summary" : "nothing new"
    }

    /// What a "nothing new" card says after "Nothing new in #vela since you
    /// last read it.": when the button will be back.
    static func nothingNewDetail(threshold: Int, showsNewLine: Bool) -> String {
        guard showsNewLine else {
            return "Catch me up summarizes the messages you missed. Ask again when something's new."
        }
        let count = max(1, threshold)
        let messages = count == 1 ? "a new message arrives" : "\(count) or more messages are new"
        return "Catch me up summarizes the messages you missed. Its button appears on the New line when \(messages)."
    }
}

/// Opening, refreshing and copying Catch me up summaries, shared by the
/// marker button, the card, the context menu and the palette.
@MainActor
enum CatchUpActions {
    /// Whether there's anything to catch up on: unread lines in a buffer
    /// that isn't on screen, or lines under the open buffer's New marker
    /// (opening it marked them read).
    static func hasUnread(_ buffer: BufferModel, app: AppModel) -> Bool {
        if app.selectedBufferID == buffer.id {
            return CatchUpEligibility.unreadLineCount(buffer.lines, after: buffer.unreadMarkerAfter) > 0
        }
        return buffer.unreadCount > 0
    }

    /// Shows `buffer`'s card under its New marker (where the unread lines
    /// start, when the marker is hidden) and summarizes what's new. Selects
    /// the buffer first when it isn't on screen.
    ///
    /// With nothing new, it shows the buffer's latest summary again (its
    /// stretch has been read since), or a card at the end saying there's
    /// nothing new and when the button comes back.
    static func open(_ buffer: BufferModel, session: NetworkSession, app: AppModel, store: CatchUpStore) {
        // Build the request before selecting: selecting marks the buffer
        // read, but the New marker it places covers the same lines.
        let marker = buffer.unreadMarkerAfter ?? buffer.lastReadAt
        let request = CatchUpRequest(buffer: buffer, session: session, since: marker)
        let isNew = hasUnread(buffer, app: app) && !request.lines.isEmpty
        if app.selectedBufferID != buffer.id { app.select(buffer) }
        if isNew {
            store.open(request, marker: buffer.unreadMarkerAfter ?? marker)
        } else if !store.reopen(buffer.id) {
            var nothing = request
            nothing.lines = []
            store.open(nothing, marker: buffer.lines.last?.time ?? marker)
        }
    }

    /// Summarizes the card's stretch again, including anything that has
    /// arrived since. Also Try Again after a failure. The stretch starts at
    /// the card's own anchor, wherever the live New marker has gone.
    static func regenerate(_ card: CatchUpCard, buffer: BufferModel, session: NetworkSession, store: CatchUpStore) {
        let request = CatchUpRequest(buffer: buffer, session: session, since: card.anchor)
        store.regenerate(request.lines.isEmpty ? card.request : request, marker: card.marker)
    }

    static func copy(_ summary: CatchUpSummary, bufferName: String, messageCount: Int) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plainText(summary, bufferName: bufferName, messageCount: messageCount), forType: .string)
    }

    /// The summary as plain text, for Copy.
    nonisolated static func plainText(_ summary: CatchUpSummary, bufferName: String, messageCount: Int) -> String {
        var parts = ["While you were away in \(bufferName) · \(messagesLabel(messageCount))"]
        if !summary.overview.isEmpty { parts.append(summary.overview) }
        if !summary.topics.isEmpty {
            parts.append(summary.topics.map { topic in
                var line = "• \(topic.title)"
                if !topic.summary.isEmpty { line += " — \(topic.summary)" }
                if !topic.participants.isEmpty { line += " (\(topic.participants.joined(separator: ", ")))" }
                return line
            }.joined(separator: "\n"))
        }
        if !summary.addressedToYou.isEmpty {
            parts.append((["You were mentioned:"] + summary.addressedToYou.map { "• \($0)" }).joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    /// "1 message", "42 messages", "1,240 messages".
    nonisolated static func messagesLabel(_ count: Int) -> String {
        count == 1 ? "1 message" : "\(count.formatted()) messages"
    }

    /// "kenji", "kenji and ada", "kenji, ada and theo", "kenji, ada and 2 others".
    nonisolated static func participantsLabel(_ nicks: [String]) -> String {
        switch nicks.count {
        case 0: ""
        case 1: nicks[0]
        case 2: "\(nicks[0]) and \(nicks[1])"
        case 3: "\(nicks[0]), \(nicks[1]) and \(nicks[2])"
        default: "\(nicks[0]), \(nicks[1]) and \(nicks.count - 2) others"
        }
    }
}

/// Demo mode's `--catch-up` launch argument opens the first Catch me up
/// card that's offered, so screenshots can show it:
/// `scripts/demo-screenshot.sh Vela.app out.png --select "#swift" --set intelligence.catchUpThreshold=1 --catch-up`.
@MainActor
enum CatchUpDemo {
    private static var pending = ProcessInfo.processInfo.arguments.contains("--catch-up")

    /// True once, in demo mode with `--catch-up`.
    static func takeLaunchRequest(isDemo: Bool) -> Bool {
        guard isDemo, pending else { return false }
        pending = false
        return true
    }
}
