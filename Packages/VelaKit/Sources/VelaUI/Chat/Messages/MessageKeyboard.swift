// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaTheme

// The messages from the keyboard (the `.messages` focus area, ⌥⌘2 or F6).
//
// An AppKit view behind the list (`MessageKeyView`) takes the focus when
// it's asked to, reports it, and turns keys into commands
// (`MessageKeyCommand`). The selected row lives in the list's controller
// (`MessageListController.selection`). Only the list reads it, and it
// tells that one row (`DisplayItemRow.selection`), so moving the selection
// runs the list's body once and two rows', never every row's, and costs
// nothing while scrolling. The selected row puts a small view behind
// itself (`SelectedRowAnchor`) that says where menus open and how far in
// view it is.
//
// What the keys do reuses what the mouse does: the controller's Reply and
// Copy Text, the hover toolbar's reaction picker, the row's own context
// menu, the user menu a nick opens, the menu's Translate.

// MARK: Keys

/// What a key does in the messages.
nonisolated enum MessageKeyCommand: Equatable, Sendable {
    /// ↑ / ↓: the previous or next message.
    case previous, next
    /// Page Up / Page Down: a page of messages back or on.
    case pageUp, pageDown
    /// Home / End: the first or last message loaded.
    case first, last
    /// Return: open the message's link (a menu of them when it has
    /// several); expand or collapse a join/part run.
    case activate
    /// R, E, C (and ⌘C), U, T.
    case reply, react, copy, userMenu, translate
    /// Space, the context-menu key or ⇧F10: the message's right-click menu.
    case showMenu
    /// Esc: back to the message box.
    case leave
    /// Any other key that types something: typed in the message box.
    case type

    private static let escapeKeyCode: UInt16 = 53
    /// The context-menu (application) key of PC keyboards.
    private static let contextMenuKeyCode: UInt16 = 110

    /// The command for a key press, or nil for a key the messages leave
    /// alone (Tab, ←, →, ⌃ and ⌘ shortcuts…).
    static func command(
        keyCode: UInt16,
        characters: String,
        charactersIgnoringModifiers: String,
        modifiers: NSEvent.ModifierFlags
    ) -> MessageKeyCommand? {
        let flags = modifiers.intersection([.command, .control, .option, .shift])
        let key = charactersIgnoringModifiers.unicodeScalars.first?.value ?? 0
        if flags.contains(.command) {
            // ⌘C, when Edit → Copy doesn't take it first.
            return flags == .command && charactersIgnoringModifiers.lowercased() == "c" ? .copy : nil
        }
        if flags.contains(.control) { return nil }
        if keyCode == escapeKeyCode { return flags.isEmpty ? .leave : nil }
        if keyCode == contextMenuKeyCode || key == UInt32(NSMenuFunctionKey) { return .showMenu }
        switch key {
        case UInt32(NSUpArrowFunctionKey): return flags.isEmpty ? .previous : nil
        case UInt32(NSDownArrowFunctionKey): return flags.isEmpty ? .next : nil
        case UInt32(NSPageUpFunctionKey): return flags.isEmpty ? .pageUp : nil
        case UInt32(NSPageDownFunctionKey): return flags.isEmpty ? .pageDown : nil
        case UInt32(NSHomeFunctionKey): return flags.isEmpty ? .first : nil
        case UInt32(NSEndFunctionKey): return flags.isEmpty ? .last : nil
        case UInt32(NSF10FunctionKey): return flags == .shift ? .showMenu : nil
        case 0x0D, 0x03: return flags.isEmpty ? .activate : nil   // Return, Enter
        case 0x20: return flags.isEmpty ? .showMenu : nil
        default: break
        }
        if flags.isEmpty {
            switch charactersIgnoringModifiers.lowercased() {
            case "r": return .reply
            case "e": return .react
            case "c": return .copy
            case "u": return .userMenu
            case "t": return .translate
            default: break
            }
        }
        return types(characters, ignoringModifiers: charactersIgnoringModifiers) ? .type : nil
    }

    static func command(for event: NSEvent) -> MessageKeyCommand? {
        guard event.type == .keyDown else { return nil }
        return command(
            keyCode: event.keyCode,
            characters: event.characters ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            modifiers: event.modifierFlags
        )
    }

    /// Whether a key types something: printable characters, or a dead key
    /// (⌥E) that starts one. Not control characters (Tab, Delete) or
    /// function keys (arrows, F-keys), which macOS puts in a private range.
    private static func types(_ characters: String, ignoringModifiers: String) -> Bool {
        let text = characters.isEmpty ? ignoringModifiers : characters
        guard !text.isEmpty else { return false }
        return !text.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .control || (0xF700...0xF8FF).contains(scalar.value)
        }
    }
}

