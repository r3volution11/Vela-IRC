// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
@testable import VelaCore
import VelaIntelligence
import VelaMedia
import VelaStore
import VelaTheme
@testable import VelaUI

extension LinkSelectionTests {
    /// The messages from the keyboard, and the message box scrolling them:
    /// the chat column hosted as in the window (`ChatColumnView`) in an
    /// offscreen window, driven with key events as AppKit delivers them.
    ///
    /// Menus are caught as they'd open (`MessageListController.menuPresenter`),
    /// links as they'd open, and copies land on a pasteboard of the test's
    /// own: a real menu would open on screen and run its own event loop.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that send events to offscreen windows.
    @MainActor
    @Suite("Messages from the keyboard", .serialized)
    struct MessageKeyboardHostedTests {
        private final class Caught {
            var menus: [NSMenu] = []
            var links: [URL] = []
            var beeps = 0
        }

        private final class Hosted {
            let app: AppModel
            let uiState: UIState
            let services: SceneServices
            let buffer: BufferModel
            let lines: Lines
            let window: NSWindow
            let host: NSView
            let caught = Caught()
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("app.vela.tests.keyboard.\(UUID().uuidString)"))

            init(app: AppModel, uiState: UIState, services: SceneServices, buffer: BufferModel, lines: Lines, window: NSWindow, host: NSView) {
                self.app = app
                self.uiState = uiState
                self.services = services
                self.buffer = buffer
                self.lines = lines
                self.window = window
                self.host = host
            }

            var keyView: MessageKeyView? {
                MessageKeyboardHostedTests.findAll(in: host) { $0 is MessageKeyView }.first as? MessageKeyView
            }

            var controller: MessageListController? { keyView?.handler?.controller }

            var composer: ComposerNSTextView? {
                MessageKeyboardHostedTests.findAll(in: host) { $0 is ComposerNSTextView }.first as? ComposerNSTextView
            }

            var selectedID: DisplayItemID? { controller?.selection?.id }

