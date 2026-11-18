// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaIntelligence
import VelaTheme
@testable import VelaUI

extension LinkSelectionTests {
    /// Right-clicking messages: rows from the demo, hosted as in the message
    /// list (a lazy stack in a scroll view) in an offscreen window. A
    /// right-click or Control-click on a message's text opens the message's
    /// menu, as anywhere else on the row, rather than selectable text's own
    /// Cut / Copy / Paste / Font menu; on selected text the menu also has
    /// the selection's items (Copy, Look Up…).
    ///
    /// Menus are asked for the way AppKit does on a right-click (the view
    /// it lands on, then up the views around it), not opened: a real menu
    /// would open on screen, and its tracking loop can end the test run.
    ///
    /// Nested in the serialized `LinkSelectionTests`, so they take turns
    /// with `LinkClickMonitor.shared`.
    @MainActor
    @Suite("Message context menus")
    struct MessageContextMenuTests {
        private static let app: AppModel = {
            let app = AppModel.demo()
            // Nothing fetched or shown under the messages.
            app.settings[.mediaShowLinkCards] = false
            app.settings[.mediaAutoLoad] = false
            return app
        }()

        private final class Opened {
            var urls: [URL] = []
        }

        private final class Hosted {
            let window: NSWindow
            let host: NSView
            let buffer: BufferModel
            let uiState: UIState
            let opened: Opened
            /// The selectable texts, top to bottom.
            let texts: [NSView]

            init(window: NSWindow, host: NSView, buffer: BufferModel, uiState: UIState, opened: Opened, texts: [NSView]) {
                self.window = window
                self.host = host
                self.buffer = buffer
                self.uiState = uiState
                self.opened = opened
                self.texts = texts
            }

            var regionViews: [LinkPointerRegionView] {
                MessageContextMenuTests.findAll(in: host) { $0 is LinkPointerRegionView }.compactMap { $0 as? LinkPointerRegionView }
            }

            /// A point on the first line of `text`, `x` points from its
            /// leading edge, in the window.
            func point(in text: NSView, x: CGFloat) -> CGPoint {
                let bounds = text.bounds
                return text.convert(CGPoint(x: bounds.minX + x, y: text.isFlipped ? bounds.minY + 7 : bounds.maxY - 7), to: nil)
            }

            /// Level with `text`'s first line, near the row's end: on the
            /// row but on nothing in it.
            func emptySpace(beside text: NSView) -> CGPoint {
                CGPoint(x: host.convert(host.bounds, to: nil).maxX - 30, y: point(in: text, x: 0).y)
            }

            /// The middle of link `index` of the text under `regionView`.
            func linkPoint(_ index: Int, in regionView: LinkPointerRegionView) throws -> CGPoint {
                let rect = try #require(regionView.regions.regions.first { $0.link == index }?.rect)
                return regionView.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
            }

