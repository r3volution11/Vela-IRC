// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaIRC

/// Something you can do to someone from their menu: in the member list, on
/// their nick in a message, or in a message's menu under their name.
nonisolated public enum UserAction: Hashable, Sendable {
    /// Open a private conversation.
    case message
    /// Put their nick in the message box.
    case mention
    case whois
    /// CTCP PING, showing the round trip when they answer.
    case ping
    /// Another CTCP request: `VERSION`, `TIME` or `CLIENTINFO`.
    case ctcp(String)
    /// Invite them to one of your other channels.
    case invite(channel: String)
    /// Copy their nick (everyone's, for several people).
    case copyNick
    /// Copy `nick!user@host`.
    case copyHostMask
    case ignore
    case unignore
    /// Give (`+`) or take (`-`) a membership mode such as `o` or `v`.
    case mode(sign: Character, mode: Character)
    /// Kick with the default reason (`moderation.kickReason`).
    case kick
    /// Ask for a reason, then kick.
    case kickWithReason
    case ban
    /// Ban, then kick, with the default reason.
    case kickBan
    /// Ask for a reason, then ban and kick.
    case kickBanWithReason
    case quiet
    case unquiet
    /// Open a Recap of conversations with them.
    case recap

    /// Actions the app does itself (the pasteboard, the message box, a
    /// sheet) rather than by sending something.
    public var isHandledByApp: Bool {
        switch self {
        case .mention, .copyNick, .copyHostMask, .kickWithReason, .kickBanWithReason, .recap: true
        default: false
        }
    }
}

/// One item of a user menu.
nonisolated public struct UserMenuItem: Hashable, Sendable, Identifiable {
    public var action: UserAction
    public var title: String
    /// An SF Symbol, for menus that show icons.
    public var systemImage: String?
    /// False for things that need a connection while you're offline.
    public var isEnabled: Bool
    /// Kicks and bans.
    public var isDestructive: Bool

    public var id: UserAction { action }

    public init(action: UserAction, title: String, systemImage: String? = nil, isEnabled: Bool = true, isDestructive: Bool = false) {
        self.action = action
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
    }
}

nonisolated public indirect enum UserMenuEntry: Hashable, Sendable {
    case item(UserMenuItem)
    case submenu(title: String, systemImage: String?, entries: [UserMenuEntry])
}

/// Someone a user menu is for.
nonisolated public struct UserMenuTarget: Hashable, Sendable {
    public var nick: String
    /// Their membership modes in the menu's channel (`o`, `v`…); empty
    /// when they have none or aren't there.
    public var modes: Set<Character>
    /// `user@host`, when known.
    public var userHost: String?
    public var isSelf: Bool
    /// They're in the menu's channel.
    public var isMember: Bool
    /// One of the network's ignore masks matches them.
    public var isIgnored: Bool

    public init(nick: String, modes: Set<Character> = [], userHost: String? = nil, isSelf: Bool = false, isMember: Bool = true, isIgnored: Bool = false) {
        self.nick = nick
        self.modes = modes
        self.userHost = userHost
        self.isSelf = isSelf
        self.isMember = isMember
        self.isIgnored = isIgnored
    }

    /// `nick!user@host`, when the host is known.
    public var hostMask: String? { userHost.map { "\(nick)!\($0)" } }
}

/// Everything a user menu depends on.
nonisolated public struct UserMenuContext: Hashable, Sendable {
    /// One person, or several selected in the member list.
    public var targets: [UserMenuTarget]
    /// Your rank in the channel.
    public var privileges: ChannelPrivileges
    public var isConnected: Bool
    /// The menu is for a channel, so ranks and moderation can apply.
    public var isChannel: Bool
    /// How this server quiets people, if it can.
    public var quietMethod: QuietMethod?
    /// Your other channels on the network that a single target isn't in.
    public var inviteChannels: [String]

    public init(
        targets: [UserMenuTarget],
        privileges: ChannelPrivileges,
        isConnected: Bool,
        isChannel: Bool,
        quietMethod: QuietMethod? = nil,
        inviteChannels: [String] = []
    ) {
        self.targets = targets
        self.privileges = privileges
        self.isConnected = isConnected
        self.isChannel = isChannel
        self.quietMethod = quietMethod
        self.inviteChannels = inviteChannels
    }
}

