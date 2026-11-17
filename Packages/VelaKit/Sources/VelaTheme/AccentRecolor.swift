// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Switches a theme's accent to another color everywhere the theme uses it,
/// producing token overrides for `appearance.colorCustomizations`.
///
/// Works on the theme as designed (no user overrides). For each color the
/// theme sets:
/// - the accent itself, or a color that's practically the same, becomes the
///   new accent (keeping the token's alpha);
/// - the theme's `accentText` and `accentForeground` become the new ones;
/// - tokens whose role is the accent's (their registry default derives from
///   it) and whose color is a tint, shade or translucent wash of the accent
///   are rebuilt from the new accent in the same proportions;
/// - semantic colors (success, warnings, errors, joins and parts) never
///   change, even when they match the accent.
///
/// `accentForeground` is re-chosen to read at 4.5:1 on the new accent and
/// `accentText` is lightened or darkened to 4.5:1 on the window, chat and
/// settings backgrounds. Finally every contrast pair the theme audit checks
/// is kept at least as readable as the theme had it (or at the audit's
/// minimum, when the theme met it). Tokens the theme leaves to their
/// defaults follow the new accent through the registry on their own.
public enum AccentRecolor {
    /// Colors closer than this (OKLab ΔE) are the same color.
    static let sameColor = 0.02
    /// How far a color may sit from a straight mix of the accent with a
    /// surface (or black or white) and still count as that mix.
    static let mixTolerance = 0.02
    /// Text drawn in the accent (links, your nick, mentions).
    public static let textContrast = 4.5

    /// Tokens whose color means something. They keep it even when it
    /// happens to equal the accent.
    public static let semanticTokens: Set<String> = [
        ThemeKey.statusSuccess, ThemeKey.statusWarning, ThemeKey.statusError,
        ThemeKey.chatError, ThemeKey.chatEventJoin, ThemeKey.chatEventPart, ThemeKey.chatEventQuit,
    ]

    /// The overrides that give `definition` (flattened, without user
    /// overrides; `base` is it resolved) the accent `color`. Includes
    /// `accent`, `accentText` and `accentForeground`, plus every other token
    /// whose color changes.
    public static func overrides(
        for definition: ThemeDefinition,
        base: ResolvedTheme,
        accent color: ThemeColor
    ) -> [String: ThemeColor] {
        let oldAccent = base.color(ThemeKey.accent).withAlpha(1)
        let oldText = base.color(ThemeKey.accentText).withAlpha(1)
        let oldForeground = base.color(ThemeKey.accentForeground).withAlpha(1)
        let accent = color.withAlpha(1)
        let text = accentText(for: accent, in: base)
        let foreground = accentForeground(on: accent, like: oldForeground)

        var result: [String: ThemeColor] = [
            ThemeKey.accent: accent,
            ThemeKey.accentText: text,
            ThemeKey.accentForeground: foreground,
        ]

        let family = accentFamily(for: base.kind)
        let surfaces = [ThemeKey.windowBackground, ThemeKey.chatBackground, ThemeKey.sidebarBackground, ThemeKey.settingsBackground]
            .map { ThemeAudit.surface($0, in: base) }
        let anchors = [(oldAccent, accent)] + (oldText.distance(to: oldAccent) < sameColor ? [] : [(oldText, text)])

        for key in definition.colors.keys.sorted() where result[key] == nil && !semanticTokens.contains(key) {
            let original = base.color(key)
            let opaque = original.withAlpha(1)
            var replacement: ThemeColor?
            if opaque.distance(to: oldAccent) < sameColor {
                replacement = accent
            } else if opaque.distance(to: oldText) < sameColor {
                replacement = text
            } else if family.contains(key) {
                if opaque.distance(to: oldForeground) < sameColor {
                    replacement = foreground
                } else if let mix = remix(opaque, anchors: anchors, surfaces: surfaces) {
                    replacement = mix
                } else {
                    replacement = rotated(opaque, from: oldAccent, to: accent)
                }
            }
            if let replacement {
                let value = replacement.withAlpha(original.alpha)
                if value.hex != original.hex { result[key] = value }
            }
        }

        repairContrast(definition: definition, base: base, overrides: &result, accent: accent, text: text)
        return result
    }

