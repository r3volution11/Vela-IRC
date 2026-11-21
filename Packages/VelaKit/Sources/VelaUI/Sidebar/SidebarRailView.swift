// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// The collapsed sidebar: a narrow rail of network glyphs and channel tiles.
///
/// Reorders like the tree: network glyphs drag their tiles (and a bouncer
/// its networks) along, channel and conversation tiles move within their
/// own group. The line between networks belongs to the network below it.
struct SidebarRailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SidebarMetrics.collapsedNetworksKey) private var collapsedNetworks = NetworkIDSet()

    /// The sidebar has the keyboard focus: the tile the keyboard is on
    /// gets a ring (see `SidebarContainer`).
    var hasKeyboardFocus = false
    /// Told when a drag to reorder starts and ends, so the tree doesn't
    /// float open over the rail mid-drag.
    var onReorderingChange: ((Bool) -> Void)?

    @State private var networkReorder = ReorderController<UUID>(axis: .vertical, coordinateSpace: "sidebar.rail")
    @State private var bufferReorder = ReorderController<BufferID>(axis: .vertical, coordinateSpace: "sidebar.rail")

    var body: some View {
        let groups = app.sidebarGroups
        let topLevel = groups.filter { !$0.isOrphan }.map(\.id)
        let isReordering = networkReorder.isDragging || bufferReorder.isDragging
        let cursor = hasKeyboardFocus ? SidebarKeyboard.cursor(selected: app.selectedBufferID, in: app, collapsed: collapsedNetworks) : nil

        VStack(spacing: 0) {
            // Tall enough for the traffic lights, which stack vertically here.
            SidebarTitleStrip(height: TrafficLightLayout.verticalStackHeight) { EmptyView() }

            ScrollViewReader { proxy in
                SidebarReorderScrollView(
                    coordinateSpace: networkReorder.coordinateSpace,
                    isDragging: isReordering,
                    nudge: { networkReorder.nudge(by: $0) ?? bufferReorder.nudge(by: $0) }
                ) {
                    VStack(spacing: 6) {
                        ForEach(groups) { group in
                            groupView(group, isFirst: group.id == groups.first?.id, siblings: group.isOrphan ? [] : topLevel, cursor: cursor)
                                .zIndex(holdsDrag(group) ? 1 : 0)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    .environment(\.isSidebarReordering, isReordering)
                }
                .scrollIndicators(.never)
                .scrollContentBackground(.hidden)
                // Keeps the tile the keyboard is on in view.
                .onChange(of: cursor) { _, cursor in
                    if let cursor { proxy.scrollTo(cursor) }
                }
            }

            VStack(spacing: 4) {
                SidebarAddMenu()
                SidebarIconButton(systemImage: "sidebar.left", help: "Expand Sidebar") {
                    app.settings[.sidebarCollapsed] = false
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .padding(.trailing, 1)
        .frame(width: SidebarMetrics.railWidth)
        .frame(maxHeight: .infinity)
        .surfaceBackground(ThemeKey.railBackground, on: .sidebar)
        .devTag("Rail", tokens: [ThemeKey.railBackground, ThemeKey.railBorder])
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme[ThemeKey.railBorder]).frame(width: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
        .onChange(of: isReordering) { _, dragging in
            onReorderingChange?(dragging)
        }
        .onDisappear {
            networkReorder.end { _, _ in }
            bufferReorder.end { _, _ in }
            onReorderingChange?(false)
        }
    }

    /// A top-level network with its bouncer networks, if any, after the
    /// line that sets it apart from the one above.
    private func groupView(_ group: SidebarNetworkGroup, isFirst: Bool, siblings: [UUID], cursor: BufferID?) -> some View {
        VStack(spacing: 6) {
            if !isFirst {
                RailSeparator()
                    .reorderPart(of: group.id, in: networkReorder, part: "separator")
            }
            VStack(spacing: 6) {
                section(group.network, siblings: siblings, cursor: cursor)
                    .zIndex(holdsDraggedBuffer(group.network) ? 1 : 0)
                if !group.children.isEmpty {
                    let childIDs = group.children.map(\.id)
                    VStack(spacing: 6) {
                        ForEach(group.children) { child in
                            VStack(spacing: 6) {
                                RailSeparator()
                                    .reorderPart(of: child.id, in: networkReorder, part: "separator")
                                section(child, siblings: childIDs, cursor: cursor)
                                    .background { networkLift(child.id) }
                            }
                            .zIndex(networkReorder.isMoving(child.id) || holdsDraggedBuffer(child) ? 1 : 0)
                        }
                    }
                    .reorderPart(of: group.id, in: networkReorder, part: "children")
                }
            }
            .background { networkLift(group.id) }
        }
    }

    /// A network glyph and, unless folded, its channel and conversation tiles.
    @ViewBuilder
    private func section(_ session: NetworkSession, siblings: [UUID], cursor: BufferID?) -> some View {
        let isCollapsed = collapsedNetworks.contains(session.id)
        let buffers = session.sidebarBuffers
        let selectedID = app.selectedBufferID

        VStack(spacing: 6) {
            RailNetworkItem(
                session: session,
                isSelected: selectedID == session.serverBuffer.id,
                isCollapsed: isCollapsed,
                showsKeyboardFocus: cursor == session.serverBuffer.id
            )
            .id(session.serverBuffer.id)
            .accessibilityMoveActions(axis: .vertical, index: siblings.firstIndex(of: session.id) ?? 0, count: siblings.count) { offset in
                withAnimation(moveAnimation) { app.moveNetwork(session.id, by: offset) }
            }
            .reorderable(session.id, siblings: siblings, in: networkReorder) { id, index in
                app.moveNetwork(id, toIndex: index)
            }

            if !isCollapsed && !buffers.isEmpty {
                let channels = buffers.filter { $0.kind == .channel }
                let queries = buffers.filter { $0.kind == .query }
                let channelIDs = channels.map(\.id)
                let queryIDs = queries.map(\.id)
                VStack(spacing: 6) {
                    ForEach(Array(channels.enumerated()), id: \.element.id) { index, buffer in
                        bufferTile(buffer, in: session, isSelected: selectedID == buffer.id, index: index, siblings: channelIDs, cursor: cursor)
                    }
                    ForEach(Array(queries.enumerated()), id: \.element.id) { index, buffer in
                        bufferTile(buffer, in: session, isSelected: selectedID == buffer.id, index: index, siblings: queryIDs, cursor: cursor)
                    }
                }
                .reorderPart(of: session.id, in: networkReorder, part: "buffers")
            }
        }
    }

    private func bufferTile(_ buffer: BufferModel, in session: NetworkSession, isSelected: Bool, index: Int, siblings: [BufferID], cursor: BufferID?) -> some View {
        let isLifted = bufferReorder.isDragging(buffer.id)
        return RailBufferItem(buffer: buffer, session: session, isSelected: isSelected, showsKeyboardFocus: cursor == buffer.id)
            .background {
                // Under the tile itself, which draws its own fill on top
                // (translucent at rest, so this also hides what it passes over).
                if isLifted {
                    SidebarLiftBackground(surface: ThemeKey.railBackground, cornerRadius: 9)
                        .frame(width: SidebarMetrics.railTileSize, height: SidebarMetrics.railTileSize)
                }
            }
            .accessibilityMoveActions(axis: .vertical, index: index, count: siblings.count) { offset in
                withAnimation(moveAnimation) { session.moveBuffer(buffer, by: offset) }
            }
            .reorderable(buffer.id, siblings: siblings, in: bufferReorder) { id, index in
                guard let moving = session.buffers.first(where: { $0.id == id }) else { return }
                session.moveBuffer(moving, toIndex: index)
            }
            .id(buffer.id)
    }

    /// A column a little wider than the tiles, behind a dragged network.
    private func networkLift(_ id: UUID) -> some View {
        SidebarNetworkLift(id: id, controller: networkReorder, surface: ThemeKey.railBackground, cornerRadius: 12)
            .padding(.vertical, -4)
            .frame(width: SidebarMetrics.railTileSize + 8)
    }

    /// Whether the item being dragged is in this block, which then draws
    /// over its neighbours (the dragged item and its shadow overlap them).
    private func holdsDrag(_ group: SidebarNetworkGroup) -> Bool {
        let networks = [group.network] + group.children
        if let moving = networkReorder.moving, networks.contains(where: { $0.id == moving }) { return true }
        return networks.contains(where: holdsDraggedBuffer)
    }

    private func holdsDraggedBuffer(_ session: NetworkSession) -> Bool {
        bufferReorder.moving?.networkID == session.id
    }

    /// Move Up/Down from VoiceOver or Full Keyboard Access.
    private var moveAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22)
    }
}

/// The line between networks in the rail.
private struct RailSeparator: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Capsule()
            .fill(theme.color(ThemeKey.railForeground).withAlpha(0.14).color)
            .frame(width: 24, height: 1)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }
}

