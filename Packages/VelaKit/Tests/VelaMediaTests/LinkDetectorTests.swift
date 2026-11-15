// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

@Suite struct LinkDetectorTests {
    /// The matched text of each link.
    private func texts(_ message: String) -> [String] {
        LinkDetector.links(in: message).map { String(message[$0.range]) }
    }

    private func urls(_ message: String) -> [String] {
        LinkDetector.links(in: message).map(\.url.absoluteString)
    }

    @Test func plainLink() {
        let message = "check https://example.com/page out"
        let links = LinkDetector.links(in: message)
        #expect(links.count == 1)
        #expect(links.first?.url == URL(string: "https://example.com/page"))
        #expect(links.first.map { String(message[$0.range]) } == "https://example.com/page")
    }

    @Test func noLinks() {
        #expect(LinkDetector.links(in: "").isEmpty)
        #expect(LinkDetector.links(in: "hello there, nothing to see").isEmpty)
    }

    @Test(arguments: [
        ("see https://example.com.", "https://example.com"),
        ("see https://example.com/foo, and more", "https://example.com/foo"),
        ("really https://example.com/a;", "https://example.com/a"),
        ("look: https://example.com/path:", "https://example.com/path"),
        ("wow https://example.com/?q=1!", "https://example.com/?q=1"),
        ("is it https://example.com/path?", "https://example.com/path"),
        ("hmm https://example.com/x...", "https://example.com/x"),
        ("what https://example.com/x?!", "https://example.com/x"),
    ])
    func trimsTrailingPunctuation(message: String, expected: String) {
        #expect(texts(message) == [expected])
        #expect(urls(message) == [expected])
    }

    @Test func keepsBalancedParentheses() {
        let wiki = "https://en.wikipedia.org/wiki/Swift_(programming_language)"
        #expect(texts(wiki) == [wiki])
        #expect(texts("\(wiki).") == [wiki])
        #expect(texts("(see \(wiki))") == [wiki])
        #expect(texts("(see \(wiki)).") == [wiki])
        #expect(texts("(https://example.com/foo)") == ["https://example.com/foo"])
        #expect(texts("https://example.com/a)") == ["https://example.com/a"])
    }

    @Test func balancesSquareBrackets() {
        #expect(texts("[https://example.com/a]") == ["https://example.com/a"])
        #expect(texts("https://example.com/a]") == ["https://example.com/a"])
        #expect(urls("https://example.com/a]") == ["https://example.com/a"])
    }

    @Test func angleBracketWrapping() {
        let message = "link: <https://example.com/a?b=c>"
        #expect(texts(message) == ["https://example.com/a?b=c"])
        #expect(texts("<https://example.com/>") == ["https://example.com/"])
    }

    @Test func quoteAndEmphasisWrapping() {
        #expect(texts("\"https://example.com/quoted\"") == ["https://example.com/quoted"])
        #expect(texts("'https://example.com/single'") == ["https://example.com/single"])
        #expect(texts("*https://example.com/x*") == ["https://example.com/x"])
        #expect(texts("“https://example.com/curly”") == ["https://example.com/curly"])
    }

    @Test func multipleLinks() {
        let message = "two https://a.com/x and http://b.org/y?z=1#frag, also https://c.net."
        #expect(texts(message) == ["https://a.com/x", "http://b.org/y?z=1#frag", "https://c.net"])
        let links = LinkDetector.links(in: message)
        #expect(links.map(\.url.scheme) == ["https", "http", "https"])
        // Ranges are in order and do not overlap.
        #expect(zip(links, links.dropFirst()).allSatisfy { $0.range.upperBound <= $1.range.lowerBound })
    }

    @Test func ignoresNonHTTPSchemes() {
        #expect(urls("ftp://files.example.com/x mailto:foo@bar.com foo@bar.com").isEmpty)
        #expect(urls("javascript:alert(1) data:text/html,hi file:///etc/passwd").isEmpty)
        #expect(urls("irc://irc.libera.chat/#vela").isEmpty)
    }

    @Test func wwwLinksWithoutScheme() {
        let message = "go to www.example.com/path now"
        #expect(texts(message) == ["www.example.com/path"])
        let url = LinkDetector.links(in: message).first?.url
        #expect(url?.host() == "www.example.com")
        #expect(url?.scheme == "http" || url?.scheme == "https")
    }

    @Test func ignoresBareDomains() {
        #expect(urls("see example.com and readme.md and node.js").isEmpty)
    }

    @Test func rangesPointIntoOriginalString() {
        let message = "😀 émoji first: https://example.com/ü?x=1 then text"
        let link = try! #require(LinkDetector.links(in: message).first)
        #expect(String(message[link.range]) == "https://example.com/ü?x=1")
        #expect(link.url.host() == "example.com")
    }

    @Test func internationalizedHost() {
        let link = LinkDetector.links(in: "visit https://例子.测试/路径 now").first
        #expect(link?.url.host()?.hasPrefix("xn--") == true)
    }

    @Test func uppercaseSchemeAndPorts() {
        #expect(texts("HTTPS://EXAMPLE.COM/UP") == ["HTTPS://EXAMPLE.COM/UP"])
        #expect(texts("dev server http://localhost:3000/x?") == ["http://localhost:3000/x"])
    }

    @Test func trailingApostropheOnlyWhenUnpaired() {
        #expect(texts("it's at https://example.com/a'b") == ["https://example.com/a'b"])
    }
}
