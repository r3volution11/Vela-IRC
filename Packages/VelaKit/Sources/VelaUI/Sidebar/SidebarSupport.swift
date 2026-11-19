// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// Shared geometry for the sidebar tree and the collapsed rail.
enum SidebarMetrics {
    /// Height of the window's title strip; kept clear for the traffic lights.
    static let titleStripHeight: CGFloat = 52
    /// Width of the collapsed rail.
    static let railWidth: CGFloat = 56
    /// Side of a network glyph or channel tile in the rail.
    static let railTileSize: CGFloat = 32
    /// Allowed tree widths (settings `sidebar.width`).
    static let widthRange: ClosedRange<Double> = 110...360
    /// Inset of row backgrounds from the sidebar edges.
    static let outerInset: CGFloat = 8
    /// Padding inside a row, before the icon column.
    static let rowPadding: CGFloat = 6
    /// Width of the leading icon column (`#`, avatars, status dots).
    static let iconColumn: CGFloat = 16
    /// Gap between the icon column and the name.
    static let iconGap: CGFloat = 5
    /// Delay before hovering the rail floats the full tree over the chat.
    static let hoverExpandDelay: Duration = .milliseconds(350)
    /// Grace period before the floating tree closes after the pointer leaves.
    static let hoverCollapseDelay: Duration = .milliseconds(200)
    /// `UserDefaults` key of the networks whose channels are folded away.
    static let collapsedNetworksKey = "Vela.sidebar.collapsedNetworks"

    static func clampedWidth(_ width: Double) -> CGFloat {
        CGFloat(min(widthRange.upperBound, max(widthRange.lowerBound, width)))
    }

    static func cornerRadius(forRowHeight height: Double) -> CGFloat {
        CGFloat(min(6, max(3, height / 3.6)))
    }
}

