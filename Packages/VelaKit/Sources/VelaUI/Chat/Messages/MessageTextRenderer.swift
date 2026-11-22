// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import VelaCore
import VelaIntents
import VelaFoundation
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
    /// The theme's nick colors (`ResolvedTheme.nickPalette`), for nicks in
    /// the text. Part of the palette so a theme switch re-renders them.
    var nickColors: [Color]
    /// Their shape, for a conversation's assignment
    /// (`BufferModel.nickColorIndex(for:palette:)`).
    var nickGeometry: NickPaletteGeometry

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
        nickColors = theme.nickPalette.map(\.color)
        nickGeometry = theme.nickPaletteGeometry
    }

    init(
        foreground: Color, background: Color, link: Color, mention: Color,
        codeForeground: Color, codeBackground: Color, irc: [Color], monospaceFont: Font,
        nickColors: [Color] = [], nickGeometry: NickPaletteGeometry = NickPaletteGeometry(distances: [])
    ) {
        self.foreground = foreground
        self.background = background
        self.link = link
        self.mention = mention
        self.codeForeground = codeForeground
        self.codeBackground = codeBackground
        self.irc = irc
        self.monospaceFont = monospaceFont
        self.nickColors = nickColors
        self.nickGeometry = nickGeometry
    }

    /// The nick color at `index` (wrapping, like `ResolvedTheme.nickColor(at:)`).
    func nickColor(at index: Int) -> Color? {
        guard !nickColors.isEmpty else { return nil }
        return nickColors[((index % nickColors.count) + nickColors.count) % nickColors.count]
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

extension MessageTextPalette {
    private struct Inputs: Equatable {
        var theme: ResolvedTheme
        var monospaceFont: Font
    }

    @MainActor private static var memo: (inputs: Inputs, palette: MessageTextPalette)?

    /// `init(theme:style:)`, kept for the last theme and font. The message
    /// list asks on every update, and mapping the 99 mIRC colors each time
    /// adds up. An unchanged theme compares cheaply (its arrays and
    /// dictionaries are the same storage).
    @MainActor
    static func cached(theme: ResolvedTheme, style: ChatStyle) -> MessageTextPalette {
        let inputs = Inputs(theme: theme, monospaceFont: style.monospaceFont)
        if let memo, memo.inputs == inputs { return memo.palette }
        let palette = MessageTextPalette(theme: theme, style: style)
        memo = (inputs, palette)
        return palette
    }
}

/// Everything besides the palette that changes how text renders.
nonisolated struct MessageTextOptions: Equatable, Sendable {
    var renderFormatting = true
    /// Our nick, highlighted where it's mentioned. Empty disables mentions.
    var selfNick = ""
    var channelTypes: Set<Character> = ["#"]
    /// Color the nicks of people here where the text mentions them
    /// (`chat.colorNicks` and `chat.colorNicksInText`, in a channel or a
    /// conversation). Who's here comes with each render (`NickLookup`).
    var colorsNicks = false
    /// The network's casemapping, which nicks in the text are matched by.
    var caseMapping: CaseMapping = .rfc1459
}

/// Who a message's words might be, for coloring nicks in its text: given a
/// word and its case-folded form, the index of their color in
/// `MessageTextPalette.nickColors` when it's the nick of someone here, nil
/// for any other word. Called once per nick-like word, so it must be a
/// hash lookup (`MessageListController.nickColorIndex(word:folded:geometry:)`).
typealias NickLookup = (_ word: Substring, _ folded: String) -> Int?

/// A message body ready to draw.
nonisolated struct RenderedText: Sendable {
    var attributed: AttributedString
    /// The text with formatting codes removed.
    var plain: String
    var links: [URL]
    /// One to three emoji and nothing else.
    var isEmojiOnly: Bool
    /// The runs of `attributed` that are links, channel names included
    /// (for VoiceOver's actions, made once here rather than per row).
    var linkRuns: [LinkRuns.Link] = []
    /// Hashes of the case-folded words that would be colored if they were
    /// the nick of someone here, whether or not they are now, sorted.
    /// When someone joins, leaves or gets another color, the text cache
    /// drops the renderings with their nick here, and only those
    /// (`MessageTextCache.invalidate(nickKeys:)`). Empty without nick
    /// coloring.
    var nickKeys: [Int] = []

    /// Whether this text has a word that folds to one of `keys` (hashes
    /// from `MessageTextRenderer.nickKey(_:)`).
    func mentions(anyOf keys: Set<Int>) -> Bool {
        Self.keys(nickKeys, containAnyOf: keys)
    }

    /// Whether sorted `nickKeys` and `keys` share one: a binary search per
    /// key for the usual handful, a hash lookup per word for a crowd.
    static func keys(_ nickKeys: [Int], containAnyOf keys: Set<Int>) -> Bool {
        guard !nickKeys.isEmpty else { return false }
        if keys.count <= 4 {
            return keys.contains { key in sortedContains(nickKeys, key) }
        }
        return nickKeys.contains(where: keys.contains)
    }

    private static func sortedContains(_ sorted: [Int], _ key: Int) -> Bool {
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < key { low = mid + 1 } else { high = mid }
        }
        return low < sorted.count && sorted[low] == key
    }
}

