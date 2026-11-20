// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import SwiftUI
import Testing
@testable import VelaCore
@testable import VelaUI

/// The member list's keyboard highlight: where the keys take it, and that
/// moving it touches two rows, however long the list.
@MainActor
@Suite("Member list keyboard")
struct MemberListKeyboardTests {
    private func order(_ nicks: [String]) -> MemberListOrder {
        MemberListOrder(groups: [MemberGroup(id: "", title: "Members", members: nicks.map { Member(nick: $0) })])
    }

    @Test func keysMoveThroughTheList() {
        let order = order(["a", "b", "c", "d", "e", "f"])
        #expect(order.target(.down, from: 0, page: 3) == 1)
        #expect(order.target(.down, from: 5, page: 3) == 5)
        #expect(order.target(.up, from: 0, page: 3) == 0)
        #expect(order.target(.pageDown, from: 1, page: 3) == 4)
        #expect(order.target(.pageDown, from: 4, page: 3) == 5)
        #expect(order.target(.pageUp, from: 4, page: 3) == 1)
        #expect(order.target(.pageUp, from: 1, page: 3) == 0)
        #expect(order.target(.home, from: 3, page: 3) == 0)
        #expect(order.target(.end, from: 0, page: 3) == 5)
        // From no highlight: the first, or the last for End.
        #expect(order.target(.down, from: nil, page: 3) == 0)
        #expect(order.target(.end, from: nil, page: 3) == 5)
        #expect(order.target(.return, from: 2, page: 3) == nil)
        #expect(MemberListOrder(groups: []).target(.down, from: nil, page: 3) == nil)
        #expect(order.index(of: "c") == 2)
        #expect(order.index(of: "z") == nil)
    }

    /// Each row watches its own flag, so a move redraws two rows, not the
    /// thousands the list may have.
    @Test func movingTheHighlightTouchesTwoRows() {
        let keyboard = MemberListKeyboard()
        let nicks = (0..<3000).map { "user\($0)" }
        let flags = nicks.map { keyboard.flag(for: $0) }
        keyboard.highlight("user10")
        keyboard.setShowing(true)
        #expect(flags[10].isOn)

        // Told synchronously, on the main thread, by the mutation.
        nonisolated final class Changes: @unchecked Sendable {
            var nicks: [String] = []
        }
        let changes = Changes()
        for (nick, flag) in zip(nicks, flags) {
            withObservationTracking { _ = flag.isOn } onChange: { changes.nicks.append(nick) }
        }
        keyboard.highlight("user11")
        #expect(changes.nicks.sorted() == ["user10", "user11"])
        #expect(!flags[10].isOn && flags[11].isOn)

        // Losing the focus hides it; a row drawn later starts right.
        keyboard.setShowing(false)
        #expect(!flags[11].isOn)
        keyboard.setShowing(true)
        keyboard.highlight("user4000")
        #expect(keyboard.flag(for: "user4000").isOn)
        #expect(!keyboard.flag(for: "user11").isOn)
    }

    @Test func anotherChannelStartsOver() {
        let keyboard = MemberListKeyboard()
        keyboard.setShowing(true)
        keyboard.highlight("ada")
        let old = keyboard.flag(for: "ada")
        keyboard.reset()
        #expect(keyboard.highlighted == nil)
        #expect(keyboard.flag(for: "ada") !== old)
        #expect(!keyboard.flag(for: "ada").isOn)
    }
}

extension LinkSelectionTests {
    /// The member list with the keyboard, in the main window: ⌥⌘4 (a
    /// request for `.members`) highlights a member, the keys move the
    /// highlight, Return opens a conversation, Space the user menu, and
    /// typing filters. Demo content: in #vela, doug (you) owns it, kenji and
    /// marisol are ops, ada and theo voiced, then lukas, nadia, oskar_away,
    /// priya and wren.
    ///
    /// Menus are read as they're handed over to open, never opened: a real
    /// menu's tracking loop can end the test run. Nested in the serialized
    /// `LinkSelectionTests` with the other suites that use offscreen
    /// windows.
    @MainActor
    @Suite("Member list keyboard, hosted", .serialized)
    struct MemberListKeyboardHostedTests {
        private final class Menus {
            var shown: [NSMenu] = []
            /// What each opened under.
            var anchors: [NSView] = []
            var last: NSMenu? { shown.last }
            var titles: [String] { last?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? [] }

