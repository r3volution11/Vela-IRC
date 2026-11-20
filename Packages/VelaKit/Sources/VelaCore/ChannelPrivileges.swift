// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaIRC
import VelaStore

/// What you may do to people in one channel, from your rank there.
///
/// Ranks come from ISUPPORT PREFIX, highest first: `(qaohv)~&@%+` ranks
/// owner, admin, op, halfop, voice. Without PREFIX it's `(ov)@+`. The rules
/// are deliberately conservative, so the menus never offer what the server
/// is likely to refuse (no IRC operator or services overrides):
///
/// - **Changing a rank** (a prefix mode `m` on someone): an op or higher
///   may set or remove `m` when it ranks below their own, and anyone at
///   least an op may set or remove `o`. A halfop may set or remove modes
///   below halfop (voice). So an owner can give `a`, `o`, `h` and `v`, but
///   an admin can't give `a`.
/// - **Who it can be done to**: someone ranked at or below you when you're
///   an op or higher, and only people below halfop when you're a halfop
///   (UnrealIRCd and InspIRCd protect owners and admins from lower ranks).
/// - **Your own modes**: you can always remove them.
/// - **Kick, ban and quiet**: you need to be at least a halfop, and the
///   same "who" rule applies. Never yourself.
nonisolated public struct ChannelPrivileges: Sendable, Hashable {
    /// Membership modes in rank order, highest first.
    public let ranks: [Character]
    /// The membership modes you hold in the channel.
    public let ownModes: Set<Character>

    public init(ranks: [Character], ownModes: Set<Character>) {
        self.ranks = ranks
        self.ownModes = ownModes
    }

    /// From ISUPPORT PREFIX and your entry in the member list (its prefix
    /// symbols).
    public init(isupport: ISupport, ownPrefixes: String) {
        self.init(ranks: isupport.prefixModes, ownModes: Self.modes(forSymbols: ownPrefixes, isupport: isupport))
    }

    /// The mode letters for prefix symbols such as `"@+"`.
    public static func modes(forSymbols symbols: String, isupport: ISupport) -> Set<Character> {
        let prefixes = isupport.prefixes
        return Set(symbols.compactMap { symbol in prefixes.first { $0.symbol == symbol }?.mode })
    }

    // MARK: Ranks

    /// Where `mode` ranks (0 is the highest), or nil when the server has no
    /// such membership mode.
    public func rank(of mode: Character) -> Int? {
        ranks.firstIndex(of: mode)
    }

    /// The rank of the highest of `modes`, or `ranks.count` (below every
    /// rank) for someone without one.
    public func topRank(of modes: Set<Character>) -> Int {
        ranks.firstIndex(where: modes.contains) ?? ranks.count
    }

    /// Your own rank (see `topRank(of:)`).
    public var ownRank: Int { topRank(of: ownModes) }

    /// Whether you hold `mode` or a higher one. False when the server has
    /// no such mode.
    public func isAtLeast(_ mode: Character) -> Bool {
        guard let target = rank(of: mode) else { return false }
        return ownRank <= target
    }

    /// An op or higher.
    public var isOperator: Bool { isAtLeast("o") }

    /// A halfop or higher.
    public var isHalfOperator: Bool { isAtLeast("h") || isOperator }

    /// Whether you can moderate anyone at all: change ranks, kick or ban.
    public var canModerate: Bool { isHalfOperator }

    // MARK: Rules

    /// Whether you may act on someone holding `modes`: they rank at or
    /// below you (op or higher), or below halfop (halfop).
    public func canActOn(_ modes: Set<Character>) -> Bool {
        let target = topRank(of: modes)
        if isOperator { return target >= ownRank }
        if let halfop = rank(of: "h"), isAtLeast("h") { return target > halfop }
        return false
    }

    /// Whether you may set or remove `mode` at all, whoever it's on.
    public func canAssign(_ mode: Character) -> Bool {
        guard let modeRank = rank(of: mode) else { return false }
        if isOperator { return modeRank > ownRank || mode == "o" }
        if let halfop = rank(of: "h"), isAtLeast("h") { return modeRank > halfop }
        return false
    }

    /// Whether you're allowed to give (`adding`) or take `mode` from
    /// someone holding `targetModes`, whether or not they have it.
    public func mayChange(_ mode: Character, adding: Bool, targetModes: Set<Character>, targetIsSelf: Bool) -> Bool {
        guard rank(of: mode) != nil else { return false }
        if targetIsSelf, !adding, targetModes.contains(mode) { return true }
        guard canAssign(mode) else { return false }
        return targetIsSelf || canActOn(targetModes)
    }

    /// Whether you may give (`adding`) or take `mode` from someone holding
    /// `targetModes`, and it would change something: giving a mode they
    /// have, or taking one they don't, isn't offered.
    public func canChange(_ mode: Character, adding: Bool, targetModes: Set<Character>, targetIsSelf: Bool) -> Bool {
        targetModes.contains(mode) != adding && mayChange(mode, adding: adding, targetModes: targetModes, targetIsSelf: targetIsSelf)
    }

    /// Whether you may kick, ban or quiet someone holding `targetModes`.
    public func canRemove(targetModes: Set<Character>, targetIsSelf: Bool) -> Bool {
        guard !targetIsSelf, isHalfOperator else { return false }
        return canActOn(targetModes)
    }
}