            func close() {
                pasteboard.releaseGlobally()
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        /// The lines the tests act on, oldest first, after a long history
        /// with a run of joins early on.
        private struct Lines {
            var earlyJoins: [ChatLine]
            var oneLink: ChatLine
            var twoLinks: ChatLine
            var joins: [ChatLine]
            var mode: ChatLine
            var spanish: ChatLine
            var newest: ChatLine
        }

        private static var lineNumber = 0

        private static func line(_ nick: String, _ text: String, at time: Date, kind: ChatLineKind = .message) -> ChatLine {
            lineNumber += 1
            return ChatLine(msgid: "keys-\(lineNumber)", time: time, kind: kind, nick: nick, userHost: "\(nick)@user/\(nick)", text: text, isHistory: true)
        }

        private func host(history: Int = 120) async throws -> Hosted {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaKeys-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let app = AppModel(
                settings: SettingsStore(fileURL: root.appendingPathComponent("settings.json")),
                networkStore: NetworkConfigStore(fileURL: root.appendingPathComponent("networks.json")),
                database: nil,
                isDemo: true
            )
            DemoContent.populate(app)
            // Nothing fetched or shown under the messages.
            app.settings[.mediaShowLinkCards] = false
            app.settings[.mediaAutoLoad] = false
            let session = try #require(app.sessions.first)
            let buffer = session.ensureBuffer(name: "##keys", kind: .channel, persist: false)
            buffer.isJoined = true
            let start = Date().addingTimeInterval(-Double(history + 20) * 30)
            func at(_ index: Int) -> Date { start.addingTimeInterval(Double(index) * 30) }
            var all = (0..<history).map { index in
                Self.line(["ann", "bob", "cy", "dee"][index % 4], "message number \(index)", at: at(index))
            }
            let lines = Lines(
                earlyJoins: [
                    Self.line("hal", "hal (hal@user/hal) joined", at: at(30).addingTimeInterval(10), kind: .join),
                    Self.line("ivy", "ivy (ivy@user/ivy) joined", at: at(30).addingTimeInterval(20), kind: .join),
                ],
                oneLink: Self.line("ann", "notes at https://example.com/one for later", at: at(history)),
                twoLinks: Self.line("bob", "compare https://example.com/two with https://example.org/three", at: at(history + 1)),
                joins: [
                    Self.line("fay", "fay (fay@user/fay) joined", at: at(history + 2), kind: .join),
                    Self.line("gus", "gus (gus@user/gus) joined", at: at(history + 3), kind: .join),
                ],
                mode: Self.line("ChanServ", "ChanServ sets mode +v fay", at: at(history + 4), kind: .mode),
                spanish: Self.line("marisol", "¡Qué envidia! Aquí en Madrid el cielo estaba despejado, pero no se veía nada.", at: at(history + 5)),
                newest: Self.line("wren", "the newest message", at: at(history + 6))
            )
            all += lines.earlyJoins + [lines.oneLink, lines.twoLinks] + lines.joins + [lines.mode, lines.spanish, lines.newest]
            buffer.insertSorted(all)
            app.select(buffer)

            let size = CGSize(width: 900, height: 640)
            let themeStore = ThemeStore(userThemesDirectory: root.appendingPathComponent("Themes"))
            let uiState = UIState()
            let services = SceneServices(intelligence: .demo())
            let view = ChatColumnView()
                .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFrontRegardless()
            let hosted = Hosted(app: app, uiState: uiState, services: services, buffer: buffer, lines: lines, window: window, host: host)
            try await settle(hosted, for: 500)
            let controller = try #require(hosted.controller)
            controller.pasteboard = hosted.pasteboard
            controller.menuPresenter = { [caught = hosted.caught] (menu: NSMenu, _: NSPoint, _: NSView) in caught.menus.append(menu) }
            controller.linkOpener = { [caught = hosted.caught] url in caught.links.append(url) }
            controller.beep = { [caught = hosted.caught] in caught.beeps += 1 }
            return hosted
        }

        fileprivate static func findAll(in view: NSView, where matches: (NSView) -> Bool) -> [NSView] {
            (matches(view) ? [view] : []) + view.subviews.flatMap { findAll(in: $0, where: matches) }
        }

        private func settle(_ hosted: Hosted, for milliseconds: Int = 120) async throws {
            try await Task.sleep(for: .milliseconds(milliseconds / 2))
            hosted.host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(milliseconds / 2))
        }

        // MARK: Keys

        private enum Key {
            case up, down, pageUp, pageDown, home, end, returnKey, space, escape
            case character(String, keyCode: UInt16)
            case command(String, keyCode: UInt16)

            static let r = character("r", keyCode: 15)
            static let e = character("e", keyCode: 14)
            static let c = character("c", keyCode: 8)
            static let u = character("u", keyCode: 32)
            static let t = character("t", keyCode: 17)
            static let x = character("x", keyCode: 7)
            static let commandC = command("c", keyCode: 8)

            private static func function(_ key: Int) -> String { String(Character(UnicodeScalar(UInt32(key))!)) }

            var event: (characters: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
                switch self {
                case .up: (Self.function(NSUpArrowFunctionKey), [.function, .numericPad], 126)
                case .down: (Self.function(NSDownArrowFunctionKey), [.function, .numericPad], 125)
                case .pageUp: (Self.function(NSPageUpFunctionKey), .function, 116)
                case .pageDown: (Self.function(NSPageDownFunctionKey), .function, 121)
                case .home: (Self.function(NSHomeFunctionKey), .function, 115)
                case .end: (Self.function(NSEndFunctionKey), .function, 119)
                case .returnKey: ("\r", [], 36)
                case .space: (" ", [], 49)
                case .escape: ("\u{1b}", [], 53)
                case .character(let text, let keyCode): (text, [], keyCode)
                case .command(let text, let keyCode): (text, .command, keyCode)
                }
            }
        }

