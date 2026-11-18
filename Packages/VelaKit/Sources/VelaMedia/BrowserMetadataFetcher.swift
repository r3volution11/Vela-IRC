// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network
import WebKit

/// What the browser engine read from a page.
public struct BrowserPage: Sendable, Hashable {
    /// The document's address once loaded: after redirects and after the
    /// bot check reloaded the page.
    public var finalURL: URL
    /// The document's `<head>` metadata, as `HTMLMetadataParser` reads it.
    public var metadata: HTMLMetadata
    /// How the load went, when `BrowserMetadataFetcher.Options.collectsStats`.
    public var stats: BrowserLoadStats?

    public init(finalURL: URL, metadata: HTMLMetadata, stats: BrowserLoadStats? = nil) {
        self.finalURL = finalURL
        self.metadata = metadata
        self.stats = stats
    }
}

/// What one browser-engine load cost, for measuring.
public struct BrowserLoadStats: Sendable, Hashable {
    /// From starting the load to having the real page's metadata.
    public var seconds: Double
    /// Main-frame documents loaded: the bot check, then the page.
    public var documents: Int
    /// Requests the documents made and finished, the documents included
    /// (Resource Timing; blocked requests never start, so aren't counted).
    public var requests: Int
    /// Bytes transferred, as far as Resource Timing tells: other sites'
    /// responses report 0 unless they send `Timing-Allow-Origin`.
    public var transferBytes: Int
}

/// Why the browser engine couldn't read a page.
public enum BrowserFetchError: Error, Sendable, Hashable {
    /// No real page (only the bot check, or nothing) within the time limit.
    case timedOut
    /// The page tried to go somewhere it may not: another site, a site the
    /// policy blocks, a private network address, or not `http(s)`.
    case refused
    /// The page isn't HTML (a file, say).
    case notAPage
    /// The load failed (a network error, or the web content process ended).
    case failed
    /// Loading this address failed earlier in this session; it isn't tried again.
    case failedBefore
}

/// Something that loads a page in a real browser engine and reads its
/// `<head>` metadata. `BrowserMetadataFetcher` is the real one; tests use stubs.
public protocol BrowserMetadataLoading: Sendable {
    @MainActor func load(_ url: URL, policy: MediaPolicy) async throws -> BrowserPage
}

/// Reads a page's metadata with WebKit, for sites that show a bot check
/// (or an empty, script-only page) to anything that doesn't run JavaScript.
///
/// The page loads the way it would in Safari, and the site's own check runs
/// as it would there. Nothing is impersonated: the user agent is WebKit's own,
/// and no challenge is solved or forged here.
///
/// - **Private and throwaway.** A non-persistent website data store, cleared
///   after every load: no cookies, cache or storage outlive a fetch, and none
///   are shared with Safari or the video players.
/// - **Offscreen.** The web view is never in a window and is never shown.
///   New windows, pop-ups, downloads, dialogs, camera, microphone and media
///   playback are all refused; no address is ever handed to another app.
/// - **Light.** A content rule list blocks images, media, fonts and style
///   sheets, and every request to another site except the bot checks' own
///   hosts (`challengeHosts`), so only the page's HTML and the scripts the
///   check needs load. Private network addresses are blocked for every request.
/// - **Contained.** Main-frame navigation stays on the page's site, plus the
///   redirects the server sends; every navigation is checked with `MediaPolicy`.
/// - **Early exit.** A script (in its own content world, out of the page's
///   reach) reports the document's `<head>` as soon as it's parsed; the load
///   stops at the first one that's the real page rather than the check.
/// - **One at a time.** Loads queue for one shared web view, which is
///   reused, then torn down after `Options.idleTeardown` without use.
/// - **Bounded.** A load gives up after `Options.timeout`. A URL that failed
///   isn't tried again this session.
@MainActor
public final class BrowserMetadataFetcher: BrowserMetadataLoading {
    public struct Options: Sendable {
        /// The longest one load may take.
        public var timeout: Duration
        /// How long the web view (and its web content process) is kept for
        /// the next load.
        public var idleTeardown: Duration
        /// Block subresources other than what a bot check needs. Off only to
        /// measure what blocking saves.
        public var blocksSubresources: Bool
        /// Fill in `BrowserPage.stats`.
        public var collectsStats: Bool
        /// Proxies for the web view's requests. Only for measuring what a
        /// load transfers (a counting proxy in the tests).
        var proxyConfigurations: [ProxyConfiguration] = []

