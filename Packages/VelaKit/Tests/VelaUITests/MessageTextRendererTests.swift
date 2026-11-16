// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import Testing
import VelaCore
@testable import VelaUI

@MainActor
@Suite("Message text rendering")
struct MessageTextRendererTests {
    private let palette = MessageTextPalette(
        foreground: .white, background: .black, link: .blue, mention: .purple,
        codeForeground: .green, codeBackground: .gray,
        irc: (0..<99).map { Color(white: Double($0) / 99) },
        monospaceFont: .system(size: 13, design: .monospaced)
    )

    private func render(_ text: String, nick: String = "doug", formatting: Bool = true) -> RenderedText {
        MessageTextRenderer.render(text, palette: palette,
                                   options: MessageTextOptions(renderFormatting: formatting, selfNick: nick, channelTypes: ["#", "&"]))
    }

    /// The runs of `text` covering `substring`.
    private func runs(of substring: String, in rendered: RenderedText) -> AttributedString? {
        guard let range = rendered.attributed.range(of: substring) else { return nil }
        return AttributedString(rendered.attributed[range])
    }

    @Test func formattingCodesBecomeAttributes() {
        let rendered = render("a \u{02}bold\u{02} \u{1D}it\u{1D} \u{1F}u\u{1F} \u{1E}s\u{1E} \u{11}code\u{11} \u{03}04red\u{03}")
        #expect(rendered.plain == "a bold it u s code red")
        #expect(runs(of: "bold", in: rendered)?.runs.first?.inlinePresentationIntent == .stronglyEmphasized)
        #expect(runs(of: "it", in: rendered)?.runs.first?.inlinePresentationIntent == .emphasized)
        #expect(runs(of: "u", in: rendered)?.runs.first?.underlineStyle == .single)
        #expect(runs(of: " s ", in: rendered)?.runs.contains { $0.strikethroughStyle == .single } == true)
        #expect(runs(of: "code", in: rendered)?.runs.first?.backgroundColor == palette.codeBackground)
        #expect(runs(of: "code", in: rendered)?.runs.first?.font == palette.monospaceFont)
        #expect(runs(of: "red", in: rendered)?.runs.first?.foregroundColor == palette.irc[4])
    }

    @Test func reverseSwapsColors() {
        let rendered = render("\u{16}rev\u{16}")
        let run = runs(of: "rev", in: rendered)?.runs.first
        #expect(run?.foregroundColor == palette.background)
        #expect(run?.backgroundColor == palette.foreground)
    }

    @Test func formattingCanBeStripped() {
        let rendered = render("\u{02}bold\u{02} and \u{03}04red", formatting: false)
        #expect(rendered.plain == "bold and red")
        #expect(rendered.attributed.runs.allSatisfy { $0.inlinePresentationIntent == nil && $0.foregroundColor == nil })
    }

    @Test func linksAreDetected() {
        let rendered = render("see https://example.com/a?b=1, then \u{02}https://bold.example\u{02}.")
        #expect(rendered.links.map(\.absoluteString) == ["https://example.com/a?b=1", "https://bold.example"])
        #expect(runs(of: "https://example.com/a?b=1", in: rendered)?.runs.first?.link?.absoluteString == "https://example.com/a?b=1")
        #expect(runs(of: "https://bold.example", in: rendered)?.runs.first?.foregroundColor == palette.link)
    }

    @Test func channelsBecomeJoinLinks() {
        #expect(MessageTextRenderer.channelRanges(in: "join #vela, &local and (#swift).", types: ["#", "&"]).count == 3)
        // Issue numbers, mid-word hashes and URL fragments aren't channels.
        #expect(MessageTextRenderer.channelRanges(in: "fixed #12 in c#", types: ["#"]).isEmpty)
        let rendered = render("see https://x.org/page#frag and #vela")
        let link = runs(of: "#vela", in: rendered)?.runs.first?.link
        #expect(link.flatMap(ChannelLink.channel(from:)) == "#vela")
        #expect(runs(of: "page#frag", in: rendered)?.runs.allSatisfy { $0.link?.scheme == "https" } == true)
    }

