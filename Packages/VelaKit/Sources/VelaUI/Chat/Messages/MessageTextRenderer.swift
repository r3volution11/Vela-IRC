// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import VelaCore
import VelaIRC
import VelaMedia
import VelaTheme

/// Colors and fonts the renderer bakes into attributed text, resolved once
/// from the theme and chat style.
nonisolated struct MessageTextPalette: Equatable, Sendable {
    var foreground: Color
    var background: Color
    var link: Color
    var mention: Color
    var codeForeground: Color
    var codeBackground: Color
    /// mIRC colors 0–98.
    var irc: [Color]
    var monospaceFont: Font

    @MainActor
    init(theme: ResolvedTheme, style: ChatStyle) {
        foreground = theme[ThemeKey.chatForeground]
        background = theme[ThemeKey.chatBackground]
        link = theme[ThemeKey.chatLink]
        mention = theme[ThemeKey.chatMention]
        codeForeground = theme[ThemeKey.chatCodeForeground]
        codeBackground = theme[ThemeKey.chatCodeBackground]
        irc = theme.ircColors.map(\.color)
        monospaceFont = style.monospaceFont
    }

    init(
        foreground: Color, background: Color, link: Color, mention: Color,
        codeForeground: Color, codeBackground: Color, irc: [Color], monospaceFont: Font
    ) {
        self.foreground = foreground
        self.background = background
        self.link = link
        self.mention = mention
        self.codeForeground = codeForeground
        self.codeBackground = codeBackground
        self.irc = irc
        self.monospaceFont = monospaceFont
    }

    func color(_ color: IRCColor) -> Color? {
        switch color {
        case .palette(let index):
            return irc.indices.contains(index) ? irc[index] : nil
        case .rgb(let value):
            return Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        }
    }
}

/// Everything besides the palette that changes how text renders.
nonisolated struct MessageTextOptions: Equatable, Sendable {
    var renderFormatting = true
    /// Our nick, highlighted where it's mentioned. Empty disables mentions.
    var selfNick = ""
    var channelTypes: Set<Character> = ["#"]
}

/// A message body ready to draw.
nonisolated struct RenderedText: Sendable {
    var attributed: AttributedString
    /// The text with formatting codes removed.
    var plain: String
    var links: [URL]
    /// One to three emoji and nothing else.
    var isEmojiOnly: Bool
}

