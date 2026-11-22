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
///   stored; everything else reads as its ``SettingKey`` default. With
///   duplicate keys, the last one wins (as in VS Code).
/// - Unknown keys are preserved when saving.
/// - Changes made in the app are written back after a short debounce as
///   minimal edits to the file's text (``JSONCEditing``): comments,
///   indentation, line endings and trailing commas are kept, a changed value
///   is replaced in place, a removed key takes its line (and its trailing
///   comment) with it, and a new key is appended after the last one. Object
///   values are compared member by member, so comments inside
///   `appearance.colorCustomizations` and `media.siteRules` survive too. A
///   missing or blank file gets a fresh pretty-printed object. Writes are
///   atomic.
/// - External edits are picked up through ``FileWatcher``; the app's own
///   writes are recognized by content and ignored. Changes still pending
///   from the app are re-applied on top of an externally edited file.
/// - A missing file means "all defaults". An invalid file leaves the last
///   good values in place, sets ``lastError``, and blocks app-side writes
///   (they stay pending) until the file parses again, so a half-typed edit
///   is never overwritten.
/// - The settings editor's JSON view reads and writes the text itself with
///   ``fileText()`` and ``saveFileText(_:)``, and watches ``fileRevision``
///   to notice changes on disk.
@MainActor
@Observable
public final class SettingsStore {
    /// Explicitly set values, keyed by dotted setting name.
    public private(set) var values: [String: JSONValue] = [:]
    /// Why the file could not be read or written, if it couldn't.
    public private(set) var lastError: String?
    /// Bumped whenever settings.json's contents change: app-side writes,
    /// ``saveFileText(_:)``, and edits made elsewhere (once the file watcher
    /// or ``reload()`` notices them). Starts at 0 for the contents read at
    /// launch. Observable.
    public private(set) var fileRevision = 0

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
    /// True when the last write had to rewrite the whole file because the
    /// minimal edits didn't produce the expected values (a safety net that
    /// should never be needed). For tests.
    @ObservationIgnored private(set) var lastWriteRewroteFile = false

    /// Loads `fileURL` and, if `watchForChanges` is true, starts watching it.
    public init(fileURL: URL, watchForChanges: Bool = true) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        refreshFromDisk(force: true)
        fileRevision = 0
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

    /// Sets (or, with `nil`, removes) several raw values as one change:
    /// ``values`` is replaced once, so views watching settings update once,
    /// and one save is scheduled. Keys whose value doesn't change are left
    /// alone.
    public func setValues(_ changes: [String: JSONValue?]) {
        var updated = values
        for (key, value) in changes where updated[key] != value {
            if let value {
                updated[key] = value
                pending[key] = .set(value)
            } else {
                updated.removeValue(forKey: key)
                pending[key] = .remove
            }
        }
        guard updated != values else { return }
        values = updated
        scheduleSave()
    }

    // MARK: Migration

    /// Upgrades keys written by older versions of Vela (see
    /// ``SettingsMigration``) and, if anything changed, saves right away.
    /// Idempotent, so it is safe to call on every launch. Returns the changes made.
    @discardableResult
    public func applyMigrations(_ rules: [SettingsMigration.Rule] = SettingsMigration.rules) -> [SettingsChange] {
        let changes = SettingsMigration.changes(for: values, rules: rules)
        guard !changes.isEmpty else { return [] }
        for change in changes {
            setValue(change.value, forKey: change.key)
        }
        flush()
        return changes
    }

    // MARK: Persistence

