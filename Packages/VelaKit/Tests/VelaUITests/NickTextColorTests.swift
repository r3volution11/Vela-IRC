// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import Testing
@testable import VelaCore
import VelaFoundation
import VelaIRC
@testable import VelaTheme
@testable import VelaUI

/// The nicks of people here, colored where messages mention them
/// (`chat.colorNicksInText`).
@MainActor
@Suite("Nicks colored in message text")
struct NickTextColorTests {
    private static let nickColors: [Color] = [.red, .orange, .yellow, .green, .teal, .indigo]

    private let palette = MessageTextPalette(
        foreground: .white, background: .black, link: .blue, mention: .purple,
        codeForeground: .mint, codeBackground: .gray,
        irc: (0..<99).map { Color(white: Double($0) / 99) },
        monospaceFont: .system(size: 13, design: .monospaced),
        nickColors: nickColors
    )

    /// Renders `text` with `members` here, each colored by their place in
    /// the list (alice red, bob orange, …).
    private func render(
        _ text: String,
        members: [String] = ["alice", "bob", "Kenji", "nick[m]", "a", "doug"],
        selfNick: String = "doug",
        caseMapping: CaseMapping = .rfc1459,
        formatting: Bool = true,
        colorsNicks: Bool = true,
        highlightMentions: Bool = true
    ) -> RenderedText {
        let colors = Dictionary(uniqueKeysWithValues: members.enumerated().map { (caseMapping.fold($1), $0) })
        return MessageTextRenderer.render(
            text, palette: palette,
            options: MessageTextOptions(
                renderFormatting: formatting, selfNick: selfNick, channelTypes: ["#", "&"],
                colorsNicks: colorsNicks, caseMapping: caseMapping
            ),
            highlightMentions: highlightMentions,
            nicks: { _, folded in colors[folded] }
        )
    }

    /// The colors of the runs covering the `occurrence`th `word` in `rendered`.
    private func colors(of word: String, in rendered: RenderedText, occurrence: Int = 0) -> [Color?] {
        var searchStart = rendered.attributed.startIndex
        var found: Range<AttributedString.Index>?
        for _ in 0...occurrence {
            guard let range = rendered.attributed[searchStart...].range(of: word) else { return [] }
            found = range
            searchStart = range.upperBound
        }
        guard let found else { return [] }
        return rendered.attributed[found].runs.map(\.foregroundColor)
    }

