// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// The expanded sidebar: a compact tree of networks, channels and queries.
/// Also used, floating, when the rail is hover-expanded.
///
/// Network headers drag to reorder networks (a section takes its rows, and
/// a bouncer its networks, along); channel and query rows drag within their
/// own group.
struct SidebarTreeView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SidebarMetrics.collapsedNetworksKey) private var collapsedNetworks = NetworkIDSet()

    /// Shown over the chat while the rail is hover-expanded.
    var isFloating = false
    /// The sidebar has the keyboard focus: the row the keyboard is on gets
    /// a ring (see `SidebarContainer`).
    var hasKeyboardFocus = false
    /// Told when a drag to reorder starts and ends, so the floating tree
    /// stays open while the pointer strays off it mid-drag.
    var onReorderingChange: ((Bool) -> Void)?

    @State private var networkReorder = ReorderController<UUID>(axis: .vertical, coordinateSpace: "sidebar.tree")
    @State private var bufferReorder = ReorderController<BufferID>(axis: .vertical, coordinateSpace: "sidebar.tree")

    var body: some View {
        let groups = app.sidebarGroups
        let topLevel = groups.filter { !$0.isOrphan }.map(\.id)
        let isReordering = networkReorder.isDragging || bufferReorder.isDragging
        let cursor = hasKeyboardFocus ? SidebarKeyboard.cursor(selected: app.selectedBufferID, in: app, collapsed: collapsedNetworks) : nil

        VStack(spacing: 0) {
            SidebarTitleStrip {
                SidebarIconButton(
                    systemImage: "sidebar.left",
                    help: isFloating ? "Keep Sidebar Open" : "Collapse Sidebar"
                ) {
                    toggleRail()
                }
            }

            ScrollViewReader { proxy in
                SidebarReorderScrollView(
                    coordinateSpace: networkReorder.coordinateSpace,
                    isDragging: isReordering,
                    nudge: { networkReorder.nudge(by: $0) ?? bufferReorder.nudge(by: $0) }
                ) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(groups) { group in
                            groupView(group, siblings: group.isOrphan ? [] : topLevel, cursor: cursor)
                                .padding(.top, group.id == groups.first?.id ? 2 : 10)
                                .zIndex(holdsDrag(group) ? 1 : 0)
                        }
                    }
                    .padding(.horizontal, SidebarMetrics.outerInset)
                    .padding(.bottom, 12)
                    .environment(\.isSidebarReordering, isReordering)
                    .themedScrollers()
                }
                .scrollIndicators(.automatic)
                .scrollContentBackground(.hidden)
                // Keeps the row the keyboard is on in view.
                .onChange(of: cursor) { _, cursor in
                    if let cursor { proxy.scrollTo(cursor) }
                }
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .surfaceBackground(ThemeKey.sidebarBackground, on: .sidebar, isFloating: isFloating)
        .devTag("Sidebar", tokens: [ThemeKey.sidebarBackground, ThemeKey.sidebarForeground, ThemeKey.sidebarBorder])
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

    /// A top-level network with its bouncer networks, if any. The block
    /// draws the lifted backdrop for a top-level drag; each bouncer network
    /// draws its own for a drag among its bouncer's networks.
    private func groupView(_ group: SidebarNetworkGroup, siblings: [UUID], cursor: BufferID?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            section(group.network, siblings: siblings, cursor: cursor)
                .zIndex(holdsDraggedBuffer(group.network) ? 1 : 0)
            if !group.children.isEmpty {
                let childIDs = group.children.map(\.id)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(group.children) { child in
                        section(child, siblings: childIDs, cursor: cursor)
                            .background { networkLift(child.id) }
                            .padding(.top, 10)
                            .zIndex(networkReorder.isMoving(child.id) || holdsDraggedBuffer(child) ? 1 : 0)
                    }
                }
                .reorderPart(of: group.id, in: networkReorder, part: "children")
            }
        }
        .background { networkLift(group.id) }
    }

    /// A network's header and, unless folded, its channels and queries.
    @ViewBuilder
    private func section(_ session: NetworkSession, siblings: [UUID], cursor: BufferID?) -> some View {
        let isCollapsed = collapsedNetworks.contains(session.id)
        let buffers = session.sidebarBuffers

        VStack(alignment: .leading, spacing: 1) {
            SidebarNetworkHeader(
                session: session,
                isSelected: app.selectedBufferID == session.serverBuffer.id,
                isCollapsed: isCollapsed,
                canCollapse: !buffers.isEmpty,
                showsKeyboardFocus: cursor == session.serverBuffer.id
            ) {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    collapsedNetworks.toggle(session.id)
                }
            }
            .id(session.serverBuffer.id)
            .accessibilityMoveActions(axis: .vertical, index: siblings.firstIndex(of: session.id) ?? 0, count: siblings.count) { offset in
                withAnimation(moveAnimation) { app.moveNetwork(session.id, by: offset) }
            }
            .reorderable(session.id, siblings: siblings, in: networkReorder) { id, index in
                app.moveNetwork(id, toIndex: index)
            }

            if !isCollapsed && !buffers.isEmpty {
                bufferRows(buffers, in: session, cursor: cursor)
                    .reorderPart(of: session.id, in: networkReorder, part: "rows")
                    .transition(.opacity)
            }
        }
    }

    /// Channels, then queries; each kind only reorders among itself.
    private func bufferRows(_ buffers: [BufferModel], in session: NetworkSession, cursor: BufferID?) -> some View {
        let channels = buffers.filter { $0.kind == .channel }
        let queries = buffers.filter { $0.kind == .query }
        let channelIDs = channels.map(\.id)
        let queryIDs = queries.map(\.id)

        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { index, buffer in
                bufferRow(buffer, in: session, index: index, siblings: channelIDs, cursor: cursor)
            }
            if !channels.isEmpty && !queries.isEmpty {
                // Sets conversations a little apart from channels.
                Color.clear.frame(height: 4)
            }
            ForEach(Array(queries.enumerated()), id: \.element.id) { index, buffer in
                bufferRow(buffer, in: session, index: index, siblings: queryIDs, cursor: cursor)
            }
        }
    }

    private func bufferRow(_ buffer: BufferModel, in session: NetworkSession, index: Int, siblings: [BufferID], cursor: BufferID?) -> some View {
        let isLifted = bufferReorder.isDragging(buffer.id)
        return SidebarBufferRow(
            buffer: buffer,
            session: session,
            isSelected: app.selectedBufferID == buffer.id,
            showsKeyboardFocus: cursor == buffer.id
        )
            .background {
                if isLifted {
                    SidebarLiftBackground(cornerRadius: SidebarMetrics.cornerRadius(forRowHeight: style.sidebarRowHeight))
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

    private func networkLift(_ id: UUID) -> some View {
        SidebarNetworkLift(
            id: id,
            controller: networkReorder,
            cornerRadius: SidebarMetrics.cornerRadius(forRowHeight: style.sidebarRowHeight) + 3
        )
        .padding(.horizontal, -4)
        .padding(.vertical, -3)
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

    private var footer: some View {
        HStack(spacing: 2) {
            SidebarAddMenu()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SidebarMetrics.outerInset)
        .frame(height: 36)
    }

    private func toggleRail() {
        if isFloating {
            uiState.isRailHoverExpanded = false
            app.settings[.sidebarCollapsed] = false
        } else {
            app.settings[.sidebarCollapsed] = true
        }
    }
}

/// A network's header: status dot, uppercase name and fold chevron.
/// Clicking it selects the server buffer.
struct SidebarNetworkHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.isSidebarReordering) private var isReordering
    @Environment(\.sidebarKeyboardFocus) private var keyboardFocus
    let session: NetworkSession
    let isSelected: Bool
    let isCollapsed: Bool
    let canCollapse: Bool
    /// The keyboard is on this header (the sidebar has the focus).
    var showsKeyboardFocus = false
    let toggle: () -> Void

    @State private var hovering = false

    var body: some View {
        let showsHover = hovering && !isReordering
        let isOffline = session.connectionState == .disconnected
        let fontSize = CGFloat(max(9, style.sidebarFontSize - 1.5))
        let activity = BufferActivity(headerOf: session, isCollapsed: isCollapsed)
        let foregroundKey = isSelected
            ? ThemeKey.sidebarActiveForeground
            : (isOffline ? ThemeKey.sidebarDisconnectedForeground : ThemeKey.sidebarHeaderForeground)

        HStack(spacing: SidebarMetrics.iconGap) {
            ConnectionIndicator(state: session.connectionState, size: 6)
                .frame(width: SidebarMetrics.iconColumn)
            Text(session.displayName)
                .textCase(.uppercase)
                .font(.system(size: fontSize, weight: .semibold))
                .italic(isOffline)
                .tracking(0.6)
                .foregroundStyle(theme[foregroundKey])
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if !isSelected {
                SidebarActivityIndicator(activity: activity, showsMutedGlyph: false)
            }
            if canCollapse {
                chevron(showsHover: showsHover)
            }
        }
        .padding(.leading, SidebarMetrics.rowPadding)
        .padding(.trailing, canCollapse ? 2 : SidebarMetrics.rowPadding)
        .frame(height: CGFloat(style.sidebarRowHeight) + 2)
        .background { SidebarRowBackground(isSelected: isSelected, isHovering: showsHover) }
        .devTag(
            "Sidebar network header",
            tokens: [
                foregroundKey,
                isSelected ? ThemeKey.sidebarActiveBackground : showsHover ? ThemeKey.sidebarHoverBackground : ThemeKey.sidebarBackground,
            ],
            font: .system(size: fontSize, weight: .semibold),
            padding: EdgeInsets(top: 0, leading: SidebarMetrics.rowPadding, bottom: 0, trailing: canCollapse ? 2 : SidebarMetrics.rowPadding)
        )
        .keyboardFocusRing(showsKeyboardFocus, cornerRadius: SidebarMetrics.cornerRadius(forRowHeight: style.sidebarRowHeight))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .contextMenu { ServerContextMenuItems(session: session) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.displayName)
        .accessibilityValue([session.connectionDescription, isCollapsed ? "collapsed" : nil, activity.accessibilityDescription]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isHeader, .isButton, .isSelected] : [.isHeader, .isButton])
        .accessibilityAction { open() }
        .accessibilityAction(named: isCollapsed ? "Expand" : "Collapse") { toggle() }
    }

    /// Clicked: the console, with the focus in its message box.
    private func open() {
        keyboardFocus?.yieldToClick(uiState)
        app.select(session.serverBuffer)
    }

    private func chevron(showsHover: Bool) -> some View {
        Button(action: toggle) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .foregroundStyle(theme[isSelected ? ThemeKey.sidebarActiveForeground : ThemeKey.sidebarHeaderForeground])
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(showsHover || isCollapsed ? 1 : 0)
        .help(isCollapsed ? "Show channels" : "Hide channels")
        .accessibilityHidden(true)
    }
}

