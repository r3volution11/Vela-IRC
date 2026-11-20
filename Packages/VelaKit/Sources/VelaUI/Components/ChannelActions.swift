// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

/// Leaving, removing, hiding and closing from the window: a tab's ×,
/// middle-click, VoiceOver, the context menus and the command palette.
///
/// On a network without a bouncer:
/// - **Leave** parts a channel and keeps it in the list, dimmed. It comes
///   off the auto-join list; **Join** puts it back.
/// - **Remove** parts it and takes it out of the list and off the auto-join
///   list; it goes to Recently Closed. A tab's × does this.
///
/// Through a bouncer (ZNC or soju):
/// - **Leave** detaches the channel: the bouncer stays in it and keeps its
///   history, and Vela shows it dimmed. **Join** reattaches it. A tab's ×
///   does this, unless `channels.bouncerCloseRemoves` is on.
/// - **Hide** takes a detached channel out of the list, leaving it on the
///   bouncer. A tab's × on a detached channel does this.
/// - **Remove** parts it, so the bouncer forgets it too.
///
/// **Close** takes a private conversation out of the list. Leave and Remove
/// ask first while `channels.confirmLeave` and `channels.confirmRemove` are
/// on. `/part` and `/close` never ask (they go straight to `AppModel`), and
/// `/part` really parts, even through a bouncer. Each can be undone with ⌘Z.
@MainActor
enum ChannelActions {
    /// What a tab's ×, a middle-click or VoiceOver's close action does.
    enum CloseAction: Equatable {
        /// Part a channel and take it out of the list.
        case remove
        /// Through a bouncer: leave the channel in Vela, keeping it on the
        /// bouncer, detached.
        case detach
        /// Through a bouncer: take a detached channel out of the list.
        case hide
        /// A private conversation: close it.
        case closeConversation

        /// The name it goes by in menus and for VoiceOver.
        var title: String {
            switch self {
            case .remove: "Remove Channel"
            case .detach: "Leave Channel"
            case .hide: "Hide Channel"
            case .closeConversation: "Close Conversation"
            }
        }
    }

    /// What closing `buffer`'s tab does. On a network without a bouncer, it
    /// leaves and removes a channel. Through a bouncer, it leaves a channel
    /// you're in (detaching it), hides a detached one and removes one
    /// you're not in; with `removesOnBouncer` (`channels.bouncerCloseRemoves`)
    /// it always removes.
    static func closeAction(for buffer: BufferModel, in session: NetworkSession, removesOnBouncer: Bool) -> CloseAction? {
        switch buffer.kind {
        case .server: return nil
        case .query: return .closeConversation
        case .channel:
            guard session.isBouncer, !removesOnBouncer else { return .remove }
            if session.isIn(buffer) { return .detach }
            return session.canHide(buffer) ? .hide : .remove
        }
    }

    static func closeAction(for buffer: BufferModel, in session: NetworkSession, app: AppModel) -> CloseAction? {
        closeAction(for: buffer, in: session, removesOnBouncer: app.settings[.channelsBouncerCloseRemoves])
    }

    /// A tab's ×, a middle-click or VoiceOver's close action (see
    /// `closeAction(for:in:app:)`).
    static func closeTab(_ buffer: BufferModel, app: AppModel, uiState: UIState) {
        guard let session = app.session(for: buffer.id.networkID),
              let action = closeAction(for: buffer, in: session, app: app) else { return }
        switch action {
        case .remove: remove(buffer, app: app, uiState: uiState)
        case .detach: leave(buffer, app: app, uiState: uiState)
        case .hide: hide(buffer, app: app)
        case .closeConversation: app.close(buffer)
        }
    }

    /// Leave Channel, asking first while `channels.confirmLeave` is on: a
    /// part on a network without a bouncer, a detach through one.
    static func leave(_ channel: BufferModel, app: AppModel, uiState: UIState) {
        guard channel.kind == .channel, let session = app.session(for: channel.id.networkID) else { return }
        let action: ChannelConfirmation.Action = session.isBouncer ? .detach : .leave
        if app.settings[.channelsConfirmLeave] {
            uiState.channelConfirmation = ChannelConfirmation(action, bufferID: channel.id)
        } else {
            perform(action, on: channel, app: app)
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

    /// Hide Channel: a detached bouncer channel out of the list. It doesn't
    /// ask: nothing changes on the bouncer, and it's easy to get back.
    static func hide(_ channel: BufferModel, app: AppModel) {
        app.hide(channel)
    }

    /// Join Channel on a channel you left or detached.
    static func join(_ channel: BufferModel, app: AppModel) {
        app.rejoin(channel)
    }

    /// Leaves, detaches or removes the channel `request` asked about, now
    /// you've said yes. "Don't ask again" turns its setting off.
    static func confirm(_ request: ChannelConfirmation, dontAskAgain: Bool, app: AppModel) {
        if dontAskAgain {
            app.settings[request.action == .remove ? .channelsConfirmRemove : .channelsConfirmLeave] = false
        }
        guard let channel = app.session(for: request.bufferID.networkID)?.buffer(id: request.bufferID) else { return }
        perform(request.action, on: channel, app: app)
    }

    private static func perform(_ action: ChannelConfirmation.Action, on channel: BufferModel, app: AppModel) {
        switch action {
        case .leave: app.leave(channel)
        case .detach: app.detach(channel)
        case .remove: app.close(channel)
        }
    }

    // MARK: Wording

    /// "Leave #vela?" or "Remove #vela?"
    static func question(for request: ChannelConfirmation, app: AppModel) -> String {
        let name = app.session(for: request.bufferID.networkID)?.buffer(id: request.bufferID)?.name ?? "this channel"
        return request.action == .remove ? "Remove \(name)?" : "Leave \(name)?"
    }

    /// What leaving, detaching or removing it does.
    static func explanation(for request: ChannelConfirmation, app: AppModel) -> String {
        let session = app.session(for: request.bufferID.networkID)
        switch request.action {
        case .leave:
            return "You'll stop receiving its messages, and Vela won't join it when you connect. It stays in the list so you can join it again."
        case .detach:
            return "Your bouncer stays in the channel and keeps its history; join it again to catch up."
        case .remove:
            let network = session?.displayName ?? "the network"
            let bouncer = session?.isBouncer ?? false
            return bouncer
                ? "Your bouncer leaves it too and forgets it, and it's taken out of the list and \(network)'s channels. File → Recently Closed brings it back."
                : "It's taken out of the list and \(network)'s channels. File → Recently Closed brings it back."
        }
    }

    static func confirmTitle(_ action: ChannelConfirmation.Action) -> String {
        action == .remove ? "Remove" : "Leave"
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
