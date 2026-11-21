// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaStore
@testable import VelaUI

private func makeSettings(_ style: NavigationStyle, _ placement: TabStackPlacement) -> SettingsStore {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "VelaTitleBar-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: "settings.json")
    let settings = SettingsStore(fileURL: url, watchForChanges: false)
    settings[.navigationStyle] = style
    settings[.tabsPlacement] = placement
    return settings
}

/// Hiding the channel title bar moves the tabs into the title bar, and
/// showing it puts them back where they were.
@MainActor
@Suite("Channel title bar")
struct ChannelTitleBarTests {
    @Test func itCanBeHiddenOnlyWithTabsAtTheTopOrTheBottom() {
        for placement in TabStackPlacement.allCases {
            let sidebar = makeSettings(.sidebar, placement)
            #expect(ChannelTitleBar.isShown(sidebar), "\(placement)")
            #expect(!ChannelTitleBar.canHide(sidebar), "\(placement)")
            #expect(!ChannelTitleBar.canShow(sidebar), "\(placement)")
        }
        for placement in [TabStackPlacement.top, .bottom] {
            let tabs = makeSettings(.tabs, placement)
            #expect(ChannelTitleBar.isShown(tabs))
            #expect(ChannelTitleBar.canHide(tabs))
            #expect(!ChannelTitleBar.canShow(tabs))
        }
        let titleBar = makeSettings(.tabs, .titleBar)
        #expect(!ChannelTitleBar.isShown(titleBar))
        #expect(!ChannelTitleBar.canHide(titleBar))
        #expect(ChannelTitleBar.canShow(titleBar))
    }

    @Test func showingItPutsTheTabsBackWhereTheyWere() {
        #expect(ChannelTitleBar.restoredPlacement(remembered: nil) == .top)
        #expect(ChannelTitleBar.restoredPlacement(remembered: .top) == .top)
        #expect(ChannelTitleBar.restoredPlacement(remembered: .bottom) == .bottom)
        #expect(ChannelTitleBar.restoredPlacement(remembered: .titleBar) == .top)

        for placement in [TabStackPlacement.top, .bottom] {
            let settings = makeSettings(.tabs, placement)
            let uiState = UIState()
            ChannelTitleBar.hide(settings: settings, uiState: uiState)
            #expect(settings[.tabsPlacement] == .titleBar)
            #expect(settings[.navigationStyle] == .tabs)
            ChannelTitleBar.show(settings: settings, uiState: uiState)
            #expect(settings[.tabsPlacement] == placement)
        }
    }

    @Test func withNothingRememberedTheTabsGoToTheTop() {
        // Launched with the tabs in the title bar: they've been nowhere else.
        let settings = makeSettings(.tabs, .titleBar)
        let uiState = UIState()
        ChannelTitleBar.show(settings: settings, uiState: uiState)
        #expect(settings[.tabsPlacement] == .top)
    }

    @Test func itRemembersWhereTheTabsWereShownHoweverTheyMoved() {
        // Moved to the bottom in Settings (the tab stack noting it as it
        // appears there), then to the title bar from View → Navigation.
        let settings = makeSettings(.tabs, .titleBar)
        let uiState = UIState()
        uiState.noteStripTabPlacement(.top)
        uiState.noteStripTabPlacement(.bottom)
        uiState.noteStripTabPlacement(.titleBar)
        #expect(uiState.stripTabPlacement == .bottom)
        ChannelTitleBar.show(settings: settings, uiState: uiState)
        #expect(settings[.tabsPlacement] == .bottom)
    }

    @Test func withTheSidebarNothingMoves() {
        for placement in TabStackPlacement.allCases {
            let settings = makeSettings(.sidebar, placement)
            let uiState = UIState()
            ChannelTitleBar.hide(settings: settings, uiState: uiState)
            ChannelTitleBar.show(settings: settings, uiState: uiState)
            ChannelTitleBar.toggle(settings: settings, uiState: uiState)
            #expect(settings[.tabsPlacement] == placement)
            #expect(settings[.navigationStyle] == .sidebar)
        }
    }

    @Test func theViewMenuItemIsATickedToggleWithTabs() {
        let settings = makeSettings(.tabs, .bottom)
        let uiState = UIState()
        var command = VelaCommandCatalog.channelTitleBarCommand(settings: settings, uiState: uiState)
        #expect(command.resolvedMenuTitle == "Show Channel Title Bar")
        #expect(command.paletteTitle == "View: Show Channel Title Bar")
        #expect(command.isEnabled)
        #expect(command.isChecked == true)

        command.perform()
        #expect(settings[.tabsPlacement] == .titleBar)
        command = VelaCommandCatalog.channelTitleBarCommand(settings: settings, uiState: uiState)
        #expect(command.isChecked == false)

        command.perform()
        #expect(settings[.tabsPlacement] == .bottom)
        #expect(VelaCommandCatalog.channelTitleBarCommand(settings: settings, uiState: uiState).isChecked == true)
    }

