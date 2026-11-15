// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Shares one task between concurrent requests for the same key and cancels
/// it once every waiter has been cancelled. Lives inside an actor.
struct InFlightTasks<Key: Hashable, Value: Sendable> {
    typealias Work = Task<Value, any Error>

    private struct Entry {
        var id: UInt64
        var task: Work
        var waiters: Int
    }

    private var entries: [Key: Entry] = [:]
    private var nextID: UInt64 = 0

    var count: Int { entries.count }

    /// Joins the running task for `key`, or starts one. `start` receives the
    /// entry's id, which the task must pass to `finish` when it completes.
    mutating func join(_ key: Key, start: (UInt64) -> Work) -> (task: Work, id: UInt64) {
        if var entry = entries[key] {
            entry.waiters += 1
            entries[key] = entry
            return (entry.task, entry.id)
        }
        nextID &+= 1
        let id = nextID
        let task = start(id)
        entries[key] = Entry(id: id, task: task, waiters: 1)
        return (task, id)
    }

    /// A waiter was cancelled; the last one to leave cancels the work.
    mutating func leave(_ key: Key, id: UInt64) {
        guard var entry = entries[key], entry.id == id else { return }
        entry.waiters -= 1
        if entry.waiters <= 0 {
            entries[key] = nil
            entry.task.cancel()
        } else {
            entries[key] = entry
        }
    }

    /// The work finished; later requests start fresh (or hit a cache).
    mutating func finish(_ key: Key, id: UInt64) {
        if entries[key]?.id == id { entries[key] = nil }
    }
}