/// Networks folded in the sidebar, stored in `UserDefaults` via `@AppStorage`
/// (view state, not a preference worth a settings.json key).
nonisolated struct NetworkIDSet: RawRepresentable, Equatable, Sendable {
    var ids: Set<UUID>

    init(_ ids: Set<UUID> = []) {
        self.ids = ids
    }

    init?(rawValue: String) {
        ids = Set(rawValue.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    var rawValue: String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    mutating func toggle(_ id: UUID) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }
}

/// How a buffer is emphasized in the sidebar and the rail.
struct BufferActivity: Equatable {
    var unread: Int
    var highlights: Int
    var isMuted: Bool
    /// Parted channel, or a network that isn't connected.
    var isInactive: Bool

    init(unread: Int, highlights: Int, isMuted: Bool, isInactive: Bool) {
        self.unread = unread
        self.highlights = highlights
        self.isMuted = isMuted
        self.isInactive = isInactive
    }

    init(buffer: BufferModel, session: NetworkSession) {
        self.init(
            unread: buffer.unreadCount,
            highlights: buffer.highlightCount,
            isMuted: buffer.isMuted,
            isInactive: !session.isConnected || (buffer.kind == .channel && !buffer.isJoined)
        )
    }

    /// Everything hidden under a folded network header.
    init(aggregating buffers: [BufferModel]) {
        self.init(
            unread: buffers.reduce(0) { $0 + ($1.isMuted ? 0 : $1.unreadCount) },
            highlights: buffers.reduce(0) { $0 + $1.highlightCount },
            isMuted: false,
            isInactive: false
        )
    }

    /// A network header or glyph: folded networks summarize their hidden
    /// buffers; otherwise only mentions in the server buffer (e.g. notices
    /// addressed to you) are worth a badge.
    init(headerOf session: NetworkSession, isCollapsed: Bool) {
        if isCollapsed {
            self.init(aggregating: session.sidebarBuffers)
        } else {
            self.init(unread: 0, highlights: 0, isMuted: false, isInactive: false)
        }
        highlights += session.serverBuffer.highlightCount
    }

    /// Mentions break through muting; plain unread messages don't.
    var hasHighlights: Bool { highlights > 0 }
    var hasUnread: Bool { !isMuted && unread > 0 }
    var isEmphasized: Bool { hasHighlights || hasUnread }

    /// The text color token for a row in the tree.
    func foregroundKey(isSelected: Bool) -> String {
        if isSelected { return ThemeKey.sidebarActiveForeground }
        if hasHighlights { return ThemeKey.sidebarHighlightForeground }
        if isInactive { return ThemeKey.sidebarDisconnectedForeground }
        if isMuted { return ThemeKey.sidebarSecondaryForeground }
        if hasUnread { return ThemeKey.sidebarUnreadForeground }
        return ThemeKey.sidebarForeground
    }

    /// Spoken after the buffer name, e.g. "2 mentions, 5 unread, muted".
    var accessibilityDescription: String {
        var parts: [String] = []
        if highlights > 0 { parts.append(highlights == 1 ? "1 mention" : "\(highlights) mentions") }
        if unread > 0 && !isMuted { parts.append("\(unread) unread") }
        if isMuted { parts.append("muted") }
        if isInactive { parts.append("inactive") }
        return parts.joined(separator: ", ")
    }
}

extension NetworkSession {
    /// The network's channels and queries, or nothing for a bouncer control
    /// connection (which only shows its server buffer).
    var sidebarBuffers: [BufferModel] {
        isBouncerControl ? [] : buffers
    }

    /// Spoken/visible connection state.
    var connectionDescription: String {
        switch connectionState {
        case .connected: "connected"
        case .connecting, .registering: "connecting"
        case .disconnected: "disconnected"
        }
    }

    /// Splits a channel name into its type prefix (`#`, `&`…) and the rest.
    /// `maxLength` allows a longer prefix: with 2, `##linux` is `##` and `linux`.
    func splitChannelPrefix(_ name: String, maxLength: Int = 1) -> (prefix: String, name: String) {
        let types = isupport.channelTypes
        let prefix = name.prefix { types.contains($0) || $0 == "#" }.prefix(max(1, maxLength))
        guard !prefix.isEmpty else { return ("", name) }
        let rest = name.dropFirst(prefix.count)
        return (String(prefix), rest.isEmpty ? name : String(rest))
    }
}

/// Short labels for rail tiles.
enum RailLabel {
    /// One or two letters for a channel tile: `#swift-lang` → `SL`, `#vela` → `Ve`.
    static func initials(for name: String) -> String {
        let trimmed = name.drop { !$0.isLetter && !$0.isNumber }
        let words = trimmed
            .split { $0 == "-" || $0 == "_" || $0 == "." || $0 == " " || $0 == "/" }
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
        if words.count >= 2, let a = words[0].first, let b = words[1].first {
            return (String(a) + String(b)).uppercased()
        }
        let letters = trimmed.filter { $0.isLetter || $0.isNumber }
        guard let first = letters.first else { return String(name.prefix(1)) }
        let second = letters.dropFirst().first.map { String($0).lowercased() } ?? ""
        return String(first).uppercased() + second
    }

    /// The network glyph letter: `Libera.Chat` → `L`.
    static func networkInitial(for name: String) -> String {
        guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Small shared views

/// A dot (or ring) showing a network's connection state with `status.*` colors.
struct ConnectionIndicator: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: IRCConnectionState
    var size: CGFloat = 6

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
                        } animation: { _ in
                            .easeInOut(duration: 0.7)
                        }
                }
            case .disconnected:
                Circle().strokeBorder(theme[ThemeKey.statusError], lineWidth: max(1, size / 5))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The row background used by the tree: selection, hover or nothing.
struct SidebarRowBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let isSelected: Bool
    let isHovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: SidebarMetrics.cornerRadius(forRowHeight: style.sidebarRowHeight), style: .continuous)
            .fill(isSelected ? theme[ThemeKey.sidebarActiveBackground] : (isHovering ? theme[ThemeKey.sidebarHoverBackground] : .clear))
    }
}

/// Unread badge, highlight badge, dot or muted glyph at the end of a row.
struct SidebarActivityIndicator: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let activity: BufferActivity
    var showsMutedGlyph = true

    var body: some View {
        let fontSize = CGFloat(max(9, style.sidebarFontSize - 2))
        if activity.hasHighlights {
            if style.sidebarShowUnreadCounts {
                UnreadBadge(count: activity.highlights, isHighlight: true, fontSize: fontSize)
            } else {
                dot(ThemeKey.sidebarHighlightBadgeBackground)
                    .accessibilityLabel("Mentions")
            }
        } else if activity.hasUnread {
            if style.sidebarShowUnreadCounts {
                UnreadBadge(count: activity.unread, fontSize: fontSize)
            } else {
                dot(ThemeKey.sidebarUnreadForeground)
                    .accessibilityLabel("Unread")
            }
        } else if activity.isMuted && showsMutedGlyph {
            Image(systemName: "bell.slash")
                .font(.system(size: fontSize - 1, weight: .medium))
                .foregroundStyle(theme[ThemeKey.sidebarSecondaryForeground])
                .accessibilityLabel("Muted")
        }
    }

    private func dot(_ key: String) -> some View {
        Circle()
            .fill(theme[key])
            .frame(width: 6, height: 6)
            .padding(.trailing, 2)
    }
}

