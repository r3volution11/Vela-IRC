// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaIRC
import VelaStore
import VelaTheme

// The user (nick) menu: one `UserMenu` from VelaCore, shown by SwiftUI
// context menus (the member list, nicks in message headers, a message's
// menu) and by AppKit (a nick right-clicked in message text). Both run
// their items through `UserMenuActions`.

// MARK: Actions

/// Does what a user menu item says, for the people it's for, in a buffer.
/// What goes to the server takes the same path as the slash commands
/// (`NetworkSession.perform(_:on:in:)`); the rest happens here: the
/// pasteboard, the message box, the reason sheet.
@MainActor
struct UserMenuActions {
    let app: AppModel
    let uiState: UIState
    let session: NetworkSession
    let buffer: BufferModel

    /// The menu for `targets`.
    func menu(for targets: [UserMenuTarget]) -> UserMenu {
        let menu = session.userMenu(for: targets, in: buffer)
        return RecapActions.isOffered(app.settings) ? menu.addingRecap(for: targets) : menu
    }

    /// `nick` as a menu sees them here (`userHost` from one of their
    /// messages, for someone who has left).
    func target(nick: String, userHost: String? = nil) -> UserMenuTarget {
        session.userMenuTarget(nick: nick, in: buffer, userHost: userHost)
    }

    func perform(_ action: UserAction, on targets: [UserMenuTarget]) {
        guard let first = targets.first else { return }
        switch action {
        case .message:
            // Opens the conversation here, so it shows in this window.
            app.select(session.ensureBuffer(name: first.nick, kind: .query))
        case .mention:
            uiState.mentionRequest = MentionRequest(bufferID: buffer.id, nick: first.nick)
        case .copyNick:
            copy(targets.map(\.nick).joined(separator: " "))
        case .copyHostMask:
            if let mask = first.hostMask { copy(mask) }
        case .recap:
            // Their conversations across the network: channels and your
            // private conversation with them.
            RecapWindowRouter.shared?.open(RecapWindowValue(scope: RecapScope(place: .network(session.id), person: first.nick)))
        case .kickWithReason, .kickBanWithReason:
            uiState.kickRequest = KickRequest(
                bufferID: buffer.id,
                nicks: targets.map(\.nick),
                ban: action == .kickBanWithReason,
                reason: app.settings[.moderationKickReason]
            )
        default:
            session.perform(action, on: targets, in: buffer)
        }
    }

    private func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: Nicks in message text

    /// The menu for a word right-clicked in `line`'s text, when it's a
    /// nick: the author's, in the `<nick>` (or `* nick`) before the text,
    /// which is the first `prefixLength` UTF-16 characters; anyone in the
    /// channel, or the person a conversation is with, elsewhere (the nicks
    /// `chat.colorNicksInText` colors). Nil for other words, which get the
    /// message's menu.
    func menu(forWord word: String, range: Range<Int>, in line: ChatLine, prefixLength: Int) -> UserMenu.Resolved? {
        let mapping = session.isupport.caseMapping
        let target: UserMenuTarget
        if range.lowerBound < prefixLength, let author = line.nick, mapping.equal(word, author) {
            target = self.target(nick: author, userHost: line.userHost)
        } else if buffer.kind == .channel, let member = buffer.member(named: word, caseMapping: mapping) {
            target = self.target(nick: member.nick)
        } else if buffer.kind == .query, mapping.fold(word) == buffer.id.foldedName {
            target = self.target(nick: buffer.name)
        } else {
            return nil
        }
        return UserMenu.Resolved(menu: menu(for: [target]), targets: [target])
    }

    /// An AppKit menu for `resolved`, running its items here.
    func nsMenu(_ resolved: UserMenu.Resolved) -> NSMenu {
        UserMenuAppKit.menu(resolved.menu) { action in perform(action, on: resolved.targets) }
    }
}

extension UserMenu {
    /// A menu with the people it's for.
    struct Resolved {
        let menu: UserMenu
        let targets: [UserMenuTarget]
    }
}

// MARK: SwiftUI

/// A user menu's items, for `.contextMenu` or a `Menu`.
struct UserMenuContent: View {
    let menu: UserMenu
    let perform: (UserAction) -> Void

    var body: some View {
        ForEach(Array(menu.sections.enumerated()), id: \.offset) { index, section in
            if index > 0 { Divider() }
            ForEach(section, id: \.self) { entry in
                UserMenuEntryView(entry: entry, perform: perform)
            }
        }
    }
}

private struct UserMenuEntryView: View {
    let entry: UserMenuEntry
    let perform: (UserAction) -> Void

    var body: some View {
        switch entry {
        case .item(let item):
            Button(role: item.isDestructive ? .destructive : nil) {
                perform(item.action)
            } label: {
                if let image = item.systemImage {
                    Label(item.title, systemImage: image)
                } else {
                    Text(item.title)
                }
            }
            .disabled(!item.isEnabled)
        case .submenu(let title, let image, let entries):
            Menu {
                ForEach(entries, id: \.self) { entry in
                    UserMenuEntryView(entry: entry, perform: perform)
                }
            } label: {
                if let image {
                    Label(title, systemImage: image)
                } else {
                    Text(title)
                }
            }
        }
    }
}