        /// Presses `key` in the window, as the keyboard would.
        private func press(_ key: Key, in hosted: Hosted, settling milliseconds: Int = 120) async throws {
            let (characters, modifiers, keyCode) = key.event
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosted.window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode
            ))
            hosted.window.sendEvent(event)
            try await settle(hosted, for: milliseconds)
        }

        private func focusMessages(_ hosted: Hosted) async throws {
            hosted.uiState.focus(.messages)
            try await settle(hosted, for: 200)
        }

        private func select(_ id: DisplayItemID, in hosted: Hosted, from start: Key = .up) async throws {
            for _ in 0..<12 where hosted.selectedID != id {
                try await press(start, in: hosted)
            }
            #expect(hosted.selectedID == id)
        }

        /// The selected row is laid out and all of it is in view.
        private static func showsWhole(_ controller: MessageListController) -> Bool {
            controller.selectedRowScrollDistance().map { abs($0) <= 0.5 } ?? false
        }

        /// Whether the selected row comes into view whole within a second
        /// (longer than it takes, for a machine busy with other tests).
        private func comesIntoViewWhole(_ controller: MessageListController) async throws -> Bool {
            for _ in 0..<20 {
                if Self.showsWhole(controller) { return true }
                try await Task.sleep(for: .milliseconds(50))
            }
            return Self.showsWhole(controller)
        }

        // MARK: Focus and moving

        @Test func takesTheFocusAndSelectsTheNewestMessage() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let keyView = try #require(hosted.keyView)
            #expect(hosted.window.firstResponder !== keyView)
            try await focusMessages(hosted)
            #expect(hosted.window.firstResponder === keyView)
            #expect(hosted.uiState.focusedArea == .messages)
            #expect(hosted.uiState.focusRequest == nil)
            #expect(hosted.selectedID == .line(hosted.lines.newest.id))
            // The selected row is drawn as selected, in view.
            let controller = try #require(hosted.controller)
            #expect(controller.selectedRowView != nil)
            #expect(try await comesIntoViewWhole(controller), "\(String(describing: controller.selectedRowScrollDistance()))")
        }

        /// The focus is reported as it moves, not a turn later: a message
        /// box that appears meanwhile (after switching channels) must see
        /// that the messages have it. The selection is there at once too.
        @Test func reportsTheFocusAtOnce() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let keyView = try #require(hosted.keyView)
            let composer = try #require(hosted.composer)
            hosted.window.makeFirstResponder(keyView)
            #expect(hosted.uiState.focusedArea == .messages)
            #expect(hosted.selectedID == .line(hosted.lines.newest.id))
            hosted.window.makeFirstResponder(composer)
            #expect(hosted.uiState.focusedArea != .messages)
            // The selection goes on the next turn.
            try await settle(hosted)
            #expect(hosted.selectedID == nil)
        }

        @Test func arrowsSkipEventsAndSelectRuns() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await focusMessages(hosted)
            let lines = hosted.lines
            try await press(.up, in: hosted)
            // Past nothing: the Spanish message is just above.
            #expect(hosted.selectedID == .line(lines.spanish.id))
            try await press(.up, in: hosted)
            // Past the mode change, to the run of joins.
            #expect(hosted.selectedID == .membershipRun(lines.joins[0].id))
            try await press(.up, in: hosted)
            #expect(hosted.selectedID == .line(lines.twoLinks.id))
            try await press(.down, in: hosted)
            try await press(.down, in: hosted)
            #expect(hosted.selectedID == .line(lines.spanish.id))
            // Return on the run shows its events, and again hides them.
            try await press(.up, in: hosted)
            let controller = try #require(hosted.controller)
            try await press(.returnKey, in: hosted)
            #expect(controller.expandedRuns.contains(lines.joins[0].id))
            try await press(.returnKey, in: hosted)
            #expect(!controller.expandedRuns.contains(lines.joins[0].id))
            // ↓ at the newest stays there.
            try await press(.end, in: hosted)
            try await press(.down, in: hosted)
            #expect(hosted.selectedID == .line(lines.newest.id))
        }

        @Test func homeEndAndPagesMoveAndKeepTheSelectionInView() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await focusMessages(hosted)
            let controller = try #require(hosted.controller)
            let items = controller.displayCache.items
            let newest = try #require(MessageSelection.newest(in: items))
            try await press(.pageUp, in: hosted, settling: 300)
            let afterPage = try #require(controller.selectedItem?.index)
            // A page: more than one row, fewer than all of them.
            let moved = (afterPage..<newest).count(where: { MessageSelection.isSelectable(items[$0]) })
            #expect(moved > 3 && moved < 40, "moved \(moved) rows")
            #expect(controller.selectedRowView != nil)
            #expect(try await comesIntoViewWhole(controller), "\(String(describing: controller.selectedRowScrollDistance()))")
            // Off the bottom, the list no longer follows new lines.
            #expect(!controller.isPinnedToBottom)
            try await press(.home, in: hosted, settling: 500)
            let oldest = try #require(MessageSelection.oldest(in: items))
            #expect(controller.selectedItem?.index == oldest)
            #expect(controller.selectedRowView != nil)
            #expect(try await comesIntoViewWhole(controller), "\(String(describing: controller.selectedRowScrollDistance()))")
            try await press(.down, in: hosted)
            #expect(controller.selectedItem?.index == MessageSelection.step(from: oldest, by: 1, in: items))
            try await press(.pageDown, in: hosted, settling: 300)
            #expect(controller.selectedRowView != nil)
            #expect(try await comesIntoViewWhole(controller), "\(String(describing: controller.selectedRowScrollDistance()))")
            try await press(.end, in: hosted, settling: 600)
            #expect(hosted.selectedID == .line(hosted.lines.newest.id))
            #expect(controller.isPinnedToBottom)
            #expect(try await comesIntoViewWhole(controller), "\(String(describing: controller.selectedRowScrollDistance()))")
        }

        /// A run of joins just above the top of the list comes into view
        /// whole when the selection reaches it, and so does each message
        /// on the way, going up and coming back down.
        @Test func rowsComeIntoViewWholeOneAtATime() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await focusMessages(hosted)
            let controller = try #require(hosted.controller)
            let run = DisplayItemID.membershipRun(hosted.lines.earlyJoins[0].id)
            var presses = 0
            while hosted.selectedID != run, presses < 140 {
                try await press(.up, in: hosted, settling: 40)
                presses += 1
                let whole = try await comesIntoViewWhole(controller)
                #expect(whole, "press \(presses): \(String(describing: controller.selectedRowScrollDistance()))")
            }
            #expect(hosted.selectedID == run)
            let runWhole = try await comesIntoViewWhole(controller)
            #expect(runWhole, "\(String(describing: controller.selectedRowScrollDistance()))")
            // Back down past it, then up onto it again.
            for _ in 0..<10 { try await press(.down, in: hosted, settling: 80) }
            let downWhole = try await comesIntoViewWhole(controller)
            #expect(downWhole, "\(String(describing: controller.selectedRowScrollDistance()))")
            try await select(run, in: hosted)
            let againWhole = try await comesIntoViewWhole(controller)
            #expect(againWhole, "\(String(describing: controller.selectedRowScrollDistance()))")
        }

        @Test func scrolledUpItSelectsTheLowestMessageInView() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let composer = try #require(hosted.composer)
            hosted.window.makeFirstResponder(composer)
            try await press(.pageUp, in: hosted, settling: 300)
            try await press(.pageUp, in: hosted, settling: 500)
            let controller = try #require(hosted.controller)
            #expect(!controller.isPinnedToBottom)
            try await focusMessages(hosted)
            let selected = try #require(controller.selectedItem)
            #expect(MessageSelection.isMessage(selected.item))
            // In view, near the bottom of it: nothing in view below it is a message.
            #expect(controller.visibleIDs.contains(selected.item.id))
            let below = controller.visibleIDs.drop { $0 != selected.item.id }.dropFirst()
            let items = controller.displayCache.items
            #expect(below.allSatisfy { id in
                guard let index = MessageSelection.index(of: id, in: items) else { return true }
                return !MessageSelection.isMessage(items[index])
            }, "\(below)")
            #expect(hosted.selectedID != .line(hosted.lines.newest.id))
        }

        // MARK: Acting

        @Test func rRepliesAndGoesToTheMessageBox() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await focusMessages(hosted)
            try await press(.up, in: hosted)
            try await press(.r, in: hosted, settling: 300)
            #expect(hosted.uiState.replyTargets[hosted.buffer.id]?.id == hosted.lines.spanish.id)
            #expect(hosted.window.firstResponder === hosted.composer)
            #expect(hosted.uiState.focusedArea == .messageBox)
            // The selection goes with the focus.
            #expect(hosted.selectedID == nil)
        }

        @Test func cAndCommandCCopyTheText() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await focusMessages(hosted)
            try await press(.c, in: hosted)
            #expect(hosted.pasteboard.string(forType: .string) == "the newest message")
            try await press(.up, in: hosted)
            try await press(.commandC, in: hosted)
            #expect(hosted.pasteboard.string(forType: .string) == hosted.lines.spanish.text)
            // Edit → Copy is on for a message.
            let keyView = try #require(hosted.keyView)
            let copy = NSMenuItem(title: "Copy", action: #selector(MessageKeyView.copy(_:)), keyEquivalent: "c")
            #expect(keyView.validateMenuItem(copy))
            // Not for a run of joins, which has nothing to copy.
            try await press(.up, in: hosted)
            #expect(!keyView.validateMenuItem(copy))
            try await press(.c, in: hosted)
            #expect(hosted.caught.beeps == 1)
        }

        @Test func returnOpensTheLinkOrAMenuOfThem() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await focusMessages(hosted)
            // No link: nothing to open.
            try await press(.returnKey, in: hosted)
            #expect(hosted.caught.beeps == 1)
            #expect(hosted.caught.links.isEmpty)
            try await select(.line(hosted.lines.twoLinks.id), in: hosted)
            try await press(.returnKey, in: hosted)
            let menu = try #require(hosted.caught.menus.last)
            #expect(menu.items.map(\.title) == ["https://example.com/two", "https://example.org/three"])
            menu.performActionForItem(at: 1)
            #expect(hosted.caught.links == [URL(string: "https://example.org/three")!])
            try await press(.up, in: hosted)
            try await press(.returnKey, in: hosted)
            #expect(hosted.caught.links.last == URL(string: "https://example.com/one")!)
            #expect(hosted.caught.menus.count == 1)
        }

        @Test func uOpensTheSendersMenu() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await focusMessages(hosted)
            try await press(.up, in: hosted)
            try await press(.u, in: hosted)
            let menu = try #require(hosted.caught.menus.last)
            #expect(menu.title == "marisol")
            let items = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
            #expect(Array(items.prefix(3)) == ["Message", "Mention", "Whois"], "\(items)")
            #expect(items.contains("Copy Nick"))
            // Its items work: Mention puts the nick in the message box.
            menu.performActionForItem(at: menu.indexOfItem(withTitle: "Mention"))
            try await settle(hosted, for: 300)
            #expect(hosted.composer?.string == "marisol: ")
            #expect(hosted.window.firstResponder === hosted.composer)
            // Kept as the draft too, so it's what gets sent.
            #expect(hosted.uiState.drafts[hosted.buffer.id] == "marisol: ")
        }

        /// A mention from a user menu while the message box doesn't have
        /// the focus (the messages or the member list do) lands in it. It
        /// used to show for a moment, then vanish.
        @Test func aMentionReachesAMessageBoxWithoutTheFocus() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            hosted.window.makeFirstResponder(nil)
            try await settle(hosted)
            hosted.uiState.mentionRequest = MentionRequest(bufferID: hosted.buffer.id, nick: "kenji")
            try await settle(hosted, for: 600)
            #expect(hosted.composer?.string == "kenji: ")
            #expect(hosted.uiState.drafts[hosted.buffer.id] == "kenji: ")
            #expect(hosted.window.firstResponder === hosted.composer)
        }

        @Test func spaceOpensTheMessagesOwnMenu() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await focusMessages(hosted)
            try await press(.up, in: hosted)
            try await press(.space, in: hosted)
            let menu = try #require(hosted.caught.menus.last)
            let items = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
            #expect(Array(items.prefix(2)) == ["Add Reaction", "Reply"], "\(items)")
            for item in ["Translate", "Copy Text", "Copy Nick", "Whois marisol"] {
                #expect(items.contains(item), "\(item): \(items)")
            }
            // The same menu a right-click opens: its items work.
            menu.performActionForItem(at: menu.indexOfItem(withTitle: "Copy Text"))
            #expect(hosted.pasteboard.string(forType: .string) == hosted.lines.spanish.text)
        }

        @Test func tTranslatesAndAgainHides() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await focusMessages(hosted)
            try await press(.up, in: hosted)
            let store = hosted.services.translations
            let id = hosted.lines.spanish.id
            try await press(.t, in: hosted)
            #expect(store.state(for: id)?.isShowing == true)
            for _ in 0..<40 {
                if case .translated = store.state(for: id) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            if case .translated(let text, _) = store.state(for: id) {
                #expect(text == CannedTranslator.demoTranslations[hosted.lines.spanish.text])
            } else {
                Issue.record("not translated: \(String(describing: store.state(for: id)))")
            }
            try await press(.t, in: hosted)
            #expect(store.state(for: id)?.isShowing != true)
            // The newest message is in English already: nothing to do.
            try await press(.down, in: hosted)
            try await press(.t, in: hosted)
            #expect(hosted.caught.beeps == 1)
        }

        @Test func eOpensTheReactionPicker() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            try await focusMessages(hosted)
            try await press(.e, in: hosted, settling: 600)
            let popovers = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) && $0.isVisible && $0 !== hosted.window }
            #expect(!popovers.isEmpty, "no picker opened")
            let texts = popovers.flatMap { window in
                window.contentView.map { Self.findAll(in: $0) { $0 is NSTextField } } ?? []
            }
            #expect(!texts.isEmpty, "no search field in \(popovers)")
            for window in popovers { window.orderOut(nil) }
        }

        @Test func escAndTypingGoBackToTheMessageBox() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let composer = try #require(hosted.composer)
            try await focusMessages(hosted)
            try await press(.escape, in: hosted, settling: 300)
            #expect(hosted.window.firstResponder === composer)
            #expect(hosted.uiState.focusedArea == .messageBox)
            #expect(hosted.selectedID == nil)
            try await focusMessages(hosted)
            #expect(hosted.selectedID == .line(hosted.lines.newest.id))
            try await press(.x, in: hosted, settling: 300)
            #expect(hosted.window.firstResponder === composer)
            #expect(composer.string == "x")
        }

        @Test func switchingChannelsKeepsTheFocusOnTheMessages() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            try await focusMessages(hosted)
            let session = try #require(hosted.app.sessions.first)
            let other = try #require(session.buffer(named: "#vela"))
            hosted.app.select(other)
            try await settle(hosted, for: 500)
            let keyView = try #require(hosted.keyView)
            #expect(hosted.window.firstResponder === keyView)
            #expect(hosted.uiState.focusedArea == .messages)
            #expect(keyView.handler?.controller.buffer === other)
            #expect(keyView.handler?.controller.selection != nil)
        }

        // MARK: VoiceOver

        @Test func voiceOverReadsTheSelectionAndOffersItsActions() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let keyView = try #require(hosted.keyView)
            // Not an element of its own until it has the focus.
            #expect(!keyView.isAccessibilityElement())
            try await focusMessages(hosted)
            try await press(.up, in: hosted)
            #expect(keyView.isAccessibilityElement())
            let value = try #require(keyView.accessibilityValue() as? String)
            #expect(value.hasPrefix("marisol, "), "\(value)")
            #expect(value.contains("¡Qué envidia!"), "\(value)")
            let actions = try #require(keyView.accessibilityCustomActions())
            #expect(actions.map(\.name) == [
                "Reply", "Add Reaction", "Copy Text", "Actions for marisol…", "Translate", "Show Menu",
            ])
            // They do what the keys do.
            let copy = try #require(actions.first { $0.name == "Copy Text" })
            #expect(copy.handler?() == true)
            #expect(hosted.pasteboard.string(forType: .string) == hosted.lines.spanish.text)
            // A run says whether its events show.
            try await press(.up, in: hosted)
            #expect((keyView.accessibilityValue() as? String)?.hasSuffix(", collapsed") == true)
            #expect(keyView.accessibilityCustomActions()?.map(\.name) == ["Show or Hide Events"])
        }

        /// The message's own VoiceOver element (its text) has Add Reaction,
        /// which opens its reaction picker.
        @Test func aMessageOffersAddReactionToVoiceOver() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
            NSApp.perform(enhancedInterface, with: NSNumber(value: true))
            defer { NSApp.perform(enhancedInterface, with: NSNumber(value: false)) }
            try await settle(hosted, for: 300)
            var message: AnyObject?
            func visit(_ object: AnyObject) {
                guard message == nil else { return }
                if let label = object.accessibilityLabel?() ?? nil, label.hasPrefix("wren, "), label.contains("the newest message") {
                    message = object
                    return
                }
                for child in (object.accessibilityChildren?() ?? nil) ?? [] { visit(child as AnyObject) }
            }
            visit(hosted.window)
            let element = try #require(message, "no element for the newest message")
            let actions = (element.accessibilityCustomActions?() ?? nil) ?? []
            let names = actions.map(\.name)
            #expect(names.contains("Reply"), "\(names)")
            let react = try #require(actions.first { $0.name == "Add Reaction" }, "\(names)")
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            _ = react.handler?()
            try await settle(hosted, for: 600)
            let popovers = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) && $0.isVisible && $0 !== hosted.window }
            #expect(!popovers.isEmpty, "no picker opened")
            for window in popovers { window.orderOut(nil) }
        }

        // MARK: The message box

        private func scrollOffset(_ hosted: Hosted) throws -> CGFloat {
            try #require(hosted.controller?.metrics?.visibleMinY)
        }

        @Test func pageKeysInTheMessageBoxScrollTheMessages() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let composer = try #require(hosted.composer)
            hosted.window.makeFirstResponder(composer)
            composer.string = "half a thought"
            let controller = try #require(hosted.controller)
            #expect(controller.isPinnedToBottom)
            let bottom = try scrollOffset(hosted)
            let height = try #require(controller.metrics?.containerHeight)
            try await press(.pageUp, in: hosted, settling: 600)
            let up = try scrollOffset(hosted)
            // A page, less a little.
            #expect(abs((bottom - up) - KeyboardPaging.distance(containerHeight: height)) < 2, "moved \(bottom - up) of \(height)")
            #expect(!controller.isPinnedToBottom)
            #expect(controller.showsJumpToPresent)
            // The text and the focus stay.
            #expect(composer.string == "half a thought")
            #expect(hosted.window.firstResponder === composer)
            try await press(.pageDown, in: hosted, settling: 800)
            #expect(controller.isPinnedToBottom)
            #expect(abs(try scrollOffset(hosted) - bottom) < 2)
            try await press(.home, in: hosted, settling: 800)
            #expect(try scrollOffset(hosted) < 600)
            try await press(.end, in: hosted, settling: 1200)
            #expect(controller.isPinnedToBottom)
            #expect(controller.metrics.map(ScrollPinning.isAtBottom) == true)
        }

        @Test func escWithNothingToCancelJumpsToThePresent() async throws {
            let hosted = try await host()
            defer { hosted.close() }
            let composer = try #require(hosted.composer)
            hosted.window.makeFirstResponder(composer)
            let controller = try #require(hosted.controller)
            try await press(.pageUp, in: hosted, settling: 300)
            try await press(.pageUp, in: hosted, settling: 600)
            #expect(!controller.isPinnedToBottom)
            let scrolledTo = try scrollOffset(hosted)
            // A reply to cancel: Esc cancels it, and the list stays.
            hosted.uiState.replyTargets[hosted.buffer.id] = hosted.lines.newest
            try await settle(hosted, for: 300)
            try await press(.escape, in: hosted, settling: 600)
            #expect(hosted.uiState.replyTargets[hosted.buffer.id] == nil)
            #expect(!controller.isPinnedToBottom)
            #expect(abs(try scrollOffset(hosted) - scrolledTo) < 2)
            // Nothing left to cancel: back to the newest message.
            try await press(.escape, in: hosted, settling: 1200)
            #expect(controller.isPinnedToBottom)
            #expect(controller.metrics.map(ScrollPinning.isAtBottom) == true)
            #expect(hosted.window.firstResponder === composer)
        }
    }
}