/// Small borderless icon button drawn with sidebar tokens.
struct SidebarIconButton: View {
    @Environment(\.theme) private var theme
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .foregroundStyle(theme[hovering ? ThemeKey.sidebarForeground : ThemeKey.sidebarSecondaryForeground])
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? theme[ThemeKey.sidebarHoverBackground] : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

/// The "+" menu: Add Network… and Join Channel….
struct SidebarAddMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme

    @State private var hovering = false

    var body: some View {
        let joinTarget = Self.joinTarget(in: app)
        Menu {
            Button("Add Network…") { uiState.networkEditor = .new }
            Button(joinTarget.map { "Join Channel on \($0.displayName)…" } ?? "Join Channel…") {
                if let joinTarget { uiState.joinChannelNetwork = joinTarget.id }
            }
            .disabled(joinTarget == nil)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .foregroundStyle(theme[hovering ? ThemeKey.sidebarForeground : ThemeKey.sidebarSecondaryForeground])
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? theme[ThemeKey.sidebarHoverBackground] : .clear)
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Add a network or join a channel")
        .accessibilityLabel("Add")
    }

    /// The selected network when it can join channels, else the first one that can.
    static func joinTarget(in app: AppModel) -> NetworkSession? {
        func canJoin(_ session: NetworkSession) -> Bool { session.isConnected && !session.isBouncerControl }
        if let selected = app.selectedSession, canJoin(selected) { return selected }
        return app.sessions.first(where: canJoin)
    }
}

/// The empty top strip that keeps the traffic lights clear and drags the window.
struct SidebarTitleStrip<Accessory: View>: View {
    var height: CGFloat = SidebarMetrics.titleStripHeight
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, SidebarMetrics.outerInset)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .windowTitleBarArea()
        .allowsWindowActivationEvents(true)
    }
}

// MARK: - Reordering

/// A top-level network and, for a soju bouncer, the networks it provides:
/// the block that moves when a top-level network is dragged.
struct SidebarNetworkGroup: Identifiable {
    var network: NetworkSession
    var children: [NetworkSession] = []

    var id: UUID { network.id }

    /// A bouncer network whose bouncer is gone. Shown on its own and not
    /// draggable: it has no place among the top-level networks.
    var isOrphan: Bool { network.config.parentNetworkID != nil }
}

extension AppModel {
    /// `sessions` grouped under their bouncers, in display order (bouncer
    /// networks already follow their bouncer there).
    var sidebarGroups: [SidebarNetworkGroup] {
        var groups: [SidebarNetworkGroup] = []
        var groupIndex: [UUID: Int] = [:]
        for session in sessions {
            if let parent = session.config.parentNetworkID, let index = groupIndex[parent] {
                groups[index].children.append(session)
            } else {
                groupIndex[session.id] = groups.count
                groups.append(SidebarNetworkGroup(network: session))
            }
        }
        return groups
    }
}

extension EnvironmentValues {
    /// Whether an item in this sidebar (or rail) is being dragged. Rows hold
    /// back their hover highlight meanwhile, so it doesn't flicker across
    /// the rows the drag passes over.
    @Entry var isSidebarReordering = false
}

/// The raised look of an item being dragged: an opaque tile with the hover
/// tint, so it hides the rows it passes over, and a soft shadow.
struct SidebarLiftBackground: View {
    @Environment(\.theme) private var theme
    /// The surface the tile stands on (`sidebar.background` or `rail.background`).
    var surface: String = ThemeKey.sidebarBackground
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme.color(ThemeKey.sidebarHoverBackground).composited(over: theme.color(surface)).color)
            .shadow(color: .black.opacity(theme.kind == .dark ? 0.4 : 0.16), radius: 6, y: 2)
    }
}

/// The lifted backdrop of a network while it's dragged. A section is
/// several views (header, rows, bouncer networks) that move separately, so
/// the container that holds them draws one backdrop behind them all; as
/// the container itself stays put, the backdrop follows the drag offset.
/// It fades rather than vanishes on drop, gliding into place with the rows.
struct SidebarNetworkLift: View {
    let id: UUID
    let controller: ReorderController<UUID>
    var surface: String = ThemeKey.sidebarBackground
    var cornerRadius: CGFloat

    var body: some View {
        SidebarLiftBackground(surface: surface, cornerRadius: cornerRadius)
            .offset(controller.offset(for: id))
            .opacity(controller.isDragging(id) ? 1 : 0)
            .allowsHitTesting(false)
    }
}

/// The vertical scroll view of the sidebar tree or rail, set up for
/// drag-to-reorder: its content carries the reorder coordinate space, and
/// dragging an item toward the top or bottom edge scrolls to reveal more.
struct SidebarReorderScrollView<Content: View>: View {
    let coordinateSpace: String
    /// Whether an item is being dragged.
    let isDragging: Bool
    /// Moves the dragged item; see `ReorderController.nudge(by:)`.
    let nudge: (CGFloat) -> CGFloat?
    let content: Content

