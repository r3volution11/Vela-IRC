// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

// The keyboard focus of the sidebar, the tabs and the member list: one
// invisible AppKit view per area that becomes the first responder when the
// area is asked to take the focus (⌥⌘1, ⌥⌘4, F6) and turns the keys it gets
// into moves. The area draws where the keyboard is from its own state (the
// selected row, the highlighted member), so no row takes the focus itself.
//
// AppKit's first responder rather than SwiftUI's focus: SwiftUI documents
// buttons and other "activate" views as focusable only with Keyboard
// navigation on in System Settings (`FocusInteractions.activate`), and a
// focusable view that edits takes the focus on every click, which would
// leave a channel clicked in the sidebar without its message box.
// `makeFirstResponder` works either way, and the view says at once when it
// gains or loses the focus, before a selection made with the keyboard
// brings in a new message box (which leaves the focus to the area that
// reports having it; see `UIState.focusedArea`).

/// A key an area does something with.
enum NavigationKey: Equatable {
    case up, down, left, right
    case home, end, pageUp, pageDown
    case `return`, escape, space
    /// ⇧F10, or the context-menu key of a PC keyboard: an item's menu.
    case menu
    /// Letters, digits and other printable characters, typed without ⌘, ⌃
    /// or ⌥ (Shift is fine): type-select, or the member list's filter.
    case text(String)

    /// The key `event` is, or nil for one the areas leave alone (anything
    /// with ⌘, ⌃ or ⌥ goes on to the menus and the rest of the window).
    init?(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch event.keyCode {
        case 126: self = .up
        case 125: self = .down
        case 123: self = .left
        case 124: self = .right
        case 115: self = .home
        case 119: self = .end
        case 116: self = .pageUp
        case 121: self = .pageDown
        case 36, 76: self = .return
        case 53: self = .escape
        case 49: self = .space
        case 110: self = .menu
        case 109 where modifiers == .shift: self = .menu
        default:
            guard modifiers.subtracting(.shift).isEmpty, let characters = event.characters,
                  Self.isPrintable(characters) else { return nil }
            self = .text(characters)
            return
        }
        // Shift, ⌘, ⌃ and ⌥ arrows and the like are other commands (⌥⌘↓,
        // ⇧⌘[…); ⇧F10 has been checked above.
        if self != .menu, !modifiers.isEmpty { return nil }
    }

    /// Text without control characters or the function keys' private-use
    /// characters (arrows, F-keys, Home…), and not a space.
    static func isPrintable(_ characters: String) -> Bool {
        guard !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }
}

/// Lets an area take the keyboard focus, and tells whether it has it, from
/// outside SwiftUI's updates (key handlers, `onChange`).
@MainActor
final class KeyboardFocusHandle {
    fileprivate weak var view: KeyboardFocusView?

    /// The area's view is the window's first responder.
    var hasFocus: Bool { view?.hasFocus ?? false }

    /// The window the area is in.
    var window: NSWindow? { view?.window }

    /// The area's view, the size of the area: something to open a menu
    /// from.
    var anchorView: NSView? { view }

    /// Makes the area the first responder, as soon as it's in a window.
    func focus() {
        view?.takeFocus()
    }

    /// Gives the focus up to the window, so the next message box takes it.
    func resign() {
        guard let view, view.hasFocus, let window = view.window else { return }
        window.makeFirstResponder(nil)
    }

    /// A row in the area was clicked (or pressed with VoiceOver) to open
    /// it: the focus goes to the message box, as after any click on a
    /// channel, rather than staying with the keyboard here. Call it before
    /// selecting, so the new message box doesn't leave the focus here.
    func yieldToClick(_ uiState: UIState) {
        guard hasFocus else { return }
        resign()
        uiState.focusInput()
    }
}

/// The view that has the keyboard focus for an area, placed behind it.
struct KeyboardFocusArea: NSViewRepresentable {
    let handle: KeyboardFocusHandle
    /// Called at once when the area gains or loses the focus.
    let onFocusChange: (Bool) -> Void
    /// A key pressed while the area has the focus, and when (the event's
    /// timestamp, for type-select); false passes it on.
    let onKey: (NavigationKey, TimeInterval) -> Bool

    func makeNSView(context: Context) -> KeyboardFocusView {
        let view = KeyboardFocusView()
        handle.view = view
        update(view)
        return view
    }