// MARK: Ban masks

/// Builds the masks bans and quiets use (`moderation.banMask`).
nonisolated public enum BanMask {
    /// Whether `target` is already a mask (it has `!` or `@`) rather than
    /// a nick.
    public static func isMask(_ target: String) -> Bool {
        target.contains("!") || target.contains("@")
    }

    /// The mask for `nick` in `style`, from their `user@host` when it's
    /// known; `nick!*@*` when it isn't.
    public static func mask(nick: String, userHost: String?, style: BanMaskStyle) -> String {
        guard let userHost, let at = userHost.lastIndex(of: "@") else { return "\(nick)!*@*" }
        let user = userHost[..<at]
        let host = userHost[userHost.index(after: at)...]
        guard !host.isEmpty else { return "\(nick)!*@*" }
        switch style {
        case .host: return "*!*@\(host)"
        case .userHost: return user.isEmpty ? "*!*@\(host)" : "*!\(user)@\(host)"
        case .nick: return "\(nick)!*@*"
        }
    }

    /// Whether `style` needs someone's host (so it's worth asking the
    /// server for it).
    public static func needsHost(_ style: BanMaskStyle) -> Bool {
        style != .nick
    }
}

// MARK: Nicks in text

nonisolated public enum NickWords {
    /// Characters IRC nicks are made of besides letters and digits.
    static let specials: Set<Character> = ["[", "]", "\\", "`", "^", "{", "}", "|", "-", "_"]

    public static func isNickCharacter(_ character: Character) -> Bool {
        // Most text is ASCII: a table lookup gives the same answer as the
        // Unicode properties and the set, without hashing a Character.
        if let ascii = character.asciiValue, character.utf8.count == 1 { return asciiNickCharacters[Int(ascii)] }
        return character.isLetter || character.isNumber || specials.contains(character)
    }

    private static let asciiNickCharacters: [Bool] = (0..<128).map { value in
        let character = Character(Unicode.Scalar(UInt8(value)))
        return character.isLetter || character.isNumber || specials.contains(character)
    }

    /// Calls `body` with the range of each nick-like word in `text`, in
    /// order: the words `word(at:in:)` finds (and a right-click on one opens
    /// that nick's menu). One pass over the characters.
    public static func forEachWord(in text: String, _ body: (Range<String.Index>) -> Void) {
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if isNickCharacter(text[index]) {
                if start == nil { start = index }
            } else if let wordStart = start {
                emit(wordStart..<index, in: text, body)
                start = nil
            }
            index = next
        }
        if let wordStart = start { emit(wordStart..<text.endIndex, in: text, body) }
    }

    /// `word(at:in:)`'s rule: a lone hyphen or underscore isn't a word.
    private static func emit(_ range: Range<String.Index>, in text: String, _ body: (Range<String.Index>) -> Void) {
        if text.index(after: range.lowerBound) == range.upperBound {
            let character = text[range.lowerBound]
            guard character.isLetter || character.isNumber else { return }
        }
        body(range)
    }

    /// The nick-like word around UTF-16 offset `offset` in `text` (letters,
    /// digits and `[]\`^{}|-_`), so "marisol:" or "<marisol>" gives
    /// "marisol". Nil when there's no word there.
    public static func word(at offset: Int, in text: String) -> (word: String, range: Range<Int>)? {
        let utf16 = text.utf16
        guard offset >= 0, offset < utf16.count,
              let index = utf16.index(utf16.startIndex, offsetBy: offset, limitedBy: utf16.endIndex),
              let position = index.samePosition(in: text) ?? text.indices.last(where: { $0 <= index })
        else { return nil }
        guard position < text.endIndex, isNickCharacter(text[position]) else { return nil }
        var start = position
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard isNickCharacter(text[previous]) else { break }
            start = previous
        }
        var end = text.index(after: position)
        while end < text.endIndex, isNickCharacter(text[end]) {
            end = text.index(after: end)
        }
        // Trailing hyphens and underscores belong to nicks ("doug_"), but
        // a word that's only punctuation isn't one.
        let word = String(text[start..<end])
        guard word.contains(where: { $0.isLetter || $0.isNumber }) || word.count > 1 else { return nil }
        let lower = utf16.distance(from: utf16.startIndex, to: start)
        let upper = lower + word.utf16.count
        return (word, lower..<upper)
    }
}
