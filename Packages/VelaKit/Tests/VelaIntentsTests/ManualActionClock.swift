// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore

/// An ``ActionClock`` that moves only when the test moves it. Actions that
/// wait for a network then take the clock's time, not the machine's, so a
/// busy test run can't stretch a wait past its timeout or a test's bounds.
@MainActor
final class ManualActionClock {
    private(set) var now: Duration = .zero
    private var sleepers: [(wakeAt: Duration, continuation: CheckedContinuation<Void, Never>)] = []

    /// For ``AppModel/actionClock``.
    var actionClock: ActionClock {
        ActionClock(now: { self.now }, sleep: { await self.sleep(for: $0) })
    }

    /// When the next sleeper wakes, while one is asleep.
    var nextWake: Duration? { sleepers.map(\.wakeAt).min() }

    private func sleep(for duration: Duration) async {
        await withCheckedContinuation { continuation in
            sleepers.append((now + max(.zero, duration), continuation))
        }
    }

    /// Moves the clock on to `time` and wakes every sleeper due by then.
    func advance(to time: Duration) {
        now = max(now, time)
        let due = sleepers.filter { $0.wakeAt <= now }
        sleepers.removeAll { $0.wakeAt <= now }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// What ``run(_:changes:)`` reports.
    struct Outcome<Value> {
        var result: Result<Value, any Error>
        /// How long the action took on the clock.
        var took: Duration
    }

    /// Runs `action` to the end, moving the clock to each wake-up while it
    /// waits. Each of `changes` is made once the clock reaches its time
    /// (counted from now), so only while `action` is waiting.
    func run<Value>(
        _ action: @escaping () async throws -> Value,
        changes: [(at: Duration, change: () -> Void)] = []
    ) async -> Outcome<Value> {
        let start = now
        var changes = changes.sorted { $0.at < $1.at }
        let box = ResultBox<Value>()
        Task {
            do { box.result = .success(try await action()) } catch { box.result = .failure(error) }
        }
        var idleTurns = 0
        while box.result == nil {
            if let wake = nextWake {
                idleTurns = 0
                if let next = changes.first, start + next.at <= wake {
                    changes.removeFirst()
                    advance(to: start + next.at)
                    next.change()
                } else {
                    advance(to: wake)
                }
            } else {
                // Running between waits: let it get on.
                idleTurns += 1
                if idleTurns > 10_000 {
                    Issue.record("The action neither finished nor waited on the clock")
                    return Outcome(result: .failure(CancellationError()), took: now - start)
                }
            }
            await Task.yield()
        }
        return Outcome(result: box.result!, took: now - start)
    }

    private final class ResultBox<Value> {
        var result: Result<Value, any Error>?
    }
}
