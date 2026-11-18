// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
@testable import VelaUI

// MARK: Clicks, drags and multi-clicks

@Suite("Telling link clicks from selecting")
struct LinkClickTrackerTests {
    private typealias Tracker = LinkClickTracker<String>
    private let onLink = CGPoint(x: 100, y: 50)

    @Test func aClickOpensTheLinkOnRelease() {
        var tracker = Tracker()
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: "a")
        #expect(tracker.mouseUp(at: onLink, clickCount: 1) == "a")
        // Nothing is left over to open later.
        #expect(tracker.mouseUp(at: onLink, clickCount: 1) == nil)
    }

    @Test func aLittleWobbleIsStillAClick() {
        var tracker = Tracker()
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: "a")
        tracker.mouseDragged(to: CGPoint(x: 102, y: 51))
        tracker.mouseDragged(to: CGPoint(x: 103, y: 52))
        #expect(tracker.mouseUp(at: CGPoint(x: 102, y: 52), clickCount: 1) == "a")
    }

    @Test func aDragFromALinkSelectsInstead() {
        var tracker = Tracker()
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: "a")
        tracker.mouseDragged(to: CGPoint(x: 130, y: 50))
        #expect(tracker.mouseUp(at: CGPoint(x: 130, y: 50), clickCount: 1) == nil)
    }

    @Test func aDragThatComesBackIsStillADrag() {
        // Selecting, then changing your mind and returning to the link.
        var tracker = Tracker()
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: "a")
        tracker.mouseDragged(to: CGPoint(x: 160, y: 50))
        tracker.mouseDragged(to: onLink)
        #expect(tracker.mouseUp(at: onLink, clickCount: 1) == nil)
    }

    @Test func aReleaseAwayFromThePressIsNotAClick() {
        var tracker = Tracker()
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: "a")
        #expect(tracker.mouseUp(at: CGPoint(x: 100, y: 60), clickCount: 1) == nil)
    }

    @Test func aDoubleClickOpensTheLinkOnce() {
        // The first click opens it; the second selects a word and opens
        // nothing more.
        var tracker = Tracker()
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: "a")
        #expect(tracker.mouseUp(at: onLink, clickCount: 1) == "a")
        tracker.mouseDown(at: onLink, clickCount: 2, modifiers: [], target: "a")
        #expect(tracker.mouseUp(at: onLink, clickCount: 2) == nil)
    }

    @Test func aTripleClickOpensTheLinkOnce() {
        var tracker = Tracker()
        var opened: [String] = []
        for count in 1...3 {
            tracker.mouseDown(at: onLink, clickCount: count, modifiers: [], target: "a")
            if let link = tracker.mouseUp(at: onLink, clickCount: count) { opened.append(link) }
        }
        #expect(opened == ["a"])
    }

    @Test func separateClicksEachOpen() {
        // Clicks too far apart in time to make a double-click.
        var tracker = Tracker()
        let other = CGPoint(x: 300, y: 50)
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: "a")
        #expect(tracker.mouseUp(at: onLink, clickCount: 1) == "a")
        tracker.mouseDown(at: other, clickCount: 1, modifiers: [], target: "b")
        #expect(tracker.mouseUp(at: other, clickCount: 1) == "b")
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: "a")
        #expect(tracker.mouseUp(at: onLink, clickCount: 1) == "a")
    }

    @Test func pressesOffLinksOpenNothing() {
        var tracker = Tracker()
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: nil)
        #expect(tracker.mouseUp(at: onLink, clickCount: 1) == nil)
    }

    @Test func aPressOffALinkForgetsTheLastOne() {
        // A press that never got its release (a menu took it), then a click
        // beside the link.
        var tracker = Tracker()
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: "a")
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: nil)
        #expect(tracker.mouseUp(at: onLink, clickCount: 1) == nil)
    }

    @Test func commandAndOptionClicksOpenLinks() {
        for modifiers: NSEvent.ModifierFlags in [.command, .option, [.command, .option], .capsLock, .function] {
            var tracker = Tracker()
            tracker.mouseDown(at: onLink, clickCount: 1, modifiers: modifiers, target: "a")
            #expect(tracker.mouseUp(at: onLink, clickCount: 1) == "a", "\(modifiers)")
        }
    }

    @Test func shiftAndControlClicksDoNot() {
        // Shift extends the selection; Control-click opens the menu.
        for modifiers: NSEvent.ModifierFlags in [.shift, .control, [.command, .shift], [.control, .option]] {
            var tracker = Tracker()
            tracker.mouseDown(at: onLink, clickCount: 1, modifiers: modifiers, target: "a")
            #expect(tracker.mouseUp(at: onLink, clickCount: 1) == nil, "\(modifiers)")
        }
    }

    @Test func aForceClickDoesNotOpen() {
        // A deep press looks the word up instead.
        var tracker = Tracker()
        tracker.mouseDown(at: onLink, clickCount: 1, modifiers: [], target: "a")
        tracker.cancelPress()
        #expect(tracker.mouseUp(at: onLink, clickCount: 1) == nil)
    }
}

