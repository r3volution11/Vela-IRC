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

/// Answers every link preview request with a small page, a little later, as
/// a slow site would. Nothing leaves the Mac.
private nonisolated final class SlowPageStandIn: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let delay = 80 + abs(url.path.hashValue) % 400
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

/// A long, busy channel full of media shows its newest lines when it's
/// opened or switched to, and as new lines arrive.
///
/// The message list is a lazy stack: rows it hasn't laid out count at an
/// estimated height, so its content height is partly a guess. In a channel
/// where one-line messages sit between 315 pt video players, link previews
/// and long messages, that guess can end a screenful or more below the
/// last row. The list used to open at that estimated bottom (and scroll to
/// it after new lines), where nothing is laid out: the channel looked empty
/// until the next message arrived.
///
/// The list is hosted as in the window (`ChatColumnView`) in an offscreen
/// window; what's on screen is read from a render of it.
@MainActor
@Suite("Message list bottom", .serialized)
struct MessageListBottomTests {
    struct Channel: CustomStringConvertible, Sendable {
        var preset = "focus"
        var lines = 1200
        /// Every how many lines someone posts a video.
        var videoEvery = 9
        var description: String { "\(preset), \(lines) lines, a video every \(videoEvery)" }
    }

    private final class Hosted {
        let app: AppModel
        let session: NetworkSession
        let busy: BufferModel
        let quiet: BufferModel
        let window: NSWindow
        let host: NSView
        /// The bar beside a mention: the newest line is one.
        let mentionColor: NSColor

        init(app: AppModel, session: NetworkSession, busy: BufferModel, quiet: BufferModel, window: NSWindow, host: NSView, mentionColor: NSColor) {
            self.app = app
            self.session = session
            self.busy = busy
            self.quiet = quiet
            self.window = window
            self.host = host
            self.mentionColor = mentionColor
        }

        func close() {
            window.orderOut(nil)
            window.contentView = nil
        }
    }

    /// What the list shows: how much of its visible area is drawn on, and
    /// whether the newest line (a mention) is at the bottom of it.
    private struct Shown: CustomStringConvertible {
        var inkedPixels: Int
        /// Sampled pixels of the mention bar (at the rows' leading edge) in
        /// the bottom 120 points.
        var mentionPixels: Int

        var showsLines: Bool { inkedPixels > 1000 }
        var showsTheNewestLine: Bool { mentionPixels > 5 }
        var description: String { "\(inkedPixels) inked pixels, \(mentionPixels) of the newest line's bar at the bottom" }
    }

    private static var lineNumber = 0

    private static func line(_ nick: String, _ text: String, at time: Date, isHistory: Bool) -> ChatLine {
        lineNumber += 1
        return ChatLine(msgid: "bottom-\(lineNumber)", time: time, kind: .message, nick: nick, userHost: "\(nick)@user/\(nick)", text: text, isHistory: isHistory)
    }

    private static func mention(at time: Date, isHistory: Bool) -> ChatLine {
        lineNumber += 1
        return ChatLine(msgid: "bottom-\(lineNumber)", time: time, kind: .message, nick: "gus", userHost: "gus@user/gus", text: "doug: the newest line", isHighlight: true, isHistory: isHistory)
    }

    /// What people say in the busy channel: mostly one-liners, some long
    /// messages, videos and articles.
    private static func text(_ index: Int, channel: Channel) -> String {
        if index % channel.videoEvery == 0 { return "watch this https://www.youtube.com/watch?v=aqz-KE-bpKQ&t=\(index)" }
        if index % 7 == 2 {
            return String(repeating: "a long message that wraps over several lines, number \(index), ", count: 1 + (index * 7919) % 30)
        }
        switch index % 9 {
        case 3, 6: return "article: https://news.example.org/story/\(index) worth a read"
        default: return "message number \(index)"
        }
    }

    private func host(_ channel: Channel, scrollback: Int? = nil, selecting first: (_ busy: BufferModel, _ quiet: BufferModel) -> BufferModel) throws -> Hosted {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaListBottom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SlowPageStandIn.self]
        let app = AppModel(
            settings: SettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            networkStore: NetworkConfigStore(fileURL: root.appendingPathComponent("networks.json")),
            database: nil,
            previewService: LinkPreviewService(session: URLSession(configuration: configuration), browser: nil),
            isDemo: true
        )
        DemoContent.populate(app)
        app.settings.apply(channel.preset == "tabbed" ? .tabbed : .focus)
        // Video thumbnails come from ytimg.com, which the stand-in doesn't
        // serve: never fetched. The players keep their size without them.
        app.settings[.mediaSiteRules] = ["ytimg.com": .string("block")]
        if let scrollback { app.settings[.chatScrollbackInMemory] = scrollback }
        let session = try #require(app.sessions.first)
        let busy = session.ensureBuffer(name: "##politicalfun", kind: .channel, persist: false)
        let start = Date().addingTimeInterval(-Double(channel.lines + 10) * 30)
        busy.insertSorted((0..<channel.lines).map { index in
            Self.line(["ann", "bob", "cy", "dee"][index % 4], Self.text(index, channel: channel), at: start.addingTimeInterval(Double(index) * 30), isHistory: true)
        })
        // The newest line mentions us, so it's easy to spot.
        busy.insertSorted([Self.mention(at: start.addingTimeInterval(Double(channel.lines) * 30), isHistory: true)])
        let quiet = session.ensureBuffer(name: "##quiet", kind: .channel, persist: false)
        quiet.insertSorted((0..<20).map { index in
            Self.line("eve", "quiet line \(index)", at: start.addingTimeInterval(Double(index) * 60), isHistory: true)
        })
        app.select(first(busy, quiet))

