// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
@testable import VelaUI

/// Moving through the sidebar with the keyboard: the rows, what each key
/// does, and type-select. Demo content: Libera.Chat (#vela, #swift,
/// #macdev, #media, #vela-offtopic and a conversation with marisol), OFTC
/// (#debian) and Ergo Testnet (#ergo).
@MainActor
@Suite("Sidebar keyboard")
struct SidebarKeyboardTests {
    private let app = AppModel.demo()

    private func names(_ rows: [SidebarKeyboard.Row]) -> [String] {
        rows.map { $0.names.last ?? "" }
    }

    private func id(_ name: String) throws -> BufferID {
        if let session = app.sessions.first(where: { $0.displayName == name }) { return session.serverBuffer.id }
        for session in app.sessions {
            if let buffer = session.buffer(named: name) { return buffer.id }
        }
        throw Missing(name: name)
    }

    private struct Missing: Error {
        let name: String
    }

    @Test func rowsAreTheSidebarsInOrder() throws {
        let rows = SidebarKeyboard.rows(in: app, collapsed: NetworkIDSet())
        #expect(names(rows) == [
            "Libera.Chat", "#vela", "#swift", "#macdev", "#media", "#vela-offtopic", "marisol",
            "OFTC", "#debian", "Ergo Testnet", "#ergo",
        ])
        #expect(rows.filter(\.isHeader).count == 3)
        // Channels match with or without their #.
        #expect(rows[1].names == ["vela", "#vela"])
        #expect(rows[6].names == ["marisol"])
    }

    @Test func aFoldedNetworkShowsOnlyItsHeader() throws {
        let libera = try #require(app.sessions.first)
        let collapsed = NetworkIDSet([libera.id])
        let rows = SidebarKeyboard.rows(in: app, collapsed: collapsed)
        #expect(names(rows) == ["Libera.Chat", "OFTC", "#debian", "Ergo Testnet", "#ergo"])
        // The keyboard is on the header of a folded network's channel.
        #expect(SidebarKeyboard.cursor(selected: try id("#swift"), in: app, collapsed: collapsed) == libera.serverBuffer.id)
        #expect(SidebarKeyboard.cursor(selected: try id("#swift"), in: app, collapsed: NetworkIDSet()) == (try id("#swift")))
        #expect(SidebarKeyboard.cursor(selected: nil, in: app, collapsed: collapsed) == nil)
    }

    private func action(_ key: NavigationKey, from name: String?, collapsed: NetworkIDSet = NetworkIDSet()) throws -> SidebarKeyboard.Action? {
        let rows = SidebarKeyboard.rows(in: app, collapsed: collapsed)
        let cursor = try name.map { name in try #require(rows.firstIndex { $0.id == (try id(name)) }) }
        var typeSelect = TypeSelect()
        return SidebarKeyboard.action(for: key, rows: rows, cursor: cursor, collapsed: collapsed, typeSelect: &typeSelect, time: 0)
    }

    @Test func upAndDownSelectAsTheyGo() throws {
        #expect(try action(.down, from: "#vela") == .select(try id("#swift")))
        #expect(try action(.up, from: "#vela") == .select(try id("Libera.Chat")))
        #expect(try action(.down, from: "marisol") == .select(try id("OFTC")))
        // At the ends, nothing (and no beep).
        #expect(try action(.up, from: "Libera.Chat") == .nothing)
        #expect(try action(.down, from: "#ergo") == .nothing)
        #expect(try action(.home, from: "#debian") == .select(try id("Libera.Chat")))
        #expect(try action(.end, from: "#debian") == .select(try id("#ergo")))
        // With nothing selected, the first or the last.
        #expect(try action(.down, from: nil) == .select(try id("Libera.Chat")))
        #expect(try action(.up, from: nil) == .select(try id("#ergo")))
    }

    @Test func leftAndRightFoldNetworksLikeAnOutline() throws {
        let libera = try #require(app.sessions.first)
        // A channel: out to its network.
        #expect(try action(.left, from: "#swift") == .select(libera.serverBuffer.id))
        // The network: fold it, then unfold it.
        #expect(try action(.left, from: "Libera.Chat") == .collapse(libera.id))
        let folded = NetworkIDSet([libera.id])
        #expect(try action(.left, from: "Libera.Chat", collapsed: folded) == .nothing)
        #expect(try action(.right, from: "Libera.Chat", collapsed: folded) == .expand(libera.id))
        #expect(try action(.right, from: "Libera.Chat") == .nothing)
        #expect(try action(.right, from: "#swift") == .nothing)
    }

    @Test func returnAndEscapeGoToTheMessageBox() throws {
        #expect(try action(.return, from: "#swift") == .focusMessageBox)
        #expect(try action(.escape, from: "OFTC") == .focusMessageBox)
        // Nothing selected: no message box.
        #expect(try action(.return, from: nil) == nil)
        #expect(try action(.space, from: "#swift") == nil)
    }

    @Test func typingGoesToTheNextNameStartingWithIt() throws {
        let rows = SidebarKeyboard.rows(in: app, collapsed: NetworkIDSet())
        var typeSelect = TypeSelect()
        func type(_ text: String, at time: TimeInterval, from name: String) throws -> String? {
            let cursor = rows.firstIndex { $0.id == (try? id(name)) }
            let action = SidebarKeyboard.action(for: .text(text), rows: rows, cursor: cursor, collapsed: NetworkIDSet(), typeSelect: &typeSelect, time: time)
            guard case .select(let selected) = action else { return nil }
            return rows.first { $0.id == selected }?.names.last
        }
        #expect(try type("s", at: 0, from: "#vela") == "#swift")
        // Again, a while later: the next one with an m.
        #expect(try type("m", at: 5, from: "#swift") == "#macdev")
        #expect(try type("m", at: 5.2, from: "#macdev") == "#media")
        #expect(try type("m", at: 5.4, from: "#media") == "marisol")
        // Letters typed together add up, and stay on a name that fits.
        #expect(try type("v", at: 10, from: "marisol") == "#vela")
        #expect(try type("e", at: 10.2, from: "#vela") == nil)
        #expect(try type("l", at: 10.4, from: "#vela") == nil)
        #expect(try type("a", at: 10.6, from: "#vela") == nil)
        #expect(try type("-", at: 10.8, from: "#vela") == "#vela-offtopic")
        // Networks by name, and the # typed too.
        #expect(try type("o", at: 20, from: "#vela-offtopic") == "OFTC")
        #expect(try type("#", at: 30, from: "OFTC") == "#debian")
        #expect(try type("e", at: 30.1, from: "#debian") == "#ergo")
        // Wraps around; nothing that fits stays put.
        #expect(try type("l", at: 40, from: "#ergo") == "Libera.Chat")
        #expect(try type("q", at: 50, from: "Libera.Chat") == nil)
    }

    @Test func typeSelectStartsOverAfterASecond() {
        var typeSelect = TypeSelect()
        typeSelect.type("a", at: 1)
        typeSelect.type("b", at: 1.5)
        #expect(typeSelect.typed == "ab")
        typeSelect.type("c", at: 2.6)
        #expect(typeSelect.typed == "c")
        typeSelect.reset()
        typeSelect.type("d", at: 2.7)
        #expect(typeSelect.typed == "d")
    }

    @Test func keysAsAppKitSendsThem() throws {
        func key(_ characters: String, code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) throws -> NavigationKey? {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
            ))
            return NavigationKey(event)
        }
        #expect(try key("\u{F701}", code: 125, [.numericPad, .function]) == .down)
        #expect(try key("\u{F702}", code: 123, [.numericPad, .function]) == .left)
        #expect(try key("\r", code: 36) == .return)
        #expect(try key("\u{3}", code: 76) == .return)
        #expect(try key("\u{1B}", code: 53) == .escape)
        #expect(try key(" ", code: 49) == .space)
        #expect(try key("v", code: 9) == .text("v"))
        #expect(try key("V", code: 9, .shift) == .text("V"))
        #expect(try key("\u{F70D}", code: 109, [.shift, .function]) == .menu)
        #expect(try key("\u{10}", code: 110, .function) == .menu)
        // Other commands' keys go on to them.
        #expect(try key("\u{F701}", code: 125, [.option, .command, .numericPad, .function]) == nil)
        #expect(try key("1", code: 18, .command) == nil)
        #expect(try key("\u{F709}", code: 97, .function) == nil)
        #expect(try key("\u{F70D}", code: 109, .function) == nil)
        #expect(try key("\t", code: 48) == nil)
    }
}

