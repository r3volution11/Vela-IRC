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
/// the ones in use. A color, once given, stays: nobody changes color
/// mid-conversation.
public struct NickColorAssigner: Sendable {
    public let palette: NickPaletteGeometry
    /// Case-folded nick → palette index.
    private var slots: [String: Int] = [:]
    /// Case-folded nicks that spoke, least recent first.
    private var recent: [String] = []

    /// How many recent speakers to remember; only the last
    /// `palette.count - 1` matter when choosing a color.
    private static let recentLimit = 64
    /// The current exchange: the speakers whose colors a newcomer shouldn't
    /// resemble.
    private static let exchangeSize = 5

    public init(palette: NickPaletteGeometry) {
        self.palette = palette
    }

    /// `nick`'s color: its own once it has spoken here, otherwise the
    /// color it would start from.
    public func index(for nick: String) -> Int {
        let key = Self.fold(nick)
        return slots[key] ?? usualIndex(folded: key)
    }

    /// Records that `nick` just spoke: gives it a color if it has none and
    /// makes it the most recent speaker. Returns true when that changed
    /// the nick's color (from its usual one to another).
    @discardableResult
    public mutating func noteSpeaker(_ nick: String) -> Bool {
        let key = Self.fold(nick)
        let moved = assign(key)
        if let index = recent.lastIndex(of: key) { recent.remove(at: index) }
        recent.append(key)
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }
        return moved
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
        let taken = Set(recent.suffix(available.count - 1).compactMap { slots[$0] })
        let exchange = Set(recent.suffix(min(Self.exchangeSize, available.count - 1)).compactMap { slots[$0] })
        func nearest(_ index: Int, among colors: Set<Int>) -> Double {
            colors.map { distances[index][$0] }.min() ?? .infinity
        }
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
