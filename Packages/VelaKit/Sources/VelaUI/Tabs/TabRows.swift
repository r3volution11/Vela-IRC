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

    var body: some View {
        let metrics = TabMetrics(style: style, height: TabMetrics.channelHeight(style), appearance: appearance)
        let palette = TabPalette.channels(on: surface, appearance: appearance)
        let buffers = tabs
        let ids = buffers.map(\.id)
        let selectedID = app.selectedBufferID
        let selectedIndex = ids.firstIndex { $0 == selectedID }
        let hoveredIndex = ids.firstIndex { interaction.hovered == .buffer($0) }
        let shortcutTargets = TabActions.shortcutTargets(in: session).map(\.id)

        HStack(spacing: 2) {
            TabScroller(target: selectedID, dragsWindow: dragsWindow, isOverflowing: $isOverflowing) {
                HStack(spacing: metrics.gap) {
                    ForEach(Array(buffers.enumerated()), id: \.element.id) { index, buffer in
                        ChannelTab(
                            buffer: buffer,
                            session: session,
                            context: TabContext(
                                metrics: metrics,
                                palette: palette,
                                appearance: appearance,
                                selection: selectionNamespace,
                                isSelected: index == selectedIndex,
                                isHovered: index == hoveredIndex,
                                isFocused: focusedTab == .buffer(buffer.id),
                                showsSeparator: showsSeparator(after: index, count: buffers.count, selected: selectedIndex, hovered: hoveredIndex)
                            ),
                            showsNetworkName: showsNetworkName,
                            shortcutNumber: shortcutTargets.firstIndex(of: buffer.id).flatMap { $0 < 9 ? $0 + 1 : nil },
                            focus: $focusedTab,
                            onSelect: { select(buffer) },
                            onClose: {
                                interaction.setHovering(false, .buffer(buffer.id))
                                TabActions.close(buffer, in: session, app: app)
                            },
                            onHover: { interaction.setHovering($0, .buffer(buffer.id)) }
                        )
                        .tabScrollID(buffer.id)
                        .transition(tabTransition)
                    }
                    TabAddMenu(session: session, height: metrics.height, palette: palette)
                        .padding(.leading, metrics.gap == 0 ? 4 : 2)
                }
                .padding(.leading, leadingInset)
                .padding(.trailing, 8)
                .frame(height: rowHeight, alignment: rowAlignment)
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selectedID)
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: ids)
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
            repairSelection(old: oldValue, new: newValue)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Channels on \(session.displayName)")
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

    private let segmentInset: CGFloat = 2

    var body: some View {
        let sessions = app.sessions
        let height = isSegmented ? tabHeight - segmentInset * 2 : tabHeight
        let metrics = TabMetrics(style: style, height: height, appearance: .floating)
        let palette = TabPalette.servers(on: surface)
        let ids = sessions.map(\.id)
        let selectedID = app.selectedBufferID?.networkID
        let selectedIndex = ids.firstIndex { $0 == selectedID }
        let hoveredIndex = ids.firstIndex { interaction.hovered == .network($0) }

        HStack(spacing: 2) {
            TabScroller(
                target: selectedID,
                isOverflowing: $isOverflowing,
                onContentWidthChange: isSegmented ? { width in
                    if contentWidth != width { contentWidth = width }
                } : nil
            ) {
                HStack(spacing: isSegmented ? 1 : metrics.gap) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        ServerTab(
                            session: session,
                            context: TabContext(
                                metrics: metrics,
                                palette: palette,
                                appearance: .floating,
                                selection: selectionNamespace,
                                isSelected: index == selectedIndex,
                                isHovered: index == hoveredIndex,
                                isFocused: focusedTab == .network(session.id),
                                showsSeparator: !isSegmented && showsSeparator(after: index, count: sessions.count, selected: selectedIndex, hovered: hoveredIndex)
                            ),
                            focus: $focusedTab,
                            onSelect: {
                                TabActions.select(session, app: app)
                                uiState.focusInput()
                            },
                            onHover: { interaction.setHovering($0, .network(session.id)) }
                        )
                        .tabScrollID(session.id)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Networks")
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

/// Separators sit between two unselected, unhovered tabs.
private func showsSeparator(after index: Int, count: Int, selected: Int?, hovered: Int?) -> Bool {
    guard index < count - 1 else { return false }
    let neighbors = [index, index + 1]
    if let selected, neighbors.contains(selected) { return false }
    if let hovered, neighbors.contains(hovered) { return false }
    return true
}
