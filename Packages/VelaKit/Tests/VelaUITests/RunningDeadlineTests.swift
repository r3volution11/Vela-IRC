// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing

@Suite("Running deadline")
struct RunningDeadlineTests {
    private let start = ContinuousClock.now

    @Test func gapsUpToASliceCountInFull() {
        var deadline = RunningDeadline(.seconds(1), now: start)
        for ms in [200, 400, 600, 800] {
            let left = deadline.hasTimeLeft(now: start + .milliseconds(ms))
            #expect(left, "\(ms) ms")
        }
        let leftAtOneSecond = deadline.hasTimeLeft(now: start + .milliseconds(1000))
        #expect(!leftAtOneSecond)
    }

    @Test func aStallCountsForOneSlice() {
        var deadline = RunningDeadline(.seconds(1), now: start)
        // 30 s on another test's setup counts as 250 ms.
        let leftAfterStall = deadline.hasTimeLeft(now: start + .seconds(30))
        #expect(leftAfterStall)
        var now = start + .seconds(30)
        var checks = 0
        while deadline.hasTimeLeft(now: now) {
            now += .milliseconds(10)
            checks += 1
        }
        // The other 750 ms, checked every 10 ms.
        #expect((74...76).contains(checks))
    }
}
