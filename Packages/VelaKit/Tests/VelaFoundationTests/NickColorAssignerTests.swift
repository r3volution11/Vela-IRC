// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import VelaFoundation

@Suite("Nick color assigner")
struct NickColorAssignerTests {
    /// `count` colors evenly around a wheel, one step apart from their
    /// neighbors. With `similar: 2`, neighbors look alike.
    private func wheel(_ count: Int, similar: Double = NickPaletteGeometry.oklabSimilar) -> NickPaletteGeometry {
        NickPaletteGeometry(distances: (0..<count).map { i in
            (0..<count).map { j in Double(min(abs(i - j), count - abs(i - j))) }
        }, similar: similar)
    }

    /// A nick whose usual color is `index` of `size`.
    private func nick(usually index: Int, of size: Int, not others: Set<String> = []) -> String {
        (0...).lazy.map { "nick\($0)" }.first {
            NickColorAssigner.preferredIndex(for: $0, paletteSize: size) == index && !others.contains($0)
        }!
    }

    @Test func startsFromAStableCaseInsensitiveHash() {
        #expect(NickColorAssigner.preferredIndex(for: "alice", paletteSize: 12) == NickColorAssigner.preferredIndex(for: "ALICE", paletteSize: 12))
        #expect(NickColorAssigner.preferredIndex(for: "nick[away]", paletteSize: 12) == NickColorAssigner.preferredIndex(for: "nick{away}", paletteSize: 12))
        #expect(NickColorAssigner.preferredIndex(for: "", paletteSize: 12) == Int(2_166_136_261 % 12))
    }

    @Test func peopleInOneConversationGetDifferentColors() {
        // The clash that prompted this: both hash to the same entry of 12.
        #expect(NickColorAssigner.preferredIndex(for: "jeebz", paletteSize: 12) == NickColorAssigner.preferredIndex(for: "tomf", paletteSize: 12))

        var assigner = NickColorAssigner(palette: wheel(12, similar: 2))
        assigner.noteSpeaker("jeebz")
        assigner.noteSpeaker("tomf")
        let jeebz = assigner.index(for: "jeebz"), tomf = assigner.index(for: "tomf")
        #expect(jeebz == NickColorAssigner.preferredIndex(for: "jeebz", paletteSize: 12))
        // The closest color that doesn't look like jeebz's: two steps on,
        // past the look-alike neighbor.
        #expect(tomf == (jeebz + 2) % 12)
    }

    @Test func lookAlikesMoveOnlyWhenNeeded() {
        let a = nick(usually: 0, of: 12)
        let b = nick(usually: 1, of: 12)   // looks like a's
        let c = nick(usually: 6, of: 12)   // nothing like a's

        // Alone, b keeps its usual color.
        var alone = NickColorAssigner(palette: wheel(12, similar: 2))
        alone.noteSpeaker(b)
        #expect(alone.index(for: b) == 1)

        // Beside a (and c), b takes the nearest color unlike both.
        var assigner = NickColorAssigner(palette: wheel(12, similar: 2))
        assigner.noteSpeaker(a)
        assigner.noteSpeaker(c)
        assigner.noteSpeaker(b)
        #expect(assigner.index(for: a) == 0)
        #expect(assigner.index(for: c) == 6)
        #expect(assigner.index(for: b) == 2)

        // Look-alikes that stopped talking a while ago don't count.
        var later = NickColorAssigner(palette: wheel(12, similar: 2))
        later.noteSpeaker(a)
        for index in [3, 5, 7, 9, 11] { later.noteSpeaker(nick(usually: index, of: 12, not: [a, b])) }
        later.noteSpeaker(b)
        #expect(later.index(for: b) == 1)
    }

    @Test func crowdedLookAlikesKeepTheirColor() {
        // Four colors; only opposite ones are clearly different.
        let x = nick(usually: 0, of: 4)
        let y = nick(usually: 2, of: 4)
        let z = nick(usually: 1, of: 4)
        var assigner = NickColorAssigner(palette: wheel(4, similar: 2))
        assigner.noteSpeaker(x)
        assigner.noteSpeaker(y)
        assigner.noteSpeaker(z)
        // Nothing free is clearly different from both, so z keeps its own.
        #expect(assigner.index(for: z) == 1)
    }

    @Test func colorsStickOnceGiven() {
        var assigner = NickColorAssigner(palette: wheel(12))
        assigner.noteSpeaker("jeebz")
        assigner.noteSpeaker("tomf")
        let tomf = assigner.index(for: "tomf")
        for nick in ["xmn", "r3volution11", "Templarian", "kenji", "ada"] { assigner.noteSpeaker(nick) }
        assigner.noteSpeaker("TOMF")
        #expect(assigner.index(for: "tomf") == tomf)
    }

    @Test func manyDistinctColorsWhileThePaletteHasRoom() {
        var assigner = NickColorAssigner(palette: wheel(8))
        let nicks = ["a", "b", "c", "d", "e", "f", "g", "h"]
        for nick in nicks { assigner.noteSpeaker(nick) }
        #expect(Set(nicks.map(assigner.index(for:))).count == 8)
    }