        let size = CGSize(width: 900, height: 640)
        let themeStore = ThemeStore(userThemesDirectory: root.appendingPathComponent("Themes"))
        let view = ChatColumnView()
            .velaEnvironment(
                app: app,
                themeStore: themeStore,
                uiState: UIState(),
                services: SceneServices(intelligence: .demo()),
                isPrimary: false
            )
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        let mentionColor = try #require(themeStore.current.color(ThemeKey.chatHighlightBorder).nsColor.usingColorSpace(.sRGB))
        return Hosted(app: app, session: session, busy: busy, quiet: quiet, window: window, host: host, mentionColor: mentionColor)
    }

    private static func findAll(in view: NSView, where matches: (NSView) -> Bool) -> [NSView] {
        (matches(view) ? [view] : []) + view.subviews.flatMap { findAll(in: $0, where: matches) }
    }

    /// Renders the message list (the tallest scroll view) and samples it.
    private func shown(_ hosted: Hosted) throws -> Shown {
        hosted.host.layoutSubtreeIfNeeded()
        let scrollViews = Self.findAll(in: hosted.host) { $0 is NSScrollView }.compactMap { $0 as? NSScrollView }
        let list = try #require(scrollViews.max { $0.frame.height < $1.frame.height })
        var bounds = list.bounds
        bounds.size.width -= 20   // not the scroll bar
        let rep = try #require(list.bitmapImageRepForCachingDisplay(in: bounds))
        list.cacheDisplay(in: bounds, to: rep)
        func difference(_ a: NSColor, _ b: NSColor) -> CGFloat {
            abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
        }
        let background = try #require(rep.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB))
        let bottomBand = rep.pixelsHigh - Int(120 * CGFloat(rep.pixelsHigh) / bounds.height)
        var inked = 0
        var mention = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if difference(color, background) > 0.15 { inked += 1 }
                if x < 8, y >= bottomBand, difference(color, hosted.mentionColor) < 0.2 { mention += 1 }
            }
        }
        return Shown(inkedPixels: inked, mentionPixels: mention)
    }

    /// What the list shows once it has had `seconds` to show the newest
    /// lines (or right away, once it does). Longer than the list keeps
    /// trying for (`BottomSettle`), for a busy machine.
    private func settled(_ hosted: Hosted, within seconds: Double = 6) async throws -> Shown {
        let deadline = Date().addingTimeInterval(seconds)
        try await Task.sleep(for: .milliseconds(300))
        var shown = try shown(hosted)
        while !(shown.showsLines && shown.showsTheNewestLine), Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
            shown = try self.shown(hosted)
        }
        return shown
    }

    private nonisolated static let channels = [Channel(), Channel(preset: "tabbed"), Channel(videoEvery: 4)]

    @Test(arguments: channels)
    func opensAtTheNewestLines(_ channel: Channel) async throws {
        let hosted = try host(channel) { busy, _ in busy }
        defer { hosted.close() }
        let shown = try await settled(hosted)
        #expect(shown.showsLines, "\(channel): the list shows nothing (\(shown))")
        #expect(shown.showsTheNewestLine, "\(channel): the newest line isn't at the bottom (\(shown))")
    }

    /// Switching to the busy channel from a quiet one, as reported.
    @Test(arguments: channels)
    func switchingToItShowsTheNewestLines(_ channel: Channel) async throws {
        let hosted = try host(channel) { _, quiet in quiet }
        defer { hosted.close() }
        try await Task.sleep(for: .milliseconds(500))
        hosted.app.select(hosted.busy)
        let shown = try await settled(hosted)
        #expect(shown.showsLines, "\(channel): the list shows nothing (\(shown))")
        #expect(shown.showsTheNewestLine, "\(channel): the newest line isn't at the bottom (\(shown))")
    }

    /// Blocks the main actor for 50 ms at a time, with 10 ms between, until
    /// cancelled: a busy app, or a busy machine.
    private func keepMainActorBusy() -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                usleep(50_000)
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    /// Opening the channel while the main actor is mostly busy: the checks
    /// that the list got to the bottom come late and seldom, and still get
    /// it there.
    @Test(arguments: channels)
    func opensAtTheNewestLinesWhileTheMainActorIsBusy(_ channel: Channel) async throws {
        let busy = keepMainActorBusy()
        let hosted = try host(channel) { busy, _ in busy }
        defer { hosted.close() }
        try await Task.sleep(for: .milliseconds(1500))
        busy.cancel()
        let shown = try await settled(hosted)
        #expect(shown.showsLines, "\(channel): the list shows nothing (\(shown))")
        #expect(shown.showsTheNewestLine, "\(channel): the newest line isn't at the bottom (\(shown))")
    }

    /// A burst of new lines that also drops old ones off the top (past
    /// `chat.scrollbackInMemory`) keeps the newest lines in view.
    @Test func aBurstThatTrimsTheTopKeepsTheNewestLines() async throws {
        let channel = Channel(preset: "tabbed", lines: 600)
        let hosted = try host(channel, scrollback: 300) { busy, _ in busy }
        defer { hosted.close() }
        _ = try await settled(hosted)
        for index in 0..<70 {
            hosted.session.add(Self.line("fay", Self.text(index + 1, channel: channel), at: Date(), isHistory: false), to: hosted.busy)
        }
        hosted.session.add(Self.mention(at: Date(), isHistory: false), to: hosted.busy)
        let shown = try await settled(hosted)
        #expect(shown.showsLines, "the list shows nothing (\(shown))")
        #expect(shown.showsTheNewestLine, "the newest line isn't at the bottom (\(shown))")
    }
}
