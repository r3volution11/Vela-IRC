// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Counts pieces of work in flight, so callers can wait until none are
/// left. Each `begin()` is matched by one `end()`.
final class PendingWork {
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isIdle: Bool { count == 0 }

    func begin() {
        count += 1
    }

    func end() {
        count = max(0, count - 1)
        guard count == 0, !waiters.isEmpty else { return }
        let waiting = waiters
        waiters.removeAll()
        for waiter in waiting { waiter.resume() }
    }

    /// Returns once nothing is in flight (at once if nothing is).
    func wait() async {
        while count > 0 {
            await withCheckedContinuation { waiters.append($0) }
        }
    }
}
