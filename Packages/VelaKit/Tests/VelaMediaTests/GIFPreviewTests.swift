// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import VelaMedia

/// Resolving GIF links through `LinkPreviewService`, against a stub server.
@Suite struct GIFPreviewTests {
    let server = StubServer()
    let policy = MediaPolicy()

    private func makeService() -> LinkPreviewService {
        LinkPreviewService(session: server.makeSession())
    }

    private func url(_ string: String) -> URL { URL(string: string)! }

    private let tenorPage = "https://tenor.com/view/karate-kid-body-bag-the-karate-kid-sarcastic-laugh-gif-10249931"

    @Test func tenorShortLinkFollowsItsRedirectToThePage() async throws {
        server.route("https://tenor.com/RaDD.gif", .redirect(to: tenorPage, status: 301))
        server.route(tenorPage, .html(try Fixtures.string("tenor-view.html")))
        let preview = try await makeService().preview(for: url("https://tenor.com/RaDD.gif"), policy: policy)

        #expect(preview.kind == .gif)
        #expect(preview.url == url("https://tenor.com/RaDD.gif"))
        #expect(preview.finalURL == url(tenorPage))
        #expect(preview.siteName == "Tenor")
        #expect(preview.title?.hasPrefix("Karate Kid Body Bag GIF") == true)
        let gif = try #require(preview.gif)
        #expect(gif.provider == .tenor)
        #expect(gif.videoURL == url("https://media.tenor.com/WAeOn7-AdfgAAAPo/karate-kid-body-bag.mp4"))
        #expect(gif.imageURL == url("https://media.tenor.com/WAeOn7-AdfgAAAAd/karate-kid-body-bag.gif"))
        #expect(gif.pixelSize == CGSize(width: 490, height: 270))
        #expect(preview.mediaURL == gif.videoURL)
        #expect(preview.declaresAdult == false)
        // Only the page: the animation loads when it's drawn, through the policy.
        #expect(server.requests.allSatisfy { $0.url?.host() == "tenor.com" })
        let request = try #require(server.requests(to: tenorPage).first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == LinkPreviewService.defaultUserAgent)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func giphyShortLinkIsResolvedFromWhereItLeads() async throws {
        let landing = "https://giphy.com/gifs/nfl-draft-nfl-2020-W0Jhy2gEBx4mQIf6Vh"
        server.route("https://gph.is/g/46vwxjM", .redirect(to: landing, status: 301))
        // GIPHY answers slug links with a page that only redirects.
        server.route(landing, .html(#"<head><meta http-equiv="refresh" content="0;url=https://giphy.com/gifs/W0Jhy2gEBx4mQIf6Vh"/></head>"#))
        let preview = try await makeService().preview(for: url("https://gph.is/g/46vwxjM"), policy: policy)

        #expect(preview.kind == .gif)
        #expect(preview.finalURL == url(landing))
        #expect(preview.gif?.videoURL == url("https://media.giphy.com/media/W0Jhy2gEBx4mQIf6Vh/giphy.mp4"))
        #expect(preview.gif?.imageURL == url("https://media.giphy.com/media/W0Jhy2gEBx4mQIf6Vh/giphy.webp"))
    }

    @Test func linksThatNameTheAnimationNeedNoRequest() async throws {
        let service = makeService()
        for link in [
            "https://media.tenor.com/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif",
            "https://i.giphy.com/JIX9t2j0ZTN9S.webp",
        ] {
            let preview = try await service.preview(for: url(link), policy: policy)
            #expect(preview.kind == .gif)
            #expect(preview.gif?.isResolved == true)
            #expect(preview.displayTitle != nil)
        }
        #expect(server.requests.isEmpty)
    }

    @Test func aGiphyPageIsFetchedOnlyForItsTitle() async throws {
        // The decider fetches a resolved page link only for a text card.
        // GIPHY answers the page's other address with a page that only
        // redirects to the one with the tags; Vela follows that once.
        let slug = "https://giphy.com/gifs/cat-funny-JIX9t2j0ZTN9S"
        let page = "https://giphy.com/gifs/JIX9t2j0ZTN9S"
        server.route(slug, .html(#"<head><meta id="__next-page-redirect" http-equiv="refresh" content="0;url=https://giphy.com/gifs/JIX9t2j0ZTN9S"/></head>"#))
        server.route(page, .html(try Fixtures.string("giphy-gif.html")))
        let preview = try await makeService().preview(for: url(slug), policy: policy)
        #expect(preview.kind == .gif)
        #expect(preview.url == url(slug))
        #expect(preview.title == "Cat Working GIF - Find & Share on GIPHY")
        #expect(preview.gif?.videoURL == url("https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.mp4"))
    }

    @Test func refreshesToOtherSitesAreNotFollowed() async throws {
        let page = "https://giphy.com/gifs/JIX9t2j0ZTN9S"
        server.route(page, .html(#"<head><meta http-equiv="refresh" content="0;url=https://elsewhere.example/x"></head>"#))
        let preview = try await makeService().preview(for: url(page), policy: policy)
        #expect(preview.title == "giphy.com")
        #expect(server.requests(to: "https://elsewhere.example/x").isEmpty)
    }

    @Test func aGiphyPageThatFailsStillHasItsAnimation() async throws {
        server.route("https://giphy.com/gifs/JIX9t2j0ZTN9S", .status(500))
        let preview = try await makeService().preview(for: url("https://giphy.com/gifs/JIX9t2j0ZTN9S"), policy: policy)
        #expect(preview.kind == .gif)
        #expect(preview.gif?.isResolved == true)
    }

    @Test func aTenorPageWithoutAnAnimationIsACard() async throws {
        let page = "https://tenor.com/view/removed-gif-1"
        server.route(page, .html(#"<head><title>Tenor GIF Keyboard</title><meta property="og:image" content="https://tenor.com/logo.png"></head>"#))
        let preview = try await makeService().preview(for: url(page), policy: policy)
        #expect(preview.kind == .page)
        #expect(preview.title == "Tenor GIF Keyboard")
        #expect(preview.gif == nil)
    }

    @Test func aStickerPageResolvesToItsImage() async throws {
        let page = "https://tenor.com/view/brick-cat-sticker-27149281"
        server.route(page, .html(try Fixtures.string("tenor-sticker.html")))
        let preview = try await makeService().preview(for: url(page), policy: policy)
        #expect(preview.gif?.videoURL == nil)
        #expect(preview.gif?.imageURL == url("https://media.tenor.com/3w0Our6WmXUAAAAm/brick-cat.webp"))
    }

    @Test func aShortLinkIntoABlockedSiteIsRefused() async throws {
        let blocking = MediaPolicy(siteRules: SiteRules(["tenor.com": "block"]))
        server.route("https://gph.is/g/abc", .redirect(to: "https://tenor.com/view/x-gif-1", status: 301))
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .userBlocked, domain: "tenor.com"))) {
            try await makeService().preview(for: url("https://gph.is/g/abc"), policy: blocking)
        }
        #expect(server.requests(to: "https://tenor.com/view/x-gif-1").isEmpty)
    }

    @Test func aTextOnlySiteStillGetsItsTextButNoMediaRequests() async throws {
        let textOnly = MediaPolicy(siteRules: SiteRules(["tenor.com": "textOnly"]))
        server.route(tenorPage, .html(try Fixtures.string("tenor-view.html")))
        let preview = try await makeService().preview(for: url(tenorPage), policy: textOnly)
        #expect(preview.hasCardContent(showingImages: false))
        #expect(server.requests.allSatisfy { $0.url?.host() == "tenor.com" })
    }
}

/// `LoopingVideoLoader`: the checks that keep GIF videos to the image rules.
@Suite struct LoopingVideoLoaderTests {
    let server = StubServer()

    private func url(_ string: String) -> URL { URL(string: string)! }

    private func makeLoader() -> LoopingVideoLoader {
        LoopingVideoLoader(
            session: server.makeSession(),
            directory: FileManager.default.temporaryDirectory.appending(path: "vela-gif-tests-\(UUID().uuidString)")
        )
    }

    @Test func recognizesMP4s() {
        #expect(LoopingVideoLoader.isMP4(Data([0, 0, 0, 0x20]) + Data("ftypisom".utf8) + Data(count: 8)))
        #expect(!LoopingVideoLoader.isMP4(Data("GIF89a......".utf8)))
        #expect(!LoopingVideoLoader.isMP4(Data("ftyp".utf8)))
    }

    @Test func refusesWhatThePolicyRefuses() async {
        let loader = makeLoader()
        let textOnly = MediaPolicy(siteRules: SiteRules(["tenor.com": "textOnly"]))
        await #expect(throws: MediaError.blockedByPolicy) {
            try await loader.load(url("https://media.tenor.com/a/b.mp4"), policy: textOnly)
        }
        let blocked = MediaPolicy(siteRules: SiteRules(["giphy.com": "block"]))
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .userBlocked, domain: "giphy.com"))) {
            try await loader.load(url("https://media.giphy.com/media/x/giphy.mp4"), policy: blocked)
        }
        #expect(server.requests.isEmpty)
    }

    @Test func refusesRedirectsIntoBlockedSites() async {
        server.route("https://cdn.example.com/a.mp4", .redirect(to: "https://blocked.example/a.mp4"))
        let policy = MediaPolicy(siteRules: SiteRules(["blocked.example": "block"]))
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .userBlocked, domain: "blocked.example"))) {
            try await makeLoader().load(url("https://cdn.example.com/a.mp4"), policy: policy)
        }
        #expect(server.requests(to: "https://blocked.example/a.mp4").isEmpty)
    }

    @Test func honorsTheSizeLimit() async {
        let body = Data([0, 0, 0, 0x20]) + Data("ftypisom".utf8) + Data(count: 4_000)
        server.route("https://cdn.example.com/big.mp4", .data(body, contentType: "video/mp4"))
        await #expect(throws: MediaError.tooLarge) {
            try await makeLoader().load(url("https://cdn.example.com/big.mp4"), policy: MediaPolicy(maxImageBytes: 1_000))
        }
    }

    @Test func loadsChecksAndKeepsAnMP4() async throws {
        let body = try await TestVideos.mp4(width: 32, height: 16)
        server.route("https://media.tenor.com/WAeOn7-AdfgAAAPo/a.mp4", .data(body, contentType: "video/mp4"))
        let loader = makeLoader()
        let link = url("https://media.tenor.com/WAeOn7-AdfgAAAPo/a.mp4")

        let video = try await loader.load(link, policy: MediaPolicy())
        #expect(video.pixelSize == CGSize(width: 32, height: 16))
        #expect(video.byteCount == body.count)
        #expect(FileManager.default.fileExists(atPath: video.fileURL.path(percentEncoded: false)))
        let request = try #require(server.requests(to: link.absoluteString).first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == LinkPreviewService.defaultUserAgent)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)

        // From disk the second time, and only under a policy that allows it.
        #expect(try await loader.load(link, policy: MediaPolicy()) == video)
        #expect(server.requests(to: link.absoluteString).count == 1)
        #expect(await loader.cachedVideo(for: link, policy: MediaPolicy()) == video)
        let textOnly = MediaPolicy(siteRules: SiteRules(["tenor.com": "textOnly"]))
        #expect(await loader.cachedVideo(for: link, policy: textOnly) == nil)
        await #expect(throws: MediaError.tooLarge) {
            try await loader.load(link, policy: MediaPolicy(maxImageBytes: 10))
        }
        await loader.removeAll()
        #expect(!FileManager.default.fileExists(atPath: video.fileURL.path(percentEncoded: false)))
    }

    @Test func evictsTheLeastRecentlyUsedFiles() async throws {
        let body = try await TestVideos.mp4(width: 16, height: 16)
        for name in ["a", "b", "c"] {
            server.route("https://cdn.example.com/\(name).mp4", .data(body, contentType: "video/mp4"))
        }
        let loader = LoopingVideoLoader(
            session: server.makeSession(),
            directory: FileManager.default.temporaryDirectory.appending(path: "vela-gif-tests-\(UUID().uuidString)"),
            countLimit: 2
        )
        let a = try await loader.load(url("https://cdn.example.com/a.mp4"), policy: MediaPolicy())
        _ = try await loader.load(url("https://cdn.example.com/b.mp4"), policy: MediaPolicy())
        _ = try await loader.load(url("https://cdn.example.com/c.mp4"), policy: MediaPolicy())
        #expect(await loader.cachedVideo(for: url("https://cdn.example.com/a.mp4"), policy: MediaPolicy()) == nil)
        #expect(!FileManager.default.fileExists(atPath: a.fileURL.path(percentEncoded: false)))
        #expect(await loader.cachedVideo(for: url("https://cdn.example.com/c.mp4"), policy: MediaPolicy()) != nil)
        await loader.removeAll()
    }

    @Test func refusesWhatIsntAnMP4() async {
        server.route("https://cdn.example.com/page.mp4", .html("<html></html>"))
        server.route("https://cdn.example.com/anim.mp4", .data(Data("GIF89a-not-a-video".utf8), contentType: "video/mp4"))
        server.route("https://cdn.example.com/broken.mp4", .data(Data([0, 0, 0, 0x20]) + Data("ftypisom".utf8) + Data(count: 64), contentType: "video/mp4"))
        let loader = makeLoader()
        for path in ["page", "anim", "broken"] {
            await #expect(throws: MediaError.unsupportedContent) {
                try await loader.load(url("https://cdn.example.com/\(path).mp4"), policy: MediaPolicy())
            }
        }
    }
}

/// Encodes tiny H.264 MP4s in memory, so tests need no binary fixtures.
enum TestVideos {
    struct EncodingFailed: Error {}

    static func mp4(width: Int, height: Int, frames: Int = 3) async throws -> Data {
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "vela-test-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw EncodingFailed() }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? EncodingFailed() }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw EncodingFailed() }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw EncodingFailed() }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(frame * 60 % 255), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10)) else {
                throw writer.error ?? EncodingFailed()
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? EncodingFailed() }
        return try Data(contentsOf: fileURL)
    }
}
