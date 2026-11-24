// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A test's timeout, counted in time the test could actually run.
///
/// Swift Testing starts every UI test at once, and each one sets up on the
/// main actor, which they all share. So a waiting test can go many seconds
/// between two checks while the others take their turns: 15 to 30 s at the
/// start of a run on GitHub's 3-core runners. A wall-clock deadline runs out
/// in that wait, and the test fails though nothing it watches was slow. This
/// one counts each gap between checks only up to ``slice``, so the test gets
/// its whole timeout to watch.
struct RunningDeadline {
    /// The most one gap between checks counts for: longer than any test
    /// waits between checks, far shorter than a stall.
    static let slice: Duration = .milliseconds(250)

    private let timeout: Duration
    private var counted: Duration = .zero
    private var lastCheck: ContinuousClock.Instant

    init(_ timeout: Duration, now: ContinuousClock.Instant = .now) {
        self.timeout = timeout
        lastCheck = now
    }

    /// Counts the time since the last check (at most ``slice``), and
    /// returns whether any of the timeout is left.
    mutating func hasTimeLeft(now: ContinuousClock.Instant = .now) -> Bool {
        counted += min(now - lastCheck, Self.slice)
        lastCheck = now
        return counted < timeout
    }

    /// Checks `condition` every `interval` until it holds, or until
    /// `timeout` of running time has passed. Returns whether it held.
    @MainActor
    static func wait(
        timeout: Duration,
        every interval: Duration = .milliseconds(10),
        until condition: () throws -> Bool
    ) async rethrows -> Bool {
        var deadline = RunningDeadline(timeout)
        while true {
            if try condition() { return true }
            guard deadline.hasTimeLeft() else { return false }
            try? await Task.sleep(for: interval)
        }
    }
}