    @State private var position = ScrollPosition()
    @State private var autoScroll = SidebarAutoScroll()

    init(
        coordinateSpace: String,
        isDragging: Bool,
        nudge: @escaping (CGFloat) -> CGFloat?,
        @ViewBuilder content: () -> Content
    ) {
        self.coordinateSpace = coordinateSpace
        self.isDragging = isDragging
        self.nudge = nudge
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .coordinateSpace(.named(coordinateSpace))
                // Only watches where the pointer is in the visible area; the
                // rows' own gestures do the dragging.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .scrollView)
                        .onChanged { value in
                            autoScroll.pointer = value.location.y
                            autoScroll.start = value.startLocation.y
                        }
                        .onEnded { _ in
                            autoScroll.pointer = nil
                            autoScroll.start = nil
                        }
                )
        }
        .scrollPosition($position)
        // Kept off the view's state: it changes on every scroll and is only
        // read while auto-scrolling.
        .onScrollGeometryChange(for: SidebarAutoScroll.Geometry.self, of: SidebarAutoScroll.Geometry.init) { _, geometry in
            autoScroll.geometry = geometry
        }
        .onChange(of: isDragging) { _, dragging in
            if dragging { startAutoScroll() } else { autoScroll.stop() }
        }
        .onDisappear { autoScroll.stop() }
    }

    private func startAutoScroll() {
        autoScroll.stop()
        autoScroll.task = Task {
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let elapsed = min(0.05, (now - last) / .seconds(1))
                last = now
                if Task.isCancelled || !autoScrollStep(elapsed: elapsed) { break }
            }
        }
    }

    /// Scrolls one step if the pointer is near an edge, moving the dragged
    /// item along so it stays under the pointer. Returns false once nothing
    /// is being dragged.
    private func autoScrollStep(elapsed: Double) -> Bool {
        guard let geometry = autoScroll.geometry, let pointer = autoScroll.pointer, let start = autoScroll.start else { return true }
        let speed = SidebarAutoScroll.speed(pointer: pointer, start: start, height: geometry.height)
        guard speed != 0 else { return true }
        let offset = min(max(geometry.offset + speed * elapsed, geometry.offsets.lowerBound), geometry.offsets.upperBound)
        guard abs(offset - geometry.offset) >= 0.5 else { return true }
        // The item can't go past its siblings, and there's no point
        // scrolling further than it can follow.
        guard let moved = nudge(offset - geometry.offset) else { return false }
        guard moved != 0 else { return true }
        autoScroll.geometry?.offset += moved
        position.scrollTo(y: geometry.offset + moved)
        return true
    }
}

/// Auto-scroll state of a `SidebarReorderScrollView`. Not observable: it
/// changes with every scroll and pointer move and never needs a redraw.
final class SidebarAutoScroll {
    /// The pointer's height in the visible area, and where it went down,
    /// while it's dragging.
    var pointer: CGFloat?
    var start: CGFloat?
    var geometry: Geometry?
    var task: Task<Void, Never>?

    func stop() {
        task?.cancel()
        task = nil
    }

    nonisolated struct Geometry: Equatable {
        var offset: CGFloat
        /// Height of the visible area.
        var height: CGFloat
        /// The offsets the content can scroll to.
        var offsets: ClosedRange<CGFloat>

        init(_ geometry: ScrollGeometry) {
            offset = geometry.contentOffset.y
            height = geometry.containerSize.height
            let top = -geometry.contentInsets.top
            offsets = top...max(top, geometry.contentSize.height + geometry.contentInsets.bottom - height)
        }
    }

    /// Height of the band along each edge that scrolls.
    nonisolated static let edgeBand: CGFloat = 36
    nonisolated static let speeds: ClosedRange<CGFloat> = 80...720

    /// Points per second to scroll by (negative is up) for a pointer
    /// `pointer` points down a visible area `height` tall, having gone down
    /// at `start`: nothing until it's in the band along an edge it has
    /// moved toward, so grabbing a row near an edge doesn't scroll at once;
    /// then faster the deeper it goes, at full speed past the edge.
    nonisolated static func speed(pointer: CGFloat, start: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0 else { return 0 }
        let band = min(edgeBand, height / 4)
        func ramp(_ depth: CGFloat) -> CGFloat {
            speeds.lowerBound + (speeds.upperBound - speeds.lowerBound) * min(1, depth / band)
        }
        if pointer < band, pointer < start { return -ramp(band - pointer) }
        if pointer > height - band, pointer > start { return ramp(pointer - (height - band)) }
        return 0
    }
}
