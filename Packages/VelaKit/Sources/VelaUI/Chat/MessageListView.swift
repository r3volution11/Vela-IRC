// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// The scrollback of one buffer in the classic, grouped or columns layout.
///
/// Lines become display items (day dividers, the unread marker, collapsed
/// join/part runs, grouped messages) in `MessageDisplayCache`, which only
/// processes new lines on append; message text is rendered once per line in
/// `MessageTextCache`. Rows live in a `LazyVStack`, so only visible rows
/// are built. The list starts at the bottom and stays pinned there while
/// new lines arrive unless the user has scrolled up, in which case a
/// "Jump to present" pill counts what's new.
struct MessageListView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let buffer: BufferModel
    let session: NetworkSession

    @State private var controller: MessageListController
    @State private var position = ScrollPosition(idType: DisplayItemID.self)

    init(buffer: BufferModel, session: NetworkSession) {
        self.buffer = buffer
        self.session = session
        _controller = State(initialValue: MessageListController(buffer: buffer, session: session))
    }

    var body: some View {
        let options = MessageDisplayOptions(
            joinPart: style.joinPart,
            groupingInterval: style.groupingInterval,
            unreadMarkerAfter: buffer.unreadMarkerAfter
        )
        let items = controller.displayCache.items(for: buffer.lines, options: options)
        let _ = controller.textCache.prepare(
            palette: MessageTextPalette(theme: theme, style: style),
            options: MessageTextOptions(
                renderFormatting: style.renderFormatting,
                selfNick: session.nick,
                channelTypes: session.isupport.channelTypes
            )
        )

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HistoryHeader(buffer: buffer, title: BufferTitle.title(for: buffer, in: session))
                ForEach(items) { item in
                    DisplayItemRow(item: item)
                        .equatable()
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, 12)
        }
        .scrollPosition($position)
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
            controller.isUserScrolling = phase == .interacting || phase == .decelerating
        }
        .onScrollTargetVisibilityChange(idType: DisplayItemID.self, threshold: 0.5) { visible in
            // Transient layouts can report nothing visible; keep the last row.
            if let first = visible.first { controller.topVisibleID = first }
        }
        .onChange(of: buffer.lines.last?.id) { _, _ in
            linesAppended()
        }
        .onChange(of: buffer.isLoadingHistory) { _, loading in
            if !loading { releaseHistoryAnchor() }
        }
        .onChange(of: uiState.scrollTarget, initial: true) { _, target in
            if let target { scroll(toLine: target) }
        }
        .overlay(alignment: .bottom) {
            ZStack {
                if controller.showsJumpToPresent {
                    JumpToPresentPill(count: controller.unseenCount) { jumpToPresent() }
                        .padding(.bottom, 12)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: controller.showsJumpToPresent)
        }
        .environment(controller)
        .environment(\.openURL, OpenURLAction(handler: open))
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

    // MARK: Scrolling

    private func scrollMetricsChanged(from old: ScrollMetrics, to new: ScrollMetrics) {
        // LazyVStack re-estimates row heights as rows appear, so the content
        // height can briefly lag behind the visible rect. Ignore those frames.
        guard new.isConsistent else { return }
        controller.distanceFromBottom = new.distanceFromBottom
        controller.containerHeight = new.containerHeight
        let atBottom = new.isAtBottom
        if Date() < controller.pinningSuspendedUntil {
            // A programmatic scroll (reply jump, jump to present) is moving
            // the list; its intermediate frames aren't user intent.
        } else if atBottom {
            controller.setPinned(true)
        } else if new.visibleMinY < old.visibleMinY - 0.5 {
            // Moving up is always the user (content growth never moves us up).
            controller.setPinned(false)
        } else if controller.isPinnedToBottom {
            // Content or the viewport grew underneath a pinned list.
            position.scrollTo(edge: .bottom)
        }

        if controller.isPinnedToBottom {
            markAllSeen()
        }
        let showPill = !controller.isPinnedToBottom
            && (new.distanceFromBottom > new.containerHeight * 0.5 || controller.unseenCount > 0)
        if controller.showsJumpToPresent != showPill { controller.showsJumpToPresent = showPill }

        // Near the top and still scrolling up: fetch older history.
        if new.visibleMinY < 600, new.visibleMinY < old.visibleMinY, new.contentHeight > new.containerHeight,
           buffer.hasMoreHistory, !buffer.isLoadingHistory, !controller.holdsAnchorForHistory {
            loadOlderHistory()
        }
    }

    private func linesAppended() {
        guard let last = buffer.lines.last else { return }
        let fresh = linesSinceLastSeen()
        if fresh.contains(where: { $0.isSelf && !$0.isHistory && $0.kind.isConversation }) {
            // Sending a message always returns to the present.
            controller.setPinned(true)
            position.scrollTo(edge: .bottom)
        }
        if controller.isPinnedToBottom {
            controller.lastSeenLineID = last.id
            controller.unseenCount = 0
            position.scrollTo(edge: .bottom)
        } else {
            controller.unseenCount += fresh.filter { $0.kind.isConversation && !$0.isSelf }.count
            controller.lastSeenLineID = last.id
            if controller.unseenCount > 0, !controller.showsJumpToPresent { controller.showsJumpToPresent = true }
            // LazyVStack re-estimates the unrealized rows when its data
            // changes, which can move what's on screen. Hold the reader's
            // place by the row that was at the top before the update (unless
            // they're scrolling right now; don't fight their gesture).
            if !controller.isUserScrolling, let anchor = controller.topVisibleID {
                hold(anchor)
            }
        }
    }

    private func hold(_ anchor: DisplayItemID) {
        controller.suspendPinning(for: 0.3)
        position.scrollTo(id: anchor, anchor: .top)
        Task {
            try? await Task.sleep(for: .milliseconds(40))
            position.scrollTo(id: anchor, anchor: UnitPoint(x: 0.5, y: 0.0001))
        }
    }

    /// Lines after the last one we accounted for (empty if it's gone).
    private func linesSinceLastSeen() -> ArraySlice<ChatLine> {
        let lines = buffer.lines
        guard let seen = controller.lastSeenLineID else { return lines[...] }
        // New lines arrive at the end, so search backwards.
        guard let index = lines.lastIndex(where: { $0.id == seen }) else { return [] }
        return lines[(index + 1)...]
    }

    private func markAllSeen() {
        controller.lastSeenLineID = buffer.lines.last?.id
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
        controller.setPinned(true)
        controller.suspendPinning()
        markAllSeen()
        controller.showsJumpToPresent = false
        // Long animated scrolls through a lazy stack land unreliably (rows
        // are estimated); animate only short trips.
        let near = controller.distanceFromBottom < controller.containerHeight * 3
        withAnimation(reduceMotion || !near ? nil : .smooth(duration: 0.35)) {
            position.scrollTo(edge: .bottom)
        }
    }

    private func scroll(toLine lineID: UUID) {
        let id = DisplayItemID.line(lineID)
        let items = controller.displayCache.items
        guard let targetIndex = items.firstIndex(where: { $0.id == id }) else { return }
        uiState.scrollTarget = nil
        controller.setPinned(false)
        controller.suspendPinning()
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

    // MARK: Links

    private func open(_ url: URL) -> OpenURLAction.Result {
        guard let channel = ChannelLink.channel(from: url) else { return .systemAction }
        if let existing = session.buffer(named: channel), existing.isJoined || !session.isConnected {
            app.select(existing)
        } else {
            session.submit("/join \(channel)", in: buffer)
        }
        return .handled
    }
}

/// The scroll values the list reacts to.
private struct ScrollMetrics: Equatable {
    var visibleMinY: CGFloat
    var visibleMaxY: CGFloat
    var contentHeight: CGFloat
    var containerHeight: CGFloat

    init(_ geometry: ScrollGeometry) {
        visibleMinY = geometry.visibleRect.minY
        visibleMaxY = geometry.visibleRect.maxY
        contentHeight = geometry.contentSize.height
        containerHeight = geometry.containerSize.height
    }

    var distanceFromBottom: CGFloat { max(0, contentHeight - visibleMaxY) }

    var fitsWithoutScrolling: Bool { contentHeight <= containerHeight + 1 }

    var isAtBottom: Bool { fitsWithoutScrolling || distanceFromBottom < 24 }

    /// False while the visible rect extends past the (estimated) content.
    var isConsistent: Bool { fitsWithoutScrolling || visibleMaxY <= contentHeight + 2 }
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
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        .help("Jump to the newest messages")
        .accessibilityLabel(count > 0 ? "Jump to present, \(count) new messages" : "Jump to present")
    }
}
