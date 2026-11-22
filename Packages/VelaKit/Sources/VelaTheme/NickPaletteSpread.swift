// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization
import VelaFoundation

/// Moves a theme's look-alike nick colors a little apart, once, when the
/// theme resolves, so the people given them can be told apart.
///
/// Many palettes hold near twins: Palenight's blue #82AAFF and lavender
/// #A9B4FF, or its red #F07178 and orange #F78C6C. The assigner keeps the
/// people in one exchange off look-alikes while it can, but the fewer
/// clearly different colors a palette has, the sooner it runs out. So:
///
/// 1. A color that looks like your own nick's (`chat.selfNick`) moves off
///    it when a small change makes it clearly different from yours and
///    from every color that's handed out. Otherwise it stays as it is, and
///    is kept for you (`ResolvedTheme.selfLikeNickColors`).
/// 2. Then, closest pair first, colors that look alike (closer than
///    `NickPaletteGeometry.oklabSimilar`) are moved apart by the smallest
///    change that does it, in OKLCh: turning the hue a little first, then
///    lighter or darker, then less vivid. One color of the pair moves when
///    that's enough: the one that needs the smaller change, but never the
///    theme's accent or self color while the other can go instead. Failing
///    that, both move part of the way; and a pair that can't reach the
///    threshold within the limits is moved as far apart as they allow.
///
/// The limits keep the theme's look: no color moves more than
/// `maximumChange` from the theme's own, turns more than `maximumHueTurn`,
/// gains more than `maximumChromaGain` of chroma or loses more than
/// `maximumChromaLoss` of it (a muted palette stays muted, a vivid one
/// vivid), and a move sRGB can't show as meant isn't taken (a turn that
/// would come out duller is a dulling in disguise); each stays readable on `chat.background` (`ThemeAudit.nickMinimum`)
/// and distinct from the text (`ResolvedTheme.isDistinctNickColor`); and no
/// move brings a color closer to another, or to yours, than the threshold,
/// or than it already was. A color that looks like no other is left exactly
/// as the theme has it.
///
/// Deterministic, and remembered per palette: about a millisecond for a
/// 12-color palette in a release build, and a theme resolves often (its
/// preview, accent choices, the editor), so the work is done once.
enum NickPaletteSpread {
    /// How far (OKLab ΔE) a color may move from the theme's own: enough
    /// to part a blue from a lavender, not enough to make either another
    /// color.
    static let maximumChange = 0.06
    /// How much more chroma a color may gain.
    static let maximumChromaGain = 0.016
    /// How much of its chroma a color may lose: a vivid color stays vivid
    /// rather than turning greyish.
    static let maximumChromaLoss = 1.0 / 3
    /// How far (degrees) a color's hue may turn: a pale color covers little
    /// distance per degree, and a cyan turned far enough is a mint.
    static let maximumHueTurn = 25.0
    /// A palette color this close to `chat.selfNick` or the accent is the
    /// theme's own, and moves only when its look-alike can't.
    static let anchorDistance = 0.02

    /// `palette` with its look-alikes moved apart (same order, same count).
    static func spread(_ palette: [ThemeColor], colors: [String: ThemeColor]) -> [ThemeColor] {
        spread(
            palette,
            text: colors[ThemeKey.chatForeground],
            background: colors[ThemeKey.chatBackground],
            selfNick: colors[ThemeKey.chatSelfNick],
            accent: colors[ThemeKey.accent]
        )
    }

    static func spread(
        _ palette: [ThemeColor],
        text: ThemeColor?,
        background: ThemeColor?,
        selfNick: ThemeColor?,
        accent: ThemeColor?
    ) -> [ThemeColor] {
        guard palette.count > 1 else { return palette }
        let key = Key(palette: palette, text: text, background: background, selfNick: selfNick, accent: accent)
        if let known = memory.withLock({ $0[key] }) { return known }
        var spreader = Spreader(palette: palette, text: text, background: background, selfNick: selfNick, accent: accent)
        let result = spreader.run()
        memory.withLock { known in
            // A handful of themes and accents in use; start over past that.
            if known.count >= 64 { known.removeAll() }
            known[key] = result
        }
        return result
    }

