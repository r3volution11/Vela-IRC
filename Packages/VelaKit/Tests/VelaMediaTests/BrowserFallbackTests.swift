// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import Testing
@testable import VelaMedia

/// A browser engine that answers from a table and records what it was asked.
final class StubBrowser: BrowserMetadataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var pages: [String: Result<BrowserPage, BrowserFetchError>] = [:]
    private var asked: [URL] = []

    func answer(_ url: String, with page: BrowserPage) {
        lock.withLock { pages[url] = .success(page) }
    }

    func fail(_ url: String, with error: BrowserFetchError) {
        lock.withLock { pages[url] = .failure(error) }
    }

    var requests: [URL] { lock.withLock { asked } }

    @MainActor
    func load(_ url: URL, policy: MediaPolicy) async throws -> BrowserPage {
        let answer = lock.withLock {
            asked.append(url)
            return pages[url.absoluteString]
        }
        switch answer {
        case .success(let page): return page
        case .failure(let error): throw error
        case nil: throw BrowserFetchError.timedOut
        }
    }
}

/// When `PreviewFetcher` turns to the browser engine, and what it makes of
/// the answer: a stub engine, a stub server.
@Suite struct BrowserFallbackTests {
    let server = StubServer()
    let browser = StubBrowser()
    let policy = MediaPolicy()

    private func makeService(cache: (any LinkPreviewCache)? = nil) -> LinkPreviewService {
        LinkPreviewService(session: server.makeSession(), cache: cache, browser: browser)
    }

    private func url(_ string: String) -> URL { URL(string: string)! }

    private static let realPage = HTMLMetadata(
        title: "The Other Two (TV Series 2019–2023)",
        summary: "Two siblings get famous.",
        siteName: "IMDb",
        type: "video.tv_show",
        imageURL: URL(string: "https://m.media-amazon.com/images/M/poster.jpg"),
        faviconURL: URL(string: "https://m.media-amazon.com/images/G/favicon.ico"),
        imageWidth: 1000,
        imageHeight: 1481
    )

    /// An AWS WAF check, as IMDb serves it.
    private func routeAWSChallenge(_ address: String) throws {
        server.route(address, StubResponse(
            status: 202,
            headers: ["Content-Type": "text/html; charset=UTF-8", "x-amzn-waf-action": "challenge"],
            body: Data(try Fixtures.string("awswaf-challenge.html").utf8)
        ))
    }

    /// A Cloudflare check, served as 403.
    private func routeCloudflareChallenge(_ address: String) throws {
        server.route(address, StubResponse(
            status: 403,
            headers: ["Content-Type": "text/html; charset=UTF-8", "cf-mitigated": "challenge"],
            body: Data(try Fixtures.string("cloudflare-challenge.html").utf8)
        ))
    }

    // MARK: The fallback

    @Test func aChallengeIsReadWithTheBrowserEngine() async throws {
        let address = "https://www.imdb.example/title/tt8310612/"
        try routeAWSChallenge(address)
        browser.answer(address, with: BrowserPage(finalURL: url(address), metadata: Self.realPage))
        let cache = MemoryPreviewCache()

        let preview = try await makeService(cache: cache).preview(for: url(address), policy: policy)
        #expect(browser.requests == [url(address)])
        #expect(preview.kind == .page)
        #expect(preview.title == "The Other Two (TV Series 2019–2023)")
        #expect(preview.summary == "Two siblings get famous.")
        #expect(preview.siteName == "IMDb")
        #expect(preview.imageURL == url("https://m.media-amazon.com/images/M/poster.jpg"))
        #expect(preview.imageSize == CGSize(width: 1000, height: 1481))
        #expect(preview.faviconURL == url("https://m.media-amazon.com/images/G/favicon.ico"))
        #expect(preview.loadedWithBrowserEngine == true)
        // Cached like any preview: the page is loaded once.
        #expect(await cache.storeCount == 1)
        _ = try await makeService(cache: cache).preview(for: url(address), policy: policy)
        #expect(browser.requests.count == 1)
    }

