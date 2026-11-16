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
struct SidebarTreeView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SidebarMetrics.collapsedNetworksKey) private var collapsedNetworks = NetworkIDSet()

    /// Shown over the chat while the rail is hover-expanded.
    var isFloating = false

    var body: some View {
        VStack(spacing: 0) {
            SidebarTitleStrip {
                SidebarIconButton(
                    systemImage: "sidebar.left",
                    help: isFloating ? "Keep Sidebar Open" : "Collapse Sidebar"
                ) {
                    toggleRail()
                }
            }

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(app.sessions.enumerated()), id: \.element.id) { index, session in
                        networkSection(session, isFirst: index == 0)
                    }
                }
                .padding(.horizontal, SidebarMetrics.outerInset)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.automatic)
            .scrollContentBackground(.hidden)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme[ThemeKey.sidebarBackground])
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
    }

    @ViewBuilder
    private func networkSection(_ session: NetworkSession, isFirst: Bool) -> some View {
        let isCollapsed = collapsedNetworks.contains(session.id)
        let buffers = session.sidebarBuffers
        let selectedID = app.selectedBufferID

        SidebarNetworkHeader(
            session: session,
            isSelected: selectedID == session.serverBuffer.id,
            isCollapsed: isCollapsed,
            canCollapse: !buffers.isEmpty
        ) {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                collapsedNetworks.toggle(session.id)
            }
        }
        .padding(.top, isFirst ? 2 : 10)

        if !isCollapsed {
            let firstQueryID = buffers.first { $0.kind == .query }?.id
            ForEach(buffers) { buffer in
                SidebarBufferRow(buffer: buffer, session: session, isSelected: selectedID == buffer.id)
                    .padding(.top, buffer.id == firstQueryID && buffers.first?.id != firstQueryID ? 5 : 0)
                    .transition(.opacity)
            }
        }
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
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let session: NetworkSession
    let isSelected: Bool
    let isCollapsed: Bool
    let canCollapse: Bool
    let toggle: () -> Void

    @State private var hovering = false

    var body: some View {
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
                chevron
            }
        }
        .padding(.leading, SidebarMetrics.rowPadding)
        .padding(.trailing, canCollapse ? 2 : SidebarMetrics.rowPadding)
        .frame(height: CGFloat(style.sidebarRowHeight) + 2)
        .background { SidebarRowBackground(isSelected: isSelected, isHovering: hovering) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { app.select(session.serverBuffer) }
        .contextMenu { ServerContextMenuItems(session: session) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.displayName)
        .accessibilityValue([session.connectionDescription, isCollapsed ? "collapsed" : nil, activity.accessibilityDescription]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isHeader, .isButton, .isSelected] : [.isHeader, .isButton])
        .accessibilityAction { app.select(session.serverBuffer) }
        .accessibilityAction(named: isCollapsed ? "Expand" : "Collapse") { toggle() }
    }

    private var chevron: some View {
        Button(action: toggle) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .foregroundStyle(theme[isSelected ? ThemeKey.sidebarActiveForeground : ThemeKey.sidebarHeaderForeground])
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hovering || isCollapsed ? 1 : 0)
        .help(isCollapsed ? "Show channels" : "Hide channels")
        .accessibilityHidden(true)
    }
}

/// A channel or query row.
struct SidebarBufferRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let buffer: BufferModel
    let session: NetworkSession
    let isSelected: Bool

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
        .background { SidebarRowBackground(isSelected: isSelected, isHovering: hovering) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { app.select(buffer) }
        .contextMenu { BufferContextMenuItems(buffer: buffer, session: session) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(buffer.kind == .query ? "Conversation with \(buffer.name)" : buffer.name)
        .accessibilityValue(activity.accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { app.select(buffer) }
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