/// Turns IRC message text into an AttributedString: mIRC formatting, links,
/// clickable channel names, the nicks of people here and mentions of our
/// nick.
nonisolated enum MessageTextRenderer {
    /// `nicks`, when given with `options.colorsNicks`, finds the people here
    /// among the words of the text, whose nicks are then drawn in their
    /// color (see `colorNicks`).
    static func render(
        _ text: String,
        palette: MessageTextPalette,
        options: MessageTextOptions,
        highlightMentions: Bool = true,
        nicks: NickLookup? = nil
    ) -> RenderedText {
        let spans = options.renderFormatting
            ? IRCFormatting.parse(text)
            : [IRCTextSpan(text: IRCFormatting.strip(text))]

        let colorsNicks = options.colorsNicks && nicks != nil
        var attributed = AttributedString()
        var plain = ""
        /// Where the sender chose colors (UTF-8 offsets into `plain`),
        /// which nick colors leave alone.
        var senderColored: [Range<Int>] = []
        for span in spans where !span.text.isEmpty {
            var piece = AttributedString(span.text)
            apply(span.style, to: &piece, palette: palette)
            attributed.append(piece)
            if colorsNicks, span.style.setsColors {
                let start = plain.utf8.count
                senderColored.append(start..<(start + span.text.utf8.count))
            }
            plain += span.text
        }

        let detected = LinkDetector.links(in: plain)
        for link in detected {
            guard let range = attributedRange(link.range, in: plain, attributed: attributed) else { continue }
            attributed[range].link = link.url
            attributed[range].foregroundColor = palette.link
        }

        let linkRanges = detected.map(\.range)
        var hasLinks = !detected.isEmpty
        var channels: [Range<String.Index>] = []
        for channel in channelRanges(in: plain, types: options.channelTypes)
        where !linkRanges.contains(where: { $0.overlaps(channel) }) {
            guard let url = ChannelLink.url(for: String(plain[channel])),
                  let range = attributedRange(channel, in: plain, attributed: attributed) else { continue }
            attributed[range].link = url
            attributed[range].foregroundColor = palette.link
            hasLinks = true
            channels.append(channel)
        }

        var nickKeys: [Int] = []
        if colorsNicks, let nicks {
            let utf8 = plain.utf8
            func offsets(_ range: Range<String.Index>) -> Range<Int> {
                utf8.distance(from: utf8.startIndex, to: range.lowerBound)..<utf8.distance(from: utf8.startIndex, to: range.upperBound)
            }
            let excluded = senderColored + (linkRanges + channels).map(offsets)
            nickKeys = colorNicks(
                in: plain, attributed: &attributed, excluded: excluded,
                selfNick: options.selfNick, caseMapping: options.caseMapping, palette: palette, nicks: nicks
            )
        }

        // Last, so a mention of our nick keeps its own style.
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
            isEmojiOnly: EmojiDetection.isEmojiOnly(plain),
            linkRuns: hasLinks ? LinkRuns.links(in: attributed) : [],
            nickKeys: nickKeys
        )
    }

    // MARK: Nicks

    /// Colors the nicks of people here in `plain` (mirrored in
    /// `attributed`) and returns the keys of every word that could be a
    /// nick (`RenderedText.nickKeys`).
    ///
    /// One pass over the words, by the rules a right-click on a nick uses
    /// (`NickWords`), so what's colored is what opens a nick's menu. Each
    /// word of two or more characters is case-folded by the network's
    /// casemapping and looked up in `nicks`, a hash lookup: the cost per
    /// row is a fold and a lookup per word, plus coloring the few that
    /// match. Words inside links, channel names and text the sender colored
    /// (`excluded`, UTF-8 offsets) are skipped, and our own nick is left to
    /// the mention style.
    private static func colorNicks(
        in plain: String,
        attributed: inout AttributedString,
        excluded: [Range<Int>],
        selfNick: String,
        caseMapping: CaseMapping,
        palette: MessageTextPalette,
        nicks: NickLookup
    ) -> [Int] {
        let utf8 = plain.utf8
        let excluded = excluded.sorted { $0.lowerBound < $1.lowerBound }
        var nextExcluded = 0
        let foldedSelf = selfNick.isEmpty ? "" : caseMapping.fold(selfNick)
        var keys: [Int] = []
        NickWords.forEachWord(in: plain) { range in
            // One-character nicks would color every "a" and "I".
            guard plain.index(after: range.lowerBound) < range.upperBound else { return }
            if !excluded.isEmpty {
                let lower = utf8.distance(from: utf8.startIndex, to: range.lowerBound)
                let upper = utf8.distance(from: utf8.startIndex, to: range.upperBound)
                // Words come in order: skip what ends before this one.
                while nextExcluded < excluded.count, excluded[nextExcluded].upperBound <= lower { nextExcluded += 1 }
                if nextExcluded < excluded.count, excluded[nextExcluded].lowerBound < upper { return }
            }
            let word = plain[range]
            let folded = caseMapping.fold(String(word))
            guard folded != foldedSelf else { return }
            keys.append(nickKey(folded))
            guard let index = nicks(word, folded), let color = palette.nickColor(at: index),
                  let target = attributedRange(range, in: plain, attributed: attributed) else { return }
            attributed[target].foregroundColor = color
        }
        keys.sort()
        // Repeated words share a key.
        var unique: [Int] = []
        unique.reserveCapacity(keys.count)
        for key in keys where key != unique.last { unique.append(key) }
        return unique
    }

    /// The key a case-folded nick has in `RenderedText.nickKeys`.
    static func nickKey(_ folded: String) -> Int {
        folded.hashValue
    }

    // MARK: Formatting

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