    @Test func aChallengeServedAsAnErrorIsReadToo() async throws {
        let address = "https://shop.example/item/42"
        try routeCloudflareChallenge(address)
        browser.answer(address, with: BrowserPage(finalURL: url(address), metadata: HTMLMetadata(title: "Item 42", summary: "A thing.")))
        let preview = try await makeService().preview(for: url(address), policy: policy)
        #expect(preview.title == "Item 42")
        #expect(preview.loadedWithBrowserEngine == true)
    }

    @Test func anEmptyScriptShellIsReadWithTheBrowserEngine() async throws {
        let address = "https://app.example/release-notes"
        server.route(address, .html(try Fixtures.string("spa-shell.html")))
        browser.answer(address, with: BrowserPage(finalURL: url(address), metadata: HTMLMetadata(title: "Release notes")))
        let preview = try await makeService().preview(for: url(address), policy: policy)
        #expect(preview.title == "Release notes")
        #expect(preview.loadedWithBrowserEngine == true)
    }

    @Test func whereTheBrowserLandedIsTheAddress() async throws {
        let address = "https://www.imdb.example/title/tt8310612/"
        try routeAWSChallenge(address)
        let landed = "https://www.imdb.example/title/tt8310612/?ref_=check"
        browser.answer(address, with: BrowserPage(finalURL: url(landed), metadata: Self.realPage))
        let preview = try await makeService().preview(for: url(address), policy: policy)
        #expect(preview.url == url(address))
        #expect(preview.finalURL == url(landed))
    }

    /// The quick fetch followed a short link to the check: the engine loads
    /// where it led, not the short link again.
    @Test func theBrowserLoadsWhereTheLinkLed() async throws {
        server.route("https://short.example/x", .redirect(to: "https://www.imdb.example/title/tt1/"))
        try routeAWSChallenge("https://www.imdb.example/title/tt1/")
        browser.answer("https://www.imdb.example/title/tt1/", with: BrowserPage(finalURL: url("https://www.imdb.example/title/tt1/"), metadata: Self.realPage))
        let preview = try await makeService().preview(for: url("https://short.example/x"), policy: policy)
        #expect(browser.requests == [url("https://www.imdb.example/title/tt1/")])
        #expect(preview.title == Self.realPage.title)
    }

    @Test func anAdultRatingFromTheQuickFetchSticks() async throws {
        let address = "https://www.imdb.example/title/tt2/"
        server.route(address, StubResponse(
            status: 202,
            headers: ["Content-Type": "text/html", "x-amzn-waf-action": "challenge", "Rating": "RTA-5042-1996-1400-1577-RTA"],
            body: Data(try Fixtures.string("awswaf-challenge.html").utf8)
        ))
        browser.answer(address, with: BrowserPage(finalURL: url(address), metadata: Self.realPage))
        var permissive = policy
        permissive.filterAdultSites = false
        let preview = try await makeService().preview(for: url(address), policy: permissive)
        #expect(preview.declaresAdult == true)
        #expect(preview.loadedWithBrowserEngine == true)
    }

    // MARK: When the engine can't help

    @Test func aFailedEngineLeavesAPlainCardKeptInMemoryOnly() async throws {
        let address = "https://www.imdb.example/title/tt3/"
        try routeAWSChallenge(address)
        browser.fail(address, with: .timedOut)
        let cache = MemoryPreviewCache()
        let preview = try await makeService(cache: cache).preview(for: url(address), policy: policy)
        #expect(preview.title == "imdb.example")
        #expect(preview.summary == nil)
        #expect(preview.loadedWithBrowserEngine == nil)
        #expect(await cache.storeCount == 0, "a check's card isn't stored: another try may do better")
    }

