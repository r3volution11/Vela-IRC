// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// File and folder names for chat logs:
///
///     Logs/
///       Libera.Chat/
///         #vela.log                                current file
///         #vela 2026-10-02 – 2026-11-01.log        a full file, renamed with the dates it covers
///         alice.log                                a private conversation
///         server.log                               server messages (logging.includeServer)
///       OFTC/
///         #debian.log
///
/// Names keep their case and characters, except the few a Mac can't use
/// in a file name (see ``sanitize(_:)``).
nonisolated public enum ChatLogNaming {
    public static let fileExtension = "log"
    /// The server buffer's file, `server.log`.
    public static let serverFileBase = "server"
    /// The separator between the dates of a full file.
    static let rangeSeparator = " – "

    /// `name` as a file or folder name: `/` and `:` (which Finder shows as
    /// `/`) and control characters become `_`, a leading `.` (a hidden
    /// file) becomes `_`, and very long names are shortened. Never empty.
    public static func sanitize(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            switch scalar {
            case "/", ":":
                scalars.append("_")
            default:
                scalars.append(scalar.value < 0x20 || scalar.value == 0x7F ? "_" : scalar)
            }
        }
        var result = String(scalars)
        if result.hasPrefix(".") { result = "_" + result.dropFirst() }
        // File names are limited to 255 bytes; leave room for a full file's dates.
        if result.utf8.count > maxBaseBytes {
            var shortened = ""
            for character in result {
                guard shortened.utf8.count + character.utf8.count <= maxBaseBytes else { break }
                shortened.append(character)
            }
            result = shortened
        }
        return result.isEmpty ? "_" : result
    }

    static let maxBaseBytes = 200

    /// The file name without its extension for a buffer: the channel or
    /// nick as shown, or `server` for the server buffer. A conversation
    /// with someone called "server" gets `server (query)`.
    public static func fileBase(bufferName: String, kind: BufferKind) -> String {
        switch kind {
        case .server:
            return serverFileBase
        case .channel:
            return sanitize(bufferName)
        case .query:
            let base = sanitize(bufferName)
            return base.lowercased() == serverFileBase ? "\(base) (query)" : base
        }
    }

    /// `#vela.log`.
    public static func currentFileName(base: String) -> String {
        "\(base).\(fileExtension)"
    }

    /// `#vela 2026-11-01 – 2026-11-17.log`, or with ` (2)` and up when a
    /// file with that name exists (two full files in one day).
    public static func rotatedFileName(base: String, from: String, to: String, counter: Int = 1) -> String {
        let suffix = counter > 1 ? " (\(counter))" : ""
        return "\(base) \(from)\(rangeSeparator)\(to)\(suffix).\(fileExtension)"
    }

    /// A full file's dates and counter, if `fileName` is one of `base`'s.
    public static func parseRotated(_ fileName: String, base: String) -> (from: String, to: String, counter: Int)? {
        guard let parts = splitRotated(fileName), parts.base == base else { return nil }
        return (parts.from, parts.to, parts.counter)
    }

    /// Whether `fileName` is a full (renamed) file of any log.
    static func isRotatedFileName(_ fileName: String) -> Bool {
        splitRotated(fileName) != nil
    }

    /// `#vela 2026-11-01 – 2026-11-17 (2).log` → its parts, read from the end.
    static func splitRotated(_ fileName: String) -> (base: String, from: String, to: String, counter: Int)? {
        let ext = ".\(fileExtension)"
        guard fileName.hasSuffix(ext) else { return nil }
        var rest = Substring(fileName.dropLast(ext.count))
        var counter = 1
        if rest.hasSuffix(")"), let open = rest.lastIndex(of: "("), rest[..<open].hasSuffix(" "),
           let number = Int(rest[rest.index(after: open)..<rest.index(before: rest.endIndex)]), number > 1 {
            counter = number
            rest = rest[..<rest.index(before: open)]
        }
        let to = String(rest.suffix(10))
        rest = rest.dropLast(to.count)
        guard rest.hasSuffix(rangeSeparator) else { return nil }
        rest = rest.dropLast(rangeSeparator.count)
        let from = String(rest.suffix(10))
        rest = rest.dropLast(from.count)
        guard rest.hasSuffix(" "), isDay(from), isDay(to) else { return nil }
        let base = String(rest.dropLast())
        return base.isEmpty ? nil : (base, from, to, counter)
    }

    /// `2026-11-17`.
    private static func isDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        return text.count == 10 && parts.count == 3 && parts.map(\.count) == [4, 2, 2] && parts.allSatisfy { $0.allSatisfy(\.isASCII) && Int($0) != nil }
    }
}

/// One folder name per network, kept the same across launches.
///
/// A network's folder is named after it. Two networks with the same name
/// get "Name" and "Name (2)". When a network is renamed its folder name
/// follows (the writer moves the folder), and the names are saved so each
/// network keeps its folder after Vela restarts.
@MainActor
final class ChatLogNetworkFolders {
    /// Network UUID string → folder name.
    private(set) var names: [String: String]
    /// The display name each folder name was made from, so unchanged names
    /// aren't sanitized again for every line.
    private var madeFrom: [UUID: String] = [:]

    init(saved: [String: String]) {
        names = saved
    }

    /// Forgets networks that no longer exist, so a new network with the
    /// same name can have their folder.
    func prune(keeping networkIDs: Set<UUID>) {
        let live = Set(networkIDs.map(\.uuidString))
        names = names.filter { live.contains($0.key) }
    }

    /// The folder name for a network called `displayName`.
    func folderName(for networkID: UUID, displayName: String) -> String {
        let key = networkID.uuidString
        if let current = names[key], madeFrom[networkID] == displayName { return current }
        let wanted = ChatLogNaming.sanitize(displayName)
        madeFrom[networkID] = displayName
        // Unchanged (possibly with a " (2)" another network made it need).
        if let current = names[key], current == wanted || Self.withoutCounter(current) == wanted { return current }
        let taken = Set(names.filter { $0.key != key }.values.map { $0.lowercased() })
        var candidate = wanted
        var counter = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(wanted) (\(counter))"
            counter += 1
        }
        names[key] = candidate
        return candidate
    }

    /// `Libera (2)` → `Libera`.
    nonisolated static func withoutCounter(_ name: String) -> String {
        guard name.hasSuffix(")"), let open = name.lastIndex(of: "("), name[..<open].hasSuffix(" "),
              Int(name[name.index(after: open)..<name.index(before: name.endIndex)]) != nil
        else { return name }
        return String(name[..<name.index(before: open)])
    }
}