    // MARK: Accent text and foreground

    /// `accent` with its lightness moved just far enough to read at 4.5:1 on
    /// the window, chat and settings backgrounds.
    static func accentText(for accent: ThemeColor, in base: ResolvedTheme) -> ThemeColor {
        let backgrounds = [ThemeKey.windowBackground, ThemeKey.chatBackground, ThemeKey.settingsBackground]
            .map { ThemeAudit.surface($0, in: base) }
        return accent.adjustingLightness(toReach: textContrast, against: backgrounds)
    }

    /// Text for accent-colored fills: the theme's own choice (a dark one
    /// re-tinted to the new hue) when it still reads at 4.5:1, otherwise
    /// white or a dark shade of the accent.
    static func accentForeground(on fill: ThemeColor, like original: ThemeColor) -> ThemeColor {
        let tinted = original.isDark && original.chroma > 0.005 ? original.withHue(of: fill) : original
        for candidate in [tinted, original, .white] where candidate.contrastRatio(against: fill) >= textContrast {
            return candidate
        }
        var amount = 0.82
        while amount < 1 {
            let dark = fill.mixed(with: .black, amount: amount)
            if dark.contrastRatio(against: fill) >= textContrast { return dark }
            amount += 0.02
        }
        return ThemeColor.white.contrastRatio(against: fill) >= ThemeColor.black.contrastRatio(against: fill) ? .white : .black
    }

    // MARK: Accent variants

    /// Tokens whose registry default derives from `accent`, `accentText` or
    /// `accentForeground`, directly or through other tokens: the ones whose
    /// job is to show the accent.
    static func accentFamily(for kind: ThemeKind) -> Set<String> {
        let roots: Set<String> = [ThemeKey.accent, ThemeKey.accentText, ThemeKey.accentForeground]
        var memo: [String: Bool] = [:]
        func derives(_ key: String, visiting: Set<String>) -> Bool {
            if roots.contains(key) { return true }
            if let known = memo[key] { return known }
            guard !visiting.contains(key), let token = ThemeRegistry.token(key) else { return false }
            let result = token.defaultValue(for: kind).references.contains {
                derives($0, visiting: visiting.union([key]))
            }
            memo[key] = result
            return result
        }
        return Set(ThemeRegistry.tokens.map(\.key).filter { derives($0, visiting: []) })
    }

    /// If `color` is a mix of an old accent color with a surface (or black or
    /// white), the same mix of the new one.
    static func remix(
        _ color: ThemeColor,
        anchors: [(old: ThemeColor, new: ThemeColor)],
        surfaces: [ThemeColor]
    ) -> ThemeColor? {
        let bases = surfaces.map { ($0, true) } + [(ThemeColor.black, false), (ThemeColor.white, false)]
        var best: (residual: Double, result: ThemeColor)?
        for (base, isSurface) in bases {
            for anchor in anchors {
                guard let fit = mixFit(color, from: base, toward: anchor.old) else { continue }
                // Surfaces take light tints; black and white only shades
                // and tints that are mostly the accent.
                let range = isSurface ? 0.04...1.05 : 0.5...1.05
                guard range.contains(fit.amount), fit.residual < mixTolerance,
                      best.map({ fit.residual < $0.residual }) ?? true else { continue }
                let b = base.oklab, n = anchor.new.oklab, t = fit.amount
                // A tinted surface keeps its lightness, so it stays where the
                // theme put it among the other surfaces (and under its text)
                // even when the new accent is much lighter or darker.
                let result = ThemeColor(
                    oklabL: isSurface ? color.oklab.l : b.l + (n.l - b.l) * t,
                    a: b.a + (n.a - b.a) * t,
                    b: b.b + (n.b - b.b) * t
                )
                best = (fit.residual, result)
            }
        }
        return best?.result
    }

