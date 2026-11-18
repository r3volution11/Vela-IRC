// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

@Suite struct HTMLMetadataParserTests {
    private func parse(fixture: String, base: String = "https://example.com/article") throws -> HTMLMetadata {
        HTMLMetadataParser.parse(html: try Fixtures.string(fixture), baseURL: URL(string: base)!)
    }

    @Test func openGraphArticle() throws {
        let meta = try parse(fixture: "og-article.html")
        #expect(meta.title == "The Real OG Title")
        #expect(meta.summary == "A description from OpenGraph.")
        #expect(meta.siteName == "Example")
        #expect(meta.type == "article")
        // secure_url of the first image wins; the second image's width is ignored.
        #expect(meta.imageURL == URL(string: "https://cdn.example.com/card.jpg"))
        #expect(meta.imageWidth == 1200)
        #expect(meta.imageHeight == 630)
        #expect(meta.videoURL == URL(string: "https://cdn.example.com/clip.mp4"))
        // The theme color without a media query is preferred, normalized to #RRGGBB.
        #expect(meta.themeColor == "#00FF00")
        #expect(meta.faviconURL == URL(string: "https://example.com/favicon-32.png"))
        #expect(meta.oEmbedURL == URL(string: "https://example.com/oembed?url=https%3A%2F%2Fexample.com%2Farticle"))
    }

    @Test func twitterCardFallbacks() throws {
        let meta = try parse(fixture: "twitter-card.html")
        #expect(meta.title == "Tweet-style title")
        #expect(meta.summary == "Tweet-style description")
        #expect(meta.imageURL == URL(string: "https://pbs.example.com/media/abc.png"))
        #expect(meta.imageWidth == nil)
        #expect(meta.siteName == "Bird Site")
        #expect(meta.faviconURL == URL(string: "https://example.com/favicon.ico"))
        #expect(meta.themeColor == nil)
    }

    @Test func metaRefresh() {
        func refresh(_ content: String) -> URL? {
            HTMLMetadataParser.parse(
                html: #"<head><meta http-equiv="Refresh" content="\#(content)"></head>"#,
                baseURL: URL(string: "https://giphy.com/gifs/a")!
            ).refreshURL
        }
        #expect(refresh("0;url=https://giphy.com/gifs/b") == URL(string: "https://giphy.com/gifs/b"))
        #expect(refresh("5; URL='/gifs/c'") == URL(string: "https://giphy.com/gifs/c"))
        #expect(refresh("0") == nil)
        #expect(refresh("0;javascript:alert(1)") == nil)
        #expect(refresh("0;url=javascript:alert(1)") == nil)
    }

    @Test func htmlTitleWhitespaceIsCollapsed() {
        let html = "<head><title>\n   Twitter   Card\n   Page\n</title></head>"
        let meta = HTMLMetadataParser.parse(html: html, baseURL: URL(string: "https://example.com")!)
        #expect(meta.title == "Twitter Card Page")
    }

    @Test func decodesEntities() throws {
        let meta = try parse(fixture: "entities.html")
        #expect(meta.title == "Tom & Jerry's — Café — “Quotes” …")
        #expect(meta.summary == "She said \"hi\" <3 😀 &unknown; &")
        #expect(meta.siteName == "© Example™")
        #expect(meta.imageURL == URL(string: "https://example.com/img?a=1&b=2"))
    }

    @Test func resolvesRelativeURLsAgainstBase() throws {
        let meta = try parse(fixture: "relative-urls.html", base: "https://example.com/posts/1")
        #expect(meta.title == "Relative")
        #expect(meta.imageURL == URL(string: "https://example.com/blog/images/card.png"))
        #expect(meta.faviconURL == URL(string: "https://example.com/apple-touch-icon.png"))
        #expect(meta.oEmbedURL == URL(string: "https://example.com/blog/oembed.json"))
        #expect(meta.videoURL == URL(string: "https://video.example.com/v.mp4"))
    }

