// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import SwiftUI
import VelaCore
import VelaIRC
import VelaStore

/// Identifies a tab in either row.
enum TabKey: Hashable {
    case buffer(BufferID)
    case network(UUID)

    var bufferID: BufferID? {
        if case .buffer(let id) = self { id } else { nil }
    }

    var networkID: UUID? {
        if case .network(let id) = self { id } else { nil }
    }
}

/// A row of tabs, for the keyboard.
enum TabKeyboardRow: Equatable {
    case networks
    case channels
}

/// Hover state shared by both rows (for separators and hover fills) and
/// middle-click-to-close, which SwiftUI has no gesture for. Pointing at a
/// tab's close slot is the slot's own state (`TabCloseSlot`), not this.
///
/// Also the tabs' keyboard focus (⌥⌘1, F6): the row the keyboard is on,
/// whose selected tab gets the focus ring, and the view that has the focus
/// (`TabStackView`).
@Observable
final class TabInteraction {
    var hovered: TabKey?
    /// The row whose selected tab has the focus ring, while the tabs have
    /// the keyboard focus. Drawn from; keys go by `activeKeyboardRow`.
    var keyboardRow: TabKeyboardRow?

    /// Where the stack is, for which way ↑ and ↓ go.
    let placement: TabStackPlacement
    let keyboardFocus = KeyboardFocusHandle()
    /// The row the keyboard is on, at once (`keyboardRow` follows after
    /// the update a focus change can come in the middle of).
    @ObservationIgnored var activeKeyboardRow: TabKeyboardRow = .channels
    /// The row to put the keyboard on when the tabs next take the focus.
    @ObservationIgnored var nextKeyboardRow: TabKeyboardRow?

    init(placement: TabStackPlacement = .top) {
        self.placement = placement
    }
    /// Rows with a tab button focused from the keyboard (Tab with Keyboard
    /// navigation on in System Settings): they count as the tabs having
    /// the focus too.
    @ObservationIgnored private var rowsWithFocusedButton: Set<TabKeyboardRow> = []

    /// The tabs have the keyboard focus, one way or the other.
    var hasKeyboardFocus: Bool { keyboardFocus.hasFocus || !rowsWithFocusedButton.isEmpty }

    /// A tab button in `row` gained or lost the focus.
    func setButtonFocused(_ focused: Bool, in row: TabKeyboardRow) {
        if focused { rowsWithFocusedButton.insert(row) } else { rowsWithFocusedButton.remove(row) }
    }

    /// A tab clicked (or pressed with Space or VoiceOver): the focus goes
    /// to the new message box, as after any click on a tab, rather than
    /// staying with the keyboard in the tabs. Call it before selecting.
    func yieldToClick(_ uiState: UIState) {
        keyboardFocus.yieldToClick(uiState)
        if !rowsWithFocusedButton.isEmpty { uiState.setFocused(.navigation, false) }
    }

    /// ↑ or ↓ on a focused tab button: the keyboard goes on from the tabs'
    /// own focus, to `row`.
    func moveKeyboard(to row: TabKeyboardRow) {
        nextKeyboardRow = row
        keyboardFocus.focus()
    }

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var middleClickHandler: ((TabKey) -> Bool)?

    func setHovering(_ hovering: Bool, _ key: TabKey) {
        if hovering {
            hovered = key
        } else if hovered == key {
            hovered = nil
        }
    }

    /// Calls `handler` with the hovered tab when the middle button is released
    /// over it. The click is swallowed only when `handler` returns true.
    func installMiddleClickMonitor(_ handler: @escaping (TabKey) -> Bool) {
        removeMiddleClickMonitor()
        middleClickHandler = handler
        monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self else { return event }
            return handleOtherMouseUp(event)
        }
    }

    /// The monitor's decision: nil (swallowed) for a middle-click the
    /// handler took, else the event, to go on as usual.
    func handleOtherMouseUp(_ event: NSEvent) -> NSEvent? {
        guard event.type == .otherMouseUp, event.buttonNumber == 2,
              let key = hovered, let middleClickHandler else { return event }
        return middleClickHandler(key) ? nil : event
    }

    func removeMiddleClickMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        middleClickHandler = nil
    }
}

/// Actions shared by tabs, menus and shortcuts.
enum TabActions {
    /// Selects the buffer you were last on in the network, so a server tab
    /// returns to where you were (like a Vivaldi stack remembering its
    /// active tab).
    static func select(_ session: NetworkSession, app: AppModel) {
        app.select(app.lastSelectedBuffer(in: session))
    }

    /// A tab's ×: removes a channel (asking first, by default), or, through
    /// a bouncer, leaves it on the bouncer, detached, and hides it once it's
    /// detached (see `ChannelActions.closeAction`); closes a conversation. A
    /// removed or hidden channel or closed conversation's tab goes; if it
    /// was selected, its right neighbor (or left, at the end) is selected,
    /// like a browser.
    static func close(_ buffer: BufferModel, app: AppModel, uiState: UIState) {
        ChannelActions.closeTab(buffer, app: app, uiState: uiState)
    }

