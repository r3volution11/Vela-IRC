// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The shape of a nick color palette, as the assigner needs it: how many
/// colors, how different each pair looks, and which are kept back.
public struct NickPaletteGeometry: Sendable, Hashable {
    /// Perceptual distance between palette entries (`distances[i][j]`).
    public let distances: [[Double]]
    /// Entries closer than this look alike side by side.
    public let similar: Double
    /// Entries nobody is given: those that look like your own nick's color
    /// (`chat.selfNick`), which is in every conversation. Never all of them.
    public let reserved: Set<Int>
    /// Tells palettes apart cheaply (checked on every lookup).
    public let signature: Int
    /// Each entry, or for a reserved one the unreserved entry most like it:
    /// where a nick that hashes to it starts.
    let usualIndexes: [Int]
    /// The entries that can be given (all but `reserved`), in palette order.
    public let available: [Int]

    public var count: Int { distances.count }

    /// OKLab distance under which two nick colors read as alike: red and
    /// orange, blue and lavender, teal and cyan in a typical palette.
    public static let oklabSimilar = 0.11

    public init(distances: [[Double]], similar: Double = oklabSimilar, reserved: Set<Int> = []) {
        self.distances = distances
        self.similar = similar
        let count = distances.count
        // Something must be left to give out.
        let inRange = reserved.filter { (0..<count).contains($0) }
        let kept = inRange.count < count ? inRange : []
        let available = (0..<count).filter { !kept.contains($0) }
        self.reserved = kept
        self.available = available
        usualIndexes = (0..<count).map { index in
            guard kept.contains(index) else { return index }
            return available.min { distances[index][$0] < distances[index][$1] } ?? index
        }
        var hasher = Hasher()
        hasher.combine(distances)
        hasher.combine(similar)
        hasher.combine(kept)
        signature = hasher.finalize()
    }

    /// Where a nick hashed to `index` starts: `index`, unless it's reserved.
    public func usualIndex(_ index: Int) -> Int {
        usualIndexes.indices.contains(index) ? usualIndexes[index] : index
    }
}

/// Hands out nick colors (indexes into a palette) within one conversation,
/// so that people talking there can be told apart.
///
/// Everyone starts from their usual color, hashed from their nick, so the
/// same nick looks the same everywhere and across launches, and most
/// people never get anything else. A nick that hashes to a reserved color
/// (one that looks like your own nick's) starts from the unreserved color
/// most like it instead: nobody else is ever given yours. A newcomer only
/// gets another color when their usual one is needed elsewhere:
/// - it belongs to one of the recent speakers (the last `n - 1`, for the
///   `n` colors that can be given), or
/// - it looks like the color of someone in the current exchange (the last
///   few speakers), as red does beside orange.
/// They then get the palette color closest to their usual one that's
/// clearly different from everyone in the exchange. When every such color
/// is held by a recent speaker (a crowded channel), they share the color
/// of someone who spoke earlier but isn't in the exchange, rather than
/// look like someone who is. When even that fails, a look-alike keeps its
/// usual color, and only a duplicate moves, to the free color most unlike
/// the ones in use.
///
/// A color, once given, stays, with one exception. Colors are given as
/// people first speak, so two people given theirs apart (one spoke an hour
/// ago, the other just now, in a busy channel) can end up talking side by
/// side in one color, or in look-alikes. When someone speaks in a color
/// that looks like the color of someone in the exchange, one of the two
/// moves to the color closest to their usual one that's clearly different
/// from everyone in the exchange, chosen as for a newcomer: whoever had
/// spoken less recently before this message (usually the one coming back,
/// whose lines are further up, out of view), or the other when they've
/// moved this way before. Each nick moves like this at most once per
/// conversation, so nobody changes color back and forth; and when there's
/// no clearly different color to go to, nobody moves.
public struct NickColorAssigner: Sendable {
    public let palette: NickPaletteGeometry
    /// Case-folded nick → palette index.
    private var slots: [String: Int] = [:]
    /// Case-folded nicks that spoke, least recent first.
    private var recent: [String] = []
    /// Case-folded recent speaker → their nick as last sent, to say who
    /// moved.
    private var names: [String: String] = [:]
    /// Case-folded nicks moved off a look-alike, which don't move again.
    private var movedApart: Set<String> = []

