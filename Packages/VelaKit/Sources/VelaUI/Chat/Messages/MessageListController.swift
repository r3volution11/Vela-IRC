// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// Per-list state shared by the message list and its rows: caches, the
/// row being flashed, expanded membership runs and pending deletions.
/// Scroll bookkeeping that changes on every frame is `@ObservationIgnored`
/// so scrolling never re-evaluates rows.
@Observable
final class MessageListController {
    let buffer: BufferModel
    let session: NetworkSession

    /// Line briefly tinted after jumping to it (reply quote clicks).
    var flashedLineID: UUID?
    /// Membership runs the user expanded, keyed by their first line.
    var expandedRuns: Set<UUID> = []
    /// Message awaiting delete confirmation.
    var pendingDeletion: ChatLine?
    /// Show the "Jump to present" pill.
    var showsJumpToPresent = false
    /// Conversation lines that arrived while scrolled away from the bottom.
    var unseenCount = 0

    @ObservationIgnored let displayCache = MessageDisplayCache()
    @ObservationIgnored let textCache = MessageTextCache()
    @ObservationIgnored private(set) var isPinnedToBottom = true
    @ObservationIgnored var topVisibleID: DisplayItemID?
    @ObservationIgnored var lastSeenLineID: UUID?
    @ObservationIgnored var flashTask: Task<Void, Never>?
    /// While a programmatic scroll animates, scroll geometry changes don't
    /// pin or unpin the list.
    @ObservationIgnored var pinningSuspendedUntil = Date.distantPast
    @ObservationIgnored var isUserScrolling = false
    @ObservationIgnored var distanceFromBottom: CGFloat = 0
    @ObservationIgnored var containerHeight: CGFloat = 0

    init(buffer: BufferModel, session: NetworkSession) {
        self.buffer = buffer
        self.session = session
        lastSeenLineID = buffer.lines.last?.id
    }

    func suspendPinning(for seconds: TimeInterval = 0.6) {
        pinningSuspendedUntil = Date().addingTimeInterval(seconds)
    }

    /// Whether content-size changes keep the bottom in place. Observed (the
    /// list's scroll anchor depends on it), so only written when it flips.
    private(set) var anchorsToBottom = true

    func setPinned(_ pinned: Bool) {
        isPinnedToBottom = pinned
        if anchorsToBottom != pinned { anchorsToBottom = pinned }
    }

    /// Bottom-anchors size changes while older history is inserted above.
    private(set) var holdsAnchorForHistory = false

    func setHoldsAnchorForHistory(_ holds: Bool) {
        if holdsAnchorForHistory != holds { holdsAnchorForHistory = holds }
    }

    // MARK: Actions shared by the hover toolbar, context menu and accessibility

    var canReact: Bool { session.supportsReactions && buffer.kind != .server }

    func canReact(to line: ChatLine) -> Bool { canReact && line.msgid != nil && !line.isRedacted }

    func canReply(to line: ChatLine) -> Bool {
        session.supportsReplies && line.msgid != nil && buffer.kind != .server && !line.isRedacted
    }

    func canDelete(_ line: ChatLine) -> Bool {
        line.isSelf && line.msgid != nil && session.supportsRedaction && !line.isRedacted
    }

    /// Adds `emoji` (from a picker); does nothing if we already reacted with it.
    func addReaction(_ emoji: String, to line: ChatLine) {
        EmojiRecents.record(emoji)
        let existing = buffer.reactions(for: line.msgid).first { $0.emoji == emoji }
        guard existing?.includesSelf != true else { return }
        session.toggleReaction(emoji, on: line, in: buffer)
    }

    func toggleReaction(_ emoji: String, on line: ChatLine) {
        EmojiRecents.record(emoji)
        session.toggleReaction(emoji, on: line, in: buffer)
    }

    func reply(to line: ChatLine, uiState: UIState) {
        uiState.replyTargets[buffer.id] = line
        uiState.focusInput()
    }

    func copyText(of line: ChatLine) {
        let text = IRCFormatting.strip(line.text)
        let copied: String
        switch line.kind {
        case .action: copied = "* \(line.nick ?? "") \(text)"
        default: copied = text
        }
        copyToPasteboard(copied)
    }

    func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func message(_ nick: String) {
        session.submit("/query \(nick)", in: buffer)
    }

    func whois(_ nick: String) {
        session.submit("/whois \(nick)", in: buffer)
    }

    func confirmDelete(_ line: ChatLine) {
        pendingDeletion = line
    }

    func delete(_ line: ChatLine) {
        session.redact(line, in: buffer)
        pendingDeletion = nil
    }

    func flash(_ lineID: UUID, reduceMotion: Bool) {
        flashTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { flashedLineID = lineID }
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, let self else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { self.flashedLineID = nil }
        }
    }

    func toggleRun(_ id: UUID) {
        if expandedRuns.contains(id) { expandedRuns.remove(id) } else { expandedRuns.insert(id) }
    }
}

/// Fixed widths for timestamp columns (classic and columns layouts), so
/// times line up whatever the format (`HH:mm`, `h:mm a`, `HH:mm:ss`…).
enum TimestampMetrics {
    private static var cache: [String: CGFloat] = [:]

    static func columnWidth(style: ChatStyle, bracketed: Bool) -> CGFloat {
        let size = max(9, style.fontSize - 2)
        let key = "\(style.timestampFormat)|\(size)|\(bracketed)"
        if let cached = cache[key] { return cached }
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        // Wide samples: two-digit hours in the morning and afternoon.
        let samples = [(10, 58, 58), (22, 58, 58), (12, 0, 0)].compactMap { hour, minute, second in
            calendar.date(from: DateComponents(year: 2026, month: 12, day: 28, hour: hour, minute: minute, second: second))
        }
        let widest = samples.map { date -> CGFloat in
            let text = bracketed ? "[\(style.timestamp(date))]" : style.timestamp(date)
            return (text as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 36
        let width = ceil(widest) + 1
        cache[key] = width
        return width
    }
}

extension ChatStyle {
    /// Avatar diameter in the grouped layout, scaled with the font size.
    var avatarSize: CGFloat { (fontSize * 2.5).rounded() }

    /// Leading/trailing inset of every row.
    var rowHorizontalPadding: CGFloat { 20 }
}

extension ResolvedTheme {
    /// The color for `nick` in message headers, honoring `chat.colorNicks`
    /// and `chat.selfNick`.
    func nickDisplayColor(_ nick: String?, isSelf: Bool, colorNicks: Bool) -> Color {
        if isSelf { return self[ThemeKey.chatSelfNick] }
        guard let nick, colorNicks else { return self[ThemeKey.chatForeground] }
        return nickColor(for: nick).color
    }
}
