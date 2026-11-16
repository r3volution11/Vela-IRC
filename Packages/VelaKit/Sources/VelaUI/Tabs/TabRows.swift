// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

/// Second level: the selected network's server console, channels and queries.
struct ChannelTabRow: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(TabInteraction.self) private var interaction
    @Environment(\.chatStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let session: NetworkSession
    let surface: TabSurface
    let appearance: TabAppearance
    let showsNetworkName: Bool
    let rowHeight: CGFloat
    var dragsWindow = false
    /// Space before the first tab; strip rows share it so both levels line up.
    var leadingInset: CGFloat = TabMetrics.stripInset

    @Namespace private var selectionNamespace
    @FocusState private var focusedTab: TabKey?
    @State private var isOverflowing = false
    @State private var reorder = ReorderController<BufferID>(axis: .horizontal, coordinateSpace: "channel-tabs")
    @State private var lastDragged: BufferID?

    var body: some View {
        let metrics = TabMetrics(style: style, height: TabMetrics.channelHeight(style), appearance: appearance)
        let palette = TabPalette.channels(on: surface, appearance: appearance)
        let buffers = tabs
        let ids = buffers.map(\.id)
        // Channels move among channels, queries among queries.
        let groups = Dictionary(grouping: buffers.filter { $0.kind != .server }, by: \.kind).mapValues { $0.map(\.id) }
        let selectedID = app.selectedBufferID
        // Mid-drag, the tabs sliding under the pointer aren't being pointed at.
        let hoveredID = reorder.isDragging ? nil : interaction.hovered?.bufferID
        let separated = TabDrawOrder.separated(drawnOrder(ids, groups: groups)) { id in
            id != selectedID && id != hoveredID && !reorder.isMoving(id)
        }
        let shortcutTargets = TabActions.shortcutTargets(in: session).map(\.id)

        HStack(spacing: 2) {
            TabScroller(target: selectedID, dragsWindow: dragsWindow, reorder: reorder, isOverflowing: $isOverflowing) {
                HStack(spacing: metrics.gap) {
                    ForEach(buffers) { buffer in
                        let role = buffer.kind == .server ? nil : TabReorder(
                            controller: reorder,
                            id: buffer.id,
                            siblings: groups[buffer.kind] ?? [],
                            lastDragged: lastDragged,
                            move: { session.moveBuffer(buffer, toIndex: $0) }
                        )
                        ChannelTab(
                            buffer: buffer,
                            session: session,
                            context: TabContext(
                                metrics: metrics,
                                palette: palette,
                                appearance: appearance,
                                selection: selectionNamespace,
                                isSelected: buffer.id == selectedID,
                                isHovered: buffer.id == hoveredID,
                                isFocused: focusedTab == .buffer(buffer.id),
                                showsSeparator: separated.contains(buffer.id),
                                isLifted: role?.isLifted ?? false
                            ),
                            showsNetworkName: showsNetworkName,
                            shortcutNumber: shortcutTargets.firstIndex(of: buffer.id).flatMap { $0 < 9 ? $0 + 1 : nil },
                            focus: $focusedTab,
                            reorder: role,
                            onSelect: { select(buffer) },
                            onClose: {
                                interaction.setHovering(false, .buffer(buffer.id))
                                TabActions.close(buffer, in: session, app: app)
                            },
                            onHover: { interaction.setHovering($0, .buffer(buffer.id)) }
                        )
                        // In the title bar, a drag on a tab is the tab's, never the window's.
                        .excludedFromWindowDragRegion()
                        .tabReorderItem(role)
                        .tabScrollID(buffer.id)
                        .transition(tabTransition)
                        // Outermost, or the row doesn't see it: a lifted tab
                        // draws over the tabs it passes.
                        .zIndex(role?.isRaised == true ? 1 : 0)
                    }
                    TabAddMenu(session: session, height: metrics.height, palette: palette)
                        .padding(.leading, metrics.gap == 0 ? 4 : 2)
                }
                .padding(.leading, leadingInset)
                .padding(.trailing, 8)
                .frame(height: rowHeight, alignment: rowAlignment)
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selectedID)
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: ids)
                .coordinateSpace(.named(reorder.coordinateSpace))
            }

            if isOverflowing {
                TabOverflowMenu(height: metrics.height, palette: palette, accessibilityLabel: "All Tabs on \(session.displayName)") {
                    overflowItems(buffers, selectedID: selectedID)
                }
                .padding(.trailing, 6)
                .frame(height: rowHeight, alignment: rowAlignment)
            }
        }
        .frame(height: rowHeight)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .home, .end]) { press in
            moveFocus(press.key, in: buffers)
        }
        .onChange(of: ids) { oldValue, newValue in
            reorder.abandon()
            repairSelection(old: oldValue, new: newValue)
        }
        .onChange(of: reorder.dragged) { _, dragged in
            if let dragged { lastDragged = dragged }
        }
        .onDisappear { reorder.abandon() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Channels on \(session.displayName)")
    }

    /// The tabs as drawn: mid-drag, the dragged one in the slot it would
    /// land in.
    private func drawnOrder(_ ids: [BufferID], groups: [BufferKind: [BufferID]]) -> [BufferID] {
        guard let dragged = reorder.moving, let target = reorder.target,
              let siblings = groups.values.first(where: { $0.contains(dragged) }) else { return ids }
        return TabDrawOrder.order(ids, siblings: siblings, dragged: dragged, target: target) { id in
            siblings.contains(id) ? id : nil
        }
    }

    /// Server console, then channels, then queries (bouncer control
    /// connections only have their console).
    private var tabs: [BufferModel] {
        session.isBouncerControl ? [session.serverBuffer] + session.buffers : session.allBuffers
    }

    private var rowAlignment: Alignment {
        switch appearance.attachedEdge {
        case .bottom: .bottom
        case .top: .top
        case nil: .center
        }
    }

    private var tabTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let anchor: UnitPoint = appearance.attachedEdge == .top ? .top : .bottom
        return .scale(scale: 0.6, anchor: anchor).combined(with: .opacity)
    }

    private func select(_ buffer: BufferModel) {
        app.select(buffer)
        uiState.focusInput()
    }

    @ViewBuilder
    private func overflowItems(_ buffers: [BufferModel], selectedID: BufferID?) -> some View {
        ForEach(buffers) { buffer in
            Toggle(isOn: Binding(get: { buffer.id == selectedID }, set: { _ in select(buffer) })) {
                let activity = TabDescriptions.activity(
                    unread: buffer.isMuted ? 0 : buffer.unreadCount,
                    highlights: buffer.highlightCount
                )
                let title = buffer.kind == .server ? "\(session.displayName) (server)" : buffer.name
                Text(activity.isEmpty ? title : "\(title)  ·  \(activity.joined(separator: ", "))")
            }
        }
        Divider()
        Button("Join Channel…") { uiState.joinChannelNetwork = session.id }
            .disabled(!session.isConnected || session.isBouncerControl)
    }

    /// ←/→/Home/End move between tabs while one has keyboard focus (Full
    /// Keyboard Access), selecting as they go like a native tab view.
    private func moveFocus(_ key: KeyEquivalent, in buffers: [BufferModel]) -> KeyPress.Result {
        guard case .buffer(let current) = focusedTab,
              let index = buffers.firstIndex(where: { $0.id == current }) else { return .ignored }
        let target = switch key {
        case .leftArrow: max(0, index - 1)
        case .rightArrow: min(buffers.count - 1, index + 1)
        case .home: 0
        default: buffers.count - 1
        }
        guard target != index else { return .handled }
        app.select(buffers[target])
        focusedTab = .buffer(buffers[target].id)
        return .handled
    }

    /// When the selected tab disappears (closed from a menu, /part…), select
    /// the tab that took its place.
    private func repairSelection(old: [BufferID], new: [BufferID]) {
        guard let selected = app.selectedBufferID, selected.networkID == session.id,
              !new.contains(selected), let oldIndex = old.firstIndex(of: selected) else { return }
        let buffers = tabs
        guard !buffers.isEmpty else { return }
        app.select(buffers[min(oldIndex, buffers.count - 1)])
    }
}

