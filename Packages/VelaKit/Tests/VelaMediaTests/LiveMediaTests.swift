// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

/// Against the real sites, so off unless asked for:
///
///     VELA_LIVE_GIF_TESTS=1 swift test --filter LiveGIFTests
///     VELA_LIVE_REDDIT_TESTS=1 swift test --filter LiveRedditTests
///
/// They check that the sites still serve what Vela expects.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["VELA_LIVE_GIF_TESTS"] != nil))
struct LiveGIFTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private func loader() -> LoopingVideoLoader {
        LoopingVideoLoader(directory: FileManager.default.temporaryDirectory.appending(path: "vela-live-gifs-\(UUID().uuidString)"))
    }

    @Test func tenorShortLink() async throws {
        let preview = try await LinkPreviewService().preview(for: url("https://tenor.com/RaDD.gif"), policy: MediaPolicy())
        #expect(preview.kind == .gif)
        #expect(preview.finalURL.path().hasPrefix("/view/"))
        let gif = try #require(preview.gif)
        let video = try #require(gif.videoURL)
        #expect(video.host() == "media.tenor.com")
        #expect(video.pathExtension == "mp4")

        let loaded = try await loader().load(video, policy: MediaPolicy())
        #expect(loaded.pixelSize.width > 0 && loaded.pixelSize.height > 0)
        #expect(loaded.byteCount < 1024 * 1024)
        // The fallback GIF exists too.
        let fallback = try #require(gif.imageURL)
        #expect(try await ImageLoader().load(fallback, policy: MediaPolicy()).isAnimated)
    }

    @Test func tenorFileSwapsToItsMP4() async throws {
        guard case .gif(let gif) = MediaClassifier.classify(url("https://media.tenor.com/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif")),
              let video = gif.videoURL
        else {
            Issue.record("not a GIF")
            return
        }
        let loaded = try await loader().load(video, policy: MediaPolicy())
        #expect(loaded.byteCount < 200 * 1024)
    }

    @Test func giphyPageAndShortLink() async throws {
        guard case .gif(let gif) = MediaClassifier.classify(url("https://giphy.com/gifs/cat-funny-JIX9t2j0ZTN9S")),
              let video = gif.videoURL
        else {
            Issue.record("not a GIF")
            return
        }
        let loaded = try await loader().load(video, policy: MediaPolicy())
        #expect(loaded.pixelSize.width > 0)
        #expect(try await ImageLoader().load(try #require(gif.imageURL), policy: MediaPolicy()).isAnimated)

        let short = try await LinkPreviewService().preview(for: url("https://gph.is/g/46vwxjM"), policy: MediaPolicy())
        #expect(short.kind == .gif)
        #expect(short.gif?.videoURL == url("https://media.giphy.com/media/W0Jhy2gEBx4mQIf6Vh/giphy.mp4"))
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["VELA_LIVE_REDDIT_TESTS"] != nil))
struct LiveRedditTests {
    @Test func videoLink() async throws {
        let link = URL(string: "https://v.redd.it/1crlzghxl82i1")!
        let preview = try await LinkPreviewService().preview(for: link, policy: MediaPolicy())
        #expect(preview.kind == .embed)
        #expect(preview.title == "Jet powered skateboard")
        let embed = try #require(preview.embed)
        #expect(embed.provider == .reddit)
        #expect(embed.community == "r/LoveTrash")
        #expect(embed.authorName?.hasPrefix("u/") == true)
        #expect(embed.isGIF != nil)
        #expect(embed.embedURL == URL(string: "https://v.redd.it/1crlzghxl82i1/HLSPlaylist.m3u8"))
    }
}
