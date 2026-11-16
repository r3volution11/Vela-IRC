// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A settings list of buffers, such as `media.disabledBuffers`. Each entry is
/// one buffer, `"<networkUUID>/<foldedName>"` (``BufferID/description``), or
/// every buffer of a network, `"<networkUUID>/*"`.
///
/// The network UUID matches case-insensitively, so hand-written lowercase
/// UUIDs work; names compare exactly, as they are already case-folded.
/// Entries that don't parse are kept untouched.
nonisolated public struct BufferScopeList: Sendable, Hashable {
    /// The entries in settings order.
    public private(set) var entries: [String]

    public init(_ entries: [String] = []) {
        self.entries = entries
    }

    /// The entry for a whole network.
    public static func networkEntry(for networkID: UUID) -> String {
        "\(networkID.uuidString)/\(wildcard)"
    }

    /// Whether `bufferID` is listed, by itself or through its network.
    public func contains(_ bufferID: BufferID) -> Bool {
        entries.contains { entry in
            guard let (networkID, name) = Self.parse(entry), networkID == bufferID.networkID else { return false }
            return name == Self.wildcard || name == bufferID.foldedName
        }
    }

    /// Whether the whole network is listed (`"<networkUUID>/*"`).
    public func containsNetwork(_ networkID: UUID) -> Bool {
        entries.contains { Self.parse($0).map { $0.networkID == networkID && $0.name == Self.wildcard } ?? false }
    }

    /// Lists or unlists `bufferID` by itself. Its network's entry is left
    /// alone, so a buffer stays listed while its whole network is.
    public mutating func set(_ listed: Bool, for bufferID: BufferID) {
        entries.removeAll { entry in
            Self.parse(entry).map { $0.networkID == bufferID.networkID && $0.name == bufferID.foldedName } ?? false
        }
        if listed { entries.append(bufferID.description) }
    }

    /// Lists or unlists every buffer of a network. Entries for single buffers
    /// of the network are kept.
    public mutating func set(_ listed: Bool, forNetwork networkID: UUID) {
        entries.removeAll { entry in
            Self.parse(entry).map { $0.networkID == networkID && $0.name == Self.wildcard } ?? false
        }
        if listed { entries.append(Self.networkEntry(for: networkID)) }
    }

    // MARK: Parsing

    private static let wildcard = "*"

    /// `"<uuid>/<name>"` → the UUID and the name (which may itself contain `/`).
    private static func parse(_ entry: String) -> (networkID: UUID, name: String)? {
        guard let slash = entry.firstIndex(of: "/"), let networkID = UUID(uuidString: String(entry[..<slash])) else {
            return nil
        }
        return (networkID, String(entry[entry.index(after: slash)...]))
    }
}
