// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaMedia
@testable import VelaUI

@Suite("Image load failures")
struct ImageLoadFailureTests {
    private let megabyte = 1024 * 1024

    @Test func saysWhatHappened() {
        #expect(ImageLoadFailure(MediaError.tooLarge, limitBytes: 10 * megabyte) == .tooLarge(limitBytes: 10 * megabyte))
        #expect(ImageLoadFailure(MediaError.tooManyPixels, limitBytes: 10 * megabyte) == .tooManyPixels)
        #expect(ImageLoadFailure(MediaError.http(404), limitBytes: 10 * megabyte) == .unavailable)
        #expect(ImageLoadFailure(URLError(.timedOut), limitBytes: 10 * megabyte) == .unavailable)
    }

    @Test func titleNamesTheLimit() {
        #expect(ImageLoadFailure.tooLarge(limitBytes: 10 * megabyte).title == "Image larger than 10 MB")
        #expect(ImageLoadFailure.tooLarge(limitBytes: Int(2.5 * Double(megabyte))).title == "Image larger than 2.5 MB")
        // How `AppModel` turns the setting into bytes.
        #expect(ImageLoadFailure.tooLarge(limitBytes: Int(25.0 * 1024 * 1024)).title == "Image larger than 25 MB")
        #expect(ImageLoadFailure.tooManyPixels.title == "Image too large to show inline")
        #expect(ImageLoadFailure.unavailable.title == "Couldn't load image")
        #expect(ImageLoadFailure.unavailable.isError)
        #expect(!ImageLoadFailure.tooLarge(limitBytes: megabyte).isError)
    }

    @Test func aRaisedLimitRetriesTooLargeImages() {
        let failure = ImageLoadFailure.tooLarge(limitBytes: 10 * megabyte)
        #expect(failure.persists(under: MediaPolicy(maxImageBytes: 10 * megabyte)))
        #expect(failure.persists(under: MediaPolicy(maxImageBytes: 5 * megabyte)))
        #expect(!failure.persists(under: MediaPolicy(maxImageBytes: 20 * megabyte)))
        #expect(ImageLoadFailure.tooManyPixels.persists(under: MediaPolicy(maxImageBytes: 100 * megabyte)))
        #expect(ImageLoadFailure.unavailable.persists(under: MediaPolicy(maxImageBytes: 100 * megabyte)))
    }
}
