// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Temporary folders for demo mode (`--demo`, screenshots, previews), named
/// `VelaDemo-…` in the temporary directory.
///
/// Each demo run makes fresh ones and removes them when it quits. Runs that
/// exit early (snapshots call `exit`) leave theirs behind, so every new demo
/// run also sweeps `VelaDemo-…` folders more than an hour old. The hour keeps
/// demo runs that are still going (parallel screenshot renders) safe.
nonisolated public enum DemoScratch {
    /// Folders older than this are removed by ``removeStale(in:olderThan:now:)``.
    public static let staleAge: TimeInterval = 60 * 60

    nonisolated(unsafe) private static var own: [URL] = []
    private static let lock = NSLock()

    /// A new, empty `<prefix><UUID>` folder in `directory`, remembered so
    /// ``removeOwn()`` can delete it.
    public static func makeDirectory(
        prefix: String,
        in directory: URL = FileManager.default.temporaryDirectory
    ) -> URL {
        let url = directory.appendingPathComponent("\(prefix)\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        lock.withLock { own.append(url) }
        return url
    }

    /// Deletes the folders this process made.
    public static func removeOwn() {
        let urls = lock.withLock { () -> [URL] in
            defer { own.removeAll() }
            return own
        }
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    /// Deletes `VelaDemo-…` folders in `directory` last modified more than
    /// `olderThan` ago. Returns how many were removed.
    @discardableResult
    public static func removeStale(
        in directory: URL = FileManager.default.temporaryDirectory,
        olderThan age: TimeInterval = staleAge,
        now: Date = Date()
    ) -> Int {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var removed = 0
        for url in entries where url.lastPathComponent.hasPrefix("VelaDemo-") {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true,
                  let modified = values?.contentModificationDate,
                  now.timeIntervalSince(modified) > age
            else { continue }
            if (try? fileManager.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }
}
