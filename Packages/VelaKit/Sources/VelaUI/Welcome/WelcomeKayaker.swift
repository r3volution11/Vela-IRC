// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

nonisolated extension WelcomeArt {
    // MARK: The kayaker

    /// A kayaker paddling away from us, upstream toward the sun. `c` is the
    /// kayak's middle on the water, `heading` its course on screen and `k` the
    /// scene's scale (one point at 300 wide).
    static func drawKayaker<Painter: ScenePainter>(_ g: inout Painter, theme: WelcomeScene, p: Palette, at c: CGPoint, heading: CGPoint, k: CGFloat, sun: CGPoint) {
        // A small model in metres, x right, y away, z up, seen from above at
        // about 27 degrees.
        let sinE: CGFloat = 0.45, cosE: CGFloat = 0.893, sc = 9.6 * k
        var mirrored = false
        func P3(_ q: SceneVector) -> CGPoint { CGPoint(x: c.x + q.x * sc, y: c.y - (q.y * sinE + (mirrored ? -q.z : q.z) * cosE) * sc) }
        let hd = heading.unit
        let fwd = SceneVector(hd.x, -hd.y / sinE, 0).unit
        let side = SceneVector(fwd.y, -fwd.x, 0)                         // to starboard, toward us
        let up = SceneVector(0, 0, 1)
        let sunDir = SceneVector(0.40, 0.70, 0.60).unit
        let toUs = SceneVector(0, -cosE, sinE)
        let light = Lighting(amb: theme.bg.mix(theme.accent, 0.15).atLuma(0.5),
                             key: SceneRGB(r: 1, g: 0.93, b: 0.80).mix(p.light, 0.12).times(0.64), desat: 0, toward: (sun - c).unit)
        func lam(_ n: SceneVector) -> Double { Double(max(0, n.unit.dot(sunDir))) }
        func tone(_ m: SceneRGB, _ n: SceneVector, _ extra: Double = 0) -> SceneRGB { light.at(m, lam(n) + extra) }

        // A kayak color that stands off the theme's accent (the water's tint).
        let choices = [SceneRGB(r: 0.93, g: 0.45, b: 0.15), SceneRGB(r: 0.96, g: 0.74, b: 0.18), SceneRGB(r: 0.10, g: 0.48, b: 0.70)]
        func apart(_ h: Double) -> Double { let d = abs(h - theme.accent.hue); return min(d, 360 - d) }
        let hull = choices.max { apart($0.hue) < apart($1.hue) }!
        let vest = theme.accent.mix(SceneRGB(r: 0.5, g: 0.5, b: 0.5), 0.15).mix(SceneRGB.black, 0.06), shirt = SceneRGB(r: 0.34, g: 0.40, b: 0.47), skin = SceneRGB(r: 0.88, g: 0.66, b: 0.52)
        let hair = SceneRGB(r: 0.26, g: 0.18, b: 0.13), cap = SceneRGB(r: 0.20, g: 0.26, b: 0.40), neoprene = SceneRGB(r: 0.24, g: 0.26, b: 0.30)
        let blade = hull.mix(SceneRGB.black, 0.1), carbon = SceneRGB(r: 0.16, g: 0.16, b: 0.18)
        let crest = p.waterNear.mix(SceneRGB(r: 1, g: 0.97, b: 0.90), 0.5), trough = p.waterEdge

        // The hull: 3.7 m long; `deck(s, t)` from stern (s = -1) to bow (1),
        // port sheer (t = -1) over the ridge (0) to the starboard sheer (1).
        let half: CGFloat = 1.85
        func beam(_ s: CGFloat) -> CGFloat { 0.34 * pow(max(0, 1 - pow(abs(s), 2.2)), 0.62) }
        func sheer(_ s: CGFloat) -> CGFloat { 0.12 + 0.10 * s * s + 0.03 * s }
        func wbeam(_ s: CGFloat) -> CGFloat { 0.31 * pow(max(0, 1 - pow(abs(s) / 0.93, 2.2)), 0.62) }
        func at(_ s: CGFloat, _ off: CGFloat, _ z: CGFloat) -> SceneVector { fwd * (s * half) + side * off + up * z }
        func deck(_ s: CGFloat, _ t: CGFloat) -> SceneVector { at(s, beam(s) * t, sheer(s) + 0.085 * (1 - s * s) * (1 - t * t)) }
        func strip(_ s0: CGFloat, _ s1: CGFloat, _ t0: CGFloat, _ t1: CGFloat) -> Path {
            let ss = (0...20).map { s0 + (s1 - s0) * CGFloat($0) / 20 }
            return SceneShapes.closed((ss.map { deck($0, t0) } + ss.reversed().map { deck($0, t1) }).map(P3), smooth: false)
        }
        let ss = (0...28).map { -1 + 2 * CGFloat($0) / 28 }, ws = (0...24).map { -0.93 + 1.86 * CGFloat($0) / 24 }
        func sidePath(_ sign: CGFloat, _ upTo: CGFloat = 1) -> Path {
            let top = ss.map { s in at(s, sign * (wbeam(s) + (beam(s) - wbeam(s)) * upTo), sheer(s) * upTo) }
            return SceneShapes.closed((top + ws.reversed().map { at($0, sign * wbeam($0), 0) }).map(P3), smooth: false)
        }
        // The paddler: seated in the cockpit, starting a stroke on the right.
        let s0: CGFloat = -0.08
        let seat = at(s0 + 0.02, 0, 0.06)
        let chest = seat + up * 0.58 + fwd * 0.07
        let rSh = chest + side * 0.2 + fwd * 0.05, lSh = chest - side * 0.2 - fwd * 0.05
        let headC = chest + up * 0.215 + fwd * 0.05
        let hand1 = chest + fwd * 0.38 + side * 0.34 - up * 0.32          // the lower hand, at the catch
        let hand2 = chest + fwd * 0.06 - side * 0.30 + up * 0.30          // the top hand
        let elbow1 = (rSh + hand1) * 0.5 + side * 0.10 - up * 0.10
        let elbow2 = (lSh + hand2) * 0.5 - side * 0.14 - up * 0.10
        let shaft = (hand1 - hand2).unit, mid = (hand1 + hand2) * 0.5
        func bladePoints(_ sign: CGFloat, _ feather: CGFloat) -> [SceneVector] {
            let axis = shaft * sign, base = mid + axis * 0.64
            var w = fwd.cross(axis).unit
            if feather != 0 { w = (w * cos(feather) + axis.cross(w) * sin(feather)).unit }
            let ts: [CGFloat] = [0, 0.25, 0.55, 0.85, 1.0], top: [CGFloat] = [0.03, 0.075, 0.095, 0.098, 0.065], bot: [CGFloat] = [-0.03, -0.06, -0.085, -0.092, -0.05]
            return ts.indices.map { base + axis * (ts[$0] * 0.46) + w * top[$0] } + ts.indices.reversed().map { base + axis * (ts[$0] * 0.46) + w * bot[$0] }
        }
        let bladeA = bladePoints(1, 0), bladeB = bladePoints(-1, 1.0)
        // Where blade A meets the water, and the part of it under the surface.
        var under: [SceneVector] = [], entry: [SceneVector] = []
        for i in bladeA.indices {
            let a = bladeA[i], b = bladeA[(i + 1) % bladeA.count]
            if a.z < 0 { under.append(a) }
            if (a.z < 0) != (b.z < 0) { let t = a.z / (a.z - b.z); let x = a + (b - a) * t; under.append(x); entry.append(x) }
        }
        let splash = entry.count == 2 ? (entry[0] + entry[1]) * 0.5 : mid + shaft * 0.9
        let tipB = mid - shaft * 1.1

        func ellipse(_ center: SceneVector, _ r: CGFloat) -> Path {
            let q = P3(center)
            return Path(ellipseIn: CGRect(x: q.x - r * sc, y: q.y - r * sinE * sc, width: 2 * r * sc, height: 2 * r * sinE * sc))
        }
        func disc(_ q: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path { Path(ellipseIn: CGRect(x: q.x - rx, y: q.y - ry, width: 2 * rx, height: 2 * ry)) }
        /// A ripple: a ring on the water, its crest lighter on the far side and
        /// its trough darker on the near side.
        func ripple(_ gc: inout Painter, _ center: SceneVector, _ r: CGFloat, _ o: Double) {
            var ring = ellipse(center, r * 1.15)
            ring.addPath(ellipse(center, r * 0.78))
            let q = P3(center)
            gc.fill(ring, with: .linearGradient(SceneGradient(stops: [.init(color: crest.c(0.6 * o), location: 0), .init(color: crest.c(0.2 * o), location: 0.45),
                                                                 .init(color: trough.c(0.45 * o), location: 0.6), .init(color: trough.c(0.6 * o), location: 1)]),
                                                startPoint: CGPoint(x: q.x, y: q.y - r * sinE * sc), endPoint: CGPoint(x: q.x, y: q.y + r * sinE * sc)),
                    style: FillStyle(eoFill: true))
        }

        func drawHull(_ gc: inout Painter, detail: Bool) {
            gc.fill(sidePath(-1), with: .color(tone(hull, side * -1 + up * 0.2).color))
            let sideTop = P3(deck(0, 1)), sideLow = P3(at(0, wbeam(0), 0))
            gc.fill(sidePath(1), with: .linearGradient(SceneGradient(colors: [light.at(hull, 0.18).color, light.at(hull, 0).color, light.at(hull, 0.05).mix(p.waterFar, 0.3).color]),
                                                      startPoint: sideTop, endPoint: sideLow))
            guard detail else { return }
            gc.fill(strip(-1, 1, -1, 0), with: .color(tone(hull, up - side * 0.5).color))
            gc.fill(strip(-1, 1, 0, 1), with: .color(tone(hull, up + side * 0.5, 0.06).color))
            // A glossy sheen along the deck where it turns to the sun and to us,
            // and the darker roll of the deck into the side.
            let sheen = light.at(hull, 1.25).mix(SceneRGB(r: 1, g: 0.96, b: 0.88), 0.3)
            gc.fill(strip(-0.8, 0.85, 0.12, 0.5), with: .linearGradient(SceneGradient(colors: [sheen.c(0), sheen.c(0.85), sheen.c(0.85), sheen.c(0)]),
                                                                        startPoint: P3(deck(-0.8, 0.3)), endPoint: P3(deck(0.85, 0.3))))
            gc.fill(strip(-0.97, 0.97, 0.82, 1), with: .color(light.at(hull, 0.28).c(0.8)))
            gc.fill(strip(-0.97, 0.97, -1, -0.8), with: .color(light.at(hull, 0.3).c(0.7)))
            // Deck lines: bungees in an X before the cockpit, perimeter lines,
            // and the rear hatch.
            let cord = light.at(carbon, 0.3).c(0.85)
            var lines = Path()
            for (a, b) in [(deck(0.30, -0.7), deck(0.62, 0.7)), (deck(0.30, 0.7), deck(0.62, -0.7)), (deck(0.30, -0.75), deck(0.30, 0.75)), (deck(0.62, -0.7), deck(0.62, 0.7)),
                           (deck(0.25, 0.86), deck(0.86, 0.86)), (deck(-0.40, 0.86), deck(-0.86, 0.86)), (deck(-0.38, -0.7), deck(-0.38, 0.7))] {
                lines.addPath(SceneShapes.capsule(P3(a), P3(b), max(0.28, 0.012 * sc), max(0.28, 0.012 * sc)))
            }
            gc.fill(lines, with: .color(cord))
            let hatch = SceneShapes.closed((0..<16).map { i in let th = CGFloat(i) / 16 * 2 * .pi; return P3(at(-0.62 + 0.075 * cos(th), 0.105 * sin(th), sheer(-0.62) + 0.075)) })
            gc.fill(hatch, with: .linearGradient(SceneGradient(colors: [light.at(neoprene, 0.9).color, light.at(neoprene, 0.1).color]),
                                                startPoint: P3(at(-0.62, -0.13, 0.25)), endPoint: P3(at(-0.62, 0.13, 0.2))))
            // The cockpit: a raised rim around the spray deck.
            let zc = sheer(s0) + 0.085 * (1 - s0 * s0) + 0.03
            func ring(_ a: CGFloat, _ b: CGFloat, _ z: CGFloat) -> Path {
                SceneShapes.closed((0..<24).map { i in let th = CGFloat(i) / 24 * 2 * .pi; return P3(fwd * (s0 * half + a * cos(th)) + side * (b * sin(th)) + up * z) })
            }
            gc.fill(ring(0.45, 0.245, zc - 0.03), with: .color(light.at(neoprene, 0.1).color))
            gc.fill(ring(0.45, 0.245, zc), with: .linearGradient(SceneGradient(colors: [light.at(neoprene, 0.7).color, light.at(neoprene, 0.2).color]),
                                                                 startPoint: P3(at(s0, -0.24, zc)), endPoint: P3(at(s0, 0.24, zc))))
            gc.fill(ring(0.39, 0.19, zc + 0.01), with: .linearGradient(SceneGradient(colors: [light.at(neoprene, 0.25).color, light.at(neoprene, 0.5).color]),
                                                                       startPoint: P3(at(s0, 0, zc - 0.05)), endPoint: P3(at(s0, 0, zc + 0.06))))
        }

        func drawPaddle(_ gc: inout Painter) {
            let a = P3(mid - shaft * 0.66), b = P3(mid + shaft * 0.66), r = max(0.45, 0.016 * sc)
            gc.fill(SceneShapes.capsule(a, b, r, r), with: light.shade(Path(), carbon, lo: 0.1, hi: 1.3, axis: (a, b), r: r))
            for (pts, isB) in [(bladeB, true), (bladeA, false)] {
                var n = (pts[2] - pts[0]).cross(pts[pts.count - 3] - pts[0]).unit
                if n.dot(toUs) < 0 { n = n * -1 }
                let path = SceneShapes.closed(pts.map(P3))
                let base = P3(pts[0] * 0.5 + pts[pts.count - 1] * 0.5), tip = P3(pts[4] * 0.5 + pts[5] * 0.5)
                let k0 = lam(n) + (isB ? 0.1 : 0)
                gc.fill(path, with: .linearGradient(SceneGradient(colors: [light.at(blade, k0 + 0.15).color, light.at(blade, k0).color, light.at(blade, max(0, k0 - 0.2)).color]),
                                                    startPoint: base, endPoint: tip))
                // The spine down the blade's middle.
                gc.fill(SceneShapes.capsule(base, base + (tip - base) * 0.8, r * 0.9, r * 0.5), with: .color(light.at(blade, k0 + 0.45).c(0.8)))
            }
        }

        func drawPaddler(_ gc: inout Painter, detail: Bool) {
            func limbShade(_ a: SceneVector, _ b: SceneVector, _ ra: CGFloat, _ rb: CGFloat, _ m: SceneRGB, lo: Double, hi: Double) {
                let pa = P3(a), pb = P3(b)
                gc.fill(SceneShapes.capsule(pa, pb, ra * sc, rb * sc), with: light.shade(Path(), m, lo: lo, hi: hi, axis: (pa, pb), r: max(ra, rb) * sc))
            }
            func blob(_ pts: [SceneVector], _ m: SceneRGB, lo: Double, hi: Double, from a: SceneVector, to b: SceneVector) {
                gc.fill(SceneShapes.closed(pts.map(P3)), with: light.form(m, P3(a), P3(b), lo: lo, hi: hi))
            }
            // The far (left) arm, raised to the top hand.
            limbShade(lSh, elbow2, 0.05, 0.047, shirt, lo: 0, hi: 0.75)
            limbShade(elbow2, hand2, 0.047, 0.038, shirt, lo: 0, hi: 0.85)
            gc.fill(SceneShapes.capsule(P3(hand2 - shaft * 0.03), P3(hand2 + shaft * 0.04), 0.04 * sc, 0.04 * sc), with: .color(light.at(skin, 0.45).color))
            // Torso in a shirt, a life vest over it.
            let torso = [seat + up * 0.2 - side * 0.16, chest - up * 0.12 - side * 0.19, lSh + up * 0.03, chest + up * 0.07 - side * 0.06,
                         chest + up * 0.07 + side * 0.06, rSh + up * 0.03, chest - up * 0.12 + side * 0.19, seat + up * 0.2 + side * 0.16]
            blob(torso, shirt, lo: 0, hi: 0.9, from: seat + up * 0.2, to: chest + up * 0.08)
            let vestPts = [seat + up * 0.23 - side * 0.17, chest - up * 0.10 - side * 0.18, lSh + side * 0.085 + up * 0.035, chest + up * 0.065 - side * 0.075,
                           chest + up * 0.065 + side * 0.075, rSh - side * 0.085 + up * 0.035, chest - up * 0.10 + side * 0.18, seat + up * 0.23 + side * 0.17]
            blob(vestPts, vest, lo: 0.02, hi: 1.0, from: seat + up * 0.23 - side * 0.1, to: chest + up * 0.07 + side * 0.08)
            if detail {
                // The vest's lower panel and its side buckle.
                let lower = [seat + up * 0.23 - side * 0.17, seat + up * 0.31 - side * 0.175, seat + up * 0.31 + side * 0.175, seat + up * 0.23 + side * 0.17]
                gc.fill(SceneShapes.closed(lower.map(P3)), with: .color(light.at(vest, 0).c(0.75)))
                gc.fill(SceneShapes.closed([chest - up * 0.10 - side * 0.03, chest - up * 0.10 + side * 0.03, seat + up * 0.31 + side * 0.03, seat + up * 0.31 - side * 0.03].map(P3)),
                        with: .color(light.at(vest, 0).c(0.5)))
                gc.fill(SceneShapes.capsule(P3(seat + up * 0.27 + side * 0.175), P3(seat + up * 0.30 + side * 0.18), 0.02 * sc, 0.02 * sc), with: .color(light.at(carbon, 0.6).color))
            }
            // Neck, head from behind: hair under a cap, an ear, the arm of the
            // sunglasses; the cap's brim beyond.
            limbShade(chest + up * 0.02, headC - up * 0.06, 0.052, 0.048, skin, lo: 0, hi: 0.8)
            let brim = SceneShapes.closed((0..<16).map { i in let th = CGFloat(i) / 16 * 2 * .pi; return P3(headC + fwd * (0.12 + 0.075 * sin(th)) + side * (0.095 * cos(th)) + up * 0.04) })
            gc.fill(brim, with: .color(light.at(cap, 0.55).color))
            let hc = P3(headC)
            let headPath = disc(hc, 0.10 * sc, 0.115 * sc)
            gc.fill(headPath, with: light.form(hair, hc - light.toward * (0.12 * sc), hc + light.toward * (0.12 * sc), lo: 0, hi: 1.05))
            let ear = P3(headC + side * 0.097 - up * 0.01)
            gc.fill(disc(ear, 0.022 * sc, 0.034 * sc), with: .color(light.at(skin, 0.35).color))
            let capTop = SceneShapes.closed((0...12).map { i -> CGPoint in let th = Double(i) / 12 * .pi; return CGPoint(x: hc.x + CGFloat(cos(th)) * 0.108 * sc, y: hc.y - 0.012 * sc - CGFloat(sin(th)) * 0.118 * sc) })
            gc.fill(capTop, with: light.form(cap, hc - light.toward * (0.12 * sc), hc + light.toward * (0.12 * sc), lo: 0, hi: 1.1))
            if detail {
                gc.fill(SceneShapes.capsule(P3(headC + side * 0.09 - fwd * 0.02 + up * 0.005), P3(headC + side * 0.098 + fwd * 0.08 + up * 0.015), max(0.25, 0.011 * sc), max(0.25, 0.011 * sc)),
                        with: .color(light.at(carbon, 0.2).color))
            }
            // The near (right) arm, reaching forward to the catch.
            limbShade(rSh, elbow1, 0.05, 0.047, shirt, lo: 0, hi: 0.95)
            limbShade(elbow1, hand1, 0.047, 0.038, shirt, lo: 0, hi: 1.0)
            gc.fill(SceneShapes.capsule(P3(hand1 - shaft * 0.03), P3(hand1 + shaft * 0.04), 0.04 * sc, 0.04 * sc), with: .color(light.at(skin, 0.6).color))
        }

        // The reflection: the boat and paddler mirrored in the water, darker,
        // tinted by it and broken up by ripples.
        do {
            let top = P3(SceneVector(0, 0, 0)).y
            let box = CGRect(x: c.x - 3 * sc, y: top - 0.2 * sc, width: 6 * sc, height: 2 * sc)
            var rng = SceneRandom(state: 515)
            var cuts = Path()
            var y = top + 0.03 * sc
            while y < box.maxY {
                let h = CGFloat(rng.range(0.02, 0.045)) * sc
                for _ in 0..<3 {
                    let x = c.x + CGFloat(rng.range(-1.6, 1.6)) * sc, w = CGFloat(rng.range(0.15, 0.6)) * sc
                    cuts.addEllipse(in: CGRect(x: x - w, y: y + CGFloat(rng.range(-0.3, 0.3)) * h, width: 2 * w, height: h))
                }
                y += h * CGFloat(rng.range(1.3, 2.4))
            }
            var layer = SceneLayer(opacity: 0.34)
            layer.wash = (p.waterNear.c(0.35), box)
            layer.cuts = (cuts, 0.9)
            layer.fades = [SceneLayer.Fade(rect: box, paint: .linearGradient(SceneGradient(colors: [SceneRGB.black.c(1), SceneRGB.black.c(0)]),
                                                                             startPoint: CGPoint(x: c.x, y: top), endPoint: CGPoint(x: c.x, y: top + 1.3 * sc)))]
            g.drawLayer(layer) { r in
                mirrored = true
                drawPaddle(&r)
                drawPaddler(&r, detail: false)
                drawHull(&r, detail: false)
                mirrored = false
            }
        }

        // On the water: the hull's shadow and the paddler's (the sun ahead
        // throws them back toward us), the wake, eddies from earlier strokes.
        let toGround = SceneVector(sunDir.x / sunDir.z, sunDir.y / sunDir.z, 0)
        func flat(_ q: SceneVector) -> SceneVector { SceneVector(q.x - toGround.x * q.z, q.y - toGround.y * q.z, 0) }
        let shadePts = [seat - side * 0.2, lSh, headC + up * 0.1 - side * 0.05, headC + up * 0.1 + side * 0.05, rSh, seat + side * 0.2].map(flat)
        g.fill(SceneShapes.closed(shadePts.map(P3)), with: .color(trough.c(0.22)))
        g.fill(SceneShapes.closed(ss.map { flat(at($0, beam($0) * 1.05, sheer($0))) }.map(P3) + ss.reversed().map { P3(at($0, -beam($0), 0)) }), with: .color(trough.c(0.28)))
        // The wake: short crests stepping out from the bow on either side,
        // each with its trough behind it, fading as they spread.
        let bow = at(0.9, 0, 0)
        for sign in [-1, 1] as [CGFloat] {
            let arm = (fwd * -0.94 + side * (0.34 * sign)).unit
            let out = (arm * 0.45 + side * (0.9 * sign)).unit
            for i in 0..<6 {
                let t = CGFloat(i), o = 0.85 - Double(i) * 0.13
                let c0 = bow + arm * (0.35 + t * 0.62)
                let len = 0.26 + t * 0.08, w = 0.05 + t * 0.008
                let a = c0 - out * len, b = c0 + out * len
                let crestPath = SceneShapes.closed([a, c0 + arm * w * -1, b, c0 + arm * (w * 0.3)].map(P3))
                let troughPath = SceneShapes.closed([a + arm * 0.02, c0 + arm * (w * 0.5), b + arm * 0.02, c0 + arm * (w * 2.6)].map(P3))
                g.fill(troughPath, with: .color(trough.c(0.5 * o)))
                g.fill(crestPath, with: .color(crest.c(0.95 * o)))
            }
        }
        // The smooth trail behind the stern.
        let stern = at(-0.95, 0, 0)
        let trail = SceneShapes.closed([stern + side * 0.06, stern - fwd * 1.6 + side * 0.16, stern - fwd * 3.2 + side * 0.05, stern - fwd * 3.2 - side * 0.05, stern - fwd * 1.6 - side * 0.16, stern - side * 0.06].map(P3))
        g.fill(trail, with: .linearGradient(SceneGradient(colors: [crest.c(0.4), crest.c(0)]), startPoint: P3(stern), endPoint: P3(stern - fwd * 3.2)))
        for (i, (back, off)) in [(1.4, 0.75), (2.5, -0.85), (3.6, 0.8)].enumerated() {
            let e = at(-0.1, 0, 0) - fwd * CGFloat(back) + side * CGFloat(off)
            ripple(&g, e, 0.16 + CGFloat(i) * 0.05, 0.7 - Double(i) * 0.18)
            ripple(&g, e, 0.07 + CGFloat(i) * 0.03, 0.55 - Double(i) * 0.15)
        }
        // Rings where the drips from the raised blade land, and around the
        // blade at the catch.
        let dripFoot = SceneVector(tipB.x, tipB.y, 0)
        ripple(&g, dripFoot, 0.07, 0.8)
        ripple(&g, dripFoot, 0.15, 0.5)
        ripple(&g, splash, 0.2, 0.85)
        ripple(&g, splash, 0.34, 0.5)
        // Darker water hugging the waterline.
        g.fill(SceneShapes.closed((ws.map { at($0, wbeam($0), 0) } + ws.reversed().map { at($0, wbeam($0) + 0.05, -0.04) }).map(P3)), with: .color(trough.c(0.55)))

        // The bow wave curling off the stem, either side.
        func bowWave(_ sign: CGFloat) {
            let w = [at(0.97, 0, 0.01), at(0.80, sign * 0.12, 0.025), at(0.52, sign * 0.29, 0), at(0.70, sign * 0.21, -0.01), at(0.88, sign * 0.06, 0)]
            g.fill(SceneShapes.closed(w.map(P3)), with: .color(crest.c(0.9)))
        }
        bowWave(-1)
        drawHull(&g, detail: true)
        bowWave(1)
        drawPaddle(&g)
        drawPaddler(&g, detail: true)
        // The blade under the surface, seen through it; the water heaped around
        // it; a few drops thrown up.
        if under.count > 2 { g.fill(SceneShapes.closed(under.map(P3), smooth: false), with: .color(p.waterNear.mix(trough, 0.25).c(0.62))) }
        let sp = P3(splash)
        g.fill(disc(sp + CGPoint(x: 0, y: 0.01 * sc), 0.12 * sc, 0.035 * sc), with: .linearGradient(SceneGradient(colors: [crest.c(0.8), crest.c(0.35)]),
                                                                                               startPoint: sp - CGPoint(x: 0, y: 0.04 * sc), endPoint: sp + CGPoint(x: 0, y: 0.05 * sc)))
        // Drips falling from the raised blade's tip.
        for (i, dz) in ([0.12, 0.32, 0.58, 0.9, 1.25] as [CGFloat]).enumerated() where tipB.z - dz > 0.05 {
            let q = P3(tipB - up * dz + side * (0.015 * CGFloat(i % 2)))
            let r = max(0.45, (0.03 - CGFloat(i) * 0.003) * sc)
            let drop = Path { d in
                d.move(to: CGPoint(x: q.x, y: q.y - r * 2.2))
                d.addQuadCurve(to: CGPoint(x: q.x + r, y: q.y), control: CGPoint(x: q.x + r * 0.9, y: q.y - r * 0.9))
                d.addArc(center: q, radius: r, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
                d.addQuadCurve(to: CGPoint(x: q.x, y: q.y - r * 2.2), control: CGPoint(x: q.x - r * 0.9, y: q.y - r * 0.9))
            }
            g.fill(drop, with: .linearGradient(SceneGradient(colors: [crest.c(0.95), p.waterNear.c(0.9)]), startPoint: CGPoint(x: q.x + r, y: q.y - r * 2), endPoint: CGPoint(x: q.x - r, y: q.y + r)))
        }
    }
}
