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
    @ObservationIgnored var flashTask: Task<Void, Never>?

    // MARK: Scroll state

    /// Whether the list follows the newest line. See `ScrollPinning`.
    @ObservationIgnored private(set) var pinning = ScrollPinning()
    /// New lines and sent messages since the last update.
    @ObservationIgnored var lineTracker: LineTracker
    @ObservationIgnored var topVisibleID: DisplayItemID?
    /// Where the space after the last row was last laid out, in content
    /// coordinates.
    @ObservationIgnored var endFrame: CGRect?
    /// The checks that a scroll to the bottom got there
    /// (`MessageListView.scrollToBottom`).
    @ObservationIgnored var bottomCheck: Task<Void, Never>?
    /// The user is dragging or flinging the list (trackpad or wheel gesture).
    @ObservationIgnored private(set) var isUserScrolling = false
    @ObservationIgnored private var programmaticScrollEnds = Date.distantPast
    @ObservationIgnored private var programmaticScrollGeneration = 0
    @ObservationIgnored private var followQueued = false

    var isPinnedToBottom: Bool { pinning.isPinned }
    var metrics: ScrollMetrics? { pinning.metrics }

    var scrollDriver: ScrollPinning.Driver {
        if Date() < programmaticScrollEnds { return .programmatic }
        return isUserScrolling ? .user : .idle
    }

    init(buffer: BufferModel, session: NetworkSession) {
        self.buffer = buffer
        self.session = session
        lineTracker = LineTracker(lines: buffer.lines)
    }

    /// Whether content-size changes keep the bottom in place. Observed (the
    /// list's scroll anchor depends on it), so only written when it flips.
    private(set) var anchorsToBottom = true

    /// Where the rows end (`ScrollMetrics.contentEnd`) when the space after
    /// the last row is laid out in the visible rect of `metrics`; nil when
    /// it's somewhere else, or nowhere.
    func contentEnd(in metrics: ScrollMetrics) -> CGFloat? {
        guard let endFrame, endFrame.maxY > metrics.visibleMinY, endFrame.minY < metrics.visibleMaxY else { return nil }
        return endFrame.maxY
    }

    /// Feeds new scroll geometry to the pinning logic. Returns true when the
    /// list should scroll to the bottom.
    func scrollGeometryChanged(_ metrics: ScrollMetrics) -> Bool {
        let follow = pinning.update(metrics, driver: scrollDriver)
        syncAnchor()
        return follow
    }

    /// Runs `scrollToBottom` once on the next main-actor turn, however many
    /// geometry changes ask for it before then, if the list is still pinned
    /// and the reader isn't scrolling.
    ///
    /// Geometry changes are reported during layout. Scrolling from there
    /// changes the geometry being reported and lays the list out again in
    /// the same pass. While rows are being re-measured (media switching
    /// between full and compact, lazy rows replacing estimates) that can
    /// keep re-requesting layout within one display cycle, which AppKit
    /// treats as a fatal loop. Following on the next turn lets each pass
    /// finish first.
    func queueFollow(_ scrollToBottom: @escaping @MainActor () -> Void) {
        guard !followQueued else { return }
        followQueued = true
        Task { [weak self] in
            guard let self else { return }
            self.followQueued = false
            guard self.isPinnedToBottom, !self.isUserScrolling else { return }
            // Got there meanwhile (the space after the last row came into view).
            if let metrics = self.metrics, ScrollPinning.isAtBottom(metrics) { return }
            scrollToBottom()
        }
    }

    /// Tracks scroll gestures; when one ends, a reader who stopped near the
    /// bottom follows it again.
    func scrollPhaseChanged(isUserScrolling scrolling: Bool) {
        let ended = isUserScrolling && !scrolling
        isUserScrolling = scrolling
        if ended {
            pinning.gestureEnded()
            syncAnchor()
        }
    }

    func pin() {
        pinning.pin()
        syncAnchor()
    }

    func unpin() {
        pinning.unpin()
        syncAnchor()
    }

    private func syncAnchor() {
        if anchorsToBottom != pinning.isPinned { anchorsToBottom = pinning.isPinned }
    }

    /// Marks a programmatic scroll as running for `seconds`: geometry
    /// changes meanwhile don't pin or unpin. Afterwards the pinned state is
    /// re-derived from where the list landed and `completion` is told
    /// whether it should still scroll to the bottom.
    func beginProgrammaticScroll(for seconds: TimeInterval = 0.6, completion: @escaping (Bool) -> Void) {
        programmaticScrollEnds = Date().addingTimeInterval(seconds)
        programmaticScrollGeneration &+= 1
        let generation = programmaticScrollGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, generation == self.programmaticScrollGeneration else { return }
            let follow = self.pinning.settle()
            self.syncAnchor()
            completion(follow)
        }
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

    /// The widest time at `size` (default: `style.timestampFont`'s size).
    static func columnWidth(style: ChatStyle, bracketed: Bool, size: Double? = nil) -> CGFloat {
        let size = size ?? max(9, style.fontSize - 2)
        let key = "\(style.timestampLocaleIdentifier)|\(style.timestampPattern)|\(size)|\(bracketed)"
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

    /// Size of the small times in the grouped layout's gutter (hover times
    /// on continuation lines) and after event text.
    var gutterTimestampSize: Double { max(9, fontSize - 3) }

    var gutterTimestampFont: Font { .system(size: gutterTimestampSize).monospacedDigit() }
}

