// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import VelaCore
import VelaIRC

/// The user menu model: what shows for whom, from your rank.
@Suite("User menu")
struct UserMenuModelTests {
    private static let full = ISupport(tokens: ["PREFIX=(qaohv)~&@%+"])

    private func menu(
        own: String,
        targets: [UserMenuTarget],
        isupport: ISupport = full,
        connected: Bool = true,
        channel: Bool = true,
        quiet: QuietMethod? = nil,
        invite: [String] = []
    ) -> UserMenu {
        UserMenu.build(UserMenuContext(
            targets: targets,
            privileges: ChannelPrivileges(isupport: isupport, ownPrefixes: own),
            isConnected: connected,
            isChannel: channel,
            quietMethod: quiet,
            inviteChannels: invite
        ))
    }

    private let wren = UserMenuTarget(nick: "wren", userHost: "wren@user/wren")
    private let ada = UserMenuTarget(nick: "ada", modes: ["v"], userHost: "ada@user/ada")
    private let kenji = UserMenuTarget(nick: "kenji", modes: ["o"])
    private let marisol = UserMenuTarget(nick: "marisol", modes: ["h"])
    private let boss = UserMenuTarget(nick: "boss", modes: ["q", "o"])

    private static let moderation = ["Kick", "Kick with Reason…", "Ban", "Kick + Ban", "Kick + Ban with Reason…"]

    @Test func aRegularUserSeesNoModeration() {
        let menu = menu(own: "", targets: [wren], invite: ["#swift"])
        #expect(menu.title == "wren")
        #expect(menu.titles == ["Message", "Mention", "Whois", "Ping", "CTCP", "Invite to", "Copy Nick", "Copy Host Mask", "Ignore"])
        #expect(menu.submenu("CTCP")?.count == 3)
        #expect(menu.item(.ctcp("VERSION"))?.title == "Version")
        #expect(menu.item(.invite(channel: "#swift")) != nil)
        #expect(menu.items.allSatisfy { $0.isEnabled })
    }

    @Test func aVoicedUserSeesNoModerationEither() {
        let menu = menu(own: "+", targets: [ada], quiet: .listMode("q"))
        #expect(!menu.items.contains { if case .mode = $0.action { true } else { false } })
        #expect(Self.moderation.allSatisfy { !menu.titles.contains($0) })
        #expect(!menu.titles.contains("Quiet"))
    }

    @Test func yourself() {
        // No Message, Ping, Kick, Ban or Ignore on yourself; you can remove
        // your own modes.
        let me = UserMenuTarget(nick: "doug", modes: ["v"], userHost: "doug@user/doug", isSelf: true)
        let menu = menu(own: "+", targets: [me])
        #expect(menu.titles == ["Whois", "Copy Nick", "Copy Host Mask", "Devoice"])
        let owner = UserMenuTarget(nick: "doug", modes: ["q"], isSelf: true)
        let ownerMenu = self.menu(own: "~", targets: [owner])
        #expect(ownerMenu.titles.contains("Remove Owner"))
        #expect(Self.moderation.allSatisfy { !ownerMenu.titles.contains($0) })
        #expect(!ownerMenu.titles.contains("Message"))
        #expect(!ownerMenu.titles.contains("Ignore"))
    }

    @Test func aHalfopVoicesAndKicksRegularUsers() {
        let menu = menu(own: "%", targets: [ada])
        #expect(menu.titles.contains("Devoice"))
        #expect(!menu.titles.contains("Op"))
        #expect(!menu.titles.contains("Halfop"))
        #expect(Self.moderation.allSatisfy { menu.titles.contains($0) })
        // Not other halfops or ops.
        let onHalfop = self.menu(own: "%", targets: [marisol])
        #expect(Self.moderation.allSatisfy { !onHalfop.titles.contains($0) })
        #expect(!onHalfop.titles.contains("Voice"))
        #expect(!onHalfop.titles.contains("Dehalfop"))
    }

    @Test func anOpManagesOpsAndBelow() {
        let menu = menu(own: "@", targets: [wren], quiet: .extban("m:"))
        let ranks = menu.items.filter { if case .mode = $0.action { true } else { false } }.map(\.title)
        #expect(ranks == ["Op", "Halfop", "Voice"])
        #expect(Self.moderation.allSatisfy { menu.titles.contains($0) })
        #expect(menu.titles.contains("Quiet"))
        #expect(menu.titles.contains("Unquiet"))
        #expect(menu.item(.kick)?.isDestructive == true)
        // Another op: deop them, kick them.
        let onOp = self.menu(own: "@", targets: [kenji])
        #expect(onOp.titles.contains("Deop"))
        #expect(!onOp.titles.contains("Op"))
        #expect(onOp.titles.contains("Kick"))
        // An owner: hands off.
        let onOwner = self.menu(own: "@", targets: [boss])
        #expect(!onOwner.titles.contains("Deop"))
        #expect(!onOwner.titles.contains("Kick"))
        #expect(!onOwner.titles.contains("Ban"))
    }