// MARK: Selection

/// Which rows the keyboard selects, and where it goes from one.
///
/// Messages and collapsed join/part runs are selected (Return expands a
/// run); day dividers, the New line, the Catch me up card and events
/// (joins and parts shown one by one, topics, modes, server messages),
/// which have nothing to do, are skipped.
nonisolated enum MessageSelection {
    static func isSelectable(_ item: DisplayItem) -> Bool {
        switch item {
        case .line(let lineItem): lineItem.line.kind.isConversation
        case .membershipRun: true
        case .dayDivider, .unreadMarker, .catchUpCard: false
        }
    }

    static func isMessage(_ item: DisplayItem) -> Bool {
        if case .line(let lineItem) = item { return lineItem.line.kind.isConversation }
        return false
    }

    /// Where `id` is in `items`. `hint` (where it was last time) is checked
    /// first; otherwise it's looked for from the end, where the selection
    /// usually is.
    static func index(of id: DisplayItemID, in items: DisplayItems, hint: Int? = nil) -> Int? {
        if let hint, items.indices.contains(hint), items[hint].id == id { return hint }
        return items.lastIndex { $0.id == id }
    }

    /// The selectable row at `index`, or the nearest one after it
    /// (`forward`) or before it.
    static func selectable(from index: Int, forward: Bool, in items: DisplayItems) -> Int? {
        var current = index
        while items.indices.contains(current) {
            if isSelectable(items[current]) { return current }
            current += forward ? 1 : -1
        }
        return nil
    }

    static func newest(in items: DisplayItems) -> Int? {
        selectable(from: items.count - 1, forward: false, in: items)
    }

    static func oldest(in items: DisplayItems) -> Int? {
        selectable(from: 0, forward: true, in: items)
    }

    /// `count` selectable rows on from `index` (back, when negative),
    /// stopping at the first or the last.
    static func step(from index: Int, by count: Int, in items: DisplayItems) -> Int {
        var result = index
        var remaining = abs(count)
        var current = index
        while remaining > 0 {
            current += count > 0 ? 1 : -1
            guard items.indices.contains(current) else { break }
            if isSelectable(items[current]) {
                result = current
                remaining -= 1
            }
        }
        return result
    }

    /// Where the selection starts when the messages take the focus: the
    /// newest message while the list shows the newest lines; otherwise the
    /// bottom-most message in view. A collapsed run when there's no message
    /// to pick.
    static func initial(in items: DisplayItems, visible: [DisplayItemID], showsNewest: Bool) -> Int? {
        if !showsNewest, let inView = bottomMost(in: items, visible: visible) { return inView }
        return items.indices.reversed().first { isMessage(items[$0]) } ?? newest(in: items)
    }

    /// The bottom-most message among `visible` (rows at least half in view,
    /// top to bottom), else the bottom-most selectable row there.
    private static func bottomMost(in items: DisplayItems, visible: [DisplayItemID]) -> Int? {
        guard let last = visible.last(where: { $0 != .end }), var current = index(of: last, in: items) else { return nil }
        let shown = Set(visible)
        var fallback: Int?
        while current >= 0, shown.contains(items[current].id) {
            if isMessage(items[current]) { return current }
            if fallback == nil, isSelectable(items[current]) { fallback = current }
            current -= 1
        }
        return fallback
    }

    /// What to scroll to, by id, to bring the row `id` in at `edge`: the row
    /// itself, or for a collapsed run the line beside it, on the far side
    /// from the run (SwiftUI places a run scrolled to by id a row off). The
    /// run then sits just inside that edge, near enough for the exact
    /// correction that follows (`MessageListView.reveal`).
    static func scrollTarget(for id: DisplayItemID, toward edge: VerticalEdge, in items: DisplayItems) -> DisplayItemID {
        guard case .membershipRun = id, let index = index(of: id, in: items) else { return id }
        let step = edge == .top ? -1 : 1
        var current = index + step
        while items.indices.contains(current), abs(current - index) <= 4 {
            if case .line = items[current] { return items[current].id }
            current += step
        }
        return id
    }

    /// How many selectable rows Page Up and Page Down move: as many as are
    /// in view, less one, so the row at the edge stays in view.
    static func pageSize(visible: [DisplayItemID], in items: DisplayItems) -> Int {
        let ids = visible.filter { $0 != .end }
        guard let first = ids.first, let last = ids.last,
              let top = index(of: first, in: items), let bottom = index(of: last, in: items), top <= bottom
        else { return 5 }
        return max(1, (top...bottom).count(where: { isSelectable(items[$0]) }) - 1)
    }
}

