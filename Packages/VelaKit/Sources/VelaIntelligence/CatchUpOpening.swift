// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaStore

/// Opening a buffer's Catch me up card: shared by the marker button, the
/// context menu and the palette (VelaUI's `CatchUpActions`), and by
/// `vela://catchup` links and the AppleScript `catch up` command.
extension CatchUpStore {
    /// Messages, actions and notices newer than `marker` (the buffer's New
    /// marker): what a summary would cover. Lines are in time order.
    public nonisolated static func unreadLineCount(_ lines: [ChatLine], after marker: Date?) -> Int {
        guard let marker else { return 0 }
        // Binary search for the first line after the marker.
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time > marker { high = middle } else { low = middle + 1 }
        }
        return lines[low...].reduce(0) { $0 + ($1.kind.isConversation ? 1 : 0) }
    }

    /// Whether there's anything to catch up on: unread lines in a buffer
    /// that isn't on screen, or lines under the open buffer's New marker
    /// (opening it marked them read).
    public static func hasUnread(_ buffer: BufferModel, app: AppModel) -> Bool {
        if app.selectedBufferID == buffer.id {
            return unreadLineCount(buffer.lines, after: buffer.unreadMarkerAfter) > 0
        }
        return buffer.unreadCount > 0
    }

    /// Shows `buffer`'s card under its New marker (where the unread lines
    /// start, when the marker is hidden) and summarizes what's new. Selects
    /// the buffer first when it isn't on screen.
    ///
    /// With nothing new, it shows the buffer's latest summary again (its
    /// stretch has been read since), or a card at the end saying there's
    /// nothing new and when the button comes back.
    ///
    /// - Parameter model: A model chosen for this summary ("Catch Me Up
    ///   With…"); nil uses Catch me up's setting.
    public func openCard(for buffer: BufferModel, session: NetworkSession, app: AppModel, model: AIModelChoice? = nil) {
        // Build the request before selecting: selecting marks the buffer
        // read, but the New marker it places covers the same lines.
        let marker = buffer.unreadMarkerAfter ?? buffer.lastReadAt
        var request = CatchUpRequest(buffer: buffer, session: session, since: marker)
        request.model = model
        let isNew = Self.hasUnread(buffer, app: app) && !request.lines.isEmpty
        if app.selectedBufferID != buffer.id { app.select(buffer) }
        if isNew {
            open(request, marker: buffer.unreadMarkerAfter ?? marker)
        } else if let model, reopen(buffer.id) {
            // Nothing new: the latest stretch again, with the model chosen.
            rerun(buffer.id, with: model)
        } else if !reopen(buffer.id) {
            var nothing = request
            nothing.lines = []
            open(nothing, marker: buffer.lines.last?.time ?? marker)
        }
    }
}