    /// How much of `anchor` is mixed into `base` to make `color` (OKLab),
    /// and how far `color` is from that mix. `nil` when the color isn't
    /// tinted toward the anchor's hue (a lighter or darker grey lines up
    /// with a light accent by lightness alone).
    static func mixFit(_ color: ThemeColor, from base: ThemeColor, toward anchor: ThemeColor) -> (amount: Double, residual: Double)? {
        let c = color.oklab, b = base.oklab, a = anchor.oklab
        let d = (l: a.l - b.l, a: a.a - b.a, b: a.b - b.b)
        let length = d.l * d.l + d.a * d.a + d.b * d.b
        guard length > 1e-6 else { return nil }
        let v = (l: c.l - b.l, a: c.a - b.a, b: c.b - b.b)
        let t = (v.l * d.l + v.a * d.a + v.b * d.b) / length
        let r = (l: v.l - t * d.l, a: v.a - t * d.a, b: v.b - t * d.b)
        let residual = (r.l * r.l + r.a * r.a + r.b * r.b).squareRoot()
        let chromaLength = d.a * d.a + d.b * d.b
        if chromaLength > 0.0004 {
            let chromaAmount = (v.a * d.a + v.b * d.b) / chromaLength
            guard chromaAmount >= 0.6 * t else { return nil }
        }
        return (t, residual)
    }

    /// A color in the accent's hue family that isn't a plain mix (a hand-
    /// tuned shade): the same lightness, turned to the new hue with its
    /// colorfulness scaled alike. `nil` for colors unrelated to the accent.
    static func rotated(_ color: ThemeColor, from old: ThemeColor, to new: ThemeColor) -> ThemeColor? {
        let o = old.oklch, n = new.oklch, c = color.oklch
        guard o.c >= 0.04, c.c >= max(0.04, 0.35 * o.c) else { return nil }
        let delta = abs(c.h - o.h).truncatingRemainder(dividingBy: 360)
        guard min(delta, 360 - delta) < 30 else { return nil }
        let scale = min(max(n.c / o.c, 0.5), 2)
        return ThemeColor(oklchL: c.l, c: c.c * scale, h: c.h + n.h - o.h)
    }

    // MARK: Contrast

    /// Keeps every pair `ThemeAudit` checks at least as readable as the
    /// theme had it (capped at the check's minimum). A recolored foreground
    /// is adjusted (accent-colored text first tries `accentText`); a
    /// recolored background under the theme's own text is adjusted instead.
    static func repairContrast(
        definition: ThemeDefinition,
        base: ResolvedTheme,
        overrides: inout [String: ThemeColor],
        accent: ThemeColor,
        text: ThemeColor
    ) {
        let baseRatios = ThemeAudit.checks.map { check in
            base.color(check.foreground).contrastRatio(against: ThemeAudit.surface(check.background, in: base))
        }
        for _ in 0..<6 {
            let overrideHex = ThemeOverrides(colors: overrides.mapValues(\.hex))
            guard let resolved = try? ThemeResolver.resolve(definition, id: base.id, includeLoader: { _ in nil }, overrides: overrideHex) else { return }
            var changed = false
            for (index, check) in ThemeAudit.checks.enumerated() {
                // The audit's minimum, or what the theme had when it fell short.
                let target = baseRatios[index] >= check.minimum ? check.minimum : baseRatios[index] - 0.01
                let background = ThemeAudit.surface(check.background, in: resolved)
                let foreground = resolved.color(check.foreground)
                guard foreground.contrastRatio(against: background) < target else { continue }
                let foregroundChanged = foreground.hex != base.color(check.foreground).hex
                let backgroundChanged = resolved.color(check.background).hex != base.color(check.background).hex
                if foregroundChanged || !backgroundChanged {
                    let isAccent = foreground.withAlpha(1).distance(to: accent) < sameColor
                    if isAccent, text.withAlpha(foreground.alpha).contrastRatio(against: background) >= target {
                        overrides[check.foreground] = text.withAlpha(foreground.alpha)
                    } else {
                        overrides[check.foreground] = foreground.adjustingLightness(toReach: target, against: [background])
                    }
                } else {
                    let token = resolved.color(check.background)
                    let opaqueForeground = foreground.composited(over: background)
                    overrides[check.background] = token.adjustingLightness(toReach: target, against: [opaqueForeground])
                }
                changed = true
            }
            if !changed { return }
        }
    }
}

