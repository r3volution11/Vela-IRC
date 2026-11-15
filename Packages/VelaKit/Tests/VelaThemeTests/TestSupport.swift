// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
@testable import VelaTheme

enum Fixtures {
    static let directory: URL = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!

    static func url(_ path: String) -> URL {
        directory.appendingPathComponent(path)
    }

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: url(path))
    }
}

/// The repository root, for checking generated files are up to date.
enum Repository {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // VelaThemeTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // VelaKit
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root
}

/// A fresh temporary directory, removed when the value is deallocated.
final class TemporaryDirectory: Sendable {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VelaThemeTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ text: String, to name: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try Data(text.utf8).write(to: file, options: .atomic)
        return file
    }
}

func hex(_ value: String) -> ThemeColor {
    ThemeColor(hex: value)!
}

/// Resolves a definition with no includes and no overrides.
func resolve(_ definition: ThemeDefinition, overrides: ThemeOverrides = .none) throws -> ResolvedTheme {
    try ThemeResolver.resolve(definition, id: "test", includeLoader: { _ in nil }, overrides: overrides)
}
