// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// A horizontal, indicator-free scroller for a row of tabs. It keeps
/// `target` fully visible (clear of the edge fades, scrolling only when it
/// has to), fades the edges that have more tabs beyond them, and reports
/// whether the row overflows (to show the » menu) and how wide its content
/// is (so a row can size to its tabs). Mark each tab with `tabScrollID(_:)`.
struct TabScroller<ID: Hashable, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let target: ID?
    let dragsWindow: Bool
    @Binding var isOverflowing: Bool
    let onContentWidthChange: ((CGFloat) -> Void)?
    let content: Content

    @State private var scroll = ScrollState()
    @State private var position = ScrollPosition()
    @State private var frames = TabFrameStore()

    init(
        target: ID?,
        dragsWindow: Bool = false,
        isOverflowing: Binding<Bool>,
        onContentWidthChange: ((CGFloat) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.target = target
        self.dragsWindow = dragsWindow
        _isOverflowing = isOverflowing
        self.onContentWidthChange = onContentWidthChange
        self.content = content()
    }

    private let fadeLength: CGFloat = 18

    var body: some View {
        ScrollView(.horizontal) {
            content
                .environment(\.tabFrameStore, frames)
                // In the title bar, empty space after the tabs still drags the window.
                .frame(minWidth: dragsWindow ? scroll.containerWidth : nil, alignment: .leading)
                .background {
                    if dragsWindow {
                        Color.clear
                            .contentShape(Rectangle())
                            .windowTitleBarArea()
                            .allowsWindowActivationEvents(true)
                    }
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
            if isOverflowing != newValue.overflows { isOverflowing = newValue.overflows }
            onContentWidthChange?(newValue.contentWidth)
            if oldValue.containerWidth != newValue.containerWidth || oldValue.contentWidth != newValue.contentWidth {
                revealTarget(animated: false)
            }
        }
        .mask { edgeFade }
        .onChange(of: target) {
            revealTarget(animated: !reduceMotion)
        }
        .task {
            // Once the first layout has recorded the tab frames.
            await Task.yield()
            revealTarget(animated: false)
        }
    }

    /// Scrolls the least distance that brings the target clear of the fades.
    private func revealTarget(animated: Bool) {
        guard scroll.overflows, let target, let frame = frames.frames[AnyHashable(target)] else { return }
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