// MARK: - OKLab and OKLCh

extension ThemeColor {
    /// The sRGB color at OKLab `l`, `a`, `b`. Colors outside sRGB keep their
    /// lightness and hue and lose just enough chroma to fit.
    init(oklabL l: Double, a: Double, b: Double, alpha: Double = 1) {
        func encode(_ c: Double) -> Double {
            c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        func linear(_ scale: Double) -> (Double, Double, Double) {
            let a = a * scale, b = b * scale
            let l_ = l + 0.3963377774 * a + 0.2158037573 * b
            let m_ = l - 0.1055613458 * a - 0.0638541728 * b
            let s_ = l - 0.0894841775 * a - 1.2914855480 * b
            let l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_
            return (
                4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
                -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
                -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
            )
        }
        func inGamut(_ rgb: (Double, Double, Double)) -> Bool {
            let range = -0.0005...1.0005
            return range.contains(rgb.0) && range.contains(rgb.1) && range.contains(rgb.2)
        }
        var rgb = linear(1)
        if !inGamut(rgb) {
            var low = 0.0, high = 1.0
            for _ in 0..<24 {
                let mid = (low + high) / 2
                if inGamut(linear(mid)) { low = mid } else { high = mid }
            }
            rgb = linear(low)
        }
        self.init(red: encode(max(rgb.0, 0)), green: encode(max(rgb.1, 0)), blue: encode(max(rgb.2, 0)), alpha: alpha)
    }

    /// The color at OKLCh lightness `l`, chroma `c` and hue `h` (degrees).
    init(oklchL l: Double, c: Double, h: Double, alpha: Double = 1) {
        let radians = h * .pi / 180
        self.init(oklabL: l, a: c * cos(radians), b: c * sin(radians), alpha: alpha)
    }

    /// OKLCh lightness, chroma and hue (degrees).
    var oklch: (l: Double, c: Double, h: Double) {
        (oklab.l, chroma, hue)
    }

    /// This color's lightness and chroma with `other`'s hue.
    func withHue(of other: ThemeColor) -> ThemeColor {
        let own = oklch
        return ThemeColor(oklchL: own.l, c: own.c, h: other.hue, alpha: alpha)
    }

    /// This color with its OKLab lightness moved, by as little as possible,
    /// until it reads at `minimum` contrast on every one of `backgrounds`:
    /// lighter on dark backgrounds, darker on light ones. Hue is kept;
    /// chroma only drops where sRGB runs out. Alpha is kept.
    func adjustingLightness(toReach minimum: Double, against backgrounds: [ThemeColor]) -> ThemeColor {
        let opaque = withAlpha(1)
        // Judged as written to settings.json (8 bits per channel), so a
        // color found right at the boundary doesn't round to just under it.
        func passes(_ color: ThemeColor) -> Bool {
            let stored = ThemeColor(hex: color.hex) ?? color
            return backgrounds.allSatisfy { stored.contrastRatio(against: $0) >= minimum }
        }
        guard !backgrounds.isEmpty, !passes(opaque) else { return self }
        let lab = opaque.oklab
        let darkCount = backgrounds.filter(\.isDark).count
        let lighten = darkCount * 2 >= backgrounds.count
        let limit = lighten ? 1.0 : 0.0
        func at(_ l: Double) -> ThemeColor { ThemeColor(oklabL: l, a: lab.a, b: lab.b) }
        guard passes(at(limit)) else { return at(limit).withAlpha(alpha) }
        var near = lab.l, far = limit
        for _ in 0..<30 {
            let mid = (near + far) / 2
            if passes(at(mid)) { far = mid } else { near = mid }
        }
        return at(far).withAlpha(alpha)
    }
}