// MARK: In a window

/// Selectable message text with links, hosted in an offscreen window and
/// driven with synthetic mouse events, as AppKit delivers them.
@MainActor
@Suite("Selecting and opening links", .serialized)
struct LinkSelectionTests {
    private static let url = URL(string: "https://example.com/alpha/beta")!
    private static let channel = ChannelLink.url(for: "#vela")!
    private static let plain = "see https://example.com/alpha/beta and #vela then some more plain words"

    private let palette = MessageTextPalette(
        foreground: .black, background: .white, link: .blue, mention: .purple,
        codeForeground: .green, codeBackground: .gray,
        irc: (0..<99).map { Color(white: Double($0) / 99) },
        monospaceFont: .system(size: 13, design: .monospaced)
    )

    private final class Opened {
        var urls: [URL] = []
    }

    private final class Hosted {
        let window: NSWindow
        let host: NSView
        let textView: NSView
        let regionView: LinkPointerRegionView?
        let opened: Opened

        init(window: NSWindow, host: NSView, textView: NSView, regionView: LinkPointerRegionView?, opened: Opened) {
            self.window = window
            self.host = host
            self.textView = textView
            self.regionView = regionView
            self.opened = opened
        }

        /// The middle of link `index`, in window coordinates.
        func linkPoint(_ index: Int, dx: CGFloat = 0) throws -> CGPoint {
            let regionView = try #require(regionView)
            let rect = try #require(regionView.regions.regions.first { $0.link == index }?.rect)
            let x = dx >= 0 ? rect.minX + dx : rect.midX
            return regionView.convert(CGPoint(x: x, y: rect.midY), to: nil)
        }

        /// A point on the first line, `x` points from the text's leading
        /// edge (from its trailing edge when negative).
        func textPoint(x: CGFloat) -> CGPoint {
            let bounds = textView.bounds
            let local = CGPoint(x: x >= 0 ? bounds.minX + x : bounds.maxX + x, y: textView.isFlipped ? bounds.minY + 8 : bounds.maxY - 8)
            return textView.convert(local, to: nil)
        }

        var selectedText: String? { textView.accessibilitySelectedText() }

