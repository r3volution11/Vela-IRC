// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

/// `BotCheckDetector`: which quick-fetch answers are bot checks or empty
/// script shells (and so worth the browser engine), and which are pages.
@Suite struct BotCheckTests {
    let base = URL(string: "https://www.site.example/title/tt0000001/")!

    private func assess(_ html: String, status: Int = 200, headers: [String: String] = [:]) -> BotCheck? {
        let metadata = HTMLMetadataParser.parse(html: html, baseURL: base)
        return BotCheckDetector.assess(status: status, headers: headers, html: html, metadata: metadata)
    }

    // MARK: Bot checks

    @Test func awsWAFChallenge() throws {
        let html = try Fixtures.string("awswaf-challenge.html")
        #expect(assess(html, status: 202, headers: ["x-amzn-waf-action": "challenge"]) == .challenge(.awsWAF))
        // The header alone, and the markup alone, each give it away.
        #expect(assess("<html><head><title></title></head></html>", status: 202, headers: ["X-Amzn-Waf-Action": "captcha"])
            == .challenge(.awsWAF))
        #expect(assess(html) == .challenge(.awsWAF))
    }

    @Test func cloudflareChallenge() throws {
        let html = try Fixtures.string("cloudflare-challenge.html")
        #expect(assess(html, status: 403, headers: ["cf-mitigated": "challenge", "Server": "cloudflare"]) == .challenge(.cloudflare))
        #expect(assess(html, status: 503) == .challenge(.cloudflare))
        // Its title alone.
        #expect(assess("<html><head><title>Just a moment…</title></head><body></body></html>", status: 403)
            == .challenge(.cloudflare))
    }

    @Test func otherServices() {
        #expect(assess(#"<html><head><title>shop.example</title></head><body><script src="https://ct.captcha-delivery.com/c.js"></script></body></html>"#, status: 403)
            == .challenge(.dataDome))
        #expect(assess(#"<html><head><title>Access to this page has been denied</title></head><body><div id="px-captcha"></div></body></html>"#, status: 403)
            == .challenge(.perimeterX))
        #expect(assess(#"<html><head><title>Pardon Our Interruption</title></head><body></body></html>"#)
            == .challenge(.imperva))
        #expect(assess(#"<html><head></head><body><script src="/_sec/cp_challenge/ak-challenge-4-5.js"></script></body></html>"#)
            == .challenge(.akamai))
        #expect(assess("<html><head><title>Checking your browser...</title></head></html>") == .challenge(.other))
    }

    // MARK: Script shells

    @Test func emptyScriptShell() throws {
        #expect(assess(try Fixtures.string("spa-shell.html")) == .scriptShell)
        #expect(assess("<html><head><script src=/app.js></script></head><body><div id=app></div></body></html>") == .scriptShell)
    }

    @Test func aShellWithMetadataIsAPage() throws {
        #expect(assess(try Fixtures.string("spa-shell-with-metadata.html")) == nil)
    }

    // MARK: Pages

    @Test func ordinaryPagesAreNot() throws {
        #expect(assess(try Fixtures.string("og-article.html")) == nil)
        #expect(assess(try Fixtures.string("twitter-card.html")) == nil)
        #expect(assess("<html><head></head><body>hi</body></html>") == nil)
        #expect(assess("<html><head><title>Example Domain</title></head><body><p>Hello</p></body></html>") == nil)
    }

    /// Cloudflare adds a script to ordinary pages (`/cdn-cgi/challenge-platform/scripts/jsd/…`);
    /// AWS WAF's integration script turns up on ordinary pages too.
    @Test func botManagersOnOrdinaryPagesAreNot() {
        let cloudflare = """
        <html><head><title>A blog post</title><meta name="description" content="About things."></head>
        <body><p>Text.</p><script>window.__CF$cv$params={r:'1',t:'2'};var a=document.createElement('script');a.src='/cdn-cgi/challenge-platform/scripts/jsd/main.js';</script></body></html>
        """
        #expect(assess(cloudflare) == nil)
        let aws = """
        <html><head><title>Product</title><meta property="og:image" content="/p.jpg">
        <script>window.awsWafCookieDomainList = ['shop.example'];</script></head><body></body></html>
        """
        #expect(assess(aws) == nil)
    }

    @Test func aPageWithLotsOfTextIsNotAShell() {
        let text = String(repeating: "Words people read on the page. ", count: 20)
        #expect(assess("<html><body><p>\(text)</p><script>track()</script></body></html>") == nil)
    }

    @Test func errorPagesStayErrors() {
        #expect(assess("<html><head><title>403 Forbidden</title></head><body><h1>Forbidden</h1></body></html>", status: 403) == nil)
        #expect(assess("<html><head></head><body><script>retry()</script></body></html>", status: 503) == nil)
        #expect(assess("<html><head></head><body>Please enable JavaScript</body></html>", status: 429) == nil)
    }

    // MARK: The browser engine's view

    @Test func realPageVersusCheck() {
        func metadata(_ html: String) -> HTMLMetadata { HTMLMetadataParser.parse(html: html, baseURL: base) }
        #expect(!BotCheckDetector.isRealPage(metadata("<html><head><title></title></head></html>")))
        #expect(!BotCheckDetector.isRealPage(metadata("<html><head><title>Just a moment...</title></head></html>")))
        #expect(!BotCheckDetector.isRealPage(metadata("<html><head><title>Loading…</title></head></html>")))
        #expect(BotCheckDetector.isRealPage(metadata("<html><head><title>The Other Two (TV Series 2019–2023)</title></head></html>")))
        #expect(BotCheckDetector.isRealPage(metadata(#"<html><head><meta property="og:description" content="x"></head></html>"#)))
    }

    @Test func visibleTextSkipsScriptsStylesAndComments() {
        let html = "<html><head><style>body { color: red }</style><script>var x = '<p>not text</p>';</script></head><body><!-- a comment --><p>Hi  there</p><noscript>Enable JS</noscript></body></html>"
        #expect(BotCheckDetector.visibleTextLength(html.lowercased(), limit: 1000) == "hi there".count)
    }
}