/// What the selected row is told (`DisplayItemRow.selection`); every other
/// row gets nil.
struct RowSelection: Equatable {
    var id: DisplayItemID
    /// Bumped to open the row's reaction picker (E).
    var pickerRequest = 0
}

// MARK: Scrolling

/// What the keyboard and the message box ask of the list's scrolling.
enum MessageListScroll: Equatable {
    /// A page up or down, less a little, so a line at the edge stays in view.
    case pageUp, pageDown
    /// To the oldest message loaded (older ones load from there).
    case top
    /// To the newest message, following new ones again (Jump to present).
    case present
}

/// How `MessageListView` scrolls for the keyboard.
struct MessageListScrolling {
    /// Brings the newly selected row into view, as little as it takes:
    /// from the top when the selection went up, from the bottom when it
    /// went down.
    var reveal: (DisplayItemID, VerticalEdge) -> Void
    /// `animated`: short trips glide, as from the message box. The
    /// selection's go at once, so its row is there for the next key.
    var scroll: (MessageListScroll, _ animated: Bool) -> Void
}

/// Lets the message box scroll the message list above it (Page Up, Page
/// Down, Home, End, and Esc with nothing to cancel). The list registers
/// itself for its buffer while it's on screen; one per window.
@MainActor
final class MessageListLink {
    private var lists: [BufferID: (token: UUID, scroll: (MessageListScroll) -> Void)] = [:]

    /// Registers the list of `bufferID`; returns the token that removes it.
    func register(_ bufferID: BufferID, scroll: @escaping (MessageListScroll) -> Void) -> UUID {
        let token = UUID()
        lists[bufferID] = (token, scroll)
        return token
    }

    func unregister(_ bufferID: BufferID, token: UUID) {
        if lists[bufferID]?.token == token { lists[bufferID] = nil }
    }

    /// Scrolls the list of `bufferID`; false when it isn't on screen.
    @discardableResult
    func scroll(_ scroll: MessageListScroll, in bufferID: BufferID) -> Bool {
        guard let list = lists[bufferID] else { return false }
        list.scroll(scroll)
        return true
    }
}

extension EnvironmentValues {
    /// Set by the chat column for its message list and message box.
    @Entry var messageListLink: MessageListLink?
}

// MARK: The focus

/// The messages' share of the keyboard, behind the list. Takes the focus
/// when it's asked for (`UIState.focus(.messages)`), and passes keys to
/// `MessageKeyHandler`. Reads the focus request in a body of its own, so
/// requests for other areas don't run the list's.
struct MessageKeyboard: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(TranslationStore.self) private var translations
    @Environment(\.translationContext) private var translationContext
    @Environment(\.chatStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let controller: MessageListController
    let scrolling: MessageListScrolling

    var body: some View {
        let handler = MessageKeyHandler(
            app: app,
            uiState: uiState,
            translations: translations,
            translationContext: translationContext,
            reduceMotion: reduceMotion,
            menuInset: style.rowHorizontalPadding,
            controller: controller,
            scrolling: scrolling
        )
        MessageKeyViewHost(handler: handler, controller: controller)
            .onChange(of: uiState.focusRequest, initial: true) { _, request in
                guard request?.area == .messages, uiState.takeFocusRequest(for: .messages) else { return }
                controller.requestKeyFocus()
            }
    }
}

