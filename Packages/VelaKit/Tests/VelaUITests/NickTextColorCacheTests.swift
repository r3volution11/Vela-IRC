// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import Testing
@testable import VelaCore
import VelaFoundation
import VelaIRC
import VelaStore
@testable import VelaTheme
@testable import VelaUI

/// Rendered texts follow who's here: someone joining, leaving or changing
/// nick re-renders the lines that mention them, and only those; a theme
/// switch re-renders everything.
@MainActor
@Suite("Nick colors in text stay current")
struct NickTextColorCacheTests {
    private func makeChannel(names: String = "@doug alice bob") -> (NetworkSession, BufferModel) {
        let session = NetworkSession(config: NetworkConfig(name: "Test", host: "irc.test", nick: "doug"), database: nil)
        session.nick = "doug"
        session.connectionState = .connected
        feed(session, ":doug!d@host JOIN #vela", ":irc.test 353 doug = #vela :\(names)", ":irc.test 366 doug #vela :End")
        return (session, session.buffer(named: "#vela")!)
    }

    private func feed(_ session: NetworkSession, _ lines: String...) {
        for line in lines { session.handle(.message(IRCMessage(line: line)!, batch: nil)) }
    }

    /// What the list does on each update.
    @discardableResult
    private func prepare(_ controller: MessageListController, theme: ResolvedTheme = .fallbackDark, colorsNicks: Bool = true) -> Int {
        controller.prepareText(
            palette: MessageTextPalette.cached(theme: theme, style: ChatStyle()),
            options: MessageTextOptions(
                renderFormatting: true, selfNick: controller.session.nick, channelTypes: ["#"],
                colorsNicks: colorsNicks, caseMapping: controller.session.isupport.caseMapping
            ),
            nickChangeCount: controller.buffer.nickChangeCount
        )
    }

    private func color(of word: String, in rendered: RenderedText) -> Color? {
        guard let range = rendered.attributed.range(of: word) else { return nil }
        return rendered.attributed[range].runs.first?.foregroundColor ?? nil
    }

    private func item(_ line: ChatLine) -> DisplayItem {
        .line(LineItem(line: line, isContinuation: false, reply: nil))
    }

    @Test func joinsPartsAndNickChangesReRenderOnlyTheLinesMentioningThem() {
        let (session, channel) = makeChannel()
        let controller = MessageListController(buffer: channel, session: session)
        let theme = ResolvedTheme.fallbackDark
        let welcome = ChatLine(kind: .message, nick: "alice", text: "carol, welcome!")
        let lunch = ChatLine(kind: .message, nick: "bob", text: "alice: lunch?")
        let build = ChatLine(kind: .message, nick: "alice", text: "the build is green")
        let knows = ChatLine(kind: .message, nick: "alice", text: "bob knows")

        let generation = prepare(controller)
        for line in [welcome, lunch, build, knows] { _ = controller.textCache.rendered(line) }
        #expect(color(of: "carol", in: controller.textCache.rendered(welcome)) == nil)
        #expect(color(of: "alice", in: controller.textCache.rendered(lunch)) == theme.nickColor(for: "alice", in: channel).color)

        // carol joins: her welcome renders again, nothing else does.
        feed(session, ":carol!c@host JOIN #vela")
        #expect(prepare(controller) == generation)
        #expect(controller.textCache.count == 3)
        #expect(controller.textStamp(for: item(welcome)) != 0)
        #expect([lunch, build, knows].allSatisfy { controller.textStamp(for: item($0)) == 0 })
        #expect(color(of: "carol", in: controller.textCache.rendered(welcome)) == theme.nickColor(for: "carol", in: channel).color)
        // Only that row runs again.
        #expect(DisplayItemRow(item: item(welcome), textGeneration: generation, textStamp: 0)
            != DisplayItemRow(item: item(welcome), textGeneration: generation, textStamp: controller.textStamp(for: item(welcome))))

        // alice leaves: the line mentioning her loses her color.
        feed(session, ":alice!a@host PART #vela")
        prepare(controller)
        #expect(controller.textStamp(for: item(lunch)) != 0)
        #expect(controller.textStamp(for: item(knows)) == 0)
        #expect(color(of: "alice", in: controller.textCache.rendered(lunch)) == nil)

