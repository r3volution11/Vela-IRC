// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import ImageIO
import SwiftUI
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import VelaCore
import VelaIntelligence
import VelaMedia
import VelaStore
import VelaTheme
@testable import VelaUI

// A GIF service that isn't one, for the picker's hosted tests: requests go
// to gifs.test and media to media.test, and both are answered here.
// Nothing leaves the Mac.

/// Builds and reads requests for `FakeGIFService`.
nonisolated struct FakeGIFProvider: GIFSearchProvider {
    var id: GIFSearchServiceID { .klipy }
    var displayName: String { "Fakey" }
    var searchPlaceholder: String { "Search Fakey" }
    var attribution: String { "Powered by Fakey" }
    var pageSize: Int { 24 }
    var allowsResponseCaching: Bool { true }
    var allowsThumbnailCaching: Bool { true }

    func request(for query: GIFQuery, page: GIFPageToken?, rating: GIFContentRating, apiKey: String) -> URLRequest? {
        var components = URLComponents(string: "https://gifs.test/\(query == .trending ? "trending" : "search")")!
        let number: Int = if case .page(let number) = page { number } else { 1 }
        components.queryItems = [
            URLQueryItem(name: "q", value: query.text ?? ""),
            URLQueryItem(name: "page", value: String(number)),
            URLQueryItem(name: "rating", value: rating.rawValue),
            URLQueryItem(name: "key", value: apiKey),
        ]
        return components.url.map { URLRequest(url: $0) }
    }

    struct Body: Decodable {
        struct Item: Decodable {
            var id: String
            var title: String
            var still: URL
            var animation: URL
            var share: URL
            var width: Int
            var height: Int
        }

        var results: [Item]
        var next: Int?
    }

    func decode(_ data: Data, response: HTTPURLResponse, query: GIFQuery, page: GIFPageToken?) throws(GIFSearchError) -> GIFSearchPage {
        switch response.statusCode {
        case 200: break
        case 401: throw .invalidKey
        case 429: throw .rateLimited
        default: throw .server(response.statusCode)
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw .badResponse }
        let results = body.results.map { item in
            GIFSearchResult(
                id: item.id,
                title: item.title,
                stills: [GIFRendition(url: item.still, width: item.width, height: item.height)],
                animations: [GIFRendition(url: item.animation, width: item.width, height: item.height)],
                shareURL: item.share,
                pageURL: URL(string: "https://gifs.test/site/gifs/\(item.id)"),
                attribution: "@maker",
                aspectRatio: CGFloat(item.width) / CGFloat(item.height)
            )
        }
        return GIFSearchPage(results: results, next: body.next.map { .page($0) })
    }

    func websiteURL(for query: GIFQuery) -> URL {
        guard let text = query.text else { return URL(string: "https://gifs.test/site/trending")! }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;%&+=")
        return URL(string: "https://gifs.test/site/search/" + text.replacingOccurrences(of: " ", with: "-").addingPercentEncoding(withAllowedCharacters: allowed)!)!
    }
}

/// Answers the picker's searches with pages of made-up GIFs, and counts them.
nonisolated final class FakeGIFService: GIFSearchTransport, Sendable {
    struct State {
        var requests: [URL] = []
        var status = 200
        var pages = 6
        var delay: Duration = .zero
        var fails = false
    }

    let state = Mutex(State())

    var requests: [URL] { state.withLock { $0.requests } }
    var trendingRequests: [URL] { requests.filter { $0.path() == "/trending" } }
    var searchRequests: [URL] { requests.filter { $0.path() == "/search" } }

    func query(of url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let (status, pages, delay, fails) = state.withLock { state in
            state.requests.append(url)
            return (state.status, state.pages, state.delay, state.fails)
        }
        if fails { throw URLError(.notConnectedToInternet) }
        if delay > .zero { try await Task.sleep(for: delay) }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        guard status == 200 else { return (Data(), response) }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = items.first { $0.name == "q" }?.value ?? ""
        let page = Int(items.first { $0.name == "page" }?.value ?? "1") ?? 1
        let kind = url.lastPathComponent
        let results: [[String: Any]] = (0..<24).map { index in
            let id = "\(kind)-\(query.isEmpty ? "all" : query.replacingOccurrences(of: " ", with: "_"))-\(page)-\(index)"
            return [
                "id": id,
                "title": "\(query.isEmpty ? "Trending" : query.capitalized) \(page * 100 + index)",
                "still": "https://media.test/still/\(id).gif",
                "animation": "https://media.test/animation/\(id).gif",
                "share": "https://media.test/share/\(id).gif",
                "width": 160,
                "height": 120,
            ]
        }
        var body: [String: Any] = ["results": results]
        if page < pages { body["next"] = page + 1 }
        return (try JSONSerialization.data(withJSONObject: body), response)
    }
}