    /// Writes pending changes immediately, as minimal edits to the file's
    /// text. Call on app termination.
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard !pending.isEmpty else { return }
        // Fold in any external edit the watcher has not delivered yet so it
        // is not clobbered by this write.
        refreshFromDisk(force: false)
        guard !fileIsInvalid else { return }
        do {
            let data = Data(try editedText().utf8)
            if data != lastSeenData ?? Data() {
                try FileSupport.writeAtomically(data, to: fileURL)
                noteContents(data)
            }
            pending.removeAll()
            lastError = nil
        } catch {
            lastError = "Could not save settings.json: \(error.localizedDescription)"
        }
    }

    /// The current file text with the pending changes applied as minimal
    /// edits. Falls back to rewriting the whole file if the edits don't
    /// produce exactly ``values`` (which they should always do).
    private func editedText() throws -> String {
        let text = lastSeenData.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let changes: [SettingsFileWriter.Change] = pending.map { key, change in
            switch change {
            case .set(let value): (key, value)
            case .remove: (key, nil)
            }
        }
        lastWriteRewroteFile = false
        if let edited = try? SettingsFileWriter.text(applying: changes, to: text, fullValues: values),
           case .success(let written) = Self.parse(edited),
           written == values
        {
            return edited
        }
        lastWriteRewroteFile = true
        let format = JSONCFormat(detectingIn: JSONCDocument(text))
        return JSONCEditing.format(.object(values), format: format) + format.lineEnding
    }

    /// Re-reads the file now (normally the file watcher does this).
    public func reload() {
        refreshFromDisk(force: true)
        if !pending.isEmpty, !fileIsInvalid {
            scheduleSave()
        }
    }

    // MARK: settings.json text (the settings editor's JSON view)

    /// settings.json's text as it is on disk, for editing it in the app;
    /// `"{\n}\n"` when the file is missing or blank.
    ///
    /// Changes still waiting to be written are written first (unless the
    /// file is invalid), so the text matches ``values``.
    public func fileText() -> String {
        if pending.isEmpty {
            refreshFromDisk(force: false)
        } else {
            flush()
        }
        let text = lastSeenData.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return text.allSatisfy(\.isWhitespace) ? "{\n}\n" : text
    }

    /// Writes `text` to settings.json exactly as given, then reloads it.
    ///
    /// Invalid text is saved too: the store then keeps the last good
    /// values, sets ``lastError`` and holds app-side writes until the file
    /// is fixed, just as with an invalid edit made in another editor.
    /// Changes the app made meanwhile are re-applied on top afterwards.
    /// ``fileRevision`` is bumped (read it afterwards as the new baseline).
    ///
    /// - Throws: When the file can't be written.
    public func saveFileText(_ text: String) throws {
        saveTask?.cancel()
        saveTask = nil
        do {
            try FileSupport.writeAtomically(Data(text.utf8), to: fileURL)
        } catch {
            lastError = "Could not save settings.json: \(error.localizedDescription)"
            if !pending.isEmpty { scheduleSave() }
            throw error
        }
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
        noteContents(data)

        guard let data else {
            fileIsInvalid = false
            lastError = nil
            apply(fileValues: [:])
            return
        }
        switch Self.parse(data) {
        case .success(let object):
            fileIsInvalid = false
            lastError = nil
            apply(fileValues: object)
        case .failure(let problem):
            fileIsInvalid = true
            lastError = "settings.json is invalid; keeping previous values. \(problem.message)"
        }
    }

    /// Records the file's contents, bumping ``fileRevision`` when they changed.
    private func noteContents(_ data: Data?) {
        if data != lastSeenData { fileRevision &+= 1 }
        lastSeenData = data
    }

    private struct ParseProblem: Error {
        let message: String
    }

    /// The top-level object of settings.json's contents. Blank and
    /// comment-only files are empty; anything with a syntax error, or whose
    /// top level isn't an object, fails.
    private static func parse(_ data: Data) -> Result<[String: JSONValue], ParseProblem> {
        parse(String(decoding: data, as: UTF8.self))
    }

    private static func parse(_ text: String) -> Result<[String: JSONValue], ParseProblem> {
        let document = JSONCDocument(text)
        if let error = document.errors.first {
            let (line, column) = document.lineAndColumn(at: error.range.location)
            return .failure(ParseProblem(message: "Line \(line), column \(column): \(error.message)"))
        }
        guard let root = document.root else { return .success([:]) }
        guard root.kind == .object, case .object(let object)? = root.jsonValue else {
            return .failure(ParseProblem(message: "The top level must be an object."))
        }
        return .success(object)
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
}
