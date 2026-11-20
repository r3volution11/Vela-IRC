// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// The sidebar column shown when `navigation.style` is `sidebar`: the tree
/// (resizable via `sidebar.width`) or, when `sidebar.collapsed` is on, the
/// icon rail. Hovering the rail floats the full tree over the chat without
/// changing the layout.
///
/// It's the window's `.navigation` area: ⌥⌘1 or F6 give it the keyboard
/// focus, and the keys move through the tree or the rail alike
/// (`SidebarKeyboard`). The focus stays here as the tree and the rail swap.
struct SidebarContainer: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SidebarMetrics.collapsedNetworksKey) private var collapsedNetworks = NetworkIDSet()

    @State private var railHovering = false
    @State private var overlayHovering = false
    @State private var hoverTask: Task<Void, Never>?
    /// Something in the rail, or in the floating tree, is being dragged.
    @State private var railReordering = false
    @State private var overlayReordering = false
    /// The tree's width while its divider is dragged (see `PaneDivider`).
    @State private var dragWidth: Double?
    @State private var keyboard = SidebarKeyboardFocus()
    /// For drawing the ring on the row the keyboard is on.
    @State private var hasKeyboardFocus = false

    var body: some View {
        let settings = app.settings
        let collapsed = settings[.sidebarCollapsed]
        let width = SidebarMetrics.clampedWidth(dragWidth?.rounded() ?? settings[.sidebarWidth])

        ZStack(alignment: .topLeading) {
            if collapsed {
                SidebarRailView(hasKeyboardFocus: hasKeyboardFocus, onReorderingChange: { railReordering = $0 })
                    .onHover { inside in
                        railHovering = inside
                        updateHoverExpansion()
                    }
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    SidebarTreeView(hasKeyboardFocus: hasKeyboardFocus)
                    PaneDivider(width: width, range: SidebarMetrics.widthRange, edge: .leading, liveWidth: $dragWidth) { newWidth in
                        settings[.sidebarWidth] = newWidth.rounded()
                    }
                    .overlay {
                        // PaneDivider draws `pane.divider`; the sidebar's own edge token wins.
                        Rectangle()
                            .fill(theme[ThemeKey.sidebarBorder])
                            .frame(width: 1)
                            .allowsHitTesting(false)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: collapsed ? SidebarMetrics.railWidth : width + 1, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background {
            KeyboardFocusArea(handle: keyboard.handle, onFocusChange: keyboardFocusChanged, onKey: handleKey)
        }
        .onChange(of: uiState.focusRequest, initial: true) { _, request in
            guard request?.area == .navigation else { return }
            uiState.takeFocusRequest(for: .navigation)
            keyboard.handle.focus()
        }
        .overlay(alignment: .topLeading) {
            if collapsed && uiState.isRailHoverExpanded {
                floatingTree(width: width)
            }
        }
        .environment(\.sidebarKeyboardFocus, keyboard.handle)
        // Lets the floating tree (and the divider's grab area) sit above the chat.
        .zIndex(1)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: collapsed)
        .onChange(of: collapsed) {
            hoverTask?.cancel()
            railHovering = false
            overlayHovering = false
            railReordering = false
            overlayReordering = false
            uiState.isRailHoverExpanded = false
        }
        .onChange(of: railReordering) { _, dragging in
            // A rail drag that began just before the tree floated open
            // would carry on out of sight beneath it.
            if dragging && uiState.isRailHoverExpanded {
                overlayHovering = false
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) {
                    uiState.isRailHoverExpanded = false
                }
            }
            updateHoverExpansion()
        }
        .onChange(of: overlayReordering) {
            updateHoverExpansion()
        }
        .onDisappear {
            hoverTask?.cancel()
            uiState.isRailHoverExpanded = false
        }
    }

    // MARK: Keyboard

    /// Told at once, before a key can select another channel and bring in
    /// its message box, which then leaves the focus here.
    private func keyboardFocusChanged(_ focused: Bool) {
        uiState.setFocused(.navigation, focused)
        if focused {
            keyboard.typeSelect.reset()
            if let id = app.selectedBufferID { announce(id, prefix: "Sidebar") }
        }
        Task { @MainActor in hasKeyboardFocus = focused }
    }

    private func handleKey(_ key: NavigationKey, at time: TimeInterval) -> Bool {
        let collapsed = collapsedNetworks
        let rows = SidebarKeyboard.rows(in: app, collapsed: collapsed)
        let cursorID = SidebarKeyboard.cursor(selected: app.selectedBufferID, in: app, collapsed: collapsed)
        let cursor = cursorID.flatMap { id in rows.firstIndex { $0.id == id } }
        guard let action = SidebarKeyboard.action(
            for: key, rows: rows, cursor: cursor, collapsed: collapsed, typeSelect: &keyboard.typeSelect, time: time
        ) else { return false }
        switch action {
        case .select(let id):
            app.select(bufferID: id)
            announce(id)
        case .collapse(let id), .expand(let id):
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                collapsedNetworks.toggle(id)
            }
            KeyboardAnnouncement.post(collapsedNetworks.contains(id) ? "Collapsed" : "Expanded")
        case .focusMessageBox:
            uiState.focusInput()
        case .nothing:
            break
        }
        return true
    }

    /// Says the row VoiceOver would: "#vela, 3 unread".
    private func announce(_ id: BufferID, prefix: String? = nil) {
        guard let session = app.session(for: id.networkID), let buffer = session.buffer(id: id) else { return }
        let name: String
        let activity: BufferActivity
        switch buffer.kind {
        case .server:
            name = session.displayName
            activity = BufferActivity(headerOf: session, isCollapsed: collapsedNetworks.contains(session.id))
        case .channel:
            name = buffer.name
            activity = BufferActivity(buffer: buffer, session: session)
        case .query:
            name = "Conversation with \(buffer.name)"
            activity = BufferActivity(buffer: buffer, session: session)
        }
        KeyboardAnnouncement.post(([prefix, name, activity.accessibilityDescription].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: ", "))
    }

    private func floatingTree(width: CGFloat) -> some View {
        SidebarTreeView(isFloating: true, hasKeyboardFocus: hasKeyboardFocus, onReorderingChange: { overlayReordering = $0 })
            .frame(width: max(width, 180))
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme[ThemeKey.sidebarBorder]).frame(width: 1)
            }
            .compositingGroup()
            .shadow(radius: 1, x: 0.5)
            .shadow(radius: 18, x: 6)
            .onHover { inside in
                overlayHovering = inside
                updateHoverExpansion()
            }
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .leading).combined(with: .opacity)
            )
    }

    /// Expands after the pointer rests on the rail; collapses shortly after it
    /// leaves both the rail and the floating tree. Holds still while an item
    /// is dragged in either (the pointer may wander off the floating tree
    /// mid-drag), then catches up when the drag ends.
    private func updateHoverExpansion() {
        hoverTask?.cancel()
        guard !railReordering, !overlayReordering else { return }
        let expanded = uiState.isRailHoverExpanded
        let pointerInside = railHovering || overlayHovering
        guard expanded != pointerInside else { return }
        let delay = pointerInside ? SidebarMetrics.hoverExpandDelay : SidebarMetrics.hoverCollapseDelay
        hoverTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, app.settings[.sidebarCollapsed] else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) {
                uiState.isRailHoverExpanded = pointerInside
            }
        }
    }
}

/// The sidebar's keyboard focus and what's been typed to select. Not
/// observed: only key handlers read it.
@MainActor
final class SidebarKeyboardFocus {
    let handle = KeyboardFocusHandle()
    var typeSelect = TypeSelect()
}
