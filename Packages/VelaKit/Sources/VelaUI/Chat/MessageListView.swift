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
/// are built.
///
/// Scrolling follows `ScrollPinning`: the list opens at the bottom (or at
/// the unread marker) and stays pinned there — through new lines, media that
/// loads late, reactions, resizes and style changes — until the reader
/// scrolls up. Then nothing moves them and a "Jump to present" pill counts
/// what's new. Sending a message always returns to the bottom.
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
                // Room under the last row, and the target for scrolling to
                // the bottom. Inside the stack, so scrolling here lays out
                // the real last rows rather than estimated space.
                Color.clear
                    .frame(height: 12)
                    .id(DisplayItemID.end)
                    .accessibilityHidden(true)
            }
            .scrollTargetLayout()
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
            switch phase {
            case .tracking, .interacting, .decelerating: controller.scrollPhaseChanged(isUserScrolling: true)
            default: controller.scrollPhaseChanged(isUserScrolling: false)
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
        .onAppear {
            if items.contains(id: .unreadMarker), uiState.scrollTarget == nil { landAtUnreadMarker() }
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
        if controller.scrollGeometryChanged(new) {
            scrollToBottom()
        }
        if controller.isPinnedToBottom {
            markAllSeen()
        }
        updatePill()

        // Near the top and still scrolling up: fetch older history.
        if new.visibleMinY < 600, new.visibleMinY < old.visibleMinY, new.contentHeight > new.containerHeight,
           buffer.hasMoreHistory, !buffer.isLoadingHistory, !controller.holdsAnchorForHistory {
            loadOlderHistory()
        }
    }

    private func updatePill() {
        let farFromBottom = controller.metrics.map { $0.distanceFromBottom > $0.containerHeight * 0.5 } ?? false
        let showPill = !controller.isPinnedToBottom && (farFromBottom || controller.unseenCount > 0)
        if controller.showsJumpToPresent != showPill { controller.showsJumpToPresent = showPill }
    }

    private func linesChanged() {
        let change = controller.lineTracker.update(buffer.lines)
        if change.sentMessage {
            // Sending a message always returns to the present.
            controller.pin()
            markAllSeen()
            updatePill()
            scrollToBottom()
        } else if controller.isPinnedToBottom {
            markAllSeen()
            // Don't fight a gesture that's still within the bottom tolerance.
            if !controller.isUserScrolling { scrollToBottom() }
        } else {
            controller.unseenCount += change.newFromOthers
            updatePill()
        }
    }

    /// Scrolls to the very bottom, in two steps.
    ///
    /// The bottom *edge* alone is computed from the lazy stack's estimated
    /// row heights: after a burst of new rows (or from far up) it can land
    /// in space no row has been laid out for, and the list shows nothing.
    /// Scrolling to the spacer after the last row by id makes the stack lay
    /// out the real rows at the end first; a moment later the edge corrects
    /// whatever the estimates above got wrong. Animated jumps skip the
    /// second step (it would cut the animation short); their completion
    /// settles instead.
    private func scrollToBottom(animated: Bool = false) {
        position.scrollTo(id: DisplayItemID.end, anchor: .bottom)
        guard !animated else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            guard controller.isPinnedToBottom, !controller.isUserScrolling else { return }
            position.scrollTo(edge: .bottom)
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
            if follow { scrollToBottom() }
        }
        withAnimation(animated ? .smooth(duration: 0.35) : nil) {
            scrollToBottom(animated: animated)
        }
    }

    /// Opens a buffer with unread lines at the "New" marker, a little below
    /// the top. When everything new fits on screen this lands at the bottom
    /// and the list stays pinned.
    private func landAtUnreadMarker() {
        controller.unpin()
        controller.beginProgrammaticScroll(for: 0.4) { follow in
            if follow { scrollToBottom() }
            updatePill()
        }
        position.scrollTo(id: DisplayItemID.unreadMarker, anchor: UnitPoint(x: 0.5, y: 0.2))
        Task {
            // Rows above were estimated: correct once they're measured.
            // (An equal ScrollPosition is ignored, hence the nudged anchors.)
            for nudge in [0.2001, 0.2] {
                try? await Task.sleep(for: .milliseconds(60))
                guard !controller.isUserScrolling else { return }
                position.scrollTo(id: DisplayItemID.unreadMarker, anchor: UnitPoint(x: 0.5, y: nudge))
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
