// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaTheme

/// Row-level state a tab needs to draw itself.
struct TabContext {
    var metrics: TabMetrics
    var palette: TabPalette
    var appearance: TabAppearance
    var selection: Namespace.ID
    var isSelected: Bool
    var isHovered: Bool
    var isFocused: Bool
    var showsSeparator: Bool
}

// MARK: Channel row

/// A server-console, channel or query tab in the second row.
struct ChannelTab: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let buffer: BufferModel
    let session: NetworkSession
    let context: TabContext
    /// Show the network name on the server-console tab (when there's no server row).
    let showsNetworkName: Bool
    /// 1-based ⌘-number, for the tooltip.
    let shortcutNumber: Int?
    let focus: FocusState<TabKey?>.Binding
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void

    private var metrics: TabMetrics { context.metrics }
    private var palette: TabPalette { context.palette }
    private var isServer: Bool { buffer.kind == .server }
    private var isClosable: Bool { !isServer }
    private var unread: Int { buffer.isMuted ? 0 : buffer.unreadCount }
    private var showsClose: Bool { style.tabsShowCloseButtons && isClosable && context.isHovered }
    private var title: String { BufferTitle.title(for: buffer, in: session) }
    private var isIconOnly: Bool { isServer && !showsNetworkName }

    private var isDimmed: Bool {
        if !session.isConnected { return true }
        switch buffer.kind {
        case .server: return false
        case .channel: return !buffer.isJoined || buffer.isMuted
        case .query: return buffer.isMuted
        }
    }

    private var badge: (count: Int, isHighlight: Bool)? {
        guard style.tabsShowUnreadBadges else { return nil }
        if buffer.highlightCount > 0 { return (buffer.highlightCount, true) }
        if unread > 0 { return (unread, false) }
        return nil
    }

    private var textKey: String {
        if context.isSelected { return palette.selectedText }
        if isDimmed { return palette.dimText }
        if buffer.highlightCount > 0 { return palette.highlightText }
        if unread > 0 { return palette.unreadText }
        return palette.text
    }

    private var isEmphasized: Bool { buffer.highlightCount > 0 || unread > 0 }

    var body: some View {
        Button(action: onSelect) { label }
            .buttonStyle(TabButtonStyle())
            .focusEffectDisabled()
            .focused(focus, equals: .buffer(buffer.id))
            .accessibilityLabel(isServer ? "\(session.displayName) server console" : title)
            .accessibilityValue(TabDescriptions.bufferValue(buffer, in: session))
            .accessibilityHint(TabDescriptions.bufferKind(buffer))
            .accessibilityAddTraits(context.isSelected ? .isSelected : [])
            .accessibilityActions {
                if isClosable {
                    Button(buffer.kind == .channel ? "Close Channel" : "Close Conversation", action: onClose)
                }
            }
            .background { chrome }
            .overlay(alignment: .trailing) {
                if showsClose {
                    TabCloseButton(height: metrics.height, palette: palette, isSelected: context.isSelected, action: onClose)
                        .padding(.trailing, max(3, metrics.horizontalPadding - metrics.height * 0.36))
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .trailing) {
                TabSeparator(key: palette.separator, height: (metrics.height * 0.45).rounded())
                    .offset(x: (metrics.gap + 1) / 2)
                    .opacity(context.showsSeparator ? 1 : 0)
            }
            .overlay { focusRing }
            .onHover(perform: onHover)
            .animation(.easeOut(duration: 0.12), value: context.isHovered)
            .contextMenu { BufferContextMenuItems(buffer: buffer, session: session) }
            .help(helpText)
    }

    private var label: some View {
        HStack(spacing: metrics.spacing) {
            icon
            if !isIconOnly {
                titleView
            }
            if buffer.isMuted {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: max(8, metrics.fontSize - 3)))
                    .foregroundStyle(theme[palette.dimText])
                    .accessibilityHidden(true)
            }
            if let badge {
                UnreadBadge(count: badge.count, isHighlight: badge.isHighlight, fontSize: metrics.badgeFontSize)
                    .opacity(showsClose ? 0 : 1)
            }
        }
        .padding(.horizontal, isIconOnly ? metrics.horizontalPadding * 0.8 : metrics.horizontalPadding)
        .frame(minWidth: isIconOnly ? metrics.height * 1.25 : metrics.minWidth)
        .frame(height: metrics.height)
        // Tabs are always as wide as their content, never stretched by the row.
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
    }

    /// The title reserves its semibold width, so tabs don't change size when
    /// their unread state changes.
    private var titleView: some View {
        Text(title)
            .font(.system(size: metrics.fontSize, weight: .semibold))
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: metrics.maxLabelWidth)
            .overlay(alignment: .leading) {
                Text(title)
                    .font(.system(size: metrics.fontSize, weight: isEmphasized || context.isSelected ? .semibold : .regular))
                    .foregroundStyle(theme[textKey])
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .mask {
                // Fade the end of the title under the close button when there's no badge to swap with.
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: showsClose && badge == nil ? metrics.height * 0.75 : 0)
                }
            }
    }

    @ViewBuilder
    private var icon: some View {
        switch buffer.kind {
        case .server:
            Image(systemName: "server.rack")
                .font(.system(size: max(9, metrics.fontSize - 1), weight: .medium))
                .foregroundStyle(theme[textKey])
                .accessibilityHidden(true)
        case .query:
            AvatarView(nick: buffer.name, size: metrics.iconSize + 1)
                .opacity(isDimmed && !context.isSelected ? 0.55 : 1)
        case .channel:
            EmptyView()
        }
    }

    @ViewBuilder
    private var chrome: some View {
        switch context.appearance {
        case .attached(let edge):
            if context.isSelected {
                AttachedSelectionChrome(edge: edge, metrics: metrics, palette: palette)
                    .matchedGeometryEffect(id: "selected-tab", in: context.selection)
            } else if context.isHovered {
                FloatingTabFill(key: palette.hoverFill, radius: style.tabCornerRadius(forHeight: metrics.height - 6))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 2)
            }
        case .floating:
            if context.isSelected {
                FloatingTabFill(key: palette.selectedFill, radius: metrics.radius)
                    .matchedGeometryEffect(id: "selected-tab", in: context.selection)
            } else if context.isHovered {
                FloatingTabFill(key: palette.hoverFill, radius: metrics.radius)
            }
        }
    }

    @ViewBuilder
    private var focusRing: some View {
        if context.isFocused {
            RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                .strokeBorder(theme[ThemeKey.focusBorder], lineWidth: 2)
                .allowsHitTesting(false)
        }
    }

    private var helpText: String {
        var text = isServer ? "\(session.displayName) — server console" : title
        let activity = TabDescriptions.activity(unread: unread, highlights: buffer.highlightCount)
        if !activity.isEmpty { text += " — " + activity.joined(separator: ", ") }
        if let shortcutNumber { text += "  ⌘\(shortcutNumber)" }
        return text
    }
}

