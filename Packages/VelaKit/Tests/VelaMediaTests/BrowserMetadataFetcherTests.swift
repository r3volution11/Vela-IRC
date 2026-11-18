// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import WebKit
@testable import VelaMedia

/// The browser engine itself, with pages loaded from strings: an offscreen
/// WKWebView, no network. Each test has its own fetcher (and web view).
@MainActor
@Suite(.serialized) struct BrowserMetadataFetcherTests {
    let base = URL(string: "https://page.example/title/tt0000001/")!
    let policy = MediaPolicy()

    private func fetcher(timeout: Duration = .seconds(8)) -> BrowserMetadataFetcher {
        BrowserMetadataFetcher(options: .init(timeout: timeout, idleTeardown: .milliseconds(200)))
    }

    // MARK: Rules

    @Test func contentRulesCompile() async throws {
        _ = try await BrowserMetadataFetcher.ruleList(blocksSubresources: true)
        _ = try await BrowserMetadataFetcher.ruleList(blocksSubresources: false)
    }

    @Test func contentRulesBlockSubresourcesAndPrivateHosts() throws {
        let blocking = BrowserMetadataFetcher.contentRules(blocksSubresources: true)
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(blocking.utf8)) as? [[String: Any]])
        let actions = rules.compactMap { ($0["action"] as? [String: Any])?["type"] as? String }
        #expect(actions.first == "block")
        #expect(actions.contains("ignore-previous-rules"))
        // The private-network blocks come last, so nothing lets them through.
        let lastAllow = try #require(actions.lastIndex(of: "ignore-previous-rules"))
        #expect(actions[(lastAllow + 1)...].allSatisfy { $0 == "block" })
        #expect(blocking.contains(#"awswaf\\.com"#))
        #expect(blocking.contains(#""load-type":["third-party"]"#))
        for type in ["image", "style-sheet", "font", "media"] { #expect(blocking.contains("\"\(type)\"")) }

        let open = BrowserMetadataFetcher.contentRules(blocksSubresources: false)
        #expect(!open.contains("third-party"))
        #expect(open.contains(#"192\\.168"#))
    }

    @Test func privateHostPatternsMatchWhatThePolicyForbids() throws {
        let patterns = try BrowserMetadataFetcher.privateHostPatterns.map { pattern in
            // The JSON escaping undone: `\\.` → `\.`.
            try NSRegularExpression(pattern: pattern.replacingOccurrences(of: #"\\"#, with: #"\"#), options: [.caseInsensitive])
        }
        func blocked(_ address: String) -> Bool {
            patterns.contains { $0.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)) != nil }
        }
        for address in [
            "http://localhost/", "http://127.0.0.1:8080/x", "https://10.1.2.3/", "http://192.168.1.1/",
            "http://172.16.0.1/", "http://172.31.255.1/", "http://169.254.169.254/latest", "http://100.64.0.1/",
            "http://[::1]/", "http://printer.local/", "http://nas.lan/", "http://router/", "http://router:8080/",
            "http://box.home.arpa/", "http://224.0.0.1/",
        ] {
            #expect(blocked(address), "\(address) isn't blocked")
        }
        for address in [
            "https://www.imdb.com/title/tt8310612/", "https://172.32.0.1/", "https://100.128.0.1/",
            "https://example.com:8443/", "https://fb423e1ef94f.token.awswaf.com/challenge.js", "https://11.0.0.1/",
        ] {
            #expect(!blocked(address), "\(address) is blocked")
        }
    }

    // MARK: Reading pages

    @Test func readsHeadMetadata() async throws {
        let html = """
        <!DOCTYPE html><html><head>
        <title>Plain title</title>
        <meta property="og:title" content="The &amp; Real Title">
        <meta property="og:description" content="What it's about.">
        <meta property="og:image" content="/poster.jpg">
        <meta property="og:image:width" content="1000">
        <meta property="og:image:height" content="1500">
        <meta property="og:site_name" content="Page Example">
        <meta name="theme-color" content="#123456">
        <link rel="icon" href="/favicon-32.png" sizes="32x32">
        <link rel="canonical" href="https://page.example/title/tt0000001/">
        </head><body><p>Hello</p></body></html>
        """
        let fetcher = fetcher()
        let page = try await fetcher.load(html: html, baseURL: base, policy: policy)
        #expect(page.finalURL == base)
        #expect(page.metadata.title == "The & Real Title")
        #expect(page.metadata.summary == "What it's about.")
        #expect(page.metadata.imageURL == URL(string: "https://page.example/poster.jpg"))
        #expect(page.metadata.imageWidth == 1000)
        #expect(page.metadata.imageHeight == 1500)
        #expect(page.metadata.siteName == "Page Example")
        #expect(page.metadata.themeColor == "#123456")
        #expect(page.metadata.faviconURL == URL(string: "https://page.example/favicon-32.png"))
        #expect(page.metadata.declaresAdult == false)
        #expect(fetcher.isIdle)
    }

    @Test func readsAdultRating() async throws {
        let html = #"<html><head><title>Rated</title><meta name="rating" content="adult"></head><body></body></html>"#
        let page = try await fetcher().load(html: html, baseURL: base, policy: policy)
        #expect(page.metadata.declaresAdult)
    }

    /// A bot check's page: no title until its script is done, then the real
    /// page's metadata (here filled in by the script, as a reload would).
    @Test func waitsForTheRealPage() async throws {
        let html = """
        <!DOCTYPE html><html><head><title></title>
        <script>
        setTimeout(() => {
          document.title = 'The Real Page';
          const meta = document.createElement('meta');
          meta.setAttribute('property', 'og:description');
          meta.setAttribute('content', 'Filled in after the check.');
          document.head.appendChild(meta);
        }, 400);
        </script>
        </head><body><div id="challenge-container"></div></body></html>
        """
        let page = try await fetcher().load(html: html, baseURL: base, policy: policy)
        #expect(page.metadata.title == "The Real Page")
        #expect(page.metadata.summary == "Filled in after the check.")
    }

    @Test func aChallengeTitleIsNotThePage() async throws {
        let html = "<html><head><title>Just a moment...</title></head><body><script>1</script></body></html>"
        await #expect(throws: BrowserFetchError.timedOut) {
            try await fetcher(timeout: .seconds(1)).load(html: html, baseURL: base, policy: policy)
        }
    }

    @Test func navigatingToAnotherSiteIsRefused() async throws {
        let html = "<html><head><script>location.href = 'https://elsewhere.example/';</script></head><body></body></html>"
        await #expect(throws: BrowserFetchError.refused) {
            try await fetcher().load(html: html, baseURL: base, policy: policy)
        }
    }

    /// No impersonation: the page sees WebKit's own user agent, not another
    /// browser's or a link-preview bot's.
    @Test func userAgentIsWebKitsOwn() async throws {
        let html = "<html><head><script>document.title = navigator.userAgent;</script></head><body></body></html>"
        let page = try await fetcher().load(html: html, baseURL: base, policy: policy)
        let agent = try #require(page.metadata.title)
        #expect(agent.contains("AppleWebKit/"))
        for other in ["Chrome", "Firefox", "Edg/", "facebookexternalhit", "Slackbot", "Discordbot", "Twitterbot", "Googlebot", "bot"] {
            #expect(!agent.contains(other), "\(agent)")
        }
    }

    @Test func popUpsDoNothing() async throws {
        let html = """
        <html><head><title>Pop-ups</title>
        <script>window.open('https://page.example/popup'); alert('hi'); confirm('ok?'); prompt('name?');</script>
        </head><body></body></html>
        """
        let page = try await fetcher().load(html: html, baseURL: base, policy: policy)
        #expect(page.metadata.title == "Pop-ups")
    }

    // MARK: Policy and limits

    @Test func refusesPrivateAndBlockedAddressesWithoutLoading() async throws {
        let fetcher = fetcher()
        await #expect(throws: BrowserFetchError.refused) {
            try await fetcher.load(URL(string: "http://192.168.1.1/")!, policy: policy)
        }
        var blocking = policy
        blocking.siteRules = SiteRules(["page.example": "block"])
        await #expect(throws: BrowserFetchError.refused) {
            try await fetcher.load(base, policy: blocking)
        }
        #expect(!fetcher.hasWebView)
    }

    @Test func loadsQueueForOneWebView() async throws {
        let fetcher = fetcher()
        func html(_ title: String) -> String { "<html><head><title>\(title)</title></head><body></body></html>" }
        async let first = fetcher.load(html: html("One"), baseURL: base, policy: policy)
        async let second = fetcher.load(html: html("Two"), baseURL: base, policy: policy)
        async let third = fetcher.load(html: html("Three"), baseURL: base, policy: policy)
        let titles = try await [first, second, third].map(\.metadata.title)
        #expect(titles == ["One", "Two", "Three"])
        #expect(fetcher.isIdle)
        #expect(fetcher.hasWebView)
        try await Task.sleep(for: .milliseconds(600))
        #expect(!fetcher.hasWebView, "the idle web view is torn down")
    }

    @Test func aFailedAddressIsNotTriedAgain() async throws {
        let fetcher = fetcher(timeout: .seconds(5))
        let nowhere = URL(string: "https://vela-preview-test.invalid/")!
        await #expect(throws: BrowserFetchError.self) { try await fetcher.load(nowhere, policy: policy) }
        await #expect(throws: BrowserFetchError.failedBefore) { try await fetcher.load(nowhere, policy: policy) }
    }

    @Test func cancellingStopsTheLoad() async throws {
        let fetcher = fetcher()
        let html = "<html><head><title></title></head><body><script>1</script></body></html>"
        let task = Task { try await fetcher.load(html: html, baseURL: base, policy: policy) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fetcher.isIdle)
    }
}