        public init(
            timeout: Duration = .seconds(8),
            idleTeardown: Duration = .seconds(30),
            blocksSubresources: Bool = true,
            collectsStats: Bool = false
        ) {
            self.timeout = timeout
            self.idleTeardown = idleTeardown
            self.blocksSubresources = blocksSubresources
            self.collectsStats = collectsStats
        }
    }

    public nonisolated static let shared = BrowserMetadataFetcher()

    /// Hosts that bot checks load their scripts and frames from, allowed
    /// through the third-party block: AWS WAF, Cloudflare, DataDome and
    /// PerimeterX (HUMAN). Akamai and Imperva serve theirs from the page's site.
    public nonisolated static let challengeHosts = [
        "awswaf.com",
        "challenges.cloudflare.com",
        "captcha-delivery.com",
        "px-cdn.net",
        "px-cloud.net",
        "perimeterx.net",
    ]

    /// The content world the reporting script and its message handler live in.
    nonisolated static let worldName = "VelaLinkPreview"
    nonisolated static let handlerName = "velaPreview"

    private let options: Options
    private var webView: WKWebView?
    private var coordinator: Coordinator?
    private var idleTask: Task<Void, Never>?
    private var busy = false
    private var waiters: [(id: UInt64, continuation: CheckedContinuation<Void, any Error>)] = []
    private var nextWaiterID: UInt64 = 0
    /// URLs whose load failed this session.
    private var failures = LRUCache<String, BrowserFetchError>(countLimit: 500)

    public nonisolated init(options: Options = Options()) {
        self.options = options
    }

    /// Whether a load is running or queued. For tests.
    var isIdle: Bool { !busy && waiters.isEmpty }
    /// Whether the shared web view exists right now. For tests.
    var hasWebView: Bool { webView != nil }

    // MARK: - Loading

    /// Loads `url` and returns the real page's metadata.
    ///
    /// Throws `BrowserFetchError` (remembered for `url` for the rest of the
    /// session) or `CancellationError` (not remembered).
    public func load(_ url: URL, policy: MediaPolicy) async throws -> BrowserPage {
        try await load(.url(url), key: url.absoluteString, policy: policy)
    }

    /// Loads `html` as if served from `baseURL`, for tests.
    func load(html: String, baseURL: URL, policy: MediaPolicy) async throws -> BrowserPage {
        try await load(.html(html, baseURL: baseURL), key: nil, policy: policy)
    }

    private enum Source {
        case url(URL)
        case html(String, baseURL: URL)

        var url: URL {
            switch self {
            case .url(let url), .html(_, let url): url
            }
        }
    }

    private func load(_ source: Source, key: String?, policy: MediaPolicy) async throws -> BrowserPage {
        try Task.checkCancellation()
        if let key, let failure = failures.peek(key) {
            throw failure == .refused ? BrowserFetchError.refused : BrowserFetchError.failedBefore
        }
        guard Self.isWebURL(source.url), policy.allows(source.url) else { throw BrowserFetchError.refused }

        try await acquire()
        let result: Result<BrowserPage, any Error>
        do {
            result = .success(try await run(source, policy: policy))
        } catch {
            result = .failure(error)
        }
        await reset()
        release()

        switch result {
        case .success(let page):
            return page
        case .failure(let error):
            if let key, !(error is CancellationError) {
                failures.insert(error as? BrowserFetchError ?? .failed, for: key)
            }
            throw error
        }
    }

