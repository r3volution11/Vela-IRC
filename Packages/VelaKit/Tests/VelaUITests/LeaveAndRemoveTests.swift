// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore
@testable import VelaUI

/// What a tab's ×, the menus and the palette do to channels and
/// conversations, the confirmations and their settings, Recently Closed in
/// menus and the palette, and ⌘Z in the message box after a close.
@MainActor
@Suite("Leave, Remove and Recently Closed")
struct LeaveAndRemoveTests {
    private func demo() throws -> (app: AppModel, libera: NetworkSession, uiState: UIState) {
        let app = AppModel.demo()
        let libera = try #require(app.sessions.first { $0.displayName == "Libera.Chat" })
        return (app, libera, UIState())
    }

    private func feed(_ session: NetworkSession, _ line: String) {
        session.handle(.message(IRCMessage(line: line)!, batch: nil))
    }

    // MARK: A tab's ×

    @Test func theXLeavesAChannelYoureInAndRemovesOneYouLeft() throws {
        let (app, libera, uiState) = try demo()
        app.settings[.channelsConfirmLeave] = false
        app.settings[.channelsConfirmRemove] = false
        let vela = try #require(libera.buffer(named: "#vela"))
        #expect(ChannelActions.closeAction(for: vela, in: libera) == .leave)
        #expect(TabDescriptions.closeAction(vela, in: libera) == "Leave Channel")

        TabActions.close(vela, app: app, uiState: uiState)
        feed(libera, ":doug!d@host PART #vela")
        #expect(libera.buffer(named: "#vela") === vela)
        #expect(!vela.isJoined)
        #expect(app.recentlyClosed.isEmpty)
        // Dimmed now: its × removes it.
        #expect(TabDescriptions.closeAction(vela, in: libera) == "Remove Channel")
        TabActions.close(vela, app: app, uiState: uiState)
        #expect(libera.buffer(named: "#vela") == nil)
        #expect(app.recentlyClosed.map(\.name) == ["#vela"])

        // A conversation closes, never asking.
        app.settings[.channelsConfirmRemove] = true
        let marisol = try #require(libera.buffer(named: "marisol"))
        #expect(TabDescriptions.closeAction(marisol, in: libera) == "Close Conversation")
        TabActions.close(marisol, app: app, uiState: uiState)
        #expect(uiState.channelConfirmation == nil)
        #expect(app.recentlyClosed.map(\.name) == ["marisol", "#vela"])
    }

    @Test func offlineTheXLeavesAChannelYoudRejoin() throws {
        let app = AppModel.demo()
        let oftc = try #require(app.sessions.first { $0.displayName == "OFTC" })
        let channel = try #require(oftc.channels.first)
        #expect(!oftc.isConnected)
        #expect(ChannelActions.closeAction(for: channel, in: oftc) == .leave)
        oftc.leave(channel)
        #expect(ChannelActions.closeAction(for: channel, in: oftc) == .remove)
    }

    // MARK: Confirmations

    @Test func leavingAndRemovingAskWhileTheirSettingsAreOn() throws {
        let (app, libera, uiState) = try demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        #expect(app.settings[.channelsConfirmLeave])
        #expect(app.settings[.channelsConfirmRemove])

        ChannelActions.leave(vela, app: app, uiState: uiState)
        let leave = try #require(uiState.channelConfirmation)
        #expect(leave.action == .leave)
        #expect(leave.bufferID == vela.id)
        #expect(libera.rejoins(vela))
        #expect(ChannelActions.question(for: leave, app: app) == "Leave #vela?")

        ChannelActions.remove(vela, app: app, uiState: uiState)
        let remove = try #require(uiState.channelConfirmation)
        #expect(remove.action == .remove)
        #expect(ChannelActions.question(for: remove, app: app) == "Remove #vela?")
        #expect(ChannelActions.explanation(for: remove, app: app).contains("Libera.Chat's channels"))
        #expect(libera.buffer(named: "#vela") === vela)

        // Turned off, they happen straight away.
        uiState.channelConfirmation = nil
        app.settings[.channelsConfirmLeave] = false
        ChannelActions.leave(vela, app: app, uiState: uiState)
        #expect(uiState.channelConfirmation == nil)
        #expect(!libera.rejoins(vela))
        app.settings[.channelsConfirmRemove] = false
        ChannelActions.remove(vela, app: app, uiState: uiState)
        #expect(uiState.channelConfirmation == nil)
        #expect(libera.buffer(named: "#vela") == nil)
    }

