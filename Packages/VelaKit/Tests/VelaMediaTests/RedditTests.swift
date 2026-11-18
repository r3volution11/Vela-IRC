// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import Testing
@testable import VelaMedia

@Suite struct RedditLinkTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private func embed(_ string: String) -> EmbedInfo? {
        if case .embed(let info) = MediaClassifier.classify(url(string)) { return info }
        return nil
    }

    // MARK: Videos

    @Test(arguments: [
        "https://v.redd.it/1crlzghxl82i1",
        "http://v.redd.it/1crlzghxl82i1/",
        "https://v.redd.it/1crlzghxl82i1/HLSPlaylist.m3u8",
        "https://v.redd.it/1crlzghxl82i1/DASH_480.mp4?source=fallback",
        "https://www.reddit.com/video/1crlzghxl82i1",
    ])
    func videoLinksPlayInline(_ link: String) throws {
        let info = try #require(embed(link))
        #expect(info.provider == .reddit)
        #expect(info.videoID == "1crlzghxl82i1")
        #expect(info.embedURL == url("https://v.redd.it/1crlzghxl82i1/HLSPlaylist.m3u8"))
        #expect(info.thumbnailURL == nil)
        #expect(info.canonicalPageURL == url("https://v.redd.it/1crlzghxl82i1"))
        #expect(EmbedProvider.reddit.playsNatively)
        #expect(!EmbedProvider.youtube.playsNatively)
    }

    @Test(arguments: ["https://v.redd.it/", "https://v.redd.it/AB", "https://v.redd.it/Not-An-ID", "https://www.reddit.com/video/"])
    func otherVideoHostLinksAreNot(_ link: String) {
        #expect(embed(link) == nil)
    }

    // MARK: Posts and images

    @Test(arguments: [
        ("https://www.reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard/", "r/LoveTrash", "jet_powered_skateboard"),
        ("https://reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard", "r/LoveTrash", "jet_powered_skateboard"),
        ("https://old.reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard/?utm=x", "r/LoveTrash", "jet_powered_skateboard"),
        ("https://new.reddit.com/r/LoveTrash/comments/1xyw5ml/", "r/LoveTrash", nil),
        ("https://np.reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard/abc123/", "r/LoveTrash", "jet_powered_skateboard"),
        ("https://m.reddit.com/user/downtune79/comments/1xyw5ml/hi/", "u/downtune79", "hi"),
        ("https://www.reddit.com/comments/1xyw5ml", nil, nil),
    ] as [(String, String?, String?)])
    func postLinks(_ link: String, community: String?, slug: String?) throws {
        let post = try #require(RedditLinks.post(url(link)))
        #expect(post.id == "1xyw5ml")
        #expect(post.community == community)
        #expect(post.slug == slug)
        #expect(post.canonicalURL.host() == "www.reddit.com")
        #expect(post.canonicalURL.query() == nil)
        // Posts stay pages: what they hold can't be told from the address.
        #expect(MediaClassifier.classify(url(link)) == .page(url(link)))
    }

    @Test func canonicalPostURL() {
        #expect(RedditLinks.post(url("https://old.reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard/?utm=x"))?.canonicalURL
            == url("https://www.reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard/"))
    }

    @Test(arguments: [
        "https://www.reddit.com/", "https://www.reddit.com/r/LoveTrash/", "https://redd.it/1xyw5ml",
        "https://www.reddit.com/r/LoveTrash/s/AbCdEf12", "https://www.reddit.com/r/LoveTrash/comments/",
        "https://example.com/r/x/comments/1xyw5ml/", "https://www.reddit.com/r/x/y/comments/1xyw5ml/",
    ])
    func notPosts(_ link: String) {
        #expect(RedditLinks.post(url(link)) == nil)
    }

    @Test func redditImagesAreImages() {
        for link in [
            "https://i.redd.it/abc123def456.jpg", "https://i.redd.it/abc123def456.gif", "https://i.redd.it/abc123.png",
            "https://preview.redd.it/abc123def456.png?width=640&format=png&auto=webp&s=0123abcd",
        ] {
            #expect(MediaClassifier.classify(url(link)) == .image(url(link)))
        }
    }

    @Test func slugTitles() {
        #expect(RedditLinks.title(fromSlug: "jet_powered_skateboard") == "Jet powered skateboard")
        #expect(RedditLinks.title(fromSlug: "til_42") == "Til 42")
        #expect(RedditLinks.title(fromSlug: "___") == nil)
        #expect(RedditLinks.title(fromSlug: nil) == nil)
    }

    // MARK: oEmbed

    @Test func oEmbedResponse() throws {
        let data = Data(try Fixtures.string("reddit-oembed.json").utf8)
        let response = try JSONDecoder().decode(OEmbedResponse.self, from: data)
        #expect(response.title == "Jet powered skateboard")
        #expect(response.authorName == "downtune79")
        #expect(response.providerName == "reddit")
        #expect(response.thumbnailURL == nil)
        #expect(RedditLinks.community(inEmbedHTML: response.html) == "r/LoveTrash")
        #expect(RedditLinks.community(inEmbedHTML: "<a href=\"https://www.reddit.com/user/x/\">x</a>") == nil)
        #expect(RedditLinks.community(inEmbedHTML: nil) == nil)
    }

    @Test func oEmbedEndpointEncodesThePost() {
        let post = url("https://www.reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard/")
        #expect(OEmbedEndpoint.reddit(post: post)?.absoluteString
            == "https://www.reddit.com/oembed?url=https%3A%2F%2Fwww.reddit.com%2Fr%2FLoveTrash%2Fcomments%2F1xyw5ml%2Fjet_powered_skateboard%2F")
        // Videos need their post first.
        #expect(OEmbedEndpoint.url(for: EmbedInfo.reddit(id: "1crlzghxl82i1")) == nil)
    }

    // MARK: NSFW

    @Test func ageCheck() {
        #expect(RedditLinks.isAgeGate(url("https://www.reddit.com/over18?dest=https%3A%2F%2Fwww.reddit.com%2Fr%2Fx%2Fcomments%2Fabc%2F")))
        #expect(RedditLinks.isAgeGate(url("https://old.reddit.com/over18/")))
        #expect(!RedditLinks.isAgeGate(url("https://www.reddit.com/r/over18/comments/abc/")))
        #expect(!RedditLinks.isAgeGate(url("https://example.com/over18")))
    }

    // MARK: HLS

    @Test func playlistWithSound() throws {
        let summary = try #require(HLSPlaylist.summary(try Fixtures.string("reddit-hls.m3u8")))
        #expect(summary.hasAudio)
        #expect(summary.largestResolution == CGSize(width: 854, height: 480))
        #expect(abs((summary.aspectRatio ?? 0) - 854.0 / 480.0) < 0.001)
    }

    @Test func playlistWithoutSoundIsAGIF() throws {
        let summary = try #require(HLSPlaylist.summary(try Fixtures.string("reddit-hls-gif.m3u8")))
        #expect(!summary.hasAudio)
        #expect(summary.largestResolution == CGSize(width: 360, height: 640))
    }

    @Test func playlistSoundFromCodecsAlone() {
        let muxed = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS=\"avc1.4d401e,mp4a.40.2\"\na.m3u8\n"
        #expect(HLSPlaylist.summary(muxed)?.hasAudio == true)
        let silent = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS=\"avc1.4d401e\"\na.m3u8\n"
        #expect(HLSPlaylist.summary(silent)?.hasAudio == false)
    }

    @Test func notAMasterPlaylist() {
        #expect(HLSPlaylist.summary("<html>Too many requests</html>") == nil)
        #expect(HLSPlaylist.summary("#EXTM3U\n#EXTINF:4.0,\nsegment0.m4s\n") == nil)
        #expect(HLSPlaylist.attribute("CODECS", in: #"#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="a,b",RESOLUTION=2x1"#) == "a,b")
        #expect(HLSPlaylist.attribute("RESOLUTION", in: #"#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="a,b",RESOLUTION=2x1"#) == "2x1")
        #expect(HLSPlaylist.attribute("AUDIO", in: "#EXT-X-STREAM-INF:BANDWIDTH=1") == nil)
    }

    // MARK: Site rules

    @Test func oneRuleCoversReddit() {
        #expect(EmbedProvider.provider(forHost: "v.redd.it") == .reddit)
        #expect(EmbedProvider.provider(forHost: "i.redd.it") == .reddit)
        #expect(EmbedProvider.provider(forHost: "old.reddit.com") == .reddit)
        #expect(EmbedProvider.provider(forHost: "b.thumbs.redditmedia.com") == .reddit)
        #expect(SiteRules.suggestedRuleDomain(for: url("https://v.redd.it/1crlzghxl82i1")) == "reddit.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://i.redd.it/abc.jpg")) == "reddit.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://redd.it/1xyw5ml")) == "reddit.com")

        let blocked = MediaPolicy(siteRules: SiteRules(["reddit.com": "block"]))
        for host in ["v.redd.it", "i.redd.it", "preview.redd.it", "redd.it", "www.reddit.com", "a.thumbs.redditmedia.com"] {
            #expect(blocked.verdict(for: url("https://\(host)/x")).block == SiteBlock(reason: .userBlocked, domain: "reddit.com"))
        }
        // A rule of its own for the image host wins.
        let images = MediaPolicy(siteRules: SiteRules(["reddit.com": "block", "i.redd.it": "allow"]))
        #expect(images.verdict(for: url("https://i.redd.it/abc.jpg")) == .everything)
    }
}

