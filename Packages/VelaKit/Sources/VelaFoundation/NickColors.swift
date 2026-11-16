// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The shape of a nick color palette, as the assigner needs it: how many
/// colors, and how different each pair looks.
public struct NickPaletteGeometry: Sendable, Hashable {
    /// Perceptual distance between palette entries (`distances[i][j]`).
    public let distances: [[Double]]
    /// Tells palettes apart cheaply (checked on every lookup).
    public let signature: Int

    public var count: Int { distances.count }

    public init(distances: [[Double]]) {
        self.distances = distances
        signature = distances.hashValue
    }
}

/// Hands out nick colors (indexes into a palette) within one conversation,
/// so that people talking there get different colors.
///
/// Everyone starts from a stable color hashed from their nick, so the same
/// nick mostly looks the same everywhere and across launches. When that
/// color belongs to someone who spoke recently, a newcomer gets the free
/// color that looks most unlike the ones in use instead. A color, once
/// given, stays: nobody changes color mid-conversation.
public struct NickColorAssigner: Sendable {
    public let palette: NickPaletteGeometry
    /// Case-folded nick → palette index.
    private var slots: [String: Int] = [:]
    /// Case-folded nicks that spoke, least recent first.
    private var recent: [String] = []

    /// How many recent speakers to remember; only the last
    /// `palette.count - 1` matter when choosing a color.
    private static let recentLimit = 64

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
        let preferred = Self.preferredIndex(folded: key, paletteSize: size)
        let taken = Set(recent.suffix(size - 1).compactMap { slots[$0] })
        guard taken.contains(preferred) else {
            slots[key] = preferred
            return
        }
        // The free color furthest from every color in use; ties go to the
        // one closest after the preferred color, so the result is stable.
        var best = preferred
        var bestDistance = -1.0
        for step in 1..<size {
            let candidate = (preferred + step) % size
            guard !taken.contains(candidate) else { continue }
            let nearest = taken.map { palette.distances[candidate][$0] }.min() ?? .infinity
            if nearest > bestDistance {
                best = candidate
                bestDistance = nearest
            }
        }
        slots[key] = best
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
