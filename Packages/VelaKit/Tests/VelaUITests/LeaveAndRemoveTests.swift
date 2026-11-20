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

    /// Without a bouncer, a tab's × leaves and removes a channel in one go,
    /// asking as Remove Channel… does.
    @Test func theXLeavesAndRemovesAChannel() throws {
        let (app, libera, uiState) = try demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        #expect(ChannelActions.closeAction(for: vela, in: libera, app: app) == .remove)
        #expect(TabDescriptions.closeAction(vela, in: libera, app: app) == "Remove Channel")

        TabActions.close(vela, app: app, uiState: uiState)
        #expect(uiState.channelConfirmation?.action == .remove)
        #expect(libera.buffer(named: "#vela") === vela)
        uiState.channelConfirmation = nil
        app.settings[.channelsConfirmRemove] = false
        TabActions.close(vela, app: app, uiState: uiState)
        #expect(libera.buffer(named: "#vela") == nil)
        #expect(app.recentlyClosed.map(\.name) == ["#vela"])

        // One you've left goes the same way.
        let swift = try #require(libera.buffer(named: "#swift"))
        feed(libera, ":doug!d@host PART #swift")
        #expect(TabDescriptions.closeAction(swift, in: libera, app: app) == "Remove Channel")
        TabActions.close(swift, app: app, uiState: uiState)
        #expect(libera.buffer(named: "#swift") == nil)

        // A conversation closes, never asking.
        app.settings[.channelsConfirmRemove] = true
        let marisol = try #require(libera.buffer(named: "marisol"))
        #expect(TabDescriptions.closeAction(marisol, in: libera, app: app) == "Close Conversation")
        TabActions.close(marisol, app: app, uiState: uiState)
        #expect(uiState.channelConfirmation == nil)
        #expect(app.recentlyClosed.map(\.name) == ["marisol", "#swift", "#vela"])
    }

    /// Through a bouncer, a tab's × leaves a channel only in Vela (the
    /// bouncer stays in it, detached), asking as Leave Channel does. A second
    /// × hides it.
    @Test func throughABouncerTheXDetachesThenHides() throws {
        let (app, libera, uiState) = try demo()
        libera.config.bouncerKind = .znc
        let vela = try #require(libera.buffer(named: "#vela"))
        #expect(ChannelActions.closeAction(for: vela, in: libera, app: app) == .detach)
        #expect(TabDescriptions.closeAction(vela, in: libera, app: app) == "Leave Channel")

        TabActions.close(vela, app: app, uiState: uiState)
        let request = try #require(uiState.channelConfirmation)
        #expect(request.action == .detach)
        #expect(ChannelActions.question(for: request, app: app) == "Leave #vela?")
        #expect(ChannelActions.explanation(for: request, app: app) == "Your bouncer stays in the channel and keeps its history; join it again to catch up.")
        #expect(ChannelActions.confirmTitle(request.action) == "Leave")
        ChannelActions.confirm(request, dontAskAgain: false, app: app)
        uiState.channelConfirmation = nil
        // ZNC's answer.
        feed(libera, ":doug!d@host PART #vela")
        #expect(vela.isDetached)
        #expect(libera.buffer(named: "#vela") === vela)
        #expect(app.recentlyClosed.isEmpty)
        #expect(TabDescriptions.bufferValue(vela, in: libera).hasSuffix("detached"))

        // Detached: the × hides it, without asking.
        #expect(ChannelActions.closeAction(for: vela, in: libera, app: app) == .hide)
        #expect(TabDescriptions.closeAction(vela, in: libera, app: app) == "Hide Channel")
        TabActions.close(vela, app: app, uiState: uiState)
        #expect(uiState.channelConfirmation == nil)
        #expect(libera.buffer(named: "#vela") == nil)
        #expect(libera.hiddenChannels.map(\.name) == ["#vela"])

        // One the bouncer isn't in (kicked) is removed.
        let swift = try #require(libera.buffer(named: "#swift"))
        feed(libera, ":op!o@host KICK #swift doug :bye")
        #expect(ChannelActions.closeAction(for: swift, in: libera, app: app) == .remove)
    }

    /// `channels.bouncerCloseRemoves`: through a bouncer, the × removes,
    /// so the bouncer forgets the channel too.
    @Test func closingCanRemoveFromTheBouncer() throws {
        let (app, libera, uiState) = try demo()
        libera.config.bouncerKind = .soju
        #expect(!app.settings[.channelsBouncerCloseRemoves])
        app.settings[.channelsBouncerCloseRemoves] = true
        let vela = try #require(libera.buffer(named: "#vela"))
        #expect(ChannelActions.closeAction(for: vela, in: libera, app: app) == .remove)
        #expect(TabDescriptions.closeAction(vela, in: libera, app: app) == "Remove Channel")
        feed(libera, ":doug!d@host PART #vela :Detach")
        #expect(vela.isDetached)
        #expect(ChannelActions.closeAction(for: vela, in: libera, app: app) == .remove)

        TabActions.close(vela, app: app, uiState: uiState)
        let request = try #require(uiState.channelConfirmation)
        #expect(request.action == .remove)
        #expect(ChannelActions.explanation(for: request, app: app).hasPrefix("Your bouncer leaves it too and forgets it"))
        ChannelActions.confirm(request, dontAskAgain: false, app: app)
        #expect(libera.buffer(named: "#vela") == nil)
        #expect(libera.hiddenChannels.isEmpty)
        // Leave Channel in the menu still detaches.
        let swift = try #require(libera.buffer(named: "#swift"))
        app.settings[.channelsConfirmLeave] = false
        ChannelActions.leave(swift, app: app, uiState: uiState)
        feed(libera, ":doug!d@host PART #swift :Detach")
        #expect(swift.isDetached)
        #expect(libera.buffer(named: "#swift") === swift)
    }

    /// Offline, a bouncer's channel detaches at once (the bouncer hears of
    /// it after the next connection), and then hides.
    @Test func offlineTheXDetachesABouncerChannel() throws {
        let app = AppModel.demo()
        app.settings[.channelsConfirmLeave] = false
        let oftc = try #require(app.sessions.first { $0.displayName == "OFTC" })
        oftc.config.bouncerKind = .znc
        let channel = try #require(oftc.channels.first)
        #expect(!oftc.isConnected)
        #expect(ChannelActions.closeAction(for: channel, in: oftc, app: app) == .detach)
        TabActions.close(channel, app: app, uiState: UIState())
        #expect(channel.isDetached)
        #expect(oftc.config.pendingDetaches == [channel.name])
        #expect(ChannelActions.closeAction(for: channel, in: oftc, app: app) == .hide)
        // Without a bouncer, offline, the × removes.
        oftc.config.bouncerKind = .none
        #expect(ChannelActions.closeAction(for: try #require(oftc.channels.last), in: oftc, app: app) == .remove)
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
        #expect(ChannelActions.explanation(for: leave, app: app) == "You'll stop receiving its messages, and Vela won't join it when you connect. It stays in the list so you can join it again.")

        ChannelActions.remove(vela, app: app, uiState: uiState)
        let remove = try #require(uiState.channelConfirmation)
        #expect(remove.action == .remove)
        #expect(ChannelActions.question(for: remove, app: app) == "Remove #vela?")
        #expect(ChannelActions.explanation(for: remove, app: app) == "It's taken out of the list and Libera.Chat's channels. File → Recently Closed brings it back.")
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

    /// The questions say what happens on each kind of network.
    @Test func theQuestionsFitTheNetwork() throws {
        let (app, libera, uiState) = try demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        #expect(!ChannelActions.explanation(for: ChannelConfirmation(.leave, bufferID: vela.id), app: app).contains("bouncer"))
        #expect(!ChannelActions.explanation(for: ChannelConfirmation(.remove, bufferID: vela.id), app: app).contains("bouncer"))
        for kind in [BouncerKind.znc, .soju] {
            libera.config.bouncerKind = kind
            // Leave Channel detaches, and asks so.
            ChannelActions.leave(vela, app: app, uiState: uiState)
            let leave = try #require(uiState.channelConfirmation)
            #expect(leave.action == .detach)
            #expect(ChannelActions.question(for: leave, app: app) == "Leave #vela?")
            #expect(ChannelActions.explanation(for: leave, app: app) == "Your bouncer stays in the channel and keeps its history; join it again to catch up.")
            ChannelActions.remove(vela, app: app, uiState: uiState)
            let remove = try #require(uiState.channelConfirmation)
            #expect(ChannelActions.question(for: remove, app: app) == "Remove #vela?")
            #expect(ChannelActions.explanation(for: remove, app: app) == "Your bouncer leaves it too and forgets it, and it's taken out of the list and Libera.Chat's channels. File → Recently Closed brings it back.")
            uiState.channelConfirmation = nil
        }
    }

    /// Confirming a detach, with Don't ask again, turns off asking before
    /// leaving.
    @Test func dontAskAgainOnADetach() throws {
        let (app, libera, uiState) = try demo()
        libera.config.bouncerKind = .znc
        let swift = try #require(libera.buffer(named: "#swift"))
        ChannelActions.leave(swift, app: app, uiState: uiState)
        ChannelActions.confirm(try #require(uiState.channelConfirmation), dontAskAgain: true, app: app)
        #expect(!app.settings[.channelsConfirmLeave])
        #expect(app.settings[.channelsConfirmRemove])
        #expect(libera.detachRequests[swift.id.foldedName] != nil)
        // Leaving through a bouncer never parts the channel.
        #expect(libera.rejoins(swift))
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

        // A detached bouncer channel can be hidden.
        libera.config.bouncerKind = .soju
        let swift = try #require(libera.buffer(named: "#swift"))
        feed(libera, ":doug!d@host PART #swift :Detach")
        #expect(titles(swift) == ["Channel: Join #swift", "Channel: Hide #swift", "Channel: Remove #swift"])
        let hide = try #require(VelaCommandCatalog.membershipCommands(buffer: swift, session: libera, app: app, uiState: uiState).first { $0.id == "channel.hide" })
        hide.perform()
        #expect(libera.buffer(named: "#swift") == nil)
    }

    /// Each hidden channel has "Show #x (Network)" in the palette, once.
    @Test func hiddenChannelsInThePalette() throws {
        let (app, libera, _) = try demo()
        libera.config.bouncerKind = .znc
        let vela = try #require(libera.buffer(named: "#vela"))
        app.detach(vela)
        feed(libera, ":doug!d@host PART #vela")
        app.hide(vela)
        let show = { VelaCommandCatalog.recentlyClosedCommands(app: app) + VelaCommandCatalog.hiddenChannelCommands(app: app) }
        // Hidden this run: its Recently Closed command is the one.
        #expect(show().map(\.paletteTitle) == ["Channel: Show #vela (Libera.Chat)"])
        #expect(show().first?.resolvedMenuTitle == "#vela — Libera.Chat")
        // After a relaunch, from the hidden list.
        app.recentlyClosed = []
        let commands = show()
        #expect(commands.map(\.paletteTitle) == ["Channel: Show #vela (Libera.Chat)"])
        try #require(commands.first).perform()
        let shown = try #require(libera.buffer(named: "#vela"))
        #expect(shown.isDetached)
        #expect(app.selectedBuffer === shown)
        #expect(show().isEmpty)
    }

    /// Join Channel on a channel left without a bouncer puts its auto-join
    /// entry back.
    @Test func joinChannelPutsTheEntryBack() throws {
        let (app, libera, uiState) = try demo()
        app.settings[.channelsConfirmLeave] = false
        libera.config.autoJoin = [AutoJoinChannel(name: "#vela"), AutoJoinChannel(name: "#swift")]
        let vela = try #require(libera.buffer(named: "#vela"))
        ChannelActions.leave(vela, app: app, uiState: uiState)
        feed(libera, ":doug!d@host PART #vela")
        #expect(libera.config.autoJoin.map(\.name) == ["#swift"])
        ChannelActions.join(vela, app: app)
        #expect(libera.config.autoJoin.map(\.name) == ["#vela", "#swift"])
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