/// The user menu for `nick` (a message's author) in the message list's
/// buffer. Built when the menu opens, so it shows the current state.
struct NickUserMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(MessageListController.self) private var controller
    let nick: String
    let userHost: String?

    var body: some View {
        let actions = UserMenuActions(app: app, uiState: uiState, session: controller.session, buffer: controller.buffer)
        let target = actions.target(nick: nick, userHost: userHost)
        UserMenuContent(menu: actions.menu(for: [target])) { actions.perform($0, on: [target]) }
    }
}

extension View {
    /// Right-clicking this view (a nick or avatar in a message) opens the
    /// user menu for `nick`, rather than the message's.
    func nickContextMenu(_ nick: String?, userHost: String?) -> some View {
        modifier(NickContextMenuModifier(nick: nick, userHost: userHost))
    }
}

private struct NickContextMenuModifier: ViewModifier {
    let nick: String?
    let userHost: String?

    func body(content: Content) -> some View {
        if let nick, !nick.isEmpty {
            content.contextMenu { NickUserMenu(nick: nick, userHost: userHost) }
        } else {
            content
        }
    }
}

// MARK: AppKit

/// Builds `NSMenu`s from user menus, for right-clicks AppKit handles.
@MainActor
enum UserMenuAppKit {
    static func menu(_ userMenu: UserMenu, perform: @escaping (UserAction) -> Void) -> NSMenu {
        let menu = NSMenu(title: userMenu.title)
        menu.autoenablesItems = false
        for (index, section) in userMenu.sections.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for entry in section { menu.addItem(item(for: entry, perform: perform)) }
        }
        return menu
    }

    private static func item(for entry: UserMenuEntry, perform: @escaping (UserAction) -> Void) -> NSMenuItem {
        switch entry {
        case .item(let item):
            let menuItem = MenuItemHandler.item(title: item.title) { perform(item.action) }
            menuItem.isEnabled = item.isEnabled
            menuItem.image = item.systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            return menuItem
        case .submenu(let title, let image, let entries):
            let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            menuItem.image = image.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            let submenu = NSMenu(title: title)
            submenu.autoenablesItems = false
            for entry in entries { submenu.addItem(self.item(for: entry, perform: perform)) }
            menuItem.submenu = submenu
            return menuItem
        }
    }
}

/// Runs a menu item's closure. The item keeps it (as its represented
/// object), since an item's target is weak.
final class MenuItemHandler: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run(_ sender: Any?) {
        handler()
    }

    /// A menu item titled `title` that runs `handler`.
    static func item(title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let target = MenuItemHandler(handler)
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        return item
    }
}

// MARK: Kick with a reason

/// "Kick with Reason…" and "Kick + Ban with Reason…": the reason, filled
/// in with `moderation.kickReason`. Return kicks; Esc cancels.
struct KickReasonSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let request: KickRequest

    @State private var reason: String
    @FocusState private var reasonFocused: Bool

    init(request: KickRequest) {
        self.request = request
        _reason = State(initialValue: request.reason)
    }

    var body: some View {
        let buffer = app.session(for: request.bufferID.networkID)?.buffer(id: request.bufferID)
        VStack(alignment: .leading, spacing: 14) {
            Text(Self.title(for: request, channel: buffer?.name))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.popoverForeground])
            TextField("Reason", text: $reason, prompt: Text("No reason"))
                .textFieldStyle(.roundedBorder)
                .focused($reasonFocused)
                .onSubmit(kick)
                .accessibilityLabel("Reason")
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(ThemedButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(request.ban ? "Kick + Ban" : "Kick", action: kick)
                    .buttonStyle(ThemedButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(theme[ThemeKey.popoverBackground])
        .onAppear { reasonFocused = true }
    }

    /// "Kick wren from #vela", "Kick and ban 3 people from #vela".
    static func title(for request: KickRequest, channel: String?) -> String {
        let who = request.nicks.count == 1 ? request.nicks[0] : "\(request.nicks.count) people"
        let verb = request.ban ? "Kick and ban" : "Kick"
        return channel.map { "\(verb) \(who) from \($0)" } ?? "\(verb) \(who)"
    }

    private func kick() {
        defer { dismiss() }
        guard let session = app.session(for: request.bufferID.networkID),
              let buffer = session.buffer(id: request.bufferID)
        else { return }
        // Typed (even cleared) reasons are used as they are.
        let reason = reason.trimmingCharacters(in: .whitespaces)
        if request.ban {
            session.execute(.kickBan(nicks: request.nicks, reason: reason), in: buffer)
        } else {
            for nick in request.nicks { session.execute(.kick(nick: nick, reason: reason), in: buffer) }
        }
    }
}