    @Test func theViewMenuItemIsDisabledWithTheSidebar() {
        // The title bar is always there: ticked, and greyed out (so the
        // palette leaves it out).
        for placement in TabStackPlacement.allCases {
            let settings = makeSettings(.sidebar, placement)
            let command = VelaCommandCatalog.channelTitleBarCommand(settings: settings, uiState: UIState())
            #expect(!command.isEnabled, "\(placement)")
            #expect(command.isChecked == true, "\(placement)")
        }
    }

    @Test func theKeyboardStaysOnTheTabsAsTheyMove() {
        let settings = makeSettings(.tabs, .top)
        let uiState = UIState()
        uiState.setFocused(.navigation, true)
        ChannelTitleBar.hide(settings: settings, uiState: uiState)
        // The tabs drawn in the title bar take it when they appear.
        #expect(uiState.focusRequest?.area == .navigation)
    }

    @Test func theKeyboardIsLeftAloneElsewhere() {
        for area in [FocusArea.messages, .messageBox, .members] {
            let settings = makeSettings(.tabs, .top)
            let uiState = UIState()
            uiState.setFocused(area, true)
            ChannelTitleBar.hide(settings: settings, uiState: uiState)
            #expect(uiState.focusRequest == nil, "\(area)")
            ChannelTitleBar.show(settings: settings, uiState: uiState)
            #expect(uiState.focusRequest == nil, "\(area)")
        }
    }
}

extension LinkSelectionTests {
    /// The channel title bar's right-click menu and the title-bar tab
    /// strip's, in the main window: menus asked for as AppKit does for a
    /// right-click, their items chosen, the tabs moving between the
    /// strip and the title bar, the keyboard and the messages where they
    /// were.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Channel title bar, hosted", .serialized)
    struct ChannelTitleBarHostedTests {
        private static let hide = "Hide Channel Title Bar"
        private static let show = "Show Channel Title Bar"

        private func host(_ placement: TabStackPlacement, style: NavigationStyle = .tabs) async throws -> KeyboardHostedWindow {
            // Wide enough for room after the tabs in the title bar.
            try await KeyboardHostedWindow.show(size: CGSize(width: 1400, height: 700)) { app in
                app.settings[.navigationStyle] = style
                app.settings[.tabsPlacement] = placement
                app.settings[.memberListVisible] = false
            }
        }

        // MARK: Menus

        private static var eventNumber = 71000

        /// The menu a right-click at `point` opens, asked for as AppKit
        /// does: the view it lands on, else the first of the views around
        /// it with one. Nothing is shown.
        private func menu(at point: CGPoint, in hosted: KeyboardHostedWindow) -> NSMenu? {
            Self.eventNumber += 1
            let event = NSEvent.mouseEvent(
                with: .rightMouseDown, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosted.window.windowNumber,
                context: nil, eventNumber: Self.eventNumber, clickCount: 1, pressure: 1
            )!
            var view = hosted.window.contentView?.superview?.hitTest(point)
            while let current = view {
                if let menu = current.menu(for: event) { return menu }
                view = current.superview
            }
            return nil
        }

        private func titles(_ menu: NSMenu?) -> [String] {
            menu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
        }

        /// Chooses `title` in `menu`, as a click on it would.
        private func choose(_ title: String, in menu: NSMenu?, _ hosted: KeyboardHostedWindow) async throws {
            let menu = try #require(menu, "no menu")
            let index = menu.indexOfItem(withTitle: title)
            try #require(index >= 0, "no \(title) in \(titles(menu))")
            menu.performActionForItem(at: index)
            try await hosted.settle()
        }

        // MARK: Where things are

        /// In the channel title bar, between the title and the buttons.
        private func onTitleBar(_ hosted: KeyboardHostedWindow) -> CGPoint {
            CGPoint(x: hosted.window.frame.width / 2, y: hosted.window.frame.height - 26)
        }