    /// How many recent speakers to remember; only the last
    /// `palette.count - 1` matter when choosing a color.
    private static let recentLimit = 64
    /// The current exchange: the speakers whose colors a newcomer shouldn't
    /// resemble.
    private static let exchangeSize = 5

    /// Whose color a message changed (`noteSpeaker(_:)`), as their nicks
    /// were last sent.
    public struct Changes: Sendable, Hashable {
        /// The speaker, given a color other than their usual one as they
        /// first spoke. They have no earlier lines here.
        public var given: String?
        /// Someone who had a color and now has another, moved off a
        /// look-alike: the speaker, or the person they looked like. Lines
        /// they sent before change color too.
        public var moved: String?

        public init(given: String? = nil, moved: String? = nil) {
            self.given = given
            self.moved = moved
        }

        public var isEmpty: Bool { given == nil && moved == nil }
    }

    public init(palette: NickPaletteGeometry) {
        self.palette = palette
    }

    /// `nick`'s color: its own once it has spoken here, otherwise the
    /// color it would start from.
    public func index(for nick: String) -> Int {
        let key = Self.fold(nick)
        return slots[key] ?? usualIndex(folded: key)
    }

    /// Records that `nick` just spoke: gives it a color if it has none, or
    /// moves it or the person it looks like apart (see the type), and makes
    /// it the most recent speaker. Returns whose color that changed.
    @discardableResult
    public mutating func noteSpeaker(_ nick: String) -> Changes {
        let key = Self.fold(nick)
        var changes = Changes()
        names[key] = nick
        if slots[key] == nil {
            if assign(key) { changes.given = nick }
        } else if let moved = moveApart(key) {
            changes.moved = names[moved] ?? moved
        }
        if let index = recent.lastIndex(of: key) { recent.remove(at: index) }
        recent.append(key)
        if recent.count > Self.recentLimit {
            let gone = recent.count - Self.recentLimit
            // Names are only needed for the speakers who can move.
            for key in recent.prefix(gone) { names.removeValue(forKey: key) }
            recent.removeFirst(gone)
        }
        return changes
    }

    /// Gives `nick` a color if it has none, without making it a recent
    /// speaker: for older history loaded above what's on screen. Returns
    /// true when that changed the nick's color.
    @discardableResult
    public mutating func noteEarlierSpeaker(_ nick: String) -> Bool {
        assign(Self.fold(nick))
    }

    /// The color `nick` starts from in `palette`: its hashed entry, or the
    /// unreserved entry most like it (see `NickPaletteGeometry.reserved`).
    public static func usualIndex(for nick: String, palette: NickPaletteGeometry) -> Int {
        palette.usualIndex(preferredIndex(for: nick, paletteSize: palette.count))
    }

    private func usualIndex(folded key: String) -> Int {
        palette.usualIndex(Self.preferredIndex(folded: key, paletteSize: palette.count))
    }

    /// The colors of the last `count` speakers and `also`, leaving out
    /// `except`'s.
    private func colors(ofLast count: Int, also: String? = nil, except: String? = nil) -> Set<Int> {
        var keys = recent.suffix(count).filter { $0 != except }
        if let also, also != except { keys.append(also) }
        return Set(keys.compactMap { slots[$0] })
    }

    private func nearest(_ index: Int, among colors: Set<Int>) -> Double {
        colors.map { palette.distances[index][$0] }.min() ?? .infinity
    }

