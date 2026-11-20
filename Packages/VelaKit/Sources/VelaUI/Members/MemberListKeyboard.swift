// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import SwiftUI
import VelaCore

/// The member list's keyboard focus and highlight (⌥⌘4, F6).
///
/// The highlight costs nothing per row, in a channel of thousands: each row
/// watches only its own flag (`MemberHighlightFlag`), so moving the
/// highlight redraws the row it leaves and the row it lands on, never the
/// list, and the list's body (grouping and filtering everyone) doesn't run
/// for it. Flags are made for rows as they're drawn, and dropped with the
/// channel.
@MainActor
final class MemberListKeyboard {
    let handle = KeyboardFocusHandle()
    /// The highlighted member's nick (their row's id).
    private(set) var highlighted: String?
    /// Whether the highlight shows: the list has the keyboard focus.
    private(set) var isShowing = false
    private var flags: [String: MemberHighlightFlag] = [:]
    /// The list's scroll view, for keeping the highlight in view.
    var proxy: ScrollViewProxy?
    /// How tall the list's visible part is, for Page Up and Page Down.
    var visibleHeight: CGFloat = 0
    /// The highlighted row, which a menu opened from the keyboard hangs from.
    weak var menuAnchor: NSView?
    /// The list's top, to scroll to above the first member.
    static let topID = "members.top"

    /// The flag the row for `nick` watches.
    func flag(for nick: String) -> MemberHighlightFlag {
        if let flag = flags[nick] { return flag }
        let flag = MemberHighlightFlag(isOn: isShowing && nick == highlighted)
        flags[nick] = flag
        return flag
    }

    /// Moves the highlight to `nick`.
    func highlight(_ nick: String?) {
        guard nick != highlighted else { return }
        if let highlighted { flags[highlighted]?.isOn = false }
        highlighted = nick
        if isShowing, let nick { flag(for: nick).isOn = true }
    }

    /// Shows or hides the highlight, as the list gains or loses the focus.
    func setShowing(_ showing: Bool) {
        isShowing = showing
        if let highlighted { flags[highlighted]?.isOn = showing }
    }

    /// Another channel: no highlight, and no flags for its rows to share.
    func reset() {
        highlighted = nil
        flags = [:]
        menuAnchor = nil
        highlightedFrame = nil
    }

    /// Where the highlighted row is in the list's visible part, as it last
    /// drew: only that row reports it (`MemberRow`), as it moves or scrolls.
    var highlightedFrame: (nick: String, frame: CGRect)?

    /// Scrolls the list as little as it takes for `nick`'s row (at `index`)
    /// to show: going up, with two rows above it, so it's clear of the
    /// section header pinned at the top (from the first two, to the top);
    /// going down, at the bottom edge.
    ///
    /// `step` is ±1 for ↑ and ↓ from the row highlighted now: when the row
    /// after it is in view, as it mostly is, nothing scrolls. `scrollTo`
    /// looks the row up among everyone in the list, which in a channel of
    /// thousands costs far more than the rest of a key press.
    func reveal(_ nick: String, index: Int, above: String?, goingUp: Bool, step: Int? = nil, rowHeight: CGFloat) {
        guard let proxy else { return }
        if let step, showsRow(step, rowHeight: rowHeight) { return }
        if goingUp {
            if let above {
                proxy.scrollTo(above)
            } else {
                proxy.scrollTo(Self.topID, anchor: .top)
            }
        } else {
            proxy.scrollTo(nick)
        }
    }

    /// Height kept for a section header: one may come between two rows, and
    /// one is pinned over the top of the list.
    private static let headerAllowance: CGFloat = 32

    /// Whether the row `step` rows from the highlighted one is in view,
    /// below the pinned header, allowing for a section header between
    /// them. False when unsure (the highlighted row hasn't drawn yet).
    private func showsRow(_ step: Int, rowHeight: CGFloat) -> Bool {
        guard let record = highlightedFrame, record.nick == highlighted, visibleHeight > 0 else { return false }
        let distance = CGFloat(abs(step)) * rowHeight + Self.headerAllowance
        let target = record.frame.offsetBy(dx: 0, dy: step < 0 ? -distance : distance)
        return target.minY >= Self.headerAllowance && target.maxY <= visibleHeight
    }

    /// Shows a member's menu from the keyboard. Tests swap it to read the
    /// menu without opening it: a menu's tracking loop would hold them up.
    static var presentMenu: (NSMenu, NSView) -> Void = { popUp($0, under: $1) }

    /// Opens `menu` just under `view`, as a right-click on the row would
    /// beside the pointer.
    static func popUp(_ menu: NSMenu, under view: NSView) {
        let point = NSPoint(x: 12, y: view.isFlipped ? view.bounds.maxY : view.bounds.minY)
        menu.popUp(positioning: nil, at: point, in: view)
    }
}

/// Whether one member's row is highlighted: the only thing that row watches
/// for the keyboard.
@Observable
final class MemberHighlightFlag {
    var isOn: Bool

    init(isOn: Bool) {
        self.isOn = isOn
    }
}

/// The members in the order the list shows them, for the keys to move
/// through. Made each time the list's body runs, and flattened only when a
/// key needs it.
@MainActor
final class MemberListOrder {
    let groups: [MemberGroup]
    private(set) lazy var nicks: [String] = groups.flatMap { $0.members.map(\.nick) }
    private lazy var positions: [String: Int] = Dictionary(nicks.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

    init(groups: [MemberGroup]) {
        self.groups = groups
    }

    func index(of nick: String?) -> Int? {
        nick.flatMap { positions[$0] }
    }

    /// Where ↑, ↓, Page Up, Page Down, Home or End go from `current`, with
    /// `page` rows to a page. Nil for other keys or an empty list.
    func target(_ key: NavigationKey, from current: Int?, page: Int) -> Int? {
        guard !nicks.isEmpty else { return nil }
        let last = nicks.count - 1
        guard let current else {
            switch key {
            case .up, .down, .pageUp, .pageDown, .home: return 0
            case .end: return last
            default: return nil
            }
        }
        switch key {
        case .up: return max(0, current - 1)
        case .down: return min(last, current + 1)
        case .pageUp: return max(0, current - page)
        case .pageDown: return min(last, current + page)
        case .home: return 0
        case .end: return last
        default: return nil
        }
    }
}

/// Marks where the highlighted row is, for its menu: only that row has one.
struct MemberMenuAnchor: NSViewRepresentable {
    let keyboard: MemberListKeyboard

    func makeNSView(context: Context) -> NSView {
        AnchorView(keyboard: keyboard)
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.window != nil { keyboard.menuAnchor = view }
    }

    /// The anchor while it's in the window: a row drawn again as the list
    /// scrolls can bring a new one in before the old one goes.
    private final class AnchorView: NSView {
        private weak var keyboard: MemberListKeyboard?

        init(keyboard: MemberListKeyboard) {
            self.keyboard = keyboard
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let keyboard else { return }
            if window != nil {
                keyboard.menuAnchor = self
            } else if keyboard.menuAnchor === self {
                keyboard.menuAnchor = nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }
    }
}
