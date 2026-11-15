// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

@Suite struct MediaClassifierTests {
    private func classify(_ string: String) -> MediaClassification {
        MediaClassifier.classify(URL(string: string)!)
    }

    private func embed(_ string: String) -> EmbedInfo? {
        if case .embed(let info) = classify(string) { return info }
        return nil
    }

    // MARK: YouTube

    struct YouTubeCase: Sendable, CustomTestStringConvertible {
        var url: String
        var id: String
        var start: Int?
        var isShort = false
        var testDescription: String { url }
    }

    @Test(arguments: [
        YouTubeCase(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", id: "dQw4w9WgXcQ"),
        YouTubeCase(url: "https://youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&index=2", id: "dQw4w9WgXcQ"),
        YouTubeCase(url: "https://www.youtube.com/watch?feature=share&v=dQw4w9WgXcQ", id: "dQw4w9WgXcQ"),
        YouTubeCase(url: "https://m.youtube.com/watch?v=dQw4w9WgXcQ", id: "dQw4w9WgXcQ"),
        YouTubeCase(url: "https://music.youtube.com/watch?v=dQw4w9WgXcQ&si=abc", id: "dQw4w9WgXcQ"),
        YouTubeCase(url: "https://youtu.be/dQw4w9WgXcQ", id: "dQw4w9WgXcQ"),
        YouTubeCase(url: "https://youtu.be/dQw4w9WgXcQ?si=xyz", id: "dQw4w9WgXcQ"),
        YouTubeCase(url: "https://youtu.be/dQw4w9WgXcQ?t=90", id: "dQw4w9WgXcQ", start: 90),
        YouTubeCase(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s", id: "dQw4w9WgXcQ", start: 90),
        YouTubeCase(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90s", id: "dQw4w9WgXcQ", start: 90),
        YouTubeCase(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1h2m3s", id: "dQw4w9WgXcQ", start: 3723),
        YouTubeCase(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ#t=45", id: "dQw4w9WgXcQ", start: 45),
        YouTubeCase(url: "https://www.youtube.com/embed/dQw4w9WgXcQ?start=30", id: "dQw4w9WgXcQ", start: 30),
        YouTubeCase(url: "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", id: "dQw4w9WgXcQ"),
        YouTubeCase(url: "https://www.youtube.com/shorts/abcdefghijk", id: "abcdefghijk", isShort: true),
        YouTubeCase(url: "https://youtube.com/shorts/abcdefghijk?feature=share", id: "abcdefghijk", isShort: true),
        YouTubeCase(url: "https://www.youtube.com/live/a1b2c3d4e5F?si=x", id: "a1b2c3d4e5F"),
        YouTubeCase(url: "https://www.youtube.com/v/dQw4w9WgXcQ", id: "dQw4w9WgXcQ"),
        YouTubeCase(url: "https://www.youtube.com/watch?v=-_-_-_-_-_-", id: "-_-_-_-_-_-"),
        YouTubeCase(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=0", id: "dQw4w9WgXcQ"),
    ])
    func youtube(_ testCase: YouTubeCase) throws {
        let info = try #require(embed(testCase.url))
        #expect(info.provider == .youtube)
        #expect(info.videoID == testCase.id)
        #expect(info.startSeconds == testCase.start)
        #expect(info.thumbnailURL == URL(string: "https://i.ytimg.com/vi/\(testCase.id)/hqdefault.jpg"))
        #expect(info.embedURL.host() == "www.youtube-nocookie.com")
        #expect(info.embedURL.path() == "/embed/\(testCase.id)")
        let query = URLComponents(url: info.embedURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "autoplay", value: "1")))
        #expect(query.contains(URLQueryItem(name: "playsinline", value: "1")))
        #expect(query.contains(URLQueryItem(name: "rel", value: "0")))
        #expect(query.first { $0.name == "start" }?.value == testCase.start.map(String.init))
        if testCase.isShort {
            #expect(info.aspectRatio < 1)
        } else {
            #expect(abs(info.aspectRatio - 16.0 / 9.0) < 0.001)
        }
    }

    @Test func youtubeEmbedURLFormat() throws {
        let info = try #require(embed("https://youtu.be/dQw4w9WgXcQ?t=1m30s"))
        #expect(info.embedURL.absoluteString
            == "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=90&autoplay=1&playsinline=1&rel=0")
    }

    @Test(arguments: [
        "https://www.youtube.com/",
        "https://www.youtube.com/watch",
        "https://www.youtube.com/watch?v=short",
        "https://www.youtube.com/watch?v=waytoolongvideoid",
        "https://www.youtube.com/@SomeChannel",
        "https://www.youtube.com/channel/UC1234567890",
        "https://www.youtube.com/playlist?list=PL123",
        "https://youtu.be/",
        "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
    ])
    func youtubeNonVideoPagesArePages(_ url: String) {
        #expect(classify(url) == .page(URL(string: url)!))
    }

    // MARK: Vimeo

    @Test(arguments: [
        ("https://vimeo.com/76979871", "76979871", nil as Int?, nil as String?),
        ("https://www.vimeo.com/76979871", "76979871", nil, nil),
        ("https://vimeo.com/76979871#t=1m5s", "76979871", 65, nil),
        ("https://vimeo.com/76979871/abc123def0", "76979871", nil, "abc123def0"),
        ("https://vimeo.com/channels/staffpicks/76979871", "76979871", nil, nil),
        ("https://vimeo.com/groups/shortfilms/videos/76979871", "76979871", nil, nil),
        ("https://player.vimeo.com/video/76979871", "76979871", nil, nil),
        ("https://player.vimeo.com/video/76979871?h=abc123def0", "76979871", nil, "abc123def0"),
    ])
    func vimeo(url: String, id: String, start: Int?, hash: String?) throws {
        let info = try #require(embed(url))
        #expect(info.provider == .vimeo)
        #expect(info.videoID == id)
        #expect(info.startSeconds == start)
        #expect(info.embedURL.host() == "player.vimeo.com")
        #expect(info.embedURL.path() == "/video/\(id)")
        let h = URLComponents(url: info.embedURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "h" }
        #expect(h?.value == hash)
        if let start { #expect(info.embedURL.fragment() == "t=\(start)s") }
    }

    @Test(arguments: [
        "https://vimeo.com/",
        "https://vimeo.com/user12345",
        "https://vimeo.com/about",
        "https://player.vimeo.com/api/player.js",
    ])
    func vimeoNonVideoPages(_ url: String) {
        #expect(classify(url) == .page(URL(string: url)!))
    }

    // MARK: Twitch

    @Test func twitchClips() throws {
        for url in [
            "https://clips.twitch.tv/AwkwardHelplessSalamanderSwiftRage",
            "https://www.twitch.tv/somestreamer/clip/AwkwardHelplessSalamanderSwiftRage",
            "https://m.twitch.tv/somestreamer/clip/AwkwardHelplessSalamanderSwiftRage?filter=clips",
            "https://clips.twitch.tv/embed?clip=AwkwardHelplessSalamanderSwiftRage&parent=example.com",
        ] {
            let info = try #require(embed(url), "\(url)")
            #expect(info.provider == .twitch)
            #expect(info.videoID == "AwkwardHelplessSalamanderSwiftRage")
            #expect(info.embedURL.absoluteString
                == "https://clips.twitch.tv/embed?clip=AwkwardHelplessSalamanderSwiftRage&parent=r3volution11.github.io")
        }
        let modern = try #require(embed("https://clips.twitch.tv/FunnyClip-a1B2c3_D4"))
        #expect(modern.videoID == "FunnyClip-a1B2c3_D4")
    }

    @Test func twitchVideos() throws {
        let plain = try #require(embed("https://www.twitch.tv/videos/1234567890"))
        #expect(plain.provider == .twitch)
        #expect(plain.videoID == "1234567890")
        #expect(plain.startSeconds == nil)
        #expect(plain.embedURL.absoluteString
            == "https://player.twitch.tv/?video=1234567890&parent=r3volution11.github.io")

        let timed = try #require(embed("https://twitch.tv/videos/1234567890?t=1h2m3s"))
        #expect(timed.startSeconds == 3723)
        #expect(timed.embedURL.absoluteString.hasSuffix("&time=1h2m3s"))
    }

    @Test(arguments: [
        "https://www.twitch.tv/somestreamer",
        "https://www.twitch.tv/directory/game/Chess",
        "https://www.twitch.tv/videos/notanumber",
        "https://clips.twitch.tv/",
    ])
    func twitchOtherPages(_ url: String) {
        #expect(classify(url) == .page(URL(string: url)!))
    }

    // MARK: Streamable

    @Test(arguments: [
        ("https://streamable.com/moo5x", "moo5x"),
        ("https://www.streamable.com/abc123", "abc123"),
        ("https://streamable.com/e/abc123", "abc123"),
        ("https://streamable.com/o/abc123", "abc123"),
    ])
    func streamable(url: String, id: String) throws {
        let info = try #require(embed(url))
        #expect(info.provider == .streamable)
        #expect(info.videoID == id)
        #expect(info.embedURL.absoluteString == "https://streamable.com/e/\(id)")
    }

    @Test(arguments: ["https://streamable.com/", "https://streamable.com/login", "https://streamable.com/documentation"])
    func streamableSitePages(_ url: String) {
        #expect(classify(url) == .page(URL(string: url)!))
    }

    // MARK: Direct media

    @Test(arguments: [
        "https://example.com/cat.png", "https://example.com/a/b/photo.JPG", "https://example.com/x.jpeg?w=100",
        "https://example.com/anim.gif", "https://example.com/pic.webp", "https://example.com/p.heic",
        "https://example.com/p.heif", "https://example.com/p.avif", "https://example.com/p.bmp",
        "https://example.com/scan.tiff", "http://example.com/i.png#frag", "https://i.imgur.com/abc123.gif",
    ])
    func directImages(_ url: String) {
        #expect(classify(url) == .image(URL(string: url)!))
    }

    @Test(arguments: ["https://example.com/clip.mp4", "https://example.com/clip.MOV", "https://example.com/c.m4v?x=1"])
    func directVideos(_ url: String) {
        #expect(classify(url) == .video(URL(string: url)!))
    }

    @Test(arguments: [
        "https://example.com/", "https://example.com/article", "https://example.com/page.html",
        "https://example.com/png", "https://example.com/file.pdf", "https://imgur.com/abc123",
        "https://imgur.com/a/xyz", "https://github.com/apple/swift", "ftp://example.com/cat.png",
    ])
    func pages(_ url: String) {
        #expect(classify(url) == .page(URL(string: url)!))
    }

    // MARK: Rewrites

    @Test func imgurGifvBecomesMP4() {
        #expect(classify("https://i.imgur.com/AbCd123.gifv") == .video(URL(string: "https://i.imgur.com/AbCd123.mp4")!))
    }

    @Test func githubBlobImagesBecomeRaw() {
        #expect(classify("https://github.com/owner/repo/blob/main/docs/screenshot.png")
            == .image(URL(string: "https://raw.githubusercontent.com/owner/repo/main/docs/screenshot.png")!))
        #expect(classify("https://github.com/owner/repo/blob/feature/x/assets/demo.gif?raw=true")
            == .image(URL(string: "https://raw.githubusercontent.com/owner/repo/feature/x/assets/demo.gif")!))
        #expect(classify("https://github.com/owner/repo/blob/main/demo.mp4")
            == .video(URL(string: "https://raw.githubusercontent.com/owner/repo/main/demo.mp4")!))
        // Non-image blobs stay pages.
        #expect(classify("https://github.com/owner/repo/blob/main/README.md")
            == .page(URL(string: "https://github.com/owner/repo/blob/main/README.md")!))
    }

    // MARK: Timestamps

    @Test(arguments: [
        ("90", 90 as Int?), ("90s", 90), ("1m30s", 90), ("1m", 60), ("2h", 7200), ("1h2m3s", 3723),
        ("1m30", 90), ("1:30", 90), ("01:02:03", 3723), ("0", nil), ("", nil), ("abc", nil),
        ("1x", nil), ("-5", nil),
    ])
    func timestamps(raw: String, expected: Int?) {
        #expect(TimestampParser.seconds(from: raw) == expected)
    }
}
