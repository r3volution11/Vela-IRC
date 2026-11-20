// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import SwiftUI

// Drag-to-reorder for lists and tab rows that aren't SwiftUI `List`s.
//
// The dragged item follows the pointer along one axis, its siblings slide
// aside to open a gap where it would land, and letting go commits the move
// and settles everything into place. Escape cancels. Items only move among
// their siblings (a network's channels, the top-level networks…), which the
// container passes in.
//
// An item can be more than one view: a sidebar network section is its
// header plus its channel rows. Mark the view that starts drags with
// `reorderable(_:…)` and the others with `reorderPart(of:…)`; they all move
// together and the item's frame is the union of theirs. `reorderHandle(_:…)`
// is the drag gesture alone, for items whose views move some other way.
//
// The drag gesture takes priority over the clicks of the view it's on (a
// tab is a Button, rows have tap gestures), and only starts after a few
// points of movement, so a click still clicks and a drag never does. Since
// it outranks everything inside it, handles must not contain other handles.

/// Where a dragged item would land and how far its siblings shift, along
/// one axis. Pure geometry, so it can be tested without views.
struct ReorderLayout<ID: Hashable> {
    /// Siblings in display order.
    var ids: [ID]
    /// Each sibling's span along the axis, in one coordinate space.
    /// Siblings without one (not laid out yet) stay where they are.
    var spans: [ID: ClosedRange<CGFloat>]

    /// The index among `ids` that `dragged` would land at after moving by
    /// `translation`: past every sibling whose middle its leading edge
    /// (moving back) or trailing edge (moving on) has crossed, as browser
    /// tabs do. Going by its edges rather than its middle, an item wider
    /// than the one at either end still gets past it, held at the ends by
    /// `clampedTranslation`.
    func proposedIndex(for dragged: ID, translation: CGFloat) -> Int? {
        guard let from = ids.firstIndex(of: dragged), let span = spans[dragged] else { return nil }
        let leading = span.lowerBound + translation
        let trailing = span.upperBound + translation
        var index = 0
        for (position, id) in ids.enumerated() where id != dragged {
            let before: Bool
            if let other = spans[id] {
                let middle = (other.lowerBound + other.upperBound) / 2
                before = position < from ? leading > middle : trailing > middle
            } else {
                before = position < from
            }
            if before { index += 1 }
        }
        return index
    }

    /// How far sibling `id` shifts while `dragged` is proposed at `target`:
    /// the dragged item's length plus the gap after it, toward the slot it left.
    func offset(of id: ID, dragging dragged: ID, to target: Int) -> CGFloat {
        guard id != dragged,
              let from = ids.firstIndex(of: dragged),
              let index = ids.firstIndex(of: id) else { return 0 }
        if from < target, index > from, index <= target { return -stride(of: dragged) }
        if target < from, index >= target, index < from { return stride(of: dragged) }
        return 0
    }

    /// How far `dragged` must move from its slot to sit exactly where the
    /// move to `target` puts it: against the far edge of the last sibling
    /// it passes. Nil when that sibling hasn't been laid out.
    func finalOffset(of dragged: ID, to target: Int) -> CGFloat? {
        guard let from = ids.firstIndex(of: dragged), let span = spans[dragged],
              ids.indices.contains(target), target != from,
              let passed = spans[ids[target]] else { return nil }
        return from < target ? passed.upperBound - span.upperBound : passed.lowerBound - span.lowerBound
    }

    /// Keeps the dragged item within the siblings' overall span.
    func clampedTranslation(_ translation: CGFloat, for dragged: ID) -> CGFloat {
        guard let span = spans[dragged] else { return translation }
        let known = ids.compactMap { spans[$0] }
        guard let first = known.map(\.lowerBound).min(), let last = known.map(\.upperBound).max() else { return translation }
        return min(max(translation, first - span.lowerBound), last - span.upperBound)
    }