    func updateNSView(_ view: KeyboardFocusView, context: Context) {
        handle.view = view
        update(view)
    }

    private func update(_ view: KeyboardFocusView) {
        view.onFocusChange = onFocusChange
        view.onKey = onKey
    }
}

/// Invisible, and never hit by the pointer: clicks go to the rows in front
/// of it, and it only becomes the first responder when asked.
final class KeyboardFocusView: NSView {
    var onFocusChange: (Bool) -> Void = { _ in }
    var onKey: (NavigationKey, TimeInterval) -> Bool = { _, _ in false }
    private(set) var hasFocus = false
    private var wantsFocusOnAttach = false

    override var acceptsFirstResponder: Bool { true }

    // Out of the Tab loop: Tab from an empty message box goes where it
    // always has, and ⌥⌘1–⌥⌘4 and F6 are the way in.
    override var canBecomeKeyView: Bool { false }

    override func becomeFirstResponder() -> Bool {
        setHasFocus(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        setHasFocus(false)
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Taken out of the window with the focus (the member list hidden,
        // the sidebar swapped for tabs): no resign comes.
        if newWindow == nil { setHasFocus(false) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Asked before it was in a window: the member list, shown to take
        // the focus.
        guard wantsFocusOnAttach, let window else { return }
        wantsFocusOnAttach = false
        window.makeFirstResponder(self)
    }

    func takeFocus() {
        guard let window else {
            wantsFocusOnAttach = true
            return
        }
        if window.firstResponder !== self { window.makeFirstResponder(self) }
    }

    override func keyDown(with event: NSEvent) {
        if let key = NavigationKey(event), onKey(key, event.timestamp) { return }
        // Tab and ⇧Tab go on along the window's key views, as from
        // anywhere else.
        if event.keyCode == 48, event.modifierFlags.intersection([.command, .control, .option]).isEmpty, let window {
            if event.modifierFlags.contains(.shift) {
                window.selectPreviousKeyView(nil)
            } else {
                window.selectNextKeyView(nil)
            }
            return
        }
        super.keyDown(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // The rows are what VoiceOver reads; moves are announced
    // (`KeyboardAnnouncement`).
    override func isAccessibilityElement() -> Bool { false }

    private func setHasFocus(_ focused: Bool) {
        guard hasFocus != focused else { return }
        hasFocus = focused
        onFocusChange(focused)
    }
}

/// What the keyboard moved to, said by VoiceOver: the areas' rows aren't
/// the first responder themselves, so VoiceOver wouldn't say it otherwise.
@MainActor
enum KeyboardAnnouncement {
    static func post(_ text: String) {
        guard !text.isEmpty, NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}

/// Typing a name's first letters to go to it, as in Finder's lists: what's
/// typed within a second of the last key adds up; a letter typed on its own
/// (or again and again) goes to the next name starting with it.
struct TypeSelect {
    /// How long after the last key typing starts over.
    static let timeout: TimeInterval = 1

    private(set) var typed = ""
    private var lastTime: TimeInterval?

    /// Adds `text`, typed at `time` (an event's timestamp).
    mutating func type(_ text: String, at time: TimeInterval) {
        let continues = lastTime.map { time >= $0 && time - $0 <= Self.timeout } ?? false
        if !continues { typed = "" }
        typed += text
        lastTime = time
    }

    mutating func reset() {
        typed = ""
        lastTime = nil
    }

    /// The index of the item to go to among `names` (each item's names, any
    /// of which may match), from `current`; nil when none starts with
    /// what's typed. Wraps around.
    func match(in names: [[String]], current: Int?) -> Int? {
        guard let first = typed.first, !names.isEmpty else { return nil }
        // "v", or "vvv": the next one with a v. "ve": this one, if it fits.
        let cycles = typed.allSatisfy { $0 == first }
        let query = cycles ? String(first) : typed
        let start: Int
        if let current, names.indices.contains(current) {
            start = cycles ? current + 1 : current
        } else {
            start = 0
        }
        for offset in 0..<names.count {
            let index = (start + offset) % names.count
            if names[index].contains(where: { Self.name($0, startsWith: query) }) { return index }
        }
        return nil
    }

    static func name(_ name: String, startsWith query: String) -> Bool {
        name.range(of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
    }
}