        /// Empty space in the title bar with the tabs in it: after the +
        /// at the end of the channel tabs, and before the tabs (where the
        /// window buttons go).
        private func emptyTitleBarSpace(_ hosted: KeyboardHostedWindow) throws -> [CGPoint] {
            let frames = hosted.accessibilityFrames()
            let session = try #require(hosted.app.selectedSession)
            let tabs = try TabActions.tabs(of: session).map { buffer in
                let label = buffer.kind == .server ? "\(session.displayName) server console" : buffer.name
                return try #require(frames[label], "no tab \(label) in \(frames.keys.sorted())")
            }
            let lastTab = try #require(tabs.map(\.maxX).max())
            let buttons = try #require(frames["Topic and channel info"])
            // Past the + (a tab's height wide) after the last tab.
            let afterTabs = lastTab + 60
            #expect(afterTabs + 10 < buttons.minX, "\(lastTab), \(buttons)")
            return [
                CGPoint(x: afterTabs, y: buttons.midY),
                CGPoint(x: 30, y: buttons.midY),
            ]
        }

        /// The message list: the tallest scroll view.
        private func messageList(_ hosted: KeyboardHostedWindow) throws -> NSScrollView {
            let scrollViews = KeyboardHostedWindow.findAll(in: hosted.host) { $0 is NSScrollView }.compactMap { $0 as? NSScrollView }
            return try #require(scrollViews.max { $0.frame.height < $1.frame.height })
        }

        /// How far the list is scrolled up from its newest line.
        private func distanceFromBottom(_ list: NSScrollView) throws -> CGFloat {
            let document = try #require(list.documentView)
            let visible = list.contentView.bounds
            return document.isFlipped ? document.frame.height - visible.maxY : visible.minY
        }

        // MARK: VoiceOver

        /// The custom actions of every element VoiceOver calls `label`
        /// (or, for text, that reads `label`).
        private func customActions(of label: String, in hosted: KeyboardHostedWindow) -> [NSAccessibilityCustomAction] {
            let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
            NSApp.perform(enhancedInterface, with: NSNumber(value: true))
            defer { NSApp.perform(enhancedInterface, with: NSNumber(value: false)) }
            var actions: [NSAccessibilityCustomAction] = []
            // Text's words are its value. (By selector: looked up on
            // AnyObject, `accessibilityValue` is ambiguous.)
            let valueSelector = NSSelectorFromString("accessibilityValue")
            func visit(_ object: AnyObject) {
                let value = (object as? NSObject).flatMap { object in
                    object.responds(to: valueSelector) ? object.perform(valueSelector)?.takeUnretainedValue() as? String : nil
                }
                if (object.accessibilityLabel?() ?? nil) == label || value == label {
                    actions += (object.accessibilityCustomActions?() ?? nil) ?? []
                }
                for child in (object.accessibilityChildren?() ?? nil) ?? [] { visit(child as AnyObject) }
            }
            visit(hosted.window)
            return actions
        }

        private func perform(_ name: String, on label: String, in hosted: KeyboardHostedWindow) async throws {
            let actions = customActions(of: label, in: hosted)
            let action = try #require(actions.first { $0.name == name }, "\(label): \(actions.map(\.name))")
            if let handler = action.handler {
                _ = handler()
            } else {
                _ = action.target?.perform(action.selector)
            }
            try await hosted.settle()
        }

        // MARK: Tests

        @Test(arguments: [TabStackPlacement.top, .bottom])
        func hidingItMovesTheTabsUpAndShowingItPutsThemBack(placement: TabStackPlacement) async throws {
            let hosted = try await host(placement)
            defer { hosted.close() }

            let titleBarMenu = menu(at: onTitleBar(hosted), in: hosted)
            #expect(titles(titleBarMenu) == [Self.hide], "\(titles(titleBarMenu))")
            try await choose(Self.hide, in: titleBarMenu, hosted)
            #expect(hosted.app.settings[.tabsPlacement] == .titleBar)
            #expect(hosted.app.settings[.navigationStyle] == .tabs)

            // The tabs are in the title bar, with the topic's ⓘ button, and
            // their empty space offers the title bar back.
            for point in try emptyTitleBarSpace(hosted) {
                #expect(titles(menu(at: point, in: hosted)) == [Self.show], "at \(point)")
            }
            try await choose(Self.show, in: menu(at: try emptyTitleBarSpace(hosted)[0], in: hosted), hosted)
            #expect(hosted.app.settings[.tabsPlacement] == placement)
        }

        @Test func theTabsKeepTheirOwnMenus() async throws {
            let hosted = try await host(.titleBar)
            defer { hosted.close() }
            let frames = hosted.accessibilityFrames()
            // A channel's menu, and the console's (its network's).
            for (label, item) in [("#vela", "Mute"), ("Libera.Chat server console", "Edit Network…")] {
                let tab = try #require(frames[label], "\(frames.keys.sorted())")
                let items = titles(menu(at: CGPoint(x: tab.midX + tab.width / 6, y: tab.midY), in: hosted))
                #expect(items.contains(item), "\(label): \(items)")
                #expect(!items.contains(Self.show), "\(label): \(items)")
            }
        }

