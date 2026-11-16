// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import Testing
@testable import VelaMedia

@Suite struct LinkPreviewServiceTests {
    let server = StubServer()
    let policy = MediaPolicy()

    private func makeService(cache: (any LinkPreviewCache)? = nil) -> LinkPreviewService {
        LinkPreviewService(session: server.makeSession(), cache: cache)
    }

    private func url(_ string: String) -> URL { URL(string: string)! }

    // MARK: Pages

    @Test func htmlPage() async throws {
        server.route("https://example.com/article", .html(try Fixtures.string("og-article.html")))
        let preview = try await makeService().preview(for: url("https://example.com/article"), policy: policy)

        #expect(preview.kind == .page)
        #expect(preview.url == url("https://example.com/article"))
        #expect(preview.finalURL == url("https://example.com/article"))
        #expect(preview.title == "The Real OG Title")
        #expect(preview.summary == "A description from OpenGraph.")
        #expect(preview.siteName == "Example")
        #expect(preview.imageURL == url("https://cdn.example.com/card.jpg"))
        #expect(preview.imageSize == CGSize(width: 1200, height: 630))
        #expect(preview.faviconURL == url("https://example.com/favicon-32.png"))
        #expect(preview.themeColor == "#00FF00")
        #expect(preview.contentType == "text/html")
        #expect(preview.mediaURL == nil)
        #expect(preview.embed == nil)
        #expect(preview.id == "https://example.com/article")
        #expect(preview.declaresAdult == false)
        #expect(preview.formatVersion == LinkPreview.currentFormatVersion)

        let request = try #require(server.requests(to: "https://example.com/article").first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == LinkPreviewService.defaultUserAgent)
        #expect(request.value(forHTTPHeaderField: "Accept")?.hasPrefix("text/html") == true)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func defaultUserAgentIsHonest() {
        #expect(LinkPreviewService.defaultUserAgent
            == "Vela/0.1 (Macintosh; link preview; +https://github.com/r3volution11/Vela-IRC)")
    }

    @Test func titleFallsBackToHost() async throws {
        server.route("https://www.example.com/empty", .html("<html><head></head><body>hi</body></html>"))
        let preview = try await makeService().preview(for: url("https://www.example.com/empty"), policy: policy)
        #expect(preview.title == "example.com")
        #expect(preview.faviconURL == url("https://www.example.com/favicon.ico"))
    }

    @Test func latin1PageWithoutHeaderCharset() async throws {
        let html = #"<html><head><meta charset="ISO-8859-1"><title>Crème brûlée</title></head></html>"#
        server.route("https://example.com/fr", StubResponse(headers: ["Content-Type": "text/html"], body: html.data(using: .isoLatin1)!))
        let preview = try await makeService().preview(for: url("https://example.com/fr"), policy: policy)
        #expect(preview.title == "Crème brûlée")
    }

    @Test func pageServingAnImage() async throws {
        let png = try TestImages.png(width: 2, height: 2)
        server.route("https://example.com/i/abc", .data(png, contentType: "image/png"))
        let preview = try await makeService().preview(for: url("https://example.com/i/abc"), policy: policy)
        #expect(preview.kind == .image)
        #expect(preview.mediaURL == url("https://example.com/i/abc"))
        #expect(preview.contentType == "image/png")
    }

    @Test func pageServingOversizedImage() async throws {
        server.route("https://example.com/big", StubResponse(
            headers: ["Content-Type": "image/jpeg", "Content-Length": String(50 * 1024 * 1024)],
            body: Data(repeating: 0, count: 1024)
        ))
        await #expect(throws: MediaError.tooLarge) {
            try await makeService().preview(for: url("https://example.com/big"), policy: policy)
        }
    }

    @Test func pageServingVideo() async throws {
        server.route("https://example.com/stream", .data(Data(repeating: 1, count: 64), contentType: "video/mp4"))
        let preview = try await makeService().preview(for: url("https://example.com/stream"), policy: policy)
        #expect(preview.kind == .video)
        #expect(preview.mediaURL == url("https://example.com/stream"))
    }

    @Test func sniffsImageWithoutContentType() async throws {
        let gif = try TestImages.animatedGIF()
        server.route("https://example.com/noext", .data(gif, contentType: nil))
        let preview = try await makeService().preview(for: url("https://example.com/noext"), policy: policy)
        #expect(preview.kind == .image)
        #expect(preview.contentType == "image/gif")
    }

    @Test func unsupportedContent() async throws {
        server.route("https://example.com/paper", .data(Data("%PDF-1.7".utf8), contentType: "application/pdf"))
        await #expect(throws: MediaError.unsupportedContent) {
            try await makeService().preview(for: url("https://example.com/paper"), policy: policy)
        }
    }

    @Test func httpErrorsAreRememberedBriefly() async throws {
        server.route("https://example.com/broken", .status(500))
        let service = makeService()
        await #expect(throws: MediaError.http(500)) {
            try await service.preview(for: url("https://example.com/broken"), policy: policy)
        }
        await #expect(throws: MediaError.http(500)) {
            try await service.preview(for: url("https://example.com/broken"), policy: policy)
        }
        #expect(server.requests(to: "https://example.com/broken").count == 1)

        await service.removeAllCachedPreviews()
        await #expect(throws: MediaError.http(500)) {
            try await service.preview(for: url("https://example.com/broken"), policy: policy)
        }
        #expect(server.requests(to: "https://example.com/broken").count == 2)
    }

    // MARK: Redirects

    @Test func followsRedirects() async throws {
        server.route("https://short.example/abc", .redirect(to: "https://example.com/landing"))
        server.route("https://example.com/landing", .html("<head><title>Landed</title></head>"))
        let preview = try await makeService().preview(for: url("https://short.example/abc"), policy: policy)
        #expect(preview.url == url("https://short.example/abc"))
        #expect(preview.finalURL == url("https://example.com/landing"))
        #expect(preview.title == "Landed")
        #expect(preview.faviconURL == url("https://example.com/favicon.ico"))
    }

    @Test func redirectToBlockedDomainFailsWithTheReason() async throws {
        server.route("https://short.example/evil", .redirect(to: "https://tracker.example.net/x"))
        server.route("https://tracker.example.net/x", .html("<title>Should not load</title>"))
        let policy = MediaPolicy(siteRules: SiteRules(["example.net": "block"]))
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .userBlocked, domain: "example.net"))) {
            try await makeService().preview(for: url("https://short.example/evil"), policy: policy)
        }
        #expect(server.requests(to: "https://tracker.example.net/x").isEmpty)
    }

    @Test func redirectToAdultDomainFailsWithTheReason() async throws {
        server.route("https://short.example/nsfw", .redirect(to: "https://www.nsfw.example/video"))
        server.route("https://www.nsfw.example/video", .html("<title>Should not load</title>"))
        let policy = MediaPolicy(extraAdultDomains: ["nsfw.example"])
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .adultSite, domain: "nsfw.example"))) {
            try await makeService().preview(for: url("https://short.example/nsfw"), policy: policy)
        }
        #expect(server.requests(to: "https://www.nsfw.example/video").isEmpty)
    }

    @Test func redirectOutsideAllowedSitesFailsWithTheReason() async throws {
        server.route("https://allowed.example/go", .redirect(to: "https://www.elsewhere.example/x"))
        let policy = MediaPolicy(siteRules: SiteRules(["allowed.example": "allow"]), restrictToAllowedDomains: true)
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .notAllowed, domain: "elsewhere.example"))) {
            try await makeService().preview(for: url("https://allowed.example/go"), policy: policy)
        }
    }

    @Test func redirectToPrivateNetworkFails() async throws {
        server.route("https://short.example/lan", .redirect(to: "http://192.168.1.1/reboot"))
        await #expect(throws: MediaError.blockedByPolicy) {
            try await makeService().preview(for: url("https://short.example/lan"), policy: policy)
        }
        #expect(server.requests(to: "http://192.168.1.1/reboot").isEmpty)
    }

    @Test func redirectToYouTubeBecomesEmbed() async throws {
        server.route("https://short.example/yt", .redirect(to: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        server.route("https://www.youtube.com/watch?v=dQw4w9WgXcQ", .html("<head><title>YT page</title></head>"))
        server.route(youTubeOEmbed("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .json([
            "title": "Never Gonna Give You Up", "author_name": "Rick Astley",
        ]))
        let preview = try await makeService().preview(for: url("https://short.example/yt"), policy: policy)
        #expect(preview.kind == .embed)
        #expect(preview.embed?.videoID == "dQw4w9WgXcQ")
        #expect(preview.title == "Never Gonna Give You Up")
        #expect(preview.finalURL == url("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    // MARK: Policy

    @Test func blockedURLNeverHitsNetwork() async throws {
        let policy = MediaPolicy(siteRules: SiteRules(["example.com": "block"]), extraAdultDomains: ["nsfw.example"])
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .userBlocked, domain: "example.com"))) {
            try await makeService().preview(for: url("https://img.example.com/a.png"), policy: policy)
        }
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .adultSite, domain: "nsfw.example"))) {
            try await makeService().preview(for: url("https://nsfw.example/a"), policy: policy)
        }
        await #expect(throws: MediaError.blockedByPolicy) {
            try await makeService().preview(for: url("http://localhost:8080/"), policy: MediaPolicy())
        }
        #expect(server.requests.isEmpty)
    }

    @Test func textOnlySitesAreFetched() async throws {
        server.route("https://example.com/article", .html(try Fixtures.string("og-article.html")))
        let policy = MediaPolicy(siteRules: SiteRules(["example.com": "textOnly"]))
        let preview = try await makeService().preview(for: url("https://example.com/article"), policy: policy)
        #expect(preview.title == "The Real OG Title")
        // Recorded, but a text-only site's images are never loaded.
        #expect(preview.imageURL == url("https://cdn.example.com/card.jpg"))
        #expect(!policy.allowsImage(try #require(preview.imageURL)))
        #expect(!policy.allowsImage(try #require(preview.faviconURL)))
    }

    @Test func cardImageURLsAreKeptButRefusedAsImages() async throws {
        server.route("https://example.com/article", .html(try Fixtures.string("og-article.html")))
        let policy = MediaPolicy(siteRules: SiteRules(["cdn.example.com": "block"]))
        let preview = try await makeService().preview(for: url("https://example.com/article"), policy: policy)
        #expect(preview.title == "The Real OG Title")
        let image = try #require(preview.imageURL)
        #expect(image == url("https://cdn.example.com/card.jpg"))
        #expect(preview.imageSize == CGSize(width: 1200, height: 630))
        #expect(!policy.allowsImage(image))
        #expect(policy.allowsImage(try #require(preview.faviconURL)))
        // Image URLs are never fetched while building the preview.
        #expect(server.requests(to: "https://cdn.example.com/card.jpg").isEmpty)
    }

    // MARK: Failure memory

    @Test func failureMemoryIsPerPolicy() async throws {
        server.route("https://short.example/nsfw", .redirect(to: "https://nsfw.example/video"))
        server.route("https://nsfw.example/video", .html("<head><title>Shown once</title></head>"))
        let service = makeService()
        let strict = MediaPolicy(extraAdultDomains: ["nsfw.example"])
        let link = url("https://short.example/nsfw")

        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .adultSite, domain: "nsfw.example"))) {
            try await service.preview(for: link, policy: strict)
        }
        // Remembered for the same policy (even with display switches changed)…
        var display = strict
        display.autoLoad = false
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .adultSite, domain: "nsfw.example"))) {
            try await service.preview(for: link, policy: display)
        }
        #expect(server.requests(to: "https://short.example/nsfw").count == 1)

        // …but "Show once" applies at once.
        var once = strict
        once.allowedOnce = ["nsfw.example"]
        let preview = try await service.preview(for: link, policy: once)
        #expect(preview.title == "Shown once")
        #expect(preview.finalURL == url("https://nsfw.example/video"))
        #expect(server.requests(to: "https://short.example/nsfw").count == 2)
    }

    @Test func unblockingAppliesImmediately() async throws {
        server.route("https://short.example/t", .redirect(to: "https://tracker.example.net/x"))
        server.route("https://tracker.example.net/x", .html("<head><title>Unblocked</title></head>"))
        let service = makeService()
        let blocked = MediaPolicy(siteRules: SiteRules(["example.net": "block"]))
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .userBlocked, domain: "example.net"))) {
            try await service.preview(for: url("https://short.example/t"), policy: blocked)
        }
        let preview = try await service.preview(for: url("https://short.example/t"), policy: MediaPolicy())
        #expect(preview.title == "Unblocked")
    }

    @Test func previewRefusedPartlyIsKeptInMemoryOnly() async throws {
        server.route("https://example.com/post", .html("""
        <head><link rel="alternate" type="application/json+oembed" href="https://api.example.net/oembed?id=7"></head>
        """))
        server.route("https://api.example.net/oembed?id=7", .json(["title": "From oEmbed"]))
        let cache = MemoryPreviewCache()
        let service = makeService(cache: cache)
        let blocked = MediaPolicy(siteRules: SiteRules(["example.net": "block"]))

        let degraded = try await service.preview(for: url("https://example.com/post"), policy: blocked)
        #expect(degraded.title == "example.com")
        #expect(await cache.storeCount == 0)
        #expect(server.requests(to: "https://api.example.net/oembed?id=7").isEmpty)
        // Served from memory for the same policy…
        _ = try await service.preview(for: url("https://example.com/post"), policy: blocked)
        #expect(server.requests(to: "https://example.com/post").count == 1)
        #expect(await service.cachedPreview(for: url("https://example.com/post"), policy: blocked)?.title == "example.com")
        #expect(await service.cachedPreview(for: url("https://example.com/post"), policy: MediaPolicy()) == nil)

        // …and rebuilt in full once the site is unblocked.
        let full = try await service.preview(for: url("https://example.com/post"), policy: MediaPolicy())
        #expect(full.title == "From oEmbed")
        #expect(await cache.storeCount == 1)
    }

    // MARK: Adult labels

    @Test func pageLabelledAdult() async throws {
        server.route("https://example.com/rta", .html(try Fixtures.string("rta.html")))
        let preview = try await makeService().preview(for: url("https://example.com/rta"), policy: policy)
        #expect(preview.declaresAdult == true)
        #expect(preview.title == "Adults only")
    }

    @Test func ratingHeaderMarksPageAdult() async throws {
        server.route("https://example.com/rated", StubResponse(
            headers: ["Content-Type": "text/html", "Rating": "RTA-5042-1996-1400-1577-RTA"],
            body: Data("<head><title>Rated</title></head>".utf8)
        ))
        server.route("https://example.com/mature", StubResponse(
            headers: ["Content-Type": "text/html", "rating": "Mature"],
            body: Data("<head><title>Mature</title></head>".utf8)
        ))
        server.route("https://example.com/general", StubResponse(
            headers: ["Content-Type": "text/html", "Rating": "general"],
            body: Data("<head><title>General</title></head>".utf8)
        ))
        let service = makeService()
        #expect(try await service.preview(for: url("https://example.com/rated"), policy: policy).declaresAdult == true)
        #expect(try await service.preview(for: url("https://example.com/mature"), policy: policy).declaresAdult == true)
        #expect(try await service.preview(for: url("https://example.com/general"), policy: policy).declaresAdult == false)
    }

    @Test func ratingHeaderOnDirectMedia() async throws {
        server.route("https://example.com/x.jpg", method: "HEAD", StubResponse(
            headers: ["Content-Type": "image/jpeg", "Rating": "adult"]
        ))
        server.route("https://example.com/y.jpg", method: "HEAD", StubResponse(headers: ["Content-Type": "image/jpeg"]))
        let service = makeService()
        #expect(try await service.preview(for: url("https://example.com/x.jpg"), policy: policy).declaresAdult == true)
        #expect(try await service.preview(for: url("https://example.com/y.jpg"), policy: policy).declaresAdult == false)
    }

    // MARK: Direct media

    @Test func directImageUsesHEAD() async throws {
        server.route("https://example.com/cat.png", method: "HEAD", StubResponse(
            headers: ["Content-Type": "image/png", "Content-Length": "2048"]
        ))
        let preview = try await makeService().preview(for: url("https://example.com/cat.png"), policy: policy)
        #expect(preview.kind == .image)
        #expect(preview.mediaURL == url("https://example.com/cat.png"))
        #expect(preview.contentType == "image/png")
        #expect(server.requests.map(\.httpMethod) == ["HEAD"])
    }

    @Test func directImageTooLarge() async throws {
        server.route("https://example.com/huge.jpg", method: "HEAD", StubResponse(
            headers: ["Content-Type": "image/jpeg", "Content-Length": String(11 * 1024 * 1024)]
        ))
        await #expect(throws: MediaError.tooLarge) {
            try await makeService().preview(for: url("https://example.com/huge.jpg"), policy: policy)
        }
        // A larger budget lets it through.
        let generous = MediaPolicy(maxImageBytes: 20 * 1024 * 1024)
        let preview = try await makeService().preview(for: url("https://example.com/huge.jpg"), policy: generous)
        #expect(preview.kind == .image)
    }

    @Test func directImageToleratesBrokenHEAD() async throws {
        server.route("https://example.com/nohead.png", method: "HEAD", .status(405))
        let preview = try await makeService().preview(for: url("https://example.com/nohead.png"), policy: policy)
        #expect(preview.kind == .image)
        #expect(preview.mediaURL == url("https://example.com/nohead.png"))
    }

    @Test func directImageGone() async throws {
        server.route("https://example.com/gone.png", method: "HEAD", .status(404))
        await #expect(throws: MediaError.http(404)) {
            try await makeService().preview(for: url("https://example.com/gone.png"), policy: policy)
        }
    }

    @Test func imageURLServingHTMLIsTreatedAsPage() async throws {
        let page = "https://example.com/photo.jpg"
        server.route(page, method: "HEAD", StubResponse(headers: ["Content-Type": "text/html"]))
        server.route(page, method: "GET", .html(#"<head><meta property="og:image" content="/real.jpg"><title>Viewer</title></head>"#))
        let preview = try await makeService().preview(for: url(page), policy: policy)
        #expect(preview.kind == .page)
        #expect(preview.title == "Viewer")
        #expect(preview.imageURL == url("https://example.com/real.jpg"))
    }

    @Test func directVideoAndGifv() async throws {
        server.route("https://i.imgur.com/AbCd123.mp4", method: "HEAD", StubResponse(headers: ["Content-Type": "video/mp4"]))
        let preview = try await makeService().preview(for: url("https://i.imgur.com/AbCd123.gifv"), policy: policy)
        #expect(preview.kind == .video)
        #expect(preview.url == url("https://i.imgur.com/AbCd123.gifv"))
        #expect(preview.mediaURL == url("https://i.imgur.com/AbCd123.mp4"))
    }

    // MARK: Embeds

    private func youTubeOEmbed(_ page: String) -> String {
        "https://www.youtube.com/oembed?format=json&url=" + OEmbedEndpoint.encode(page)
    }

    @Test func youtubeOEmbed() async throws {
        server.route(youTubeOEmbed("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .json([
            "title": "Never Gonna Give You Up",
            "author_name": "Rick Astley",
            "provider_name": "YouTube",
            "thumbnail_url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
            "thumbnail_width": 480,
            "thumbnail_height": 360,
            "width": 200,
            "height": 113,
        ]))
        let preview = try await makeService().preview(
            for: url("https://youtu.be/dQw4w9WgXcQ?t=1m30s"), policy: policy
        )
        #expect(preview.kind == .embed)
        #expect(preview.title == "Never Gonna Give You Up")
        #expect(preview.siteName == "YouTube")
        #expect(preview.themeColor == "#FF0000")
        #expect(preview.imageURL == url("https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"))
        #expect(preview.imageSize == CGSize(width: 480, height: 360))
        let embed = try #require(preview.embed)
        #expect(embed.provider == .youtube)
        #expect(embed.authorName == "Rick Astley")
        #expect(embed.title == "Never Gonna Give You Up")
        #expect(embed.startSeconds == 90)
        #expect(embed.embedURL.absoluteString.hasPrefix("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=90"))

        let request = try #require(server.requests.first)
        #expect(request.url?.absoluteString
            == "https://www.youtube.com/oembed?format=json&url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ")
        #expect(server.requests.count == 1)
    }

    @Test func youtubeOEmbedFailureKeepsFallbackThumbnail() async throws {
        server.route(youTubeOEmbed("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .status(401))
        let preview = try await makeService().preview(for: url("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), policy: policy)
        #expect(preview.kind == .embed)
        #expect(preview.title == nil)
        #expect(preview.imageURL == url("https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"))
    }

    @Test func thumbnailOnBlockedHostIsKeptButRefused() async throws {
        server.route(youTubeOEmbed("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .json(["title": "T"]))
        let policy = MediaPolicy(siteRules: SiteRules(["ytimg.com": "block"]))
        let preview = try await makeService().preview(for: url("https://youtu.be/dQw4w9WgXcQ"), policy: policy)
        #expect(preview.title == "T")
        let thumbnail = try #require(preview.imageURL)
        #expect(preview.embed?.thumbnailURL == thumbnail)
        #expect(!policy.allowsImage(thumbnail))
    }

    @Test func blockedOEmbedEndpointDegradesThePreview() async throws {
        // A rule for the provider covers the link itself, so nothing is fetched…
        let blocked = MediaPolicy(siteRules: SiteRules(["youtube.com": "block"]))
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .userBlocked, domain: "youtube.com"))) {
            try await makeService().preview(for: url("https://youtu.be/dQw4w9WgXcQ"), policy: blocked)
        }
        // …while a more specific allow rule for the short link still skips oEmbed.
        let cache = MemoryPreviewCache()
        let partly = MediaPolicy(siteRules: SiteRules(["youtube.com": "block", "youtu.be": "allow"]))
        let preview = try await makeService(cache: cache).preview(for: url("https://youtu.be/dQw4w9WgXcQ"), policy: partly)
        #expect(preview.kind == .embed)
        #expect(preview.title == nil)
        #expect(server.requests.isEmpty)
        #expect(await cache.storeCount == 0)
    }

    @Test func nonWebThumbnailURLsAreIgnored() async throws {
        server.route(youTubeOEmbed("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .json([
            "title": "T", "thumbnail_url": "javascript:alert(1)",
        ]))
        let preview = try await makeService().preview(for: url("https://youtu.be/dQw4w9WgXcQ"), policy: policy)
        #expect(preview.imageURL == url("https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"))
    }

    @Test func vimeoOEmbedSetsAspectRatio() async throws {
        let endpoint = "https://vimeo.com/api/oembed.json?url=" + OEmbedEndpoint.encode("https://vimeo.com/76979871")
        server.route(endpoint, .json([
            "title": "Vertical", "author_name": "Someone", "thumbnail_url": "https://i.vimeocdn.com/video/1.jpg",
            "width": "1080", "height": 1920,
        ]))
        let preview = try await makeService().preview(for: url("https://vimeo.com/76979871"), policy: policy)
        #expect(preview.title == "Vertical")
        #expect(preview.imageURL == url("https://i.vimeocdn.com/video/1.jpg"))
        #expect(abs((preview.embed?.aspectRatio ?? 0) - 0.5625) < 0.001)
    }

    @Test func streamableOEmbed() async throws {
        let endpoint = "https://api.streamable.com/oembed.json?url=" + OEmbedEndpoint.encode("https://streamable.com/abc123")
        server.route(endpoint, .json(["title": "A clip", "thumbnail_url": "https://cdn.streamable.com/image/abc123.jpg"]))
        let preview = try await makeService().preview(for: url("https://streamable.com/abc123"), policy: policy)
        #expect(preview.embed?.provider == .streamable)
        #expect(preview.title == "A clip")
        #expect(preview.siteName == "Streamable")
    }

    @Test func twitchUsesPageOpenGraph() async throws {
        let clip = "https://clips.twitch.tv/AwkwardHelplessSalamanderSwiftRage"
        server.route(clip, .html("""
        <head>
        <meta property="og:title" content="Amazing play">
        <meta property="og:description" content="Clipped by someone">
        <meta property="og:image" content="https://clips-media-assets2.twitch.tv/thumb.jpg">
        </head>
        """))
        let preview = try await makeService().preview(for: url(clip), policy: policy)
        #expect(preview.kind == .embed)
        #expect(preview.title == "Amazing play")
        #expect(preview.summary == "Clipped by someone")
        #expect(preview.imageURL == url("https://clips-media-assets2.twitch.tv/thumb.jpg"))
        #expect(preview.siteName == "Twitch")
        #expect(preview.embed?.embedURL.absoluteString
            == "https://clips.twitch.tv/embed?clip=AwkwardHelplessSalamanderSwiftRage&parent=r3volution11.github.io")
    }

    @Test func pageAdvertisingOEmbedFillsMissingFields() async throws {
        server.route("https://example.com/post", .html("""
        <head><link rel="alternate" type="application/json+oembed" href="/oembed?id=7"></head>
        """))
        server.route("https://example.com/oembed?id=7", .json([
            "title": "From oEmbed", "provider_name": "ExampleTube", "thumbnail_url": "https://example.com/t.jpg",
            "thumbnail_width": 640, "thumbnail_height": 360,
        ]))
        let preview = try await makeService().preview(for: url("https://example.com/post"), policy: policy)
        #expect(preview.title == "From oEmbed")
        #expect(preview.siteName == "ExampleTube")
        #expect(preview.imageURL == url("https://example.com/t.jpg"))
        #expect(preview.imageSize == CGSize(width: 640, height: 360))
    }

    // MARK: Limits

    @Test func readsAtMostHalfAMegabyteOfHTML() async throws {
        let head = #"<html><head><meta property="og:title" content="Big page">"#
        let filler = String(repeating: "<!-- padding padding padding padding -->\n", count: 60_000)   // ~2.5 MB, no </head>
        var response = StubResponse.html(head + filler)
        response.chunkSize = 64 * 1024
        // Pace the stub so cancellation can reach it before it sends everything.
        response.chunkDelay = 0.002
        server.route("https://example.com/huge", response)

        let preview = try await makeService().preview(for: url("https://example.com/huge"), policy: policy)
        #expect(preview.title == "Big page")
        let totalChunks = (head.utf8.count + filler.utf8.count + response.chunkSize - 1) / response.chunkSize
        #expect(server.chunksDelivered(for: "https://example.com/huge") < totalChunks)
    }

    @Test func stopsReadingAfterHead() async throws {
        let html = "<html><head><title>Early</title></head><body>"
            + String(repeating: "<p>body text</p>\n", count: 50_000) + "</body></html>"
        var response = StubResponse.html(html)
        response.chunkSize = 4 * 1024
        response.chunkDelay = 0.001
        server.route("https://example.com/early", response)

        let preview = try await makeService().preview(for: url("https://example.com/early"), policy: policy)
        #expect(preview.title == "Early")
        #expect(server.chunksDelivered(for: "https://example.com/early") < 20)
    }

    // MARK: Caching and deduplication

    @Test func concurrentRequestsAreDeduplicated() async throws {
        var response = StubResponse.html("<head><title>Slow</title></head>")
        response.delay = 0.3
        server.route("https://example.com/slow", response)
        let service = makeService()
        let target = url("https://example.com/slow")
        let policy = self.policy

        let titles = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<8 {
                group.addTask { try await service.preview(for: target, policy: policy).title }
            }
            return try await group.reduce(into: [String?]()) { $0.append($1) }
        }
        #expect(titles == Array(repeating: "Slow", count: 8))
        #expect(server.requests(to: "https://example.com/slow").count == 1)
    }

    @Test func cancellingTheOnlyCallerCancelsTheFetch() async throws {
        var response = StubResponse.html("<title>Too slow</title>")
        response.delay = 10
        server.route("https://example.com/glacial", response)
        let service = makeService()
        let target = url("https://example.com/glacial")
        let policy = self.policy

        let started = Date()
        let task = Task { try await service.preview(for: target, policy: policy) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(started) < 5)

        // Cancellation is not remembered as a failure: the next call fetches again.
        server.route("https://example.com/glacial", .html("<title>Now fast</title>"))
        #expect(try await service.preview(for: target, policy: policy).title == "Now fast")
    }

    @Test func memoryCache() async throws {
        server.route("https://example.com/once", .html("<title>Once</title>"))
        let service = makeService()
        _ = try await service.preview(for: url("https://example.com/once"), policy: policy)
        let again = try await service.preview(for: url("https://example.com/once"), policy: policy)
        #expect(again.title == "Once")
        #expect(server.requests.count == 1)
        #expect(await service.cachedPreview(for: url("https://example.com/once"))?.title == "Once")
        #expect(await service.cachedPreview(for: url("https://example.com/other")) == nil)
    }

    @Test func persistentCache() async throws {
        server.route("https://example.com/persist", .html("<title>Persisted</title>"))
        let cache = MemoryPreviewCache()
        _ = try await makeService(cache: cache).preview(for: url("https://example.com/persist"), policy: policy)
        #expect(await cache.storeCount == 1)

        // A new service (e.g. after relaunch) is served from the persistent cache.
        let preview = try await makeService(cache: cache).preview(for: url("https://example.com/persist"), policy: policy)
        #expect(preview.title == "Persisted")
        #expect(server.requests.count == 1)
    }

    @Test func staleCacheEntriesAreRefetched() async throws {
        server.route("https://example.com/stale", .html("<title>Fresh</title>"))
        let cache = MemoryPreviewCache()
        await cache.storePreview(LinkPreview(
            url: url("https://example.com/stale"), kind: .page, title: "Old",
            fetchedAt: Date(timeIntervalSinceNow: -30 * 24 * 3600)
        ))
        let preview = try await makeService(cache: cache).preview(for: url("https://example.com/stale"), policy: policy)
        #expect(preview.title == "Fresh")
    }

    @Test func oldCacheFormatIsRefetched() async throws {
        server.route("https://example.com/v1", .html("<title>Fresh</title>"))
        server.route("https://example.com/v2", .html("<title>Fresh</title>"))
        let cache = MemoryPreviewCache()
        await cache.storePreview(LinkPreview(url: url("https://example.com/v1"), kind: .page, title: "Old", formatVersion: nil))
        await cache.storePreview(LinkPreview(url: url("https://example.com/v2"), kind: .page, title: "Old", formatVersion: 1))
        await cache.storePreview(LinkPreview(url: url("https://example.com/current"), kind: .page, title: "Current"))
        let service = makeService(cache: cache)
        #expect(try await service.preview(for: url("https://example.com/v1"), policy: policy).title == "Fresh")
        #expect(try await service.preview(for: url("https://example.com/v2"), policy: policy).title == "Fresh")
        #expect(try await service.preview(for: url("https://example.com/current"), policy: policy).title == "Current")
        #expect(server.requests(to: "https://example.com/current").isEmpty)
    }

    @Test func oldPreviewJSONStillDecodes() throws {
        let json = """
        {"url":"https://example.com/a","finalURL":"https://example.com/a","kind":"page","title":"Old",
         "imageURL":"https://example.com/i.png","imageSize":[640,360],"fetchedAt":700000000}
        """
        let preview = try JSONDecoder().decode(LinkPreview.self, from: Data(json.utf8))
        #expect(preview.title == "Old")
        #expect(preview.imageSize == CGSize(width: 640, height: 360))
        #expect(preview.declaresAdult == nil)
        #expect(preview.formatVersion == nil)
        #expect(!preview.isCurrentFormat)
        #expect(LinkPreview(url: url("https://example.com/a"), kind: .page).isCurrentFormat)
    }

    @Test func previewIsCodable() async throws {
        server.route("https://example.com/article", .html(try Fixtures.string("og-article.html")))
        let preview = try await makeService().preview(for: url("https://example.com/article"), policy: policy)
        let data = try JSONEncoder().encode(preview)
        #expect(try JSONDecoder().decode(LinkPreview.self, from: data) == preview)

        var labelled = preview
        labelled.declaresAdult = true
        let decoded = try JSONDecoder().decode(LinkPreview.self, from: try JSONEncoder().encode(labelled))
        #expect(decoded.declaresAdult == true)
        #expect(decoded.formatVersion == LinkPreview.currentFormatVersion)
    }

    // MARK: Display helpers

    @Test func displayHelpers() {
        let page = LinkPreview(
            url: url("https://www.example.com/a"), kind: .page, title: "  Spaced \n title ", summary: " ",
            siteName: nil
        )
        #expect(page.displayTitle == "Spaced title")
        #expect(page.displaySummary == nil)
        #expect(page.displaySiteName == "example.com")
        #expect(page.hasCardContent)

        let bare = LinkPreview(url: url("https://example.com/"), kind: .page, imageURL: url("https://example.com/i.png"))
        #expect(bare.displayTitle == nil)
        #expect(bare.hasCardContent)
        #expect(!bare.hasCardContent(showingImages: false))

        let video = LinkPreview(
            url: url("https://i.imgur.com/AbCd123.gifv"), kind: .video, mediaURL: url("https://i.imgur.com/AbCd123.mp4")
        )
        #expect(video.displayTitle == "AbCd123.mp4")
        #expect(video.hasCardContent(showingImages: false))
        let file = LinkPreview(url: url("https://example.com/My%20Clip.mov"), kind: .video)
        #expect(file.displayTitle == "My Clip.mov")
        let embed = LinkPreview(
            url: url("https://youtu.be/dQw4w9WgXcQ"), kind: .embed, siteName: "YouTube",
            embed: EmbedInfo.youtube(id: "dQw4w9WgXcQ", start: nil, isShort: false)
        )
        #expect(embed.displayTitle == nil)
        #expect(embed.displaySiteName == "YouTube")
    }
}
