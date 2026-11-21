// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

/// The pages of GIFs sent from the picker, which KLIPY captions open.
@Suite struct SentGIFPagesTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private let thumbsUp = URL(string: "https://static.klipy.com/ii/d7aec6f6f171607374b2065c836f92f4/3d/31/08K8MgEk.gif")!
    private let thumbsUpPage = URL(string: "https://klipy.com/gifs/awesome-ok--ksMzbJP8D")!
    private let charlie = URL(string: "https://static.klipy.com/ii/263d75c9c6d04df878152f91dbffb873/1b/1d/6Sod6SaO.gif")!
    private let charliePage = URL(string: "https://klipy.com/gifs/cc-220--ksMzbJP8D")!

    @Test func recordsAndLooksUpByTheSentLink() {
        let pages = SentGIFPages()
        #expect(pages.page(for: thumbsUp) == nil)
        pages.record(page: thumbsUpPage, for: thumbsUp)
        pages.record(page: charliePage, for: charlie)
        #expect(pages.page(for: thumbsUp) == thumbsUpPage)
        #expect(pages.page(for: charlie) == charliePage)
        // The same link, parsed again from a message's text.
        #expect(pages.page(for: url(thumbsUp.absoluteString)) == thumbsUpPage)
        // Another file of the same GIF has a link of its own, and isn't known.
        #expect(pages.page(for: url("https://static.klipy.com/ii/d7aec6f6f171607374b2065c836f92f4/3d/31/AVBuFxXW.webp")) == nil)
        #expect(pages.count == 2)
    }

    @Test func recordingAgainReplacesThePage() {
        let pages = SentGIFPages()
        pages.record(page: url("https://klipy.com/gifs/old"), for: thumbsUp)
        pages.record(page: thumbsUpPage, for: thumbsUp)
        #expect(pages.page(for: thumbsUp) == thumbsUpPage)
        #expect(pages.count == 1)
    }

    @Test func keepsOnlyTheLastSent() {
        let pages = SentGIFPages(capacity: 3)
        func link(_ number: Int) -> URL { url("https://static.klipy.com/ii/\(number).gif") }
        func page(_ number: Int) -> URL { url("https://klipy.com/gifs/gif-\(number)") }
        for number in 1...5 { pages.record(page: page(number), for: link(number)) }
        #expect(pages.count == 3)
        #expect(pages.page(for: link(1)) == nil)
        #expect(pages.page(for: link(2)) == nil)
        #expect((3...5).allSatisfy { pages.page(for: link($0)) == page($0) })

        // Sending one again makes it the newest, so the next to go is the oldest after it.
        pages.record(page: page(3), for: link(3))
        pages.record(page: page(6), for: link(6))
        #expect(pages.page(for: link(3)) == page(3))
        #expect(pages.page(for: link(4)) == nil)
        #expect(pages.count == 3)
    }

    @Test func holdsFiveHundredByDefault() {
        #expect(SentGIFPages.defaultCapacity == 500)
        let pages = SentGIFPages()
        #expect(pages.capacity == 500)
        for number in 0..<600 {
            pages.record(page: url("https://klipy.com/gifs/gif-\(number)"), for: url("https://static.klipy.com/ii/\(number).gif"))
        }
        #expect(pages.count == 500)
        #expect(pages.page(for: url("https://static.klipy.com/ii/99.gif")) == nil)
        #expect(pages.page(for: url("https://static.klipy.com/ii/100.gif")) == url("https://klipy.com/gifs/gif-100"))
        #expect(pages.page(for: url("https://static.klipy.com/ii/599.gif")) == url("https://klipy.com/gifs/gif-599"))
        #expect(SentGIFPages(capacity: 0).capacity == 1)
    }

    @Test func isSafeToUseFromManyTasks() async {
        let pages = SentGIFPages(capacity: 64)
        await withTaskGroup(of: Void.self) { group in
            for number in 0..<200 {
                group.addTask {
                    let link = URL(string: "https://static.klipy.com/ii/\(number).gif")!
                    pages.record(page: URL(string: "https://klipy.com/gifs/gif-\(number)")!, for: link)
                    _ = pages.page(for: link)
                }
            }
        }
        #expect(pages.count == 64)
    }
}
