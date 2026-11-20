// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import SwiftUI
import VelaCore
import VelaFoundation
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
    /// New lines and sent messages since the last update. Started when the
    /// list appears (`trackLines()`), not in `init`: SwiftUI makes a
    /// controller every time the list's parent runs and keeps only the first.
    @ObservationIgnored var lineTracker: LineTracker?
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
    @ObservationIgnored private var followsAnew = false

    var isPinnedToBottom: Bool { pinning.isPinned }
    var metrics: ScrollMetrics? { pinning.metrics }

    var scrollDriver: ScrollPinning.Driver {
        if Date() < programmaticScrollEnds { return .programmatic }
        return isUserScrolling ? .user : .idle
    }

    init(buffer: BufferModel, session: NetworkSession) {
        self.buffer = buffer
        self.session = session
    }

    /// Starts noticing new lines from the ones there now; once.
    func trackLines() {
        if lineTracker == nil { lineTracker = LineTracker(lines: buffer.lines) }
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

    /// How the list should follow new scroll geometry.
    enum Follow: Equatable {
        /// Stay where it is.
        case stay
        /// Scroll to the bottom.
        case scroll
        /// Scroll to the bottom although SwiftUI says it's there
        /// (`ScrollPinning.mustScrollToBottomAnew`).
        case scrollAnew
    }

    /// Feeds new scroll geometry to the pinning logic. Says whether the list
    /// should scroll to the bottom.
    func scrollGeometryChanged(_ metrics: ScrollMetrics) -> Follow {
        let previous = pinning.metrics
        let driver = scrollDriver
        let follow = pinning.update(metrics, driver: driver)
        syncAnchor()
        if pinning.mustScrollToBottomAnew(from: previous, to: metrics, driver: driver) { return .scrollAnew }
        return follow ? .scroll : .stay
    }

    /// Runs `scrollToBottom` once on the next main-actor turn, however many
    /// geometry changes ask for it before then, if the list is still pinned
    /// and the reader isn't scrolling. It's told to scroll anew when any of
    /// them asked for that.
    ///
    /// Geometry changes are reported during layout. Scrolling from there
    /// changes the geometry being reported and lays the list out again in
    /// the same pass. While rows are being re-measured (media switching
    /// between full and compact, lazy rows replacing estimates) that can
    /// keep re-requesting layout within one display cycle, which AppKit
    /// treats as a fatal loop. Following on the next turn lets each pass
    /// finish first.
    func queueFollow(_ follow: Follow, _ scrollToBottom: @escaping @MainActor (_ anew: Bool) -> Void) {
        guard follow != .stay else { return }
        if follow == .scrollAnew { followsAnew = true }
        guard !followQueued else { return }
        followQueued = true
        Task { [weak self] in
            guard let self else { return }
            let anew = self.followsAnew
            self.followQueued = false
            self.followsAnew = false
            guard self.isPinnedToBottom, !self.isUserScrolling else { return }
            // Got there meanwhile (the space after the last row came into
            // view), unless that's what SwiftUI says and can't be taken at
            // its word.
            if !anew, let metrics = self.metrics, ScrollPinning.isAtBottom(metrics) { return }
            scrollToBottom(anew)
        }
    }

    /// Tracks scroll gestures; when one ends, a reader who stopped near the
    /// bottom follows it again, and the row under the pointer shows its
    /// hover state.
    func scrollPhaseChanged(isUserScrolling scrolling: Bool) {
        let ended = isUserScrolling && !scrolling
        isUserScrolling = scrolling
        if ended {
            pinning.gestureEnded()
            syncAnchor()
            if let pending = pendingHover {
                pendingHover = nil
                pending.apply(true)
            }
        }
    }

    // MARK: Hover

    /// A row the pointer came onto during a scroll; it shows its hover
    /// state once the scroll ends.
    @ObservationIgnored private var pendingHover: (row: UUID, apply: (Bool) -> Void)?

    /// Passes a row's hover change on to `apply`, except while the reader
    /// scrolls: rows passing under the pointer would each run again and
    /// fade their toolbar in and out. Only the last row entered then is
    /// remembered, for when the scroll ends; leaving a row always applies.
    func hoverChanged(_ hovering: Bool, row: UUID, apply: @escaping (Bool) -> Void) {
        if hovering, isUserScrolling {
            pendingHover = (row, apply)
            return
        }
        if pendingHover?.row == row { pendingHover = nil }
        apply(hovering)
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

    // MARK: Text

    /// Bumped whenever all message text renders differently (our nick, the
    /// theme, fonts, formatting). Rows skip updates while their item is
    /// unchanged, so it's part of what they compare (`DisplayItemRow`).
    @ObservationIgnored private(set) var textGeneration = 0
    @ObservationIgnored private var textInputs: (palette: MessageTextPalette, options: MessageTextOptions)?

    /// Points `textCache` at the current palette and options and catches up
    /// with who came and went (`nickChangeCount`, the buffer's
    /// `BufferModel.nickChangeCount`, read by the list so it updates when
    /// that changes); returns the text generation. Cheap when nothing
    /// changed.
    @discardableResult
    func prepareText(palette: MessageTextPalette, options: MessageTextOptions, nickChangeCount: Int = 0) -> Int {
        let geometry = palette.nickGeometry
        textCache.prepare(palette: palette, options: options, nicks: options.colorsNicks ? { [unowned self] word, folded in
            self.nickColorIndex(word: word, folded: folded, geometry: geometry)
        } : nil)
        if let textInputs, textInputs.options == options, textInputs.palette == palette {
            catchUpWithNickChanges(nickChangeCount, colorsNicks: options.colorsNicks)
            return textGeneration
        }
        if textInputs != nil { textGeneration &+= 1 }
        textInputs = (palette, options)
        // Everything renders anew, so earlier nick changes are covered.
        nickChangesSeen = nickChangeCount
        textStamps.removeAll()
        return textGeneration
    }

    // MARK: Nicks in message text

    // Messages color the nicks of the people here (`chat.colorNicksInText`).
    // Who's here changes all the time in a busy channel, and re-rendering
    // every row on each join would cost the most where it's felt most, so:
    //
    // - Rendering looks each nick-like word up in the members, a hash
    //   lookup by case-folded nick (`nickColorIndex(word:folded:geometry:)`),
    //   and notes the keys of the words it looked up in the rendering
    //   (`RenderedText.nickKeys`).
    // - The buffer counts and logs the nicks that came, went or got
    //   another color (`BufferModel.nickChanges(since:)`). The list reads
    //   the count. SwiftUI updates it at most once per runloop turn,
    //   however many changes came in that turn, so a burst is caught up
    //   with once (and NAMES on joining is a single change: the members
    //   are replaced at once).
    // - Here, once per list update, the cache drops only the renderings
    //   with one of those nicks, and their lines get a new stamp
    //   (`textStamp(for:)`), so only those rows run again. Rows off screen
    //   render when they scroll in, as before. Nothing else is touched:
    //   a join of someone nobody mentioned costs a scan of the cache's keys.
    // - A burst too big to sort out (a netsplit, a fresh NAMES, a
    //   reconnect) drops everything once, like a theme switch.

    /// `buffer.nickChangeCount` when the cache last caught up.
    @ObservationIgnored private var nickChangesSeen = 0
    /// Lines whose rendering was dropped for a nick change, by when.
    @ObservationIgnored private var textStamps: [UUID: Int] = [:]
    @ObservationIgnored private var textStampCount = 0
    /// More changed nicks than this at once start over instead.
    private static let nickChangesSortedOut = 64

    /// For a row: changes when its line's text has to render again for a
    /// nick change (`DisplayItemRow`). 0 for nearly every row.
    func textStamp(for item: DisplayItem) -> Int {
        guard !textStamps.isEmpty, case .line(let lineItem) = item else { return 0 }
        return textStamps[lineItem.line.id] ?? 0
    }

    private func catchUpWithNickChanges(_ count: Int, colorsNicks: Bool) {
        guard count != nickChangesSeen else { return }
        let seen = nickChangesSeen
        nickChangesSeen = count
        guard colorsNicks else { return }
        let caseMapping = session.isupport.caseMapping
        guard let nicks = buffer.nickChanges(since: seen), nicks.count <= Self.nickChangesSortedOut else {
            textCache.removeAll()
            textStamps.removeAll()
            textGeneration &+= 1
            return
        }
        let dropped = textCache.invalidate(nickKeys: Set(nicks.map { MessageTextRenderer.nickKey(caseMapping.fold($0)) }))
        guard !dropped.isEmpty else { return }
        textStampCount &+= 1
        for id in dropped { textStamps[id] = textStampCount }
        if textStamps.count > textCache.capacity {
            // Stamps outlive renderings; when they pile up, one full pass.
            textStamps.removeAll()
            textGeneration &+= 1
        }
    }

    /// The color (an index into the palette's nick colors) of `word` in
    /// this buffer's text when it's someone here: a channel member, or the
    /// person a conversation is with; nil for any other word. The same
    /// color their messages and the member list show
    /// (`ResolvedTheme.nickColor(for:in:)`). Runs inside row bodies, so it
    /// reads nothing observed.
    func nickColorIndex(word: Substring, folded: String, geometry: NickPaletteGeometry) -> Int? {
        switch buffer.kind {
        case .channel:
            guard let member = buffer.member(foldedNick: folded) else { return nil }
            return buffer.nickColorIndex(for: member.nick, palette: geometry)
        case .query:
            guard folded == buffer.id.foldedName else { return nil }
            return buffer.nickColorIndex(for: String(word), palette: geometry)
        case .server:
            return nil
        }
    }

    // MARK: Links

    @ObservationIgnored private var openURLAction: OpenURLAction?

    /// Opens links in the list: channel links show or join the channel, the
    /// rest go to the system. One action for the list's life: a new one
    /// each time the list updated would update every link view under it.
    func openURL(app: AppModel) -> OpenURLAction {
        if let openURLAction { return openURLAction }
        let action = OpenURLAction { [weak self, weak app] url in
            guard let self, let app else { return .systemAction }
            return self.open(url, app: app)
        }
        openURLAction = action
        return action
    }

    private func open(_ url: URL, app: AppModel) -> OpenURLAction.Result {
        guard let channel = ChannelLink.channel(from: url) else { return .systemAction }
        if let existing = session.buffer(named: channel), existing.isJoined || !session.isConnected {
            app.select(existing)
        } else {
            session.submit("/join \(channel)", in: buffer)
        }
        return .handled
    }

    // MARK: Row caches

    private struct LabelEntry {
        var text: String
        var isRedacted: Bool
        var isHighlight: Bool
        var label: String
    }

    @ObservationIgnored private var accessibilityLabels: [UUID: LabelEntry] = [:]

    /// A row's VoiceOver label, made by `make` once per line (and again if
    /// its text, deletion or highlight changes). Rows set it every time
    /// they're built, VoiceOver or not.
    func accessibilityLabel(for line: ChatLine, make: () -> String) -> String {
        if let entry = accessibilityLabels[line.id], entry.text == line.text,
           entry.isRedacted == line.isRedacted, entry.isHighlight == line.isHighlight {
            return entry.label
        }
        let label = make()
        if accessibilityLabels.count >= 2_000 { accessibilityLabels.removeAll(keepingCapacity: true) }
        accessibilityLabels[line.id] = LabelEntry(text: line.text, isRedacted: line.isRedacted, isHighlight: line.isHighlight, label: label)
        return label
    }

    @ObservationIgnored private var runSummaries: [UUID: (count: Int, summary: String)] = [:]

    /// A collapsed run's summary, made once per run as long as it doesn't
    /// grow (its row runs again on hover).
    func summary(of run: MembershipRun) -> String {
        if let cached = runSummaries[run.id], cached.count == run.lines.count { return cached.summary }
        let summary = run.summary
        if runSummaries.count >= 500 { runSummaries.removeAll(keepingCapacity: true) }
        runSummaries[run.id] = (run.lines.count, summary)
        return summary
    }
}

/// Fixed widths for timestamp columns (classic and columns layouts), so
/// times line up whatever the format (`HH:mm`, `h:mm a`, `HH:mm:ss`…).
enum TimestampMetrics {
    private struct Key: Hashable {
        var localeIdentifier: String
        var pattern: String
        var size: Double
        var bracketed: Bool
    }

    private static var cache: [Key: CGFloat] = [:]
    /// The last width asked for. Rows ask several times each, nearly
    /// always for the same one; comparing is cheaper than hashing.
    private static var last: (key: Key, width: CGFloat)?

    /// The widest time at `size` (default: `style.timestampFont`'s size).
    static func columnWidth(style: ChatStyle, bracketed: Bool, size: Double? = nil) -> CGFloat {
        let size = size ?? max(9, style.fontSize - 2)
        let key = Key(localeIdentifier: style.timestampLocaleIdentifier, pattern: style.timestampPattern, size: size, bracketed: bracketed)
        if let last, last.key == key { return last.width }
        if let cached = cache[key] {
            last = (key, cached)
            return cached
        }
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
        last = (key, width)
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
    /// and `chat.selfNick`. Your own nick is always `chat.selfNick`, and
    /// nobody else is given a color like it (`NickPaletteGeometry.reserved`).
    func nickDisplayColor(_ nick: String?, isSelf: Bool, colorNicks: Bool, in buffer: BufferModel?) -> Color {
        if isSelf { return self[ThemeKey.chatSelfNick] }
        guard let nick, colorNicks else { return self[ThemeKey.chatForeground] }
        return nickColor(for: nick, in: buffer).color
    }

    /// A member's nick in the member list: dimmed while away, otherwise the
    /// color their messages show, `chat.selfNick` for yours; the list's own
    /// text color for others when nicks aren't colored.
    func memberListNickColor(_ member: Member, isSelf: Bool, colorNicks: Bool, in buffer: BufferModel?) -> Color {
        if member.isAway { return self[ThemeKey.memberListAwayForeground] }
        if isSelf { return self[ThemeKey.chatSelfNick] }
        if colorNicks { return nickColor(for: member.nick, in: buffer).color }
        return self[ThemeKey.memberListForeground]
    }
}

extension EnvironmentValues {
    /// The conversation nick colors come from (see
    /// `ResolvedTheme.nickColor(for:in:)`); set by the chat pane.
    @Entry var nickColorBuffer: BufferModel?
}
