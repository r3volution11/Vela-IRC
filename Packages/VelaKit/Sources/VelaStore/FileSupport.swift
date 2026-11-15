// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Small helpers shared by the plain-file stores.
enum FileSupport {
    /// Writes `data` atomically (temp file + rename), creating the parent
    /// directory if needed. Symlinks are resolved first so that a settings
    /// file symlinked from a dotfiles repo stays a symlink.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        let target = resolvedForWriting(url)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: target, options: .atomic)
    }

    /// Reads the file, returning `nil` when it does not exist.
    static func readIfPresent(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch let error as NSError
            where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
        {
            return nil
        }
    }

    private static func resolvedForWriting(_ url: URL) -> URL {
        let path = url.path(percentEncoded: false)
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return url
        }
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination)
        }
        return url.deletingLastPathComponent().appending(path: destination)
    }
}

/// ISO 8601 timestamps with millisecond precision, the on-disk date format
/// for config files (readable, sortable, and sync-friendly).
enum ISODate {
    static func string(from date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func date(from string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(string)
    }
}

/// A coding key that accepts any string; used to preserve unknown keys.
struct AnyCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue) }
}