/// The menu for one person or several, as sections of items, built from
/// what you can actually do (`ChannelPrivileges`). Moderation you can't do
/// is left out rather than disabled; things that need a connection are
/// disabled while you're offline. The member list, nicks in messages and
/// a message's menu all show this one menu, in SwiftUI or AppKit.
nonisolated public struct UserMenu: Hashable, Sendable {
    /// The nick, or "3 people".
    public var title: String
    /// Non-empty sections, shown with separators between them.
    public var sections: [[UserMenuEntry]]

    public init(title: String, sections: [[UserMenuEntry]]) {
        self.title = title
        self.sections = sections.filter { !$0.isEmpty }
    }

    public var isEmpty: Bool { sections.isEmpty }

    /// Every item, submenus included, in order.
    public var items: [UserMenuItem] {
        func flatten(_ entries: [UserMenuEntry]) -> [UserMenuItem] {
            entries.flatMap { entry -> [UserMenuItem] in
                switch entry {
                case .item(let item): [item]
                case .submenu(_, _, let entries): flatten(entries)
                }
            }
        }
        return sections.flatMap(flatten)
    }

    /// The titles shown at the top level (submenus by their own title).
    public var titles: [String] {
        sections.flatMap { section in
            section.map { entry in
                switch entry {
                case .item(let item): item.title
                case .submenu(let title, _, _): title
                }
            }
        }
    }

    public func item(_ action: UserAction) -> UserMenuItem? {
        items.first { $0.action == action }
    }

    /// The menu with "Recap Conversations with alice…" at the end of its
    /// first section, for one person other than you. The app adds it while
    /// Recap is offered (`intelligence.recap`).
    public func addingRecap(for targets: [UserMenuTarget]) -> UserMenu {
        guard targets.count == 1, let target = targets.first, !target.isSelf, !sections.isEmpty else { return self }
        var copy = self
        copy.sections[0].append(.item(UserMenuItem(
            action: .recap,
            title: "Recap Conversations with \(target.nick)…",
            systemImage: "doc.text"
        )))
        return copy
    }

    /// The entries of the submenu titled `title`.
    public func submenu(_ title: String) -> [UserMenuEntry]? {
        for section in sections {
            for case .submenu(let submenuTitle, _, let entries) in section where submenuTitle == title {
                return entries
            }
        }
        return nil
    }

    // MARK: Building

    /// The CTCP requests offered besides PING.
    public static let ctcpRequests: [(command: String, title: String)] = [
        ("VERSION", "Version"),
        ("TIME", "Time"),
        ("CLIENTINFO", "Client Info"),
    ]

    public static func build(_ context: UserMenuContext) -> UserMenu {
        let targets = context.targets
        guard let first = targets.first else { return UserMenu(title: "", sections: []) }
        let online = context.isConnected
        let single = targets.count == 1

        func item(_ action: UserAction, _ title: String, _ image: String?, needsConnection: Bool = false, destructive: Bool = false) -> UserMenuEntry {
            .item(UserMenuItem(action: action, title: title, systemImage: image, isEnabled: !needsConnection || online, isDestructive: destructive))
        }

        // Talking to them and finding out about them.
        var talk: [UserMenuEntry] = []
        if single, !first.isSelf {
            talk.append(item(.message, "Message", "bubble.left"))
            talk.append(item(.mention, "Mention", "at"))
        }
        if single {
            talk.append(item(.whois, "Whois", "person.crop.circle.badge.questionmark", needsConnection: true))
        }
        if single, !first.isSelf {
            talk.append(item(.ping, "Ping", "stopwatch", needsConnection: true))
            talk.append(.submenu(
                title: "CTCP",
                systemImage: "info.circle",
                entries: ctcpRequests.map { item(.ctcp($0.command), $0.title, nil, needsConnection: true) }
            ))
            if !context.inviteChannels.isEmpty {
                talk.append(.submenu(
                    title: "Invite to",
                    systemImage: "envelope",
                    entries: context.inviteChannels.map { item(.invite(channel: $0), $0, nil, needsConnection: true) }
                ))
            }
        }

        // Copying.
        var copy: [UserMenuEntry] = [item(.copyNick, single ? "Copy Nick" : "Copy Nicks", "person.text.rectangle")]
        if single, first.hostMask != nil {
            copy.append(item(.copyHostMask, "Copy Host Mask", "network"))
        }

        var ranks: [UserMenuEntry] = []
        var moderation: [UserMenuEntry] = []
        if context.isChannel {
            ranks = rankItems(context, item: item)
            moderation = moderationItems(context, item: item)
        }

        var ignore: [UserMenuEntry] = []
        if single, !first.isSelf {
            ignore.append(first.isIgnored ? item(.unignore, "Unignore", "eye") : item(.ignore, "Ignore", "eye.slash"))
        }

        let title = single ? first.nick : "\(targets.count) people"
        return UserMenu(title: title, sections: [talk, copy, ranks, moderation, ignore])
    }

    /// Op/Deop, Halfop/Dehalfop, Voice/Devoice and any higher ranks the
    /// network has, highest first: each one you may give or take for
    /// everyone in the menu, when it would change something for someone.
    private static func rankItems(
        _ context: UserMenuContext,
        item: (UserAction, String, String?, Bool, Bool) -> UserMenuEntry
    ) -> [UserMenuEntry] {
        let privileges = context.privileges
        var entries: [UserMenuEntry] = []
        for mode in privileges.ranks {
            for adding in [true, false] {
                let allowed = context.targets.allSatisfy {
                    privileges.mayChange(mode, adding: adding, targetModes: $0.modes, targetIsSelf: $0.isSelf)
                }
                let changesSomething = context.targets.contains { $0.modes.contains(mode) != adding }
                guard allowed, changesSomething else { continue }
                entries.append(item(
                    .mode(sign: adding ? "+" : "-", mode: mode),
                    modeTitle(mode, adding: adding),
                    adding ? "plus.circle" : "minus.circle",
                    true,
                    false
                ))
            }
        }
        return entries
    }

    /// Quiet, kick and ban, when you may do them to everyone in the menu.
    private static func moderationItems(
        _ context: UserMenuContext,
        item: (UserAction, String, String?, Bool, Bool) -> UserMenuEntry
    ) -> [UserMenuEntry] {
        let privileges = context.privileges
        let targets = context.targets
        guard targets.allSatisfy({ privileges.canRemove(targetModes: $0.modes, targetIsSelf: $0.isSelf) }) else { return [] }
        // Only people in the channel can be kicked; anyone can be banned.
        let canKick = targets.allSatisfy(\.isMember)
        var entries: [UserMenuEntry] = []
        if canKick {
            entries.append(item(.kick, "Kick", "figure.walk.departure", true, true))
            entries.append(item(.kickWithReason, "Kick with Reason…", "figure.walk.departure", true, true))
        }
        entries.append(item(.ban, "Ban", "nosign", true, true))
        if canKick {
            entries.append(item(.kickBan, "Kick + Ban", "nosign", true, true))
            entries.append(item(.kickBanWithReason, "Kick + Ban with Reason…", "nosign", true, true))
        }
        if context.quietMethod != nil {
            entries.append(item(.quiet, "Quiet", "speaker.slash", true, false))
            entries.append(item(.unquiet, "Unquiet", "speaker.wave.2", true, false))
        }
        return entries
    }

    /// "Op", "Deop", "Make Owner"…
    public static func modeTitle(_ mode: Character, adding: Bool) -> String {
        switch mode {
        case "q": adding ? "Make Owner" : "Remove Owner"
        case "a": adding ? "Make Admin" : "Remove Admin"
        case "o": adding ? "Op" : "Deop"
        case "h": adding ? "Halfop" : "Dehalfop"
        case "v": adding ? "Voice" : "Devoice"
        default: adding ? "Give +\(mode)" : "Take +\(mode)"
        }
    }
}
