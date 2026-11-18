// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaMedia
@testable import VelaUI

@MainActor
@Suite("GIF embeds")
struct GIFEmbedTests {
    private func link(_ string: String) -> EmbedLink {
        EmbedLink(url: URL(string: string)!)
    }

    @Test func linksThatNameTheAnimationShowIt() {
        let file = link("https://media.tenor.com/WAeOn7-AdfgAAAAC/karate-kid-body-bag.gif")
        guard case .gif(let classified) = file.classification else {
            Issue.record("not classified as a GIF")
            return
        }
        #expect(EmbedPresentation(plan: .gif(.full), link: file, preview: nil) == .gif(classified, .full))
        #expect(EmbedPresentation(plan: .gif(.thumbnail), link: file, preview: nil) == .gif(classified, .thumbnail))
    }

    @Test func pagesShowWhatTheirFetchFound() {
        let page = link("https://tenor.com/RaDD.gif")
        #expect(EmbedPresentation(plan: .gif(.full), link: page, preview: nil) == .nothing)
        let gif = GIFInfo(provider: .tenor, videoURL: URL(string: "https://media.tenor.com/WAeOn7-AdfgAAAPo/a.mp4")!)
        let preview = LinkPreview(url: page.url, kind: .gif, mediaURL: gif.videoURL, gif: gif)
        #expect(EmbedPresentation(plan: .gif(.full), link: page, preview: preview) == .gif(gif, .full))
    }

    @Test func theSameAnimationPreviewsOnce() {
        // A GIPHY page and its file name the same video.
        #expect(link("https://giphy.com/gifs/cat-funny-JIX9t2j0ZTN9S").id == link("https://i.giphy.com/JIX9t2j0ZTN9S.gif").id)
        #expect(link("https://tenor.com/RaDD.gif").id == "https://tenor.com/radd.gif")
    }

    @Test func loadChip() {
        #expect(EmbedPresentation.loadChipLabel(.gif).systemImage == "photo.stack")
        #expect(EmbedPresentation.loadChipLabel(.gif).title == "Load GIF")
        #expect(EmbedPresentation.loadChipLabel(.videoEmbed(.reddit)).title == "Load Reddit video")
    }

    @Test func failureChipsNameTheGIF() {
        #expect(ImageLoadFailure.tooLarge(limitBytes: 10 * 1024 * 1024).title(for: "GIF") == "GIF larger than 10 MB")
        #expect(ImageLoadFailure.tooManyPixels.title(for: "GIF") == "GIF too large to show inline")
        #expect(ImageLoadFailure.unavailable.title(for: "GIF") == "Couldn't load GIF")
        #expect(ImageLoadFailure.unavailable.title == "Couldn't load image")
    }

    @Test func playback() {
        func play(
            ready: Bool = true, blurred: Bool = false, visible: Bool = true, choice: Bool? = nil,
            reduceMotion: Bool = false, compact: Bool = false, hovering: Bool = false
        ) -> Bool {
            GIFPlayback.shouldPlay(
                isReady: ready, isBlurred: blurred, isVisible: visible, userChoice: choice,
                reduceMotion: reduceMotion, compact: compact, hovering: hovering
            )
        }
        #expect(play())
        // Loading, blurred or scrolled away: still.
        #expect(!play(ready: false))
        #expect(!play(blurred: true))
        #expect(!play(blurred: true, choice: true))
        #expect(!play(visible: false))
        #expect(!play(visible: false, choice: true))
        // Reduce Motion: the first frame until the user presses play.
        #expect(!play(reduceMotion: true))
        #expect(play(choice: true, reduceMotion: true))
        // Paused by the user.
        #expect(!play(choice: false))
        // Thumbnails play while hovered.
        #expect(!play(compact: true))
        #expect(play(compact: true, hovering: true))
        #expect(!play(reduceMotion: true, compact: true, hovering: true))
    }
}