    private func color(of word: String, in rendered: RenderedText, occurrence: Int = 0) -> Color? {
        let colors = colors(of: word, in: rendered, occurrence: occurrence)
        guard let first = colors.first, colors.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    // MARK: Who

    @Test func membersAreColoredAsElsewhere() {
        let rendered = render("alice: did bob see this?")
        #expect(color(of: "alice", in: rendered) == .red)
        #expect(color(of: "bob", in: rendered) == .orange)
        #expect(color(of: "did", in: rendered) == nil)
        #expect(color(of: "see", in: rendered) == nil)
    }

    @Test func nonMembersAreNot() {
        let rendered = render("carol and dave were here")
        #expect(rendered.attributed.runs.allSatisfy { $0.foregroundColor == nil })
    }

    @Test func matchingFollowsTheNetworksCasemapping() {
        // RFC 1459: case-insensitive, and {} are [] in lowercase.
        let rfc = render("ALICE and kenji and NICK{M}")
        #expect(color(of: "ALICE", in: rfc) == .red)
        #expect(color(of: "kenji", in: rfc) == .yellow)
        #expect(color(of: "NICK{M}", in: rfc) == .green)
        // ASCII casemapping: still case-insensitive, but [] aren't {}.
        let ascii = render("ALICE and NICK{M}", caseMapping: .ascii)
        #expect(color(of: "ALICE", in: ascii) == .red)
        #expect(color(of: "NICK{M}", in: ascii) == nil)
    }

    @Test func wholeWordsOnly() {
        let rendered = render("malice alices alice_ alice-ish bobby alice, (alice) <bob>")
        for word in ["malice", "alices", "alice_", "alice-ish", "bobby"] {
            #expect(color(of: word, in: rendered) == nil, "\(word)")
        }
        // "alice" itself appears at "alice," and "(alice)".
        #expect(colors(of: "alice,", in: rendered) == [.red, nil])
        #expect(colors(of: "(alice)", in: rendered) == [nil, .red, nil])
        #expect(colors(of: "<bob>", in: rendered) == [nil, .orange, nil])
    }

    @Test func oneCharacterNicksAreSkipped() {
        let rendered = render("a cat sat on a mat")
        #expect(rendered.attributed.runs.allSatisfy { $0.foregroundColor == nil })
    }

    // MARK: Where not

    @Test func notInsideLinksOrChannelNames() {
        let rendered = render("see https://example.com/alice and #bob, then alice")
        #expect(color(of: "https://example.com/alice", in: rendered) == palette.link)
        #expect(color(of: "#bob", in: rendered) == palette.link)
        // The last word is just a mention.
        #expect(color(of: "alice", in: rendered, occurrence: 1) == .red)
    }

    @Test func theSendersColorsWin() {
        let rendered = render("\u{03}04alice\u{03} \u{03},02bob\u{03} \u{11}Kenji\u{11} \u{16}nick[m]\u{16} and alice")
        #expect(color(of: "alice", in: rendered) == palette.irc[4])
        #expect(color(of: "bob", in: rendered) == nil)
        #expect(color(of: "Kenji", in: rendered) == palette.codeForeground)
        #expect(color(of: "nick[m]", in: rendered) == palette.background)
        #expect(color(of: "alice", in: rendered, occurrence: 1) == .red)
    }

    @Test func boldAndItalicKeepTheirStyle() {
        let rendered = render("\u{02}alice\u{02} and \u{1D}bob\u{1D}")
        let alice = rendered.attributed[rendered.attributed.range(of: "alice")!]
        #expect(alice.runs.first?.foregroundColor == .red)
        #expect(alice.runs.first?.inlinePresentationIntent == .stronglyEmphasized)
        let bob = rendered.attributed[rendered.attributed.range(of: "bob")!]
        #expect(bob.runs.first?.foregroundColor == .orange)
        #expect(bob.runs.first?.inlinePresentationIntent == .emphasized)
    }

    // MARK: Our own nick

    @Test func ourNickKeepsTheMentionStyle() {
        // doug is a member too, but a mention of us is a mention.
        let rendered = render("hey doug, alice wants you")
        let doug = rendered.attributed[rendered.attributed.range(of: "doug")!]
        #expect(doug.runs.first?.foregroundColor == palette.mention)
        #expect(doug.runs.first?.inlinePresentationIntent == .stronglyEmphasized)
        #expect(color(of: "alice", in: rendered) == .red)
        // In our own messages our nick stays plain; others are colored.
        let own = render("I'm doug, ask alice", highlightMentions: false)
        #expect(color(of: "doug", in: own) == nil)
        #expect(color(of: "alice", in: own) == .red)
    }

    // MARK: Off

    @Test func offWithTheSetting() {
        let rendered = render("alice and bob", colorsNicks: false)
        #expect(rendered.attributed.runs.allSatisfy { $0.foregroundColor == nil })
        #expect(rendered.nickKeys.isEmpty)
        // Or without anyone to look up.
        let alone = MessageTextRenderer.render("alice and bob", palette: palette, options: MessageTextOptions(colorsNicks: true))
        #expect(alone.attributed.runs.allSatisfy { $0.foregroundColor == nil })
    }

    @Test func formattingOffStillColorsNicks() {
        let rendered = render("\u{03}04alice\u{03} and bob", formatting: false)
        #expect(color(of: "alice", in: rendered) == .red)
        #expect(color(of: "bob", in: rendered) == .orange)
    }

    // MARK: What the cache keeps

    @Test func renderingsKnowWhichNicksTheyCouldShow() {
        let rendered = render("alice and carol, see https://x.org/dave #erin doug a")
        func key(_ nick: String) -> Int { MessageTextRenderer.nickKey(CaseMapping.rfc1459.fold(nick)) }
        // Members or not: carol might join.
        #expect(rendered.mentions(anyOf: [key("carol")]))
        #expect(rendered.mentions(anyOf: [key("ALICE")]))
        #expect(rendered.mentions(anyOf: [key("and")]))
        // Never colored here: inside a link or channel, our nick, one letter.
        #expect(!rendered.mentions(anyOf: [key("dave"), key("erin"), key("doug"), key("a")]))
        #expect(rendered.nickKeys == rendered.nickKeys.sorted())
        #expect(Set(rendered.nickKeys).count == rendered.nickKeys.count)
    }

    // MARK: Accessibility

    @Test func coloringIsVisualOnly() {
        let text = "alice: bob said \u{02}hi\u{02} in #vela, see https://swift.org"
        let colored = render(text)
        let plain = render(text, colorsNicks: false)
        #expect(colored.plain == plain.plain)
        #expect(String(colored.attributed.characters) == String(plain.attributed.characters))
        #expect(colored.linkRuns == plain.linkRuns)
        #expect(colored.links == plain.links)
    }
}
