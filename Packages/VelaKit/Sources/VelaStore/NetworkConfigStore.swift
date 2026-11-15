// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaFoundation

/// Owns `networks.json`, the list of saved networks.
///
/// File format (JSONC is accepted on read):
/// ```json
/// { "version": 1, "networks": [ { "id": "…", "name": "Libera", … } ] }
/// ```
/// A bare top-level array of networks is also accepted. Unknown top-level
/// keys and unknown per-network keys are preserved when saving.
@MainActor
@Observable
public final class NetworkConfigStore {
    public static let fileFormatVersion = 1

    /// All networks, sorted by `sortOrder` (ties broken by `createdAt`).
    public private(set) var networks: [NetworkConfig] = []

    /// The last load/save failure, or `nil` after a successful operation.
    public private(set) var lastError: String?

    public let fileURL: URL
    @ObservationIgnored private var extraTopLevel: [String: JSONValue] = [:]
    /// Set when the file on disk could not be parsed; the next save first
    /// moves it aside so hand edits are never silently destroyed.
    @ObservationIgnored private var fileNeedsBackup = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Reads the file. A missing file yields an empty list; malformed
    /// individual entries are skipped; an unparsable file throws and leaves
    /// the current list untouched.
    public func load() throws {
        guard let data = try FileSupport.readIfPresent(fileURL) else {
            networks = []
            extraTopLevel = [:]
            fileNeedsBackup = false
            lastError = nil
            return
        }
        let root: JSONValue
        do {
            root = try JSONC.value(from: data)
        } catch {
            fileNeedsBackup = true
            lastError = "networks.json is not valid JSON: \(error.localizedDescription)"
            throw error
        }

        var entries: [JSONValue] = []
        var extras: [String: JSONValue] = [:]
        switch root {
        case .array(let array):
            entries = array
        case .object(var object):
            entries = object.removeValue(forKey: "networks")?.arrayValue ?? []
            object.removeValue(forKey: "version")
            extras = object
        default:
            fileNeedsBackup = true
            let error = CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: fileURL])
            lastError = "networks.json has an unexpected top-level value."
            throw error
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        var loaded: [NetworkConfig] = []
        var seen = Set<UUID>()
        for entry in entries {
            guard case .object = entry,
                  let entryData = try? encoder.encode(entry),
                  let config = try? decoder.decode(NetworkConfig.self, from: entryData),
                  seen.insert(config.id).inserted
            else { continue }
            loaded.append(config)
        }

        networks = Self.sorted(loaded)
        extraTopLevel = extras
        fileNeedsBackup = false
        lastError = nil
    }

    /// Returns the network with `id`, if any.
    public func network(id: UUID) -> NetworkConfig? {
        networks.first { $0.id == id }
    }

    /// Inserts or replaces a network (matched by `id`), bumps `modifiedAt`
    /// and saves atomically. New networks are appended after the existing
    /// ones (their `sortOrder` is reassigned); use ``move(fromOffsets:toOffset:)``
    /// to reorder. Updated networks keep the `sortOrder` they carry.
    public func upsert(_ config: NetworkConfig) {
        var config = config
        config.modifiedAt = Date()
        if let index = networks.firstIndex(where: { $0.id == config.id }) {
            networks[index] = config
        } else {
            config.sortOrder = (networks.map(\.sortOrder).max() ?? -1) + 1
            networks.append(config)
        }
        networks = Self.sorted(networks)
        save()
    }

    /// Removes the network with `id`. Its bouncer children are not removed
    /// automatically; the app layer decides what to do with them.
    public func remove(id: UUID) {
        guard let index = networks.firstIndex(where: { $0.id == id }) else { return }
        networks.remove(at: index)
        save()
    }

    /// SwiftUI `onMove` semantics. Renumbers `sortOrder` to 0..<n and bumps
    /// `modifiedAt` on every network whose position changed.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = networks
        reordered.velaMove(fromOffsets: source, toOffset: destination)
        let now = Date()
        for index in reordered.indices where reordered[index].sortOrder != index {
            reordered[index].sortOrder = index
            reordered[index].modifiedAt = now
        }
        guard reordered != networks else { return }
        networks = reordered
        save()
    }

    // MARK: Saving

    private func save() {
        do {
            if fileNeedsBackup, FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                let stamp = ISODate.string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let backup = fileURL.deletingPathExtension()
                    .appendingPathExtension("invalid-\(stamp).json")
                try? FileManager.default.moveItem(at: fileURL, to: backup)
            }
            fileNeedsBackup = false
            try FileSupport.writeAtomically(encodedFile(), to: fileURL)
            lastError = nil
        } catch {
            lastError = "Could not save networks.json: \(error.localizedDescription)"
        }
    }

    private func encodedFile() throws -> Data {
        let networkValues = try networks.map { config -> JSONValue in
            let data = try JSONEncoder().encode(config)
            return try JSONDecoder().decode(JSONValue.self, from: data)
        }
        var object = extraTopLevel
        object["version"] = .number(Double(Self.fileFormatVersion))
        object["networks"] = .array(networkValues)
        var data = try JSONValue.object(object).prettyPrinted()
        data.append(0x0A)
        return data
    }

    private static func sorted(_ configs: [NetworkConfig]) -> [NetworkConfig] {
        configs.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

extension Array {
    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, without
    /// importing SwiftUI.
    mutating func velaMove(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { self[$0] }
        let insertionPoint = destination - valid.filter { $0 < destination }.count
        for index in valid.reversed() {
            remove(at: index)
        }
        insert(contentsOf: moving, at: Swift.max(0, Swift.min(insertionPoint, count)))
    }
}
