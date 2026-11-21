// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

// The background is flat; the stargazer and the kayaker, and what they
// handle, are modelled. Each part has its own material color, lit by the
// scene's key light (a cool moon or a warm sun, from the upper right) over an
// ambient fill from the sky: a shadow side, a base and a highlight.

nonisolated extension WelcomeArt {
    /// Light on a material: its own color under the key light and an ambient
    /// fill. `k` runs from 0 (turned away from the key) to 1 (facing it).
    struct Lighting {
        let amb, key: SceneRGB
        let desat: Double
        let toward: CGPoint            // toward the key light, on screen
        func at(_ m: SceneRGB, _ k: Double) -> SceneRGB {
            let l = m.luma, d = m.mix(SceneRGB(r: l, g: l, b: l), desat)
            return SceneRGB(r: min(0.96, d.r * (amb.r + key.r * k)), g: min(0.96, d.g * (amb.g + key.g * k)), b: min(0.96, d.b * (amb.b + key.b * k)))
        }
        /// Across a rounded form from its shadow edge `a` to its lit edge `b`:
        /// bounce light, the core shadow, the base, a highlight short of the edge.
        func form(_ m: SceneRGB, _ a: CGPoint, _ b: CGPoint, lo: Double = 0, hi: Double = 1) -> ScenePaint {
            let ks: [(CGFloat, Double)] = [(0, 0.14), (0.2, 0), (0.5, 0.4), (0.78, 0.78), (0.91, 1), (1, 0.8)]
            return .linearGradient(SceneGradient(stops: ks.map { SceneGradient.Stop(color: at(m, lo + (hi - lo) * $0.1).color, location: $0.0) }), startPoint: a, endPoint: b)
        }
        /// Shading for a rounded body, or, given its axis and radius, a cylinder
        /// (lit along its side nearer the light, or its top when the light runs
        /// along it).
        func shade(_ path: Path, _ m: SceneRGB, lo: Double = 0, hi: Double = 1, axis: (CGPoint, CGPoint)? = nil, r: CGFloat = 0) -> ScenePaint {
            if let (a, b) = axis {
                var n = (b - a).unit.turned
                if n.x * toward.x + n.y * toward.y - 0.35 * n.y < 0 { n = n * -1 }
                let mid = (a + b) * 0.5
                return form(m, mid - n * r, mid + n * r, lo: lo, hi: hi)
            }
            let bb = path.boundingRect, c = CGPoint(x: bb.midX, y: bb.midY)
            let e = (abs(toward.x) * bb.width + abs(toward.y) * bb.height) / 2
            return form(m, c - toward * e, c + toward * e, lo: lo, hi: hi)
        }
        /// A ball: lit on the side toward the light.
        func ball(_ path: Path, _ m: SceneRGB, lo: Double = 0, hi: Double = 1) -> ScenePaint {
            let bb = path.boundingRect, rr = max(bb.width, bb.height) / 2
            let c = CGPoint(x: bb.midX, y: bb.midY) + toward * (rr * 0.5)
            return .radialGradient(SceneGradient(colors: [at(m, hi).color, at(m, lo + (hi - lo) * 0.45).color, at(m, lo).color, at(m, lo + 0.1).color]),
                                   center: c, startRadius: 0, endRadius: rr * 1.6)
        }
    }

    // MARK: The stargazer

    /// A stargazer in winter clothes at a refractor aimed at the moon. `foot` is
    /// the ground between their feet, `u` one unit (they are about 34 units, or
    /// 1.75 m, tall) and `ground(x)` the knoll's outline (screen y at screen x).
    static func drawStargazer<Painter: ScenePainter>(_ g: inout Painter, theme: WelcomeScene, p: Palette, foot: CGPoint, u: CGFloat, moon: CGPoint, ground: (CGFloat) -> CGFloat) {
        // Units: x right, y up.
        func f(_ q: CGPoint) -> CGPoint { CGPoint(x: foot.x + q.x * u, y: foot.y - q.y * u) }
        func f(_ x: CGFloat, _ y: CGFloat) -> CGPoint { f(CGPoint(x: x, y: y)) }
        func shape(_ pts: [CGPoint], smooth: Bool = true) -> Path { SceneShapes.closed(pts.map { f($0) }, smooth: smooth) }
        func shape(_ pts: [(CGFloat, CGFloat)], smooth: Bool = true) -> Path { SceneShapes.closed(pts.map { f($0.0, $0.1) }, smooth: smooth) }
        func limb(_ a: CGPoint, _ b: CGPoint, _ ra: CGFloat, _ rb: CGFloat) -> Path { SceneShapes.capsule(f(a), f(b), ra * u, rb * u) }
        func circle(_ q: CGPoint, _ r: CGFloat) -> Path { let c = f(q); return Path(ellipseIn: CGRect(x: c.x - r * u, y: c.y - r * u, width: 2 * r * u, height: 2 * r * u)) }
        /// The ground's height at x, from the knoll, relative to the feet.
        func gy(_ x: CGFloat) -> CGFloat { (ground(foot.x) - ground(foot.x + x * u)) / u }

        // Cool moonlight from the upper right over the night sky's fill, in the
        // theme's hue; a little warm red from the lamp at their feet.
        let toMoon = (moon - foot).unit
        let light = Lighting(amb: theme.bg.mix(theme.accent, 0.25).atLuma(0.2), key: p.light.times(0.66), desat: 0.35, toward: toMoon)
        let lens = CGPoint(x: -3.3, y: -0.45)
        let red = SceneRGB(r: 1, g: 0.26, b: 0.17)
        func paint(_ path: Path, _ m: SceneRGB, lo: Double = 0, hi: Double = 1, axis: (CGPoint, CGPoint)? = nil, r: CGFloat = 0, warm: Double = 0) {
            let ax: (CGPoint, CGPoint)? = axis.map { (f($0.0), f($0.1)) }
            g.fill(path, with: light.shade(path, m, lo: lo, hi: hi, axis: ax, r: r * u))
            if warm > 0 {
                g.fill(path, with: .radialGradient(SceneGradient(colors: [red.c(0.5 * warm), red.c(0.16 * warm), red.c(0)]), center: f(lens), startRadius: 0, endRadius: 9 * u))
            }
        }
        func ball(_ path: Path, _ m: SceneRGB, lo: Double = 0, hi: Double = 1) { g.fill(path, with: light.ball(path, m, lo: lo, hi: hi)) }
        /// Moonlight catching the edge of a form that faces it: the shape less a
        /// copy of itself moved away from the moon, `w` units wide.
        func rim(_ path: Path, _ m: SceneRGB, _ w: CGFloat = 0.35, _ k: Double = 1.3, _ o: Double = 0.85) {
            var edge = g
            edge.clip(to: path)
            var cut = Path(path.boundingRect.insetBy(dx: -4 * u, dy: -4 * u))
            cut.addPath(path.offsetBy(dx: -toMoon.x * w * u, dy: -toMoon.y * w * u))
            edge.fill(cut, with: .color(light.at(m, k).c(o)), style: FillStyle(eoFill: true))
        }
        func tint(_ path: Path, _ m: SceneRGB, _ k: Double, _ o: Double = 1) { g.fill(path, with: .color(light.at(m, k).c(o))) }

        // Materials.
        let coat = SceneRGB(r: 0.20, g: 0.38, b: 0.42), knit = SceneRGB(r: 0.86, g: 0.64, b: 0.28), pants = SceneRGB(r: 0.31, g: 0.32, b: 0.38)
        let leather = SceneRGB(r: 0.50, g: 0.33, b: 0.22), fleece = SceneRGB(r: 0.88, g: 0.82, b: 0.70), glove = SceneRGB(r: 0.22, g: 0.22, b: 0.25)
        let skin = SceneRGB(r: 0.97, g: 0.68, b: 0.52), scarfRed = SceneRGB(r: 0.72, g: 0.20, b: 0.19), cream = SceneRGB(r: 0.93, g: 0.91, b: 0.85), blackened = SceneRGB(r: 0.15, g: 0.15, b: 0.17)
        let alu = SceneRGB(r: 0.68, g: 0.70, b: 0.74), mountWhite = SceneRGB(r: 0.88, g: 0.88, b: 0.86), rubber = SceneRGB(r: 0.12, g: 0.12, b: 0.13)
        let pack = SceneRGB(r: 0.38, g: 0.42, b: 0.30), steel = SceneRGB(r: 0.70, g: 0.72, b: 0.75)

        // The telescope, laid along its axis toward the moon: `T(s, w)` is `s`
        // along the tube from the star diagonal and `w` across it (upward).
        let E = CGPoint(x: 6.3, y: 28.2)                          // the eyecup
        let eS = f(E)
        let d = CGPoint(x: moon.x - eS.x, y: eS.y - moon.y).unit
        let n = d.turned
        let ea = (n - d * 0.15).unit                              // the eyepiece's axis
        let dg = E - ea * 2.6
        func T(_ s: CGFloat, _ w: CGFloat) -> CGPoint { dg + d * s + n * w }
        func tube(_ s0: CGFloat, _ s1: CGFloat, _ w: CGFloat, _ m: SceneRGB, lo: Double = 0, hi: Double = 1, at w0: CGFloat = 0) {
            paint(SceneShapes.band(f(T(s0, w0)), f(T(s1, w0)), w * u, w * u), m, lo: lo, hi: hi, axis: (T(s0, w0), T(s1, w0)), r: w)
        }
        // The tripod and the equatorial head.
        let q = T(7.8, -3.4)                                      // where the RA and Dec axes meet
        let hub = CGPoint(x: q.x - 1.8, y: q.y - 3.1)
        let ground0 = gy(0)
        func legFoot(_ x: CGFloat, _ near: CGFloat) -> CGPoint { CGPoint(x: x, y: gy(x) - ground0 - near) }
        let legs: [(CGPoint, CGPoint)] = [(hub + CGPoint(x: -0.9, y: -0.4), legFoot(hub.x - 6.4, 0)),
                                          (hub + CGPoint(x: 0.9, y: -0.4), legFoot(hub.x + 6.6, 0)),
                                          (hub + CGPoint(x: 0, y: -0.4), legFoot(hub.x + 0.5, 0.9))]

        // Shadows: soft contact shadows on the knoll, thrown a little toward us
        // and to the left by the moon behind.
        let shadowColor = SceneRGB.black.c(0.42)
        for (c, rx, ry) in [(CGPoint(x: -0.2, y: -0.2), 4.6, 0.7), (CGPoint(x: -8.1, y: gy(-8) - ground0 - 0.2), 3.0, 0.55)] as [(CGPoint, CGFloat, CGFloat)] {
            let s = f(c)
            g.fill(Path(ellipseIn: CGRect(x: s.x - rx * u, y: s.y - ry * u, width: 2 * rx * u, height: 2 * ry * u)),
                   with: .radialGradient(SceneGradient(colors: [shadowColor, SceneRGB.black.c(0)]), center: s, startRadius: 0, endRadius: rx * u))
        }
        for (_, b) in legs {
            let s = f(b - CGPoint(x: 0.4, y: 0.1))
            g.fill(Path(ellipseIn: CGRect(x: s.x - 1.2 * u, y: s.y - 0.35 * u, width: 2.4 * u, height: 0.7 * u)), with: .color(SceneRGB.black.c(0.3)))
        }
        // The red lamp's pool of light on the ground.
        do {
            var pool = g
            let c = f(lens + CGPoint(x: 1.8, y: 0))
            pool.translateBy(x: c.x, y: c.y); pool.scaleBy(x: 1, y: 0.24)
            pool.fill(Path(ellipseIn: CGRect(x: -8 * u, y: -8 * u, width: 16 * u, height: 16 * u)),
                      with: .radialGradient(SceneGradient(colors: [red.c(0.26), red.c(0.08), red.c(0)]), center: .zero, startRadius: 0, endRadius: 8 * u))
        }

        // Tripod: the two back legs, the tray, the mount.
        func leg(_ top: CGPoint, _ bottom: CGPoint, lo: Double, hi: Double) {
            let clampAt = top + (bottom - top) * 0.56, lowerAt = top + (bottom - top) * 0.62
            paint(SceneShapes.band(f(top), f(clampAt), 0.52 * u, 0.48 * u), alu, lo: lo, hi: hi, axis: (top, clampAt), r: 0.5)
            paint(SceneShapes.band(f(lowerAt - (bottom - top).unit * 0.1), f(bottom), 0.36 * u, 0.34 * u), alu, lo: lo, hi: hi, axis: (lowerAt, bottom), r: 0.36)
            paint(SceneShapes.band(f(clampAt), f(lowerAt), 0.66 * u, 0.62 * u), blackened, lo: lo, hi: hi, axis: (clampAt, lowerAt), r: 0.66)
            paint(limb(bottom - (bottom - top).unit * 0.5, bottom, 0.42, 0.42), rubber, lo: lo, hi: hi * 0.8)
        }
        leg(legs[0].0, legs[0].1, lo: 0, hi: 0.65)
        leg(legs[1].0, legs[1].1, lo: 0, hi: 0.75)
        // The accessory tray between the legs, eyepieces sitting in it.
        let trayT: CGFloat = 0.52
        let tl = legs[0].0 + (legs[0].1 - legs[0].0) * trayT, tr = legs[1].0 + (legs[1].1 - legs[1].0) * trayT
        let tf = legs[2].0 + (legs[2].1 - legs[2].0) * trayT - CGPoint(x: 0, y: 0.5)
        let trayBack = (tl + tr) * 0.5 + CGPoint(x: 0, y: 0.6)
        let thick = CGPoint(x: 0, y: 0.4)
        paint(shape([tl, tf, tr, tr - thick, tf - thick, tl - thick], smooth: false), alu, lo: 0, hi: 0.45)
        tint(shape([tl, tf, tr, trayBack], smooth: false), alu, 0.62)
        g.fill(shape([tl, tf, (tl + tr) * 0.5 + CGPoint(x: 0, y: 0.2)], smooth: false), with: .color(light.at(alu, 0.85).c(0.6)))
        for (x, dy) in [(-1.9, 0.0), (1.4, -0.1)] as [(CGFloat, CGFloat)] {
            let c = tf + CGPoint(x: x * 0.8, y: 0.45 + dy)
            let s = f(c)
            g.fill(Path(ellipseIn: CGRect(x: s.x - 0.55 * u, y: s.y - 0.2 * u, width: 1.1 * u, height: 0.4 * u)), with: .color(light.at(rubber, 0).color))
        }
        let ep = tf + CGPoint(x: 0.1, y: 0.4)
        paint(SceneShapes.band(f(ep), f(ep + CGPoint(x: 0, y: 1.3)), 0.42 * u, 0.42 * u), blackened, lo: 0, hi: 0.9, axis: (ep, ep + CGPoint(x: 0, y: 1.3)), r: 0.42)
        paint(SceneShapes.band(f(ep + CGPoint(x: 0, y: 1.3)), f(ep + CGPoint(x: 0, y: 1.6)), 0.46 * u, 0.46 * u), alu, lo: 0.1, hi: 1.1, axis: (ep, ep + CGPoint(x: 0, y: 1.6)), r: 0.46)

        // The equatorial head: counterweight on its shaft, Dec and RA housings,
        // the tripod's hub.
        paint(SceneShapes.band(f(T(7.8, -4.4)), f(T(7.8, -8.9)), 0.2 * u, 0.2 * u), steel, lo: 0, hi: 1.1, axis: (T(7.8, -4.4), T(7.8, -8.9)), r: 0.2)
        paint(SceneShapes.band(f(T(7.8, -6.9)), f(T(7.8, -8.2)), 1.25 * u, 1.25 * u), steel.mix(blackened, 0.45), lo: 0, hi: 1, axis: (T(7.8, -6.9), T(7.8, -8.2)), r: 1.25)
        paint(SceneShapes.band(f(hub + CGPoint(x: 0, y: 0.5)), f(q), 0.95 * u, 0.95 * u), mountWhite, lo: 0, hi: 0.95, axis: (hub, q), r: 0.95)
        paint(SceneShapes.capsule(f(T(7.8, -2.0)), f(T(7.8, -4.5)), 0.85 * u, 0.85 * u), mountWhite, lo: 0, hi: 1, axis: (T(7.8, -2.0), T(7.8, -4.5)), r: 0.85)
        ball(circle(q, 0.55), blackened, lo: 0, hi: 1.2)
        paint(Path(roundedRect: CGRect(x: f(hub).x - 1.7 * u, y: f(hub).y - 0.6 * u, width: 3.4 * u, height: 1.1 * u), cornerRadius: 0.4 * u), alu, lo: 0, hi: 0.9)

        // The tube: dovetail and saddle, the SceneRGB.white tube in its rings, a dark dew
        // shield, the finder on its bracket.
        paint(SceneShapes.band(f(T(4.8, -1.5)), f(T(10.8, -1.5)), 0.3 * u, 0.3 * u), blackened, lo: 0, hi: 1)
        paint(SceneShapes.band(f(T(6.6, -1.95)), f(T(9.0, -1.95)), 0.35 * u, 0.35 * u), alu, lo: 0, hi: 1)
        tube(3.6, 13.6, 1.25, cream, lo: 0.02, hi: 1.08)
        tube(3.6, 4.2, 1.32, blackened, lo: 0, hi: 1.1)
        for s in [5.4, 9.6] as [CGFloat] {
            tube(s, s + 0.6, 1.44, blackened, lo: 0, hi: 1.2)
            paint(SceneShapes.band(f(T(s + 0.3, 1.4)), f(T(s + 0.3, 1.95)), 0.22 * u, 0.22 * u), blackened, lo: 0.1, hi: 1)
        }
        tube(13.4, 18.2, 1.55, SceneRGB(r: 0.21, g: 0.21, b: 0.23), lo: 0, hi: 1.15)
        tube(17.9, 18.25, 1.62, blackened, lo: 0, hi: 1.3)
        paint(SceneShapes.band(f(T(4.6, 1.25)), f(T(6.8, 1.25)), 0.38 * u, 0.38 * u), blackened, lo: 0, hi: 1)
        for s in [4.9, 6.5] as [CGFloat] { paint(SceneShapes.band(f(T(s, 1.3)), f(T(s, 2.0)), 0.18 * u, 0.18 * u), blackened, lo: 0, hi: 1) }
        tube(3.5, 7.6, 0.42, cream, lo: 0, hi: 1.08, at: 2.3)
        tube(6.8, 7.8, 0.55, blackened, lo: 0, hi: 1.2, at: 2.3)
        tube(3.0, 3.5, 0.3, blackened, lo: 0, hi: 1, at: 2.3)

        // The front leg, nearest us.
        leg(legs[2].0, legs[2].1, lo: 0.05, hi: 0.9)

        // The backpack on the ground, a thermos in its side pocket.
        let pb = gy(-8) - ground0 - 0.2
        func pk(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x - 1.1, y: y + pb) }
        let packBody = shape([pk(-9.1, 0.2), pk(-4.7, 0.2), pk(-4.3, 2.6), pk(-4.6, 5.3), pk(-5.6, 6.5), pk(-7.7, 6.6), pk(-8.9, 5.7), pk(-9.4, 3.0)])
        paint(packBody, pack, lo: 0.02, hi: 1.05, warm: 0.45)
        let pocket = shape([pk(-8.4, 0.9), pk(-5.4, 0.9), pk(-5.1, 2.1), pk(-5.4, 3.4), pk(-8.4, 3.4), pk(-8.7, 2.1)])
        tint(pocket.offsetBy(dx: -0.25 * u, dy: 0.25 * u), pack, 0, 0.8)
        paint(pocket, pack, lo: 0.05, hi: 0.95, warm: 0.45)
        let lid = shape([pk(-9.0, 4.9), pk(-4.5, 4.9), pk(-4.7, 5.9), pk(-5.7, 6.8), pk(-7.7, 6.9), pk(-8.9, 6.1)])
        tint(lid.offsetBy(dx: 0, dy: 0.35 * u), pack, 0, 0.85)
        paint(lid, pack.mix(SceneRGB.black, 0.25), lo: 0.05, hi: 1.1, warm: 0.35)
        paint(SceneShapes.band(f(pk(-6.6, 5.0)), f(pk(-6.7, 2.9)), 0.28 * u, 0.28 * u), rubber, lo: 0, hi: 0.9)
        paint(Path(CGRect(x: f(pk(-7.0, 3.9)).x, y: f(pk(-7.0, 3.9)).y, width: 0.7 * u, height: 0.55 * u)), steel, lo: 0.1, hi: 1)
        paint(limb(pk(-4.5, 1.2), pk(-4.4, 5.3), 0.62, 0.62), steel, lo: 0, hi: 1.1, axis: (pk(-4.5, 1.2), pk(-4.4, 5.3)), r: 0.62, warm: 0.9)
        paint(limb(pk(-4.4, 5.3), pk(-4.4, 6.2), 0.66, 0.6), blackened, lo: 0, hi: 1.1, axis: (pk(-4.4, 5.3), pk(-4.4, 6.2)), r: 0.66, warm: 0.6)
        paint(shape([pk(-4.9, 0.6), pk(-4.1, 0.6), pk(-4.0, 2.4), pk(-4.9, 2.6)]), pack.mix(SceneRGB.black, 0.2), lo: 0, hi: 1, warm: 0.9)

        // The person. Feet and legs.
        func boot(_ ax: CGFloat, far: Bool) {
            let hi: Double = far ? 0.55 : 1, w: Double = far ? 0.75 : 1
            let body = shape([(ax - 1.6, 0.1), (ax + 3.3, 0.1), (ax + 3.75, 0.6), (ax + 3.5, 1.45), (ax + 2.2, 2.05), (ax + 1.3, 3.2), (ax + 1.4, 4.2), (ax - 1.45, 4.3), (ax - 1.6, 2.8), (ax - 1.8, 1.0)])
            paint(body, leather, lo: 0, hi: hi, warm: w)
            paint(shape([(ax - 1.85, -0.05), (ax + 3.6, -0.05), (ax + 3.85, 0.6), (ax - 1.85, 0.6)], smooth: false), rubber, lo: 0, hi: hi, warm: w)
            paint(shape([(ax - 1.65, 3.85), (ax + 1.4, 3.75), (ax + 1.5, 4.45), (ax - 1.6, 4.55)]), fleece, lo: 0, hi: hi * 0.9, warm: w)
            if !far {
                for i in 0..<3 {
                    let c = CGPoint(x: ax + 1.5 + CGFloat(i) * 0.5, y: 2.75 - CGFloat(i) * 0.38)
                    tint(limb(c, c + CGPoint(x: 0.45, y: 0.35), 0.12, 0.12), leather, 0, 0.9)
                }
            }
        }
        func trouserLeg(_ hip: CGPoint, _ knee: CGPoint, _ ankle: CGPoint, far: Bool) {
            let hi: Double = far ? 0.5 : 0.95
            // One outline from hip to knee to the boot top, so the knee is seamless.
            let top = ankle + CGPoint(x: 0, y: 1.2)
            let n1 = (knee - hip).unit.turned, n2 = (top - knee).unit.turned, nk = (n1 + n2).unit
            let leg = shape([hip + n1 * 1.85, knee + nk * 1.45, top + n2 * 1.22, top - n2 * 1.22, knee - nk * 1.45, hip - n1 * 1.85])
            paint(leg, pants, lo: 0, hi: hi, axis: (hip, top), r: 1.5, warm: far ? 0.7 : 0.9)
            if !far { rim(leg, pants, 0.3, 1.2, 0.6) }
            // Creases behind the knee and where the trousers bunch on the boot.
            tint(shape([knee + CGPoint(x: -1.5, y: 1.0), knee + CGPoint(x: -0.8, y: 0.05), knee + CGPoint(x: -1.45, y: -0.7), knee + CGPoint(x: -1.6, y: 0.1)]), pants, 0, 0.7)
            tint(shape([ankle + CGPoint(x: -0.9, y: 2.3), ankle + CGPoint(x: 0.8, y: 2.0), ankle + CGPoint(x: -0.6, y: 1.9)]), pants, 0, 0.6)
        }
        let farAnkle = CGPoint(x: -2.0, y: 2.6), nearAnkle = CGPoint(x: 2.4, y: 2.6)
        trouserLeg(CGPoint(x: -0.8, y: 16), CGPoint(x: -1.4, y: 9.4), farAnkle, far: true)
        boot(farAnkle.x, far: true)
        trouserLeg(CGPoint(x: 0.6, y: 16), CGPoint(x: 2.05, y: 9.5), nearAnkle, far: false)
        boot(nearAnkle.x, far: false)

        // The parka, leaning toward the eyepiece; the hood bunched behind the
        // neck; folds in shadow.
        let coatPts: [(CGFloat, CGFloat)] = [(2.6, 28.4), (1.0, 28.4), (0.0, 27.6), (-0.9, 26.0), (-1.6, 23.7), (-2.0, 21.2), (-2.15, 19.1), (-2.6, 17.0),
                                             (-2.95, 14.6), (-3.2, 12.3), (-1.2, 11.8), (1.0, 11.85), (3.1, 12.1), (3.0, 14.4), (2.75, 16.6), (2.95, 18.7),
                                             (3.6, 21.4), (4.3, 23.7), (4.45, 25.4), (3.95, 26.7), (3.3, 27.7)]
        let coatPath = shape(coatPts)
        paint(coatPath, coat, lo: 0.06, hi: 1.05, warm: 0.25)
        rim(coatPath, coat, 0.4, 1.2, 0.7)
        do {
            var folds = g
            folds.clip(to: coatPath)
            let dark = light.at(coat, 0).c(0.75), lit = light.at(coat, 1.1).c(0.55)
            // Drape down the back of the skirt, the cinch at the waist, the
            // pocket flap, and the arm's shadow across the chest.
            folds.fill(shape([(-1.5, 19.5), (-1.95, 15.0), (-2.15, 11.6), (-1.75, 11.6), (-1.45, 15.0)]), with: .color(dark))
            folds.fill(shape([(0.2, 17.6), (0.0, 13.5), (0.2, 11.6), (0.55, 11.6), (0.5, 13.5)]), with: .color(dark))
            folds.fill(shape([(0.6, 18.9), (2.0, 18.5), (3.4, 19.0), (2.0, 18.85)]), with: .color(dark))
            folds.fill(shape([(1.0, 19.5), (2.2, 19.05), (3.5, 19.6), (2.2, 19.4)]), with: .color(lit))
            folds.fill(shape([(-1.6, 18.7), (-0.6, 18.5), (0.2, 18.75), (-0.6, 18.68)]), with: .color(dark))
            folds.fill(shape([(0.6, 15.9), (2.7, 15.8), (2.75, 14.9), (0.7, 15.0)]), with: .color(dark))
            folds.fill(shape([(0.6, 16.2), (2.7, 16.1), (2.7, 15.85), (0.6, 15.9)], smooth: false), with: .color(lit))
            folds.fill(shape([(3.2, 25.2), (5.0, 21.4), (4.6, 19.6), (2.4, 23.0)]), with: .color(dark))
            folds.fill(shape([(2.3, 28.6), (0.8, 28.0), (0.1, 26.6), (1.3, 27.3)]), with: .color(dark))
        }

        // The back of the telescope: focuser and knob, the star diagonal and
        // the eyepiece, at the far eye (the face is in front of it).
        tube(0.75, 1.55, 0.62, alu, lo: 0, hi: 1.15)
        tube(1.5, 3.6, 1.02, blackened, lo: 0, hi: 1.2)
        paint(SceneShapes.band(f(T(1.7, -1.0)), f(T(3.0, -1.0)), 0.45 * u, 0.45 * u), blackened, lo: 0, hi: 1)
        let knob = T(2.1, -1.5)
        ball(circle(knob, 0.62), blackened, lo: 0, hi: 1.4)
        paint(shape([T(-0.85, 0.85), T(-0.85, -0.05), T(-0.05, -0.85), T(0.8, -0.85), T(0.8, 0.85)], smooth: false), blackened, lo: 0, hi: 1.35)
        paint(SceneShapes.band(f(dg + ea * 0.8), f(dg + ea * 1.95), 0.56 * u, 0.56 * u), alu, lo: 0, hi: 1.15, axis: (dg + ea * 0.8, dg + ea * 1.95), r: 0.56)
        paint(SceneShapes.band(f(dg + ea * 1.2), f(dg + ea * 1.75), 0.6 * u, 0.6 * u), rubber, lo: 0, hi: 1.1, axis: (dg + ea * 1.2, dg + ea * 1.75), r: 0.6)
        paint(SceneShapes.capsule(f(dg + ea * 1.95), f(dg + ea * 2.45), 0.7 * u, 0.62 * u), rubber, lo: 0, hi: 1.1, axis: (dg + ea * 1.95, dg + ea * 2.45), r: 0.7)

        // The scarf's free end, hanging off the chest as they lean.
        paint(shape([(4.4, 26.2), (5.4, 26.1), (5.6, 23.0), (5.8, 20.7), (4.7, 20.6), (4.55, 23.0)]), scarfRed, lo: 0, hi: 0.95)
        for i in 0..<4 {
            let x = 4.85 + CGFloat(i) * 0.28
            tint(limb(CGPoint(x: x, y: 20.7), CGPoint(x: x + 0.05, y: 19.8), 0.11, 0.09), scarfRed, 0.3)
        }

        // The head, bowed to the eyepiece: `hl(a, b)` is `a` toward the face and
        // `b` toward the crown.
        let fw = CGPoint(x: 0.72, y: -0.69).unit, hu = fw.turned
        let eye = E + ea * 0.45
        let hd = eye - fw * 1.5 - hu * 0.3
        func hl(_ a: CGFloat, _ b: CGFloat) -> CGPoint { hd + fw * a + hu * b }
        let head = shape([hl(-1.95, 0.2), hl(-1.7, 1.5), hl(-0.6, 2.3), hl(0.8, 2.2), hl(1.6, 1.3), hl(1.85, 0.55), hl(1.62, 0.2), hl(2.35, -0.55),
                          hl(1.9, -0.78), hl(2.0, -1.05), hl(1.85, -1.3), hl(1.8, -1.75), hl(1.0, -2.1), hl(0, -1.7), hl(-1.0, -1.7), hl(-1.8, -0.9)])
        paint(head, skin, lo: 0.06, hi: 1.15)
        rim(head, skin, 0.3, 1.35, 0.9)
        tint(circle(hl(1.3, 0.12), 0.34), skin, 0, 0.75)               // the eye, in the brow's shadow
        tint(shape([hl(1.2, -0.2), hl(1.95, -0.6), hl(1.7, -0.9), hl(1.1, -0.7)]), skin, 0.05, 0.45)   // under the cheekbone
        // A knit hat with a folded cuff and a pompom.
        let hat = shape([hl(1.95, 0.75), hl(2.05, 1.35), hl(1.4, 2.45), hl(0.1, 2.9), hl(-1.3, 2.55), hl(-2.15, 1.3), hl(-2.3, 0.0), hl(-2.05, -0.65), hl(-0.4, -0.25), hl(1.0, 0.35)])
        paint(hat, knit, lo: 0, hi: 1.05)
        rim(hat, knit, 0.3)
        let cuff = shape([hl(2.0, 0.7), hl(0, 0.02), hl(-2.08, -0.68), hl(-2.32, 0.4), hl(0, 1.02), hl(2.08, 1.48)])
        paint(cuff, knit.mix(SceneRGB.black, 0.12), lo: 0, hi: 1.1, axis: (hl(0, -0.1), hl(0, 1.2)), r: 0.6)
        g.fill(shape([hl(2.06, 1.4), hl(0, 0.95), hl(-2.3, 0.33), hl(-2.3, 0.5), hl(0, 1.12), hl(2.06, 1.55)]), with: .color(light.at(knit, 0).c(0.6)))
        ball(SceneShapes.closed((0..<9).map { i -> CGPoint in
            let a = Double(i) / 9 * 2 * .pi, r: CGFloat = i % 2 == 0 ? 0.95 : 0.82
            return f(hl(-0.15, 3.3) + CGPoint(x: CGFloat(cos(a)) * r, y: CGFloat(sin(a)) * r))
        }), knit, lo: 0.02, hi: 1.1)
        // The scarf, wound twice round the neck up to the chin.
        let scarf = shape([hl(1.95, -1.45), hl(0.9, -1.75), hl(-0.6, -1.55), hl(-1.7, -1.15), CGPoint(x: 1.9, y: 28.9), CGPoint(x: 1.8, y: 27.7),
                           CGPoint(x: 2.5, y: 26.8), CGPoint(x: 3.7, y: 26.2), CGPoint(x: 4.9, y: 25.9), CGPoint(x: 5.7, y: 26.3), CGPoint(x: 5.75, y: 26.85)])
        paint(scarf, scarfRed, lo: 0, hi: 1.05)
        rim(scarf, scarfRed, 0.3, 1.2, 0.7)
        do {
            var folds = g
            folds.clip(to: scarf)
            folds.fill(shape([(2.0, 27.9), (3.8, 27.0), (5.75, 26.75), (3.8, 27.4)]), with: .color(light.at(scarfRed, 0).c(0.7)))
            folds.fill(shape([(2.1, 28.4), (3.8, 27.45), (5.7, 27.05), (3.8, 27.75)]), with: .color(light.at(scarfRed, 1.0).c(0.45)))
        }

        // The near arm at the focus knob: a quilted sleeve, a knit cuff, a glove.
        let shoulder = CGPoint(x: 2.2, y: 25.3), elbow = CGPoint(x: 5.3, y: 21.4), wrist = CGPoint(x: 9.0, y: 24.5)
        paint(limb(elbow, wrist, 1.2, 1.0), coat, lo: 0.02, hi: 1.05, axis: (elbow, wrist), r: 1.15)
        paint(limb(shoulder, elbow, 1.45, 1.2), coat, lo: 0.02, hi: 1.05, axis: (shoulder, elbow), r: 1.4)
        rim(limb(shoulder, elbow, 1.45, 1.2), coat, 0.35, 1.2, 0.7)
        tint(shape([elbow + CGPoint(x: 0.1, y: 1.0), elbow + CGPoint(x: 1.2, y: 1.25), elbow + CGPoint(x: 0.5, y: 0.3)]), coat, 0, 0.85)
        tint(shape([shoulder + CGPoint(x: 1.2, y: -2.1), shoulder + CGPoint(x: 2.3, y: -2.4), shoulder + CGPoint(x: 1.6, y: -2.6)]), coat, 0, 0.6)
        tint(shape([elbow + CGPoint(x: 1.6, y: 1.0), elbow + CGPoint(x: 2.6, y: 2.2), elbow + CGPoint(x: 2.0, y: 1.1)]), coat, 0, 0.6)
        paint(limb(wrist - (wrist - elbow).unit * 0.7, wrist, 1.02, 0.98), knit.mix(SceneRGB.black, 0.12), lo: 0, hi: 1, axis: (elbow, wrist), r: 1.0)
        let hand = knob + CGPoint(x: -0.25, y: -0.35)
        paint(limb(wrist + (hand - wrist).unit * 0.3, hand, 0.82, 0.72), glove, lo: 0, hi: 1.25, axis: (wrist, hand), r: 0.8)
        paint(limb(hand + CGPoint(x: -0.3, y: 0.3), hand + CGPoint(x: 0.2, y: 1.0), 0.3, 0.28), glove, lo: 0, hi: 1.3)

        // The lamp: a small red torch lying on the ground, glowing.
        let lampA = lens + CGPoint(x: -1.6, y: 0.05), lampB = lens + CGPoint(x: -0.2, y: 0)
        paint(limb(lampA, lampB, 0.42, 0.42), blackened, lo: 0, hi: 1.2, axis: (lampA, lampB), r: 0.42, warm: 0.6)
        paint(SceneShapes.band(f(lampB), f(lens + CGPoint(x: 0.08, y: 0)), 0.52 * u, 0.52 * u), alu, lo: 0, hi: 1, axis: (lampB, lens), r: 0.52, warm: 1)
        let ls = f(lens + CGPoint(x: 0.1, y: 0))
        g.fill(Path(ellipseIn: CGRect(x: ls.x - 5 * u, y: ls.y - 5 * u, width: 10 * u, height: 10 * u)),
               with: .radialGradient(SceneGradient(colors: [red.c(0.34), red.c(0.09), red.c(0)]), center: ls, startRadius: 0, endRadius: 5 * u))
        g.fill(Path(ellipseIn: CGRect(x: ls.x - 0.2 * u, y: ls.y - 0.48 * u, width: 0.4 * u, height: 0.96 * u)), with: .color(SceneRGB(r: 1, g: 0.5, b: 0.42).color))
    }
}