    @Test func aFailedEngineLeavesAnErrorChallengeAnError() async throws {
        let address = "https://shop.example/item/43"
        try routeCloudflareChallenge(address)
        browser.fail(address, with: .timedOut)
        await #expect(throws: MediaError.http(403)) {
            try await makeService().preview(for: url(address), policy: policy)
        }
    }

    @Test func ordinaryErrorPagesStayErrors() async throws {
        let address = "https://shop.example/gone"
        server.route(address, .html("<html><head><title>403 Forbidden</title></head><body>Forbidden</body></html>", status: 403))
        await #expect(throws: MediaError.http(403)) {
            try await makeService().preview(for: url(address), policy: policy)
        }
        #expect(browser.requests.isEmpty)
    }

    // MARK: When the engine isn't used

    @Test func ordinaryPagesNeverUseIt() async throws {
        server.route("https://example.com/article", .html(try Fixtures.string("og-article.html")))
        server.route("https://app.example/notes", .html(try Fixtures.string("spa-shell-with-metadata.html")))
        server.route("https://example.com/bare", .html("<html><head></head><body>hi</body></html>"))
        let service = makeService()
        for address in ["https://example.com/article", "https://app.example/notes", "https://example.com/bare"] {
            let preview = try await service.preview(for: url(address), policy: policy)
            #expect(preview.loadedWithBrowserEngine == nil)
        }
        #expect(browser.requests.isEmpty)
    }

    @Test func theSettingTurnsItOff() async throws {
        let address = "https://www.imdb.example/title/tt4/"
        try routeAWSChallenge(address)
        browser.answer(address, with: BrowserPage(finalURL: url(address), metadata: Self.realPage))
        var off = policy
        off.browserFallback = false
        let cache = MemoryPreviewCache()
        let service = makeService(cache: cache)

        let plain = try await service.preview(for: url(address), policy: off)
        #expect(plain.title == "imdb.example")
        #expect(browser.requests.isEmpty)
        #expect(await cache.storeCount == 0, "kept for this setting only")

        // Turned back on, the same link is read properly.
        let full = try await service.preview(for: url(address), policy: policy)
        #expect(full.title == Self.realPage.title)
        #expect(browser.requests.count == 1)
    }

    @Test func theSettingOffLeavesAnErrorChallengeAnError() async throws {
        let address = "https://shop.example/item/44"
        try routeCloudflareChallenge(address)
        var off = policy
        off.browserFallback = false
        await #expect(throws: MediaError.http(403)) {
            try await makeService().preview(for: url(address), policy: off)
        }
        #expect(browser.requests.isEmpty)
    }

    @Test func blockedSitesNeverUseIt() async throws {
        let address = "https://www.imdb.example/title/tt5/"
        try routeAWSChallenge(address)
        var blocking = policy
        blocking.siteRules = SiteRules(["imdb.example": "block"])
        await #expect(throws: MediaError.self) {
            try await makeService().preview(for: url(address), policy: blocking)
        }
        var adult = policy
        adult.extraAdultDomains = ["imdb.example"]
        await #expect(throws: MediaError.self) {
            try await makeService().preview(for: url(address), policy: adult)
        }
        #expect(browser.requests.isEmpty)
        #expect(server.requests.isEmpty)
    }

    @Test func privateNetworkHostsNeverUseIt() async throws {
        for address in ["http://192.168.1.1/admin", "http://localhost:8080/", "http://router/"] {
            await #expect(throws: MediaError.blockedByPolicy) {
                try await makeService().preview(for: url(address), policy: policy)
            }
        }
        #expect(browser.requests.isEmpty)
    }

    @Test func aRedirectIntoABlockedSiteNeverUsesIt() async throws {
        server.route("https://short.example/y", .redirect(to: "https://www.imdb.example/title/tt6/"))
        try routeAWSChallenge("https://www.imdb.example/title/tt6/")
        var blocking = policy
        blocking.siteRules = SiteRules(["imdb.example": "block"])
        await #expect(throws: MediaError.self) {
            try await makeService().preview(for: url("https://short.example/y"), policy: blocking)
        }
        #expect(browser.requests.isEmpty)
    }

    @Test func aPageLabeledAdultNeverUsesItWhileAdultPreviewsAreHidden() async throws {
        let address = "https://www.imdb.example/title/tt7/"
        server.route(address, StubResponse(
            status: 202,
            headers: ["Content-Type": "text/html", "x-amzn-waf-action": "challenge", "Rating": "adult"],
            body: Data(try Fixtures.string("awswaf-challenge.html").utf8)
        ))
        let preview = try await makeService().preview(for: url(address), policy: policy)
        #expect(preview.declaresAdult == true)
        #expect(browser.requests.isEmpty)
    }

    /// Text only allows text metadata, which is all the engine reads.
    @Test func textOnlySitesUseIt() async throws {
        let address = "https://www.imdb.example/title/tt8/"
        try routeAWSChallenge(address)
        browser.answer(address, with: BrowserPage(finalURL: url(address), metadata: Self.realPage))
        var textOnly = policy
        textOnly.siteRules = SiteRules(["imdb.example": "textOnly"])
        let preview = try await makeService().preview(for: url(address), policy: textOnly)
        #expect(preview.title == Self.realPage.title)
        #expect(browser.requests.count == 1)
    }

    /// Video and GIF sites and Reddit have their own ways in.
    @Test func sitesWithTheirOwnWayInNeverUseIt() async throws {
        let shell = try Fixtures.string("spa-shell.html")
        for address in ["https://www.twitch.tv/directory", "https://www.reddit.com/r/LoveTrash/", "https://tenor.com/search/cats", "https://www.youtube.com/feed/trending"] {
            server.route(address, .html(shell))
            _ = try? await makeService().preview(for: url(address), policy: policy)
        }
        // A short link that lands on one.
        server.route("https://short.example/v", .redirect(to: "https://vimeo.com/channels/staffpicks"))
        server.route("https://vimeo.com/channels/staffpicks", .html(shell))
        _ = try? await makeService().preview(for: url("https://short.example/v"), policy: policy)
        #expect(browser.requests.isEmpty)
    }

    @Test func noEngineMeansNoFallback() async throws {
        let address = "https://www.imdb.example/title/tt9/"
        try routeAWSChallenge(address)
        let service = LinkPreviewService(session: server.makeSession(), browser: nil)
        let preview = try await service.preview(for: url(address), policy: policy)
        #expect(preview.title == "imdb.example")
    }

    // MARK: Gates

    @Test func gateFollowsThePolicy() {
        let page = url("https://www.imdb.example/title/tt1/")
        let none = HTMLMetadata()
        #expect(PreviewFetcher.allowsBrowserFallback(url: page, finalURL: page, metadata: none, policy: policy))

        var off = policy
        off.browserFallback = false
        #expect(!PreviewFetcher.allowsBrowserFallback(url: page, finalURL: page, metadata: none, policy: off))

        var blocked = policy
        blocked.siteRules = SiteRules(["imdb.example": "block"])
        #expect(!PreviewFetcher.allowsBrowserFallback(url: page, finalURL: page, metadata: none, policy: blocked))

        var restricted = policy
        restricted.restrictToAllowedDomains = true
        #expect(!PreviewFetcher.allowsBrowserFallback(url: page, finalURL: page, metadata: none, policy: restricted))

        let local = url("http://10.0.0.2/")
        #expect(!PreviewFetcher.allowsBrowserFallback(url: page, finalURL: local, metadata: none, policy: policy))

        var adult = none
        adult.declaresAdult = true
        #expect(!PreviewFetcher.allowsBrowserFallback(url: page, finalURL: page, metadata: adult, policy: policy))
        var unfiltered = policy
        unfiltered.filterAdultSites = false
        #expect(PreviewFetcher.allowsBrowserFallback(url: page, finalURL: page, metadata: adult, policy: unfiltered))

        let reddit = url("https://www.reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard/")
        #expect(!PreviewFetcher.allowsBrowserFallback(url: reddit, finalURL: reddit, metadata: none, policy: policy))
    }

    /// With auto-load off (everywhere, or in a channel with media off),
    /// nothing is fetched, so nothing reaches the engine, until Load is clicked.
    @Test func autoLoadOffFetchesNothingUntilLoad() {
        let page = url("https://www.imdb.example/title/tt1/")
        var context = PreviewContext()
        context.policy.autoLoad = false
        let waiting = PreviewDecider.decide(url: page, classification: MediaClassifier.classify(page), context: context)
        #expect(waiting.plan == .loadChip(.page))
        #expect(!waiting.shouldFetch)

        let clicked = PreviewDecider.decide(
            url: page, classification: MediaClassifier.classify(page), context: context,
            overrides: PreviewOverrides(loadRequested: true)
        )
        #expect(clicked.shouldFetch)
        #expect(clicked.policy.browserFallback)
    }
}
