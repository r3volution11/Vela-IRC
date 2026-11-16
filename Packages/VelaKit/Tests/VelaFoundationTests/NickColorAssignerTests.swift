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

    @Test func nicksThatHaveNotSpokenUseTheirUsualColor() {
        let assigner = NickColorAssigner(palette: wheel(12))
        #expect(assigner.index(for: "lurker") == NickColorAssigner.preferredIndex(for: "lurker", paletteSize: 12))
        var single = NickColorAssigner(palette: wheel(1))
        single.noteSpeaker("a")
        single.noteSpeaker("b")
        #expect(single.index(for: "b") == 0)
    }
}