        // bob becomes robert: "bob" is no one now.
        let before = controller.textStamp(for: item(welcome))
        feed(session, ":bob!b@host NICK robert")
        prepare(controller)
        #expect(controller.textStamp(for: item(knows)) != 0)
        #expect(controller.textStamp(for: item(welcome)) == before)
        #expect(color(of: "bob", in: controller.textCache.rendered(knows)) == nil)
        let robert = ChatLine(kind: .message, nick: "carol", text: "hi robert")
        #expect(color(of: "robert", in: controller.textCache.rendered(robert)) == theme.nickColor(for: "robert", in: channel).color)
        #expect(prepare(controller) == generation)
    }

    @Test func modesAndAwayDoNotReRenderAnything() {
        let (session, channel) = makeChannel()
        let controller = MessageListController(buffer: channel, session: session)
        let lunch = ChatLine(kind: .message, nick: "bob", text: "alice: lunch?")
        prepare(controller)
        _ = controller.textCache.rendered(lunch)
        feed(session, ":doug!d@host MODE #vela +o alice", ":alice!a@host AWAY :lunch")
        prepare(controller)
        #expect(controller.textCache.count == 1)
        #expect(controller.textStamp(for: item(lunch)) == 0)
    }

    @Test func aThemeSwitchReRendersEveryNick() {
        let (session, channel) = makeChannel()
        let controller = MessageListController(buffer: channel, session: session)
        let lunch = ChatLine(kind: .message, nick: "bob", text: "alice: lunch?")
        let dark = prepare(controller, theme: .fallbackDark)
        #expect(color(of: "alice", in: controller.textCache.rendered(lunch)) == ResolvedTheme.fallbackDark.nickColor(for: "alice", in: channel).color)
        let light = prepare(controller, theme: .fallbackLight)
        #expect(light != dark)
        #expect(controller.textCache.count == 0)
        #expect(color(of: "alice", in: controller.textCache.rendered(lunch)) == ResolvedTheme.fallbackLight.nickColor(for: "alice", in: channel).color)
    }

    /// A theme whose nick palette changes but nothing else the text uses
    /// still re-renders: the palette carries the nick colors.
    @Test func aNewNickPaletteAloneReRenders() {
        let base = ResolvedTheme.fallbackDark
        let shifted = ResolvedTheme(
            id: base.id, name: base.name, kind: base.kind, vibrancy: base.vibrancy, colors: base.colors,
            nickColors: Array(base.nickColors.reversed()), ircColors: base.ircColors
        )
        #expect(MessageTextPalette(theme: base, style: ChatStyle()) != MessageTextPalette(theme: shifted, style: ChatStyle()))
    }

    @Test func aBurstStartsOverOnce() {
        let (session, channel) = makeChannel()
        let controller = MessageListController(buffer: channel, session: session)
        let lunch = ChatLine(kind: .message, nick: "bob", text: "alice: lunch?")
        let generation = prepare(controller)
        _ = controller.textCache.rendered(lunch)
        // A netsplit heals: a hundred people rejoin before the list updates.
        for index in 0..<100 { feed(session, ":user\(index)!u@host JOIN #vela") }
        #expect(prepare(controller) == generation + 1)
        #expect(controller.textCache.count == 0)
        #expect(prepare(controller) == generation + 1)
    }

    @Test func withTheSettingOffNothingIsColoredOrDropped() {
        let (session, channel) = makeChannel()
        let controller = MessageListController(buffer: channel, session: session)
        let welcome = ChatLine(kind: .message, nick: "alice", text: "carol, welcome! bob says hi")
        prepare(controller, colorsNicks: false)
        #expect(color(of: "bob", in: controller.textCache.rendered(welcome)) == nil)
        feed(session, ":carol!c@host JOIN #vela")
        prepare(controller, colorsNicks: false)
        #expect(controller.textCache.count == 1)
        #expect(controller.textStamp(for: item(welcome)) == 0)
    }

    @Test func eventLinesKeepTheirLook() {
        let (session, channel) = makeChannel()
        let controller = MessageListController(buffer: channel, session: session)
        prepare(controller)
        let topic = ChatLine(kind: .topic, nick: "alice", text: "alice changed the topic to: ask bob")
        #expect(color(of: "bob", in: controller.textCache.rendered(topic)) == nil)
    }

    @Test func aConversationColorsThePersonItsWith() {
        let (session, _) = makeChannel()
        let query = session.ensureBuffer(name: "alice", kind: .query, persist: false)
        let controller = MessageListController(buffer: query, session: session)
        prepare(controller)
        let line = ChatLine(kind: .message, nick: "alice", text: "ALICE here, bob says hi")
        let rendered = controller.textCache.rendered(line)
        #expect(color(of: "ALICE", in: rendered) == ResolvedTheme.fallbackDark.nickColor(for: "alice", in: query).color)
        #expect(color(of: "bob", in: rendered) == nil)
        // The server buffer has nobody to color.
        let server = MessageListController(buffer: session.serverBuffer, session: session)
        #expect(server.nickColorIndex(word: "alice", folded: "alice", geometry: ResolvedTheme.fallbackDark.nickPaletteGeometry) == nil)
    }

    /// A speaker moved off their usual color (someone else had it) shows
    /// the new one in lines that mentioned them before they spoke.
    @Test func aNewColorReachesEarlierMentions() {
        let (session, channel) = makeChannel(names: "@doug jeebz tomf")
        let controller = MessageListController(buffer: channel, session: session)
        let theme = ResolvedTheme.fallbackDark
        let geometry = theme.nickPaletteGeometry
        prepare(controller)
        let early = ChatLine(kind: .message, nick: "doug", text: "tomf, you around?")
        _ = controller.textCache.rendered(early)
        // Someone with tomf's usual color speaks first.
        let usual = NickColorAssigner.usualIndex(for: "tomf", palette: geometry)
        let rival = (0...).lazy.map { "rival\($0)" }.first { NickColorAssigner.usualIndex(for: $0, palette: geometry) == usual }!
        feed(session, ":\(rival)!r@host JOIN #vela", ":\(rival)!r@host PRIVMSG #vela :first", ":tomf!t@host PRIVMSG #vela :here")
        #expect(channel.nickColorIndex(for: "tomf", palette: geometry) != usual)
        prepare(controller)
        #expect(controller.textStamp(for: item(early)) != 0)
        #expect(color(of: "tomf", in: controller.textCache.rendered(early)) == theme.nickColor(for: "tomf", in: channel).color)
    }
}

