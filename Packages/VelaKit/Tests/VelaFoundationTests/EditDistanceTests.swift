// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import VelaFoundation

@Suite("Edit distance")
struct EditDistanceTests {
    @Test func distance() {
        #expect(EditDistance.distance("kitten", "sitting") == 3)
        #expect(EditDistance.distance("ab", "ba") == 1)
        #expect(EditDistance.distance("", "abc") == 3)
        #expect(EditDistance.distance("same", "same") == 0)
    }

    @Test func closestMatch() {
        let candidates = ["author", "description", "include", "name"]
        #expect(EditDistance.closest(to: "autor", in: candidates) == "author")
        #expect(EditDistance.closest(to: "NAME", in: candidates) == "name")
        #expect(EditDistance.closest(to: "fontSize", in: candidates) == nil)
        // A tighter limit rules out looser matches.
        #expect(EditDistance.closest(to: "descripton", in: candidates, limit: 0) == nil)
        #expect(EditDistance.closest(to: "descripton", in: candidates, limit: 1) == "description")
    }
}