    /// The dragged item's length plus the spacing that follows it.
    private func stride(of dragged: ID) -> CGFloat {
        guard let index = ids.firstIndex(of: dragged), let span = spans[dragged] else { return 0 }
        let length = span.upperBound - span.lowerBound
        if index + 1 < ids.count, let next = spans[ids[index + 1]] {
            return length + max(0, next.lowerBound - span.upperBound)
        }
        if index > 0, let previous = spans[ids[index - 1]] {
            return length + max(0, span.lowerBound - previous.upperBound)
        }
        return length
    }
}

/// Drag state for one container (the sidebar, a tab row…). One drag at a
/// time; siblings are passed in when it starts.
@MainActor
@Observable
final class ReorderController<ID: Hashable> {
    let axis: Axis
    /// The coordinate space frames and drags are measured in. Attach it
    /// with `.coordinateSpace(.named(controller.coordinateSpace))` to the
    /// content that scrolls, so frames don't change as it scrolls.
    let coordinateSpace: String

    /// The item held by the pointer (drawn lifted).
    private(set) var dragged: ID?
    /// The item drawn away from its slot: the dragged one, then, once it's
    /// let go, the one gliding into its new slot.
    private(set) var moving: ID?
    private(set) var translation: CGFloat = 0
    private(set) var target: Int?

    /// Frames of every registered view, by item and part.
    @ObservationIgnored private var partFrames: [ID: [String: CGRect]] = [:]
    @ObservationIgnored private var layout: ReorderLayout<ID>?
    /// Escape cancelled the drag; its gesture is still going and is ignored
    /// until it ends, or until a new gesture (a different start) begins.
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var gestureStart: CGPoint?
    @ObservationIgnored private var keyMonitor: Any?
    /// The move to make once the dropped item has glided into its slot.
    @ObservationIgnored private var pendingMove: (() -> Void)?

    init(axis: Axis, coordinateSpace: String) {
        self.axis = axis
        self.coordinateSpace = coordinateSpace
    }

    isolated deinit {
        removeEscapeMonitor()
    }

    private func animation(_ animation: Animation, reduceMotion: Bool = false) -> Animation? {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
    }

    var isDragging: Bool { dragged != nil }

    func isDragging(_ id: ID) -> Bool { dragged == id }

    /// Whether `id` is drawn away from its slot (dragged or settling); it
    /// should draw above its siblings.
    func isMoving(_ id: ID) -> Bool { moving == id }

    /// The offset to draw item `id`'s views at.
    func offset(for id: ID) -> CGSize {
        guard let moving, let layout else { return .zero }
        let distance: CGFloat
        if id == moving {
            distance = translation
        } else if let target {
            distance = layout.offset(of: id, dragging: moving, to: target)
        } else {
            distance = 0
        }
        return axis == .vertical ? CGSize(width: 0, height: distance) : CGSize(width: distance, height: 0)
    }

    // MARK: Frames

    func setFrame(_ frame: CGRect, of id: ID, part: String) {
        partFrames[id, default: [:]][part] = frame
    }

    func removeFrame(of id: ID, part: String) {
        partFrames[id]?[part] = nil
        if partFrames[id]?.isEmpty == true { partFrames[id] = nil }
    }

    private func span(of id: ID) -> ClosedRange<CGFloat>? {
        guard let frames = partFrames[id]?.values, let first = frames.first else { return nil }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        return axis == .vertical ? union.minY...union.maxY : union.minX...union.maxX
    }

    // MARK: Dragging

    /// Starts or continues dragging `id` among `siblings`. `start` (the
    /// gesture's start location) tells a new gesture from the rest of one
    /// that was cancelled.
    func update(_ id: ID, siblings: [ID], translation size: CGSize, start: CGPoint? = nil) {
        if cancelled {
            // The cancelled gesture's end never came (its view went away):
            // a gesture that starts elsewhere is a new drag.
            guard let start, start != gestureStart else { return }
            cancelled = false
        }
        if dragged != id {
            guard siblings.count > 1, siblings.contains(id) else { return }
            // Grabbed again before the last drop finished settling.
            finishPendingMove()
            var spans: [ID: ClosedRange<CGFloat>] = [:]
            for sibling in siblings { spans[sibling] = span(of: sibling) }
            layout = ReorderLayout(ids: siblings, spans: spans)
            dragged = id
            moving = id
            gestureStart = start
            installEscapeMonitor()
        }
        move(to: axis == .vertical ? size.height : size.width)
    }