/// A channel or query row.
struct SidebarBufferRow: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.isSidebarReordering) private var isReordering
    @Environment(\.sidebarKeyboardFocus) private var keyboardFocus
    let buffer: BufferModel
    let session: NetworkSession
    let isSelected: Bool
    /// The keyboard is on this row (the sidebar has the focus).
    var showsKeyboardFocus = false

    @State private var hovering = false

    var body: some View {
        let activity = BufferActivity(buffer: buffer, session: session)
        let foreground = theme[activity.foregroundKey(isSelected: isSelected)]
        let split = buffer.kind == .channel ? session.splitChannelPrefix(buffer.name) : ("", buffer.name)

        HStack(spacing: SidebarMetrics.iconGap) {
            icon(prefix: split.0, foreground: foreground, isInactive: activity.isInactive)
                .frame(width: SidebarMetrics.iconColumn)
            Text(split.1)
                .font(.system(size: style.sidebarFontSize, weight: activity.isEmphasized && !isSelected ? .semibold : (isSelected ? .medium : .regular)))
                .italic(activity.isInactive)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if !isSelected {
                SidebarActivityIndicator(activity: activity)
            }
        }
        .padding(.horizontal, SidebarMetrics.rowPadding)
        .frame(height: style.sidebarRowHeight)
        .background { SidebarRowBackground(isSelected: isSelected, isHovering: hovering && !isReordering) }
        .devTag(
            "Sidebar row",
            tokens: [
                activity.foregroundKey(isSelected: isSelected),
                isSelected ? ThemeKey.sidebarActiveBackground : hovering && !isReordering ? ThemeKey.sidebarHoverBackground : ThemeKey.sidebarBackground,
            ],
            font: .system(size: style.sidebarFontSize, weight: activity.isEmphasized && !isSelected ? .semibold : (isSelected ? .medium : .regular)),
            padding: EdgeInsets(top: 0, leading: SidebarMetrics.rowPadding, bottom: 0, trailing: SidebarMetrics.rowPadding)
        )
        .keyboardFocusRing(showsKeyboardFocus, cornerRadius: SidebarMetrics.cornerRadius(forRowHeight: style.sidebarRowHeight))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .contextMenu { BufferContextMenuItems(buffer: buffer, session: session) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(buffer.kind == .query ? "Conversation with \(buffer.name)" : buffer.name)
        .accessibilityValue(activity.accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { open() }
    }

    /// Clicked: the channel or conversation, with the focus in its
    /// message box.
    private func open() {
        keyboardFocus?.yieldToClick(uiState)
        app.select(buffer)
    }

    @ViewBuilder
    private func icon(prefix: String, foreground: Color, isInactive: Bool) -> some View {
        if buffer.kind == .query {
            AvatarView(nick: buffer.name, size: CGFloat(min(16, max(12, style.sidebarRowHeight - 7))))
                .opacity(isInactive ? 0.55 : 1)
        } else {
            Text(prefix.isEmpty ? "#" : prefix)
                .font(.system(size: style.sidebarFontSize, weight: .medium))
                .foregroundStyle(foreground.opacity(0.5))
        }
    }
}
