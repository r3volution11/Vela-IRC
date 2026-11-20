// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaStore
@testable import VelaUI

/// Where the keys take the keyboard in the tab rows.
@MainActor
@Suite("Tab keyboard")
struct TabKeyboardTests {
    @Test func leftAndRightStopAtTheEnds() {
        #expect(TabActions.keyboardTarget(.right, from: 1, count: 4) == 2)
        #expect(TabActions.keyboardTarget(.right, from: 3, count: 4) == 3)
        #expect(TabActions.keyboardTarget(.left, from: 0, count: 4) == 0)
        #expect(TabActions.keyboardTarget(.home, from: 2, count: 4) == 0)
        #expect(TabActions.keyboardTarget(.end, from: 0, count: 4) == 3)
        // Nothing selected in the row: from the end it's going in from.
        #expect(TabActions.keyboardTarget(.right, from: nil, count: 4) == 0)
        #expect(TabActions.keyboardTarget(.left, from: nil, count: 4) == 3)
        #expect(TabActions.keyboardTarget(.up, from: 1, count: 4) == nil)
        #expect(TabActions.keyboardTarget(.right, from: nil, count: 0) == nil)
    }

    @Test func upAndDownFollowTheRowsOnScreen() {
        // Networks above channels at the top and in the title bar…
        for placement in [TabStackPlacement.top, .titleBar] {
            #expect(TabActions.keyboardRow(after: .channels, up: true, showsNetworks: true, placement: placement) == .networks)
            #expect(TabActions.keyboardRow(after: .networks, up: false, showsNetworks: true, placement: placement) == .channels)
            #expect(TabActions.keyboardRow(after: .channels, up: false, showsNetworks: true, placement: placement) == .channels)
        }
        // …and below them at the bottom.
        #expect(TabActions.keyboardRow(after: .channels, up: false, showsNetworks: true, placement: .bottom) == .networks)
        #expect(TabActions.keyboardRow(after: .channels, up: true, showsNetworks: true, placement: .bottom) == .channels)
        // One row: nowhere to go.
        #expect(TabActions.keyboardRow(after: .channels, up: true, showsNetworks: false, placement: .top) == .channels)
    }
}

extension LinkSelectionTests {
    /// The tab rows with the keyboard, in the main window: ⌥⌘1 (a request
    /// for `.navigation`) puts the keyboard on the selected tab, ← and →
    /// select as they go, and the new message box each one brings in
    /// leaves the focus with the tabs.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Tab keyboard, hosted", .serialized)
    struct TabKeyboardHostedTests {
        private func host(_ placement: TabStackPlacement, serverRow: ServerTabRowMode = .auto) async throws -> KeyboardHostedWindow {
            try await KeyboardHostedWindow.show { app in
                app.settings[.navigationStyle] = .tabs
                app.settings[.tabsPlacement] = placement
                app.settings[.tabsServerRow] = serverRow
            }
        }

        private func focusTabs(_ hosted: KeyboardHostedWindow) async throws {
            hosted.uiState.focus(.navigation)
            try await hosted.settle()
            #expect(hosted.focusedArea != nil, "\(String(describing: hosted.window.firstResponder))")
            #expect(hosted.uiState.focusedArea == .navigation)
            #expect(hosted.uiState.focusRequest == nil)
        }

        @Test(arguments: [TabStackPlacement.top, .bottom, .titleBar])
        func leftAndRightSelectTabsAndKeepTheFocus(placement: TabStackPlacement) async throws {
            let hosted = try await host(placement)
            defer { hosted.close() }
            #expect(hosted.selectedName == "#vela")
            #expect(try await hosted.waitForMessageBox())
            try await focusTabs(hosted)

            try await hosted.press(.right)
            #expect(hosted.selectedName == "#swift")
            // #swift's message box came in, and left the focus with the tabs.
            #expect(hosted.focusedArea != nil, "\(String(describing: hosted.window.firstResponder))")
            #expect(hosted.uiState.focusedArea == .navigation)
            try await hosted.press(.right)
            #expect(hosted.selectedName == "#macdev")
            try await hosted.press(.left)
            try await hosted.press(.left)
            try await hosted.press(.left)
            #expect(hosted.selectedName == "Libera.Chat")
            try await hosted.press(.left)
            #expect(hosted.selectedName == "Libera.Chat")
            try await hosted.press(.end)
            #expect(hosted.selectedName == "marisol")
            try await hosted.press(.home)
            #expect(hosted.selectedName == "Libera.Chat")
            #expect(hosted.focusedArea != nil)
        }

        @Test(arguments: [TabStackPlacement.top, .bottom, .titleBar])
        func upAndDownGoBetweenTheRows(placement: TabStackPlacement) async throws {
            let hosted = try await host(placement)
            defer { hosted.close() }
            try await focusTabs(hosted)
            // To the networks: above the channels, or below them at the bottom.
            try await hosted.press(placement == .bottom ? .down : .up)
            try await hosted.press(.right)
            #expect(hosted.app.selectedSession?.displayName == "OFTC")
            try await hosted.press(.right)
            #expect(hosted.app.selectedSession?.displayName == "Ergo Testnet")
            #expect(hosted.focusedArea != nil)
            // Back to the channels, of the network now selected.
            try await hosted.press(placement == .bottom ? .up : .down)
            let ergo = try hosted.session("Ergo Testnet")
            hosted.app.select(ergo.serverBuffer)
            try await hosted.settle()
            try await hosted.press(.right)
            #expect(hosted.selectedName == "#ergo")
            #expect(hosted.focusedArea != nil)
        }

        @Test func oneRowStaysOnTheChannels() async throws {
            let hosted = try await KeyboardHostedWindow.show { app in
                app.settings[.navigationStyle] = .tabs
                app.settings[.tabsPlacement] = .top
                app.settings[.tabsServerRow] = .auto
                // One network: no network row.
                for session in app.sessions.dropFirst() { app.removeNetwork(id: session.id) }
            }
            defer { hosted.close() }
            try await focusTabs(hosted)
            try await hosted.press(.up)
            try await hosted.press(.right)
            #expect(hosted.selectedName == "#swift")
        }

        @Test func returnAndEscapeGoToTheMessageBox() async throws {
            let hosted = try await host(.top)
            defer { hosted.close() }
            try await focusTabs(hosted)
            try await hosted.press(.right)
            try await hosted.press(.return)
            #expect(try await hosted.waitForMessageBox())
            #expect(hosted.selectedName == "#swift")
            try await hosted.settle()
            #expect(hosted.uiState.focusedArea == .messageBox)

            try await focusTabs(hosted)
            try await hosted.press(.escape)
            #expect(try await hosted.waitForMessageBox())
        }

        /// Clicking a tab goes to its message box, as it always has,
        /// whether or not the tabs had the keyboard focus.
        @Test func clickingATabGoesToItsMessageBox() async throws {
            let hosted = try await host(.top)
            defer { hosted.close() }
            try await focusTabs(hosted)
            try await hosted.click("#macdev")
            #expect(hosted.selectedName == "#macdev")
            #expect(try await hosted.waitForMessageBox(), "\(String(describing: hosted.window.firstResponder))")
        }
    }
}