    @Test func channelLinkRoundTrip() throws {
        for name in ["#vela", "##linux", "&local", "#c++", "#a/b"] {
            let url = try #require(ChannelLink.url(for: name))
            #expect(ChannelLink.channel(from: url) == name)
        }
        #expect(ChannelLink.channel(from: URL(string: "https://example.com/#x")!) == nil)
    }

    @Test func mentionsOfOurNick() {
        #expect(MessageTextRenderer.mentionRanges(of: "doug", in: "Doug: hi doug_ and doug, not dougie").count == 2)
        let rendered = render("hey doug!")
        #expect(runs(of: "doug", in: rendered)?.runs.first?.foregroundColor == palette.mention)
        // Our own messages don't highlight our nick.
        let own = MessageTextRenderer.render("I'm doug", palette: palette, options: MessageTextOptions(selfNick: "doug"), highlightMentions: false)
        #expect(own.attributed.runs.allSatisfy { $0.foregroundColor == nil })
    }

    @Test func emojiOnlyDetection() {
        #expect(EmojiDetection.isEmojiOnly("👍"))
        #expect(EmojiDetection.isEmojiOnly("🎉 🎉"))
        #expect(EmojiDetection.isEmojiOnly("❤️👨‍👩‍👧"))
        #expect(EmojiDetection.isEmojiOnly("1️⃣"))
        #expect(!EmojiDetection.isEmojiOnly("👍👍👍👍"))
        #expect(!EmojiDetection.isEmojiOnly("on it 👍"))
        #expect(!EmojiDetection.isEmojiOnly("123"))
        #expect(!EmojiDetection.isEmojiOnly("©"))
        #expect(!EmojiDetection.isEmojiOnly("   "))
    }

    @Test func paletteFromTheSameThemeIsEqual() {
        // The text cache is only kept while the palette compares equal, so
        // rebuilding it from an unchanged theme must not invalidate it.
        let style = ChatStyle()
        #expect(MessageTextPalette(theme: .fallbackDark, style: style) == MessageTextPalette(theme: .fallbackDark, style: style))
        #expect(MessageTextPalette(theme: .fallbackDark, style: style) != MessageTextPalette(theme: .fallbackLight, style: style))
    }

    @Test func textCacheRendersOncePerLine() {
        let cache = MessageTextCache()
        cache.prepare(palette: palette, options: MessageTextOptions(selfNick: "doug"))
        var line = ChatLine(kind: .message, nick: "a", text: "hello https://a.example")
        let first = cache.rendered(line)
        #expect(first.links.count == 1)
        line.text = "edited"
        #expect(cache.rendered(line).plain == "edited")
    }
}

@MainActor
@Suite("Emoji catalog")
struct EmojiCatalogTests {
    @Test func searchUsesNamesAndAliases() {
        #expect(EmojiCatalog.search("+1").first == "👍")
        #expect(EmojiCatalog.search("tada").contains("🎉"))
        #expect(EmojiCatalog.search("thumbs").contains("👍"))
        #expect(EmojiCatalog.search("heart").contains("❤️"))
        #expect(EmojiCatalog.search("face joy").contains("😂"))
        #expect(EmojiCatalog.search("zzzzqqq").isEmpty)
    }

    @Test func everyEmojiHasAName() {
        for category in EmojiCatalog.categories {
            for emoji in category.emoji {
                #expect(EmojiCatalog.entries[emoji]?.name.isEmpty == false, "\(emoji) has no name")
                #expect(EmojiDetection.isEmoji(Character(emoji)), "\(emoji) isn't detected as emoji")
            }
        }
    }

    @Test func flagsAreNamedByRegion() {
        #expect(EmojiCatalog.displayName(for: "🇯🇵").hasPrefix("Flag: "))
    }
}
