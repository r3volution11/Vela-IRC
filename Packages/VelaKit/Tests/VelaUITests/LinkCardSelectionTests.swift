// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaMedia
@testable import VelaUI

extension LinkSelectionTests {
    /// Link previews (`LinkCardView`), hosted in an offscreen window and driven
    /// with synthetic mouse events, as AppKit delivers them: a click anywhere
    /// on the card opens the page, and its text selects and copies like
    /// message text.
    ///
    /// Nested in the serialized `LinkSelectionTests`, so the two take turns
    /// with `LinkClickMonitor.shared`.
    ///
    /// Not on macOS 26: there SwiftUI draws a card's text as
    /// `SelectionTextField`s, which take a click in a mouse-tracking loop of
    /// their own until the release; events sent like these can't end it, so
    /// a test hangs on its first click. Clicks there are handled by
    /// `LinkClickMonitor.finishTrackedPress` and checked by hand.
    @MainActor
    @Suite(
        "Selecting and opening link previews",
        .disabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27, "macOS 26's selectable text can't be clicked by sent events; checked by hand")
    )
    struct LinkCardSelectionTests {
        private static let url = URL(string: "https://example.com/news/vela-cluster")!
        private static let title = "Stars of the Vela constellation"
        private static let summary = "Young stars light up the gas around them in a new picture from the observatory."
        private static let siteName = "Example Observatory"
        /// Nothing listens there: the blurred stand-in's image fails at once.
        private static let imageURL = URL(string: "http://127.0.0.1:9/thumbnail.png")!
        private static let app = AppModel.demo()

        private final class Opened {
            var urls: [URL] = []
        }

        private final class Hosted {
            let window: NSWindow
            let host: NSView
            /// The card's site name, title and description, top to bottom.
            let texts: [NSView]
            let regionView: LinkPointerRegionView
            let opened: Opened

            init(window: NSWindow, host: NSView, texts: [NSView], regionView: LinkPointerRegionView, opened: Opened) {
                self.window = window
                self.host = host
                self.texts = texts
                self.regionView = regionView
                self.opened = opened
            }

            var siteName: NSView { texts[0] }
            var title: NSView { texts[1] }
            var summary: NSView { texts[2] }

            /// A point on the first line of `text`, `x` points from its leading
            /// edge (from its trailing edge when negative), in the window.
            func point(in text: NSView, x: CGFloat) -> CGPoint {
                let bounds = text.bounds
                let local = CGPoint(
                    x: x >= 0 ? bounds.minX + x : bounds.maxX + x,
                    y: text.isFlipped ? bounds.minY + 6 : bounds.maxY - 6
                )
                return text.convert(local, to: nil)
            }

            /// A point in the card's bottom-right padding, away from any text.
            var paddingPoint: CGPoint {
                let bounds = regionView.bounds
                return regionView.convert(CGPoint(x: bounds.maxX - 5, y: bounds.maxY - 4), to: nil)
            }

            /// What Copy puts on a pasteboard (a private one, not the
            /// clipboard).
            func copiedText(from text: NSView) throws -> String? {
                let requestor = try #require(text as? NSServicesMenuRequestor)
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("app.vela.tests.\(UUID().uuidString)"))
                defer { pasteboard.releaseGlobally() }
                pasteboard.clearContents()
                guard requestor.writeSelection?(to: pasteboard, types: [.string]) == true else { return nil }
                return pasteboard.string(forType: .string)
            }

            func close() {
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        private func preview(withImage: Bool) -> LinkPreview {
            LinkPreview(
                url: Self.url,
                kind: .page,
                title: Self.title,
                summary: Self.summary,
                siteName: Self.siteName,
                imageURL: withImage ? Self.imageURL : nil,
                imageSize: withImage ? CGSize(width: 1200, height: 630) : nil
            )
        }

        /// `blurredImage` gives the card an image, blurred: its Click to show
        /// stand-in sits inside the card.
        /// SwiftUI's selectable text: a `TextInteraction` view, or on
        /// macOS 26 for one-line text a `SelectionTextField`.
        static func isSelectableText(_ view: NSView) -> Bool {
            let name = NSStringFromClass(type(of: view))
            return name.contains("TextInteraction") || name.hasSuffix("SelectionTextField")
        }

        private func host(_ size: PreviewLinkSize, blurredImage: Bool = false) async throws -> Hosted {
            let opened = Opened()
            let card = LinkCardView(
                preview: preview(withImage: blurredImage),
                // Lets the stand-in try (and fail) to load its image locally.
                policy: MediaPolicy(allowPrivateNetworkHosts: true),
                size: size,
                showsImages: true,
                onHide: {}
            )
            let view = card
                .environment(\.embedBlur, EmbedBlur(isBlurred: blurredImage))
                .frame(width: 560, alignment: .topLeading)
                .padding(12)
                .background(Color.black)
                .environment(Self.app)
                .environment(\.openURL, OpenURLAction { url in
                    opened.urls.append(url)
                    return .handled
                })
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(x: -8000, y: -8000, width: 584, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame.size = host.fittingSize
            host.layoutSubtreeIfNeeded()
            // AppKit only delivers clicks to a window that's on screen (this one
            // is far off it).
            window.orderFrontRegardless()
            // SwiftUI adds the text views as it lays the card out: sooner on
            // some systems than others (on macOS 26 not within 150 ms).
            var found: [NSView] = []
            var deadline = RunningDeadline(.seconds(3))
            repeat {
                try await Task.sleep(for: .milliseconds(50))
                host.layoutSubtreeIfNeeded()
                found = Self.findAll(in: host) { Self.isSelectableText($0) }
            } while found.count < (size == .minimal ? 2 : 3) && deadline.hasTimeLeft()
            // Top to bottom, then left to right (a Minimal card is one row).
            let texts = found
                .sorted { a, b in
                    let first = a.convert(a.bounds, to: nil), second = b.convert(b.bounds, to: nil)
                    guard abs(first.midY - second.midY) < 6 else { return first.midY > second.midY }
                    return first.minX < second.minX
                }
            // The test runner is never the active app, so AppKit only passes a
            // click on to a view that takes the first mouse.
            for text in texts { Self.acceptFirstMouse(type(of: text)) }
            let regionView = try #require(Self.findAll(in: host) { ($0 as? LinkPointerRegionView)?.coversBounds == true }.first as? LinkPointerRegionView)
            return Hosted(window: window, host: host, texts: texts, regionView: regionView, opened: opened)
        }

        private static func findAll(in view: NSView, where matches: (NSView) -> Bool) -> [NSView] {
            (matches(view) ? [view] : []) + view.subviews.flatMap { findAll(in: $0, where: matches) }
        }

        private static func acceptFirstMouse(_ viewClass: AnyClass) {
            let accept: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
            // Adds an override to that class only (a no-op once it has one).
            class_addMethod(viewClass, #selector(NSView.acceptsFirstMouse(for:)), imp_implementationWithBlock(accept), "c@:@")
        }

        // MARK: Events

        private static var eventNumber = 5000

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

        private func click(at point: CGPoint, in hosted: Hosted, count: Int = 1, modifiers: NSEvent.ModifierFlags = []) async throws {
            for clickCount in 1...count {
                try await send([
                    event(.leftMouseDown, at: point, in: hosted, clickCount: clickCount, modifiers: modifiers),
                    event(.leftMouseUp, at: point, in: hosted, clickCount: clickCount, modifiers: modifiers),
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

        // MARK: Opening

        @Test(arguments: [PreviewLinkSize.minimal, .standard, .large])
        func aClickAnywhereOnTheCardOpensThePageOnce(size: PreviewLinkSize) async throws {
            try await withClicksAccepted {
                let hosted = try await host(size)
                defer { hosted.close() }
                #expect(hosted.texts.count == (size == .minimal ? 2 : 3), "\(hosted.texts)")
                // The title, at once on the release.
                let onTitle = hosted.point(in: hosted.title, x: 10)
                try await send([event(.leftMouseDown, at: onTitle, in: hosted)])
                #expect(hosted.opened.urls.isEmpty)
                try await send([event(.leftMouseUp, at: onTitle, in: hosted)])
                #expect(hosted.opened.urls == [Self.url])
                // The site name and the card's padding open it too.
                try await click(at: hosted.point(in: hosted.siteName, x: 4), in: hosted)
                try await click(at: hosted.paddingPoint, in: hosted)
                #expect(hosted.opened.urls == [Self.url, Self.url, Self.url])
            }
        }

        @Test func aClickOnTheDescriptionOpensThePage() async throws {
            try await withClicksAccepted {
                let hosted = try await host(.standard)
                defer { hosted.close() }
                try await click(at: hosted.point(in: hosted.summary, x: 30), in: hosted)
                #expect(hosted.opened.urls == [Self.url])
            }
        }

        @Test func shiftAndControlClicksDoNotOpenTheCard() async throws {
            try await withClicksAccepted {
                let hosted = try await host(.standard)
                defer { hosted.close() }
                let onTitle = hosted.point(in: hosted.title, x: 10)
                try await click(at: onTitle, in: hosted, modifiers: .shift)
                // Handled directly: sending it would open the context menu.
                let monitor = LinkClickMonitor.shared
                monitor.handle(event(.leftMouseDown, at: onTitle, in: hosted, modifiers: .control))
                monitor.handle(event(.leftMouseUp, at: onTitle, in: hosted, modifiers: .control))
                #expect(hosted.opened.urls.isEmpty)
                try await click(at: onTitle, in: hosted, modifiers: .command)
                #expect(hosted.opened.urls == [Self.url])
            }
        }

        @Test func clicksInAWindowThatIsNotKeyDoNotOpenTheCard() async throws {
            _ = NSApplication.shared
            let hosted = try await host(.standard)
            defer { hosted.close() }
            #expect(!LinkClickMonitor.shared.acceptsClicks(hosted.window))
            try await click(at: hosted.point(in: hosted.title, x: 10), in: hosted)
            #expect(hosted.opened.urls.isEmpty)
        }

        // MARK: Selecting

        @Test func aDragOverTheTitleSelectsAndCopiesItWithoutOpening() async throws {
            try await withClicksAccepted {
                let hosted = try await host(.standard)
                defer { hosted.close() }
                let title = hosted.title
                try await drag(from: hosted.point(in: title, x: 1), to: hosted.point(in: title, x: -1), in: hosted)
                let selected = try #require(title.accessibilitySelectedText())
                #expect(selected.hasPrefix("Stars of the Vela constellat"), "\(selected)")
                let copied = try #require(try hosted.copiedText(from: title))
                #expect(copied.hasPrefix("Stars of the Vela constellat"), "\(copied)")
                #expect(Self.title.hasPrefix(copied), "\(copied)")
                #expect(hosted.opened.urls.isEmpty)
            }
        }

        @Test func aDragOverTheDescriptionAndSiteNameSelects() async throws {
            try await withClicksAccepted {
                let hosted = try await host(.large)
                defer { hosted.close() }
                try await drag(from: hosted.point(in: hosted.summary, x: 1), to: hosted.point(in: hosted.summary, x: 120), in: hosted)
                #expect(hosted.summary.accessibilitySelectedText()?.hasPrefix("Young stars") == true)
                try await drag(from: hosted.point(in: hosted.siteName, x: 1), to: hosted.point(in: hosted.siteName, x: -1), in: hosted)
                #expect(hosted.siteName.accessibilitySelectedText()?.hasPrefix("Example Observ") == true)
                #expect(hosted.opened.urls.isEmpty)
            }
        }

        @Test(arguments: [PreviewLinkSize.minimal, .standard])
        func aDoubleClickSelectsAWordAndOpensThePageOnce(size: PreviewLinkSize) async throws {
            try await withClicksAccepted {
                let hosted = try await host(size)
                defer { hosted.close() }
                // On "Stars".
                try await click(at: hosted.point(in: hosted.title, x: 12), in: hosted, count: 2)
                let selected = try #require(hosted.title.accessibilitySelectedText())
                #expect(selected == "Stars", "\(selected)")
                // The first click opened it; the second didn't again.
                #expect(hosted.opened.urls == [Self.url])
            }
        }

        @Test func aTripleClickSelectsTheDescription() async throws {
            try await withClicksAccepted {
                let hosted = try await host(.standard)
                defer { hosted.close() }
                try await click(at: hosted.point(in: hosted.summary, x: 30), in: hosted, count: 3)
                let selected = try #require(hosted.summary.accessibilitySelectedText())
                #expect(selected.hasPrefix("Young stars light up"), "\(selected)")
                #expect(hosted.opened.urls == [Self.url])
            }
        }

        // MARK: Inside the card

        @Test func aBlurredImageRevealsWithoutOpeningThePage() async throws {
            try await withClicksAccepted {
                let hosted = try await host(.standard, blurredImage: true)
                defer { hosted.close() }
                let standIn = try #require(hosted.regionView.excluded.first, "the stand-in isn't left out of the card's link")
                #expect(standIn.width > 50 && standIn.height > 50, "\(standIn)")
                let onStandIn = hosted.regionView.convert(CGPoint(x: standIn.midX, y: standIn.midY), to: nil)
                try await click(at: onStandIn, in: hosted)
                #expect(hosted.opened.urls.isEmpty)
                // The rest of the card still opens.
                try await click(at: hosted.point(in: hosted.title, x: 10), in: hosted)
                #expect(hosted.opened.urls == [Self.url])
            }
        }

        @Test func thePointerIsAHandOverTheCardButNotOverTheStandIn() async throws {
            let hosted = try await host(.standard, blurredImage: true)
            defer { hosted.close() }
            let regionView = hosted.regionView
            let content = try #require(hosted.window.contentView)
            var eventType: NSEvent.EventType? = .mouseMoved
            regionView.currentEventType = { eventType }
            let standIn = try #require(regionView.excluded.first)
            let onStandIn = regionView.convert(CGPoint(x: standIn.midX, y: standIn.midY), to: nil)
            for point in [hosted.point(in: hosted.title, x: 10), hosted.point(in: hosted.summary, x: 10), hosted.paddingPoint] {
                #expect(content.hitTest(point) === regionView)
            }
            #expect(content.hitTest(onStandIn) !== regionView)
            // Clicks go through to the text, which selects.
            eventType = .leftMouseDown
            #expect(content.hitTest(hosted.point(in: hosted.title, x: 10)) !== regionView)
        }

        // MARK: Context menu

        /// The menu a right-click (or Control-click) at `point` opens: the
        /// view it lands on, or the first up the responder chain with one.
        /// Asked for directly; a real one would open on screen.
        private func contextMenu(at point: CGPoint, in hosted: Hosted, control: Bool = false) -> (view: NSView?, items: [String]) {
            let region = hosted.regionView
            region.currentEventType = { control ? .leftMouseDown : .rightMouseDown }
            region.currentModifiers = { control ? .control : [] }
            defer {
                region.currentEventType = { NSApplication.shared.currentEvent?.type }
                region.currentModifiers = { NSApplication.shared.currentEvent?.modifierFlags ?? [] }
            }
            let event = control
                ? event(.leftMouseDown, at: point, in: hosted, modifiers: .control)
                : event(.rightMouseDown, at: point, in: hosted)
            let target = hosted.window.contentView?.superview?.hitTest(point)
            var responder: NSView? = target
            while let view = responder {
                if let menu = view.menu(for: event) {
                    return (target, menu.items.map(\.title).filter { !$0.isEmpty })
                }
                responder = view.superview
            }
            return (target, [])
        }

        @Test func rightClicksOnTheCardShowItsMenuAndOnSelectedTextCopy() async throws {
            try await withClicksAccepted {
                let hosted = try await host(.standard)
                defer { hosted.close() }
                let onTitle = hosted.point(in: hosted.title, x: 12)
                // Selectable text shows only its own text menu, so the card
                // takes right-clicks and Control-clicks: they open its menu.
                for (point, control) in [(onTitle, false), (onTitle, true), (hosted.point(in: hosted.summary, x: 12), false), (hosted.paddingPoint, false)] {
                    let menu = contextMenu(at: point, in: hosted, control: control)
                    #expect(menu.view === hosted.regionView)
                    #expect(Array(menu.items.prefix(2)) == ["Open Link", "Copy Link"], "\(menu.items)")
                    #expect(menu.items.contains("Hide Previews"), "\(menu.items)")
                }
                // On selected text, the text's own menu: Copy, Look Up…
                try await click(at: onTitle, in: hosted, count: 2)
                #expect(hosted.title.accessibilitySelectedText() == "Stars")
                let onSelection = contextMenu(at: onTitle, in: hosted)
                #expect(onSelection.view === hosted.title)
                #expect(onSelection.items.contains("Copy"), "\(onSelection.items)")
                #expect(onSelection.items.contains { $0.hasPrefix("Look Up") }, "\(onSelection.items)")
                // Elsewhere on the card, its menu again.
                let elsewhere = contextMenu(at: hosted.point(in: hosted.summary, x: 12), in: hosted)
                #expect(elsewhere.items.first == "Open Link", "\(elsewhere.items)")
                // None of that opened anything more than the double-click's first click.
                #expect(hosted.opened.urls == [Self.url])
            }
        }
    }
}
