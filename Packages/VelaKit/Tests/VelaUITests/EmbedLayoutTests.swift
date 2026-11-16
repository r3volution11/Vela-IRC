// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Testing
@testable import VelaUI

@MainActor
@Suite("Standard link card layout")
struct StandardCardLayoutTests {
    typealias Card = StandardCardLayout

    @Test func contentFitsTheCardWidth() {
        #expect(Card.maxContentWidth == Card.maxCardWidth - 4 - 24)
        #expect(Card.maxCardWidth == 480)
        #expect(Card.thumbnailSize == CGSize(width: 104, height: 78))
    }

    @Test func thumbnailSitsBesideTheTextAtFullWidth() {
        let columns = Card.columns(contentWidth: 2_000, hasThumbnail: true)
        #expect(columns.showsThumbnail)
        #expect(columns.textWidth == Card.maxContentWidth - Card.thumbnailSize.width - Card.spacing)
    }

    @Test func textTakesTheWholeRowWithoutAThumbnail() {
        let columns = Card.columns(contentWidth: 2_000, hasThumbnail: false)
        #expect(!columns.showsThumbnail)
        #expect(columns.textWidth == Card.maxContentWidth)
    }

    @Test func shrinksWithTheColumn() {
        let columns = Card.columns(contentWidth: 320, hasThumbnail: true)
        #expect(columns.showsThumbnail)
        #expect(columns.textWidth == 320 - Card.thumbnailSize.width - Card.spacing)
    }

    @Test func dropsTheThumbnailWhenTheTextWouldGetTooNarrow() {
        let threshold = Card.minTextWidth + Card.thumbnailSize.width + Card.spacing
        #expect(Card.columns(contentWidth: threshold, hasThumbnail: true).showsThumbnail)
        let narrow = Card.columns(contentWidth: threshold - 1, hasThumbnail: true)
        #expect(!narrow.showsThumbnail)
        #expect(narrow.textWidth == threshold - 1)
    }

    @Test func neverNegative() {
        let columns = Card.columns(contentWidth: -10, hasThumbnail: true)
        #expect(columns.textWidth == 0)
        #expect(!columns.showsThumbnail)
    }

    @Test func thumbnailSetsTheMinimumHeight() {
        let short = Card.contentSize(text: CGSize(width: 200, height: 40), showsThumbnail: true)
        #expect(short == CGSize(width: 200 + Card.spacing + Card.thumbnailSize.width, height: Card.thumbnailSize.height))
        let tall = Card.contentSize(text: CGSize(width: 336, height: 90), showsThumbnail: true)
        #expect(tall.height == 90)
        #expect(tall.width <= Card.maxContentWidth)
        #expect(Card.contentSize(text: CGSize(width: 300, height: 40), showsThumbnail: false) == CGSize(width: 300, height: 40))
    }
}

@MainActor
@Suite("Video player size")
struct VideoPlayerSizeTests {
    @Test func landscapeFillsThePlayerWidth() {
        #expect(VideoEmbedView.maxPlayerWidth == 560)
        let height = VideoEmbedView.playerMaxHeight(aspectRatio: 16.0 / 9.0, maxImageHeight: 200)
        #expect(height == 315)
        let fitted = FittedMediaLayout(
            aspectRatio: 16.0 / 9.0, naturalSize: nil, maxWidth: VideoEmbedView.maxPlayerWidth, maxHeight: height
        ).fittedSize(availableWidth: 2_000)
        #expect(fitted == CGSize(width: 560, height: 315))
    }

    @Test func tallerImageSettingRaisesTheCap() {
        #expect(VideoEmbedView.playerMaxHeight(aspectRatio: 16.0 / 9.0, maxImageHeight: 400) == 400)
        #expect(VideoEmbedView.playerMaxHeight(aspectRatio: 9.0 / 16.0, maxImageHeight: 600) == 600)
    }

    @Test func portraitGetsMoreHeight() {
        let height = VideoEmbedView.playerMaxHeight(aspectRatio: 9.0 / 16.0, maxImageHeight: 320)
        #expect(height == 490)
        let fitted = FittedMediaLayout(
            aspectRatio: 9.0 / 16.0, naturalSize: nil, maxWidth: VideoEmbedView.maxPlayerWidth, maxHeight: height
        ).fittedSize(availableWidth: 2_000)
        #expect(fitted.height == 490)
        #expect(fitted.width < 300)
    }

    @Test func narrowColumnsShrinkThePlayer() {
        let fitted = FittedMediaLayout(
            aspectRatio: 16.0 / 9.0,
            naturalSize: nil,
            maxWidth: VideoEmbedView.maxPlayerWidth,
            maxHeight: VideoEmbedView.playerMaxHeight(aspectRatio: 16.0 / 9.0, maxImageHeight: 320)
        ).fittedSize(availableWidth: 300)
        #expect(fitted == CGSize(width: 300, height: 169))
    }
}