    private struct Key: Hashable {
        var palette: [ThemeColor]
        var text: ThemeColor?
        var background: ThemeColor?
        var selfNick: ThemeColor?
        var accent: ThemeColor?
    }

    private static let memory = Mutex<[Key: [ThemeColor]]>([:])
}

// MARK: - The work

private struct Lab {
    var l: Double
    var a: Double
    var b: Double

    init(_ color: ThemeColor) {
        (l, a, b) = color.oklab
    }

    var chroma: Double { (a * a + b * b).squareRoot() }

    /// Degrees between this hue and `other`'s; 0 when either is a grey.
    func hueTurn(from other: Lab) -> Double {
        guard chroma > 0.02, other.chroma > 0.02 else { return 0 }
        let turn = abs(atan2(b, a) - atan2(other.b, other.a)) * 180 / .pi
        return turn > 180 ? 360 - turn : turn
    }

    func distance(to other: Lab) -> Double {
        let dl = l - other.l, da = a - other.a, db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}

/// A place a color could move to, and what the move costs.
private struct Candidate {
    var color: ThemeColor
    var lab: Lab
    var cost: Double
    /// Outside sRGB as asked for, so drawn duller than the move meant: a
    /// hue turn that would really drain the color. Not taken.
    var clipped = false
}

/// A change in OKLCh: hue in degrees, lightness and chroma in OKLab units.
private struct Offset {
    var hue: Double
    var lightness: Double
    var chroma: Double
    /// About the OKLab distance it covers, with lightness weighed 1.5× and
    /// chroma 2×, so a hue turn is tried before a lighter or darker color,
    /// and that before a less vivid one.
    var cost: Double
    /// Where it was made, to order equal costs the same way every time.
    var order = 0
}

private struct Spreader {
    private static let similar = NickPaletteGeometry.oklabSimilar
    private static let lightnessWeight = 1.5
    private static let chromaWeight = 2.0
    private static let hueStep = 1.0
    private static let lightnessStep = 0.004
    private static let comboHueStep = 2.0
    private static let comboLightnessStep = 0.008

    let original: [Lab]
    let minimumContrast: [Double]
    let keepsApartFromText: [Bool]
    let anchored: [Bool]
    let text: Lab?
    let background: ThemeColor?
    /// The background's luminance, as text is drawn on it.
    let backgroundLuminance: Double
    let selfNick: ThemeColor?
    let me: Lab?
    var colors: [ThemeColor]
    var labs: [Lab]
    /// Colors kept for you after step 1: nobody's given them, so they
    /// neither move nor stand in another color's way.
    var kept: Set<Int> = []
    /// Candidates worked out so far, per color (`candidates(for:combined:)`).
    private let memo = CandidateMemo()

    init(palette: [ThemeColor], text: ThemeColor?, background: ThemeColor?, selfNick: ThemeColor?, accent: ThemeColor?) {
        colors = palette
        labs = palette.map(Lab.init)
        original = labs
        self.text = text.map(Lab.init)
        self.background = background
        backgroundLuminance = background.map { ($0.alpha < 1 ? $0.composited(over: .black) : $0).luminance } ?? 0
        self.selfNick = selfNick
        me = selfNick.map(Lab.init)
        minimumContrast = palette.map { color in
            // What the audit asks, or what the theme had when it's less (a
            // palette kept whole because too few colors passed).
            background.map { min(ThemeAudit.nickMinimum, color.contrastRatio(against: $0)) } ?? 0
        }
        keepsApartFromText = palette.map { ResolvedTheme.isDistinctNickColor($0, text: text, background: nil) }
        let anchors = [selfNick, accent].compactMap { $0 }.map(Lab.init)
        anchored = labs.map { lab in anchors.contains { $0.distance(to: lab) < NickPaletteSpread.anchorDistance } }
    }

