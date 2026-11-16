// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import VelaCore

/// Lines sent from each buffer's composer, oldest first, for ↑/↓ recall.
/// In memory only; it lasts for the app session.
final class InputHistoryStore {
    static let shared = InputHistoryStore()

    static let limit = 200
    private var entries: [BufferID: [String]] = [:]

    private init() {}

    func entries(for buffer: BufferID) -> [String] {
        entries[buffer] ?? []
    }

    func push(_ text: String, for buffer: BufferID) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var list = entries[buffer] ?? []
        if list.last == text { return }
        list.append(text)
        if list.count > Self.limit { list.removeFirst(list.count - Self.limit) }
        entries[buffer] = list
    }
}

/// Where the composer is while walking through history.
struct InputHistoryCursor {
    /// Index into the buffer's history, or nil while editing a fresh line.
    var index: Int?
    /// The unsent text to restore after walking back down past the newest entry.
    var stash = ""

    /// The entry before the current one, or nil at the oldest entry.
    mutating func previous(in history: [String], current text: String) -> String? {
        guard !history.isEmpty else { return nil }
        let next = (index ?? history.count) - 1
        guard next >= 0 else { return nil }
        if index == nil { stash = text }
        index = next
        return history[next]
    }

    /// The entry after the current one, the stashed draft past the newest,
    /// or nil when not walking history.
    mutating func next(in history: [String]) -> String? {
        guard let current = index else { return nil }
        if current + 1 < history.count {
            index = current + 1
            return history[current + 1]
        }
        index = nil
        defer { stash = "" }
        return stash
    }

    mutating func reset() {
        index = nil
        stash = ""
    }
}
