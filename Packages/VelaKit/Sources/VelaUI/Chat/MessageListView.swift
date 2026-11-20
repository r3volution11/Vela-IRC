// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaIRC
import VelaStore
import VelaTheme

/// The scrollback of one buffer in the classic, grouped or columns layout.
///
/// Lines become display items (day dividers, the unread marker, collapsed
/// join/part runs, grouped messages) in `MessageDisplayCache`, which only
/// processes new lines on append; message text is rendered once per line in
/// `MessageTextCache`. Rows live in a `LazyVStack`, so only visible rows
/// are built.
///
/// Scrolling follows `ScrollPinning`: the list opens at the bottom (or at
/// the unread marker, per `chat.openAt`; see `ListLanding`) and stays pinned
/// there — through new lines, media that loads late, reactions, the composer
/// growing, resizes and style changes — until the reader scrolls up. Then
/// nothing moves them and a "Jump to present" pill counts what's new.
/// Sending a message always returns to the bottom. The bottom is always the
/// space after the last row (`DisplayItemID.end`), never the content's
/// bottom edge, which is partly estimated (see `scrollToBottom()`). And
/// it's where AppKit's clip view shows the list, not only where SwiftUI
/// reports it (`ClipViewSync`).
///
/// The typing line floats over the bottom of the list; the space under the
/// last row grows to fit it only while someone is typing (`ListEndSpacing`).
struct MessageListView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let buffer: BufferModel
    let session: NetworkSession

    @State private var controller: MessageListController
    @State private var position = ScrollPosition(idType: DisplayItemID.self)
    /// Someone is typing: the typing line shows and the list makes room for it.
    @State private var typingShown = false
    /// The typing line's measured height.
    @State private var typingLineHeight: CGFloat = 0

    /// The rows' own coordinate space: content coordinates.
    private static let contentSpace = "MessageListContent"

    init(buffer: BufferModel, session: NetworkSession) {
        self.buffer = buffer
        self.session = session
        _controller = State(initialValue: MessageListController(buffer: buffer, session: session))
    }

    var body: some View {
        let options = MessageDisplayOptions(
            joinPart: style.joinPart,
            groupingInterval: style.groupingInterval,
            unreadMarkerAfter: buffer.unreadMarkerAfter,
            showsUnreadMarker: style.showUnreadMarker,
            catchUpCardAfter: intelligence.catchUp.cards[buffer.id]?.anchor
        )
        let items = controller.displayCache.items(for: buffer.lines, options: options)
        let textGeneration = controller.prepareText(
            palette: .cached(theme: theme, style: style),
            options: MessageTextOptions(
                renderFormatting: style.renderFormatting,
                selfNick: session.nick,
                channelTypes: session.isupport.channelTypes,
                colorsNicks: style.colorNicks && style.colorNicksInText && buffer.kind != .server,
                caseMapping: session.isupport.caseMapping
            ),
            // Observed: someone coming or going updates the list, which
            // re-renders the lines that mention them (and only those).
            nickChangeCount: buffer.nickChangeCount
        )

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HistoryHeader(buffer: buffer, title: BufferTitle.title(for: buffer, in: session))
                ForEach(items) { item in
                    DisplayItemRow(item: item, textGeneration: textGeneration, textStamp: controller.textStamp(for: item))
                        .equatable()
                }
                // Room under the last row (and for the typing line), and the
                // target for scrolling to the bottom. Inside the stack, so
                // scrolling here lays out the real last rows rather than
                // estimated space. Where it ends is where the list ends.
                Color.clear
                    .frame(height: ListEndSpacing.height(typingLine: shownTypingLineHeight))
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.contentSpace)) }) { frame in
                        controller.endFrame = frame
                        endChanged()
                    }
                    .id(DisplayItemID.end)
                    .accessibilityHidden(true)
            }
            .scrollTargetLayout()
            .coordinateSpace(.named(Self.contentSpace))
            .themedScrollers()
            .background(ListScrollViewProbe { [controller] in controller.scrollView = $0 })
        }
        .modifier(ListScrollPosition(position: $position))
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        // Pinned: growth keeps the newest line in view. Loading history:
        // rows inserted above don't move what's on screen. Otherwise the
        // top stays put, so arriving messages never drag the reader along.
        .defaultScrollAnchor(
            controller.anchorsToBottom || controller.holdsAnchorForHistory || buffer.isLoadingHistory ? .bottom : .top,
            for: .sizeChanges
        )
        .onScrollGeometryChange(for: ScrollMetrics.self, of: ScrollMetrics.init) { old, new in
            scrollMetricsChanged(from: old, to: new)
        }
        .onScrollPhaseChange { _, phase in
            switch phase {
            case .tracking, .interacting, .decelerating: _ = controller.scrollPhaseChanged(isUserScrolling: true)
            default: if controller.scrollPhaseChanged(isUserScrolling: false) { scrollToBottom() }
            }
            updatePill()
        }
        .onScrollTargetVisibilityChange(idType: DisplayItemID.self, threshold: 0.5) { visible in
            // Transient layouts can report nothing visible; keep the last row.
            if let first = visible.first(where: { $0 != .end }) { controller.topVisibleID = first }
        }
        .onChange(of: LinesSignature(buffer.lines)) { _, _ in
            linesChanged()
        }
        .onChange(of: buffer.isLoadingHistory) { _, loading in
            if !loading { releaseHistoryAnchor() }
        }
        .onChange(of: uiState.scrollTarget, initial: true) { _, target in
            if let target { scroll(toLine: target) }
        }
        .onChange(of: intelligence.catchUp.reveal) { _, reveal in
            if let reveal, reveal.bufferID == buffer.id {
                intelligence.catchUp.revealHandled(reveal)
                revealCatchUpCard()
            }
        }
        .onAppear {
            controller.trackLines()
            listOpened(items)
        }
        .onDisappear {
            controller.bottomCheck?.cancel()
        }
        .onChange(of: app.isWindowActive) { _, active in
            if active { windowActivated() }
        }
        .overlay(alignment: .bottom) {
            // Rises from the list's bottom edge with the conversation, so
            // it never overlaps the last row on the way.
            TypingIndicatorView(buffer: buffer, isShown: typingShown, onActiveChange: typingChanged)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { typingLineHeight = $0 }
                .offset(y: typingShown || reduceMotion ? 0 : ListEndSpacing.typingRise(typingLine: typingLineHeight))
                .clipped()
        }
        .overlay(alignment: .bottom) {
            ZStack {
                if controller.showsJumpToPresent {
                    JumpToPresentPill(count: controller.unseenCount) { jumpToPresent() }
                        .padding(.bottom, ListEndSpacing.pillBottomPadding(typingLine: shownTypingLineHeight))
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: controller.showsJumpToPresent)
        }
        .environment(controller)
        .environment(\.openURL, controller.openURL(app: app))
        .confirmationDialog(
            "Delete this message?",
            isPresented: Binding(
                get: { controller.pendingDeletion != nil },
                set: { if !$0 { controller.pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: controller.pendingDeletion
        ) { line in
            Button("Delete Message", role: .destructive) { controller.delete(line) }
            Button("Cancel", role: .cancel) { controller.pendingDeletion = nil }
        } message: { line in
            Text("“\(ReplyQuoteView.snippet(for: line))” will be removed for everyone in \(buffer.name).")
        }
    }

    // MARK: Typing line

    private var shownTypingLineHeight: CGFloat? {
        typingShown ? typingLineHeight : nil
    }

    /// Someone started typing, or everyone stopped: show or hide the line
    /// and the room for it in one animation. Pinned, the list's bottom
    /// anchor carries the conversation up (or down) with the room; the
    /// pinning logic stands back until that's done, so it doesn't snap to
    /// the end mid-animation.
    private func typingChanged(_ active: Bool, animated: Bool) {
        guard typingShown != active else { return }
        let animation = animated && !reduceMotion ? ListEndSpacing.typingAnimation : nil
        if animation != nil, controller.isPinnedToBottom, controller.scrollDriver == .idle {
            controller.beginProgrammaticScroll(for: ListEndSpacing.typingAnimationSettle) { follow in
                if follow { scrollToBottom() } else { checkClipView() }
            }
        }
        withAnimation(animation) { typingShown = active }
    }

    // MARK: Scrolling

    private func scrollMetricsChanged(from old: ScrollMetrics, to new: ScrollMetrics) {
        var new = new
        new.contentEnd = controller.contentEnd(in: new)
        positionChanged(new)

        // Near the top and still scrolling up: fetch older history.
        if new.visibleMinY < 600, new.visibleMinY < old.visibleMinY, new.contentHeight > new.containerHeight,
           buffer.hasMoreHistory, !buffer.isLoadingHistory, !controller.holdsAnchorForHistory {
            loadOlderHistory()
        }
    }

    /// Feeds where the list is to the pinning logic, which may ask to follow
    /// the newest line.
    private func positionChanged(_ metrics: ScrollMetrics) {
        let follow = controller.scrollGeometryChanged(metrics)
        if follow == .scrollAnew, !controller.isUserScrolling {
            // The list got shorter (the composer grew a line). Right away,
            // so the conversation moves up with the composer rather than a
            // frame later. That's safe from here: scrolling doesn't change
            // the list's height, so it can't ask for this again. And again
            // on the next turn, in case this reached the scroll view before
            // its new height did.
            scrollToBottom(anew: true)
        }
        controller.queueFollow(follow) { anew in
            scrollToBottom(anew: anew)
        }
        if follow == .stay, controller.isPinnedToBottom, controller.scrollDriver == .idle {
            checkClipView()
        }
        if controller.isPinnedToBottom {
            markAllSeen()
        }
        updatePill()
    }

    /// At the bottom as SwiftUI reports it: makes sure the scroll view shows
    /// that too, once this change has been laid out (`ClipViewSync`).
    private func checkClipView() {
        controller.queueClipCheck { scrollToBottom(anew: true) }
    }

    /// The space after the last row was laid out somewhere else. That can
    /// happen without the scroll geometry changing (rows above it measured
    /// at other heights than estimated), so the position is judged again.
    private func endChanged() {
        guard var metrics = controller.metrics else { return }
        let end = controller.contentEnd(in: metrics)
        guard metrics.contentEnd != end else { return }
        metrics.contentEnd = end
        positionChanged(metrics)
    }

    private func updatePill() {
        let farFromBottom = controller.metrics.map { $0.distanceFromBottom > $0.containerHeight * 0.5 } ?? false
        let showPill = !controller.isPinnedToBottom && (farFromBottom || controller.unseenCount > 0)
        if controller.showsJumpToPresent != showPill { controller.showsJumpToPresent = showPill }
    }

    private func linesChanged() {
        guard let change = controller.lineTracker?.update(buffer.lines) else { return }
        if change.sentMessage {
            // Sending a message always returns to the present: now, or once
            // the reader's gesture ends.
            controller.pin()
            markAllSeen()
            updatePill()
            scrollToBottom()
            if controller.isUserScrolling { controller.holdBackFollow() }
        } else if controller.isPinnedToBottom {
            markAllSeen()
            // Don't fight a gesture that's still within the bottom
            // tolerance; follow when it ends.
            if controller.isUserScrolling {
                controller.holdBackFollow()
            } else {
                scrollToBottom()
            }
        } else {
            controller.unseenCount += change.newFromOthers
            updatePill()
        }
    }

    /// Scrolls to the newest line: the spacer after the last row, by id,
    /// until it's really there.
    ///
    /// Never to the bottom *edge*. That's the end of the lazy stack's
    /// content height, which counts rows it hasn't laid out at an estimated
    /// height; in a long channel with video players and link previews among
    /// one-line messages it can lie a screenful or more below the last row.
    /// The list then showed nothing, looked to be at the bottom and stayed
    /// that way until a new message arrived.
    ///
    /// A scroll to the spacer can land short of it too, where the stack
    /// estimates the spacer is, with nothing laid out; so it's checked and
    /// tried again until the spacer really is at the bottom of the visible
    /// rect (`BottomSettle`). Animated jumps skip the checks (they'd cut
    /// the animation short); their completion settles instead.
    ///
    /// `anew` makes sure SwiftUI scrolls even when it holds the list is at
    /// the bottom already, after the list got shorter
    /// (`ScrollPinning.mustScrollToBottomAnew`). Only a position other than
    /// its current one does that: `.bottom`, or when that's the current one,
    /// a hair above it, then back.
    private func scrollToBottom(animated: Bool = false, anew: Bool = false) {
        var target = position
        target.scrollTo(id: DisplayItemID.end, anchor: .bottom)
        var anchor: CGFloat = 1
        if anew, target == position {
            anchor = BottomSettle.anewAnchor
            target.scrollTo(id: DisplayItemID.end, anchor: UnitPoint(x: 0.5, y: anchor))
        }
        position = target
        controller.bottomCheck?.cancel()
        guard !animated else { return }
        controller.bottomCheck = Task { await settleAtBottom(firstAnchor: anchor) }
    }

    /// Checks that the list got to the bottom and scrolls there again until
    /// it does, as `BottomSettle` says.
    private func settleAtBottom(firstAnchor: CGFloat) async {
        var settle = BottomSettle(firstAnchor: firstAnchor)
        var lastCheck = Date()
        while true {
            try? await Task.sleep(for: .seconds(settle.wait))
            guard !Task.isCancelled, controller.isPinnedToBottom else { return }
            guard !controller.isUserScrolling else {
                // Checked again when the gesture ends.
                controller.holdBackFollow()
                return
            }
            controller.noteClipView()
            let now = Date()
            let step = settle.check(
                waited: now.timeIntervalSince(lastCheck),
                otherScrollUnderWay: controller.scrollDriver == .programmatic,
                atBottom: controller.metrics.map(ScrollPinning.isAtBottom) ?? false
            )
            lastCheck = now
            switch step {
            case .wait:
                continue
            case .scroll(let anchor):
                position.scrollTo(id: DisplayItemID.end, anchor: UnitPoint(x: 0.5, y: anchor))
            case .done(let settleBack):
                if settleBack { position.scrollTo(id: DisplayItemID.end, anchor: .bottom) }
                return
            }
        }
    }

    private func markAllSeen() {
        if controller.unseenCount != 0 { controller.unseenCount = 0 }
    }

    private func loadOlderHistory() {
        controller.setHoldsAnchorForHistory(true)
        Task {
            await session.loadOlderHistory(for: buffer)
            // Server history (CHATHISTORY) finishes later; see the
            // isLoadingHistory observer.
            if !buffer.isLoadingHistory { releaseHistoryAnchor() }
        }
    }

    /// Keeps size changes bottom-anchored a moment longer, so rows inserted
    /// above in the same update as the loading flag clears don't shift the view.
    private func releaseHistoryAnchor() {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !buffer.isLoadingHistory { controller.setHoldsAnchorForHistory(false) }
        }
    }

    private func jumpToPresent() {
        controller.pin()
        markAllSeen()
        controller.showsJumpToPresent = false
        // Long animated scrolls through a lazy stack land unreliably (rows
        // are estimated); animate only short trips.
        let near = controller.metrics.map { $0.distanceFromBottom < $0.containerHeight * 3 } ?? true
        let animated = near && !reduceMotion
        controller.beginProgrammaticScroll(for: animated ? 0.45 : 0.15) { follow in
            if follow { scrollToBottom() } else { checkClipView() }
        }
        withAnimation(animated ? .smooth(duration: 0.35) : nil) {
            scrollToBottom(animated: animated)
        }
    }

    /// The list appeared: land where `chat.openAt` says (see `ListLanding`).
    /// It starts at the bottom, pinned, as far as the estimated row heights
    /// tell; every landing scrolls for real.
    private func listOpened(_ items: DisplayItems) {
        // A jump asked for from elsewhere (a search result, a reply) wins.
        guard uiState.scrollTarget == nil else { return }
        let reveal = intelligence.catchUp.reveal.flatMap { $0.bufferID == buffer.id ? $0 : nil }
        let landing = ListLanding.onOpen(
            openAt: style.openAt,
            revealsCatchUpCard: reveal != nil,
            unreadTarget: ListLanding.unreadTarget(in: items, after: buffer.unreadMarkerAfter)
        )
        switch landing {
        case .catchUpCard:
            // Opened from a context menu or the palette.
            if let reveal { intelligence.catchUp.revealHandled(reveal) }
            revealCatchUpCard()
        case .unread(let target):
            landAtUnread(target)
        case .bottom:
            scrollToBottom()
        case .stay:
            break
        }
    }

    /// Coming back to Vela: with Show newest, settle on the newest line
    /// unless the reader scrolled up.
    private func windowActivated() {
        let landing = ListLanding.onWindowActivated(
            openAt: style.openAt,
            isPinned: controller.isPinnedToBottom,
            isUserScrolling: controller.isUserScrolling
        )
        guard landing == .bottom else { return }
        markAllSeen()
        updatePill()
        scrollToBottom()
    }

    /// Opens a buffer with unread lines at the "New" marker (or, with the
    /// marker hidden, the first unread row), a little below the top. When
    /// everything new fits on screen this lands at the bottom and the list
    /// stays pinned.
    private func landAtUnread(_ target: DisplayItemID) {
        controller.unpin()
        controller.beginProgrammaticScroll(for: 0.4) { follow in
            if follow { scrollToBottom() }
            updatePill()
        }
        position.scrollTo(id: target, anchor: UnitPoint(x: 0.5, y: 0.2))
        Task {
            // Rows above were estimated: correct once they're measured.
            // (An equal ScrollPosition is ignored, hence the nudged anchors.)
            for nudge in [0.2001, 0.2] {
                try? await Task.sleep(for: .milliseconds(60))
                guard !controller.isUserScrolling else { return }
                position.scrollTo(id: target, anchor: UnitPoint(x: 0.5, y: nudge))
            }
        }
    }

    /// Brings the Catch me up card into view: the New marker above it (or
    /// the card, once the marker has moved on or when it's hidden) near the
    /// top, so the card has room to grow beneath it.
    private func revealCatchUpCard() {
        guard let target = controller.displayCache.items.catchUpCardScrollTarget else { return }
        controller.unpin()
        controller.beginProgrammaticScroll(for: 0.4) { _ in updatePill() }
        let anchor = UnitPoint(x: 0.5, y: 0.08)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            position.scrollTo(id: target, anchor: anchor)
        }
        Task {
            // Rows above were estimated: correct once they're measured.
            // (An equal ScrollPosition is ignored, hence the nudged anchors.)
            for nudge in [0.0801, 0.08] {
                try? await Task.sleep(for: .milliseconds(80))
                guard !controller.isUserScrolling else { return }
                position.scrollTo(id: target, anchor: UnitPoint(x: 0.5, y: nudge))
            }
        }
    }

    private func scroll(toLine lineID: UUID) {
        let id = DisplayItemID.line(lineID)
        let items = controller.displayCache.items
        guard let targetIndex = items.firstIndex(where: { $0.id == id }) else { return }
        uiState.scrollTarget = nil
        controller.unpin()
        controller.beginProgrammaticScroll { follow in
            if follow { scrollToBottom() }
            updatePill()
        }
        let anchorIndex = controller.topVisibleID.flatMap { visible in items.lastIndex { $0.id == visible } }
        let near = anchorIndex.map { abs($0 - targetIndex) <= 40 } ?? false
        if near && !reduceMotion {
            withAnimation(.smooth(duration: 0.35)) {
                position.scrollTo(id: id, anchor: .center)
            }
        } else {
            // Far away rows have estimated heights: jump, then correct once
            // the rows around the target have been laid out.
            // (An equal ScrollPosition is ignored, hence the nudged anchors.)
            position.scrollTo(id: id, anchor: .center)
            Task {
                for nudge in [0.499, 0.5, 0.499] {
                    try? await Task.sleep(for: .milliseconds(50))
                    position.scrollTo(id: id, anchor: UnitPoint(x: 0.5, y: nudge))
                }
            }
        }
        controller.flash(lineID, reduceMotion: reduceMotion)
    }
}

