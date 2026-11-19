// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Sizes in-memory caches to the Mac they run on.
///
/// The budgets in the code are for Macs with 16 GB or more. A Mac with less
/// (in practice 8 GB, the smallest that runs macOS 26) gets half of each, so
/// Vela's caches don't push the rest of the system into swap. Bigger Macs
/// don't get more: the caches only hold what's near the screen.
public enum MemoryBudget {
    /// Below this much memory, budgets are halved. Macs come with 8 GB, then
    /// 16 GB or more, so this splits them cleanly.
    static let fullBudgetMemory: UInt64 = 12 * 1024 * 1024 * 1024

    /// This Mac's memory, in bytes.
    public static let physicalMemory = ProcessInfo.processInfo.physicalMemory

    /// The share of a full budget that a Mac with `physicalMemory` bytes gets.
    public static func scale(forPhysicalMemory physicalMemory: UInt64) -> Double {
        physicalMemory < fullBudgetMemory ? 0.5 : 1
    }

    /// `base` (a byte or entry budget for a 16 GB Mac) scaled to this Mac.
    public static func scaled(_ base: Int, physicalMemory: UInt64 = MemoryBudget.physicalMemory) -> Int {
        max(1, Int((Double(base) * scale(forPhysicalMemory: physicalMemory)).rounded()))
    }
}