/// Shared chrome for rail items: hover/selection fill, the indicator on the
/// rail's leading edge (a short pip for unread activity, a tall bar for the
/// selected buffer) and the mention badge.
private struct RailItem<Tile: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSidebarReordering) private var isReordering
    let isSelected: Bool
    let activity: BufferActivity
    let help: String
    /// The keyboard is on this tile (the sidebar has the focus).
    var showsKeyboardFocus = false
    /// A network's round glyph, rather than a channel's rounded square.
    var isRound = false
    let action: () -> Void
    @ViewBuilder var tile: (_ isHovering: Bool) -> Tile

    @State private var hovering = false

    /// Hover feedback, held back while something is dragged.
    private var showsHover: Bool { hovering && !isReordering }

    var body: some View {
        tile(showsHover)
            .frame(width: SidebarMetrics.railTileSize, height: SidebarMetrics.railTileSize)
            .devTag(
                isRound ? "Rail network" : "Rail channel",
                tokens: [
                    isSelected ? ThemeKey.railActiveBackground : ThemeKey.railForeground,
                    isSelected ? ThemeKey.railActiveIndicator : ThemeKey.railInactiveForeground,
                    showsHover ? ThemeKey.sidebarHoverBackground : nil,
                ].compactMap { $0 }
            )
            .overlay {
                // Just outside the tile, clear of its initials.
                if showsKeyboardFocus {
                    Group {
                        if isRound {
                            KeyboardFocusRing(shape: Circle())
                        } else {
                            KeyboardFocusRing(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(-3)
                }
            }
            .overlay(alignment: .topTrailing) {
                RailBadge(activity: activity)
                    .offset(x: 5, y: -4)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2, style: .continuous)
                    .fill(theme[isSelected ? ThemeKey.railActiveIndicator : ThemeKey.railForeground])
                    .frame(width: 3, height: indicatorHeight)
                    .opacity(indicatorHeight > 0 ? 1 : 0)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: indicatorHeight)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityValue(activity.accessibilityDescription)
            .accessibilityAction { action() }
    }

    private var indicatorHeight: CGFloat {
        if isSelected { return 20 }
        if activity.isEmphasized { return showsHover ? 12 : 8 }
        return 0
    }
}

/// Fill for a rail tile at rest, hovered or selected. Resting tiles are a
/// faint wash of `rail.foreground`; hover layers `sidebar.hoverBackground`
/// on top of that.
private func railTileFill(_ theme: ResolvedTheme, isSelected: Bool, isHovering: Bool) -> Color {
    if isSelected { return theme[ThemeKey.railActiveBackground] }
    let resting = theme.color(ThemeKey.railForeground).withAlpha(0.07)
    guard isHovering else { return resting.color }
    return theme.color(ThemeKey.sidebarHoverBackground)
        .composited(over: resting.composited(over: theme.color(ThemeKey.railBackground)))
        .color
}

/// A network glyph: a circle with the network's initial and a status dot.
private struct RailNetworkItem: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.sidebarKeyboardFocus) private var keyboardFocus
    @Environment(\.theme) private var theme
    @Environment(\.effectiveVibrancy) private var vibrancy
    let session: NetworkSession
    let isSelected: Bool
    let isCollapsed: Bool
    var showsKeyboardFocus = false

    var body: some View {
        let isOffline = session.connectionState == .disconnected
        RailItem(
            isSelected: isSelected,
            activity: BufferActivity(headerOf: session, isCollapsed: isCollapsed),
            help: "\(session.displayName) — \(session.connectionDescription)",
            showsKeyboardFocus: showsKeyboardFocus,
            isRound: true,
            action: {
                keyboardFocus?.yieldToClick(uiState)
                app.select(session.serverBuffer)
            }
        ) { hovering in
            Circle()
                .fill(railTileFill(theme, isSelected: isSelected, isHovering: hovering))
                .overlay {
                    Text(RailLabel.networkInitial(for: session.displayName))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(theme[isOffline ? ThemeKey.railInactiveForeground : ThemeKey.railForeground])
                }
                .overlay(alignment: .bottomTrailing) {
                    // Centered on the circle's edge at 45°, like a presence dot.
                    ConnectionIndicator(state: session.connectionState, size: 8)
                        .background(Circle().fill(theme.surfaceColor(ThemeKey.railBackground, on: .sidebar, vibrancy: vibrancy).color).padding(-2))
                        .offset(x: -1, y: -1)
                }
        }
        .contextMenu { ServerContextMenuItems(session: session) }
        .accessibilityLabel(session.displayName)
    }
}