    @Test func onlyRecentSpeakersHoldTheirColors() {
        // With 3 colors, a newcomer only avoids the last 2 speakers.
        var assigner = NickColorAssigner(palette: wheel(3))
        for nick in ["a", "b", "c", "d", "e", "f"] { assigner.noteSpeaker(nick) }
        assigner.noteSpeaker("x")
        let x = assigner.index(for: "x")
        #expect(x != assigner.index(for: "e") && x != assigner.index(for: "f"))
    }

    @Test func earlierHistoryDoesNotCountAsRecent() {
        var assigner = NickColorAssigner(palette: wheel(12))
        assigner.noteSpeaker("jeebz")
        // tomf only appears in older history loaded later…
        assigner.noteEarlierSpeaker("tomf")
        #expect(assigner.index(for: "tomf") != assigner.index(for: "jeebz"))
        // …and doesn't push jeebz out of the recent speakers.
        assigner.noteSpeaker("other")
        #expect(assigner.index(for: "jeebz") == NickColorAssigner.preferredIndex(for: "jeebz", paletteSize: 12))
    }

    // MARK: Your own color

    /// A 12-color wheel where 0 is your nick's color and 1 and 11 look
    /// like it (`similar: 2`).
    private func wheelKeepingYours() -> NickPaletteGeometry {
        let plain = wheel(12, similar: 2)
        return NickPaletteGeometry(distances: plain.distances, similar: 2, reserved: [0, 1, 11])
    }

    @Test func nobodyElseGetsYourColor() {
        let palette = wheelKeepingYours()
        // Usual colors steer clear of it: a nick hashed onto it starts from
        // the nearest color that isn't kept back.
        #expect(palette.usualIndex(0) == 2 || palette.usualIndex(0) == 10)
        #expect(palette.usualIndex(1) == 2)
        #expect(palette.usualIndex(11) == 10)
        #expect(palette.usualIndex(5) == 5)

        var assigner = NickColorAssigner(palette: palette)
        let nicks = (0..<40).map { "user\($0)" }
        for nick in nicks { assigner.noteSpeaker(nick) }
        for nick in nicks + ["lurker", "r3volution11", "Templarian"] {
            #expect(![0, 1, 11].contains(assigner.index(for: nick)), "\(nick)")
        }
    }

    @Test func twoNicksHashedOntoYourColorTalkInDifferentColors() {
        let palette = wheelKeepingYours()
        let a = nick(usually: 0, of: 12)
        let b = nick(usually: 1, of: 12, not: [a])
        var assigner = NickColorAssigner(palette: palette)
        assigner.noteSpeaker(a)
        assigner.noteSpeaker(b)
        let colors = [assigner.index(for: a), assigner.index(for: b)]
        #expect(colors.allSatisfy { ![0, 1, 11].contains($0) })
        // Not just different: clearly so (two steps apart on this wheel).
        #expect(palette.distances[colors[0]][colors[1]] >= 2)
    }

    @Test func aMoveIsReported() {
        var assigner = NickColorAssigner(palette: wheel(12, similar: 2))
        #expect(assigner.noteSpeaker("jeebz").isEmpty)
        // tomf hashes onto jeebz's color, so gets another one.
        #expect(assigner.noteSpeaker("tomf") == .init(given: "tomf"))
        // Already given: nothing changes.
        #expect(assigner.noteSpeaker("tomf").isEmpty)
        #expect(assigner.noteEarlierSpeaker("jeebz") == false)
    }

    @Test func aCrowdedChannelSharesAQuietPersonsColorBeforeALookAlike() {
        // Eight colors, all clearly different, except that 7 looks like
        // 3, 4, 5 and 6.
        let palette = NickPaletteGeometry(distances: (0..<8).map { i in
            (0..<8).map { j -> Double in
                if i == j { return 0 }
                return [i, j].contains(7) && [i, j].contains(where: (3...6).contains) ? 1 : 10
            }
        }, similar: 2)
        var used: Set<String> = []
        func speaker(_ color: Int) -> String {
            let found = nick(usually: color, of: 8, not: used)
            used.insert(found)
            return found
        }
        var assigner = NickColorAssigner(palette: palette)
        // Seven recent speakers hold colors 0–6; the last five (2–6) are
        // talking now. Only 7 is free, and it looks like four of them.
        let quiet = speaker(0)
        for nick in [quiet] + (1...6).map(speaker) { assigner.noteSpeaker(nick) }
        #expect((0...6).map { color in used.contains { assigner.index(for: $0) == color } }.allSatisfy { $0 })

        // A newcomer whose usual color is the quiet one's shares it, rather
        // than take 7 and look like the people talking.
        let newcomer = speaker(0)
        #expect(assigner.noteSpeaker(newcomer).isEmpty)
        #expect(assigner.index(for: newcomer) == 0)
        #expect(assigner.index(for: quiet) == 0)
    }

    // MARK: Look-alikes who end up talking together