private struct MessageKeyViewHost: NSViewRepresentable {
    let handler: MessageKeyHandler
    let controller: MessageListController

    func makeNSView(context: Context) -> MessageKeyView {
        let view = MessageKeyView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: MessageKeyView, context: Context) {
        view.handler = handler
        controller.keyView = view
    }

    static func dismantleNSView(_ view: MessageKeyView, coordinator: ()) {
        view.handler = nil
    }
}

/// The view that has the keyboard focus while the messages do. Draws
/// nothing and lets every click through.
final class MessageKeyView: NSView, NSMenuItemValidation {
    var handler: MessageKeyHandler?
    /// Leaving the window with the focus (the channel switched): the
    /// messages keep it, as far as F6 goes, and the next channel's list
    /// takes it over.
    private var isLeavingWithFocus = false

    override var acceptsFirstResponder: Bool { true }
    // Only when asked (⌥⌘2, F6): never as the window's first key view,
    // which would keep the message box from taking the focus on launch.
    override var canBecomeKeyView: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var hasFocus: Bool { window != nil && window?.firstResponder === self }

    func takeFocus() {
        guard let window, window.firstResponder !== self else { return }
        window.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { handler?.focusChanged(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted, !isLeavingWithFocus { handler?.focusChanged(false) }
        return accepted
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, hasFocus { isLeavingWithFocus = true }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        isLeavingWithFocus = false
        // Let the window settle first (the last channel's list is going).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window, let handler = self.handler else { return }
            if handler.controller.takePendingKeyFocus() || handler.inheritsFocus(in: window) { self.takeFocus() }
        }
    }

    override func keyDown(with event: NSEvent) {
        if handler?.handle(event, in: self) == true { return }
        super.keyDown(with: event)
    }

    // Edit → Copy (⌘C).
    @objc func copy(_ sender: Any?) {
        _ = handler?.perform(.copy, event: nil, in: self)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(copy(_:)) ? handler?.canCopy ?? false : true
    }

    // MARK: Accessibility

    // An element only while it has the focus, for VoiceOver to land on;
    // otherwise the rows are what there is to read.
    override func isAccessibilityElement() -> Bool { hasFocus }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { String(localized: "Messages") }
    override func accessibilityValue() -> Any? { handler?.selectionLabel() }

    override func accessibilityHelp() -> String? {
        String(localized: "Up and down arrows choose a message. R replies, E reacts, C copies, Return opens a link, U shows the sender's actions, T translates, Space shows all actions. Escape goes back to the message box.")
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        handler?.accessibilityActions(in: self)
    }

    override func accessibilityPerformShowMenu() -> Bool {
        handler?.perform(.showMenu, event: nil, in: self) ?? false
    }
}

// MARK: Commands

/// Does what the keys say, to the selected row.
@MainActor
struct MessageKeyHandler {
    let app: AppModel
    let uiState: UIState
    let translations: TranslationStore
    let translationContext: TranslationContext?
    let reduceMotion: Bool
    /// Where menus open across a row: about where its name is.
    let menuInset: CGFloat
    let controller: MessageListController
    let scrolling: MessageListScrolling

    // MARK: Focus

    /// Reported at once, for F6, and for a message box that appears
    /// meanwhile (after switching channels), which then leaves the focus
    /// here. The selection is there before any key can move it.
    func focusChanged(_ focused: Bool) {
        uiState.setFocused(.messages, focused)
        if focused {
            selectInitial()
        } else {
            // On the next turn: the focus can leave during a SwiftUI update
            // (the message box takes it in its `updateNSView`), when the
            // list mustn't change. Unless it's back by then.
            Task { @MainActor [controller] in
                if controller.keyView?.hasFocus != true { controller.select(nil) }
            }
        }
    }

