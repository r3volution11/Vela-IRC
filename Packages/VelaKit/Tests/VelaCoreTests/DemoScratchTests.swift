// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore

@Suite("Demo scratch folders")
struct DemoScratchTests {
    private func makeParent() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DemoScratchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func removesOnlyOldDemoFolders() throws {
        let parent = try makeParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        // Made directly, not through makeDirectory, so removeOwn() in a
        // parallel test can't delete them.
        let old = parent.appendingPathComponent("VelaDemo-\(UUID().uuidString)")
        let fresh = parent.appendingPathComponent("VelaDemo-Themes-\(UUID().uuidString)")
        let other = parent.appendingPathComponent("Unrelated")
        for url in [old, fresh, other] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: old.path)

        #expect(DemoScratch.removeStale(in: parent) == 1)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}