    /// A middle-click on tab `key`: does what its × does and returns true.
    /// Networks and server consoles don't close (false).
    static func middleClick(_ key: TabKey, app: AppModel, uiState: UIState) -> Bool {
        guard case .buffer(let id) = key,
              let session = app.session(for: id.networkID),
              let buffer = session.buffer(id: id),
              buffer.kind != .server else { return false }
        close(buffer, app: app, uiState: uiState)
        return true
    }

    /// Tabs reachable with ⌘1…⌘9: the network's channels, then queries.
    /// The console has no number, so ⌘1 is the first channel.
    static func shortcutTargets(in session: NetworkSession?) -> [BufferModel] {
        guard let session, !session.isBouncerControl else { return [] }
        return session.buffers
    }

    /// The network whose channels the tab stack shows: the selected one, or
    /// the first.
    static func shownSession(app: AppModel) -> NetworkSession? {
        app.selectedSession ?? app.sessions.first
    }

    /// The channel row's tabs: the server console, then channels, then
    /// queries (bouncer control connections only have their console).
    static func tabs(of session: NetworkSession) -> [BufferModel] {
        session.isBouncerControl ? [session.serverBuffer] + session.buffers : session.allBuffers
    }

    /// ←, →, Home or End from tab `index` of `count`: the tab to go to (they
    /// stop at the ends, as in a tab view), or nil for another key.
    static func keyboardTarget(_ key: NavigationKey, from index: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        switch key {
        case .left: return index.map { max(0, $0 - 1) } ?? count - 1
        case .right: return index.map { min(count - 1, $0 + 1) } ?? 0
        case .home: return 0
        case .end: return count - 1
        default: return nil
        }
    }

    /// ↑ or ↓ from `row`: the other row, in the order they're shown (the
    /// networks above the channels, except at the bottom of the window),
    /// or `row` at the edge or when there's one row.
    static func keyboardRow(after row: TabKeyboardRow, up: Bool, showsNetworks: Bool, placement: TabStackPlacement) -> TabKeyboardRow {
        guard showsNetworks else { return .channels }
        let order: [TabKeyboardRow] = placement == .bottom ? [.channels, .networks] : [.networks, .channels]
        let index = order.firstIndex(of: row) ?? 1
        return order[up ? max(0, index - 1) : min(order.count - 1, index + 1)]
    }

    /// ⌘`number`: selects the shown network's `number`th channel or
    /// conversation, as the tabs are now. False if there's none.
    @discardableResult
    static func selectShortcutTarget(_ number: Int, app: AppModel) -> Bool {
        let targets = shortcutTargets(in: shownSession(app: app))
        guard targets.indices.contains(number - 1) else { return false }
        app.select(targets[number - 1])
        return true
    }
}

/// VoiceOver and tooltip text.
enum TabDescriptions {
    static func activity(unread: Int, highlights: Int) -> [String] {
        var parts: [String] = []
        if highlights > 0 { parts.append(highlights == 1 ? "1 mention" : "\(highlights) mentions") }
        if unread > 0 { parts.append("\(unread) unread") }
        return parts
    }

    static func connection(_ state: IRCConnectionState) -> String {
        switch state {
        case .connected: "Connected"
        case .connecting, .registering: "Connecting"
        case .disconnected: "Disconnected"
        }
    }

    static func bufferValue(_ buffer: BufferModel, in session: NetworkSession) -> String {
        var parts = activity(unread: buffer.isMuted ? 0 : buffer.unreadCount, highlights: buffer.highlightCount)
        if buffer.isMuted { parts.append("muted") }
        if buffer.kind == .channel && !buffer.isJoined { parts.append(buffer.isDetached ? "detached" : "not joined") }
        if !session.isConnected { parts.append(connection(session.connectionState).lowercased()) }
        return parts.joined(separator: ", ")
    }

    /// The VoiceOver action and tooltip for what a channel or query tab's ×
    /// does, there whether or not the pointer is on the tab: "Remove
    /// Channel", "Leave Channel" (through a bouncer), "Hide Channel" or
    /// "Close Conversation".
    static func closeAction(_ buffer: BufferModel, in session: NetworkSession, app: AppModel) -> String {
        ChannelActions.closeAction(for: buffer, in: session, app: app)?.title ?? "Close"
    }

    static func bufferKind(_ buffer: BufferModel) -> String {
        switch buffer.kind {
        case .server: "Server console"
        case .channel: "Channel"
        case .query: "Conversation"
        }
    }