    mutating func run() -> [ThemeColor] {
        moveOffYourColor()
        if let selfNick {
            kept = ResolvedTheme.selfLikeNickColors(colors, selfNick: selfNick)
        }
        moveLookAlikesApart()
        return colors
    }

    // MARK: Step 1

    /// Colors like yours, closest first, move off it when a small change
    /// clears both yours and the colors handed out.
    private mutating func moveOffYourColor() {
        guard let me else { return }
        let alike = colors.indices
            .filter { labs[$0].distance(to: me) < Self.similar && !anchored[$0] }
            .sorted { labs[$0].distance(to: me) < labs[$1].distance(to: me) }
        for index in alike {
            let handedOut = colors.indices.filter { $0 != index && labs[$0].distance(to: me) >= Self.similar }
            let move = candidates(for: index, combined: true).first { candidate in
                candidate.lab.distance(to: me) >= Self.similar
                    && handedOut.allSatisfy { candidate.lab.distance(to: labs[$0]) >= Self.similar }
                    && allows(candidate, for: index, ignoring: nil)
            }
            if let move { place(move, at: index) }
        }
    }

    // MARK: Step 2

    private mutating func moveLookAlikesApart() {
        var settled: Set<[Int]> = []
        // Each pass settles a pair, and no move makes another pair look
        // alike, so this ends well before the cap.
        for _ in 0..<(colors.count * colors.count) {
            guard let (first, second, distance) = closestPair(skipping: settled) else { return }
            if moveOne(of: first, second) || moveBoth(first, second) { continue }
            moveAsFarAsAllowed(first, second, from: distance)
            settled.insert([first, second])
        }
    }

    /// The closest look-alike pair among the colors handed out.
    private func closestPair(skipping settled: Set<[Int]>) -> (Int, Int, Double)? {
        var best: (Int, Int, Double)?
        for i in colors.indices where !kept.contains(i) {
            for j in colors.indices where j > i && !kept.contains(j) && !settled.contains([i, j]) {
                let distance = labs[i].distance(to: labs[j])
                if distance < Self.similar, distance < best?.2 ?? .infinity { best = (i, j, distance) }
            }
        }
        return best
    }

    /// Moves whichever of the pair can clear the other more cheaply (a
    /// non-anchored one first). False when neither can alone.
    private mutating func moveOne(of first: Int, _ second: Int) -> Bool {
        var best: (index: Int, candidate: Candidate)?
        for (index, other) in [(first, second), (second, first)] {
            let move = candidates(for: index, combined: true).first { candidate in
                candidate.lab.distance(to: labs[other]) >= Self.similar && allows(candidate, for: index, ignoring: other)
            }
            guard let move else { continue }
            if let current = best {
                let better = anchored[index] != anchored[current.index]
                    ? !anchored[index]
                    : move.cost < current.candidate.cost
                if !better { continue }
            }
            best = (index, move)
        }
        guard let best else { return false }
        place(best.candidate, at: best.index)
        return true
    }

    /// Moves both part of the way: the pair of moves whose larger cost is
    /// least. False when no pair of moves clears.
    private mutating func moveBoth(_ first: Int, _ second: Int) -> Bool {
        let firsts = moves(for: first, ignoring: second)
        let seconds = moves(for: second, ignoring: first)
        var best: (Candidate, Candidate, Double, Double)?
        for a in firsts {
            for b in seconds where a.cost > 0 || b.cost > 0 {
                guard a.lab.distance(to: b.lab) >= Self.similar else { continue }
                let larger = max(a.cost, b.cost), total = a.cost + b.cost
                if let current = best, (larger, total) >= (current.2, current.3) { continue }
                best = (a, b, larger, total)
            }
        }
        guard let best else { return false }
        place(best.0, at: first)
        place(best.1, at: second)
        return true
    }