    @Test func picksBestFavicon() throws {
        let meta = try parse(fixture: "favicons.html")
        #expect(meta.faviconURL == URL(string: "https://example.com/favicon-32.png"))
        #expect(meta.themeColor == "#FF8000")
    }

    @Test func faviconPreferenceOrder() {
        func favicon(_ links: String) -> String? {
            HTMLMetadataParser.parse(html: "<head>\(links)</head>", baseURL: URL(string: "https://e.com/")!)
                .faviconURL?.path()
        }
        #expect(favicon(#"<link rel="icon" href="/a.svg"><link rel="apple-touch-icon" href="/touch.png">"#) == "/touch.png")
        #expect(favicon(#"<link rel="icon" href="/a.svg"><link rel="icon" href="/small.png" sizes="16x16">"#) == "/small.png")
        #expect(favicon(#"<link rel="icon" href="/only.svg">"#) == "/only.svg")
        #expect(favicon(#"<link rel="apple-touch-icon-precomposed" href="/pre.png">"#) == "/pre.png")
        #expect(favicon(#"<link rel="mask-icon" href="/mask.svg">"#) == nil)
        #expect(favicon(#"<LINK REL="Shortcut Icon" HREF="/fav.ico">"#) == "/fav.ico")
    }

    @Test func missingHead() throws {
        let meta = try parse(fixture: "no-head.html")
        #expect(meta.title == "Headless Page")
        #expect(meta.summary == "Unquoted")
        #expect(meta.imageURL == URL(string: "https://example.org/late.png"))
    }

    @Test func stopsAtEndOfHeadAndIgnoresScriptsAndComments() throws {
        let meta = try parse(fixture: "head-stop.html")
        #expect(meta.title == "Real Title")
        #expect(meta.summary == "Head description")
        #expect(meta.imageURL == nil)
    }

    @Test func attributeQuotingAndCase() {
        let html = """
        <HEAD>
        <Meta Content=Unquoted-Title Property=OG:TITLE>
        <meta property = "og:description"   content = 'single "quoted" value' >
        <meta name="theme-color" content="#ABC"/>
        <meta property="og:image" content=https://example.com/a.png/>
        </HEAD>
        """
        let meta = HTMLMetadataParser.parse(html: html, baseURL: URL(string: "https://example.com")!)
        #expect(meta.title == "Unquoted-Title")
        #expect(meta.summary == #"single "quoted" value"#)
        #expect(meta.themeColor == "#AABBCC")
        #expect(meta.imageURL == URL(string: "https://example.com/a.png/"))
    }

    @Test func emptyAndGarbageInput() {
        let base = URL(string: "https://example.com")!
        #expect(HTMLMetadataParser.parse(html: "", baseURL: base) == HTMLMetadata())
        #expect(HTMLMetadataParser.parse(html: "<<<>>> < <meta <title", baseURL: base).title == nil)
        let unterminated = HTMLMetadataParser.parse(html: "<title>Never closed", baseURL: base)
        #expect(unterminated.title == "Never closed")
        let emptyContent = HTMLMetadataParser.parse(
            html: #"<meta property="og:title" content="   "><title>Fallback</title>"#, baseURL: base
        )
        #expect(emptyContent.title == "Fallback")
    }

