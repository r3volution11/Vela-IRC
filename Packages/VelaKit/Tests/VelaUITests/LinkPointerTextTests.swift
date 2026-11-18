// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
@testable import VelaUI

@MainActor
@Suite("Pointing hand over links", .serialized)
struct LinkPointerTextTests {
    private static let link = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    private let palette = MessageTextPalette(
        foreground: .black, background: .white, link: Color(nsColor: link), mention: .purple,
        codeForeground: .green, codeBackground: .gray,
        irc: (0..<99).map { Color(white: Double($0) / 99) },
        monospaceFont: .system(size: 13, design: .monospaced)
    )

    /// `<doug> ` in bold red, then the rendered message, as the classic layout composes it.
    private func message(_ text: String) -> AttributedString {
        var prefix = AttributedString("<doug> ")
        prefix.font = .system(size: 13, weight: .bold)
        prefix.foregroundColor = .red
        let rendered = MessageTextRenderer.render(text, palette: palette, options: MessageTextOptions(selfNick: "doug"))
        return prefix + rendered.attributed
    }

    // MARK: Link runs

    @Test func linkRunsAreUTF16Ranges() {
        // "<doug> see " is 11 units, the emoji 2, then a space.
        let text = message("see 🙂 https://example.com/a and #vela ok")
        #expect(LinkRuns.ranges(in: text) == [14..<35, 40..<45])
    }

    @Test func textWithoutLinksHasNoRuns() {
        #expect(LinkRuns.ranges(in: message("just words, doug, and #1")).isEmpty)
        #expect(LinkRuns.ranges(in: AttributedString("")).isEmpty)
    }

    @Test func aLinkSplitByFormattingIsOneRange() {
        // Bold covers only part of the URL; it's still one link.
        let text = message("\u{02}https://bold\u{02}.example/x")
        #expect(LinkRuns.ranges(in: text) == [7..<29])
    }

    // MARK: Regions

    @Test func linksKeepTheirURLsAndText() {
        let links = LinkRuns.links(in: message("see https://example.com/a and #vela ok"))
        #expect(links.map(\.url) == [URL(string: "https://example.com/a")!, ChannelLink.url(for: "#vela")!])
        #expect(links.map(\.title) == ["https://example.com/a", "#vela"])
    }

    @Test func removingLinksKeepsTheTextAndItsStyle() {
        let text = message("see \u{02}https://bold\u{02}.example/x and #vela")
        let plain = LinkRuns.removingLinks(from: text)
        #expect(LinkRuns.links(in: plain).isEmpty)
        #expect(String(plain.characters) == String(text.characters))
        // Everything else, link color and bold included, is untouched.
        var expected = text
        for (link, range) in text.runs[\.link] where link != nil {
            expected[range].link = nil
        }
        #expect(plain == expected)
        #expect(plain.runs.count == text.runs.count)
    }

    @Test func regionsHitTestTheirRects() {
        let regions = LinkRegions()
        #expect(!regions.contains(CGPoint(x: 5, y: 5)))
        regions.update([
            .init(rect: CGRect(x: 0, y: 0, width: 10, height: 10), link: 0),
            .init(rect: CGRect(x: 20, y: 0, width: 10, height: 10), link: 1),
        ])
        #expect(regions.link(at: CGPoint(x: 5, y: 5)) == 0)
        #expect(!regions.contains(CGPoint(x: 15, y: 5)))
        #expect(regions.link(at: CGPoint(x: 25, y: 9)) == 1)
        #expect(!regions.contains(CGPoint(x: 25, y: 11)))
        regions.update([])
        #expect(!regions.contains(CGPoint(x: 5, y: 5)))
    }

    @Test func onlyPointerMovementIsClaimed() {
        for type: NSEvent.EventType in [.mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate] {
            #expect(LinkPointerRegionView.claimsPointer(during: type))
        }
        let passThrough: [NSEvent.EventType?] = [
            nil, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .scrollWheel, .keyDown, .flagsChanged, .magnify, .pressure,
        ]
        for type in passThrough {
            #expect(!LinkPointerRegionView.claimsPointer(during: type))
        }
    }

    @Test func outsideAnEventNothingIsClaimed() {
        let regions = LinkRegions()
        regions.update([.init(rect: CGRect(x: 0, y: 0, width: 100, height: 100), link: 0)])
        let view = LinkPointerRegionView(regions: regions)
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        // No pointer event is being handled here.
        #expect(view.hitTest(CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func hitTestsUseTopLeftCoordinates() {
        let regions = LinkRegions()
        regions.update([.init(rect: CGRect(x: 0, y: 0, width: 50, height: 20), link: 0)])
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let view = LinkPointerRegionView(regions: regions)
        view.frame = container.bounds
        container.addSubview(view)
        var eventType: NSEvent.EventType? = .mouseMoved
        view.currentEventType = { eventType }
        // The container is bottom-left origin: y 95 is near the top.
        #expect(view.hitTest(CGPoint(x: 10, y: 95)) === view)
        #expect(view.hitTest(CGPoint(x: 10, y: 10)) == nil)
        #expect(view.hitTest(CGPoint(x: 60, y: 95)) == nil)
        eventType = .leftMouseDown
        #expect(view.hitTest(CGPoint(x: 10, y: 95)) == nil)
    }

