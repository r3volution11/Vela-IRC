// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

/// Leaving, removing and closing from the window: a tab's ×, middle-click,
/// VoiceOver, the context menus and the command palette.
///
/// - **Leave** parts a channel and keeps it in the list, dimmed.
/// - **Remove** takes a channel out of the list and off its network's
///   auto-join list; it goes to Recently Closed.
/// - **Close** takes a private conversation out of the list; it goes to
///   Recently Closed too.
///
/// Leave and Remove ask first while `channels.confirmLeave` and
/// `channels.confirmRemove` are on. `/part` and `/close` never ask (they go
/// straight to `AppModel`). Each can be undone with ⌘Z.
@MainActor
enum ChannelActions {
    /// What a tab's ×, a middle-click or VoiceOver's close action does.
    enum CloseAction: Equatable {
        /// A channel you're in: leave it, keeping it in the list.
        case leave
        /// A channel you're not in (left, kicked): take it out of the list.
        case remove
        /// A private conversation: close it.
        case closeConversation

        var title: String {
            switch self {
            case .leave: "Leave Channel"
            case .remove: "Remove Channel"
            case .closeConversation: "Close Conversation"
            }
        }
    }

    static func closeAction(for buffer: BufferModel, in session: NetworkSession) -> CloseAction? {
        switch buffer.kind {
        case .server: nil
        case .query: .closeConversation
        case .channel: session.isIn(buffer) ? .leave : .remove
        }
    }

    /// A tab's ×, a middle-click or VoiceOver's close action: leaves a
    /// channel you're in, removes one you've left, closes a conversation.
    static func closeTab(_ buffer: BufferModel, app: AppModel, uiState: UIState) {
        guard let session = app.session(for: buffer.id.networkID),
              let action = closeAction(for: buffer, in: session) else { return }
        switch action {
        case .leave: leave(buffer, app: app, uiState: uiState)
        case .remove: remove(buffer, app: app, uiState: uiState)
        case .closeConversation: app.close(buffer)
        }
    }

    /// Leave Channel, asking first while `channels.confirmLeave` is on.
    static func leave(_ channel: BufferModel, app: AppModel, uiState: UIState) {
        guard channel.kind == .channel else { return }
        if app.settings[.channelsConfirmLeave] {
            uiState.channelConfirmation = ChannelConfirmation(.leave, bufferID: channel.id)
        } else {
            app.leave(channel)
        }
    }

    /// Remove Channel…, asking first while `channels.confirmRemove` is on.
    static func remove(_ channel: BufferModel, app: AppModel, uiState: UIState) {
        guard channel.kind == .channel else { return }
        if app.settings[.channelsConfirmRemove] {
            uiState.channelConfirmation = ChannelConfirmation(.remove, bufferID: channel.id)
        } else {
            app.close(channel)
        }
    }

    /// Leaves or removes the channel `request` asked about, now you've said
    /// yes. "Don't ask again" turns its setting off.
    static func confirm(_ request: ChannelConfirmation, dontAskAgain: Bool, app: AppModel) {
        if dontAskAgain {
            app.settings[request.action == .leave ? .channelsConfirmLeave : .channelsConfirmRemove] = false
        }
        guard let channel = app.session(for: request.bufferID.networkID)?.buffer(id: request.bufferID) else { return }
        switch request.action {
        case .leave: app.leave(channel)
        case .remove: app.close(channel)
        }
    }

    // MARK: Wording

    /// "Leave #vela?"
    static func question(for request: ChannelConfirmation, app: AppModel) -> String {
        let name = app.session(for: request.bufferID.networkID)?.buffer(id: request.bufferID)?.name ?? "this channel"
        return request.action == .leave ? "Leave \(name)?" : "Remove \(name)?"
    }

    /// What leaving or removing it does.
    static func explanation(for request: ChannelConfirmation, app: AppModel) -> String {
        let session = app.session(for: request.bufferID.networkID)
        let bouncer = session.map { $0.config.bouncerKind != .none } ?? false
        switch request.action {
        case .leave:
            return bouncer
                ? "You'll stop receiving its messages, and your bouncer leaves it too. It stays in the list so you can join it again."
                : "You'll stop receiving its messages. It stays in the list so you can join it again."
        case .remove:
            let network = session?.displayName ?? "the network"
            return "It's taken out of the list and \(network)'s channels\(bouncer ? ", and your bouncer leaves it" : ""). File → Recently Closed brings it back."
        }
    }

    static func confirmTitle(_ action: ChannelConfirmation.Action) -> String {
        action == .leave ? "Leave" : "Remove"
    }
}

/// The "Leave #vela?" / "Remove #vela?" sheet on the main window, with
/// "Don't ask again". Return confirms; Escape cancels. On a view of its own,
/// so its suppression checkbox stays out of the window's other dialogs.
struct ChannelConfirmationDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @State private var dontAskAgain = false

    var body: some View {
        let request = uiState.channelConfirmation
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .confirmationDialog(
                request.map { ChannelActions.question(for: $0, app: app) } ?? "",
                isPresented: Binding(
                    get: { uiState.channelConfirmation != nil },
                    set: { if !$0 { uiState.channelConfirmation = nil } }
                ),
                titleVisibility: .visible,
                presenting: request
            ) { request in
                Button(ChannelActions.confirmTitle(request.action), role: request.action == .remove ? .destructive : nil) {
                    ChannelActions.confirm(request, dontAskAgain: dontAskAgain, app: app)
                    uiState.channelConfirmation = nil
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    uiState.channelConfirmation = nil
                }
            } message: { request in
                Text(ChannelActions.explanation(for: request, app: app))
            }
            .dialogSuppressionToggle("Don't ask again", isSuppressed: $dontAskAgain)
            .onChange(of: request?.id) { dontAskAgain = false }
    }
}
