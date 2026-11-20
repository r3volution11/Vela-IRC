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
    /// Network whose "Join Channel…" sheet is showing.
    public var joinChannelNetwork: UUID?
    /// Network awaiting removal confirmation.
    public var networkPendingRemoval: UUID?
    /// The settings editor in Settings → Advanced: UI or JSON view, search
    /// query, and keys to reveal. Shared so the sidebar search, the palette and
    /// "Show in settings editor" links can drive it.
    public let settingsEditor = SettingsEditorState()
    /// The sidebar rail temporarily expanded by hover.
    public var isRailHoverExpanded = false
    /// Requests the input bar to take focus (incremented to trigger).
    public var focusInputToken = 0
    /// Request the message list to scroll to a line id.
    public var scrollTarget: UUID?
    /// The command palette, when open, and which mode it opened in.
    public var commandPalette: CommandPaletteMode?
    /// A nick to put in a buffer's message box (Mention in a user menu).
    public var mentionRequest: MentionRequest?
    /// The "Kick with Reason…" sheet, when open.
    public var kickRequest: KickRequest?
    /// "Leave #vela?" or "Remove #vela?", while it's asked
    /// (`channels.confirmLeave`, `channels.confirmRemove`).
    public var channelConfirmation: ChannelConfirmation?

    public init() {}

    public func focusInput() { focusInputToken &+= 1 }
}

/// Mention someone in a buffer's message box, once per request.
public struct MentionRequest: Equatable {
    public let id = UUID()
    public let bufferID: BufferID
    public let nick: String

    public init(bufferID: BufferID, nick: String) {
        self.bufferID = bufferID
        self.nick = nick
    }
}

/// People to kick (and maybe ban) once you've typed a reason.
public struct KickRequest: Identifiable, Equatable {
    public let id = UUID()
    public let bufferID: BufferID
    public let nicks: [String]
    /// Ban them first (Kick + Ban with Reason…).
    public let ban: Bool
    /// What the reason field starts with (`moderation.kickReason`).
    public let reason: String

    public init(bufferID: BufferID, nicks: [String], ban: Bool, reason: String) {
        self.bufferID = bufferID
        self.nicks = nicks
        self.ban = ban
        self.reason = reason
    }
}

/// Leaving or removing a channel, waiting for you to confirm it.
public struct ChannelConfirmation: Identifiable, Equatable {
    public enum Action: Equatable {
        case leave
        case remove
    }

    public let id = UUID()
    public let action: Action
    public let bufferID: BufferID

    public init(_ action: Action, bufferID: BufferID) {
        self.action = action
        self.bufferID = bufferID
    }
}

/// Modes of the VS Code-style command palette.
public enum CommandPaletteMode: Hashable {
    /// ⇧⌘P: every command (typing filters; the query has no prefix).
    case commands
    /// ⌘P / ⌘K: jump to a channel, conversation or network console.
    case buffers
    /// "Select Theme…": arrowing previews each theme live; Esc reverts.
    case themes
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

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