/// Serves media.test: every preview is a small animated GIF. Counts loads.
nonisolated final class GIFMediaStandIn: URLProtocol, @unchecked Sendable {
    static let loads = Mutex<[URL]>([])
    /// What every preview is, instead of the made-up GIF (the benchmark
    /// uses a real preview).
    static let payload = Mutex<(data: Data, type: String)?>(nil)

    static let animatedGIF: Data = {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, 8, nil)!
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<8 {
            let context = CGContext(
                data: nil, width: 160, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(CGColor(srgbRed: CGFloat(frame) / 8, green: 0.4, blue: 1 - CGFloat(frame) / 8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: frame * 18, y: 40, width: 20, height: 40))
            CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.08]] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }()

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GIFMediaStandIn.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "media.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.loads.withLock { $0.append(url) }
        let (body, type) = Self.payload.withLock { $0 } ?? (Self.animatedGIF, "image/gif")
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": type, "Content-Length": String(body.count),
        ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// What the picker opened in the browser.
@MainActor
final class OpenedURLs {
    var urls: [URL] = []
}

/// Fake GIF services for a hosted test, and what they were asked.
@MainActor
final class FakeGIFServices {
    let transport = FakeGIFService()
    let services: GIFSearchServices

    init(builtInKey: String? = "built-in-test-key", provider: (any GIFSearchProvider)? = nil) {
        let made = Mutex(0)
        let provider = provider ?? FakeGIFProvider()
        services = GIFSearchServices(
            keys: GIFKeyStore(keychain: .inMemory()),
            builtInKLIPYKey: builtInKey,
            makeProvider: { _ in
                made.withLock { $0 += 1 }
                return provider
            },
            transport: transport,
            previewSession: GIFMediaStandIn.makeSession
        )
        countMade = { made.withLock { $0 } }
    }

    /// How many times the services were asked for a provider (zero: GIFs
    /// were never touched).
    private(set) var countMade: () -> Int = { 0 }
}

// MARK: - Hosting

/// The chat column hosted as in the window, in an offscreen window, with
/// fake GIF services; and what was opened in the browser.
@MainActor
final class PickerHost {
    let app: AppModel
    let uiState: UIState
    let buffer: BufferModel
    let session: NetworkSession
    let gifs: FakeGIFServices
    let window: NSWindow
    let host: NSView
    let opened = OpenedURLs()
    private let windowsBefore: Set<ObjectIdentifier>

    /// `reduceMotion` sets Reduce Motion for this window: off unless asked,
    /// as on most Macs (CI machines have it on, which stops animated
    /// previews).
    init(gifs: FakeGIFServices = FakeGIFServices(), reduceMotion: Bool = false, configure: (AppModel) -> Void = { _ in }) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaPicker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let app = AppModel(
            settings: SettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            networkStore: NetworkConfigStore(fileURL: root.appendingPathComponent("networks.json")),
            database: nil,
            isDemo: true
        )
        DemoContent.populate(app)
        app.settings[.mediaShowLinkCards] = false
        app.settings[.mediaAutoLoad] = false
        // Off by default (and only in development builds, as these tests are):
        // on here, as for someone trying GIFs in Vela Dev.
        app.settings[.gifsEnabled] = true
        configure(app)
        let session = try #require(app.sessions.first)
        let buffer = session.ensureBuffer(name: "##picker", kind: .channel, persist: false)
        buffer.isJoined = true
        let start = Date().addingTimeInterval(-3_000)
        buffer.insertSorted((0..<40).map { index in
            ChatLine(msgid: "picker-\(UUID().uuidString)", time: start.addingTimeInterval(Double(index) * 30), kind: .message,
                     nick: ["ann", "bob"][index % 2], userHost: "u@h", text: "message \(index)", isHistory: true)
        })
        app.select(buffer)