    /// Moves the dragged item `distance` further along the axis, as if the
    /// pointer had moved: for auto-scrolling under a pointer that holds
    /// still. Returns how far it went (it stops at its siblings' ends), or
    /// nil when nothing is being dragged.
    @discardableResult
    func nudge(by distance: CGFloat) -> CGFloat? {
        guard dragged != nil, !cancelled else { return nil }
        let before = translation
        move(to: before + distance)
        return translation - before
    }

    private func move(to raw: CGFloat) {
        guard let dragged, let layout else { return }
        translation = layout.clampedTranslation(raw, for: dragged)
        let proposed = layout.proposedIndex(for: dragged, translation: translation)
        if proposed != target {
            withAnimation(animation(.snappy(duration: 0.2))) { target = proposed }
        }
    }

    /// Ends the drag. Unless it was cancelled or went nowhere, `commit`
    /// receives the item and its new index among its siblings and should
    /// move it in the model.
    ///
    /// The drop happens in two steps, so nothing moves in two ways at once.
    /// First the item glides into the slot it's moving to by its offset
    /// alone (its siblings already sit in theirs). Then the model moves it,
    /// with animations off: the new layout puts every view exactly where
    /// it's already drawn, and the offsets go back to zero unseen. Moving
    /// the model while animating the offsets back makes SwiftUI animate the
    /// new layout but not the offsets, and the item wobbles into place.
    func end(reduceMotion: Bool = false, commit: @escaping (ID, Int) -> Void) {
        defer { cancelled = false }
        guard let dragged else { return }
        removeEscapeMonitor()
        let settle = animation(.smooth(duration: 0.22), reduceMotion: reduceMotion)
        guard !cancelled, let layout, let from = layout.ids.firstIndex(of: dragged), let to = target, from != to else {
            withAnimation(settle) { reset() }
            return
        }
        guard let settle, let final = layout.finalOffset(of: dragged, to: to) else {
            withAnimation(settle) {
                commit(dragged, to)
                reset()
            }
            return
        }
        pendingMove = { commit(dragged, to) }
        withAnimation(settle, completionCriteria: .logicallyComplete) {
            self.dragged = nil
            translation = final
        } completion: { [weak self] in
            self?.finishPendingMove()
        }
    }

    /// Makes the move a drop is settling into, with animations off (see
    /// `end(reduceMotion:commit:)`).
    private func finishPendingMove() {
        guard let move = pendingMove else { return }
        pendingMove = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            move()
            reset()
        }
    }

    /// Cancels the drag (Escape): everything slides back, and the rest of
    /// the gesture is ignored.
    func cancel() {
        guard dragged != nil else { return }
        cancelled = true
        withAnimation(animation(.smooth(duration: 0.22))) { reset() }
    }

    /// Ends the drag without moving anything, when its gesture can't end
    /// it: the dragged view went away, or the items changed under it. A
    /// drop that's settling is completed instead; it was let go.
    func abandon() {
        if pendingMove != nil {
            finishPendingMove()
            return
        }
        guard dragged != nil || cancelled else { return }
        cancelled = false
        withAnimation(animation(.smooth(duration: 0.22))) { reset() }
    }

    private func reset() {
        dragged = nil
        moving = nil
        translation = 0
        target = nil
        layout = nil
        removeEscapeMonitor()
    }

    private func installEscapeMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Escape
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.dragged != nil else { return false }
                self.cancel()
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeEscapeMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