/// A channel tile (rounded square with initials) or a query avatar.
private struct RailBufferItem: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.sidebarKeyboardFocus) private var keyboardFocus
    @Environment(\.theme) private var theme
    let buffer: BufferModel
    let session: NetworkSession
    let isSelected: Bool
    var showsKeyboardFocus = false

    var body: some View {
        let activity = BufferActivity(buffer: buffer, session: session)
        let dimmed = activity.isInactive || activity.isMuted
        RailItem(
            isSelected: isSelected,
            activity: activity,
            help: "\(buffer.name) — \(session.displayName)",
            showsKeyboardFocus: showsKeyboardFocus,
            action: {
                keyboardFocus?.yieldToClick(uiState)
                app.select(buffer)
            }
        ) { hovering in
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            if buffer.kind == .query {
                shape
                    .fill(isSelected || hovering ? railTileFill(theme, isSelected: isSelected, isHovering: hovering) : .clear)
                    .overlay {
                        AvatarView(nick: buffer.name, size: 24)
                            .opacity(dimmed ? 0.55 : 1)
                    }
            } else {
                shape
                    .fill(railTileFill(theme, isSelected: isSelected, isHovering: hovering))
                    .overlay {
                        Text(RailLabel.initials(for: buffer.name))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .italic(activity.isInactive)
                            .foregroundStyle(theme[dimmed && !isSelected ? ThemeKey.railInactiveForeground : ThemeKey.railForeground])
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .padding(.horizontal, 2)
                    }
            }
        }
        .contextMenu { BufferContextMenuItems(buffer: buffer, session: session) }
        .accessibilityLabel(buffer.kind == .query ? "Conversation with \(buffer.name)" : buffer.name)
    }
}

/// Mention count capsule on the corner of a rail tile.
private struct RailBadge: View {
    @Environment(\.theme) private var theme
    @Environment(\.effectiveVibrancy) private var vibrancy
    let activity: BufferActivity

    var body: some View {
        if activity.hasHighlights {
            Text(activity.highlights > 99 ? "99+" : "\(activity.highlights)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(theme[ThemeKey.railBadgeForeground])
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(Capsule().fill(theme[ThemeKey.railBadgeBackground]))
                .background(Capsule().fill(theme.surfaceColor(ThemeKey.railBackground, on: .sidebar, vibrancy: vibrancy).color).padding(-2))
                .accessibilityHidden(true)
        }
    }
}
