// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
@testable import VelaCore
import VelaIntelligence
import VelaIRC
import VelaMedia
import VelaStore
import VelaTheme
@testable import VelaUI

/// Answers every link preview request with a small page, a little later.
/// Nothing leaves the Mac.
private nonisolated final class SendPreviewStandIn: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let delay = 60 + abs(url.path.hashValue) % 200
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

/// Sending a message returns the list to the present, and it stays there
/// whatever arrives around it: your line coming back (echo-message) or
/// going out (without it), someone else's lines just before or after it, a
/// burst, the typing line going as they answer, a link preview growing,
/// the reply bar going, the composer shrinking back from several lines.
/// Once it settles, the newest line sits at the bottom of the list, above
/// the composer, and the list still follows the next line.
///
/// Reported: right after sending, now and then, the newest line ended up
/// under the composer, the list a row short of the bottom, until scrolled.
///
/// The column is hosted as in the window (`ChatColumnView`) in an offscreen
/// window, and messages are sent from the composer (Return) and come back
/// as the server sends them. The newest line is found in a render of the
/// list: a mention by its bar, your own by its background (made magenta).
@MainActor
@Suite("Sending keeps the newest line in view", .serialized)
struct SendingFollowTests {
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
        /// Tabs at the top, or in the title bar, as reported.
        var preset: String
        /// Videos, link previews and long messages among one-liners, so
        /// most rows are estimated; otherwise short lines only.
        var busy = false
        var description: String { "\(preset)\(busy ? ", busy" : "")" }
    }

    // MARK: Hosting

    private static var lineNumber = 0

    private static func historyLine(_ nick: String, _ text: String, at time: Date, isHighlight: Bool = false) -> ChatLine {
        lineNumber += 1
        return ChatLine(msgid: "sending-\(lineNumber)", time: time, kind: .message, nick: nick, userHost: "\(nick)@user/\(nick)", text: text, isHighlight: isHighlight, isHistory: true)
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

    private func host(_ setup: Setup) throws -> Hosted {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaSending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SendPreviewStandIn.self]
        let app = AppModel(
            settings: SettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            networkStore: NetworkConfigStore(fileURL: root.appendingPathComponent("networks.json")),
            database: nil,
            previewService: LinkPreviewService(session: URLSession(configuration: configuration), browser: nil),
            isDemo: true
        )
        DemoContent.populate(app)
        app.settings.apply(SettingsPreset.all.first { $0.id == setup.preset } ?? .tabbed)
        // Video thumbnails come from ytimg.com, which the stand-in doesn't
        // serve: never fetched. The players keep their size without them.
        app.settings[.mediaSiteRules] = ["ytimg.com": .string("block")]
        // Your own lines on a color nothing else has, with no material.
        app.settings[.appearanceColorCustomizations] = ["chat.selfMessageBackground": .string("#FF00FF"), "vibrancy": .string("none")]
        let session = try #require(app.sessions.first)
        let buffer = session.ensureBuffer(name: "##sending", kind: .channel, persist: false)
        buffer.isJoined = true
        let count = setup.busy ? 600 : 120
        let start = Date().addingTimeInterval(-Double(count + 10) * 30)
        buffer.insertSorted((0..<count).map { index in
            Self.historyLine(["ann", "bob", "cy", "dee"][index % 4], Self.text(index, busy: setup.busy), at: start.addingTimeInterval(Double(index) * 30))
        })
        buffer.insertSorted([Self.historyLine("gus", "doug: the newest line", at: start.addingTimeInterval(Double(count) * 30), isHighlight: true)])
        app.select(buffer)

        let size = CGSize(width: 900, height: 640)
        // Loaded, so the color customizations apply (the app starts the
        // store itself).
        let themeStore = ThemeStore(userThemesDirectory: root.appendingPathComponent("Themes"), settings: ThemeSettings(settings: app.settings))
        themeStore.reload()
        let uiState = UIState()
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

    private func composer(_ hosted: Hosted) throws -> ComposerNSTextView {
        try #require(Self.findAll(in: hosted.host) { $0 is ComposerNSTextView }.first as? ComposerNSTextView)
    }

    /// Whether the message box is empty within `seconds`.
    private func composerEmpties(_ hosted: Hosted, within seconds: Double = 3) async throws -> Bool {
        try await RunningDeadline.wait(timeout: .seconds(seconds), every: .milliseconds(20)) {
            try composer(hosted).string.isEmpty
        }
    }

    /// Which line is the newest: one of yours, or a mention.
    enum Newest: Sendable {
        case mine
        case mention
    }

    /// Where the list is.
    private struct Look: CustomStringConvertible {
        var listHeight: CGFloat
        /// The newest line's bottom, from the list's top edge; nil when it
        /// isn't in view.
        var newestLineBottom: CGFloat?
        /// The list's scroll offset, as the scroll view has it.
        var offset: CGFloat

        /// Room between the newest line and the list's bottom edge.
        var gap: CGFloat? { newestLineBottom.map { listHeight - $0 } }
        var showsTheNewestLineAtTheBottom: Bool { gap.map { abs($0 - ListEndSpacing.resting) <= 1 } ?? false }

        var description: String {
            "gap below the newest line \(gap.map { "\($0)" } ?? "none (out of view)"), list \(listHeight), offset \(offset)"
        }
    }

    /// What the list shows, as drawn (the typing line and the composer
    /// aren't in it), to tell whether it moved.
    private func listPicture(_ hosted: Hosted) throws -> Data {
        hosted.host.layoutSubtreeIfNeeded()
        let scrollViews = Self.findAll(in: hosted.host) { $0 is NSScrollView }.compactMap { $0 as? NSScrollView }
        let list = try #require(scrollViews.max { $0.frame.height < $1.frame.height })
        let rep = try #require(list.bitmapImageRepForCachingDisplay(in: list.bounds))
        list.cacheDisplay(in: list.bounds, to: rep)
        return try #require(rep.tiffRepresentation)
    }

    /// Finds the lowest row marked like `newest` at the rows' leading edge,
    /// in the list's own render (the typing line drawn over it isn't in it).
    private func look(_ hosted: Hosted, for newest: Newest) throws -> Look {
        hosted.host.layoutSubtreeIfNeeded()
        let scrollViews = Self.findAll(in: hosted.host) { $0 is NSScrollView }.compactMap { $0 as? NSScrollView }
        let list = try #require(scrollViews.max { $0.frame.height < $1.frame.height })
        var strip = list.bounds
        strip.size.width = 4
        let rep = try #require(list.bitmapImageRepForCachingDisplay(in: strip))
        list.cacheDisplay(in: strip, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / strip.height
        let mention = hosted.mentionColor
        var lowest: Int?
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                switch newest {
                case .mine:
                    // #FF00FF, as drawn.
                    if pixel.redComponent > 0.85, pixel.greenComponent < 0.5, pixel.blueComponent > 0.85 { lowest = y }
                case .mention:
                    let difference = abs(pixel.redComponent - mention.redComponent) + abs(pixel.greenComponent - mention.greenComponent) + abs(pixel.blueComponent - mention.blueComponent)
                    if difference < 0.2 { lowest = y }
                }
            }
        }
        return Look(listHeight: list.bounds.height, newestLineBottom: lowest.map { CGFloat($0 + 1) / scale }, offset: list.contentView.bounds.minY)
    }

    /// Where the list is once it shows the newest line at the bottom, or
    /// after `seconds`: longer than the list keeps checking for (about 5 s
    /// with its late retries, `BottomSettle`), so a list that's only slow on
    /// a busy machine gets there, and one still not there is stuck. Counted
    /// in running time (``RunningDeadline``), since at the start of a CI run
    /// the main actor goes to other tests' setup for 15 to 30 s at a time.
    static let settleSeconds: Double = 8

    private func settled(_ hosted: Hosted, newest: Newest, within seconds: Double = settleSeconds) async throws -> Look {
        var deadline = RunningDeadline(.seconds(seconds))
        try await Task.sleep(for: .milliseconds(150))
        var look = try look(hosted, for: newest)
        while !look.showsTheNewestLineAtTheBottom, deadline.hasTimeLeft() {
            try await Task.sleep(for: .milliseconds(50))
            look = try self.look(hosted, for: newest)
        }
        return look
    }

    // MARK: What happens

    enum Step: Sendable {
        /// Types a message (over `lines` lines) and presses Return.
        case send(lines: Int = 1)
        /// What you sent comes back: echo-message, or the client saying it
        /// went out.
        case echo
        /// gus says something.
        case incoming(mention: Bool, preview: Bool = false)
        /// gus starts typing.
        case typing
        /// Replying to the newest line.
        case reply
        case wait(milliseconds: Int)
    }

    private static var messageNumber = 0

    /// Runs `steps`; returns which line ends up the newest.
    @discardableResult
    private func perform(_ hosted: Hosted, _ steps: [Step], echoMessage: Bool) async throws -> Newest {
        if echoMessage {
            hosted.session.capabilities.insert("echo-message")
        } else {
            hosted.session.capabilities.remove("echo-message")
        }
        var sent: [String] = []
        var newest = Newest.mention
        for step in steps {
            switch step {
            case .send(let lines):
                Self.messageNumber += 1
                let message = ["three word message \(Self.messageNumber)"] + (1..<max(1, lines)).map { "and line \($0 + 1)" }
                let composer = try composer(hosted)
                composer.insertText(message.joined(separator: "\n"), replacementRange: composer.selectedRange())
                // A taller composer, laid out before sending.
                if lines > 1 { try await Task.sleep(for: .milliseconds(400)) }
                composer.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                sent += message
            case .echo:
                for text in sent {
                    Self.messageNumber += 1
                    if echoMessage {
                        let line = "@msgid=sent-\(Self.messageNumber) :doug!doug@user/doug PRIVMSG \(hosted.buffer.name) :\(text)"
                        hosted.session.handle(.message(try #require(IRCMessage(line: line)), batch: nil))
                    } else {
                        hosted.session.handle(.sent(IRCMessage(command: "PRIVMSG", params: [hosted.buffer.name, text])))
                    }
                }
                sent = []
                newest = .mine
            case .incoming(let mention, let preview):
                Self.messageNumber += 1
                let body = preview ? "see https://news.example.org/story/sent-\(Self.messageNumber)" : "an answer \(Self.messageNumber)"
                let line = "@msgid=in-\(Self.messageNumber) :gus!gus@user/gus PRIVMSG \(hosted.buffer.name) :\(mention ? "doug: " : "")\(body)"
                hosted.session.handle(.message(try #require(IRCMessage(line: line)), batch: nil))
                newest = .mention
            case .typing:
                let line = "@+typing=active :gus!gus@user/gus TAGMSG \(hosted.buffer.name)"
                hosted.session.handle(.message(try #require(IRCMessage(line: line)), batch: nil))
            case .reply:
                hosted.uiState.replyTargets[hosted.buffer.id] = hosted.buffer.lines.last
            case .wait(let milliseconds):
                try await Task.sleep(for: .milliseconds(milliseconds))
            }
        }
        return newest
    }

    /// What happens around a send, as `(name, steps)`. The line that ends
    /// up the newest is a mention or your own; lines before it aren't
    /// mentions. Your line comes back `echo` ms after Return.
    private static func scenarios(echo: Int) -> [(String, [Step])] {
        func wait(_ milliseconds: Int) -> [Step] { milliseconds == 0 ? [] : [.wait(milliseconds: milliseconds)] }
        let echoBack = wait(echo) + [Step.echo]
        func lines(_ count: Int) -> [Step] {
            Array(repeating: [Step.incoming(mention: false), .wait(milliseconds: 6)], count: count).flatMap { $0 }
        }
        var scenarios: [(String, [Step])] = []
        // 0: the same turn; 1: the next.
        for after in [0, 1, 16, 50, 100, 200, 300, 600] {
            scenarios.append(("a line \(after) ms after yours", [.send()] + echoBack + wait(after) + [.incoming(mention: true)]))
        }
        for before in [0, 30, 100] {
            scenarios.append(("a line \(before) ms after Return, before yours", [.send()] + wait(before) + [.incoming(mention: false)] + echoBack))
        }
        scenarios.append(("a line just before Return", [.incoming(mention: false), .wait(milliseconds: 30), .send()] + echoBack))
        scenarios.append(("three lines after yours", [.send()] + echoBack + lines(2) + [.incoming(mention: true)]))
        scenarios.append(("a burst around yours", [.send(), .wait(milliseconds: 20)] + lines(5) + echoBack + lines(5) + [.incoming(mention: true)]))
        // The typing line goes as gus's line arrives.
        for after in [-30, 0, 40, 150] {
            let answer: [Step] = after < 0
                ? [.send()] + wait(max(0, echo + after)) + [.incoming(mention: false), .wait(milliseconds: -after), .echo]
                : [.send()] + echoBack + wait(after) + [.incoming(mention: true)]
            scenarios.append(("someone typing answers \(after) ms after yours", [.typing, .wait(milliseconds: 500)] + answer))
        }
        for after in [0, 100] {
            scenarios.append(("a link preview \(after) ms after yours", [.send()] + echoBack + wait(after) + [.incoming(mention: true, preview: true)]))
        }
        scenarios.append(("a link preview just before yours", [.send(), .incoming(mention: false, preview: true)] + echoBack))
        scenarios.append(("replying", [.reply, .wait(milliseconds: 400), .send()] + echoBack + [.wait(milliseconds: 30), .incoming(mention: true)]))
        scenarios.append(("a message over three lines", [.send(lines: 3)] + echoBack + [.wait(milliseconds: 30), .incoming(mention: true)]))
        return scenarios
    }

    // MARK: Tests

    private nonisolated static let setups = [Setup(preset: "tabbed"), Setup(preset: "focus", busy: true)]

    @Test(arguments: setups)
    func linesArrivingAroundASendKeepTheNewestLineInView(_ setup: Setup) async throws {
        let hosted = try host(setup)
        defer { hosted.close() }
        try await Task.sleep(for: .milliseconds(800))
        let opened = try await settled(hosted, newest: .mention, within: 10)
        try #require(opened.showsTheNewestLineAtTheBottom, "the list didn't open at the newest line within 10 s: \(opened)")

        // With echo-message your line comes back from the server a moment
        // later; without, the client adds it once it's gone out.
        for (echoMessage, echo) in [(true, 60), (false, 1)] {
            for (name, steps) in Self.scenarios(echo: echo) {
                let scenario = "\(setup), echo-message \(echoMessage ? "on" : "off"), \(name)"
                let before = try look(hosted, for: .mention).offset
                let shownBefore = try listPicture(hosted)
                let newest = try await perform(hosted, steps, echoMessage: echoMessage)
                let after = try await settled(hosted, newest: newest)
                // Return sends at once; the box empties on SwiftUI's next
                // update, which a busy CI machine can hold back for a while.
                let cleared = try await composerEmpties(hosted)
                #expect(cleared, "\(scenario): Return didn't send")
                #expect(after.showsTheNewestLineAtTheBottom, "\(scenario): the newest line isn't at the bottom after \(Int(Self.settleSeconds)) s, so the list is stuck: \(after)")
                // Not an earlier line of the same kind, left at the bottom
                // by a list that didn't move: what it shows changed. (Not
                // by its offset: on macOS 26 that can shrink by thousands of
                // points as rows above are measured, with the list showing
                // the newest lines all along.)
                #expect(try listPicture(hosted) != shownBefore, "\(scenario): the list didn't move: offset \(before) → \(after.offset)")

                // Still following: the next line is brought into view.
                hosted.buffer.updateTyping(nick: "gus", state: .done)
                let next = try await perform(hosted, [.incoming(mention: true)], echoMessage: echoMessage)
                let followed = try await settled(hosted, newest: next)
                #expect(followed.showsTheNewestLineAtTheBottom, "\(scenario): the list stopped following: \(followed)")
                #expect(followed.offset > after.offset + 10, "\(scenario): the list stopped following: \(after.offset) → \(followed.offset)")
                if !followed.showsTheNewestLineAtTheBottom {
                    // Back to the bottom (sending always gets there) for the next one.
                    try await perform(hosted, [.send(), .echo], echoMessage: echoMessage)
                    _ = try await settled(hosted, newest: .mine)
                }
            }
        }
    }
}