extension View {
    /// Lets this view be dragged to reorder item `id` among `siblings`.
    /// `onMove` receives the item and its new index among `siblings`
    /// (after removal, so `0..<siblings.count`). Clicks still reach the
    /// view; a drag starts after a few points of movement.
    func reorderable<ID: Hashable>(
        _ id: ID,
        siblings: [ID],
        in controller: ReorderController<ID>,
        isEnabled: Bool = true,
        onMove: @escaping (ID, Int) -> Void
    ) -> some View {
        // The part goes outside the handle: its z-index only reaches the
        // container from the outermost modifier.
        reorderHandle(id, siblings: siblings, in: controller, isEnabled: isEnabled, onMove: onMove)
            .reorderPart(of: id, in: controller, part: "handle")
    }

    /// `reorderable(_:…)`'s drag gesture without its movement, for an item
    /// whose views are moved with `reorderPart(of:…)` (a tab whose close
    /// button shouldn't start drags, a network whose row is part of a
    /// larger block). Disabled, it still claims drags, so they don't fall
    /// through to anything behind it.
    func reorderHandle<ID: Hashable>(
        _ id: ID,
        siblings: [ID],
        in controller: ReorderController<ID>,
        isEnabled: Bool = true,
        onMove: @escaping (ID, Int) -> Void
    ) -> some View {
        modifier(ReorderHandleModifier(id: id, siblings: siblings, controller: controller, isEnabled: isEnabled, onMove: onMove))
    }

    /// Makes this view part of item `id`: it moves with the item and counts
    /// toward its frame (a network section's channel rows, say). Its
    /// z-index (the moving item draws above its siblings) only reaches the
    /// container when nothing else wraps it, so apply it last.
    func reorderPart<ID: Hashable>(of id: ID, in controller: ReorderController<ID>, part: String) -> some View {
        modifier(ReorderPartModifier(id: id, controller: controller, part: part))
    }

    /// "Move Up/Down" (or "Left/Right") accessibility actions: drag and drop
    /// for VoiceOver and Full Keyboard Access. `move` gets −1 or +1.
    func accessibilityMoveActions(axis: Axis, index: Int, count: Int, move: @escaping (Int) -> Void) -> some View {
        modifier(AccessibilityMoveActions(axis: axis, index: index, count: count, move: move))
    }
}

private struct ReorderHandleModifier<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: ID
    let siblings: [ID]
    let controller: ReorderController<ID>
    let isEnabled: Bool
    let onMove: (ID, Int) -> Void

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(controller.coordinateSpace))
                    .onChanged { value in
                        guard isEnabled else { return }
                        controller.update(id, siblings: siblings, translation: value.translation, start: value.startLocation)
                    }
                    .onEnded { _ in
                        controller.end(reduceMotion: reduceMotion, commit: onMove)
                    }
            )
            // Its gesture won't report an end once it's gone, which would
            // leave the controller dragging (and holding on to Escape).
            .onDisappear {
                if controller.isMoving(id) { controller.abandon() }
            }
    }
}

private struct ReorderPartModifier<ID: Hashable>: ViewModifier {
    let id: ID
    let controller: ReorderController<ID>
    let part: String

    func body(content: Content) -> some View {
        let space = controller.coordinateSpace
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(space))
            } action: { frame in
                controller.setFrame(frame, of: id, part: part)
            }
            .onDisappear { controller.removeFrame(of: id, part: part) }
            .offset(controller.offset(for: id))
            .zIndex(controller.isMoving(id) ? 1 : 0)
    }
}

private struct AccessibilityMoveActions: ViewModifier {
    let axis: Axis
    let index: Int
    let count: Int
    let move: (Int) -> Void

    func body(content: Content) -> some View {
        // Only the moves that are possible, so VoiceOver doesn't list dead actions.
        content
            .accessibilityActions {
                if index > 0 {
                    Button(axis == .vertical ? "Move Up" : "Move Left") { move(-1) }
                }
                if index < count - 1 {
                    Button(axis == .vertical ? "Move Down" : "Move Right") { move(1) }
                }
            }
    }
}
