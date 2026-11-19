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
    /// Being dragged: drawn picked up, over the tabs it passes.
    var isLifted = false
}

// MARK: Channel row

/// A server-console, channel or query tab in the second row.
///
/// A channel or query tab starts with its glyph (`#`, `##` or an avatar)
/// in a fixed slot, like a browser tab's icon. Pointing at the slot turns
/// the glyph into a ×, and only the slot closes the tab: a click anywhere
/// else on it selects it. Middle-click, the context menu and VoiceOver's
/// Close action close it too.
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
    /// Drag-to-reorder; nil for the server console, which stays first.
    let reorder: TabReorder<BufferID>?
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void

    private var metrics: TabMetrics { context.metrics }
    private var palette: TabPalette { context.palette }
    private var isServer: Bool { buffer.kind == .server }
    private var isClosable: Bool { !isServer }
    private var unread: Int { buffer.isMuted ? 0 : buffer.unreadCount }
    /// The full name, for VoiceOver and the tooltip.
    private var title: String { BufferTitle.title(for: buffer, in: session) }
    private var isIconOnly: Bool { isServer && !showsNetworkName }

    /// What the tab shows: a channel's type prefix moves into the slot.
    private var displayName: (glyph: String, title: String) {
        guard buffer.kind == .channel else { return ("", title) }
        let split = session.splitChannelPrefix(buffer.name, maxLength: 2)
        return (split.prefix.isEmpty ? "#" : split.prefix, split.prefix.isEmpty ? buffer.name : split.name)
    }

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
        let name = displayName
        let slotInsets = isClosable ? metrics.closeSlotInsets(glyphWidth: glyphWidth(name.glyph)) : nil

        Button(action: onSelect) { label(name, slotInsets: slotInsets) }
            .buttonStyle(TabButtonStyle())
            .focusEffectDisabled()
            .focused(focus, equals: .buffer(buffer.id))
            .accessibilityLabel(isServer ? "\(session.displayName) server console" : title)
            .accessibilityValue(TabDescriptions.bufferValue(buffer, in: session))
            .accessibilityHint(TabDescriptions.bufferKind(buffer))
            .accessibilityAddTraits(context.isSelected ? .isSelected : [])
            .accessibilityActions {
                if isClosable {
                    Button(TabDescriptions.closeAction(buffer), action: onClose)
                }
            }
            .tabMoveActions(reorder)
            // The label starts drags; the close slot over it doesn't.
            .tabDragHandle(reorder)
            .overlay(alignment: .leading) {
                if let slotInsets {
                    closeSlot(glyph: name.glyph)
                        .padding(.leading, slotInsets.leading)
                }
            }
            .background { chrome }
            .overlay(alignment: .trailing) {
                TabSeparator(key: palette.separator, height: (metrics.height * 0.45).rounded())
                    .offset(x: (metrics.gap + 1) / 2)
                    .opacity(context.showsSeparator ? 1 : 0)
            }
            .overlay { focusRing }
            .onHover(perform: onHover)
            .animation(.easeOut(duration: 0.12), value: context.isHovered)
            .animation(.easeOut(duration: 0.12), value: context.isLifted)
            .contextMenu { BufferContextMenuItems(buffer: buffer, session: session) }
            .help(helpText)
    }

    /// `slotInsets`: room for the close slot (drawn over the label, so its
    /// clicks are its own), or nil for the server console, which has none.
    private func label(_ name: (glyph: String, title: String), slotInsets: (leading: CGFloat, trailing: CGFloat)?) -> some View {
        HStack(spacing: 0) {
            if let slotInsets {
                Color.clear.frame(width: metrics.closeSlot + slotInsets.trailing, height: metrics.closeSlot)
            }
            HStack(spacing: metrics.spacing) {
                if isServer {
                    Image(systemName: "server.rack")
                        .font(.system(size: max(9, metrics.fontSize - 1), weight: .medium))
                        .foregroundStyle(theme[textKey])
                        .accessibilityHidden(true)
                }
                if !isIconOnly {
                    titleView(name.title)
                }
                if buffer.isMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: max(8, metrics.fontSize - 3)))
                        .foregroundStyle(theme[palette.dimText])
                        .accessibilityHidden(true)
                }
                if let badge {
                    UnreadBadge(count: badge.count, isHighlight: badge.isHighlight, fontSize: metrics.badgeFontSize)
                }
            }
        }
        .padding(.leading, slotInsets?.leading ?? (isIconOnly ? metrics.horizontalPadding * 0.8 : metrics.horizontalPadding))
        .padding(.trailing, isIconOnly ? metrics.horizontalPadding * 0.8 : metrics.horizontalPadding)
        // Short names leave the extra width after the title, keeping the
        // close slot at the leading edge and the middle of the tab for selecting.
        .frame(minWidth: isIconOnly ? metrics.height * 1.25 : metrics.minWidth, alignment: isIconOnly ? .center : .leading)
        .frame(height: metrics.height)
        // Tabs are always as wide as their content, never stretched by the row.
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
    }

    /// The title reserves its semibold width, so tabs don't change size when
    /// their unread state changes.
    private func titleView(_ title: String) -> some View {
        Text(title)
            .font(.system(size: metrics.fontSize, weight: .semibold))
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: metrics.maxLabelWidth)
            .overlay(alignment: .leading) {
                Text(title)
                    .font(.system(size: metrics.fontSize, weight: titleWeight))
                    .foregroundStyle(theme[textKey])
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
    }

    private var titleWeight: Font.Weight { isEmphasized || context.isSelected ? .semibold : .regular }

    private func glyphWidth(_ glyph: String) -> CGFloat {
        buffer.kind == .query ? metrics.iconSize + 1 : metrics.channelGlyphWidth(glyph)
    }

    private func closeSlot(glyph: String) -> some View {
        TabCloseSlot(
            size: metrics.closeSlot,
            isEnabled: style.tabsShowCloseButtons,
            isTabHovered: context.isHovered,
            foreground: context.isSelected ? palette.selectedText : palette.unreadText,
            action: onClose
        ) {
            if buffer.kind == .query {
                AvatarView(nick: buffer.name, size: metrics.iconSize + 1)
                    .opacity(isDimmed && !context.isSelected ? 0.55 : 1)
            } else {
                Text(glyph)
                    .font(.system(size: metrics.fontSize, weight: titleWeight))
                    .foregroundStyle(theme[textKey])
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var chrome: some View {
        switch context.appearance {
        case .attached(let edge):
            // A selected attached tab stays joined to the conversation
            // while dragged along it, so it isn't lifted off it.
            if context.isSelected {
                AttachedSelectionChrome(edge: edge, metrics: metrics, palette: palette)
                    .matchedGeometryEffect(id: "selected-tab", in: context.selection)
            } else if context.isHovered || context.isLifted {
                FloatingTabFill(key: palette.hoverFill, radius: style.tabCornerRadius(forHeight: metrics.height - 6), liftBacking: liftBacking)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 2)
            }
        case .floating:
            if context.isSelected {
                FloatingTabFill(key: palette.selectedFill, radius: metrics.radius, liftBacking: liftBacking)
                    .matchedGeometryEffect(id: "selected-tab", in: context.selection)
            } else if context.isHovered || context.isLifted {
                FloatingTabFill(key: palette.hoverFill, radius: metrics.radius, liftBacking: liftBacking)
            }
        }
    }

    private var liftBacking: [String]? { context.isLifted ? palette.liftBacking : nil }

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
    let reorder: TabReorder<UUID>?
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
            .tabMoveActions(reorder)
            .tabDragHandle(reorder)
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
            .animation(.easeOut(duration: 0.12), value: context.isLifted)
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
        let liftBacking = context.isLifted ? palette.liftBacking : nil
        if context.isSelected {
            FloatingTabFill(key: palette.selectedFill, radius: metrics.radius, liftBacking: liftBacking)
                .matchedGeometryEffect(id: "selected-network", in: context.selection)
        } else if context.isHovered || context.isLifted {
            FloatingTabFill(key: palette.hoverFill, radius: metrics.radius, liftBacking: liftBacking)
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

/// The slot at the start of a channel or query tab: the tab's glyph, and
/// its close button. With the pointer over the slot (and only the slot)
/// the glyph gives way to a ×; anywhere else on the tab just dims the glyph
/// a little, so passing over tabs never puts a × under the pointer.
///
/// Its hover state is its own: pointing at it redraws this slot, not the
/// row. With close buttons off (`tabs.showCloseButtons`) it's only the
/// glyph, and clicks on it select the tab.
struct TabCloseSlot<Glyph: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let size: CGFloat
    let isEnabled: Bool
    /// The pointer is somewhere on the tab.
    let isTabHovered: Bool
    /// Token for the ×: the tab's strongest text color, so it reads on the
    /// tab's fill in every theme.
    let foreground: String
    let action: () -> Void
    @ViewBuilder let glyph: Glyph

    @State private var isHovering = false

    var body: some View {
        if isEnabled {
            Button(action: action) {
                ZStack {
                    glyph
                        .opacity(isHovering ? 0 : (isTabHovered ? 0.55 : 1))
                    if isHovering {
                        closeMark
                    }
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
            }
            .buttonStyle(TabButtonStyle())
            // One keyboard stop per tab: the tab, whose menu and actions close it.
            .focusable(false)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovering)
            .animation(.easeOut(duration: 0.12), value: isTabHovered)
            .help("Close Tab")
        } else {
            glyph
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        }
    }

    private var closeMark: some View {
        let color = theme[foreground]
        return Image(systemName: "xmark")
            .font(.system(size: (size * 0.46).rounded(), weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: max(3, TabMetrics.radius(style, forHeight: size)), style: .continuous)
                    .fill(color.opacity(theme.kind == .dark ? 0.18 : 0.12))
            )
            .transition(.opacity)
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