    /// Gives `key` a color if it has none. True when it isn't its usual one.
    private mutating func assign(_ key: String) -> Bool {
        guard slots[key] == nil else { return false }
        let size = palette.count
        let usual = usualIndex(folded: key)
        // Reserved colors are never given, so only the others count.
        let available = palette.available
        guard available.count > 1 else {
            slots[key] = usual
            return false
        }
        let distances = palette.distances
        let taken = colors(ofLast: available.count - 1)
        let exchange = colors(ofLast: min(Self.exchangeSize, available.count - 1))
        func isClear(_ index: Int) -> Bool { nearest(index, among: exchange) >= palette.similar }
        func closerToUsual(_ a: Int, _ b: Int) -> Bool { distances[usual][a] < distances[usual][b] }

        let usualIsFree = !taken.contains(usual)
        if usualIsFree && isClear(usual) {
            slots[key] = usual
            return false
        }
        // Free colors, in a stable order starting after the usual one.
        let free = (1..<size).map { (usual + $0) % size }.filter { !taken.contains($0) && !palette.reserved.contains($0) }
        let choice: Int
        if let closest = free.filter(isClear).min(by: closerToUsual) {
            // The clearly different color most like their usual one.
            choice = closest
        } else if let shared = available.filter(isClear).min(by: closerToUsual) {
            // Every clearly different color is held by a recent speaker:
            // share one with someone who isn't in the exchange (their usual
            // color, when that's clear) rather than look like someone who is.
            choice = shared
        } else if usualIsFree {
            // Look-alike, but nothing clearly different is left: keep it.
            choice = usual
        } else {
            // Taken, and nothing clearly different: least alike will do.
            choice = free.max(by: { nearest($0, among: taken) < nearest($1, among: taken) }) ?? usual
        }
        slots[key] = choice
        return choice != usual
    }

    /// `key`, who has a color, is speaking. When that color looks like the
    /// color of someone in the exchange, moves one of the two apart (see
    /// the type) and returns who moved. With no look-alike in the exchange,
    /// the usual case, it's a look at the few colors there.
    private mutating func moveApart(_ key: String) -> String? {
        guard let color = slots[key], palette.available.count > 1 else { return nil }
        let exchange = min(Self.exchangeSize, palette.available.count - 1)
        let alike = recent.suffix(exchange).filter { other in
            other != key && slots[other].map { palette.distances[color][$0] < palette.similar } == true
        }
        guard !alike.isEmpty else { return nil }
        // Whoever had spoken least recently first: their lines are further
        // up. `key` hasn't been made the most recent speaker yet.
        func lastSpoke(_ nick: String) -> Int { recent.lastIndex(of: nick) ?? -1 }
        let movers = ([key] + alike)
            .filter { !movedApart.contains($0) }
            .sorted { lastSpoke($0) < lastSpoke($1) }
        for mover in movers {
            guard let choice = clearColor(for: mover, speaker: key, exchange: exchange) else { continue }
            slots[mover] = choice
            movedApart.insert(mover)
            return mover
        }
        return nil
    }

    /// The color for `mover` closest to their usual one that's clearly
    /// different from everyone else in the exchange (`speaker` included),
    /// chosen as for a newcomer; nil when there's none.
    private func clearColor(for mover: String, speaker: String, exchange count: Int) -> Int? {
        let size = palette.count
        let usual = usualIndex(folded: mover)
        let distances = palette.distances
        let taken = colors(ofLast: palette.available.count - 1, also: speaker, except: mover)
        let exchange = colors(ofLast: count, also: speaker, except: mover)
        func isClear(_ index: Int) -> Bool { nearest(index, among: exchange) >= palette.similar }
        func closerToUsual(_ a: Int, _ b: Int) -> Bool { distances[usual][a] < distances[usual][b] }
        // Free colors, in a stable order starting with the usual one.
        let free = (0..<size).map { (usual + $0) % size }.filter { !taken.contains($0) && !palette.reserved.contains($0) }
        return free.filter(isClear).min(by: closerToUsual)
            ?? palette.available.filter(isClear).min(by: closerToUsual)
    }

    // MARK: Hashing

    /// The color a nick starts from: FNV-1a over the RFC 1459 case-folded
    /// nick, so `Alice`, `alice` and `ALICE` match, as do `nick[away]` and
    /// `nick{away}`, and it doesn't change between launches.
    public static func preferredIndex(for nick: String, paletteSize: Int) -> Int {
        preferredIndex(folded: fold(nick), paletteSize: paletteSize)
    }

    private static func preferredIndex(folded: String, paletteSize: Int) -> Int {
        guard paletteSize > 0 else { return 0 }
        var hash: UInt32 = 2_166_136_261
        for byte in folded.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(paletteSize))
    }

    /// RFC 1459 case mapping: ASCII lowercase plus `[]\~` → `{}|^`.
    public static func fold(_ nick: String) -> String {
        String(nick.lowercased().map { character -> Character in
            switch character {
            case "[": "{"
            case "]": "}"
            case "\\": "|"
            case "~": "^"
            default: character
            }
        })
    }
}