    @Test func rejectsNonHTTPURLs() {
        let html = #"""
        <head>
        <meta property="og:image" content="javascript:alert(1)">
        <meta name="twitter:image" content="data:image/png;base64,AAAA">
        <link rel="icon" href="file:///etc/passwd">
        </head>
        """#
        let meta = HTMLMetadataParser.parse(html: html, baseURL: URL(string: "https://example.com")!)
        #expect(meta.imageURL == nil)
        #expect(meta.faviconURL == nil)
    }

    @Test func itempropAndImageSrcFallbacks() {
        let html = """
        <head>
        <meta itemprop="name" content="Schema Name">
        <meta itemprop="description" content="Schema Description">
        <link rel="image_src" href="/thumb.jpg">
        </head>
        """
        let meta = HTMLMetadataParser.parse(html: html, baseURL: URL(string: "https://example.com/x")!)
        #expect(meta.title == "Schema Name")
        #expect(meta.summary == "Schema Description")
        #expect(meta.imageURL == URL(string: "https://example.com/thumb.jpg"))
    }

    // MARK: Adult labels

    @Test func rtaLabelInCapitals() throws {
        let meta = try parse(fixture: "rta.html")
        #expect(meta.declaresAdult)
        #expect(meta.title == "Adults only")
        #expect(meta.imageURL == URL(string: "https://cdn.adult.example/card.jpg"))
    }

    private func declaresAdult(_ head: String) -> Bool {
        HTMLMetadataParser.parse(html: "<html><head>\(head)</head><body></body></html>", baseURL: URL(string: "https://e.com/")!)
            .declaresAdult
    }

    @Test(arguments: [
        #"<meta name="rating" content="adult">"#,
        #"<meta name="Rating" content=" Mature ">"#,
        #"<meta name="rating" content="RTA-5042-1996-1400-1577-RTA">"#,
        #"<meta name="rating" content="rta-5042-1996-1400-1577-rta, adult">"#,
        #"<meta property="rating" content="ADULT">"#,
        #"<meta http-equiv="rating" content="RTA-5042-1996-1400-1577-RTA">"#,
        #"<meta http-equiv="Rating" content="adult">"#,
        #"<meta http-equiv="PICS-Label" content='(PICS-1.1 "http://www.rtalabel.org/" l gen true for "https://e.com" r (n 0 s 0 v 0 l 0))'>"#,
        #"<meta http-equiv="pics-label" content="(pics-1.1 x l r (RTA-5042-1996-1400-1577-RTA))">"#,
        #"<meta property="og:restrictions:age" content="18+">"#,
        #"<meta property="og:restrictions:age" content="21">"#,
    ])
    func adultDeclarations(_ head: String) {
        #expect(declaresAdult(head), "\(head)")
    }

    @Test(arguments: [
        #"<meta name="rating" content="general">"#,
        #"<meta name="rating" content="safe for kids">"#,
        #"<meta name="rating" content="">"#,
        #"<meta name="description" content="adult education courses">"#,
        #"<meta http-equiv="pics-label" content="(PICS-1.1 &quot;http://www.icra.org/ratingsv02.html&quot; l gen true r (cz 1))">"#,
        #"<meta property="og:restrictions:age" content="13+">"#,
        #"<meta property="og:restrictions:age" content="adults">"#,
        #"<meta itemprop="rating" content="adult">"#,
        #"<title>Adult</title>"#,
    ])
    func notAdultDeclarations(_ head: String) {
        #expect(!declaresAdult(head), "\(head)")
    }

    @Test func labelsAfterHeadAreIgnored() {
        let html = #"<html><head><title>Fine</title></head><body><meta name="rating" content="adult"></body></html>"#
        let meta = HTMLMetadataParser.parse(html: html, baseURL: URL(string: "https://e.com/")!)
        #expect(!meta.declaresAdult)
        #expect(meta.title == "Fine")
    }

    @Test func ratingValues() {
        #expect(HTMLMetadataParser.isAdultRating("Adult"))
        #expect(HTMLMetadataParser.isAdultRating(" mature\n"))
        #expect(HTMLMetadataParser.isAdultRating("RTA-5042-1996-1400-1577-RTA"))
        #expect(!HTMLMetadataParser.isAdultRating("general"))
        #expect(!HTMLMetadataParser.isAdultRating("14 years"))
    }

    // MARK: Entities and colors

    @Test(arguments: [
        ("&amp;&lt;&gt;&quot;&apos;", "&<>\"'"),
        ("&#65;&#x42;&#X43;", "ABC"),
        ("&#151;", "—"),         // Windows-1252 remap
        ("&#0;", "\u{FFFD}"),
        ("&#x110000;", "\u{FFFD}"),
        ("&eacute;&Eacute;&uuml;&szlig;", "éÉüß"),
        ("AT&T &copy 2024", "AT&T © 2024"),
        ("&notanentity; & &", "&notanentity; & &"),
        ("&#39", "'"),
        ("no entities", "no entities"),
    ])
    func entities(raw: String, expected: String) {
        #expect(HTMLEntities.decode(raw) == expected)
    }

    @Test(arguments: [
        ("#fff", "#FFFFFF" as String?), ("#FF0000", "#FF0000"), ("#ff000080", "#FF0000"), ("#f008", "#FF0000"),
        ("rgb(255, 0, 0)", "#FF0000"), ("rgba(0,128,255,0.5)", "#0080FF"), ("rgb(0 0 0 / 50%)", "#000000"),
        ("rgb(100%, 0%, 0%)", "#FF0000"), ("red", "#FF0000"), ("  White ", "#FFFFFF"), ("336699", "#336699"),
        ("not-a-color", nil), ("#12", nil), ("", nil), ("hsl(0, 100%, 50%)", nil),
    ])
    func themeColors(raw: String, expected: String?) {
        #expect(CSSColor.normalizedHex(raw) == expected)
    }

    // MARK: Charset decoding

    @Test func decodesDeclaredLatin1() throws {
        let html = #"<html><head><meta charset="iso-8859-1"><title>Café crème</title></head></html>"#
        let data = try #require(html.data(using: .isoLatin1))
        let text = HTMLTextDecoder.decode(data, contentType: "text/html")
        #expect(HTMLMetadataParser.parse(html: text, baseURL: URL(string: "https://e.com")!).title == "Café crème")
    }

    @Test func decodesCharsetFromHeader() throws {
        let html = "<title>日本語のタイトル</title>"
        let data = try #require(html.data(using: .shiftJIS))
        let text = HTMLTextDecoder.decode(data, contentType: "text/html; charset=Shift_JIS")
        #expect(text == html)
    }

    @Test func decodesHTTPEquivCharset() throws {
        let html = #"<meta http-equiv="Content-Type" content="text/html; charset=windows-1251"><title>Привет</title>"#
        let data = try #require(html.data(using: .windowsCP1251))
        #expect(HTMLTextDecoder.decode(data, contentType: nil).hasSuffix("<title>Привет</title>"))
    }

    @Test func fallsBackToLatin1ForInvalidUTF8() {
        var data = Data("<title>Caf".utf8)
        data.append(0xE9)   // é in Latin-1, invalid as UTF-8
        data.append(contentsOf: Array("</title>".utf8))
        #expect(HTMLTextDecoder.decode(data, contentType: "text/html") == "<title>Café</title>")
    }

    @Test func toleratesUTF8CutMidCharacter() {
        let full = Data("<title>naïve ✓</title>".utf8)
        let cut = full.prefix(full.count - 9)   // ends inside the 3-byte check mark
        let text = HTMLTextDecoder.decode(Data(cut), contentType: "text/html; charset=utf-8", isTruncated: true)
        #expect(text == "<title>naïve ")
    }

    @Test func charsetParameterParsing() {
        #expect(HTMLTextDecoder.charsetParameter(#"text/html; charset="UTF-8""#) == "UTF-8")
        #expect(HTMLTextDecoder.charsetParameter("text/html;charset=gbk") == "gbk")
        #expect(HTMLTextDecoder.charsetParameter("text/html") == nil)
        #expect(HTMLTextDecoder.encoding(forLabel: "latin1") == .windowsCP1252)
        #expect(HTMLTextDecoder.encoding(forLabel: "utf-8") == .utf8)
        #expect(HTMLTextDecoder.encoding(forLabel: "no-such-charset") == nil)
    }
}