    /// What VoiceOver says for a tab the keyboard moves to, as it reads the
    /// tab: "#vela, 3 unread".
    static func spoken(_ buffer: BufferModel, in session: NetworkSession) -> String {
        let name = buffer.kind == .server ? "\(session.displayName) server console" : BufferTitle.title(for: buffer, in: session)
        return [name, bufferValue(buffer, in: session)].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: Reordering

/// A tab's part in drag-to-reorder (see `Reordering.swift`).
///
/// A tab is dragged by its label, not by everything drawn over it: the
/// label carries `tabDragHandle(_:)`, so a drag can't start on the close
/// slot, while the row moves the whole tab with `tabReorderItem(_:)`.
struct TabReorder<ID: Hashable> {
    let controller: ReorderController<ID>
    let id: ID
    /// The items it moves among, in order.
    let siblings: [ID]
    /// The item it also moves with: a bouncer's networks move with their bouncer.
    var group: ID?
    var isEnabled = true
    /// The item dragged last, which stays above its neighbors after it's
    /// let go, so it settles into its slot over them rather than under.
    var lastDragged: ID?
    /// Moves it to an index among `siblings`.
    let move: (Int) -> Void

    var index: Int { siblings.firstIndex(of: id) ?? 0 }

    /// Whether it's being dragged, by itself or with its group.
    var isLifted: Bool {
        controller.isDragging(id) || group.map { controller.isDragging($0) } == true
    }

    var isRaised: Bool {
        isLifted || (lastDragged != nil && (lastDragged == id || lastDragged == group))
    }
}

extension View {
    /// Starts drags of `reorder`'s tab from this view. Nil: not draggable.
    @ViewBuilder
    func tabDragHandle<ID: Hashable>(_ reorder: TabReorder<ID>?) -> some View {
        if let reorder {
            reorderHandle(reorder.id, siblings: reorder.siblings, in: reorder.controller, isEnabled: reorder.isEnabled) { _, index in
                reorder.move(index)
            }
        } else {
            self
        }
    }

    /// Moves this whole tab with its item (and its group's), above the other
    /// tabs while lifted. Nil: the tab stays put.
    @ViewBuilder
    func tabReorderItem<ID: Hashable>(_ reorder: TabReorder<ID>?) -> some View {
        if let reorder {
            // Each part sets its own z-index and only one would reach the
            // row, so they're kept in a stack of their own and this decides.
            ZStack {
                let item = reorderPart(of: reorder.id, in: reorder.controller, part: "tab")
                if let group = reorder.group {
                    item.reorderPart(of: group, in: reorder.controller, part: "member-\(reorder.id)")
                } else {
                    item
                }
            }
        } else {
            self
        }
    }

    /// Move Left / Move Right, drag and drop for VoiceOver and Full Keyboard
    /// Access. Nil: none.
    @ViewBuilder
    func tabMoveActions<ID: Hashable>(_ reorder: TabReorder<ID>?) -> some View {
        if let reorder, reorder.isEnabled {
            accessibilityMoveActions(axis: .horizontal, index: reorder.index, count: reorder.siblings.count) { offset in
                reorder.move(reorder.index + offset)
            }
        } else {
            self
        }
    }
}

/// Tab order as drawn mid-drag, for the separators between tabs.
enum TabDrawOrder {
    /// `ids` as drawn while `dragged` is shown at `target` among `siblings`.
    /// `owner` maps each tab to the sibling it moves with (itself, or the
    /// bouncer of a bouncer's network), nil for tabs the drag leaves alone.
    /// The tabs a drag moves are contiguous: one kind of buffer, one level
    /// of networks.
    static func order<ID: Hashable>(
        _ ids: [ID],
        siblings: [ID],
        dragged: ID,
        target: Int,
        owner: (ID) -> ID?
    ) -> [ID] {
        guard let from = siblings.firstIndex(of: dragged),
              let start = ids.firstIndex(where: { owner($0) != nil }) else { return ids }
        var items = siblings
        items.remove(at: from)
        items.insert(dragged, at: min(max(0, target), items.count))
        var blocks: [ID: [ID]] = [:]
        for id in ids {
            if let item = owner(id) { blocks[item, default: []].append(id) }
        }
        var result = ids.filter { owner($0) == nil }
        result.insert(contentsOf: items.flatMap { blocks[$0] ?? [] }, at: min(start, result.count))
        return result
    }

    /// The tabs drawn with a separator after them: each one followed by
    /// another, both plain (not selected, hovered or dragged).
    static func separated<ID: Hashable>(_ order: [ID], isPlain: (ID) -> Bool) -> Set<ID> {
        var result: Set<ID> = []
        for (tab, next) in zip(order, order.dropFirst()) where isPlain(tab) && isPlain(next) {
            result.insert(tab)
        }
        return result
    }
}

/// Hidden ⌘1…⌘9 buttons in the main window, for tabs and the sidebar alike:
/// the selected network's channels, then its conversations.
///
/// Each press looks up its tab when it's pressed. SwiftUI keeps calling the
/// action a shortcut button had when its shortcut was registered, so tabs
/// captured when the view was drawn went stale as channels were joined,
/// closed and moved (⌘6 kept going to what used to be the sixth tab).
struct TabShortcutButtons: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState

    var body: some View {
        ZStack {
            ForEach(1...9, id: \.self) { number in
                Button("Select Tab \(number)") { [app, uiState] in
                    if TabActions.selectShortcutTarget(number, app: app) { uiState.focusInput() }
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