            /// The last menu opened under its row (not the list's top), with
            /// the row in view below the pinned section header.
            var openedUnderAVisibleRow: Bool {
                guard let anchor = anchors.last, !(anchor is KeyboardFocusView),
                      let clip = anchor.enclosingScrollView?.contentView else { return false }
                let row = anchor.convert(anchor.bounds, to: clip)
                var visible = clip.bounds
                visible.size.height -= 20
                if clip.isFlipped { visible.origin.y += 20 }
                return visible.minY <= row.minY && row.maxY <= visible.maxY
            }
        }

        /// The main window with the member list showing, and the menus the
        /// keyboard opens caught in `menus`.
        private func host(configure: (AppModel) -> Void = { _ in }) async throws -> (KeyboardHostedWindow, Menus) {
            let menus = Menus()
            MemberListKeyboard.presentMenu = { menu, anchor in
                menus.shown.append(menu)
                menus.anchors.append(anchor)
            }
            let hosted = try await KeyboardHostedWindow.show { app in
                app.settings[.memberListVisible] = true
                configure(app)
            }
            return (hosted, menus)
        }

        private func close(_ hosted: KeyboardHostedWindow) {
            hosted.close()
            MemberListKeyboard.presentMenu = { MemberListKeyboard.popUp($0, under: $1) }
        }

        private func focusMembers(_ hosted: KeyboardHostedWindow) async throws {
            hosted.uiState.focus(.members)
            try await hosted.settle()
            #expect(hosted.focusedArea != nil, "\(String(describing: hosted.window.firstResponder))")
            #expect(hosted.uiState.focusedArea == .members)
            #expect(hosted.uiState.focusRequest == nil)
        }

        /// Who's highlighted, by the menu Space opens for them.
        private func highlighted(_ hosted: KeyboardHostedWindow, _ menus: Menus) async throws -> String? {
            let count = menus.shown.count
            try await hosted.press(.space)
            return menus.shown.count > count ? menus.last?.title : nil
        }

        @Test func theKeysMoveTheHighlight() async throws {
            let (hosted, menus) = try await host()
            defer { close(hosted) }
            try await focusMembers(hosted)
            #expect(try await highlighted(hosted, menus) == "doug")
            try await hosted.press(.down)
            try await hosted.press(.down)
            #expect(try await highlighted(hosted, menus) == "marisol")
            try await hosted.press(.end)
            #expect(try await highlighted(hosted, menus) == "wren")
            try await hosted.press(.up)
            #expect(try await highlighted(hosted, menus) == "priya")
            try await hosted.press(.home)
            #expect(try await highlighted(hosted, menus) == "doug")
            // The whole list fits in a page.
            try await hosted.press(.pageDown)
            #expect(try await highlighted(hosted, menus) == "wren")
            try await hosted.press(.pageUp)
            #expect(try await highlighted(hosted, menus) == "doug")
            // Nothing moved the selection or the focus.
            #expect(hosted.selectedName == "#vela")
            #expect(hosted.focusedArea != nil)
        }

        @Test func spaceOpensTheUserMenu() async throws {
            let (hosted, menus) = try await host()
            defer { close(hosted) }
            try await focusMembers(hosted)
            try await hosted.press(.down)
            try await hosted.press(.down)
            try await hosted.press(.space)
            // The menu right-clicking marisol's row opens: doug owns #vela.
            #expect(menus.last?.title == "marisol")
            #expect(Array(menus.titles.prefix(5)) == ["Message", "Mention", "Whois", "Ping", "CTCP"], "\(menus.titles)")
            for item in ["Deop", "Kick", "Ban", "Ignore"] {
                #expect(menus.titles.contains(item), "\(item): \(menus.titles)")
            }
            // ⇧F10 too.
            try await hosted.press(.down)
            try await hosted.press(.shiftF10)
            #expect(menus.last?.title == "ada")
            // Its items work: Message opens the conversation.
            let menu = try #require(menus.last)
            menu.performActionForItem(at: menu.indexOfItem(withTitle: "Message"))
            try await hosted.settle()
            #expect(hosted.selectedName == "ada")
        }

        @Test func returnOpensAConversation() async throws {
            let (hosted, _) = try await host()
            defer { close(hosted) }
            try await focusMembers(hosted)
            // Not with yourself.
            try await hosted.press(.return)
            #expect(hosted.selectedName == "#vela")
            try await hosted.press(.down)
            try await hosted.press(.return)
            #expect(hosted.selectedName == "kenji")
            // The member list went with the channel; the conversation's
            // message box has the focus.
            #expect(try await hosted.waitForMessageBox(), "\(String(describing: hosted.window.firstResponder))")
        }