    /// On a 16-color wheel, a speaks, then five others; b, whose usual
    /// color looks like a's, is given it, since a isn't in the exchange
    /// any more. Returns the assigner, a, b and the others (4, 6, … 12).
    private func lookAlikesGivenApart() -> (NickColorAssigner, String, String, [String]) {
        let a = nick(usually: 0, of: 16)
        let b = nick(usually: 1, of: 16, not: [a])
        let others = [4, 6, 8, 10, 12].map { nick(usually: $0, of: 16, not: [a, b]) }
        var assigner = NickColorAssigner(palette: wheel(16, similar: 2))
        assigner.noteSpeaker(a)
        for other in others { assigner.noteSpeaker(other) }
        assigner.noteSpeaker(b)
        return (assigner, a, b, others)
    }

    @Test func lookAlikesTalkingTogetherAreMovedApart() {
        var (assigner, a, b, _) = lookAlikesGivenApart()
        #expect(assigner.index(for: a) == 0)
        #expect(assigner.index(for: b) == 1)
        // a comes back, beside b. a, who had spoken less recently, moves:
        // to the clearly different color nearest its usual one (6–12 and
        // b's 1 are in the exchange, leaving 3, 14 and 15).
        #expect(assigner.noteSpeaker(a) == .init(moved: a))
        #expect(assigner.index(for: a) == 15)
        #expect(assigner.index(for: b) == 1)
        // Then nothing changes as they talk.
        for _ in 0..<3 {
            #expect(assigner.noteSpeaker(b).isEmpty)
            #expect(assigner.noteSpeaker(a).isEmpty)
        }
        #expect(assigner.index(for: a) == 15)
    }

    @Test func nobodyMovesTwice() {
        var (assigner, a, b, others) = lookAlikesGivenApart()
        assigner.noteSpeaker(a)
        #expect(assigner.index(for: a) == 15)
        // d, whose usual 14 looks like a's new 15, is given it while a is
        // out of the exchange.
        let d = nick(usually: 14, of: 16, not: Set([a, b] + others))
        for nick in [b] + others.prefix(4) { assigner.noteSpeaker(nick) }
        assigner.noteSpeaker(d)
        #expect(assigner.index(for: d) == 14)
        // a comes back beside d. a has moved once, so d moves instead.
        #expect(assigner.noteSpeaker(a) == .init(moved: d))
        #expect(assigner.index(for: a) == 15)
        #expect(assigner.index(for: d) == 13)
    }

    @Test func withNothingClearlyDifferentNobodyMoves() {
        // Four colors; only opposite ones are clearly different. z keeps
        // its look-alike color beside x (see crowdedLookAlikesKeepTheirColor).
        let x = nick(usually: 0, of: 4)
        let y = nick(usually: 2, of: 4)
        let z = nick(usually: 1, of: 4)
        var assigner = NickColorAssigner(palette: wheel(4, similar: 2))
        for nick in [x, y, z] { assigner.noteSpeaker(nick) }
        #expect(assigner.noteSpeaker(x).isEmpty)
        #expect([x, y, z].map(assigner.index(for:)) == [0, 2, 1])
    }

    /// The crowded channel above: the newcomer shares the quiet person's
    /// color. When the quiet person speaks again, the two are side by side
    /// in one color, and the one who had spoken less recently moves, to a
    /// color clear of the exchange (shared with someone who isn't in it).
    @Test func twoPeopleSharingAColorAreParted() {
        let palette = NickPaletteGeometry(distances: (0..<8).map { i in
            (0..<8).map { j -> Double in
                if i == j { return 0 }
                return [i, j].contains(7) && [i, j].contains(where: (3...6).contains) ? 1 : 10
            }
        }, similar: 2)
        var used: Set<String> = []
        func speaker(_ color: Int) -> String {
            let found = nick(usually: color, of: 8, not: used)
            used.insert(found)
            return found
        }
        var assigner = NickColorAssigner(palette: palette)
        let quiet = speaker(0)
        let talking = (1...6).map(speaker)
        let newcomer = speaker(0)
        for nick in [quiet] + talking + [newcomer] { assigner.noteSpeaker(nick) }
        #expect(assigner.index(for: quiet) == 0 && assigner.index(for: newcomer) == 0)

        #expect(assigner.noteSpeaker(quiet) == .init(moved: quiet))
        #expect(assigner.index(for: newcomer) == 0)
        // 1 and 2 are clear of the exchange (3–6 and the newcomer's 0).
        #expect(assigner.index(for: quiet) == 1)
    }

    @Test func whoMovedIsSaidAsTheyLastSpoke() {
        var (assigner, a, _, _) = lookAlikesGivenApart()
        #expect(assigner.noteSpeaker(a.uppercased()) == .init(moved: a.uppercased()))
    }

    @Test func nicksThatHaveNotSpokenUseTheirUsualColor() {
        let assigner = NickColorAssigner(palette: wheel(12))
        #expect(assigner.index(for: "lurker") == NickColorAssigner.preferredIndex(for: "lurker", paletteSize: 12))
        var single = NickColorAssigner(palette: wheel(1))
        single.noteSpeaker("a")
        single.noteSpeaker("b")
        #expect(single.index(for: "b") == 0)
    }
}