/// Horizontal geometry of the grouped layout, shared by message rows, event
/// rows and reply quotes: a leading inset, a gutter, then the text column
/// where names, messages, media, reactions and quotes all line up.
///
/// With avatars the gutter holds them. Without, it's a slim column just
/// wide enough for a continuation line's hover time and event icons, so
/// the text sits at a modest inset instead of beside an empty avatar space.
struct GroupedMetrics: Equatable {
    /// From the row's leading edge to the gutter.
    let leading: CGFloat
    let gutter: CGFloat
    /// Between the gutter and the text column.
    let spacing: CGFloat

    /// From the row's leading edge to the text column.
    var textX: CGFloat { leading + gutter + spacing }

    @MainActor
    init(style: ChatStyle) {
        if style.showAvatars {
            leading = style.rowHorizontalPadding
            gutter = style.avatarSize
            spacing = 10
        } else {
            let time = style.showTimestamps
                ? TimestampMetrics.columnWidth(style: style, bracketed: false, size: style.gutterTimestampSize)
                : 0
            let icon = CGFloat(style.fontSize).rounded()
            gutter = max(time, icon)
            spacing = 7
            // Text about two row paddings in; wide time formats push it further.
            leading = max(8, style.rowHorizontalPadding * 2 - gutter - spacing)
        }
    }
}

extension ResolvedTheme {
    /// `nick`'s color in `buffer`'s conversation, where the people talking
    /// get different colors; its usual color without a conversation.
    func nickColor(for nick: String, in buffer: BufferModel?) -> ThemeColor {
        guard let buffer else { return nickColor(for: nick) }
        return nickColor(at: buffer.nickColorIndex(for: nick, palette: nickPaletteGeometry))
    }

    /// The color for `nick` in message headers, honoring `chat.colorNicks`
    /// and `chat.selfNick`.
    func nickDisplayColor(_ nick: String?, isSelf: Bool, colorNicks: Bool, in buffer: BufferModel?) -> Color {
        if isSelf { return self[ThemeKey.chatSelfNick] }
        guard let nick, colorNicks else { return self[ThemeKey.chatForeground] }
        return nickColor(for: nick, in: buffer).color
    }
}

extension EnvironmentValues {
    /// The conversation nick colors come from (see
    /// `ResolvedTheme.nickColor(for:in:)`); set by the chat pane.
    @Entry var nickColorBuffer: BufferModel?
}