    /// A list that appears (after switching channels) while the messages
    /// had the focus takes it, unless something else has it now.
    func inheritsFocus(in window: NSWindow) -> Bool {
        guard uiState.focusedArea == .messages else { return false }
        let responder = window.firstResponder
        return responder == nil || responder === window || responder is MessageKeyView
    }

    private func selectInitial() {
        let items = controller.displayCache.items
        let visible = controller.visibleIDs
        let showsNewest = controller.isPinnedToBottom || visible.isEmpty
        guard let index = MessageSelection.initial(in: items, visible: visible, showsNewest: showsNewest) else { return }
        select(index, in: items, revealing: .bottom)
    }

    private func select(_ index: Int, in items: DisplayItems, revealing edge: VerticalEdge) {
        let id = items[index].id
        controller.select(id, index: index)
        scrolling.reveal(id, edge)
        announceSelection()
    }

    // MARK: Keys

    func handle(_ event: NSEvent, in view: MessageKeyView) -> Bool {
        guard let command = MessageKeyCommand.command(for: event) else { return false }
        return perform(command, event: event, in: view)
    }

    /// Does `command`; false for one that isn't the messages' to handle.
    @discardableResult
    func perform(_ command: MessageKeyCommand, event: NSEvent?, in view: MessageKeyView) -> Bool {
        switch command {
        case .leave:
            uiState.focus(.messageBox)
            return true
        case .type:
            return typeInMessageBox(event, from: view)
        case .previous, .next, .pageUp, .pageDown, .first, .last:
            move(command)
            return true
        case .activate, .reply, .react, .copy, .userMenu, .translate, .showMenu:
            guard let selected = controller.selectedItem else {
                controller.beep()
                return true
            }
            if !act(command, on: selected.item, in: view) { controller.beep() }
            return true
        }
    }

    // MARK: Moving

    private func move(_ command: MessageKeyCommand) {
        let items = controller.displayCache.items
        guard let current = controller.selectedItem?.index else {
            // The selected row went (trimmed off the top, say): start again
            // where taking the focus does.
            if MessageSelection.newest(in: items) != nil {
                selectInitial()
                return
            }
            // Nothing to select (only events here): the keys scroll.
            switch command {
            case .previous, .pageUp: scrolling.scroll(.pageUp, true)
            case .next, .pageDown: scrolling.scroll(.pageDown, true)
            case .first: scrolling.scroll(.top, true)
            default: scrolling.scroll(.present, true)
            }
            return
        }
        let target: Int?
        switch command {
        case .previous: target = MessageSelection.step(from: current, by: -1, in: items)
        case .next: target = MessageSelection.step(from: current, by: 1, in: items)
        case .pageUp, .pageDown:
            let page = MessageSelection.pageSize(visible: controller.visibleIDs, in: items)
            target = MessageSelection.step(from: current, by: command == .pageUp ? -page : page, in: items)
        case .first: target = MessageSelection.oldest(in: items)
        default: target = MessageSelection.newest(in: items)
        }
        guard let target else { return }
        let goesUp = command == .previous || command == .pageUp || command == .first
        if target == MessageSelection.oldest(in: items), goesUp {
            // The first message loaded: the top of the list, with the
            // history header, from where older messages load.
            if target != current { controller.select(items[target].id, index: target); announceSelection() }
            scrolling.scroll(.top, false)
        } else if target == MessageSelection.newest(in: items), !goesUp {
            // The newest: back to the present, following new messages.
            if target != current { controller.select(items[target].id, index: target); announceSelection() }
            scrolling.scroll(.present, false)
        } else if target != current {
            select(target, in: items, revealing: goesUp ? .top : .bottom)
        }
    }

    // MARK: Acting