    @Test func aWholeViewLinkClaimsItselfButNotItsControls() {
        // A link preview (`linkClickArea`): all of it but a button inside.
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let view = LinkPointerRegionView(regions: LinkRegions())
        view.coversBounds = true
        view.frame = container.bounds
        view.excluded = [CGRect(x: 150, y: 0, width: 50, height: 50)]
        container.addSubview(view)
        var eventType: NSEvent.EventType? = .mouseMoved
        var modifiers: NSEvent.ModifierFlags = []
        view.currentEventType = { eventType }
        view.currentModifiers = { modifiers }
        // Container coordinates are bottom-left origin: y 95 is near the top.
        #expect(view.linkIndex(at: CGPoint(x: 10, y: 90)) == 0)
        #expect(view.linkIndex(at: CGPoint(x: 160, y: 10)) == nil)
        #expect(view.hitTest(CGPoint(x: 10, y: 5)) === view)
        #expect(view.hitTest(CGPoint(x: 160, y: 95)) == nil)
        #expect(view.hitTest(CGPoint(x: 260, y: 95)) == nil)
        // Clicks go through to the text; context clicks open the view's menu.
        eventType = .leftMouseDown
        #expect(view.hitTest(CGPoint(x: 10, y: 5)) == nil)
        modifiers = .control
        #expect(view.hitTest(CGPoint(x: 10, y: 5)) === view)
        #expect(view.hitTest(CGPoint(x: 160, y: 95)) == nil)
        modifiers = []
        eventType = .rightMouseDown
        #expect(view.hitTest(CGPoint(x: 10, y: 5)) === view)
        // Links in text leave context clicks to the text.
        view.coversBounds = false
        view.regions.update([.init(rect: CGRect(x: 0, y: 0, width: 50, height: 20), link: 0)])
        #expect(view.hitTest(CGPoint(x: 10, y: 95)) == nil)
    }

    @Test func contextClicksAreRightClicksAndControlClicks() {
        #expect(LinkPointerRegionView.isContextClick(.rightMouseDown, modifiers: []))
        #expect(LinkPointerRegionView.isContextClick(.leftMouseDown, modifiers: .control))
        #expect(LinkPointerRegionView.isContextClick(.leftMouseDown, modifiers: [.control, .option]))
        #expect(!LinkPointerRegionView.isContextClick(.leftMouseDown, modifiers: []))
        #expect(!LinkPointerRegionView.isContextClick(.leftMouseDown, modifiers: .command))
        #expect(!LinkPointerRegionView.isContextClick(.rightMouseUp, modifiers: []))
        #expect(!LinkPointerRegionView.isContextClick(nil, modifiers: .control))
    }

    // MARK: Laid out offscreen

    private struct Hosted {
        let window: NSWindow
        let host: NSView
        let regionView: LinkPointerRegionView?
        let bitmap: NSBitmapImageRep

        /// The link rects in the host's coordinates (top-left origin).
        var rects: [CGRect] {
            guard let regionView else { return [] }
            return regionView.regions.rects.map { regionView.convert($0, to: host) }
        }
    }

