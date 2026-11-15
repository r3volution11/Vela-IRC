// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Observation
import SwiftUI
import VelaCore
import VelaStore

/// Window-level UI state that isn't persisted in settings.json.
@Observable
public final class UIState {
    /// Message being replied to, per buffer.
    public var replyTargets: [BufferID: ChatLine] = [:]
    /// Unsent input text, per buffer.
    public var drafts: [BufferID: String] = [:]
    /// Network editor sheet: `.new` or an existing network's id.
    public var networkEditor: NetworkEditorTarget?
    /// The sidebar rail temporarily expanded by hover.
    public var isRailHoverExpanded = false
    /// Requests the input bar to take focus (incremented to trigger).
    public var focusInputToken = 0
    /// Request the message list to scroll to a line id.
    public var scrollTarget: UUID?

    public init() {}

    public func focusInput() { focusInputToken &+= 1 }
}

public enum NetworkEditorTarget: Identifiable, Hashable {
    case new
    case existing(UUID)

    public var id: String {
        switch self {
        case .new: "new"
        case .existing(let id): id.uuidString
        }
    }
}