            func close() {
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        private static let translationContext = TranslationContext(target: Locale.Language(identifier: "en"), isAutomatic: false, isDemo: true)

        private func host(_ lines: [ChatLine], in buffer: BufferModel, translations: TranslationStore = TranslationStore()) async throws -> Hosted {
            let app = Self.app
            let session = try #require(app.sessions.first)
            let controller = MessageListController(buffer: buffer, session: session)
            let uiState = UIState()
            let opened = Opened()
            let theme = ResolvedTheme.fallbackLight
            let style = ChatStyle(settings: app.settings)
            controller.textCache.prepare(
                palette: MessageTextPalette(theme: theme, style: style),
                options: MessageTextOptions(renderFormatting: style.renderFormatting, selfNick: session.nick, channelTypes: session.isupport.channelTypes)
            )
            let view = ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        DisplayItemRow(item: .line(LineItem(line: line, isContinuation: false, reply: nil)))
                    }
                }
            }
            .frame(width: 640, height: 360, alignment: .topLeading)
            .environment(controller)
            .environment(app)
            .environment(uiState)
            .environment(IntelligenceServices.demo())
            .environment(translations)
            .environment(\.translationContext, Self.translationContext)
            .environment(\.theme, theme)
            .environment(\.chatStyle, style)
            .environment(\.nickColorBuffer, buffer)
            .environment(\.openURL, OpenURLAction { url in
                opened.urls.append(url)
                return .handled
            })
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(x: -8000, y: -8000, width: 640, height: 360), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            // AppKit only delivers clicks to a window that's on screen (this one
            // is far off it).
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(200))
            let texts = Self.findAll(in: host) { NSStringFromClass(type(of: $0)).contains("TextInteraction") }
                .sorted { $0.convert($0.bounds, to: nil).midY > $1.convert($1.bounds, to: nil).midY }
            // The test runner is never the active app, so AppKit only passes a
            // click on to a view that takes the first mouse.
            for text in texts { Self.acceptFirstMouse(type(of: text)) }
            return Hosted(window: window, host: host, buffer: buffer, uiState: uiState, opened: opened, texts: texts)
        }

        fileprivate static func findAll(in view: NSView, where matches: (NSView) -> Bool) -> [NSView] {
            (matches(view) ? [view] : []) + view.subviews.flatMap { findAll(in: $0, where: matches) }
        }

        private static func acceptFirstMouse(_ viewClass: AnyClass) {
            let accept: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
            // Adds an override to that class only (a no-op once it has one).
            class_addMethod(viewClass, #selector(NSView.acceptsFirstMouse(for:)), imp_implementationWithBlock(accept), "c@:@")
        }

        private struct Demo {
            let offtopic: BufferModel
            let vela: BufferModel
            /// Two of #vela-offtopic's lines in other languages.
            let spanish: ChatLine
            let japanese: ChatLine
        }

        private func demo() throws -> Demo {
            let session = try #require(Self.app.sessions.first)
            let offtopic = try #require(session.buffer(named: "#vela-offtopic"))
            return Demo(
                offtopic: offtopic,
                vela: try #require(session.buffer(named: "#vela")),
                spanish: try #require(offtopic.lines.first { $0.text.hasPrefix("¡Qué envidia") }),
                japanese: try #require(offtopic.lines.first { $0.text.hasPrefix("北海道") })
            )
        }

        // MARK: Events

        private static var eventNumber = 9000

        private func event(_ type: NSEvent.EventType, at point: CGPoint, in hosted: Hosted, clickCount: Int = 1, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            Self.eventNumber += 1
            return NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosted.window.windowNumber,
                context: nil, eventNumber: Self.eventNumber, clickCount: clickCount,
                pressure: type == .leftMouseUp ? 0 : 1
            )!
        }

        /// Sends events through the app, as the event loop would (so event
        /// monitors see them too).
        private func send(_ events: [NSEvent]) async throws {
            for event in events {
                NSApp.sendEvent(event)
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        private func click(at point: CGPoint, in hosted: Hosted, count: Int = 1) async throws {
            for clickCount in 1...count {
                try await send([
                    event(.leftMouseDown, at: point, in: hosted, clickCount: clickCount),
                    event(.leftMouseUp, at: point, in: hosted, clickCount: clickCount),
                ])
            }
        }

        private func drag(from start: CGPoint, to end: CGPoint, in hosted: Hosted) async throws {
            let nudge = CGPoint(x: start.x + (end.x > start.x ? 12 : -12), y: start.y)
            try await send([
                event(.leftMouseDown, at: start, in: hosted),
                event(.leftMouseDragged, at: nudge, in: hosted),
                event(.leftMouseDragged, at: end, in: hosted),
                event(.leftMouseUp, at: end, in: hosted),
            ])
        }

        /// Runs `body` with the monitor taking clicks in this inactive test
        /// app's windows.
        private func withClicksAccepted(_ body: () async throws -> Void) async rethrows {
            _ = NSApplication.shared
            let monitor = LinkClickMonitor.shared
            let acceptsClicks = monitor.acceptsClicks
            monitor.acceptsClicks = { _ in true }
            defer { monitor.acceptsClicks = acceptsClicks }
            try await body()
        }

        // MARK: Menus

        private struct ContextMenu {
            /// The view the click lands on.
            var view: NSView?
            var menu: NSMenu?
            var items: [String] { menu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? [] }
        }

        /// The menu a right-click (or Control-click) at `point` opens, asked
        /// for as AppKit does: the view it lands on, else the first of the
        /// views around it with one. Meanwhile the click is what the views
        /// over text see as the app's current event, as they would.
        private func contextMenu(at point: CGPoint, in hosted: Hosted, control: Bool = false) -> ContextMenu {
            let event = control
                ? event(.leftMouseDown, at: point, in: hosted, modifiers: .control)
                : event(.rightMouseDown, at: point, in: hosted)
            let regionViews = hosted.regionViews
            for view in regionViews {
                view.currentEventType = { event.type }
                view.currentModifiers = { event.modifierFlags }
            }
            defer {
                for view in regionViews {
                    view.currentEventType = { NSApplication.shared.currentEvent?.type }
                    view.currentModifiers = { NSApplication.shared.currentEvent?.modifierFlags ?? [] }
                }
            }
            let target = hosted.window.contentView?.superview?.hitTest(point)
            var responder = target
            while let view = responder {
                if let menu = view.menu(for: event) { return ContextMenu(view: target, menu: menu) }
                responder = view.superview
            }
            return ContextMenu(view: target, menu: nil)
        }

        /// Items of selectable text's own menu that a message's never has.
        private static let textMenuOnly = ["Cut", "Paste", "Paste and Match Style", "Font", "Spelling and Grammar", "Substitutions", "Layout Orientation"]

        // MARK: Message text

        @Test func rightClickingMessageTextOpensTheMessageMenu() async throws {
            let demo = try demo()
            let hosted = try await host([demo.spanish], in: demo.offtopic)
            defer { hosted.close() }
            let text = try #require(hosted.texts.first)
            let onText = hosted.point(in: text, x: 20)
            for control in [false, true] {
                let menu = contextMenu(at: onText, in: hosted, control: control)
                #expect(menu.view is LinkPointerRegionView)
                #expect(Array(menu.items.prefix(2)) == ["Add Reaction", "Reply"], "\(menu.items)")
                for item in ["Translate", "Copy Text", "Copy Nick", "Whois marisol"] {
                    #expect(menu.items.contains(item), "\(item): \(menu.items)")
                }
                #expect(Self.textMenuOnly.allSatisfy { !menu.items.contains($0) }, "\(menu.items)")
            }
            // Beside the text: the same menu, as before.
            let beside = contextMenu(at: hosted.emptySpace(beside: text), in: hosted)
            #expect(!(beside.view is LinkPointerRegionView))
            #expect(beside.items == contextMenu(at: onText, in: hosted).items)
            // Nothing got selected.
            #expect(text.accessibilitySelectedText()?.isEmpty ?? true)
        }

        @Test func rightClickingALinkOffersCopyLinkForThatLink() async throws {
            try await withClicksAccepted {
                let demo = try demo()
                let first = URL(string: "https://example.com/alpha")!
                let second = URL(string: "https://example.org/beta")!
                let line = ChatLine(kind: .message, nick: "theo", text: "two links: \(first.absoluteString) and \(second.absoluteString) for later")
                let hosted = try await host([line], in: demo.vela)
                defer { hosted.close() }
                let regionView = try #require(hosted.regionViews.first)
                #expect(regionView.takesContextClicks)
                let onSecond = try hosted.linkPoint(1, in: regionView)
                for control in [false, true] {
                    let menu = contextMenu(at: onSecond, in: hosted, control: control)
                    #expect(menu.view === regionView)
                    #expect(menu.items.contains("Copy Link"), "\(menu.items)")
                    #expect(menu.items.contains("Copy Text"), "\(menu.items)")
                    #expect(Self.textMenuOnly.allSatisfy { !menu.items.contains($0) }, "\(menu.items)")
                }
                // Copy Link copies the link that was right-clicked. (Handled
                // directly: sending it would open a real menu.)
                let monitor = LinkClickMonitor.shared
                monitor.handle(event(.rightMouseDown, at: onSecond, in: hosted))
                #expect(monitor.contextLink(among: [first, second]) == second)
                monitor.handle(event(.leftMouseDown, at: try hosted.linkPoint(0, in: regionView), in: hosted, modifiers: .control))
                #expect(monitor.contextLink(among: [first, second]) == first)
                #expect(hosted.opened.urls.isEmpty)
            }
        }

        @Test func rightClickingSelectedTextAddsCopyAndLookUp() async throws {
            try await withClicksAccepted {
                let demo = try demo()
                let hosted = try await host([demo.spanish, demo.japanese], in: demo.offtopic)
                defer { hosted.close() }
                let text = try #require(hosted.texts.first)
                let onWord = hosted.point(in: text, x: 20)
                try await click(at: onWord, in: hosted, count: 2)
                #expect(text.accessibilitySelectedText() == "Qué")
                for control in [false, true] {
                    let menu = contextMenu(at: onWord, in: hosted, control: control)
                    #expect(menu.view is LinkPointerRegionView)
                    let items = menu.items
                    // The selection's items, then the message's.
                    #expect(items.first?.hasPrefix("Look Up") == true, "\(items)")
                    let copy = try #require(items.firstIndex(of: "Copy"), "\(items)")
                    let reply = try #require(items.firstIndex(of: "Reply"), "\(items)")
                    #expect(copy < reply)
                    #expect(items.contains("Share…"), "\(items)")
                    for item in ["Translate", "Copy Text", "Copy Nick"] {
                        #expect(items.contains(item), "\(item): \(items)")
                    }
                    #expect(Self.textMenuOnly.allSatisfy { !items.contains($0) }, "\(items)")
                    // Copy goes to the text, which copies its selection.
                    let copyItem = try #require(menu.menu?.items.first { $0.title == "Copy" })
                    #expect(copyItem.action == #selector(NSText.copy(_:)))
                    #expect(copyItem.target === text)
                }
                // The message's items still work.
                let menu = try #require(contextMenu(at: onWord, in: hosted).menu)
                menu.performActionForItem(at: menu.indexOfItem(withTitle: "Reply"))
                #expect(hosted.uiState.replyTargets[hosted.buffer.id]?.id == demo.spanish.id)
                // Another message's text, without a selection: just its menu.
                let other = try #require(hosted.texts.last)
                let otherMenu = contextMenu(at: hosted.point(in: other, x: 20), in: hosted)
                #expect(otherMenu.items.first == "Add Reaction", "\(otherMenu.items)")
                #expect(!otherMenu.items.contains("Copy"), "\(otherMenu.items)")
                #expect(text.accessibilitySelectedText() == "Qué")
            }
        }

        @Test func rightClickingATranslationOpensTheMessageMenu() async throws {
            let demo = try demo()
            let store = TranslationStore()
            let source = try #require(store.offer(for: demo.spanish, in: demo.offtopic, context: Self.translationContext))
            store.translate(demo.spanish, from: source, context: Self.translationContext)
            // The demo's canned translation takes a moment.
            for _ in 0..<40 where !isTranslated(demo.spanish, in: store) {
                try await Task.sleep(for: .milliseconds(50))
            }
            let hosted = try await host([demo.spanish], in: demo.offtopic, translations: store)
            defer { hosted.close() }
            #expect(hosted.texts.count == 2)
            let translation = try #require(hosted.texts.last)
            #expect(translation.accessibilityValue() as? String == CannedTranslator.demoTranslations[demo.spanish.text])
            let menu = contextMenu(at: hosted.point(in: translation, x: 20), in: hosted)
            #expect(menu.view is LinkPointerRegionView)
            #expect(menu.items.contains("Hide Translation"), "\(menu.items)")
            #expect(menu.items.contains("Reply"), "\(menu.items)")
            #expect(Self.textMenuOnly.allSatisfy { !menu.items.contains($0) }, "\(menu.items)")
        }

        private func isTranslated(_ line: ChatLine, in store: TranslationStore) -> Bool {
            if case .translated = store.state(for: line.id) { true } else { false }
        }

        // MARK: Unchanged

        @Test func selectingAndOpeningLinksWorkAsBefore() async throws {
            try await withClicksAccepted {
                let demo = try demo()
                let link = URL(string: "https://example.com/alpha/beta")!
                let line = ChatLine(kind: .message, nick: "theo", text: "see \(link.absoluteString) and then some more plain words")
                let hosted = try await host([line], in: demo.vela)
                defer { hosted.close() }
                let text = try #require(hosted.texts.first)
                let regionView = try #require(hosted.regionViews.first)
                let onLink = try hosted.linkPoint(0, in: regionView)
                // The pointing hand over the link only.
                let root = try #require(hosted.window.contentView?.superview)
                regionView.currentEventType = { .mouseMoved }
                #expect(root.hitTest(onLink) === regionView)
                #expect(root.hitTest(hosted.point(in: text, x: 6)) !== regionView)
                regionView.currentEventType = { NSApplication.shared.currentEvent?.type }
                // A drag from the link's start selects.
                let linkRect = try #require(regionView.regions.regions.first?.rect)
                let linkStart = regionView.convert(CGPoint(x: linkRect.minX + 1, y: linkRect.midY), to: nil)
                try await drag(from: linkStart, to: hosted.point(in: text, x: text.bounds.width - 4), in: hosted)
                let selected = text.accessibilitySelectedText() ?? ""
                #expect(selected.hasPrefix("https://example.com/alpha/beta and then some"), "\(selected)")
                #expect(hosted.opened.urls.isEmpty)
                // A double-click selects a word.
                try await click(at: hosted.point(in: text, x: text.bounds.width - 20), in: hosted, count: 2)
                #expect(text.accessibilitySelectedText() == "words")
                // A click on the link opens it.
                try await click(at: onLink, in: hosted)
                #expect(hosted.opened.urls == [link])
            }
        }

        @Test func eventLinesKeepTheirTextMenu() async throws {
            // Event lines have no menu of their own, so their text keeps its
            // own (which copies a selection), with or without links.
            let demo = try demo()
            let join = try #require(demo.vela.lines.first { $0.kind == .join })
            let topic = ChatLine(kind: .topic, nick: "doug", text: "doug changed the topic to: notes at https://example.com/notes")
            let hosted = try await host([join, topic], in: demo.vela)
            defer { hosted.close() }
            #expect(hosted.texts.count == 2)
            let regionViews = hosted.regionViews
            #expect(regionViews.count == 1)
            #expect(regionViews.allSatisfy { !$0.takesContextClicks })
            for text in hosted.texts {
                let menu = contextMenu(at: hosted.point(in: text, x: 20), in: hosted)
                #expect(menu.view === text)
                #expect(menu.items.contains("Copy"), "\(menu.items)")
                #expect(!menu.items.contains("Reply"), "\(menu.items)")
            }
        }
    }
}