    private func run(_ source: Source, policy: MediaPolicy) async throws -> BrowserPage {
        try Task.checkCancellation()
        let (webView, coordinator) = try await preparedWebView()
        let load = PageLoad(url: source.url, policy: policy, collectsStats: options.collectsStats)
        coordinator.load = load
        defer { coordinator.load = nil }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                load.continuation = continuation
                let timeout = options.timeout
                load.timeoutTask = Task { @MainActor [weak load] in
                    try? await Task.sleep(for: timeout)
                    load?.timedOut()
                }
                switch source {
                case .url(let url):
                    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                    request.timeoutInterval = Double(timeout.components.seconds)
                    webView.load(request)
                case .html(let html, let baseURL):
                    webView.loadHTMLString(html, baseURL: baseURL)
                }
            }
        } onCancel: {
            Task { @MainActor in load.finish(.failure(CancellationError())) }
        }
    }

    /// Stops the page, unloads it and forgets everything it stored.
    private func reset() async {
        guard let webView else { return }
        webView.stopLoading()
        if coordinator?.processEnded == true {
            tearDown()
            return
        }
        webView.loadHTMLString("", baseURL: nil)
        await webView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
        )
    }

    // MARK: - Queue

    private func acquire() async throws {
        if !busy {
            busy = true
            return
        }
        let id = nextWaiterID
        nextWaiterID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// Hands the web view to the next load, or lets it go idle.
    private func release() {
        if waiters.isEmpty {
            busy = false
            scheduleTeardown()
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    // MARK: - The web view

    private func preparedWebView() async throws -> (WKWebView, Coordinator) {
        idleTask?.cancel()
        idleTask = nil
        if let webView, let coordinator, !coordinator.processEnded { return (webView, coordinator) }
        tearDown()

        let rules = try await Self.ruleList(blocksSubresources: options.blocksSubresources)
        try Task.checkCancellation()
        if let webView, let coordinator { return (webView, coordinator) }

        let configuration = WKWebViewConfiguration()
        let dataStore = WKWebsiteDataStore.nonPersistent()
        if !options.proxyConfigurations.isEmpty { dataStore.proxyConfigurations = options.proxyConfigurations }
        configuration.websiteDataStore = dataStore
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.suppressesIncrementalRendering = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // WebKit's own user agent: nothing is set or appended.

        let coordinator = Coordinator()
        let world = WKContentWorld.world(name: Self.worldName)
        let controller = configuration.userContentController
        controller.add(rules)
        controller.addUserScript(WKUserScript(
            source: Self.reportingScript(collectsStats: options.collectsStats),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: world
        ))
        controller.add(coordinator, contentWorld: world, name: Self.handlerName)

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.isInspectable = false
        self.webView = webView
        self.coordinator = coordinator
        return (webView, coordinator)
    }

    private func scheduleTeardown() {
        idleTask?.cancel()
        let delay = options.idleTeardown
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.busy else { return }
            self.tearDown()
        }
    }

    private func tearDown() {
        guard let webView else { return }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeAllContentRuleLists()
        self.webView = nil
        coordinator = nil
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host() != nil
    }

    // MARK: - Content rules

    private static var ruleLists: [Bool: WKContentRuleList] = [:]
    private static var ruleListTasks: [Bool: Task<WKContentRuleList, any Error>] = [:]

    /// The compiled rules, compiled once per launch (and kept on disk between
    /// launches, under a name that changes with the rules).
    static func ruleList(blocksSubresources: Bool) async throws -> WKContentRuleList {
        if let list = ruleLists[blocksSubresources] { return list }
        if let task = ruleListTasks[blocksSubresources] { return try await task.value }
        let json = contentRules(blocksSubresources: blocksSubresources)
        let identifier = "vela-link-preview-\(blocksSubresources ? "blocking" : "open")-\(fingerprint(json))"
        let task = Task { @MainActor () throws -> WKContentRuleList in
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "VelaContentRules", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = WKContentRuleListStore(url: directory) ?? WKContentRuleListStore.default()!
            if let stored = try? await store.contentRuleList(forIdentifier: identifier) { return stored }
            guard let compiled = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
            else { throw BrowserFetchError.failed }
            return compiled
        }
        ruleListTasks[blocksSubresources] = task
        do {
            let list = try await task.value
            ruleLists[blocksSubresources] = list
            ruleListTasks[blocksSubresources] = nil
            return list
        } catch {
            ruleListTasks[blocksSubresources] = nil
            throw error
        }
    }

    /// The content blocker rules, as WebKit's JSON.
    ///
    /// Blocking: images, media, fonts, style sheets and pings everywhere, and
    /// every request to another site, except the bot checks' own hosts
    /// (`challengeHosts`). Always: private network addresses, whatever else
    /// a rule allowed (the last rules win).
    nonisolated static func contentRules(blocksSubresources: Bool) -> String {
        var rules: [String] = []
        if blocksSubresources {
            rules.append(#"{"trigger":{"url-filter":".*","resource-type":["image","style-sheet","font","media","svg-document","ping","popup"]},"action":{"type":"block"}}"#)
            rules.append(#"{"trigger":{"url-filter":".*","load-type":["third-party"]},"action":{"type":"block"}}"#)
            for host in challengeHosts {
                let pattern = #"^https?://([^/:]+\\.)?"# + host.replacingOccurrences(of: ".", with: #"\\."#) + "[/:]"
                rules.append(#"{"trigger":{"url-filter":""# + pattern + #"","resource-type":["document","script","raw","fetch","websocket","other"]},"action":{"type":"ignore-previous-rules"}}"#)
            }
        }
        for pattern in privateHostPatterns {
            rules.append(#"{"trigger":{"url-filter":""# + pattern + #""},"action":{"type":"block"}}"#)
        }
        return "[" + rules.joined(separator: ",") + "]"
    }

    /// `MediaPolicy.isPrivateNetworkHost` as content blocker URL filters
    /// (which have no alternation): loopback, private, link-local, CGNAT and
    /// multicast IPv4, every IPv6 literal, local-only names and single-label hosts.
    nonisolated static let privateHostPatterns: [String] = {
        let start = #"^[a-z]+://"#
        let ipv4Tail = #"\\.[0-9]+\\.[0-9]+\\.[0-9]+[:/]"#
        let ipv4ThirdTail = #"\\.[0-9]+\\.[0-9]+[:/]"#
        var patterns = ["0", "10", "127", "22[4-9]", "2[3-5][0-9]"].map { start + $0 + ipv4Tail }
        patterns += ["169\\\\.254", "192\\\\.168", "172\\\\.1[6-9]", "172\\\\.2[0-9]", "172\\\\.3[01]",
                     "100\\\\.6[4-9]", "100\\\\.[7-9][0-9]", "100\\\\.1[01][0-9]", "100\\\\.12[0-7]"]
            .map { start + $0 + ipv4ThirdTail }
        patterns.append(start + #"\\["#)
        patterns.append(start + #"localhost[:/]"#)
        patterns += ["localhost", "local", "internal", "lan", "home\\\\.arpa"].map { start + #"[^/:]+\\."# + $0 + "[:/]" }
        patterns.append(start + #"[^/:.]+[:/]"#)
        return patterns
    }()

    /// FNV-1a of `text`, in hex: stable across launches, unlike `hashValue`.
    nonisolated static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    // MARK: - Reporting script

    /// Runs at document start in its own content world, so the page can't
    /// see it or post to its handler. It reports the document's metadata
    /// (only `<title>`, `<meta>`, `<link>` and `<base>`) as soon as the head
    /// is parsed, at DOMContentLoaded, at load, and when a script changes
    /// the head; with `collectsStats`, Resource Timing totals too.
    nonisolated static func reportingScript(collectsStats: Bool) -> String {
        """
        (() => {
          const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handlerName);
          if (!handler) return;
          const doc = Math.random().toString(36).slice(2);
          const collectsStats = \(collectsStats ? "true" : "false");
          const maxLength = 131072;
          const escape = (text) => String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
          const tag = (element) => {
            let attributes = '';
            for (const attribute of element.attributes) attributes += ' ' + attribute.name + '="' + escape(attribute.value) + '"';
            return '<' + element.localName + attributes + '>';
          };
          const snapshot = () => {
            const parts = ['<title>' + escape(document.title || '') + '</title>'];
            let length = parts[0].length;
            const add = (nodes, limit) => {
              for (let i = 0; i < nodes.length && i < limit && length < maxLength; i++) {
                const text = tag(nodes[i]);
                parts.push(text);
                length += text.length;
              }
            };
            if (document.head) add(document.head.querySelectorAll('meta, link, base'), 400);
            if (document.body) add(document.body.querySelectorAll('meta[property^="og:"], meta[name^="twitter:"], meta[name="description"], meta[name="rating"]'), 50);
            return '<html><head>' + parts.join('') + '</head></html>';
          };
          const stats = () => {
            const navigation = performance.getEntriesByType('navigation')[0];
            const resources = performance.getEntriesByType('resource');
            let bytes = navigation ? (navigation.transferSize || 0) : 0;
            for (const entry of resources) bytes += entry.transferSize || 0;
            return { requests: resources.length + 1, bytes };
          };
          let headDone = false;
          const post = (reason) => {
            try {
              const message = { doc, reason, url: location.href, html: snapshot(), headDone: headDone || !!document.body || document.readyState !== 'loading' };
              if (collectsStats) message.stats = stats();
              handler.postMessage(message);
            } catch (error) {}
          };
          let timer = 0;
          const headObserver = new MutationObserver(() => {
            clearTimeout(timer);
            timer = setTimeout(() => post('change'), 100);
          });
          const watchHead = () => {
            if (headDone) return;
            headDone = true;
            post('head');
            if (document.head) headObserver.observe(document.head, { childList: true, subtree: true, characterData: true, attributes: true });
          };
          const bodyObserver = new MutationObserver(() => {
            if (document.body) {
              bodyObserver.disconnect();
              watchHead();
            }
          });
          bodyObserver.observe(document, { childList: true, subtree: true });
          document.addEventListener('DOMContentLoaded', () => { bodyObserver.disconnect(); watchHead(); post('ready'); });
          window.addEventListener('load', () => post('load'));
          if (collectsStats) window.addEventListener('pagehide', () => post('hide'));
        })();
        """
    }
}

// MARK: - One load

/// The state of one load, from start to its single result.
@MainActor
private final class PageLoad {
    let url: URL
    let policy: MediaPolicy
    let collectsStats: Bool
    let started = ContinuousClock.now
    var continuation: CheckedContinuation<BrowserPage, any Error>?
    var timeoutTask: Task<Void, Never>?
    var settleTask: Task<Void, Never>?
    /// Sites main-frame navigation may go to: the page's, and where the
    /// server redirected it.
    var sites: Set<String>
    /// The latest report that was the real page.
    var realPage: BrowserPage?
    var mainFrameIsProvisional = false
    var ratedAdult = false
    var mainFrameNavigations = 0
    /// Resource Timing totals per document.
    var documentStats: [String: (requests: Int, bytes: Int)] = [:]

    /// Main-frame navigations allowed per load (the check's reloads included).
    static let maxMainFrameNavigations = 12

    init(url: URL, policy: MediaPolicy, collectsStats: Bool) {
        self.url = url
        self.policy = policy
        self.collectsStats = collectsStats
        self.sites = Set([PageLoad.site(of: url)].compactMap { $0 })
    }

    var isFinished: Bool { continuation == nil }

    func finish(_ result: Result<BrowserPage, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        settleTask?.cancel()
        continuation.resume(with: result)
    }

    func timedOut() {
        if let realPage { finish(.success(withStats(realPage))) } else { finish(.failure(BrowserFetchError.timedOut)) }
    }

    /// A report from the reporting script.
    func report(_ body: [String: Any]) {
        guard !isFinished, let html = body["html"] as? String, let address = body["url"] as? String,
              let documentURL = URL(string: address), BrowserMetadataFetcher.isWebURL(documentURL),
              let site = Self.site(of: documentURL), sites.contains(site)
        else { return }
        if collectsStats, let doc = body["doc"] as? String, let stats = body["stats"] as? [String: Any] {
            let requests = (stats["requests"] as? NSNumber)?.intValue ?? 0
            let bytes = (stats["bytes"] as? NSNumber)?.intValue ?? 0
            documentStats[doc] = (requests, bytes)
        }
        var metadata = HTMLMetadataParser.parse(html: html, baseURL: documentURL)
        guard BotCheckDetector.isRealPage(metadata) else { return }
        if ratedAdult { metadata.declaresAdult = true }
        realPage = BrowserPage(finalURL: documentURL, metadata: metadata)

        let reason = body["reason"] as? String
        let headDone = (body["headDone"] as? Bool) ?? false
        if headDone, reason != "change" {
            // The parsed head: everything the server sent.
            finish(.success(withStats(realPage!)))
        } else if settleTask == nil {
            // A script is filling in the head: give it a moment to finish.
            settleTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, let page = self.realPage else { return }
                self.finish(.success(self.withStats(page)))
            }
        }
    }

    private func withStats(_ page: BrowserPage) -> BrowserPage {
        guard collectsStats else { return page }
        var page = page
        let elapsed = ContinuousClock.now - started
        page.stats = BrowserLoadStats(
            seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
            documents: max(documentStats.count, mainFrameNavigations),
            requests: documentStats.values.reduce(0) { $0 + $1.requests },
            transferBytes: documentStats.values.reduce(0) { $0 + $1.bytes }
        )
        return page
    }

    /// Whether the main frame may navigate to `url`.
    func allowsMainFrame(_ url: URL) -> Bool {
        guard BrowserMetadataFetcher.isWebURL(url), policy.allows(url) else { return false }
        guard mainFrameNavigations < Self.maxMainFrameNavigations else { return false }
        guard let site = Self.site(of: url) else { return false }
        if sites.contains(site) { return true }
        // A server redirect arrives while the navigation is still provisional.
        if mainFrameIsProvisional {
            sites.insert(site)
            return true
        }
        return false
    }

    /// Whether a frame inside the page may load `url` (a bot check's frame).
    func allowsSubframe(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "about", "data", "blob": true
        case "http", "https": policy.allows(url)
        default: false
        }
    }

    /// The site a host belongs to, roughly its registrable domain:
    /// `www.imdb.com` → `imdb.com`, `news.bbc.co.uk` → `bbc.co.uk`.
    static func site(of url: URL) -> String? {
        guard let host = SiteRules.normalizedHost(url) else { return nil }
        if SiteRules.isIPLiteral(host) { return host }
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return host }
        let secondLevel = labels[labels.count - 2]
        let commonSecondLevels: Set<Substring> = ["co", "com", "net", "org", "gov", "edu", "ac", "ne", "or", "go", "gob", "nic"]
        let keep = labels[labels.count - 1].count == 2 && commonSecondLevels.contains(secondLevel) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }
}

// MARK: - Delegates

/// Navigation, UI and script-message delegate for the shared web view.
/// Everything not needed to load one page is refused.
@MainActor
private final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var load: PageLoad?
    private(set) var processEnded = false

    // MARK: Navigation

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        let url = action.request.url
        // The blank page that unloads the last page (its policy check may
        // arrive once the next load has begun). It loads nothing.
        if url?.absoluteString == "about:blank" { return (.allow, preferences) }
        guard let load, !load.isFinished, let url else { return (.cancel, preferences) }
        if action.shouldPerformDownload || action.targetFrame == nil { return (.cancel, preferences) }
        if action.targetFrame?.isMainFrame == true {
            guard load.allowsMainFrame(url) else {
                load.finish(.failure(BrowserFetchError.refused))
                return (.cancel, preferences)
            }
            load.mainFrameNavigations += 1
            return (.allow, preferences)
        }
        return (load.allowsSubframe(url) ? .allow : .cancel, preferences)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor response: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        guard let load, !load.isFinished else { return .cancel }
        guard response.canShowMIMEType else {
            if response.isForMainFrame { load.finish(.failure(BrowserFetchError.notAPage)) }
            return .cancel
        }
        if response.isForMainFrame {
            let mime = response.response.mimeType?.lowercased() ?? "text/html"
            guard PreviewFetcher.isHTML(mime) else {
                load.finish(.failure(BrowserFetchError.notAPage))
                return .cancel
            }
            if let http = response.response as? HTTPURLResponse, PreviewFetcher.ratingDeclaresAdult(http) {
                load.ratedAdult = true
            }
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        load?.mainFrameIsProvisional = true
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        load?.mainFrameIsProvisional = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        load?.mainFrameIsProvisional = false
        mainFrameFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        mainFrameFailed(error)
    }

    /// A reload (the bot check's, or one interrupting another) cancels the
    /// navigation before it; that's no failure.
    private func mainFrameFailed(_ error: any Error) {
        guard let load, !load.isFinished else { return }
        let error = error as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain", error.code == 102 { return }   // frame load interrupted
        if let page = load.realPage { load.finish(.success(page)) } else { load.finish(.failure(BrowserFetchError.failed)) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        processEnded = true
        load?.finish(.failure(BrowserFetchError.failed))
    }

    func webView(
        _ webView: WKWebView,
        respondTo challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        // Server trust is checked as usual; nothing asks for a password.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            return (.performDefaultHandling, nil)
        }
        return (.cancelAuthenticationChallenge, nil)
    }

    // MARK: UI: nothing opens, nothing asks

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {}

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        false
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        nil
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo
    ) async -> [URL]? {
        nil
    }

    func webView(
        _ webView: WKWebView,
        decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        .deny
    }

    // MARK: Reports

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
        load?.report(body)
    }
}