    /// Short of the threshold: as far apart as the limits allow. An
    /// anchored color stays put unless both are.
    private mutating func moveAsFarAsAllowed(_ first: Int, _ second: Int, from distance: Double) {
        let firstStays = anchored[first] && !anchored[second]
        let secondStays = anchored[second] && !anchored[first]
        let firsts = firstStays ? [stay(first)] : moves(for: first, ignoring: second)
        let seconds = secondStays ? [stay(second)] : moves(for: second, ignoring: first)
        var best: (Candidate, Candidate, Double, Double)?
        for a in firsts {
            for b in seconds {
                let apart = a.lab.distance(to: b.lab), total = a.cost + b.cost
                if let current = best, apart < current.2 || (apart == current.2 && total >= current.3) { continue }
                best = (a, b, apart, total)
            }
        }
        guard let best, best.2 > distance + 1e-6 else { return }
        place(best.0, at: first)
        place(best.1, at: second)
    }

    /// Staying put, then every single-axis move of `index` the limits allow
    /// (ignoring its partner `other`).
    private func moves(for index: Int, ignoring other: Int) -> [Candidate] {
        [stay(index)] + candidates(for: index, combined: false).filter { allows($0, for: index, ignoring: other) }
    }

    private func stay(_ index: Int) -> Candidate {
        Candidate(color: colors[index], lab: labs[index], cost: 0)
    }

    private mutating func place(_ candidate: Candidate, at index: Int) {
        colors[index] = candidate.color
        labs[index] = candidate.lab
    }

    // MARK: Limits

    /// Whether `index` may move to `candidate`: within the limits, and no
    /// closer to anyone (but `other`, and colors kept for you) than the
    /// threshold, or than it already is.
    private func allows(_ candidate: Candidate, for index: Int, ignoring other: Int?) -> Bool {
        let lab = candidate.lab
        guard !candidate.clipped,
              lab.distance(to: original[index]) <= NickPaletteSpread.maximumChange,
              // A hair over, for colors rounded to 8 bits.
              lab.chroma <= original[index].chroma + NickPaletteSpread.maximumChromaGain + 0.002,
              lab.chroma >= original[index].chroma * (1 - NickPaletteSpread.maximumChromaLoss) - 0.002,
              lab.hueTurn(from: original[index]) <= NickPaletteSpread.maximumHueTurn else { return false }
        if let me, lab.distance(to: me) < min(Self.similar, labs[index].distance(to: me)) { return false }
        for neighbor in colors.indices where neighbor != index && neighbor != other && !kept.contains(neighbor) {
            if lab.distance(to: labs[neighbor]) < min(Self.similar, labs[index].distance(to: labs[neighbor])) { return false }
        }
        if background != nil, contrast(of: candidate.color) < minimumContrast[index] { return false }
        guard keepsApartFromText[index], let text else { return true }
        return ResolvedTheme.readsApartFromText(distance: lab.distance(to: text), chroma: lab.chroma)
    }

    /// `color.contrastRatio(against: background)`, with the background's
    /// part worked out once.
    private func contrast(of color: ThemeColor) -> Double {
        guard let background else { return .infinity }
        guard color.alpha == 1 else { return color.contrastRatio(against: background) }
        let luminance = color.luminance
        return (max(luminance, backgroundLuminance) + 0.05) / (min(luminance, backgroundLuminance) + 0.05)
    }

    // MARK: Candidates

    /// Where `index` could move, cheapest first. `combined` adds moves that
    /// turn the hue and change the lightness together. Worked out as
    /// they're asked for, and kept until the color moves: a color is
    /// tried for several pairs.
    private func candidates(for index: Int, combined: Bool) -> LazyMapSequence<Range<Int>, Candidate> {
        let slot = index * 2 + (combined ? 1 : 0)
        let current = colors[index]
        let made: CandidateList
        if let known = memo.lists[slot], known.from == current {
            made = known
        } else {
            made = CandidateList(from: current, combined: combined)
            memo.lists[slot] = made
        }
        return (0..<made.offsets.count).lazy.map { made.candidate($0) }
    }