        let themeStore = ThemeStore(userThemesDirectory: root.appendingPathComponent("Themes"))
        let uiState = UIState()
        let opened = opened
        let view = ChatColumnView()
            .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: SceneServices(intelligence: .demo()), isPrimary: false)
            .environment(\.gifSearchServices, gifs.services)
            .environment(\._accessibilityReduceMotion, reduceMotion)
            .environment(\.openURL, OpenURLAction { url in
                opened.urls.append(url)
                return .handled
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        windowsBefore = Set(NSApp.windows.map(ObjectIdentifier.init))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: CGSize(width: 900, height: 640)), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        // SwiftUI's accessibility elements, which the tests press.
        NSApp.perform(Self.enhancedInterface, with: NSNumber(value: true))
        self.app = app
        self.uiState = uiState
        self.buffer = buffer
        self.session = session
        self.gifs = gifs
        self.window = window
        self.host = host
    }

    static let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")

    /// Leaves VoiceOver's enhanced interface on: switched off and on again
    /// between tests, the second switch can arrive first, and SwiftUI then
    /// builds no elements for the next window.
    func close() {
        for window in pickerWindows { window.orderOut(nil) }
        window.orderOut(nil)
        window.contentView = nil
    }

    func settle(_ milliseconds: Int = 150) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds / 2))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(milliseconds / 2))
    }

    /// Waits up to `seconds` for `condition`.
    func wait(_ seconds: Double = 3, until condition: () -> Bool) async throws -> Bool {
        await RunningDeadline.wait(timeout: .seconds(seconds), every: .milliseconds(30), until: condition)
    }

    static func findAll(in view: NSView, where matches: (NSView) -> Bool) -> [NSView] {
        (matches(view) ? [view] : []) + view.subviews.flatMap { findAll(in: $0, where: matches) }
    }

    var composer: ComposerNSTextView? {
        Self.findAll(in: host) { $0 is ComposerNSTextView }.first as? ComposerNSTextView
    }

    /// Windows opened since hosting that show the picker.
    var pickerWindows: [NSWindow] {
        NSApp.windows.filter { window in
            !windowsBefore.contains(ObjectIdentifier(window)) && window !== self.window && window.isVisible
                && window.contentView.map { !Self.findAll(in: $0) { $0 is PaletteTextField }.isEmpty } == true
        }
    }

    var pickerWindow: NSWindow? { pickerWindows.first }

    var searchField: PaletteTextField? {
        pickerWindow?.contentView.flatMap { Self.findAll(in: $0) { $0 is PaletteTextField }.first as? PaletteTextField }
    }

    // MARK: Accessibility

    /// The first accessibility element under `root` labeled `label` (or
    /// whose label starts with it).
    static func element(labeled label: String, prefix: Bool = false, in root: AnyObject) -> AnyObject? {
        // A button's label, or a static text's value.
        let names = [root.accessibilityLabel?() ?? nil, PickerHost.value(of: root)].compactMap { $0 }
        if names.contains(where: { prefix ? $0.hasPrefix(label) : $0 == label }) { return root }
        for child in (root.accessibilityChildren?() ?? nil) ?? [] {
            if let match = element(labeled: label, prefix: prefix, in: child as AnyObject) { return match }
        }
        return nil
    }

    /// A static text's text.
    static func value(of element: AnyObject) -> String? {
        let selector = NSSelectorFromString("accessibilityValue")
        guard let object = element as? NSObject, object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? String
    }

    static func labels(in root: AnyObject) -> [String] {
        let own = [root.accessibilityLabel?() ?? nil, PickerHost.value(of: root)].compactMap { $0 }
        return own + ((root.accessibilityChildren?() ?? nil) ?? []).flatMap { labels(in: $0 as AnyObject) }
    }

    func element(_ label: String, prefix: Bool = false, inPicker: Bool = false) -> AnyObject? {
        let root: AnyObject? = inPicker ? pickerWindow?.contentView : host
        return root.flatMap { Self.element(labeled: label, prefix: prefix, in: $0) }
    }

    /// Presses the button labeled `label`, as VoiceOver would.
    func press(_ label: String, inPicker: Bool = false) async throws {
        let button = try await waitForElement(label, inPicker: inPicker)
        _ = button.accessibilityPerformPress?()
    }

    /// The element labeled `label`, once it's there: SwiftUI builds and
    /// rebuilds its elements as views change.
    func waitForElement(_ label: String, inPicker: Bool = false) async throws -> AnyObject {
        var found = element(label, inPicker: inPicker)
        for attempt in 0..<60 where found == nil {
            // Another suite may have switched the enhanced interface off.
            if attempt % 20 == 19 { NSApp.perform(Self.enhancedInterface, with: NSNumber(value: true)) }
            try await Task.sleep(for: .milliseconds(50))
            found = element(label, inPicker: inPicker)
        }
        return try #require(found, "no \(label)")
    }

    /// Whether an element labeled `label` shows within a few seconds.
    func shows(_ label: String) async throws -> Bool {
        try await wait { element(label) != nil }
    }

    /// Whether no element labeled `label` is left within a few seconds.
    func hides(_ label: String) async throws -> Bool {
        try await wait { element(label) == nil }
    }

    /// Where the element labeled `label` is, in the main window's coordinates.
    func windowPoint(of label: String) async throws -> CGPoint {
        let element = try await waitForElement(label)
        let frame = try #require(element.accessibilityFrame?())
        let rect = window.convertFromScreen(frame)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private static var eventNumber = 0

    /// Clicks at `point` in the main window, through the app as the event
    /// loop would.
    func click(at point: CGPoint) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            Self.eventNumber += 1
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: Self.eventNumber, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
            ))
            NSApp.sendEvent(event)
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    // MARK: Keys

    enum Key {
        case up, down, left, right, returnKey, escape, tab, controlTab, delete

        private static func function(_ key: Int) -> String { String(Character(UnicodeScalar(UInt32(key))!)) }

        var event: (characters: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
            switch self {
            case .up: (Self.function(NSUpArrowFunctionKey), [.function, .numericPad], 126)
            case .down: (Self.function(NSDownArrowFunctionKey), [.function, .numericPad], 125)
            case .left: (Self.function(NSLeftArrowFunctionKey), [.function, .numericPad], 123)
            case .right: (Self.function(NSRightArrowFunctionKey), [.function, .numericPad], 124)
            case .returnKey: ("\r", [], 36)
            case .escape: ("\u{1b}", [], 53)
            case .tab: ("\t", [], 48)
            case .controlTab: ("\t", .control, 48)
            case .delete: ("\u{7f}", [], 51)
            }
        }
    }

    /// Presses `key` in `window`, as the keyboard would: a key equivalent
    /// first (⌃Tab), then the first responder.
    func press(_ key: Key, in window: NSWindow, settling milliseconds: Int = 150) async throws {
        let (characters, modifiers, keyCode) = key.event
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        ))
        if modifiers.contains(.control) || modifiers.contains(.command), window.performKeyEquivalent(with: event) {
            // Handled as a key equivalent.
        } else {
            window.sendEvent(event)
        }
        try await settle(milliseconds)
    }

    /// Types `text` into the picker's search field, a character at a time.
    func typeInPicker(_ text: String, pause: Duration = .milliseconds(40)) async throws {
        let field = try #require(searchField)
        let editor = try #require(field.currentEditor() as? NSTextView, "the search field doesn't have the focus")
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            try await Task.sleep(for: pause)
        }
    }

    /// Opens the picker with the smiley and waits for its search field.
    func openPicker() async throws {
        // "Emoji and GIFs", or just "Emoji" with GIFs off.
        try await press(ComposerPickerButton.labels(showsGIFs: GIFAvailability.isOn(in: app.settings)).label)
        #expect(try await wait { searchField?.currentEditor() != nil }, "the picker didn't open with its search field focused")
        try await settle(200)
    }

    func resetDefaults(tab: ComposerPickerTab = .emoji) {
        ComposerPickerTab.remembered = tab
    }
}
