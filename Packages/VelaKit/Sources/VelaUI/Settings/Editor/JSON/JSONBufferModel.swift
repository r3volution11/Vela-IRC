// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The JSON view's buffer against settings.json on disk: whether it has
/// unsaved edits, and what to do when the file changes underneath it.
///
/// ``SettingsStore/fileRevision`` bumps on every change to the file, the
/// view's own saves included, so the model remembers the revision its
/// ``baseline`` came from and reads the new one after each save.
///
/// - Clean buffer, file changed: reload silently.
/// - Dirty buffer, file changed: a conflict ("settings.json changed on
///   disk. Reload · Keep My Changes"), unless the file now holds exactly
///   the buffer's text.
nonisolated struct JSONBufferModel: Equatable, Sendable {
    /// A change on disk that arrived while the buffer had unsaved edits.
    struct Conflict: Equatable, Sendable {
        var diskText: String
        var revision: Int
    }

    /// What the view should do after ``fileChanged(diskText:revision:buffer:)``.
    enum Response: Equatable, Sendable {
        /// Nothing: the revision was already known, or the file now matches
        /// the buffer.
        case none
        /// Replace the buffer's text with this (keeping the selection and
        /// scroll position as far as possible).
        case reload(String)
        /// Show the conflict banner.
        case conflict
    }

    /// The text on disk that the buffer is compared against.
    private(set) var baseline: String
    /// The store's ``SettingsStore/fileRevision`` for ``baseline``.
    private(set) var baselineRevision: Int
    /// Set while the conflict banner shows.
    private(set) var conflict: Conflict?

    init(diskText: String, revision: Int) {
        baseline = diskText
        baselineRevision = revision
    }

    /// True when `buffer` differs from the file it was loaded from.
    func isDirty(_ buffer: String) -> Bool {
        buffer.utf16.count != baseline.utf16.count || buffer != baseline
    }

    /// The file changed (or might have): `revision` is the store's current
    /// revision and `diskText` its current text.
    mutating func fileChanged(diskText: String, revision: Int, buffer: String) -> Response {
        guard revision != baselineRevision, revision != conflict?.revision else { return .none }
        if !isDirty(buffer) {
            baseline = diskText
            baselineRevision = revision
            conflict = nil
            return diskText == buffer ? .none : .reload(diskText)
        }
        if diskText == buffer {
            // Someone saved exactly these edits (or undid theirs).
            baseline = diskText
            baselineRevision = revision
            conflict = nil
            return .none
        }
        conflict = Conflict(diskText: diskText, revision: revision)
        return .conflict
    }

    /// The buffer was written to disk; `revision` is the store's revision
    /// read right after the save. Resolves any conflict (the save wins).
    mutating func saved(_ text: String, revision: Int) {
        baseline = text
        baselineRevision = revision
        conflict = nil
    }

    /// "Reload": the text to put in the buffer (the file's), now clean.
    mutating func reloadFromConflict() -> String? {
        guard let conflict else { return nil }
        baseline = conflict.diskText
        baselineRevision = conflict.revision
        self.conflict = nil
        return baseline
    }

    /// "Keep My Changes": the buffer stays as it is, still unsaved, and is
    /// compared against the file's new text from now on.
    mutating func keepMine() {
        guard let conflict else { return }
        baseline = conflict.diskText
        baselineRevision = conflict.revision
        self.conflict = nil
    }

    /// "Revert" (and "Discard"): the text to put back, the file's latest.
    mutating func revert() -> String {
        if let text = reloadFromConflict() { return text }
        return baseline
    }
}
