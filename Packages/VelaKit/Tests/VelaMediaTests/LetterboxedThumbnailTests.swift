// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import Testing
@testable import VelaMedia

@Suite struct LetterboxedThumbnailTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private let hqdefault = URL(string: "https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg")!

    @Test func youTubeFourByThreeThumbnailsDropTheirBars() throws {
        // hqdefault is 480×360 around a 480×270 picture: 45 px bars above and below.
        let rect = try #require(LetterboxedThumbnail.pictureRect(url: hqdefault, pixelSize: CGSize(width: 480, height: 360)))
        #expect(rect.minX == 0 && rect.width == 1)
        #expect(abs(rect.minY - 0.125) < 0.0001)
        #expect(abs(rect.height - 0.75) < 0.0001)
        #expect(LetterboxedThumbnail.pictureSize(url: hqdefault, pixelSize: CGSize(width: 480, height: 360))
            == CGSize(width: 480, height: 270))
        #expect(LetterboxedThumbnail.pictureRect(url: hqdefault, pixelWidth: 480, pixelHeight: 360)
            == CGRect(x: 0, y: 45, width: 480, height: 270))
    }

    @Test func coversTheThumbnailHostsAndVariants() {
        let fourByThree = CGSize(width: 640, height: 480)
        for string in [
            "https://i.ytimg.com/vi/aqz-KE-bpKQ/sddefault.jpg",
            "https://i3.ytimg.com/vi/aqz-KE-bpKQ/default.jpg",
            "https://img.youtube.com/vi/aqz-KE-bpKQ/0.jpg",
            "https://i.ytimg.com/vi_webp/aqz-KE-bpKQ/hqdefault.webp",
            "https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault_live.jpg",
        ] {
            #expect(LetterboxedThumbnail.pictureRect(url: url(string), pixelSize: fourByThree) != nil, "\(string)")
        }
    }

    @Test func downsampledCopiesStillMatch() {
        // Thumbnails decoded smaller round their sides (e.g. 80×60, 24×18, 208×156).
        for size in [CGSize(width: 80, height: 60), CGSize(width: 24, height: 18), CGSize(width: 101, height: 76)] {
            #expect(LetterboxedThumbnail.pictureRect(url: hqdefault, pixelSize: size) != nil, "\(size)")
        }
        #expect(LetterboxedThumbnail.pictureRect(url: hqdefault, pixelWidth: 24, pixelHeight: 18)
            == CGRect(x: 0, y: 2, width: 24, height: 14))
    }

    @Test func sixteenByNineThumbnailsAreLeftAlone() {
        // mqdefault, maxresdefault and hq720 have no bars.
        let wide = CGSize(width: 1280, height: 720)
        #expect(LetterboxedThumbnail.pictureRect(url: url("https://i.ytimg.com/vi/aqz-KE-bpKQ/maxresdefault.jpg"), pixelSize: wide) == nil)
        #expect(LetterboxedThumbnail.pictureSize(url: url("https://i.ytimg.com/vi/aqz-KE-bpKQ/mqdefault.jpg"), pixelSize: CGSize(width: 320, height: 180))
            == CGSize(width: 320, height: 180))
    }

    @Test func otherImagesAreLeftAlone() {
        let fourByThree = CGSize(width: 480, height: 360)
        for string in [
            "https://i.vimeocdn.com/video/20963649-f028-d_640",
            "https://example.com/vi/abc/hqdefault.jpg",
            "https://i.ytimg.com/an_webp/aqz-KE-bpKQ/mqdefault_6s.webp",
            "https://i.ytimg.com/vi/hqdefault.jpg",
            "https://yt3.ggpht.com/avatar.jpg",
            "https://notytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg",
        ] {
            #expect(LetterboxedThumbnail.pictureRect(url: url(string), pixelSize: fourByThree) == nil, "\(string)")
            #expect(LetterboxedThumbnail.pictureSize(url: url(string), pixelSize: fourByThree) == fourByThree)
        }
        #expect(LetterboxedThumbnail.pictureRect(url: hqdefault, pixelSize: .zero) == nil)
    }
}
