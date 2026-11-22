// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Observation
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaIntents
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
    /// The channel name the next Join Channel sheet starts with (a
    /// `vela://join` link), taken when the sheet appears.
    var joinChannelPrefill: String?
    /// Message search, while it's open, and what it opened with.
    var messageSearch: MessageSearchRequest?
    /// A short notice at the top of the main window (a link Vela couldn't follow).
    var automationNotice: AutomationNotice?
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
    /// The latest request for an area of the window to take the keyboard
    /// focus (⌥⌘1–⌥⌘4, F6). The area it names takes the focus when it sees
    /// it, on change or, for one that wasn't on screen yet (the member
    /// list, shown to take it), on appear, and clears it with
    /// `takeFocusRequest(for:)`. The message box goes by `focusInputToken`.
    public private(set) var focusRequest: FocusRequest?
    /// The area with the keyboard focus, as the areas report it (nil: none
    /// of them, e.g. a field in a sheet, or the palette). Read when F6 is
    /// pressed, so not observed.
    @ObservationIgnored public private(set) var focusedArea: FocusArea?
    /// Request the message list to scroll to a line id.
    public var scrollTarget: UUID?
    /// The command palette, when open, and which mode it opened in.
    public var commandPalette: CommandPaletteMode?
    /// A nick to put in a buffer's message box (Mention in a user menu).
    public var mentionRequest: MentionRequest?
    /// The "Kick with Reason…" sheet, when open.
    public var kickRequest: KickRequest?
    /// "Leave #vela?" or "Remove #vela?", while it's asked
    /// (`channels.confirmLeave`, `channels.confirmRemove`). Leaving through a
    /// bouncer is a detach, asked the same way.
    public var channelConfirmation: ChannelConfirmation?
    /// A question about saved message history, asked in the main window
    /// (from the command palette). Settings asks in its own window.
    var historyDialog: HistoryDialog?
    /// A GIF picked for the message box, per buffer: sent with the text.
    var composerGIFs: [BufferID: ComposerGIF] = [:]
    /// Opens or closes the message box's emoji and GIF picker (⇧⌘E);
    /// incremented to trigger.
    var composerPickerToken = 0
    /// A Settings section to scroll to when its pane shows (Media's GIFs).
    var settingsSectionReveal: SettingsReveal?
    /// One of your AI providers waiting for your OK before Vela sends it
    /// messages: the main window's consent sheet.
    var aiConsent: AIConsentRequest?
    /// Where the tabs were last shown outside the title bar, top or bottom,
    /// this session: **Show Channel Title Bar** puts them back there
    /// (`ChannelTitleBar`). Not saved, and read only by that command, so
    /// not observed.
    @ObservationIgnored private(set) var stripTabPlacement: TabStackPlacement?

    public init() {}

    /// The tabs are showing at `placement` (`TabStackView`, on appear).
    func noteStripTabPlacement(_ placement: TabStackPlacement) {
        if placement != .titleBar { stripTabPlacement = placement }
    }

    public func focusInput() { focusInputToken &+= 1 }

    /// ⇧⌘E: the selected buffer's message box opens its picker, or closes it.
    func toggleComposerPicker() { composerPickerToken &+= 1 }

    /// Moves the keyboard focus to `area`.
    public func focus(_ area: FocusArea) {
        if area == .messageBox {
            focusRequest = nil
            focusInput()
        } else {
            focusRequest = FocusRequest(area: area)
        }
    }

    /// Whether there's a request for `area` to take the focus, clearing it:
    /// an area calls it once it has the focus.
    @discardableResult
    public func takeFocusRequest(for area: FocusArea) -> Bool {
        guard focusRequest?.area == area else { return false }
        focusRequest = nil
        return true
    }

    /// An area reports that it has gained (or lost) the keyboard focus.
    public func setFocused(_ area: FocusArea, _ isFocused: Bool) {
        if isFocused {
            focusedArea = area
        } else if focusedArea == area {
            focusedArea = nil
        }
    }
}

/// Mention someone in a buffer's message box, once per request.
/// A section of a Settings pane to show: the section's view has `.id(section)`.
struct SettingsReveal: Equatable {
    var pane: SettingsPane
    var section: String

    static let gifs = SettingsReveal(pane: .media, section: "gifs")
    /// Intelligence's Models: your providers and the default model.
    static let aiModels = SettingsReveal(pane: .intelligence, section: "models")
}

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
        /// Part, and keep the channel in the list (no bouncer).
        case leave
        /// Leave it in Vela, and keep it on the bouncer, detached.
        case detach
        /// Part, and take it out of the list.
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
    /// Pick a model: "AI: Set Default Model…", "Catch Me Up With…",
    /// "Recap With…".
    case models(AIModelPickerPurpose)
}

/// What a model picked in the palette is for.
public enum AIModelPickerPurpose: Hashable {
    /// `intelligence.model`.
    case defaultModel
    /// Catch me up in this buffer, with the model picked.
    case catchUp(BufferID)
    /// A Recap of this scope, with the model picked.
    case recap(RecapScope)
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