extension IRCTextStyle {
    /// Colors the sender chose: mIRC colors, reverse, or monospace (drawn
    /// in the code colors). Nick coloring leaves these alone.
    nonisolated var setsColors: Bool {
        foreground != nil || background != nil || reverse || monospace
    }
}

/// `vela://join/<channel>` links for channel names in messages. Read back
/// through the same parser as every other `vela://` link (``VelaLink``);
/// clicked in a message, one joins on that message's network.
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
        guard case .join(let channel, nil) = VelaLink.parse(url) else { return nil }
        return channel
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
/// palette or options change (theme switch, font change, nick change), all
/// at once, and when someone joins, leaves or gets another nick color, only
/// those whose text has that nick (`invalidate(nickKeys:)`).
///
/// When full, the least recently used half goes, so the rows around the
/// one being read stay rendered. It holds 4,000 lines (2,000 on a Mac with
/// 8 GB) and gives memory back under memory pressure.
@MainActor
final class MessageTextCache {
    private var palette: MessageTextPalette?
    private var options = MessageTextOptions()
    /// Who's here, for nicks in messages (`MessageTextRenderer.render`).
    private var nicks: NickLookup?
    private var entries: [UUID: Entry] = [:]
    /// Each entry's `RenderedText.nickKeys`, when it has any, kept apart so
    /// `invalidate(nickKeys:)` scans small arrays rather than copying every
    /// entry (its attributed text and strings) out of `entries`.
    private var nickKeys: [UUID: [Int]] = [:]
    private var tick: UInt64 = 0
    let capacity: Int