    @Test func anOwnerSetsEveryRankBelowOwner() {
        let menu = menu(own: "~", targets: [wren])
        let ranks = menu.items.filter { if case .mode = $0.action { true } else { false } }.map(\.title)
        #expect(ranks == ["Make Admin", "Op", "Halfop", "Voice"])
        #expect(menu.item(.mode(sign: "+", mode: "a")) != nil)
        // Libera-style servers have only op and voice.
        let libera = ISupport(tokens: ["PREFIX=(ov)@+"])
        let opMenu = self.menu(own: "@", targets: [wren], isupport: libera)
        #expect(opMenu.items.filter { if case .mode = $0.action { true } else { false } }.map(\.title) == ["Op", "Voice"])
    }

    @Test func severalPeople() {
        let menu = menu(own: "@", targets: [wren, ada, kenji], quiet: .listMode("q"))
        #expect(menu.title == "3 people")
        #expect(menu.titles.first == "Copy Nicks")
        // Nothing that's only for one person.
        for title in ["Message", "Mention", "Whois", "Ping", "CTCP", "Copy Host Mask", "Ignore"] {
            #expect(!menu.titles.contains(title), "\(title)")
        }
        // Op for those who aren't, deop for those who are, and so on.
        #expect(menu.titles.contains("Op"))
        #expect(menu.titles.contains("Deop"))
        #expect(menu.titles.contains("Voice"))
        #expect(menu.titles.contains("Devoice"))
        #expect(Self.moderation.allSatisfy { menu.titles.contains($0) })
        #expect(menu.titles.contains("Quiet"))
    }

    @Test func severalPeopleShowOnlyWhatsAllowedForEveryone() {
        // A halfop with a voiced user and an op selected: no kick (the op
        // outranks them), but devoicing the voiced one is fine...
        let menu = menu(own: "%", targets: [ada, kenji])
        #expect(Self.moderation.allSatisfy { !menu.titles.contains($0) })
        #expect(!menu.titles.contains("Devoice"))
        // ...and with yourself among them, no kicking at all.
        let me = UserMenuTarget(nick: "doug", modes: ["o"], isSelf: true)
        let withSelf = self.menu(own: "@", targets: [wren, me])
        #expect(Self.moderation.allSatisfy { !withSelf.titles.contains($0) })
        #expect(withSelf.titles.contains("Deop"))
        #expect(withSelf.titles.contains("Copy Nicks"))
    }

    @Test func disconnected() {
        // Things that need a connection are disabled, the rest still work.
        let menu = menu(own: "@", targets: [wren], connected: false, invite: ["#swift"])
        for action in [UserAction.whois, .ping, .ctcp("VERSION"), .invite(channel: "#swift"), .kick, .ban, .mode(sign: "+", mode: "o")] {
            #expect(menu.item(action)?.isEnabled == false, "\(action)")
        }
        for action in [UserAction.message, .mention, .copyNick, .copyHostMask, .ignore] {
            #expect(menu.item(action)?.isEnabled == true, "\(action)")
        }
    }

    @Test func outsideAChannel() {
        // A query: no ranks or moderation, even for an op elsewhere.
        let menu = menu(own: "@", targets: [wren], channel: false)
        #expect(menu.titles == ["Message", "Mention", "Whois", "Ping", "CTCP", "Copy Nick", "Copy Host Mask", "Ignore"])
    }

    @Test func someoneWhoLeftCanBeBannedButNotKicked() {
        let gone = UserMenuTarget(nick: "troll", userHost: "t@spam.example", isMember: false)
        let menu = menu(own: "@", targets: [gone])
        #expect(menu.titles.contains("Ban"))
        #expect(!menu.titles.contains("Kick"))
        #expect(!menu.titles.contains("Kick + Ban"))
    }

    @Test func ignoreReflectsTheList() {
        var ignored = wren
        ignored.isIgnored = true
        #expect(menu(own: "", targets: [ignored]).titles.last == "Unignore")
        #expect(menu(own: "", targets: [wren]).titles.last == "Ignore")
    }

    @Test func noHostNoCopyHostMask() {
        let unknown = UserMenuTarget(nick: "wren")
        #expect(!menu(own: "", targets: [unknown]).titles.contains("Copy Host Mask"))
        #expect(wren.hostMask == "wren!wren@user/wren")
    }

    @Test func appActions() {
        #expect(UserAction.mention.isHandledByApp)
        #expect(UserAction.kickWithReason.isHandledByApp)
        #expect(!UserAction.kick.isHandledByApp)
        #expect(UserMenu.modeTitle("Y", adding: true) == "Give +Y")
    }
}