    @Test func confirmingDoesItAndDontAskAgainTurnsTheSettingOff() throws {
        let (app, libera, uiState) = try demo()
        let swift = try #require(libera.buffer(named: "#swift"))
        ChannelActions.leave(swift, app: app, uiState: uiState)
        ChannelActions.confirm(try #require(uiState.channelConfirmation), dontAskAgain: false, app: app)
        #expect(!libera.rejoins(swift))
        #expect(app.settings[.channelsConfirmLeave])

        ChannelActions.remove(swift, app: app, uiState: uiState)
        ChannelActions.confirm(try #require(uiState.channelConfirmation), dontAskAgain: true, app: app)
        #expect(libera.buffer(named: "#swift") == nil)
        #expect(!app.settings[.channelsConfirmRemove])
        #expect(app.settings[.channelsConfirmLeave])
    }

    @Test func theQuestionMentionsTheBouncer() throws {
        let (app, libera, _) = try demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        #expect(!ChannelActions.explanation(for: ChannelConfirmation(.leave, bufferID: vela.id), app: app).contains("bouncer"))
        libera.config.bouncerKind = .znc
        #expect(ChannelActions.explanation(for: ChannelConfirmation(.leave, bufferID: vela.id), app: app).contains("your bouncer leaves it too"))
        #expect(ChannelActions.explanation(for: ChannelConfirmation(.remove, bufferID: vela.id), app: app).contains("your bouncer leaves it"))
    }

    // MARK: Menus and the palette

    @Test func paletteCommandsFollowTheChannel() throws {
        let (app, libera, uiState) = try demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        let titles = { (buffer: BufferModel) in
            VelaCommandCatalog.membershipCommands(buffer: buffer, session: libera, app: app, uiState: uiState).map(\.paletteTitle)
        }
        #expect(titles(vela) == ["Channel: Leave #vela", "Channel: Remove #vela"])
        feed(libera, ":doug!d@host PART #vela")
        #expect(titles(vela) == ["Channel: Join #vela", "Channel: Remove #vela"])
        #expect(titles(try #require(libera.buffer(named: "marisol"))) == ["Buffer: Close"])

        // Remove from the palette asks too.
        let remove = try #require(VelaCommandCatalog.membershipCommands(buffer: vela, session: libera, app: app, uiState: uiState).last)
        remove.perform()
        #expect(uiState.channelConfirmation?.action == .remove)
    }

    @Test func recentlyClosedInTheMenuAndPalette() throws {
        let (app, libera, _) = try demo()
        var reopen = VelaCommandCatalog.reopenClosed(app: app)
        #expect(!reopen.isEnabled)
        #expect(reopen.shortcut == VelaCommandCatalog.Shortcuts.reopenClosed)
        #expect(VelaCommandCatalog.recentlyClosedCommands(app: app).isEmpty)

        app.close(try #require(libera.buffer(named: "#swift")))
        app.close(try #require(libera.buffer(named: "marisol")))
        reopen = VelaCommandCatalog.reopenClosed(app: app)
        #expect(reopen.isEnabled)
        #expect(reopen.resolvedMenuTitle == "Reopen Closed Conversation")
        #expect(reopen.paletteTitle == "Buffer: Reopen Closed Channel")
        let items = VelaCommandCatalog.recentlyClosedCommands(app: app)
        #expect(items.map(\.resolvedMenuTitle) == ["marisol — Libera.Chat", "#swift — Libera.Chat"])
        #expect(items.map(\.paletteTitle) == ["Buffer: Reopen marisol (Libera.Chat)", "Buffer: Reopen #swift (Libera.Chat)"])

        items[1].perform()
        #expect(app.selectedBuffer?.name == "#swift")
        reopen = VelaCommandCatalog.reopenClosed(app: app)
        reopen.perform()
        #expect(app.selectedBuffer?.name == "marisol")
        #expect(!VelaCommandCatalog.reopenClosed(app: app).isEnabled)
    }

    // MARK: ⌘Z in the message box

    /// The message box's undo manager, as the window gives it.
    private final class UndoSource: NSObject, NSTextViewDelegate {
        let undoManager: UndoManager
        init(_ undoManager: UndoManager) { self.undoManager = undoManager }
        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }
    }

    /// Typing, then removing a channel, then typing again: ⌘Z undoes the
    /// later typing, then the remove, then the earlier typing, as a Mac
    /// app's one undo stack does. Redo goes forward the same way.
    @Test func undoInTheMessageBoxStacksWithClosing() throws {
        let (app, libera, _) = try demo()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        app.undoManager = undoManager
        let source = UndoSource(undoManager)
        let textView = ComposerNSTextView(usingTextLayoutManager: false)
        textView.allowsUndo = true
        textView.delegate = source
        func type(_ text: String) {
            for character in text {
                undoManager.beginUndoGrouping()
                textView.insertText(String(character), replacementRange: textView.selectedRange())
                undoManager.endUndoGrouping()
            }
        }
        let swift = try #require(libera.buffer(named: "#swift"))

        type("hello")
        undoManager.beginUndoGrouping()
        app.close(swift)
        undoManager.endUndoGrouping()
        type(" world")
        #expect(textView.string == "hello world")
        #expect(libera.buffer(named: "#swift") == nil)

        // The typing since the remove first…
        var steps = 0
        while textView.string != "hello", steps < 20 {
            #expect(undoManager.undoMenuItemTitle != "Undo Remove Channel")
            undoManager.undo()
            steps += 1
        }
        #expect(textView.string == "hello")
        #expect(libera.buffer(named: "#swift") == nil)
        // …then the remove…
        #expect(undoManager.undoMenuItemTitle == "Undo Remove Channel")
        undoManager.undo()
        #expect(libera.buffer(named: "#swift") != nil)
        #expect(textView.string == "hello")
        // …then the typing before it.
        while textView.string != "", undoManager.canUndo, steps < 40 {
            undoManager.undo()
            steps += 1
        }
        #expect(textView.string == "")
        #expect(libera.buffer(named: "#swift") != nil)

        // Redo comes back the same way.
        while textView.string != "hello", undoManager.canRedo, steps < 60 {
            undoManager.redo()
            steps += 1
        }
        #expect(undoManager.redoMenuItemTitle == "Redo Remove Channel")
        undoManager.redo()
        #expect(libera.buffer(named: "#swift") == nil)
        #expect(textView.string == "hello")
        while undoManager.canRedo, steps < 80 {
            undoManager.redo()
            steps += 1
        }
        #expect(textView.string == "hello world")
        #expect(libera.buffer(named: "#swift") == nil)
    }
}