    /// Does `command` to the selected row; false when there's nothing to
    /// do (the reaction picker on a server without reactions, Return on a
    /// message without links…).
    private func act(_ command: MessageKeyCommand, on item: DisplayItem, in view: MessageKeyView) -> Bool {
        switch item {
        case .membershipRun(let run):
            // A run has nothing but its events: Return and Space show or
            // hide them.
            guard command == .activate || command == .showMenu else { return false }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { controller.toggleRun(run.id) }
            announceSelection()
            return true
        case .line(let lineItem):
            return act(command, on: lineItem.line, in: view)
        case .dayDivider, .unreadMarker, .catchUpCard:
            return false
        }
    }

    private func act(_ command: MessageKeyCommand, on line: ChatLine, in view: MessageKeyView) -> Bool {
        switch command {
        case .reply:
            guard controller.canReply(to: line) else { return false }
            controller.reply(to: line, uiState: uiState)
        case .react:
            guard controller.canReact(to: line) else { return false }
            controller.requestReactionPicker()
        case .copy:
            guard !line.isRedacted else { return false }
            controller.copyText(of: line)
        case .activate:
            return openLinks(of: line, from: view)
        case .userMenu:
            guard let nick = line.nick, !nick.isEmpty else { return false }
            let actions = UserMenuActions(app: app, uiState: uiState, session: controller.session, buffer: controller.buffer)
            let target = actions.target(nick: nick, userHost: line.userHost)
            showMenu(actions.nsMenu(UserMenu.Resolved(menu: actions.menu(for: [target]), targets: [target])), from: view)
        case .translate:
            guard let translationContext,
                  let action = translations.messageAction(for: line, in: controller.buffer, context: translationContext)
            else { return false }
            translations.perform(action, on: line, context: translationContext)
        case .showMenu:
            return showContextMenu(from: view)
        default:
            return false
        }
        return true
    }

    var canCopy: Bool {
        guard case .line(let lineItem) = controller.selectedItem?.item else { return false }
        return !lineItem.line.isRedacted
    }

    /// Return: the message's link, or a menu of them when it has several.
    private func openLinks(of line: ChatLine, from view: MessageKeyView) -> Bool {
        guard !line.isRedacted else { return false }
        let links = controller.textCache.rendered(line).linkRuns
        guard let first = links.first else { return false }
        guard links.count > 1 else {
            controller.openLink(first.url, app: app)
            return true
        }
        let menu = NSMenu(title: String(localized: "Links"))
        menu.autoenablesItems = false
        for link in links {
            let item = MenuItemHandler.item(title: link.title) { [controller, app] in controller.openLink(link.url, app: app) }
            item.toolTip = link.url.absoluteString
            menu.addItem(item)
        }
        showMenu(menu, from: view)
        return true
    }

    /// Space: the row's own context menu, as a right-click on it opens it
    /// (asked for the same way AppKit does, from a spot on the row clear
    /// of its text, whose own menu would come first).
    private func showContextMenu(from view: MessageKeyView) -> Bool {
        guard let row = controller.selectedRowView, let window = row.window,
              let root = window.contentView?.superview ?? window.contentView
        else { return false }
        let local = NSPoint(x: 2, y: min(row.bounds.height / 2, 10))
        let point = row.convert(local, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .rightMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ) else { return false }
        var candidate = root.hitTest(point)
        while let current = candidate {
            if let menu = current.menu(for: event) {
                controller.menuPresenter(menu, NSPoint(x: menuInset, y: local.y), row)
                return true
            }
            candidate = current.superview
        }
        return false
    }

    /// Opens `menu` at the selected row, by its name; at the list's edge
    /// when the row isn't laid out.
    private func showMenu(_ menu: NSMenu, from view: MessageKeyView) {
        if let row = controller.selectedRowView, row.window != nil {
            controller.menuPresenter(menu, NSPoint(x: menuInset, y: min(row.bounds.height, 20)), row)
        } else {
            controller.menuPresenter(menu, NSPoint(x: menuInset, y: view.bounds.midY), view)
        }
    }

    /// Any other character goes to the message box, as if typed there.
    private func typeInMessageBox(_ event: NSEvent?, from view: NSView) -> Bool {
        guard let event, let window = view.window,
              let composer = Self.messageBox(in: window.contentView),
              window.makeFirstResponder(composer)
        else {
            uiState.focus(.messageBox)
            return true
        }
        composer.keyDown(with: event)
        return true
    }