/// Reddit through `LinkPreviewService`, against a stub server.
@Suite struct RedditPreviewTests {
    let server = StubServer()
    let policy = MediaPolicy()

    private func url(_ string: String) -> URL { URL(string: string)! }

    private func makeService(cache: (any LinkPreviewCache)? = nil) -> LinkPreviewService {
        LinkPreviewService(session: server.makeSession(), cache: cache)
    }

    private let video = "https://v.redd.it/1crlzghxl82i1"
    private let post = "https://www.reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard/"

    private var oEmbed: String { OEmbedEndpoint.reddit(post: url(post))!.absoluteString }

    private func routeVideo(playlist: String = "reddit-hls.m3u8", oEmbedResponse: StubResponse? = nil) throws {
        server.route(video, .redirect(to: "https://www.reddit.com/video/1crlzghxl82i1", status: 302))
        server.route("https://www.reddit.com/video/1crlzghxl82i1", .redirect(to: post, status: 301))
        server.route(post, .html(try Fixtures.string("reddit-challenge.html")))
        server.route(oEmbed, try oEmbedResponse ?? StubResponse(
            headers: ["Content-Type": "application/json"], body: Data(Fixtures.string("reddit-oembed.json").utf8)
        ))
        server.route(
            "https://v.redd.it/1crlzghxl82i1/HLSPlaylist.m3u8",
            .data(Data(try Fixtures.string(playlist).utf8), contentType: "application/x-mpegurl")
        )
    }