/// The list's scroll position, applied in a body of its own. SwiftUI
/// writes the position back as the list scrolls, and the body that applies
/// it runs again each time; applied in the list's body, that was the whole
/// list (every row compared, the environment rebuilt) on nearly every frame.
private struct ListScrollPosition: ViewModifier {
    @Binding var position: ScrollPosition

    func body(content: Content) -> some View {
        content.scrollPosition($position)
    }
}

extension ScrollMetrics {
    init(_ geometry: ScrollGeometry) {
        self.init(
            visibleMinY: geometry.visibleRect.minY,
            visibleMaxY: geometry.visibleRect.maxY,
            contentHeight: geometry.contentSize.height,
            containerHeight: geometry.containerSize.height
        )
    }
}

/// A spinner while older history loads, or a quiet note at the very start.
private struct HistoryHeader: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let buffer: BufferModel
    let title: String

    var body: some View {
        if buffer.isLoadingHistory {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .accessibilityLabel("Loading older messages")
        } else if !buffer.hasMoreHistory, !buffer.lines.isEmpty {
            Text("This is the beginning of \(title)")
                .font(style.font(size: max(10, style.fontSize - 2)))
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 4)
        } else {
            Color.clear.frame(height: 6)
        }
    }
}

/// Floating "Jump to present" button shown while scrolled up.
private struct JumpToPresentPill: View {
    @Environment(\.theme) private var theme
    let count: Int
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Jump to present")
                if count > 0 {
                    Text("·")
                    Text(count == 1 ? "1 new" : "\(count) new")
                        .monospacedDigit()
                }
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme[ThemeKey.accentForeground])
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(theme[ThemeKey.accent]))
            .overlay(Capsule().fill(hovering ? theme[ThemeKey.accentForeground].opacity(0.1) : .clear))
            .shadow(color: theme[ThemeKey.windowBackground].opacity(theme.kind == .dark ? 0.5 : 0.2), radius: 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Jump to the newest messages")
        .accessibilityLabel(count > 0 ? "Jump to present, \(count) new messages" : "Jump to present")
    }
}