// MARK: Selection items

@MainActor
@Suite("The selection's items in a message's menu")
struct SelectionMenuItemsTests {
    private func item(_ title: String, _ action: String?, submenu: [NSMenuItem]? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action.map(NSSelectorFromString), keyEquivalent: "")
        if let submenu {
            let menu = NSMenu(title: title)
            menu.items = submenu
            item.submenu = menu
        }
        return item
    }

    /// Like selectable text's own menu.
    private func textMenu() -> NSMenu {
        let menu = NSMenu()
        menu.items = [
            item("Look Up “Qué”", "_rvMenuItemAction"),
            item("Translate “Qué”", "_rvMenuItemAction"),
            .separator(),
            item("Search With Google", "_searchWithGoogleFromMenu:"),
            .separator(),
            item("Cut", "cut:"),
            item("Copy", "copy:"),
            item("Paste", "paste:"),
            item("Paste and Match Style", "pasteAsPlainText:"),
            .separator(),
            item("Share…", "_performStandardShareMenuItem:"),
            .separator(),
            item("Font", "submenuAction:", submenu: [item("Show Fonts", "orderFrontFontPanel:"), item("Bold", "addFontTrait:")]),
            .separator(),
            item("Spelling and Grammar", "submenuAction:", submenu: [item("Check Document Now", "checkSpelling:")]),
            item("Transformations", "submenuAction:", submenu: [item("Make Upper Case", "uppercaseWord:")]),
            item("Speech", "submenuAction:", submenu: [item("Start Speaking", "startSpeaking:"), item("Stop Speaking", "stopSpeaking:")]),
            item("Writing Direction", "submenuAction:", submenu: [item("Paragraph", nil), item("Default", "makeBaseWritingDirectionNatural:")]),
            item("Layout Orientation", "submenuAction:", submenu: [item("Horizontal", "changeLayoutOrientation:")]),
        ]
        return menu
    }

    private func titles(_ items: [NSMenuItem]) -> [String] {
        items.map { $0.isSeparatorItem ? "—" : $0.title }
    }

    @Test func keepsTheSelectionsItemsAndLeavesOutEditing() {
        #expect(titles(SelectionMenuItems.selectionItems(in: textMenu()))
            == ["Look Up “Qué”", "Translate “Qué”", "—", "Search With Google", "—", "Copy", "—", "Share…", "—", "Speech"])
    }

    @Test func movesThemAboveTheMenuAndSendsCopyToTheText() {
        let text = NSTextView()
        let textMenu = textMenu()
        let menu = NSMenu()
        menu.items = [item("Reply", "reply:"), item("Copy Text", "copyText:")]
        SelectionMenuItems.move(from: textMenu, of: text, to: menu)
        #expect(titles(menu.items)
            == ["Look Up “Qué”", "Translate “Qué”", "—", "Search With Google", "—", "Copy", "—", "Share…", "—", "Speech", "—", "Reply", "Copy Text"])
        #expect(menu.items.first { $0.title == "Copy" }?.target === text)
        #expect(menu.items.first { $0.title == "Speech" }?.submenu?.items.first?.target === text)
        // Moved, not copied.
        #expect(!textMenu.items.contains { $0.title == "Copy" })
    }

    @Test func aMenuWithNothingForTheSelectionIsLeftAlone() {
        let textMenu = NSMenu()
        textMenu.items = [item("Cut", "cut:"), .separator(), item("Paste", "paste:")]
        let menu = NSMenu()
        menu.items = [item("Reply", "reply:")]
        SelectionMenuItems.move(from: textMenu, of: NSTextView(), to: menu)
        #expect(titles(menu.items) == ["Reply"])
    }
}