/// First level: one tab per network. In the title bar it's drawn as a
/// compact segmented group; in the strip it's its own row.
struct ServerTabRow: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(TabInteraction.self) private var interaction
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let surface: TabSurface
    /// Segmented group (title bar) rather than a full-width row.
    let isSegmented: Bool
    let tabHeight: CGFloat
    let rowHeight: CGFloat

    @Namespace private var selectionNamespace
    @FocusState private var focusedTab: TabKey?
    @State private var isOverflowing = false
    /// Natural width of the segmented group, so it hugs its tabs.
    @State private var contentWidth: CGFloat?
    @State private var reorder = ReorderController<UUID>(axis: .horizontal, coordinateSpace: "server-tabs")
    @State private var lastDragged: UUID?

    private let segmentInset: CGFloat = 2

    var body: some View {
        let sessions = app.sessions
        let height = isSegmented ? tabHeight - segmentInset * 2 : tabHeight
        let metrics = TabMetrics(style: style, height: height, appearance: .floating)
        let palette = TabPalette.servers(on: surface)
        let ids = sessions.map(\.id)
        let roles = reorderRoles(sessions)
        let selectedID = app.selectedBufferID?.networkID
        // Mid-drag, the tabs sliding under the pointer aren't being pointed at.
        let hoveredID = reorder.isDragging ? nil : interaction.hovered?.networkID
        let separated: Set<UUID> = isSegmented ? [] : TabDrawOrder.separated(drawnOrder(ids, roles: roles)) { id in
            id != selectedID && id != hoveredID && roles[id]?.isLifted != true
        }

        HStack(spacing: 2) {
            TabScroller(
                target: selectedID,
                reorder: reorder,
                isOverflowing: $isOverflowing,
                onContentWidthChange: isSegmented ? { width in
                    if contentWidth != width { contentWidth = width }
                } : nil
            ) {
                HStack(spacing: isSegmented ? 1 : metrics.gap) {
                    ForEach(sessions) { session in
                        let role = roles[session.id]
                        ServerTab(
                            session: session,
                            context: TabContext(
                                metrics: metrics,
                                palette: palette,
                                appearance: .floating,
                                selection: selectionNamespace,
                                isSelected: session.id == selectedID,
                                isHovered: session.id == hoveredID,
                                isFocused: focusedTab == .network(session.id),
                                showsSeparator: separated.contains(session.id),
                                isLifted: role?.isLifted ?? false
                            ),
                            focus: $focusedTab,
                            reorder: role,
                            onSelect: {
                                TabActions.select(session, app: app)
                                uiState.focusInput()
                            },
                            onHover: { interaction.setHovering($0, .network(session.id)) }
                        )
                        .excludedFromWindowDragRegion()
                        .tabReorderItem(role)
                        .tabScrollID(session.id)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
                        .zIndex(role?.isRaised == true ? 1 : 0)
                    }
                    if !isSegmented {
                        TabAddNetworkButton(height: metrics.height, palette: palette)
                            .padding(.leading, 2)
                    }
                }
                .padding(.horizontal, isSegmented ? segmentInset : TabMetrics.stripInset)
                .frame(height: isSegmented ? tabHeight : rowHeight)
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selectedID)
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: ids)
                .coordinateSpace(.named(reorder.coordinateSpace))
            }
            .frame(height: isSegmented ? tabHeight : rowHeight)
            .frame(maxWidth: isSegmented ? min(contentWidth ?? 320, 380) : .infinity)
            .background {
                if isSegmented {
                    RoundedRectangle(cornerRadius: TabMetrics.radius(style, forHeight: tabHeight), style: .continuous)
                        .fill(theme[palette.groupFill])
                }
            }

            if isOverflowing {
                TabOverflowMenu(height: metrics.height, palette: palette, accessibilityLabel: "All Networks") {
                    ForEach(sessions) { session in
                        Toggle(isOn: Binding(
                            get: { session.id == selectedID },
                            set: { _ in TabActions.select(session, app: app) }
                        )) {
                            Text(session.displayName)
                        }
                    }
                    Divider()
                    Button("Add Network…") { uiState.networkEditor = .new }
                }
                .padding(.trailing, isSegmented ? 0 : 6)
            }
        }
        .frame(height: rowHeight)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .home, .end]) { press in
            moveFocus(press.key, in: sessions)
        }
        .onChange(of: ids) { reorder.abandon() }
        .onChange(of: reorder.dragged) { _, dragged in
            if let dragged { lastDragged = dragged }
        }
        .onDisappear { reorder.abandon() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Networks")
    }

    /// How each network moves: top-level networks among themselves (a
    /// bouncer taking its networks along), a bouncer's networks among each
    /// other (`AppModel.networkSiblings(of:)`).
    private func reorderRoles(_ sessions: [NetworkSession]) -> [UUID: TabReorder<UUID>] {
        let present = Set(sessions.map(\.id))
        let siblings = Dictionary(grouping: sessions, by: \.config.parentNetworkID).mapValues { $0.map(\.id) }
        var roles: [UUID: TabReorder<UUID>] = [:]
        for session in sessions {
            let parent = session.config.parentNetworkID
            // A network whose bouncer is gone has nowhere to move.
            let isOrphan = parent.map { !present.contains($0) } ?? false
            roles[session.id] = TabReorder(
                controller: reorder,
                id: session.id,
                siblings: siblings[parent] ?? [],
                group: isOrphan ? nil : parent,
                isEnabled: !isOrphan,
                lastDragged: lastDragged,
                move: { [app] index in app.moveNetwork(session.id, toIndex: index) }
            )
        }
        return roles
    }

    /// The networks as drawn: mid-drag, the dragged one (with a bouncer's
    /// networks) in the slot it would land in.
    private func drawnOrder(_ ids: [UUID], roles: [UUID: TabReorder<UUID>]) -> [UUID] {
        guard let dragged = reorder.moving, let target = reorder.target,
              let siblings = roles[dragged]?.siblings else { return ids }
        return TabDrawOrder.order(ids, siblings: siblings, dragged: dragged, target: target) { id in
            if siblings.contains(id) { return id }
            guard let group = roles[id]?.group, siblings.contains(group) else { return nil }
            return group
        }
    }

    private func moveFocus(_ key: KeyEquivalent, in sessions: [NetworkSession]) -> KeyPress.Result {
        guard case .network(let current) = focusedTab,
              let index = sessions.firstIndex(where: { $0.id == current }) else { return .ignored }
        let target = switch key {
        case .leftArrow: max(0, index - 1)
        case .rightArrow: min(sessions.count - 1, index + 1)
        case .home: 0
        default: sessions.count - 1
        }
        guard target != index else { return .handled }
        TabActions.select(sessions[target], app: app)
        focusedTab = .network(sessions[target].id)
        return .handled
    }
}
