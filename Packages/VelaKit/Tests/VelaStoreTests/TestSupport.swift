// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

/// A unique scratch directory, removed by `cleanup()`.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "VelaStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL {
        url.appending(path: name, directoryHint: .notDirectory)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Polls `condition` until it holds or `timeout` elapses.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(10),
    interval: Duration = .milliseconds(50),
    _ condition: () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: interval)
    }
    return condition()
}

func writeString(_ string: String, to url: URL) throws {
    try Data(string.utf8).write(to: url, options: .atomic)
}

func readString(_ url: URL) throws -> String {
    try String(decoding: Data(contentsOf: url), as: UTF8.self)
}
