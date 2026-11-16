// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// The collapsed sidebar: a narrow rail of network glyphs and channel tiles.
struct SidebarRailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @AppStorage(SidebarMetrics.collapsedNetworksKey) private var collapsedNetworks = NetworkIDSet()

    var body: some View {
        let selectedID = app.selectedBufferID

        VStack(spacing: 0) {
            // Tall enough for the traffic lights, which stack vertically here.
            SidebarTitleStrip(height: TrafficLightLayout.verticalStackHeight) { EmptyView() }

            ScrollView(.vertical) {
                LazyVStack(spacing: 6) {
                    ForEach(Array(app.sessions.enumerated()), id: \.element.id) { index, session in
                        let isCollapsed = collapsedNetworks.contains(session.id)
                        if index > 0 {
                            Capsule()
                                .fill(theme.color(ThemeKey.railForeground).withAlpha(0.14).color)
                                .frame(width: 24, height: 1)
                                .padding(.vertical, 4)
                                .accessibilityHidden(true)
                        }
                        RailNetworkItem(
                            session: session,
                            isSelected: selectedID == session.serverBuffer.id,
                            isCollapsed: isCollapsed
                        )
                        if !isCollapsed {
                            ForEach(session.sidebarBuffers) { buffer in
                                RailBufferItem(buffer: buffer, session: session, isSelected: selectedID == buffer.id)
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)

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
        .background(theme[ThemeKey.railBackground])
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme[ThemeKey.railBorder]).frame(width: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
    }
}

/// Shared chrome for rail items: hover/selection fill, the indicator on the
/// rail's leading edge (a short pip for unread activity, a tall bar for the
/// selected buffer) and the mention badge.
private struct RailItem<Tile: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isSelected: Bool
    let activity: BufferActivity
    let help: String
    let action: () -> Void
    @ViewBuilder var tile: (_ isHovering: Bool) -> Tile

    @State private var hovering = false

    static var tileSize: CGFloat { 32 }

    var body: some View {
        tile(hovering)
            .frame(width: Self.tileSize, height: Self.tileSize)
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
        if activity.isEmphasized { return hovering ? 12 : 8 }
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
    @Environment(\.theme) private var theme
    let session: NetworkSession
    let isSelected: Bool
    let isCollapsed: Bool

    var body: some View {
        let isOffline = session.connectionState == .disconnected
        RailItem(
            isSelected: isSelected,
            activity: BufferActivity(headerOf: session, isCollapsed: isCollapsed),
            help: "\(session.displayName) — \(session.connectionDescription)",
            action: { app.select(session.serverBuffer) }
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
                        .background(Circle().fill(theme[ThemeKey.railBackground]).padding(-2))
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
    @Environment(\.theme) private var theme
    let buffer: BufferModel
    let session: NetworkSession
    let isSelected: Bool

    var body: some View {
        let activity = BufferActivity(buffer: buffer, session: session)
        let dimmed = activity.isInactive || activity.isMuted
        RailItem(
            isSelected: isSelected,
            activity: activity,
            help: "\(buffer.name) — \(session.displayName)",
            action: { app.select(buffer) }
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
    let activity: BufferActivity

    var body: some View {
        if activity.hasHighlights {
            Text(activity.highlights > 99 ? "99+" : "\(activity.highlights)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(theme[ThemeKey.railBadgeForeground])
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(Capsule().fill(theme[ThemeKey.railBadgeBackground]))
                .background(Capsule().fill(theme[ThemeKey.railBackground]).padding(-2))
                .accessibilityHidden(true)
        }
    }
}