    private struct Entry {
        var text: String
        var rendered: RenderedText
        var lastUse: UInt64
    }

    init(capacity: Int = MemoryBudget.scaled(4_000)) {
        self.capacity = max(2, capacity)
        MemoryPressureMonitor.shared.register(self) { cache, level in cache.trim(for: level) }
    }

    var count: Int { entries.count }

    /// Call once per list update; cheap when nothing changed. `nicks` finds
    /// the people here when `options.colorsNicks` (it's kept, not compared:
    /// the list says when who's here changes, with `invalidate(nickKeys:)`).
    func prepare(palette: MessageTextPalette, options: MessageTextOptions, nicks: NickLookup? = nil) {
        self.nicks = nicks
        guard palette != self.palette || options != self.options else { return }
        self.palette = palette
        self.options = options
        removeAll()
    }

    func rendered(_ line: ChatLine) -> RenderedText {
        tick &+= 1
        if let index = entries.index(forKey: line.id), entries.values[index].text == line.text {
            entries.values[index].lastUse = tick
            return entries.values[index].rendered
        }
        guard let palette else {
            return RenderedText(attributed: AttributedString(line.text), plain: line.text, links: [], isEmojiOnly: false)
        }
        // Only what people say: event lines (topics, kicks, modes) keep
        // their own look.
        let rendered = MessageTextRenderer.render(
            line.text, palette: palette, options: options, highlightMentions: !line.isSelf,
            nicks: line.kind.isConversation ? nicks : nil
        )
        if entries.count >= capacity { trim(keepingNewest: capacity / 2) }
        entries[line.id] = Entry(text: line.text, rendered: rendered, lastUse: tick)
        if rendered.nickKeys.isEmpty {
            nickKeys.removeValue(forKey: line.id)
        } else {
            nickKeys[line.id] = rendered.nickKeys
        }
        return rendered
    }

    /// Drops the renderings whose text has a nick-like word with one of
    /// `keys` (`MessageTextRenderer.nickKey(_:)`), and says whose lines
    /// they were. A binary search per key in each entry's sorted keys, over
    /// a few thousand small arrays: well under a millisecond for a full
    /// cache, and the lines that don't mention anyone who came or went
    /// keep their rendering.
    func invalidate(nickKeys keys: Set<Int>) -> [UUID] {
        guard !keys.isEmpty, !nickKeys.isEmpty else { return [] }
        var dropped: [UUID] = []
        for (id, lineKeys) in nickKeys where RenderedText.keys(lineKeys, containAnyOf: keys) {
            dropped.append(id)
        }
        for id in dropped {
            entries.removeValue(forKey: id)
            nickKeys.removeValue(forKey: id)
        }
        return dropped
    }

    /// Drops every rendering (who's here changed too much to sort out).
    func removeAll() {
        entries.removeAll(keepingCapacity: true)
        nickKeys.removeAll(keepingCapacity: true)
    }

    /// Half on a warning; everything when critical (rows on screen keep
    /// the text they drew).
    func trim(for level: MemoryPressureLevel) {
        switch level {
        case .warning: trim(keepingNewest: entries.count / 2)
        case .critical:
            entries.removeAll()
            nickKeys.removeAll()
        }
    }

    private func trim(keepingNewest count: Int) {
        guard entries.count > count else { return }
        let oldest = entries.sorted { $0.value.lastUse < $1.value.lastUse }.prefix(entries.count - count)
        for (id, _) in oldest {
            entries.removeValue(forKey: id)
            nickKeys.removeValue(forKey: id)
        }
    }
}
