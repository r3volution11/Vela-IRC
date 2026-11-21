// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// A horizontal, indicator-free scroller for a row of tabs. It keeps
/// `target` fully visible (clear of the edge fades, scrolling only when it
/// has to), fades the edges that have more tabs beyond them, and reports
/// whether the row overflows (to show the » menu) and how wide its content
/// is (so a row can size to its tabs). Mark each tab with `tabScrollID(_:)`.
///
/// With the row's `reorder` controller, a tab dragged against either edge
/// scrolls the row, and the selection doesn't scroll it mid-drag.
struct TabScroller<ID: Hashable, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let target: ID?
    let dragsWindow: Bool
    let reorder: ReorderController<ID>?
    @Binding var isOverflowing: Bool
    let onContentWidthChange: ((CGFloat) -> Void)?
    let content: Content

    @State private var scroll = ScrollState()
    @State private var position = ScrollPosition()
    @State private var frames = TabFrameStore()

    init(
        target: ID?,
        dragsWindow: Bool = false,
        reorder: ReorderController<ID>? = nil,
        isOverflowing: Binding<Bool>,
        onContentWidthChange: ((CGFloat) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.target = target
        self.dragsWindow = dragsWindow
        self.reorder = reorder
        _isOverflowing = isOverflowing
        self.onContentWidthChange = onContentWidthChange
        self.content = content()
    }

    private let fadeLength: CGFloat = 18
    /// How close a dragged tab gets to an edge before the row scrolls.
    private let autoScrollZone: CGFloat = 32
    /// Points per second with a dragged tab at (or past) the edge.
    private let autoScrollSpeed: CGFloat = 600

    var body: some View {
        ScrollView(.horizontal) {
            ZStack(alignment: .leading) {
                if dragsWindow {
                    // In the title bar, empty space after and between the
                    // tabs still drags the window (and offers Show Channel
                    // Title Bar): this fills the visible width behind
                    // them. Sized by layout rather than by the measured
                    // width, so the content never resizes in response to
                    // its own scroll geometry.
                    Color.clear
                        .containerRelativeFrame(.horizontal)
                        .contentShape(Rectangle())
                        .titleBarTabStripArea()
                }
                content
                    .environment(\.tabFrameStore, frames)
            }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollState.self) { geometry in
            ScrollState(
                offset: geometry.contentOffset.x,
                contentWidth: geometry.contentSize.width,
                containerWidth: geometry.containerSize.width
            )
        } action: { oldValue, newValue in
            scroll = newValue
            let resized = oldValue.containerWidth != newValue.containerWidth || oldValue.contentWidth != newValue.contentWidth
            // Geometry is reported during layout. Showing the » menu,
            // resizing the row and scrolling all change that layout, so they
            // wait for the next turn instead of re-running layout in this pass.
            Task { geometrySettled(resized: resized) }
        }
        .mask { edgeFade }
        .onChange(of: target) {
            revealTarget(animated: !reduceMotion)
        }
        .task(id: reorder?.dragged) {
            if let reorder, let dragged = reorder.dragged {
                await autoScroll(reorder, dragging: dragged)
            }
        }
        .task {
            // Once the first layout has recorded the tab frames.
            await Task.yield()
            revealTarget(animated: false)
        }
    }

    private func geometrySettled(resized: Bool) {
        if isOverflowing != scroll.overflows { isOverflowing = scroll.overflows }
        onContentWidthChange?(scroll.contentWidth)
        if resized { revealTarget(animated: false) }
    }

    /// Scrolls the least distance that brings the target clear of the fades.
    /// Not mid-drag: the dragged tab decides where the row scrolls.
    private func revealTarget(animated: Bool) {
        guard reorder?.isDragging != true,
              scroll.overflows, let target, let frame = frames.frames[AnyHashable(target)] else { return }
        let visible = fadeLength...(scroll.containerWidth - fadeLength)
        var delta: CGFloat = 0
        if frame.minX < visible.lowerBound {
            delta = frame.minX - visible.lowerBound
        } else if frame.maxX > visible.upperBound {
            // A tab wider than the view keeps its leading edge in view.
            delta = min(frame.maxX - visible.upperBound, frame.minX - visible.lowerBound)
        }
        guard abs(delta) > 0.5 else { return }
        let x = min(max(0, scroll.offset + delta), scroll.contentWidth - scroll.containerWidth)
        withAnimation(animated ? .snappy(duration: 0.25) : nil) {
            position.scrollTo(x: x)
        }
    }

    /// While tab `id` is dragged toward an edge it's near, scrolls that way,
    /// faster the further in it is, and carries the tab along so it stays
    /// under the pointer (the drag only reports pointer moves). Runs on its
    /// own clock, never from a geometry callback.
    private func autoScroll(_ reorder: ReorderController<ID>, dragging id: ID) async {
        guard let frame = frames.frames[AnyHashable(id)] else { return }
        // Frames are in visible coordinates; where the tab rests in the
        // content holds still while the row scrolls.
        let restingX = frame.minX + scroll.offset
        var offset = scroll.offset
        let clock = ContinuousClock()
        var last = clock.now
        var lastScrolled = last
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled, reorder.isDragging(id) else { return }
            let now = clock.now
            let elapsed = CGFloat(min((now - last) / .seconds(1), 0.05))
            last = now

            let limit = scroll.contentWidth - scroll.containerWidth
            let translation = reorder.translation
            let minX = restingX + translation - offset
            let maxX = minX + frame.width
            var speed: CGFloat = 0
            // Only toward the way it's being dragged, so picking up a tab
            // that rests near an edge doesn't scroll the row by itself.
            if translation < 0, minX < autoScrollZone {
                speed = -min(1, (autoScrollZone - minX) / autoScrollZone)
            } else if translation > 0, maxX > scroll.containerWidth - autoScrollZone {
                speed = min(1, (maxX - scroll.containerWidth + autoScrollZone) / autoScrollZone)
            }
            guard limit > 0.5, speed != 0 else {
                // Follow the row should something else scroll it, once our
                // own scrolling has shown up in its geometry.
                if now - lastScrolled > .milliseconds(150) { offset = scroll.offset }
                continue
            }
            let step = min(max(0, offset + speed * autoScrollSpeed * elapsed), limit) - offset
            guard abs(step) > 0.1 else { continue }
            // The tab stops at its group's ends; so does the scrolling.
            guard let moved = reorder.nudge(by: step), abs(moved) > 0.1 else { continue }
            let next = offset + moved
            offset = next
            lastScrolled = now
            position.scrollTo(x: next)
        }
    }

    /// Alpha mask; only the opacity of these colors matters.
    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: scroll.canScrollBackward ? fadeLength : 0)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: scroll.canScrollForward ? fadeLength : 0)
        }
        .animation(.easeOut(duration: 0.15), value: scroll.canScrollBackward)
        .animation(.easeOut(duration: 0.15), value: scroll.canScrollForward)
    }
}

extension View {
    /// Registers a tab's frame with the enclosing `TabScroller`, so it can be
    /// scrolled into view when selected.
    func tabScrollID(_ id: some Hashable) -> some View {
        modifier(TabScrollIDModifier(id: AnyHashable(id)))
    }
}

private struct TabScrollIDModifier: ViewModifier {
    @Environment(\.tabFrameStore) private var store
    let id: AnyHashable

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .scrollView)
        } action: { frame in
            store?.frames[id] = frame
        }
    }
}

/// Tab frames in the scroll view's visible coordinates. Deliberately not
/// observable: frames change on every scroll and only matter on selection.
final class TabFrameStore {
    var frames: [AnyHashable: CGRect] = [:]
}

extension EnvironmentValues {
    @Entry var tabFrameStore: TabFrameStore?
}

private struct ScrollState: Equatable {
    var offset: CGFloat = 0
    var contentWidth: CGFloat = 0
    var containerWidth: CGFloat = 0

    var overflows: Bool { contentWidth > containerWidth + 0.5 }
    var canScrollBackward: Bool { overflows && offset > 0.5 }
    var canScrollForward: Bool { overflows && offset + containerWidth < contentWidth - 0.5 }
}
