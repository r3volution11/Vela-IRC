// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A small least-recently-used cache with optional cost accounting.
///
/// Value semantics; meant to live inside an actor. Lookups and inserts are
/// O(1); eviction scans for the oldest entry, which is fine for the few
/// hundred entries the media caches hold.
struct LRUCache<Key: Hashable, Value> {
    private struct Entry {
        var value: Value
        var cost: Int
        var lastAccess: UInt64
    }

    let countLimit: Int
    let costLimit: Int
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var totalCost = 0

    init(countLimit: Int, costLimit: Int = .max) {
        self.countLimit = max(1, countLimit)
        self.costLimit = max(1, costLimit)
    }

    var count: Int { entries.count }

    /// Returns the value and marks it as most recently used.
    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1
        entry.lastAccess = clock
        entries[key] = entry
        return entry.value
    }

    /// Returns the value without touching its recency.
    func peek(_ key: Key) -> Value? {
        entries[key]?.value
    }

    mutating func insert(_ value: Value, for key: Key, cost: Int = 0) {
        let cost = max(0, cost)
        // An item that can never fit is not worth evicting everything else for.
        guard cost <= costLimit else {
            removeValue(for: key)
            return
        }
        clock &+= 1
        if let old = entries[key] { totalCost -= old.cost }
        entries[key] = Entry(value: value, cost: cost, lastAccess: clock)
        totalCost += cost
        evictIfNeeded(protecting: key)
    }

    @discardableResult
    mutating func removeValue(for key: Key) -> Value? {
        guard let old = entries.removeValue(forKey: key) else { return nil }
        totalCost -= old.cost
        return old.value
    }

    mutating func removeAll() {
        entries.removeAll()
        totalCost = 0
    }

    /// Drops the least recently used entries until at most `count` remain
    /// and they cost at most `cost` (memory pressure).
    mutating func trim(toCount count: Int, cost: Int = .max) {
        guard entries.count > count || totalCost > cost else { return }
        for (key, _) in entries.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            guard entries.count > count || totalCost > cost else { break }
            removeValue(for: key)
        }
    }

    /// Keeps the most recently used `fraction` of the entries and their cost.
    mutating func trim(keeping fraction: Double) {
        trim(toCount: Int(Double(entries.count) * fraction), cost: Int(Double(totalCost) * fraction))
    }

    private mutating func evictIfNeeded(protecting protected: Key) {
        while entries.count > countLimit || totalCost > costLimit {
            var oldestKey: Key?
            var oldestAccess = UInt64.max
            for (key, entry) in entries where key != protected && entry.lastAccess < oldestAccess {
                oldestKey = key
                oldestAccess = entry.lastAccess
            }
            guard let oldestKey else { return }
            removeValue(for: oldestKey)
        }
    }
}
