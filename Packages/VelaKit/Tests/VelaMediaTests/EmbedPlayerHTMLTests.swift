// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

@Suite struct EmbedPlayerHTMLTests {
    private func embed(_ string: String) throws -> EmbedInfo {
        guard case .embed(let info) = MediaClassifier.classify(URL(string: string)!) else {
            throw EmbedMissing()
        }
        return info
    }

    struct EmbedMissing: Error {}

    @Test func baseURLIsHTTPS() {
        #expect(EmbedPlayerHTML.baseURL.absoluteString == "https://r3volution11.github.io/Vela-IRC/")
        #expect(EmbedPlayerHTML.baseURL.scheme == "https")
    }

    @Test func youtubePage() throws {
        let info = try embed("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42")
        let html = EmbedPlayerHTML.html(for: info, autoplay: true)
        #expect(html.contains(#"<meta name="referrer" content="strict-origin-when-cross-origin">"#))
        #expect(html.contains(#"referrerpolicy="strict-origin-when-cross-origin""#))
        #expect(html.contains(#"allow="autoplay; encrypted-media; picture-in-picture; fullscreen""#))
        #expect(html.contains("allowfullscreen"))
        #expect(html.contains("background: #000"))
        #expect(html.contains("<iframe src=\"https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=42&amp;"))
        #expect(html.contains("autoplay=1"))
        #expect(html.contains("playsinline=1"))
        #expect(html.contains("rel=0"))
    }

    @Test func autoplayOff() throws {
        let info = try embed("https://youtu.be/dQw4w9WgXcQ")
        let url = EmbedPlayerHTML.playerURL(for: info, autoplay: false)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.filter { $0.name == "autoplay" } == [URLQueryItem(name: "autoplay", value: "0")])
        #expect(EmbedPlayerHTML.html(for: info, autoplay: false).contains("autoplay=0"))
    }

    @Test func providerPlayerURLs() throws {
        let vimeo = EmbedPlayerHTML.playerURL(for: try embed("https://vimeo.com/76979871#t=10s"), autoplay: true)
        #expect(vimeo.absoluteString == "https://player.vimeo.com/video/76979871?autoplay=1#t=10s")

        let clip = EmbedPlayerHTML.playerURL(for: try embed("https://clips.twitch.tv/SomeClipSlug"), autoplay: false)
        #expect(clip.absoluteString
            == "https://clips.twitch.tv/embed?clip=SomeClipSlug&parent=r3volution11.github.io&autoplay=false")

        let vod = EmbedPlayerHTML.playerURL(for: try embed("https://www.twitch.tv/videos/123"), autoplay: true)
        #expect(vod.absoluteString == "https://player.twitch.tv/?video=123&parent=r3volution11.github.io&autoplay=true")

        let streamable = EmbedPlayerHTML.playerURL(for: try embed("https://streamable.com/abc123"), autoplay: true)
        #expect(streamable.absoluteString == "https://streamable.com/e/abc123?autoplay=1")
    }

    @Test func twitchParentMatchesBaseHost() throws {
        let info = try embed("https://clips.twitch.tv/SomeClipSlug")
        let parent = URLComponents(url: info.embedURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "parent" }?.value
        #expect(parent == EmbedPlayerHTML.baseURL.host())
    }

    @Test func escapesTitle() throws {
        var info = try embed("https://youtu.be/dQw4w9WgXcQ")
        info.title = #"<script>alert("x")</script> & 'friends'"#
        let html = EmbedPlayerHTML.html(for: info, autoplay: true)
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &#39;friends&#39;"))
    }
}