        @Test func theSidebarsTitleBarOffersNothingNew() async throws {
            let hosted = try await host(.top, style: .sidebar)
            defer { hosted.close() }
            // No menu at all, as before: not even an empty one.
            let shown = menu(at: onTitleBar(hosted), in: hosted)
            #expect(shown == nil, "\(titles(shown))")
        }

        @Test func voiceOverHasTheMenusItemsAsActions() async throws {
            let hosted = try await host(.top)
            defer { hosted.close() }
            // On the channel's name in the title bar.
            try await perform(Self.hide, on: "#vela", in: hosted)
            #expect(hosted.app.settings[.tabsPlacement] == .titleBar)
            // On the channel tabs in the title bar.
            try await perform(Self.show, on: "Channels on Libera.Chat", in: hosted)
            #expect(hosted.app.settings[.tabsPlacement] == .top)
            #expect(!customActions(of: "Channels on Libera.Chat", in: hosted).map(\.name).contains(Self.show))
        }

        @Test func voiceOverIsOfferedNothingNewWithTheSidebar() async throws {
            let hosted = try await host(.top, style: .sidebar)
            defer { hosted.close() }
            let names = customActions(of: "#vela", in: hosted).map(\.name)
            #expect(!names.contains(Self.hide), "\(names)")
        }

        @Test func theMessageBoxKeepsTheKeyboard() async throws {
            let hosted = try await host(.top)
            defer { hosted.close() }
            hosted.uiState.focusInput()
            #expect(try await hosted.waitForMessageBox())

            try await choose(Self.hide, in: menu(at: onTitleBar(hosted), in: hosted), hosted)
            #expect(hosted.app.settings[.tabsPlacement] == .titleBar)
            #expect(hosted.messageBoxHasFocus, "\(String(describing: hosted.window.firstResponder))")

            try await choose(Self.show, in: menu(at: try emptyTitleBarSpace(hosted)[0], in: hosted), hosted)
            #expect(hosted.app.settings[.tabsPlacement] == .top)
            #expect(hosted.messageBoxHasFocus, "\(String(describing: hosted.window.firstResponder))")
        }

        @Test func theKeyboardGoesWithTheTabs() async throws {
            let hosted = try await host(.bottom)
            defer { hosted.close() }
            hosted.uiState.focus(.navigation)
            try await hosted.settle()
            #expect(hosted.focusedArea != nil)

            // From the View menu, as someone at the keyboard would.
            VelaCommandCatalog.channelTitleBarCommand(settings: hosted.app.settings, uiState: hosted.uiState).perform()
            try await hosted.settle()
            #expect(hosted.app.settings[.tabsPlacement] == .titleBar)
            #expect(hosted.focusedArea != nil, "\(String(describing: hosted.window.firstResponder))")
            #expect(hosted.uiState.focusedArea == .navigation)
            // And ← and → still go along them.
            try await hosted.press(.right)
            #expect(hosted.selectedName == "#swift")

            VelaCommandCatalog.channelTitleBarCommand(settings: hosted.app.settings, uiState: hosted.uiState).perform()
            try await hosted.settle()
            #expect(hosted.app.settings[.tabsPlacement] == .bottom)
            #expect(hosted.focusedArea != nil, "\(String(describing: hosted.window.firstResponder))")
            #expect(hosted.uiState.focusedArea == .navigation)
        }

        @Test(arguments: [TabStackPlacement.top, .bottom])
        func theMessagesStayAtTheNewestLine(placement: TabStackPlacement) async throws {
            let hosted = try await host(placement)
            defer { hosted.close() }
            try await Task.sleep(for: .milliseconds(300))
            let list = try messageList(hosted)
            let height = list.frame.height
            #expect(try distanceFromBottom(list) < 2)

            try await choose(Self.hide, in: menu(at: onTitleBar(hosted), in: hosted), hosted)
            try await Task.sleep(for: .milliseconds(200))
            // The same list, only taller, still at the newest line.
            #expect(try messageList(hosted) === list)
            #expect(list.frame.height > height)
            #expect(try distanceFromBottom(list) < 2)

            try await choose(Self.show, in: menu(at: try emptyTitleBarSpace(hosted)[0], in: hosted), hosted)
            try await Task.sleep(for: .milliseconds(200))
            #expect(try messageList(hosted) === list)
            #expect(abs(list.frame.height - height) < 0.5)
            #expect(try distanceFromBottom(list) < 2)
        }
    }
}
