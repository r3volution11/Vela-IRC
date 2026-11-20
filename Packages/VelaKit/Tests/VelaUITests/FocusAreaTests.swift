// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import Testing
@testable import VelaUI

/// ⌥⌘1–⌥⌘4 and F6 / ⇧F6: moving the keyboard focus between the window's areas.
@MainActor
@Suite("Focus areas")
struct FocusAreaTests {
    @Test func whatThereIsToGoTo() {
        #expect(FocusAreas.available(hasBuffer: true, showsMembers: true) == [.navigation, .messages, .messageBox, .members])
        #expect(FocusAreas.available(hasBuffer: true, showsMembers: false) == [.navigation, .messages, .messageBox])
        #expect(FocusAreas.available(hasBuffer: false, showsMembers: true) == [.navigation])
    }

    @Test func f6GoesRoundInScreenOrder() {
        let all = FocusArea.allCases
        #expect(FocusAreas.adjacent(to: .navigation, forward: true, in: all) == .messages)
        #expect(FocusAreas.adjacent(to: .messageBox, forward: true, in: all) == .members)
        #expect(FocusAreas.adjacent(to: .members, forward: true, in: all) == .navigation)
        #expect(FocusAreas.adjacent(to: .navigation, forward: false, in: all) == .members)
        // From none of them, or from the member list after it's hidden.
        #expect(FocusAreas.adjacent(to: nil, forward: true, in: all) == .navigation)
        #expect(FocusAreas.adjacent(to: nil, forward: false, in: all) == .members)
        let noMembers: [FocusArea] = [.navigation, .messages, .messageBox]
        #expect(FocusAreas.adjacent(to: .messageBox, forward: true, in: noMembers) == .navigation)
        #expect(FocusAreas.adjacent(to: .members, forward: true, in: noMembers) == .navigation)
        #expect(FocusAreas.adjacent(to: .messages, forward: true, in: []) == nil)
    }

    @Test func requestsAreTakenOnceByTheirArea() {
        let state = UIState()
        let token = state.focusInputToken
        state.focus(.members)
        #expect(state.focusRequest?.area == .members)
        #expect(!state.takeFocusRequest(for: .messages))
        #expect(state.takeFocusRequest(for: .members))
        #expect(state.focusRequest == nil)
        #expect(!state.takeFocusRequest(for: .members))
        // The message box goes by ⌘L's token.
        state.focus(.messageBox)
        #expect(state.focusRequest == nil)
        #expect(state.focusInputToken == token &+ 1)
    }

    @Test func areasReportTheFocus() {
        let state = UIState()
        state.setFocused(.messages, true)
        #expect(state.focusedArea == .messages)
        state.setFocused(.messageBox, true)
        // A late "lost it" from the area before doesn't clear the new one.
        state.setFocused(.messages, false)
        #expect(state.focusedArea == .messageBox)
        state.setFocused(.messageBox, false)
        #expect(state.focusedArea == nil)
    }

    @Test func functionKeysShowByName() {
        #expect(ShortcutGlyphs.string(for: VelaCommandCatalog.Shortcuts.nextArea) == "F6")
        #expect(ShortcutGlyphs.string(for: VelaCommandCatalog.Shortcuts.previousArea) == "⇧F6")
        #expect(ShortcutGlyphs.string(for: VelaCommandCatalog.Shortcuts.focusMembers) == "⌥⌘4")
        #expect(ShortcutGlyphs.spoken(VelaCommandCatalog.Shortcuts.previousArea) == "Shift F6")
    }
}