/// Turns IRC message text into an AttributedString: mIRC formatting, links,
/// clickable channel names and mentions of our nick.
nonisolated enum MessageTextRenderer {
    static func render(
        _ text: String,
        palette: MessageTextPalette,
        options: MessageTextOptions,
        highlightMentions: Bool = true
    ) -> RenderedText {
        let spans = options.renderFormatting
            ? IRCFormatting.parse(text)
            : [IRCTextSpan(text: IRCFormatting.strip(text))]

        var attributed = AttributedString()
        var plain = ""
        for span in spans where !span.text.isEmpty {
            var piece = AttributedString(span.text)
            apply(span.style, to: &piece, palette: palette)
            attributed.append(piece)
            plain += span.text
        }

        let detected = LinkDetector.links(in: plain)
        for link in detected {
            guard let range = attributedRange(link.range, in: plain, attributed: attributed) else { continue }
            attributed[range].link = link.url
            attributed[range].foregroundColor = palette.link
        }

        let linkRanges = detected.map(\.range)
        for channel in channelRanges(in: plain, types: options.channelTypes)
        where !linkRanges.contains(where: { $0.overlaps(channel) }) {
            guard let url = ChannelLink.url(for: String(plain[channel])),
                  let range = attributedRange(channel, in: plain, attributed: attributed) else { continue }
            attributed[range].link = url
            attributed[range].foregroundColor = palette.link
        }

        if highlightMentions, !options.selfNick.isEmpty {
            for mention in mentionRanges(of: options.selfNick, in: plain)
            where !linkRanges.contains(where: { $0.overlaps(mention) }) {
                guard let range = attributedRange(mention, in: plain, attributed: attributed) else { continue }
                attributed[range].foregroundColor = palette.mention
                attributed[range].inlinePresentationIntent = (attributed[range].inlinePresentationIntent ?? []).union(.stronglyEmphasized)
            }
        }

        return RenderedText(
            attributed: attributed,
            plain: plain,
            links: detected.map(\.url),
            isEmojiOnly: EmojiDetection.isEmojiOnly(plain)
        )
    }

    private static func apply(_ style: IRCTextStyle, to piece: inout AttributedString, palette: MessageTextPalette) {
        guard !style.isPlain else { return }
        var intent: InlinePresentationIntent = []
        if style.bold { intent.insert(.stronglyEmphasized) }
        if style.italic { intent.insert(.emphasized) }
        if !intent.isEmpty { piece.inlinePresentationIntent = intent }
        if style.underline { piece.underlineStyle = .single }
        if style.strikethrough { piece.strikethroughStyle = .single }

        var foreground = style.foreground.flatMap(palette.color)
        var background = style.background.flatMap(palette.color)
        if style.monospace {
            piece.font = palette.monospaceFont
            foreground = foreground ?? palette.codeForeground
            background = background ?? palette.codeBackground
        }
        if style.reverse {
            (foreground, background) = (background ?? palette.background, foreground ?? palette.foreground)
        }
        if let foreground { piece.foregroundColor = foreground }
        if let background { piece.backgroundColor = background }
    }

    /// Converts a range of `plain` into the matching range of `attributed`,
    /// which holds the same characters.
    static func attributedRange(
        _ range: Range<String.Index>,
        in plain: String,
        attributed: AttributedString
    ) -> Range<AttributedString.Index>? {
        Range(NSRange(range, in: plain), in: attributed)
    }

    // MARK: Channels

    /// `#channel` tokens at word starts. Names need a letter, so "#1" (an
    /// issue number) isn't treated as a channel.
    static func channelRanges(in text: String, types: Set<Character>) -> [Range<String.Index>] {
        guard !types.isEmpty, text.contains(where: { types.contains($0) }) else { return [] }
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        var previous: Character?
        while index < text.endIndex {
            let character = text[index]
            let atWordStart = previous.map { $0.isWhitespace || "([{<\"'".contains($0) } ?? true
            if atWordStart, types.contains(character) {
                var end = text.index(after: index)
                while end < text.endIndex, !text[end].isWhitespace, !",\u{07}".contains(text[end]) {
                    end = text.index(after: end)
                }
                // Trailing sentence punctuation and closing brackets aren't part of the name.
                while end > text.index(after: index), ".!?:;)]}>\"'".contains(text[text.index(before: end)]) {
                    end = text.index(before: end)
                }
                let name = text[text.index(after: index)..<end]
                if name.contains(where: \.isLetter) {
                    ranges.append(index..<end)
                }
                previous = text[text.index(before: end)]
                index = end
                continue
            }
            previous = character
            index = text.index(after: index)
        }
        return ranges
    }

    // MARK: Mentions

    /// Case-insensitive whole-word occurrences of `nick`.
    static func mentionRanges(of nick: String, in text: String) -> [Range<String.Index>] {
        guard !nick.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let found = text.range(of: nick, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
            let before = found.lowerBound > text.startIndex ? text[text.index(before: found.lowerBound)] : nil
            let after = found.upperBound < text.endIndex ? text[found.upperBound] : nil
            if !isNickCharacter(before), !isNickCharacter(after) {
                ranges.append(found)
            }
            searchStart = found.upperBound
        }
        return ranges
    }

    private static func isNickCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || "_-[]\\`^{}|".contains(character)
    }
}

/// `vela://join/<channel>` links for channel names in messages.
nonisolated enum ChannelLink {
    static let scheme = "vela"
    static let host = "join"

    static func url(for channel: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + channel
        return components.url
    }

    static func channel(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let name = String(components.path.drop { $0 == "/" })
        return name.isEmpty ? nil : name
    }
}

nonisolated enum EmojiDetection {
    /// True for characters drawn as emoji (not text symbols such as `©` or digits).
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        guard first.properties.isEmoji else { return false }
        // Text-default emoji (digits, ©, ↔…) only count with a variation
        // selector, keycap or modifier attached.
        return scalars.count > 1 || first.value > 0x238C
    }

    /// One to `limit` emoji, optionally separated by spaces, and nothing else.
    static func isEmojiOnly(_ text: String, limit: Int = 3) -> Bool {
        var count = 0
        for character in text where !character.isWhitespace {
            guard isEmoji(character) else { return false }
            count += 1
            if count > limit { return false }
        }
        return count > 0
    }
}

/// Memoizes rendered message text per line. Entries are dropped when the
/// palette or options change (theme switch, font change, nick change).
@MainActor
final class MessageTextCache {
    private var palette: MessageTextPalette?
    private var options = MessageTextOptions()
    private var entries: [UUID: Entry] = [:]
    private let capacity = 4_000

    private struct Entry {
        var text: String
        var rendered: RenderedText
    }

    /// Call once per list update; cheap when nothing changed.
    func prepare(palette: MessageTextPalette, options: MessageTextOptions) {
        guard palette != self.palette || options != self.options else { return }
        self.palette = palette
        self.options = options
        entries.removeAll(keepingCapacity: true)
    }

    func rendered(_ line: ChatLine) -> RenderedText {
        if let entry = entries[line.id], entry.text == line.text { return entry.rendered }
        guard let palette else {
            return RenderedText(attributed: AttributedString(line.text), plain: line.text, links: [], isEmojiOnly: false)
        }
        let rendered = MessageTextRenderer.render(line.text, palette: palette, options: options, highlightMentions: !line.isSelf)
        if entries.count >= capacity { entries.removeAll(keepingCapacity: true) }
        entries[line.id] = Entry(text: line.text, rendered: rendered)
        return rendered
    }
}