    @Test func videoGetsItsPostsTitleSubredditAndAuthor() async throws {
        try routeVideo()
        let cache = MemoryPreviewCache()
        let preview = try await makeService(cache: cache).preview(for: url(video), policy: policy)

        #expect(preview.kind == .embed)
        #expect(preview.url == url(video))
        #expect(preview.finalURL == url(post))
        #expect(preview.title == "Jet powered skateboard")
        #expect(preview.siteName == "Reddit")
        #expect(preview.summary == "r/LoveTrash · u/downtune79")
        #expect(preview.imageURL == nil)
        #expect(preview.declaresAdult == nil)
        let embed = try #require(preview.embed)
        #expect(embed.provider == .reddit)
        #expect(embed.title == "Jet powered skateboard")
        #expect(embed.authorName == "u/downtune79")
        #expect(embed.community == "r/LoveTrash")
        #expect(embed.isGIF == false)
        #expect(abs(embed.aspectRatio - 854.0 / 480.0) < 0.001)
        // No thumbnail and no frame: nothing of the video shows before a click.
        #expect(embed.thumbnailURL == nil)
        #expect(await cache.storeCount == 1)

        // The post page itself is only passed through on the way (its body is skipped).
        let request = try #require(server.requests(to: oEmbed).first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == LinkPreviewService.defaultUserAgent)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(server.requests.allSatisfy { ["v.redd.it", "www.reddit.com"].contains($0.url?.host() ?? "") })
    }