extension LinkSelectionTests {
    /// The sidebar and the rail with the keyboard, in the main window: ⌥⌘1
    /// (a request for `.navigation`) gives the sidebar the focus, the keys
    /// select as they go, and the new message box each one brings in leaves
    /// the focus where it is.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Sidebar keyboard, hosted", .serialized)
    struct SidebarKeyboardHostedTests {
        private func focusSidebar(_ hosted: KeyboardHostedWindow) async throws {
            hosted.uiState.focus(.navigation)
            try await hosted.settle()
            #expect(hosted.focusedArea != nil, "\(String(describing: hosted.window.firstResponder))")
            #expect(hosted.uiState.focusedArea == .navigation)
            #expect(hosted.uiState.focusRequest == nil)
        }

        @Test func arrowsSelectAndKeepTheFocus() async throws {
            let hosted = try await KeyboardHostedWindow.show()
            defer { hosted.close() }
            #expect(hosted.selectedName == "#vela")
            #expect(try await hosted.waitForMessageBox())
            try await focusSidebar(hosted)

            try await hosted.press(.down)
            #expect(hosted.selectedName == "#swift")
            // #swift's message box came in and left the focus here.
            #expect(hosted.focusedArea != nil, "\(String(describing: hosted.window.firstResponder))")
            #expect(hosted.uiState.focusedArea == .navigation)

            try await hosted.press(.down)
            try await hosted.press(.down)
            #expect(hosted.selectedName == "#media")
            try await hosted.press(.up)
            try await hosted.press(.up)
            try await hosted.press(.up)
            #expect(hosted.selectedName == "#vela")
            try await hosted.press(.up)
            #expect(hosted.selectedName == "Libera.Chat")
            try await hosted.press(.up)
            #expect(hosted.selectedName == "Libera.Chat")
            try await hosted.press(.end)
            #expect(hosted.selectedName == "#ergo")
            #expect(hosted.focusedArea != nil)
        }