    private static func messageBox(in view: NSView?) -> ComposerNSTextView? {
        guard let view else { return nil }
        if let composer = view as? ComposerNSTextView { return composer }
        for subview in view.subviews {
            if let found = messageBox(in: subview) { return found }
        }
        return nil
    }

    // MARK: VoiceOver

    /// What VoiceOver says about the selected row.
    func selectionLabel() -> String? {
        guard let selected = controller.selectedItem else { return nil }
        switch selected.item {
        case .line(let lineItem):
            let line = lineItem.line
            let rendered = line.isRedacted ? nil : controller.textCache.rendered(line)
            return controller.accessibilityLabel(for: line) { MessageAccessibility.label(for: line, rendered: rendered) }
        case .membershipRun(let run):
            let state = controller.expandedRuns.contains(run.id) ? String(localized: "expanded") : String(localized: "collapsed")
            return "\(controller.summary(of: run)), \(state)"
        case .dayDivider, .unreadMarker, .catchUpCard:
            return nil
        }
    }

    private func announceSelection() {
        guard NSWorkspace.shared.isVoiceOverEnabled, let label = selectionLabel() else { return }
        AccessibilityNotification.Announcement(label).post()
    }

    /// The keys' actions for the selected message, as VoiceOver actions on
    /// the messages.
    func accessibilityActions(in view: MessageKeyView) -> [NSAccessibilityCustomAction] {
        guard case .line(let lineItem) = controller.selectedItem?.item else {
            if case .membershipRun = controller.selectedItem?.item {
                return [action(String(localized: "Show or Hide Events"), .activate, in: view)]
            }
            return []
        }
        let line = lineItem.line
        var actions: [NSAccessibilityCustomAction] = []
        if controller.canReply(to: line) { actions.append(action(String(localized: "Reply"), .reply, in: view)) }
        if controller.canReact(to: line) { actions.append(action(String(localized: "Add Reaction"), .react, in: view)) }
        if !line.isRedacted {
            actions.append(action(String(localized: "Copy Text"), .copy, in: view))
            let links = controller.textCache.rendered(line).linkRuns
            if links.count == 1 {
                actions.append(action(String(localized: "Open \(links[0].title)"), .activate, in: view))
            } else if links.count > 1 {
                actions.append(action(String(localized: "Open a Link…"), .activate, in: view))
            }
        }
        if let nick = line.nick, !nick.isEmpty {
            actions.append(action(String(localized: "Actions for \(nick)…"), .userMenu, in: view))
        }
        if let translationContext, let translation = translations.messageAction(for: line, in: controller.buffer, context: translationContext) {
            let name = translation == .hide ? String(localized: "Hide Translation") : String(localized: "Translate")
            actions.append(action(name, .translate, in: view))
        }
        actions.append(action(String(localized: "Show Menu"), .showMenu, in: view))
        return actions
    }

    private func action(_ name: String, _ command: MessageKeyCommand, in view: MessageKeyView) -> NSAccessibilityCustomAction {
        NSAccessibilityCustomAction(name: name) { [weak view] in
            guard let view, let handler = view.handler else { return false }
            return handler.perform(command, event: nil, in: view)
        }
    }
}

// MARK: The selected row

/// Behind the selected row only: tells the controller where the row is,
/// for menus opened from the keyboard and for keeping the row in view.
struct SelectedRowAnchor: NSViewRepresentable {
    @Environment(MessageListController.self) private var controller
    let id: DisplayItemID

    final class AnchorView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    // Both: a new view isn't always updated right after it's made. The
    // controller keeps it weakly, so there's nothing to undo.

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.setAccessibilityElement(false)
        controller.setSelectedRowView(view, for: id)
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        controller.setSelectedRowView(view, for: id)
    }
}

/// The selected row's highlight: the theme's selection color, and its
/// focus ring around the row.
struct MessageSelectionHighlight: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme[ThemeKey.chatSelectionBackground]
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(theme[ThemeKey.focusBorder], lineWidth: 1.5)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
