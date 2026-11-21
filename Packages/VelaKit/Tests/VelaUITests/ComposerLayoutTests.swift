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

/// Answers every link preview request with a small page, a little later.
/// Nothing leaves the Mac.
private nonisolated final class PreviewPageStandIn: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let delay = 80 + abs(url.path.hashValue) % 300
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delay)) { [self] in
            let html = """
                <html><head><title>Story \(url.lastPathComponent): a headline long enough to need room</title>
                <meta property="og:description" content="A summary of the story that goes on long enough to wrap.">
                <meta property="og:site_name" content="Example News"></head><body></body></html>
                """
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(html.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// While the list follows the newest line, that line stays in full view
/// above the composer, whatever takes height from the list: the composer
/// growing a line as you type, a pasted or drafted message, the reply bar,
/// the window getting shorter, tabs moving to the bottom. The conversation
/// moves up instead, as in Messages. Scrolled up, the reader stays put.
///
/// The list's bottom anchor used to lose that move on the Mac (it reached
/// the scroll view while the list was still its old height) while SwiftUI
/// reported the list at the bottom: the newest line stayed under the
/// composer by as much as the list got shorter, until another message came.
///
/// The column is hosted as in the window (`ChatColumnView`) in an
/// offscreen window. The newest line is a mention, whose bar at the rows'
/// leading edge is found in a render of the list.
@MainActor
@Suite("Newest line above the composer", .serialized)
struct ComposerLayoutTests {
    private final class Hosted {
        let app: AppModel
        let uiState: UIState
        let session: NetworkSession
        let buffer: BufferModel
        let window: NSWindow
        let host: NSView
        let mentionColor: NSColor

        init(app: AppModel, uiState: UIState, session: NetworkSession, buffer: BufferModel, window: NSWindow, host: NSView, mentionColor: NSColor) {
            self.app = app
            self.uiState = uiState
            self.session = session
            self.buffer = buffer
            self.window = window
            self.host = host
            self.mentionColor = mentionColor
        }

        func close() {
            window.orderOut(nil)
            window.contentView = nil
        }
    }

    struct Setup: CustomStringConvertible, Sendable {
        var preset: String
        /// Videos, link previews and long messages among one-liners, so
        /// most rows are estimated; otherwise short lines only.
        var busy = false
        var description: String { "\(preset)\(busy ? ", busy" : "")" }

        var settingsPreset: SettingsPreset {
            SettingsPreset.all.first { $0.id == preset } ?? .modern
        }
    }

    private static var lineNumber = 0

    private static func line(_ nick: String, _ text: String, at time: Date, isHighlight: Bool = false, isHistory: Bool) -> ChatLine {
        lineNumber += 1
        return ChatLine(msgid: "composer-\(lineNumber)", time: time, kind: .message, nick: nick, userHost: "\(nick)@user/\(nick)", text: text, isHighlight: isHighlight, isHistory: isHistory)
    }

    private static func text(_ index: Int, busy: Bool) -> String {
        guard busy else { return "message number \(index)" }
        if index % 9 == 0 { return "watch this https://www.youtube.com/watch?v=aqz-KE-bpKQ&t=\(index)" }
        if index % 7 == 2 {
            return String(repeating: "a long message that wraps over several lines, number \(index), ", count: 1 + (index * 7919) % 30)
        }
        switch index % 9 {
        case 3, 6: return "article: https://news.example.org/story/\(index) worth a read"
        default: return "message number \(index)"
        }
    }

    /// Fills `buffer` with conversation that ends in a mention.
    private static func fill(_ buffer: BufferModel, lines: Int, busy: Bool) {
        let start = Date().addingTimeInterval(-Double(lines + 10) * 30)
        buffer.insertSorted((0..<lines).map { index in
            line(["ann", "bob", "cy", "dee"][index % 4], text(index, busy: busy), at: start.addingTimeInterval(Double(index) * 30), isHistory: true)
        })
        buffer.insertSorted([line("gus", "doug: the newest line", at: start.addingTimeInterval(Double(lines) * 30), isHighlight: true, isHistory: true)])
    }

    private func host(_ setup: Setup) throws -> Hosted {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaComposerLayout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewPageStandIn.self]
        let app = AppModel(
            settings: SettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            networkStore: NetworkConfigStore(fileURL: root.appendingPathComponent("networks.json")),
            database: nil,
            previewService: LinkPreviewService(session: URLSession(configuration: configuration), browser: nil),
            isDemo: true
        )
        DemoContent.populate(app)
        app.settings.apply(setup.settingsPreset)
        // Video thumbnails come from ytimg.com, which the stand-in doesn't
        // serve: never fetched. The players keep their size without them.
        app.settings[.mediaSiteRules] = ["ytimg.com": .string("block")]
        let session = try #require(app.sessions.first)
        let buffer = session.ensureBuffer(name: "##composer", kind: .channel, persist: false)
        Self.fill(buffer, lines: setup.busy ? 600 : 120, busy: setup.busy)
        app.select(buffer)

        let size = CGSize(width: 900, height: 640)
        let themeStore = ThemeStore(userThemesDirectory: root.appendingPathComponent("Themes"))
        let uiState = UIState()
        // Sized by the window, so resizing it resizes the column.
        let view = ChatColumnView()
            .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: SceneServices(intelligence: .demo()), isPrimary: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        let mentionColor = try #require(themeStore.current.color(ThemeKey.chatHighlightBorder).nsColor.usingColorSpace(.sRGB))
        return Hosted(app: app, uiState: uiState, session: session, buffer: buffer, window: window, host: host, mentionColor: mentionColor)
    }

    // MARK: Looking

    private static func findAll(in view: NSView, where matches: (NSView) -> Bool) -> [NSView] {
        (matches(view) ? [view] : []) + view.subviews.flatMap { findAll(in: $0, where: matches) }
    }

    /// Where things are, in the column's coordinates (top down).
    private struct Layout: CustomStringConvertible {
        var list: CGRect
        var composer: CGRect
        /// The newest line's bottom, from the list's top edge; nil when it
        /// isn't in view.
        var newestLineBottom: CGFloat?
        /// The list's scroll offset, as the scroll view has it.
        var offset: CGFloat

        /// Room between the newest line and the list's bottom edge; nil
        /// when the line is out of view.
        var gapBelowNewestLine: CGFloat? { newestLineBottom.map { list.height - $0 } }

        var description: String {
            "list \(list), composer \(composer), gap below the newest line \(gapBelowNewestLine.map { "\($0)" } ?? "none (out of view)"), offset \(offset)"
        }
    }

    private func composerTextView(_ hosted: Hosted) throws -> ComposerNSTextView {
        try #require(Self.findAll(in: hosted.host) { $0 is ComposerNSTextView }.first as? ComposerNSTextView)
    }

    private func layout(_ hosted: Hosted) throws -> Layout {
        hosted.host.layoutSubtreeIfNeeded()
        let scrollViews = Self.findAll(in: hosted.host) { $0 is NSScrollView }.compactMap { $0 as? NSScrollView }
        let list = try #require(scrollViews.max { $0.frame.height < $1.frame.height })
        let composer = try #require(try composerTextView(hosted).enclosingScrollView)
        func inColumn(_ view: NSView) -> CGRect {
            let rect = view.convert(view.bounds, to: hosted.host)
            return hosted.host.isFlipped ? rect : CGRect(x: rect.minX, y: hosted.host.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        }
        // The rows' leading edge, where a mention has its bar. (The list's
        // own render: the typing line drawn over it isn't in it.)
        var strip = list.bounds
        strip.size.width = 4
        let rep = try #require(list.bitmapImageRepForCachingDisplay(in: strip))
        list.cacheDisplay(in: strip, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / strip.height
        let mention = hosted.mentionColor
        var lowest: Int?
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let difference = abs(color.redComponent - mention.redComponent) + abs(color.greenComponent - mention.greenComponent) + abs(color.blueComponent - mention.blueComponent)
                if difference < 0.2 { lowest = y }
            }
        }
        return Layout(
            list: inColumn(list),
            composer: inColumn(composer),
            newestLineBottom: lowest.map { CGFloat($0 + 1) / scale },
            offset: list.contentView.bounds.minY
        )
    }

    /// The layout once `holds` does, or after `seconds` (bar animations
    /// and the list's checks take a fraction of that).
    private func settled(_ hosted: Hosted, within seconds: Double = 2.5, until holds: (Layout) -> Bool) async throws -> Layout {
        let deadline = Date().addingTimeInterval(seconds)
        try await Task.sleep(for: .milliseconds(200))
        var layout = try layout(hosted)
        while !holds(layout), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            layout = try self.layout(hosted)
        }
        return layout
    }

    /// The newest line's gap once the list has opened at the bottom.
    private func openedGap(_ hosted: Hosted) async throws -> CGFloat {
        try await Task.sleep(for: .milliseconds(800))
        let opened = try await settled(hosted, within: 6) { layout in
            layout.gapBelowNewestLine.map { abs($0 - ListEndSpacing.resting) <= 1 } ?? false
        }
        let gap = try #require(opened.gapBelowNewestLine, "the newest line isn't in view after opening: \(opened)")
        #expect(abs(gap - ListEndSpacing.resting) <= 1, "the list didn't open at the newest line: \(opened)")
        return gap
    }

    /// After `step`, the composer sits under the list without covering it,
    /// and the newest line sits `gap` above the list's bottom edge, as it
    /// did before.
    private func expectNewestLineInView(_ hosted: Hosted, gap: CGFloat, _ step: String, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let layout = try await settled(hosted) { layout in
            layout.gapBelowNewestLine.map { abs($0 - gap) <= 1 } ?? false
        }
        #expect(layout.composer.minY >= layout.list.maxY - 0.5, "\(step): the composer overlaps the list: \(layout)", sourceLocation: sourceLocation)
        let shown = try #require(layout.gapBelowNewestLine, "\(step): the newest line is out of view: \(layout)", sourceLocation: sourceLocation)
        #expect(abs(shown - gap) <= 1, "\(step): the newest line isn't \(gap) pt above the list's bottom edge: \(layout)", sourceLocation: sourceLocation)
    }

    // MARK: Tests

    private nonisolated static let setups = [Setup(preset: "modern"), Setup(preset: "focus"), Setup(preset: "classic", busy: true)]

    /// Typing past one line, as reported: each new line pushes the
    /// conversation up; deleting them brings it back down.
    @Test(arguments: setups)
    func typingLinesPushesTheConversationUp(_ setup: Setup) async throws {
        let hosted = try host(setup)
        defer { hosted.close() }
        let gap = try await openedGap(hosted)
        let composer = try composerTextView(hosted)
        let oneLine = try layout(hosted).composer.height
        composer.insertText("a message that", replacementRange: composer.selectedRange())
        for index in 1...3 {
            composer.insertNewlineIgnoringFieldEditor(nil)
            composer.insertText("goes on for line \(index + 1)", replacementRange: composer.selectedRange())
            try await expectNewestLineInView(hosted, gap: gap, "line \(index + 1) typed")
        }
        #expect(try layout(hosted).composer.height > oneLine + 40, "the composer didn't grow")
        // Pasted at once.
        composer.insertText("\nand\nthree more", replacementRange: composer.selectedRange())
        try await expectNewestLineInView(hosted, gap: gap, "two lines pasted")
        composer.selectAll(nil)
        composer.insertText("", replacementRange: composer.selectedRange())
        try await expectNewestLineInView(hosted, gap: gap, "text deleted")
    }

    /// A multi-line draft put in from elsewhere (Siri's "draft a message"),
    /// and the reply bar coming and going.
    @Test func draftsAndTheReplyBarPushTheConversationUp() async throws {
        let hosted = try host(Setup(preset: "modern"))
        defer { hosted.close() }
        let gap = try await openedGap(hosted)
        hosted.uiState.drafts[hosted.buffer.id] = "a drafted message\nover\nthree lines"
        try await expectNewestLineInView(hosted, gap: gap, "draft put in")
        let target = hosted.buffer.lines[hosted.buffer.lines.count - 3]
        hosted.uiState.replyTargets[hosted.buffer.id] = target
        try await expectNewestLineInView(hosted, gap: gap, "reply bar shown")
        hosted.uiState.replyTargets[hosted.buffer.id] = nil
        try await expectNewestLineInView(hosted, gap: gap, "reply bar hidden")
        // The reply bar first, then the text grows under it.
        hosted.uiState.drafts[hosted.buffer.id] = ""
        try await expectNewestLineInView(hosted, gap: gap, "draft cleared")
        hosted.uiState.replyTargets[hosted.buffer.id] = target
        try await expectNewestLineInView(hosted, gap: gap, "reply bar shown again")
        let composer = try composerTextView(hosted)
        composer.insertText("replying\nat some length", replacementRange: composer.selectedRange())
        try await expectNewestLineInView(hosted, gap: gap, "reply typed")
    }

    /// With someone typing, the newest line stays above the typing line too
    /// as the composer grows.
    @Test func theTypingLineStaysClearAsTheComposerGrows() async throws {
        let hosted = try host(Setup(preset: "modern"))
        defer { hosted.close() }
        _ = try await openedGap(hosted)
        hosted.buffer.typingNicks = ["zed"]
        // The room for the typing line opens with an animation. Wait until
        // it's open and holding still, not a fixed time: a CI machine running
        // other suites at once can take far longer.
        var previous: CGFloat?
        var still = 0
        let opened = try await settled(hosted, within: 6) { layout in
            guard let gap = layout.gapBelowNewestLine, gap > ListEndSpacing.resting + 5 else {
                previous = nil
                still = 0
                return false
            }
            still = previous.map { abs($0 - gap) < 0.5 } == true ? still + 1 : 0
            previous = gap
            return still >= 3
        }
        let withTypingLine = try #require(opened.gapBelowNewestLine)
        #expect(withTypingLine > ListEndSpacing.resting + 5, "no room was made for the typing line: \(opened)")
        let composer = try composerTextView(hosted)
        composer.insertText("one\ntwo\nthree", replacementRange: composer.selectedRange())
        try await expectNewestLineInView(hosted, gap: withTypingLine, "composer grown under the typing line")
    }

    /// The window getting taller, then shorter, and tabs moving to the
    /// bottom.
    @Test(arguments: [Setup(preset: "modern"), Setup(preset: "focus")])
    func aShorterListKeepsTheNewestLine(_ setup: Setup) async throws {
        let hosted = try host(setup)
        defer { hosted.close() }
        let gap = try await openedGap(hosted)
        var frame = hosted.window.frame
        frame.size.height += 41
        hosted.window.setFrame(frame, display: true)
        try await expectNewestLineInView(hosted, gap: gap, "window taller")
        frame.size.height -= 78
        hosted.window.setFrame(frame, display: true)
        try await expectNewestLineInView(hosted, gap: gap, "window shorter")
        if hosted.app.settings[.navigationStyle] == .tabs {
            hosted.app.settings[.tabsPlacement] = .bottom
            try await expectNewestLineInView(hosted, gap: gap, "tabs at the bottom")
        }
    }

    /// New lines, and a link preview that loads after its line arrived,
    /// while the composer is several lines tall.
    @Test func newLinesStayAboveATallComposer() async throws {
        let hosted = try host(Setup(preset: "modern"))
        defer { hosted.close() }
        let gap = try await openedGap(hosted)
        let composer = try composerTextView(hosted)
        composer.insertText("a\nlong\ndraft", replacementRange: composer.selectedRange())
        try await expectNewestLineInView(hosted, gap: gap, "composer grown")
        hosted.session.add(Self.line("gus", "doug: one more", at: Date(), isHighlight: true, isHistory: false), to: hosted.buffer)
        try await expectNewestLineInView(hosted, gap: gap, "new line")
        hosted.session.add(Self.line("gus", "doug: see https://news.example.org/story/fresh now", at: Date(), isHighlight: true, isHistory: false), to: hosted.buffer)
        try await Task.sleep(for: .milliseconds(600))   // the preview loads
        try await expectNewestLineInView(hosted, gap: gap, "link preview loaded")
    }

    /// Switching to a channel whose draft runs over several lines: the
    /// composer grows as the channel opens.
    @Test func openingAChannelWithALongDraftShowsTheNewestLine() async throws {
        let hosted = try host(Setup(preset: "modern"))
        defer { hosted.close() }
        _ = try await openedGap(hosted)
        let other = hosted.session.ensureBuffer(name: "##drafted", kind: .channel, persist: false)
        Self.fill(other, lines: 120, busy: false)
        hosted.uiState.drafts[other.id] = "a draft\nleft here\nover four\nlines"
        hosted.app.select(other)
        try await Task.sleep(for: .milliseconds(500))
        try await expectNewestLineInView(hosted, gap: ListEndSpacing.resting, "channel with a draft opened")
        #expect(try composerTextView(hosted).string.contains("over four"), "the draft wasn't restored")
    }

    /// A reader who scrolled up stays where they are while the composer grows.
    @Test func aReaderScrolledUpStaysPut() async throws {
        let hosted = try host(Setup(preset: "modern"))
        defer { hosted.close() }
        _ = try await openedGap(hosted)
        hosted.uiState.scrollTarget = hosted.buffer.lines[hosted.buffer.lines.count - 60].id
        try await Task.sleep(for: .milliseconds(1200))
        let before = try layout(hosted)
        #expect(before.newestLineBottom == nil, "the jump didn't scroll away from the newest line: \(before)")
        let composer = try composerTextView(hosted)
        composer.insertText("one\ntwo\nthree\nfour", replacementRange: composer.selectedRange())
        try await Task.sleep(for: .milliseconds(800))
        let after = try layout(hosted)
        let shrink = before.list.height - after.list.height
        #expect(shrink > 40, "the composer didn't grow: \(after)")
        // The jump leaves SwiftUI holding the line it went to, at the
        // centre, which it may keep there as the list gets shorter (half the
        // shrink; seen on slower Macs). Never more than the list lost, and
        // never down to the newest line.
        #expect(abs(after.offset - before.offset) <= shrink / 2 + 1, "the reader was moved: \(before) → \(after)")
        #expect(after.newestLineBottom == nil, "the reader was taken to the newest line: \(after)")
    }
}
