// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import Testing
@testable import VelaMedia

@Suite struct GIFLinkTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private func gif(_ string: String) -> GIFInfo? {
        if case .gif(let info) = MediaClassifier.classify(url(string)) { return info }
        return nil
    }

    // MARK: Tenor

    @Test(arguments: [
        "https://tenor.com/view/karate-kid-body-bag-the-karate-kid-sarcastic-laugh-gif-10249931",
        "https://www.tenor.com/view/karate-kid-body-bag-the-karate-kid-sarcastic-laugh-gif-10249931",
        "https://tenor.com/de/view/karate-kid-body-bag-the-karate-kid-sarcastic-laugh-gif-10249931",
        "https://tenor.com/view/cat-gif-123?utm_source=share",
        "https://tenor.com/RaDD.gif",
        "https://tenor.com/bQx9a.gif",
    ])
    func tenorPagesNeedTheirPage(_ link: String) throws {
        let info = try #require(gif(link))
        #expect(info.provider == .tenor)
        #expect(!info.isResolved)
        #expect(info.videoURL == nil && info.imageURL == nil)
        #expect(!info.isSticker)
    }

    @Test func tenorStickerPagesAreMarked() throws {
        #expect(try #require(gif("https://tenor.com/view/brick-cat-sticker-27149281")).isSticker)
    }

    @Test(arguments: [
        "https://tenor.com/", "https://tenor.com/search/cat-gifs", "https://tenor.com/view/",
        "https://tenor.com/view/no-id-here", "https://tenor.com/gif-maker", "https://tenor.com/a/b/view/x-1",
        "https://media.tenor.com/images/0123456789abcdef0123456789abcdef/tenor.gif",
        "https://media.tenor.com/WAeOn7-AdfgAAAAN/karate-kid-body-bag.png",
    ])
    func otherTenorLinksAreNotGIFs(_ link: String) {
        #expect(gif(link) == nil)
    }

    @Test(arguments: [
        ("https://media.tenor.com/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif", "https://media.tenor.com/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif"),
        ("https://media1.tenor.com/m/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif", "https://media1.tenor.com/m/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif"),
        ("https://c.tenor.com/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif", "https://c.tenor.com/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif"),
        ("https://media.tenor.com/WAeOn7-AdfgAAAAM/karate-kid-body-bag.gif", "https://media.tenor.com/WAeOn7-AdfgAAAAM/karate-kid-body-bag.gif"),
        ("https://media.tenor.com/WAeOn7-AdfgAAAA1/karate-kid-body-bag.webp", "https://media.tenor.com/WAeOn7-AdfgAAAA1/karate-kid-body-bag.webp"),
        // A link to a video falls back to Tenor's medium GIF.
        ("https://media.tenor.com/WAeOn7-AdfgAAAPo/karate-kid-body-bag.mp4", "https://media.tenor.com/WAeOn7-AdfgAAAAd/karate-kid-body-bag.gif"),
        ("https://media.tenor.com/WAeOn7-AdfgAAAP1/karate-kid-body-bag.mp4", "https://media.tenor.com/WAeOn7-AdfgAAAAd/karate-kid-body-bag.gif"),
    ])
    func tenorFilesPlayTheirMP4(_ link: String, fallback: String) throws {
        let info = try #require(gif(link))
        #expect(info.provider == .tenor)
        #expect(info.videoURL == url("https://media.tenor.com/WAeOn7-AdfgAAAPo/karate-kid-body-bag.mp4"))
        #expect(info.imageURL == url(fallback))
        #expect(info.primaryURL == info.videoURL)
    }

    @Test func tenorStickerFilesKeepTheirTransparentWebP() throws {
        let link = "https://media.tenor.com/3w0Our6WmXUAAAAm/brick-cat.webp"
        let info = try #require(gif(link))
        #expect(info.videoURL == nil)
        #expect(info.imageURL == url(link))
        #expect(info.isSticker)
    }

    @Test func tenorFileNamesAreReEncoded() throws {
        let info = try #require(gif("https://media.tenor.com/BCQJFkjyNYwAAAAM/%D1%85%D0%B0%D0%BF%D0%BF%D0%B8-happy-cat.gif"))
        #expect(info.videoURL?.absoluteString
            == "https://media.tenor.com/BCQJFkjyNYwAAAPo/%D1%85%D0%B0%D0%BF%D0%BF%D0%B8-happy-cat.mp4")
    }

    // MARK: GIPHY

    @Test(arguments: [
        "https://giphy.com/gifs/cat-funny-JIX9t2j0ZTN9S",
        "https://www.giphy.com/gifs/cat-funny-JIX9t2j0ZTN9S",
        "https://giphy.com/gifs/JIX9t2j0ZTN9S",
        "https://giphy.com/gifs/JIX9t2j0ZTN9S/fullscreen",
        "https://giphy.com/embed/JIX9t2j0ZTN9S",
        "https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.gif",
        "https://media0.giphy.com/media/JIX9t2j0ZTN9S/200w.gif?cid=abc",
        "https://media3.giphy.com/media/v1.Y2lkPTc5MGI3NjEx/JIX9t2j0ZTN9S/giphy.webp",
        "https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.mp4",
        "https://i.giphy.com/JIX9t2j0ZTN9S.gif",
        "https://i.giphy.com/JIX9t2j0ZTN9S.webp",
        "https://i.giphy.com/media/JIX9t2j0ZTN9S/giphy.gif",
    ])
    func giphyLinksNameTheirGIF(_ link: String) throws {
        let info = try #require(gif(link))
        #expect(info.provider == .giphy)
        #expect(info.videoURL == url("https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.mp4"))
        #expect(info.imageURL == url("https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.webp"))
    }

    @Test func giphyStickersPlayTheirWebP() throws {
        let info = try #require(gif("https://giphy.com/stickers/hello-wave-l0MYt5jPR6QX5pnqM"))
        #expect(info.videoURL == nil)
        #expect(info.imageURL == url("https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.webp"))
        #expect(info.isSticker)
    }

    @Test(arguments: ["https://gph.is/16sUz2u", "https://gph.is/g/46vwxjM", "http://gph.is/2cPVZfL"])
    func giphyShortLinksNeedTheirPage(_ link: String) throws {
        let info = try #require(gif(link))
        #expect(info.provider == .giphy)
        #expect(!info.isResolved)
    }

    @Test(arguments: [
        "https://giphy.com/", "https://giphy.com/gifs", "https://giphy.com/explore/cats",
        "https://giphy.com/gifs/funny-cats", "https://giphy.com/clips/cat-funny-JIX9t2j0ZTN9S",
        "https://giphy.com/channel/giphy", "https://gph.is/", "https://media.giphy.com/headers/x.gif",
    ])
    func otherGiphyLinksAreNotGIFs(_ link: String) {
        #expect(gif(link) == nil)
    }

    @Test func giphyIDsComeFromTheEndOfTheSlug() {
        #expect(GIFLinks.giphyID(fromSlug: "nfl-draft-nfl-2020-W0Jhy2gEBx4mQIf6Vh") == "W0Jhy2gEBx4mQIf6Vh")
        #expect(GIFLinks.giphyID(fromSlug: "error-TqiwHbFBaZ4ti") == "TqiwHbFBaZ4ti")
        #expect(GIFLinks.giphyID(fromSlug: "3osxY9kuM2NGUfvThe") == "3osxY9kuM2NGUfvThe")
        // Slug words, too short or with no capital or digit, aren't IDs.
        #expect(GIFLinks.giphyID(fromSlug: "funny-compilation") == nil)
        #expect(GIFLinks.giphyID(fromSlug: "cat-Ab1") == nil)
        #expect(GIFLinks.giphyID(fromSlug: "cat-ab_cd-EF12gh") == nil)
    }

    // MARK: Imgur

    @Test(arguments: [
        "https://i.imgur.com/AbCd123.gifv", "https://imgur.com/AbCd123.gifv", "https://i.imgur.com/AbCd123.GIFV?x=1",
    ])
    func imgurGifvPlaysItsMP4(_ link: String) throws {
        let info = try #require(gif(link))
        #expect(info.provider == .imgur)
        #expect(info.videoURL == url("https://i.imgur.com/AbCd123.mp4"))
        #expect(info.imageURL == nil)
    }

    @Test func otherImgurLinksAreUnchanged() {
        #expect(MediaClassifier.classify(url("https://i.imgur.com/AbCd123.gif")) == .image(url("https://i.imgur.com/AbCd123.gif")))
        #expect(MediaClassifier.classify(url("https://i.imgur.com/AbCd123.mp4")) == .video(url("https://i.imgur.com/AbCd123.mp4")))
        #expect(MediaClassifier.classify(url("https://imgur.com/gallery/AbCd123")) == .page(url("https://imgur.com/gallery/AbCd123")))
    }

    @Test func otherGIFsStayImages() {
        let earth = url("https://upload.wikimedia.org/wikipedia/commons/thumb/e/e1/Rotating_earth_animated.gif/250px-Rotating_earth_animated.gif")
        #expect(MediaClassifier.classify(earth) == .image(earth))
    }

    // MARK: Resolving pages

    private func metadata(_ fixture: String, base: String) throws -> HTMLMetadata {
        HTMLMetadataParser.parse(html: try Fixtures.string(fixture), baseURL: url(base))
    }

    @Test func tenorPageMetadata() throws {
        let meta = try metadata("tenor-view.html", base: "https://tenor.com/view/karate-kid-gif-10249931")
        // The first og:video, with its own type and size; not the one in the
        // script, nor the one in <body>.
        #expect(meta.videoURL == url("https://media.tenor.com/WAeOn7-AdfgAAAPo/karate-kid-body-bag.mp4"))
        #expect(meta.videoType == "video/mp4")
        #expect(meta.videoWidth == 490)
        #expect(meta.videoHeight == 270)
        #expect(meta.imageURL == url("https://media1.tenor.com/m/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif"))
        #expect(meta.siteName == "Tenor")
    }

    @Test func tenorPageResolvesToItsMP4() throws {
        let meta = try metadata("tenor-view.html", base: "https://tenor.com/view/karate-kid-gif-10249931")
        let info = try #require(GIFResolver.resolve(meta, provider: .tenor, isSticker: false))
        #expect(info.videoURL == url("https://media.tenor.com/WAeOn7-AdfgAAAPo/karate-kid-body-bag.mp4"))
        // Tenor's medium GIF (a fraction of the page's full-size one) is the fallback.
        #expect(info.imageURL == url("https://media.tenor.com/WAeOn7-AdfgAAAAd/karate-kid-body-bag.gif"))
        #expect(info.pixelSize == CGSize(width: 490, height: 270))
        #expect(info.title == "Karate Kid Body Bag GIF - Karate Kid Body Bag The Karate Kid - Discover & Share GIFs")
    }

    @Test func giphyPageResolvesToItsMP4() throws {
        let meta = try metadata("giphy-gif.html", base: "https://giphy.com/gifs/JIX9t2j0ZTN9S")
        let info = try #require(GIFResolver.resolve(meta, provider: .giphy, isSticker: false))
        #expect(info.videoURL == url("https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.mp4"))
        #expect(info.imageURL == url("https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.webp"))
        #expect(info.pixelSize == CGSize(width: 480, height: 480))
        #expect(info.title == "Cat Working GIF - Find & Share on GIPHY")
    }

    @Test func stickerPagesResolveToTheirImage() throws {
        let meta = try metadata("tenor-sticker.html", base: "https://tenor.com/view/brick-cat-sticker-27149281")
        let info = try #require(GIFResolver.resolve(meta, provider: .tenor, isSticker: true))
        #expect(info.videoURL == nil)
        #expect(info.imageURL == url("https://media.tenor.com/3w0Our6WmXUAAAAm/brick-cat.webp"))
        #expect(info.pixelSize == CGSize(width: 220, height: 220))
        // Not marked as a sticker, the same page plays its MP4.
        #expect(GIFResolver.resolve(meta, provider: .tenor, isSticker: false)?.videoURL
            == url("https://media.tenor.com/3w0Our6WmXUAAAPo/brick-cat.mp4"))
    }

    @Test func variantChoice() {
        func resolve(video: String?, type: String? = nil, image: String?) -> GIFInfo? {
            GIFResolver.resolve(
                HTMLMetadata(
                    title: "T", imageURL: image.map(url), videoURL: video.map(url), videoType: type,
                    videoWidth: 320, videoHeight: 240, imageWidth: 640, imageHeight: 480
                ),
                provider: .tenor, isSticker: false
            )
        }
        // An MP4 wins over the GIF, and its size is used.
        let both = resolve(video: "https://cdn.example.com/a.mp4", image: "https://cdn.example.com/a.gif")
        #expect(both?.videoURL == url("https://cdn.example.com/a.mp4"))
        #expect(both?.imageURL == url("https://cdn.example.com/a.gif"))
        #expect(both?.pixelSize == CGSize(width: 320, height: 240))
        // A typed MP4 without the extension counts; a WebM doesn't.
        #expect(resolve(video: "https://cdn.example.com/stream?id=1", type: "video/mp4", image: nil)?.videoURL != nil)
        let webm = resolve(video: "https://cdn.example.com/a.webm", type: "video/webm", image: "https://cdn.example.com/a.webp")
        #expect(webm?.videoURL == nil)
        #expect(webm?.imageURL == url("https://cdn.example.com/a.webp"))
        #expect(webm?.pixelSize == CGSize(width: 640, height: 480))
        // A still image is no animation.
        #expect(resolve(video: nil, image: "https://cdn.example.com/a.png") == nil)
        #expect(resolve(video: nil, image: nil) == nil)
    }

    // MARK: Info

    @Test func infoHelpers() {
        let info = GIFInfo(
            provider: .giphy, videoURL: url("https://media.giphy.com/media/x/giphy.mp4"),
            imageURL: url("https://media.giphy.com/media/x/giphy.webp"), width: 0, height: 10
        )
        #expect(info.isResolved)
        #expect(info.primaryURL == url("https://media.giphy.com/media/x/giphy.mp4"))
        #expect(info.mediaURLs.count == 2)
        #expect(info.pixelSize == nil)
        #expect(!GIFInfo(provider: .tenor).isResolved)
        #expect(GIFInfo(provider: .tenor, imageURL: url("https://x.example/a.gif")).primaryURL == url("https://x.example/a.gif"))
        #expect(GIFProvider.allCases.map(\.displayName) == ["Tenor", "GIPHY", "Imgur"])
    }

    @Test func infoRoundTripsWithoutTheStickerHint() throws {
        let info = GIFInfo(provider: .tenor, imageURL: url("https://media.tenor.com/a.webp"), width: 2, height: 3, title: "T", isSticker: true)
        let decoded = try JSONDecoder().decode(GIFInfo.self, from: JSONEncoder().encode(info))
        #expect(decoded.imageURL == info.imageURL)
        #expect(decoded.pixelSize == CGSize(width: 2, height: 3))
        #expect(decoded.title == "T")
        #expect(!decoded.isSticker)
    }

    // MARK: Site rules

    @Test func gifSitesFollowTheirMainDomain() {
        #expect(SiteRules.suggestedRuleDomain(for: url("https://media.tenor.com/WAeOn7-AdfgAAAAC/a.gif")) == "tenor.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://media1.tenor.com/m/WAeOn7-AdfgAAAAC/a.gif")) == "tenor.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://gph.is/g/46vwxjM")) == "giphy.com")
        #expect(SiteRules.suggestedRuleDomain(for: url("https://i.giphy.com/JIX9t2j0ZTN9S.gif")) == "giphy.com")
        // Imgur's image host keeps rules of its own.
        #expect(SiteRules.suggestedRuleDomain(for: url("https://i.imgur.com/AbCd123.gifv")) == "i.imgur.com")

        let policy = MediaPolicy(siteRules: SiteRules(["giphy.com": "block", "tenor.com": "textOnly"]))
        #expect(policy.verdict(for: url("https://gph.is/g/46vwxjM")).block?.reason == .userBlocked)
        #expect(policy.verdict(for: url("https://media.giphy.com/media/x/giphy.mp4")).block?.domain == "giphy.com")
        #expect(policy.verdict(for: url("https://media.tenor.com/x/a.mp4")) == .textOnly)
        // A rule of its own wins.
        let own = MediaPolicy(siteRules: SiteRules(["giphy.com": "block", "gph.is": "allow"]))
        #expect(own.verdict(for: url("https://gph.is/g/46vwxjM")) == .everything)
    }
}