    /// `plainText` hosts a plain `Text` with its links instead, for
    /// comparison.
    private func host(_ text: AttributedString, width: CGFloat, italic: Bool = false, size: CGFloat = 13, lineSpacing: CGFloat = 3, plainText: Bool = false) -> Hosted {
        let style = { (text: Text) in
            text
                .font(.system(size: size))
                .italic(italic)
                .foregroundStyle(Color.black)
        }
        let view = Group {
            if plainText {
                style(Text(text))
            } else {
                LinkPointerText(text, style: style)
            }
        }
        .lineSpacing(lineSpacing)
        .tint(Color(nsColor: Self.link))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: width, alignment: .topLeading)
        .padding(12)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: -8000, y: -8000, width: width + 24, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return Hosted(window: window, host: host, regionView: Self.find(LinkPointerRegionView.self, in: host), bitmap: bitmap)
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = find(type, in: subview) { return match }
        }
        return nil
    }

    /// Pixels drawn in the link color, and in dark body text, as points in the host.
    private func inkPoints(_ hosted: Hosted) -> (link: [CGPoint], body: [CGPoint]) {
        let bitmap = hosted.bitmap
        let scale = CGFloat(bitmap.pixelsWide) / hosted.host.bounds.width
        let flipped = hosted.host.isFlipped
        var link: [CGPoint] = [], body: [CGPoint] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                var point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                if !flipped { point.y = hosted.host.bounds.height - point.y }
                if b - max(r, g) > 0.45 {
                    link.append(point)
                } else if max(r, g, b) < 0.35 {
                    body.append(point)
                }
            }
        }
        return (link, body)
    }

    private func check(_ hosted: Hosted, expectedRects: Int? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
        let rects = hosted.rects
        #expect(hosted.regionView != nil, "no pointer regions over text with links", sourceLocation: sourceLocation)
        #expect(!rects.isEmpty, sourceLocation: sourceLocation)
        if let expectedRects {
            #expect(rects.count == expectedRects, "\(rects)", sourceLocation: sourceLocation)
        }
        let ink = inkPoints(hosted)
        #expect(ink.link.count > 50, "the link color wasn't drawn", sourceLocation: sourceLocation)
        // Every link pixel sits inside a link rect (allowing for antialiasing).
        let grown = rects.map { $0.insetBy(dx: -1, dy: -1) }
        let stray = ink.link.filter { point in !grown.contains { $0.contains(point) } }
        #expect(stray.isEmpty, "\(stray.count) link pixels outside \(rects), e.g. \(stray.prefix(3))", sourceLocation: sourceLocation)
        // And the plain text stays outside them (it keeps the I-beam).
        let shrunk = rects.map { $0.insetBy(dx: 1, dy: 1) }
        let inside = ink.body.filter { point in shrunk.contains { $0.contains(point) } }
        #expect(inside.count * 50 <= ink.body.count, "\(inside.count) of \(ink.body.count) body pixels inside link rects", sourceLocation: sourceLocation)
        // Each rect is mostly link: no rect spans plain text.
        for rect in rects {
            #expect(ink.link.contains { rect.contains($0) }, "an empty link rect \(rect)", sourceLocation: sourceLocation)
        }
    }

    @Test func drawsExactlyLikeTextWithItsLinks() {
        // The visible text has no links (so it selects everywhere) but must
        // look the same: same color, no underline, same lines.
        for (text, width) in [
            (message("see https://example.com/a and #vela ok"), 600.0),
            (message("see 🙂 https://example.com/a/rather/long/path/that/wraps?q=1 and then #vela ok"), 190.0),
        ] {
            let ours = host(text, width: width)
            let plain = host(text, width: width, plainText: true)
            #expect(ours.bitmap.pixelsWide == plain.bitmap.pixelsWide)
            #expect(ours.bitmap.pixelsHigh == plain.bitmap.pixelsHigh)
            #expect(ours.bitmap.tiffRepresentation == plain.bitmap.tiffRepresentation)
        }
    }

    @Test func rectsCoverTheLinksOnOneLine() {
        let hosted = host(message("see https://example.com/a and #vela ok"), width: 600)
        check(hosted, expectedRects: 2)
        #expect(hosted.regionView?.regions.regions.map(\.link) == [0, 1])
        #expect(hosted.regionView?.urls == [URL(string: "https://example.com/a")!, ChannelLink.url(for: "#vela")!])
    }

    @Test func rectsFollowALinkOntoTheNextLine() {
        // The URL breaks across lines, after an emoji and the bold prefix.
        let hosted = host(message("see 🙂 https://example.com/a/rather/long/path/that/wraps?q=1 and then #vela ok"), width: 190)
        check(hosted)
        let rects = hosted.rects
        #expect(Set(rects.map { $0.minY.rounded() }).count >= 2, "\(rects)")
    }

    @Test func rectsHoldForItalicActions() {
        // Italics outset the layout from the frame.
        check(host(message("waves at https://example.com/hello and #vela"), width: 420, italic: true), expectedRects: 2)
    }

    @Test func rectsHoldForLargeTextAndWideLineSpacing() {
        check(host(message("🙂 big https://example.com/x #vela"), width: 700, size: 26, lineSpacing: 8), expectedRects: 2)
    }

    @Test func textWithoutLinksGetsNoRegions() {
        let hosted = host(message("no links here, just #1 and doug"), width: 400)
        #expect(hosted.regionView == nil)
    }

    @Test func pointerMovesClaimLinksAndClicksFallThrough() throws {
        let hosted = host(message("see https://example.com/a and more text"), width: 600)
        let regionView = try #require(hosted.regionView)
        let linkRect = try #require(regionView.regions.rects.first)
        let content = try #require(hosted.window.contentView)
        // Points in the content view's superview (window) coordinates.
        let onLink = regionView.convert(CGPoint(x: linkRect.midX, y: linkRect.midY), to: nil)
        let offLink = regionView.convert(CGPoint(x: linkRect.maxX + 40, y: linkRect.midY), to: nil)
        var eventType: NSEvent.EventType? = .mouseMoved
        regionView.currentEventType = { eventType }

        // Moving over the link claims it, so its pointer style applies.
        #expect(content.hitTest(onLink) === regionView)
        let textView = content.hitTest(offLink)
        #expect(textView != nil)
        #expect(textView !== regionView)

        // Clicks and the rest reach the selectable text underneath, as they
        // do beside the link.
        for type: NSEvent.EventType? in [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, nil] {
            eventType = type
            #expect(content.hitTest(onLink) === textView, "\(String(describing: type))")
        }
    }
}