// MARK: Server row

/// One network in the first row (or the title bar's segmented group).
struct ServerTab: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let session: NetworkSession
    let context: TabContext
    let focus: FocusState<TabKey?>.Binding
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    private var metrics: TabMetrics { context.metrics }
    private var palette: TabPalette { context.palette }
    private var highlights: Int { session.totalHighlights }
    private var unread: Int { session.totalUnread }
    private var isOffline: Bool { session.connectionState == .disconnected }

    private var textKey: String {
        if context.isSelected { return palette.selectedText }
        if isOffline { return palette.dimText }
        if highlights > 0 { return palette.highlightText }
        if unread > 0 { return palette.unreadText }
        return palette.text
    }

    var body: some View {
        Button(action: onSelect) { label }
            .buttonStyle(TabButtonStyle())
            .focusEffectDisabled()
            .focused(focus, equals: .network(session.id))
            .accessibilityLabel(session.displayName)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Network. Shows its channels.")
            .accessibilityAddTraits(context.isSelected ? .isSelected : [])
            .background { chrome }
            .overlay(alignment: .trailing) {
                TabSeparator(key: palette.separator, height: (metrics.height * 0.45).rounded())
                    .offset(x: (metrics.gap + 1) / 2)
                    .opacity(context.showsSeparator ? 1 : 0)
            }
            .overlay {
                if context.isFocused {
                    RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                        .strokeBorder(theme[ThemeKey.focusBorder], lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .onHover(perform: onHover)
            .animation(.easeOut(duration: 0.12), value: context.isHovered)
            .contextMenu { ServerContextMenuItems(session: session) }
            .help(helpText)
    }

    private var label: some View {
        HStack(spacing: metrics.spacing) {
            ConnectionDot(state: session.connectionState, size: max(5, (metrics.height * 0.24).rounded()), offlineKey: palette.dimText)
            Text(session.displayName)
                .font(.system(size: metrics.fontSize, weight: context.isSelected || highlights > 0 || unread > 0 ? .semibold : .medium))
                .foregroundStyle(theme[textKey])
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: metrics.maxLabelWidth)
            if style.tabsShowUnreadBadges, highlights > 0 || unread > 0 {
                UnreadBadge(
                    count: highlights > 0 ? highlights : unread,
                    isHighlight: highlights > 0,
                    fontSize: metrics.badgeFontSize
                )
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(height: metrics.height)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
        .opacity(isOffline && !context.isSelected ? 0.85 : 1)
    }

    @ViewBuilder
    private var chrome: some View {
        if context.isSelected {
            FloatingTabFill(key: palette.selectedFill, radius: metrics.radius)
                .matchedGeometryEffect(id: "selected-network", in: context.selection)
        } else if context.isHovered {
            FloatingTabFill(key: palette.hoverFill, radius: metrics.radius)
        }
    }

    private var accessibilityValue: String {
        ([TabDescriptions.connection(session.connectionState)]
            + TabDescriptions.activity(unread: unread, highlights: highlights))
            .joined(separator: ", ")
    }

    private var helpText: String {
        var text = "\(session.displayName) — \(TabDescriptions.connection(session.connectionState))"
        let activity = TabDescriptions.activity(unread: unread, highlights: highlights)
        if !activity.isEmpty { text += ", " + activity.joined(separator: ", ") }
        return text
    }
}

/// Connection state: a filled dot when connected, pulsing while connecting,
/// a hollow ring when offline.
struct ConnectionDot: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: IRCConnectionState
    let size: CGFloat
    let offlineKey: String

    var body: some View {
        Group {
            switch state {
            case .connected:
                Circle().fill(theme[ThemeKey.statusSuccess])
            case .connecting, .registering:
                if reduceMotion {
                    Circle().fill(theme[ThemeKey.statusWarning])
                } else {
                    Circle().fill(theme[ThemeKey.statusWarning])
                        .phaseAnimator([1.0, 0.3]) { content, opacity in
                            content.opacity(opacity)
                        } animation: { _ in .easeInOut(duration: 0.7) }
                }
            case .disconnected:
                Circle().strokeBorder(theme[offlineKey], lineWidth: 1.25)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: Row controls

/// Close button shown over a hovered tab.
struct TabCloseButton: View {
    let height: CGFloat
    let palette: TabPalette
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TabToolLabel(
                systemImage: "xmark",
                size: max(14, (height * 0.58).rounded()),
                foreground: isSelected ? palette.selectedText : palette.text,
                hoverFill: palette.hoverFill,
                isHovering: hovering,
                weight: .bold
            )
        }
        .buttonStyle(TabButtonStyle())
        .onHover { hovering = $0 }
        .help("Close Tab")
        .accessibilityHidden(true)
    }
}

/// The "+" at the end of the channel row.
struct TabAddMenu: View {
    @Environment(UIState.self) private var uiState
    let session: NetworkSession?
    let height: CGFloat
    let palette: TabPalette

    @State private var hovering = false

    var body: some View {
        Menu {
            Button("Join Channel…") {
                if let session { uiState.joinChannelNetwork = session.id }
            }
            .disabled(session.map { !$0.isConnected || $0.isBouncerControl } ?? true)
            Button("Add Network…") { uiState.networkEditor = .new }
        } label: {
            TabToolLabel(
                systemImage: "plus",
                size: (height * 0.82).rounded(),
                foreground: palette.text,
                hoverFill: palette.hoverFill,
                isHovering: hovering
            )
        }
        .menuStyle(.button)
        .buttonStyle(TabButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Join a channel or add a network")
        .accessibilityLabel("New Tab")
    }
}

/// The "+" at the end of the server row.
struct TabAddNetworkButton: View {
    @Environment(UIState.self) private var uiState
    let height: CGFloat
    let palette: TabPalette

    @State private var hovering = false

    var body: some View {
        Button { uiState.networkEditor = .new } label: {
            TabToolLabel(
                systemImage: "plus",
                size: (height * 0.9).rounded(),
                foreground: palette.text,
                hoverFill: palette.hoverFill,
                isHovering: hovering
            )
        }
        .buttonStyle(TabButtonStyle())
        .onHover { hovering = $0 }
        .help("Add Network…")
        .accessibilityLabel("Add Network")
    }
}

/// » menu listing every tab of a row that overflows.
struct TabOverflowMenu<Items: View>: View {
    let height: CGFloat
    let palette: TabPalette
    let accessibilityLabel: String
    @ViewBuilder let items: () -> Items

    @State private var hovering = false

    var body: some View {
        Menu(content: items) {
            TabToolLabel(
                systemImage: "chevron.right.2",
                size: (height * 0.82).rounded(),
                foreground: palette.text,
                hoverFill: palette.hoverFill,
                isHovering: hovering
            )
        }
        .menuStyle(.button)
        .buttonStyle(TabButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}