        /// What Copy puts on a pasteboard (a private one, not the
        /// clipboard).
        func copiedText() throws -> String? {
            let requestor = try #require(textView as? NSServicesMenuRequestor)
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

    private func message(_ text: String = Self.plain) -> AttributedString {
        MessageTextRenderer.render(text, palette: palette, options: MessageTextOptions(selfNick: "doug")).attributed
    }

    /// `covered` lays a view over the text, as the hover toolbar can be.
    private func host(_ text: AttributedString, linkText: Bool = true, covered: Bool = false) async throws -> Hosted {
        let opened = Opened()
        let content = Group {
            if linkText {
                LinkPointerText(text) { $0.font(.system(size: 13)).foregroundStyle(Color.black) }
            } else {
                // Plain SwiftUI text with its links, for comparison.
                Text(text).font(.system(size: 13)).foregroundStyle(Color.black)
            }
        }
        let view = content
            .tint(.blue)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 560, alignment: .topLeading)
            .overlay {
                if covered { Color.red.opacity(0.2) }
            }
            .padding(12)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.openURL, OpenURLAction { url in
                opened.urls.append(url)
                return .handled
            })
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: -8000, y: -8000, width: 584, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        // AppKit only delivers clicks to a window that's on screen (this one
        // is far off it).
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(100))
        let textView = try #require(Self.find(in: host) { NSStringFromClass(type(of: $0)).contains("TextInteraction") })
        // The test runner is never the active app, so AppKit only passes a
        // click on to a view that takes the first mouse.
        Self.acceptFirstMouse(type(of: textView))
        let regionView = Self.find(in: host) { $0 is LinkPointerRegionView } as? LinkPointerRegionView
        return Hosted(window: window, host: host, textView: textView, regionView: regionView, opened: opened)
    }

    private static func find(in view: NSView, where matches: (NSView) -> Bool) -> NSView? {
        if matches(view) { return view }
        for subview in view.subviews {
            if let match = find(in: subview, where: matches) { return match }
        }
        return nil
    }

    private static func acceptFirstMouse(_ viewClass: AnyClass) {
        let accept: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
        // Adds an override to that class only (a no-op once it has one).
        class_addMethod(viewClass, #selector(NSView.acceptsFirstMouse(for:)), imp_implementationWithBlock(accept), "c@:@")
    }

    // MARK: Events

    private static var eventNumber = 1000

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
    /// monitors see them too). Waits between them with the main actor free,
    /// so other tests' work isn't held up.
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

    /// Longer than the double-click interval used to be, when a click
    /// waited it out before opening.
    private func waitAWhile() async throws {
        try await Task.sleep(for: .milliseconds(600))
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

    // MARK: Why

    @Test func swiftUIWontStartASelectionOnALink() async throws {
        // The bug: selectable SwiftUI text declines to begin a selection on
        // a `.link` run, so a drag that starts there selects nothing. (If
        // this ever fails, SwiftUI has changed and the workaround may no
        // longer be needed.)
        try await withClicksAccepted {
            let hosted = try await host(message(), linkText: false)
            defer { hosted.close() }
            // Where the link is, measured on our text (it lays out the same).
            let ours = try await host(message())
            let start = try ours.linkPoint(0, dx: 1)
            ours.close()
            try await drag(from: start, to: hosted.textPoint(x: -4), in: hosted)
            #expect(hosted.selectedText?.isEmpty ?? true)
            // Starting just before it works.
            try await drag(from: hosted.textPoint(x: 1), to: hosted.textPoint(x: -4), in: hosted)
            #expect(hosted.selectedText?.hasPrefix("see https://") == true)
        }
    }

    // MARK: Selecting

    @Test func aDragStartingOnALinkSelectsText() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message())
            defer { hosted.close() }
            try await drag(from: try hosted.linkPoint(0, dx: 1), to: hosted.textPoint(x: -4), in: hosted)
            let selected = try #require(hosted.selectedText)
            #expect(selected.hasPrefix("https://example.com/alpha/beta and #vela then"), "\(selected)")
            #expect(hosted.opened.urls.isEmpty)
        }
    }

    @Test func aDragAcrossALinkCopiesItsFullText() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message())
            defer { hosted.close() }
            try await drag(from: hosted.textPoint(x: 1), to: hosted.textPoint(x: -1), in: hosted)
            let copied = try #require(try hosted.copiedText())
            #expect(copied.hasPrefix("see https://example.com/alpha/beta and #vela then some more plain wor"), "\(copied)")
            #expect(hosted.opened.urls.isEmpty)
        }
    }

    @Test func aDragEndingOnALinkOpensNothing() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message())
            defer { hosted.close() }
            try await drag(from: hosted.textPoint(x: -4), to: try hosted.linkPoint(0), in: hosted)
            #expect(!(hosted.selectedText ?? "").isEmpty)
            #expect(hosted.opened.urls.isEmpty)
        }
    }

    @Test func aDoubleClickInALinkSelectsAWordAndOpensItOnce() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message())
            defer { hosted.close() }
            // On "example".
            let regionView = try #require(hosted.regionView)
            let rect = try #require(regionView.regions.regions.first { $0.link == 0 }?.rect)
            let point = regionView.convert(CGPoint(x: rect.minX + rect.width * 0.35, y: rect.midY), to: nil)
            try await click(at: point, in: hosted, count: 2)
            let selected = try #require(hosted.selectedText)
            #expect(!selected.isEmpty)
            #expect(!selected.contains(" "), "\(selected)")
            #expect(Self.url.absoluteString.contains(selected), "\(selected)")
            // The first click opened it; the second didn't again.
            #expect(hosted.opened.urls == [Self.url])
        }
    }

    @Test func aTripleClickInALinkSelectsTheLineAndOpensItOnce() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message())
            defer { hosted.close() }
            try await click(at: try hosted.linkPoint(0), in: hosted, count: 3)
            let selected = try #require(hosted.selectedText)
            #expect(selected.hasPrefix(Self.plain), "\(selected)")
            #expect(hosted.opened.urls == [Self.url])
        }
    }

    // MARK: Opening

    @Test func aClickOnALinkOpensItOnRelease() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message())
            defer { hosted.close() }
            let point = try hosted.linkPoint(0)
            try await send([event(.leftMouseDown, at: point, in: hosted)])
            #expect(hosted.opened.urls.isEmpty)
            // At once: no waiting to see whether a second click follows.
            NSApp.sendEvent(event(.leftMouseUp, at: point, in: hosted))
            #expect(hosted.opened.urls == [Self.url])
            try await waitAWhile()
            #expect(hosted.opened.urls == [Self.url])
        }
    }

    @Test func aClickOnAChannelOpensItsJoinLink() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message())
            defer { hosted.close() }
            try await click(at: try hosted.linkPoint(1), in: hosted)
            #expect(hosted.opened.urls == [Self.channel])
        }
    }

    @Test func aCommandClickOpensTheLinkAndAShiftClickDoesNot() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message())
            defer { hosted.close() }
            try await click(at: try hosted.linkPoint(0), in: hosted, modifiers: .shift)
            #expect(hosted.opened.urls.isEmpty)
            try await click(at: try hosted.linkPoint(0), in: hosted, modifiers: .command)
            #expect(hosted.opened.urls == [Self.url])
        }
    }

    @Test func aClickOnPlainTextOpensNothing() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message())
            defer { hosted.close() }
            try await click(at: hosted.textPoint(x: 6), in: hosted)
            try await click(at: hosted.textPoint(x: -6), in: hosted)
            #expect(hosted.opened.urls.isEmpty)
        }
    }

    @Test func aCoveredLinkDoesNotOpen() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message(), covered: true)
            defer { hosted.close() }
            try await click(at: try hosted.linkPoint(0), in: hosted)
            #expect(hosted.opened.urls.isEmpty)
        }
    }

    @Test func clicksInAWindowThatIsNotKeyOpenNothing() async throws {
        // The first click only brings the window forward.
        _ = NSApplication.shared
        let hosted = try await host(message())
        defer { hosted.close() }
        #expect(!LinkClickMonitor.shared.acceptsClicks(hosted.window))
        try await click(at: try hosted.linkPoint(0), in: hosted)
        #expect(hosted.opened.urls.isEmpty)
    }

    // MARK: Copy Link

    @Test func aRightClickPicksTheLinkForCopyLink() async throws {
        try await withClicksAccepted {
            let hosted = try await host(message())
            defer { hosted.close() }
            let monitor = LinkClickMonitor.shared
            let links = [Self.url, URL(string: "https://example.org/other")!]
            // Handled directly: sending it would open a real menu.
            monitor.handle(event(.rightMouseDown, at: try hosted.linkPoint(0), in: hosted))
            #expect(monitor.contextLink(among: links) == Self.url)
            // Not one of the message's web links.
            monitor.handle(event(.rightMouseDown, at: try hosted.linkPoint(1), in: hosted))
            #expect(monitor.contextLink(among: links) == nil)
            monitor.handle(event(.leftMouseDown, at: try hosted.linkPoint(0), in: hosted, modifiers: .control))
            #expect(monitor.contextLink(among: links) == Self.url)
            monitor.handle(event(.rightMouseDown, at: hosted.textPoint(x: -6), in: hosted))
            #expect(monitor.contextLink(among: links) == nil)
            // A plain click (such as on the hover toolbar's More button)
            // forgets it.
            monitor.handle(event(.rightMouseDown, at: try hosted.linkPoint(0), in: hosted))
            monitor.handle(event(.leftMouseDown, at: hosted.textPoint(x: -6), in: hosted))
            #expect(monitor.contextLink(among: links) == nil)
            monitor.handle(event(.leftMouseUp, at: hosted.textPoint(x: -6), in: hosted))
        }
    }
}
