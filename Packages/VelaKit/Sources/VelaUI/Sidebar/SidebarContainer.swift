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
struct SidebarContainer: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var railHovering = false
    @State private var overlayHovering = false
    @State private var hoverTask: Task<Void, Never>?
    /// Something in the rail, or in the floating tree, is being dragged.
    @State private var railReordering = false
    @State private var overlayReordering = false

    var body: some View {
        let settings = app.settings
        let collapsed = settings[.sidebarCollapsed]
        let width = SidebarMetrics.clampedWidth(settings[.sidebarWidth])

        ZStack(alignment: .topLeading) {
            if collapsed {
                SidebarRailView(onReorderingChange: { railReordering = $0 })
                    .onHover { inside in
                        railHovering = inside
                        updateHoverExpansion()
                    }
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    SidebarTreeView()
                    PaneDivider(width: width, range: SidebarMetrics.widthRange, edge: .leading) { newWidth in
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
        .overlay(alignment: .topLeading) {
            if collapsed && uiState.isRailHoverExpanded {
                floatingTree(width: width)
            }
        }
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

    private func floatingTree(width: CGFloat) -> some View {
        SidebarTreeView(isFloating: true, onReorderingChange: { overlayReordering = $0 })
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