/// Your own nick has one color everywhere, and nobody else gets one like it.
@MainActor
@Suite("Your own nick's color")
struct SelfNickColorTests {
    @Test func theSameInTheMemberListAndMessages() {
        let theme = ResolvedTheme.fallbackDark
        let me = Member(nick: "r3volution11")
        for colorNicks in [true, false] {
            let header = theme.nickDisplayColor("r3volution11", isSelf: true, colorNicks: colorNicks, in: nil)
            #expect(header == theme[ThemeKey.chatSelfNick])
            #expect(theme.memberListNickColor(me, isSelf: true, colorNicks: colorNicks, in: nil) == header)
        }
        // Someone else matches their messages too.
        let channel = BufferModel(id: BufferID(networkID: UUID(), foldedName: "#vela"), name: "#vela", kind: .channel)
        let other = Member(nick: "Templarian")
        #expect(theme.memberListNickColor(other, isSelf: false, colorNicks: true, in: channel)
            == theme.nickDisplayColor("Templarian", isSelf: false, colorNicks: true, in: channel))
    }

    /// The report: in Palenight, with seven people in a channel, your nick
    /// (r3volution11) and Templarian's looked the same in the chat, while
    /// the member list showed them in two blues. Palenight's self color
    /// (#C792EA) is in its nick palette, beside #A9B4FF and #82AAFF; a blue
    /// accent makes the self color a blue like #82AAFF itself.
    @Test func thePalenightChannelFromTheReport() throws {
        let palenight = ResolvedTheme.fallbackDark
        let blue: ThemeColor = try #require(ThemeColor(hex: "#82AAFF"))
        var blueColors = palenight.colors
        blueColors[ThemeKey.chatSelfNick] = blue
        let blueSelf = ResolvedTheme(
            id: palenight.id, name: palenight.name, kind: palenight.kind, vibrancy: palenight.vibrancy,
            colors: blueColors, nickColors: palenight.nickColors, ircColors: palenight.ircColors
        )
        let others = ["Templarian", "jeebz", "tomf", "xmn", "kenji", "ada"]
        for theme in [palenight, blueSelf] {
            let session = NetworkSession(config: NetworkConfig(name: "Libera", host: "irc.test", nick: "r3volution11"), database: nil)
            session.nick = "r3volution11"
            session.connectionState = .connected
            let joining = [
                ":r3volution11!u@host JOIN #vela",
                ":irc.test 353 r3volution11 = #vela :@r3volution11 \(others.joined(separator: " "))",
                ":irc.test 366 r3volution11 #vela :End",
            ]
            let talking = others.map { ":\($0)!u@host PRIVMSG #vela :hello" } + [":r3volution11!u@host PRIVMSG #vela :hi all"]
            for line in joining + talking {
                session.handle(.message(IRCMessage(line: line)!, batch: nil))
            }
            let channel = try #require(session.buffer(named: "#vela"))
            #expect(channel.memberCount == 7)
            let me = theme.color(ThemeKey.chatSelfNick)
            for nick in others {
                let color = theme.nickColor(for: nick, in: channel)
                #expect(color.distance(to: me) >= NickPaletteGeometry.oklabSimilar, "self \(me.hex): \(nick) is \(color.hex)")
                // The member list agrees with the chat.
                #expect(theme.memberListNickColor(Member(nick: nick), isSelf: false, colorNicks: true, in: channel) == color.color)
            }
            // Everyone talking has a color of their own.
            #expect(Set(others.map { channel.nickColorIndex(for: $0, palette: theme.nickPaletteGeometry) }).count == others.count)
            #expect(theme.memberListNickColor(Member(nick: "r3volution11"), isSelf: true, colorNicks: true, in: channel)
                == theme.nickDisplayColor("r3volution11", isSelf: true, colorNicks: true, in: channel))
        }
    }

    @Test func nickColorsInTextNeverLookLikeYou() {
        let theme = ResolvedTheme.fallbackDark
        let palette = MessageTextPalette(theme: theme, style: ChatStyle())
        let me = theme.color(ThemeKey.chatSelfNick)
        #expect(!theme.nickPaletteGeometry.reserved.isEmpty)
        for index in theme.nickPaletteGeometry.available {
            #expect(palette.nickColor(at: index) == theme.nickPalette[index].color)
            #expect(theme.nickPalette[index].distance(to: me) >= NickPaletteGeometry.oklabSimilar)
        }
    }
}