        @Test func leftAndRightFoldANetwork() async throws {
            let hosted = try await KeyboardHostedWindow.show()
            defer { hosted.close() }
            let libera = try hosted.session("Libera.Chat")
            hosted.app.select(try #require(libera.buffer(named: "#swift")))
            try await hosted.settle()
            try await focusSidebar(hosted)

            try await hosted.press(.left)
            #expect(hosted.selectedName == "Libera.Chat")
            try await hosted.press(.left)
            #expect(NetworkIDSet(rawValue: UserDefaults.standard.string(forKey: SidebarMetrics.collapsedNetworksKey) ?? "")?.contains(libera.id) == true)
            // Folded: down goes straight to the next network.
            try await hosted.press(.down)
            #expect(hosted.selectedName == "OFTC")
            try await hosted.press(.up)
            try await hosted.press(.right)
            #expect(NetworkIDSet(rawValue: UserDefaults.standard.string(forKey: SidebarMetrics.collapsedNetworksKey) ?? "")?.contains(libera.id) == false)
            try await hosted.press(.down)
            #expect(hosted.selectedName == "#vela")
            #expect(hosted.focusedArea != nil)
        }

        @Test func typingGoesToAChannel() async throws {
            let hosted = try await KeyboardHostedWindow.show()
            defer { hosted.close() }
            try await focusSidebar(hosted)
            try await hosted.press(.text("sw"))
            #expect(hosted.selectedName == "#swift")
            try await hosted.press(.text("de"), after: 2)
            #expect(hosted.selectedName == "#debian")
            try await hosted.press(.text("m"), after: 2)
            #expect(hosted.selectedName == "#macdev")
            try await hosted.press(.text("m"), after: 2)
            #expect(hosted.selectedName == "#media")
            #expect(hosted.focusedArea != nil)
        }

        @Test func returnAndEscapeGoToTheMessageBox() async throws {
            let hosted = try await KeyboardHostedWindow.show()
            defer { hosted.close() }
            try await focusSidebar(hosted)
            try await hosted.press(.down)
            try await hosted.press(.return)
            #expect(try await hosted.waitForMessageBox())
            #expect(hosted.selectedName == "#swift")
            try await hosted.settle()
            #expect(hosted.uiState.focusedArea == .messageBox)

            try await focusSidebar(hosted)
            try await hosted.press(.escape)
            #expect(try await hosted.waitForMessageBox())
        }

        @Test func theRailWorksTheSame() async throws {
            let hosted = try await KeyboardHostedWindow.show { app in
                app.settings[.sidebarCollapsed] = true
            }
            defer { hosted.close() }
            try await focusSidebar(hosted)
            try await hosted.press(.text("o"))
            #expect(hosted.selectedName == "OFTC")
            try await hosted.press(.text("m"), after: 2)
            #expect(hosted.selectedName == "#macdev")
            try await hosted.press(.down)
            #expect(hosted.selectedName == "#media")
            #expect(hosted.focusedArea != nil)
            try await hosted.press(.return)
            #expect(try await hosted.waitForMessageBox())
        }

        /// Clicking a channel goes to its message box, as it always has,
        /// whether or not the sidebar had the keyboard focus.
        @Test func clickingAChannelGoesToItsMessageBox() async throws {
            let hosted = try await KeyboardHostedWindow.show()
            defer { hosted.close() }
            try await hosted.click("#swift")
            #expect(hosted.selectedName == "#swift")
            #expect(try await hosted.waitForMessageBox())

            try await focusSidebar(hosted)
            try await hosted.click("#macdev")
            #expect(hosted.selectedName == "#macdev")
            #expect(try await hosted.waitForMessageBox(), "\(String(describing: hosted.window.firstResponder))")
        }

        @Test func theFocusStaysAsTheSidebarCollapses() async throws {
            let hosted = try await KeyboardHostedWindow.show()
            defer { hosted.close() }
            try await focusSidebar(hosted)
            hosted.app.settings[.sidebarCollapsed] = true
            try await hosted.settle()
            #expect(hosted.focusedArea != nil)
            try await hosted.press(.down)
            #expect(hosted.selectedName == "#swift")
        }
    }
}
