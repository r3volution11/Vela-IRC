// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaFoundation

/// VS Code-style user settings backed by a hand-editable `settings.json`.
///
/// - The file is JSONC (comments and trailing commas are accepted) holding a
///   flat object of dotted keys. Only keys that were explicitly set are
///   stored; everything else reads as its ``SettingKey`` default.
/// - Unknown keys are preserved when saving.
/// - Changes made in the app are written back after a short debounce
///   (pretty-printed, sorted keys, atomic replace). Comments in the file are
///   not preserved by app-side writes.
/// - External edits are picked up through ``FileWatcher``; the app's own
///   writes are recognized by content and ignored. Changes still pending
///   from the app are re-applied on top of an externally edited file.
/// - A missing file means "all defaults". An invalid file leaves the last
///   good values in place, sets ``lastError``, and blocks app-side writes
///   (they stay pending) until the file parses again, so a half-typed edit
///   is never overwritten.
@MainActor
@Observable
public final class SettingsStore {
    /// Explicitly set values, keyed by dotted setting name.
    public private(set) var values: [String: JSONValue] = [:]
    /// Why the file could not be read or written, if it couldn't.
    public private(set) var lastError: String?

    public let fileURL: URL
    /// Debounce interval for app-side writes.
    @ObservationIgnored public var saveDelay: Duration = .milliseconds(300)

    private enum PendingChange {
        case set(JSONValue)
        case remove
    }

    @ObservationIgnored private var pending: [String: PendingChange] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: FileWatcher?
    /// The file contents last read or written by this store.
    @ObservationIgnored private var lastSeenData: Data?
    @ObservationIgnored private var fileIsInvalid = false

    /// Loads `fileURL` and, if `watchForChanges` is true, starts watching it.
    public init(fileURL: URL, watchForChanges: Bool = true) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        refreshFromDisk(force: true)
        if watchForChanges {
            startWatching()
        }
    }

    // MARK: Typed access

    public subscript<Value>(_ key: SettingKey<Value>) -> Value {
        get { key.value(from: values[key.key]) }
        set { setValue(key.jsonValue(for: newValue), forKey: key.key) }
    }

    /// Whether the user explicitly set `key` (as opposed to using its default).
    public func isSet<Value>(_ key: SettingKey<Value>) -> Bool {
        values[key.key] != nil
    }

    /// Removes an explicit value so the setting reverts to its default.
    public func reset<Value>(_ key: SettingKey<Value>) {
        setValue(nil, forKey: key.key)
    }

    // MARK: Untyped access

    public func value(forKey key: String) -> JSONValue? {
        values[key]
    }

    /// Sets (or, with `nil`, removes) a raw value and schedules a save.
    public func setValue(_ value: JSONValue?, forKey key: String) {
        guard values[key] != value else { return }
        if let value {
            values[key] = value
            pending[key] = .set(value)
        } else {
            values.removeValue(forKey: key)
            pending[key] = .remove
        }
        scheduleSave()
    }

    // MARK: Persistence

    /// Writes pending changes immediately. Call on app termination.
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard !pending.isEmpty else { return }
        // Fold in any external edit the watcher has not delivered yet so it
        // is not clobbered by this write.
        refreshFromDisk(force: false)
        guard !fileIsInvalid else { return }
        do {
            var data = try JSONValue.object(values).prettyPrinted()
            data.append(0x0A)
            if data != lastSeenData {
                try FileSupport.writeAtomically(data, to: fileURL)
                lastSeenData = data
            }
            pending.removeAll()
            lastError = nil
        } catch {
            lastError = "Could not save settings.json: \(error.localizedDescription)"
        }
    }

    /// Re-reads the file now (normally the file watcher does this).
    public func reload() {
        refreshFromDisk(force: true)
        if !pending.isEmpty, !fileIsInvalid {
            scheduleSave()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Reads the file and merges it with pending app-side changes. With
    /// `force == false` an unchanged file (by content) is skipped, which is
    /// how the store ignores its own writes.
    private func refreshFromDisk(force: Bool) {
        let data: Data?
        do {
            data = try FileSupport.readIfPresent(fileURL)
        } catch {
            lastError = "Could not read settings.json: \(error.localizedDescription)"
            return
        }
        if !force, data == lastSeenData { return }
        lastSeenData = data

        guard let data else {
            fileIsInvalid = false
            lastError = nil
            apply(fileValues: [:])
            return
        }
        do {
            let normalized = JSONC.normalize(data)
            let isBlank = normalized.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
            let root = isBlank ? JSONValue.object([:]) : try JSONDecoder().decode(JSONValue.self, from: normalized)
            guard case .object(let object) = root else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [
                    NSLocalizedDescriptionKey: "The top level must be an object.",
                ])
            }
            fileIsInvalid = false
            lastError = nil
            apply(fileValues: object)
        } catch {
            fileIsInvalid = true
            lastError = "settings.json is invalid; keeping previous values. \(Self.describe(error))"
        }
    }

    private func apply(fileValues: [String: JSONValue]) {
        var merged = fileValues
        for (key, change) in pending {
            switch change {
            case .set(let value): merged[key] = value
            case .remove: merged.removeValue(forKey: key)
            }
        }
        if merged != values {
            values = merged
        }
    }

    private func startWatching() {
        let fileName = fileURL.lastPathComponent
        let watcher = FileWatcher(directory: fileURL.deletingLastPathComponent()) { [weak self] urls in
            guard urls.contains(where: { $0.lastPathComponent == fileName }) else { return }
            Task { @MainActor [weak self] in
                self?.handleExternalChange()
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    private func handleExternalChange() {
        refreshFromDisk(force: false)
        if !pending.isEmpty, !fileIsInvalid, saveTask == nil {
            scheduleSave()
        }
    }

    private static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .dataCorrupted(let context):
                let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey]
                return (underlying as? String) ?? context.debugDescription
            default:
                return String(describing: decoding)
            }
        }
        return error.localizedDescription
    }
}