    @Test func silentVideoIsAGIF() async throws {
        try routeVideo(playlist: "reddit-hls-gif.m3u8")
        let preview = try await makeService().preview(for: url(video), policy: policy)
        #expect(preview.embed?.isGIF == true)
        #expect(abs((preview.embed?.aspectRatio ?? 0) - 360.0 / 640.0) < 0.001)
    }

    @Test func rateLimitedOEmbedFallsBackToTheAddressAndIsRetriedLater() async throws {
        try routeVideo(oEmbedResponse: .status(429))
        let cache = MemoryPreviewCache()
        let preview = try await makeService(cache: cache).preview(for: url(video), policy: policy)
        #expect(preview.kind == .embed)
        #expect(preview.title == "Jet powered skateboard")   // from the post's address
        #expect(preview.embed?.authorName == nil)
        #expect(preview.embed?.community == "r/LoveTrash")
        // Not kept on disk, so the next launch asks again.
        #expect(await cache.storeCount == 0)
    }

    @Test func ageCheckMarksTheVideoAdult() async throws {
        let gate = "https://www.reddit.com/over18?dest=https%3A%2F%2Fwww.reddit.com%2Fr%2Fx%2Fcomments%2Fabc123%2Fy%2F"
        server.route(video, .redirect(to: gate, status: 302))
        server.route(gate, .html("<html><head><title>Reddit</title></head></html>"))
        let preview = try await makeService().preview(for: url(video), policy: policy)
        #expect(preview.declaresAdult == true)
        let decision = PreviewDecider.decide(
            url: url(video), classification: MediaClassifier.classify(url(video)), preview: preview,
            context: PreviewContext(policy: policy)
        )
        #expect(decision.plan == .blocked(SiteBlock(reason: .adultPage, domain: "reddit.com")))
    }

    @Test func postLinkIsACardFromOEmbedWithoutLoadingThePage() async throws {
        try routeVideo()
        let link = "https://old.reddit.com/r/LoveTrash/comments/1xyw5ml/jet_powered_skateboard/"
        let preview = try await makeService().preview(for: url(link), policy: policy)
        #expect(preview.kind == .page)
        #expect(preview.title == "Jet powered skateboard")
        #expect(preview.summary == "r/LoveTrash · Posted by u/downtune79")
        #expect(preview.siteName == "Reddit")
        #expect(preview.imageURL == nil)
        #expect(preview.faviconURL == RedditLinks.faviconURL)
        #expect(server.requests(to: link).isEmpty)
        #expect(server.requests(to: post).isEmpty)
        #expect(server.requests(to: oEmbed).count == 1)
    }

    @Test func shortLinkFollowsItsRedirectToThePost() async throws {
        try routeVideo()
        server.route("https://redd.it/1xyw5ml", .redirect(to: post, status: 301))
        let preview = try await makeService().preview(for: url("https://redd.it/1xyw5ml"), policy: policy)
        #expect(preview.kind == .page)
        #expect(preview.finalURL == url(post))
        #expect(preview.title == "Jet powered skateboard")
    }

    @Test func blockedRedditIsNeverContacted() async {
        let blocked = MediaPolicy(siteRules: SiteRules(["reddit.com": "block"]))
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .userBlocked, domain: "reddit.com"))) {
            try await makeService().preview(for: url(video), policy: blocked)
        }
        #expect(server.requests.isEmpty)
    }

    @Test func decisions() {
        let link = url(video)
        func decide(_ policy: MediaPolicy = MediaPolicy(), layout: PreviewLayout = PreviewLayout(), blur: Bool = false) -> PreviewDecision {
            PreviewDecider.decide(
                url: link, classification: MediaClassifier.classify(link),
                context: PreviewContext(policy: policy, layout: layout, blurImages: blur)
            )
        }
        #expect(decide().plan == .videoEmbed(.player))
        #expect(decide().shouldFetch)
        #expect(decide(layout: PreviewLayout(videoStyle: .compact)).plan == .videoEmbed(.compact))
        #expect(decide(layout: PreviewLayout(videoStyle: .off)).plan == .pending)
        #expect(decide(MediaPolicy(autoLoad: false)).plan == .loadChip(.videoEmbed(.reddit)))
        #expect(decide(blur: true).blurred)
        // Text only: a card with the post's title, no player.
        #expect(decide(MediaPolicy(siteRules: SiteRules(["reddit.com": "textOnly"]))).plan == .pending)
    }
}