        @Test func typingFiltersAndDownComesBack() async throws {
            let (hosted, menus) = try await host()
            defer { close(hosted) }
            try await focusMembers(hosted)
            try await hosted.press(.text("ma"))
            #expect(hosted.fieldEditorHasFocus, "\(String(describing: hosted.window.firstResponder))")
            #expect((hosted.window.firstResponder as? NSTextView)?.string == "ma")
            #expect(hosted.uiState.focusedArea == .members)
            // ↓ goes back into the list, on the one match.
            try await hosted.press(.down)
            #expect(hosted.focusedArea != nil, "\(String(describing: hosted.window.firstResponder))")
            #expect(try await highlighted(hosted, menus) == "marisol")
            // Esc clears the filter and stays; again goes to the message box.
            try await hosted.press(.escape)
            #expect(hosted.focusedArea != nil)
            #expect(try await highlighted(hosted, menus) == "marisol")
            try await hosted.press(.escape)
            #expect(try await hosted.waitForMessageBox())
        }

        @Test func escapeInTheFilter() async throws {
            let (hosted, _) = try await host()
            defer { close(hosted) }
            try await focusMembers(hosted)
            try await hosted.press(.text("w"))
            #expect(hosted.fieldEditorHasFocus)
            try await hosted.press(.escape)
            #expect((hosted.window.firstResponder as? NSTextView)?.string == "")
            #expect(hosted.fieldEditorHasFocus)
            try await hosted.press(.escape)
            #expect(try await hosted.waitForMessageBox())
        }

        @Test func theHighlightStaysWhereItWas() async throws {
            let (hosted, menus) = try await host()
            defer { close(hosted) }
            try await focusMembers(hosted)
            try await hosted.press(.end)
            try await hosted.press(.escape)
            #expect(try await hosted.waitForMessageBox())
            try await focusMembers(hosted)
            #expect(try await highlighted(hosted, menus) == "wren")
        }

        /// ⌥⌘4 shows a hidden list first; it takes the focus as it appears.
        @Test func aHiddenListShowsAndTakesTheFocus() async throws {
            let (hosted, menus) = try await host { app in
                app.settings[.memberListVisible] = false
            }
            defer { close(hosted) }
            hosted.app.settings[.memberListVisible] = true
            hosted.uiState.focus(.members)
            try await hosted.settle()
            #expect(hosted.focusedArea != nil, "\(String(describing: hosted.window.firstResponder))")
            #expect(hosted.uiState.focusedArea == .members)
            #expect(try await highlighted(hosted, menus) == "doug")
        }

        /// A channel of thousands: the keys go to the end and back, and the
        /// highlight's row is drawn (and its menu opens under it) wherever
        /// it is.
        @Test func aBigChannel() async throws {
            let (hosted, menus) = try await host { app in
                guard let vela = app.sessions.first?.buffer(named: "#vela") else { return }
                var members: [String: Member] = [:]
                for index in 0..<5000 {
                    let nick = String(format: "guest%04d", index)
                    members[nick] = Member(nick: nick)
                }
                vela.replaceMembers(members)
            }
            defer { close(hosted) }
            try await focusMembers(hosted)
            #expect(try await highlighted(hosted, menus) == "guest0000")
            #expect(menus.openedUnderAVisibleRow)
            // Down past the bottom of the view (about 26 rows): the list follows.
            for _ in 0..<32 { try await hosted.press(.down, after: 0.01) }
            #expect(try await highlighted(hosted, menus) == "guest0032")
            #expect(menus.openedUnderAVisibleRow)
            try await hosted.press(.end)
            #expect(try await highlighted(hosted, menus) == "guest4999")
            #expect(menus.openedUnderAVisibleRow)
            // Up past the top, clear of the pinned section header.
            for _ in 0..<32 { try await hosted.press(.up, after: 0.01) }
            #expect(try await highlighted(hosted, menus) == "guest4967")
            #expect(menus.openedUnderAVisibleRow)
            try await hosted.press(.pageUp)
            let paged = try #require(try await highlighted(hosted, menus))
            #expect(paged < "guest4950", "\(paged)")
            #expect(menus.openedUnderAVisibleRow)
            try await hosted.press(.home)
            #expect(try await highlighted(hosted, menus) == "guest0000")
            #expect(menus.openedUnderAVisibleRow)
        }
    }
}