    /// Every change worth trying for a color of chroma `chroma`, cheapest
    /// first. Hue turns only for colors that have a hue.
    fileprivate static func offsets(chroma: Double, combined: Bool) -> [Offset] {
        let limit = NickPaletteSpread.maximumChange
        // Hue turns cover about chroma × angle; a little over the limit,
        // since gamut and rounding move the result.
        let hueLimit = limit * 1.2
        var offsets: [Offset] = []
        func arc(_ degrees: Double) -> Double { chroma * degrees * .pi / 180 }
        let hasHue = chroma > 0.02
        if hasHue {
            for step in 1... {
                let degrees = Double(step) * hueStep
                guard arc(degrees) <= hueLimit else { break }
                offsets.append(Offset(hue: degrees, lightness: 0, chroma: 0, cost: arc(degrees)))
                offsets.append(Offset(hue: -degrees, lightness: 0, chroma: 0, cost: arc(degrees)))
            }
        }
        // Lightness and chroma steps up to one past the limit.
        let steps = Int((limit / lightnessStep).rounded(.down)) + 1
        for step in 1...steps {
            let amount = Double(step) * lightnessStep
            offsets.append(Offset(hue: 0, lightness: amount, chroma: 0, cost: lightnessWeight * amount))
            offsets.append(Offset(hue: 0, lightness: -amount, chroma: 0, cost: lightnessWeight * amount))
            if amount <= NickPaletteSpread.maximumChromaGain + 1e-9 {
                offsets.append(Offset(hue: 0, lightness: 0, chroma: amount, cost: chromaWeight * amount))
            }
            offsets.append(Offset(hue: 0, lightness: 0, chroma: -amount, cost: chromaWeight * amount))
        }
        if combined && hasHue {
            let comboSteps = Int((limit / comboLightnessStep).rounded(.down)) + 1
            for hueStepCount in 1... {
                let degrees = Double(hueStepCount) * comboHueStep
                guard arc(degrees) <= hueLimit else { break }
                for step in 1...comboSteps {
                    let lightness = Double(step) * comboLightnessStep
                    let cost = (arc(degrees) * arc(degrees) + lightnessWeight * lightnessWeight * lightness * lightness).squareRoot()
                    for hue in [degrees, -degrees] {
                        offsets.append(Offset(hue: hue, lightness: lightness, chroma: 0, cost: cost))
                        offsets.append(Offset(hue: hue, lightness: -lightness, chroma: 0, cost: cost))
                    }
                }
            }
        }
        // Stable for equal costs, so the result never depends on sorting.
        for index in offsets.indices { offsets[index].order = index }
        return offsets.sorted { $0.cost != $1.cost ? $0.cost < $1.cost : $0.order < $1.order }
    }
}

/// The places one color could move to, worked out as they're asked for.
private final class CandidateList {
    let from: ThemeColor
    let offsets: [Offset]
    private let lch: (l: Double, c: Double, h: Double)
    private var made: [Candidate?]

    init(from color: ThemeColor, combined: Bool) {
        from = color
        lch = color.oklch
        offsets = Spreader.offsets(chroma: lch.c, combined: combined)
        made = Array(repeating: nil, count: offsets.count)
    }

    func candidate(_ index: Int) -> Candidate {
        if let known = made[index] { return known }
        let offset = offsets[index]
        let color = ThemeColor(oklchL: lch.l + offset.lightness, c: max(0, lch.c + offset.chroma), h: lch.h + offset.hue)
            .storable(alpha: from.alpha)
        let lab = Lab(color)
        let meant = max(0, lch.c + offset.chroma)
        let candidate = Candidate(color: color, lab: lab, cost: offset.cost, clipped: lab.chroma < meant - 0.01)
        made[index] = candidate
        return candidate
    }
}

private final class CandidateMemo {
    /// By color index × 2, plus 1 for combined moves.
    var lists: [Int: CandidateList] = [:]
}

private extension ThemeColor {
    /// As written to a theme file (8 bits per channel), so what's measured
    /// is what's drawn and shown as hex.
    func storable(alpha: Double) -> ThemeColor {
        func byte(_ value: Double) -> Double { (min(max(value, 0), 1) * 255).rounded() / 255 }
        return ThemeColor(red: byte(red), green: byte(green), blue: byte(blue), alpha: alpha)
    }
}
