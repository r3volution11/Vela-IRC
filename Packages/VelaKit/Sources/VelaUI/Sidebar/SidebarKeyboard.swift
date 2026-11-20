// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore

/// Moving through the sidebar (or the rail) with the keyboard, like Mail's
/// mailbox list: the selected row is where the keyboard is, so ↑ and ↓
/// select as they go, ← and → fold and unfold a network, and typing a
/// name's first letters goes to it.
enum SidebarKeyboard {
    /// A row as the keyboard sees it: a network's header (its console) or
    /// one of its channels or conversations, in the order they're shown.
    struct Row: Equatable {
        let id: BufferID
        let isHeader: Bool
        /// A header whose channels can be folded away.
        let canCollapse: Bool
        /// The names typing can match: a channel's with and without its
        /// `#`, a conversation's nick, a network's name.
        let names: [String]

        var networkID: UUID { id.networkID }
    }

    /// What a key does.
    enum Action: Equatable {
        case select(BufferID)
        case collapse(UUID)
        case expand(UUID)
        /// Return or Esc: on to the message box.
        case focusMessageBox
        /// A key that does nothing here (↑ on the first row): taken, so it
        /// doesn't beep.
        case nothing
    }

    /// The rows shown, top to bottom: every network, with its channels then
    /// conversations unless it's folded away (`collapsed`).
    @MainActor
    static func rows(in app: AppModel, collapsed: NetworkIDSet) -> [Row] {
        var rows: [Row] = []
        for group in app.sidebarGroups {
            for session in [group.network] + group.children {
                let buffers = session.sidebarBuffers
                rows.append(Row(id: session.serverBuffer.id, isHeader: true, canCollapse: !buffers.isEmpty, names: [session.displayName]))
                guard !collapsed.contains(session.id) else { continue }
                let channelTypes = session.isupport.channelTypes
                for buffer in buffers.filter({ $0.kind == .channel }) + buffers.filter({ $0.kind == .query }) {
                    var names = [buffer.name]
                    if buffer.kind == .channel {
                        let bare = buffer.name.drop { channelTypes.contains($0) || $0 == "#" }
                        if !bare.isEmpty { names.insert(String(bare), at: 0) }
                    }
                    rows.append(Row(id: buffer.id, isHeader: false, canCollapse: false, names: names))
                }
            }
        }
        return rows
    }

    /// Where the keyboard is: the selected row or, when it's folded away,
    /// its network's header. Nil with nothing selected.
    @MainActor
    static func cursor(selected: BufferID?, in app: AppModel, collapsed: NetworkIDSet) -> BufferID? {
        guard let selected, let session = app.session(for: selected.networkID) else { return nil }
        let header = session.serverBuffer.id
        if selected == header { return header }
        return collapsed.contains(session.id) || session.isBouncerControl ? header : selected
    }

    /// What `key` does with the keyboard on `cursor` (an index in `rows`,
    /// nil with nothing selected). Letters go through `typeSelect`, typed at
    /// `time`. Nil for a key the sidebar leaves alone.
    static func action(
        for key: NavigationKey,
        rows: [Row],
        cursor: Int?,
        collapsed: NetworkIDSet,
        typeSelect: inout TypeSelect,
        time: TimeInterval
    ) -> Action? {
        if case .text = key {} else { typeSelect.reset() }
        guard !rows.isEmpty else {
            switch key {
            case .return, .escape, .space, .menu: return nil
            default: return .nothing
            }
        }
        let last = rows.count - 1
        func select(_ index: Int) -> Action {
            index == cursor ? .nothing : .select(rows[index].id)
        }
        switch key {
        case .up:
            guard let cursor else { return select(last) }
            return select(max(0, cursor - 1))
        case .down:
            guard let cursor else { return select(0) }
            return select(min(last, cursor + 1))
        case .home:
            return select(0)
        case .end:
            return select(last)
        case .left:
            guard let cursor else { return .nothing }
            let row = rows[cursor]
            if !row.isHeader {
                // Out to the network, like an outline: ← again folds it.
                guard let header = rows.firstIndex(where: { $0.isHeader && $0.networkID == row.networkID }) else { return .nothing }
                return select(header)
            }
            return row.canCollapse && !collapsed.contains(row.networkID) ? .collapse(row.networkID) : .nothing
        case .right:
            guard let cursor else { return .nothing }
            let row = rows[cursor]
            return row.isHeader && row.canCollapse && collapsed.contains(row.networkID) ? .expand(row.networkID) : .nothing
        case .return, .escape:
            return cursor == nil ? nil : .focusMessageBox
        case .text(let text):
            typeSelect.type(text, at: time)
            guard let index = typeSelect.match(in: rows.map(\.names), current: cursor) else { return .nothing }
            return select(index)
        case .pageUp, .pageDown, .space, .menu:
            return nil
        }
    }
}
