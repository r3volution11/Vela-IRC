// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The shape of a nick color palette, as the assigner needs it: how many
/// colors, and how different each pair looks.
public struct NickPaletteGeometry: Sendable, Hashable {
    /// Perceptual distance between palette entries (`distances[i][j]`).
    public let distances: [[Double]]
    /// Entries closer than this look alike side by side.
    public let similar: Double
    /// Tells palettes apart cheaply (checked on every lookup).
    public let signature: Int

    public var count: Int { distances.count }

    /// OKLab distance under which two nick colors read as alike: red and
    /// orange, blue and lavender, teal and cyan in a typical palette.
    public static let oklabSimilar = 0.11

    public init(distances: [[Double]], similar: Double = oklabSimilar) {
        self.distances = distances
        self.similar = similar
        var hasher = Hasher()
        hasher.combine(distances)
        hasher.combine(similar)
        signature = hasher.finalize()
    }
}

/// Hands out nick colors (indexes into a palette) within one conversation,
/// so that people talking there can be told apart.
///
/// Everyone starts from their usual color, hashed from their nick, so the
/// same nick looks the same everywhere and across launches, and most
/// people never get anything else. A newcomer only gets another color when
/// their usual one is needed elsewhere:
/// - it belongs to one of the recent speakers (the last `palette.count - 1`), or
/// - it looks like the color of someone in the current exchange (the last
///   few speakers), as red does beside orange.
/// They then get the palette color closest to their usual one that's
/// clearly different from everyone in the exchange. When none is (a
/// crowded channel), a look-alike keeps its usual color, and only a
/// duplicate moves, to the free color most unlike the ones in use. A
/// color, once given, stays: nobody changes color mid-conversation.
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
        slots[Self.fold(nick)] ?? Self.preferredIndex(for: nick, paletteSize: palette.count)
    }

    /// Records that `nick` just spoke: gives it a color if it has none and
    /// makes it the most recent speaker.
    public mutating func noteSpeaker(_ nick: String) {
        let key = Self.fold(nick)
        assign(key)
        if let index = recent.lastIndex(of: key) { recent.remove(at: index) }
        recent.append(key)
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }
    }

    /// Gives `nick` a color if it has none, without making it a recent
    /// speaker: for older history loaded above what's on screen.
    public mutating func noteEarlierSpeaker(_ nick: String) {
        assign(Self.fold(nick))
    }

    private mutating func assign(_ key: String) {
        guard slots[key] == nil else { return }
        let size = palette.count
        guard size > 1 else {
            slots[key] = 0
            return
        }
        let distances = palette.distances
        let preferred = Self.preferredIndex(folded: key, paletteSize: size)
        let taken = Set(recent.suffix(size - 1).compactMap { slots[$0] })
        let exchange = Set(recent.suffix(min(Self.exchangeSize, size - 1)).compactMap { slots[$0] })
        func nearest(_ index: Int, among colors: Set<Int>) -> Double {
            colors.map { distances[index][$0] }.min() ?? .infinity
        }
        func isClear(_ index: Int) -> Bool { nearest(index, among: exchange) >= palette.similar }

        let preferredIsFree = !taken.contains(preferred)
        if preferredIsFree && isClear(preferred) {
            slots[key] = preferred
            return
        }
        // Free colors, in a stable order starting after the preferred one.
        let free = (1..<size).map { (preferred + $0) % size }.filter { !taken.contains($0) }
        // The clearly different color most like their usual one.
        if let closest = free.filter(isClear).min(by: { distances[preferred][$0] < distances[preferred][$1] }) {
            slots[key] = closest
        } else if preferredIsFree {
            // Look-alike, but nothing clearly different is left: keep it.
            slots[key] = preferred
        } else {
            // Taken, and nothing clearly different: least alike will do.
            slots[key] = free.max(by: { nearest($0, among: taken) < nearest($1, among: taken) }) ?? preferred
        }
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
