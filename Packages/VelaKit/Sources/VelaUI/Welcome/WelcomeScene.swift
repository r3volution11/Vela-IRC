// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Savage
import SwiftUI
import VelaTheme

/// The welcome screen's picture: a river winding through a mountain valley.
/// Dark themes get night (a full moon, Vela's stars and a stargazer at a
/// telescope); light themes get day (the sun, clouds, birds and a kayaker
/// paddling upstream). The background is flat, with gradients for depth; the
/// figures are modelled and lit by the scene.
///
/// Its colors come from the theme: the chat background, text, secondary text
/// and accent. Drawing is deterministic (seeded), so a size and a theme
/// always give the same picture.
nonisolated struct WelcomeScene: Equatable {
    var bg, fg, secondary, accent: PaintColor
    /// Night, for a dark theme.
    var dark: Bool

    /// The scene's width over its height.
    static let aspectRatio: CGFloat = 600.0 / 380.0

    init(bg: PaintColor, fg: PaintColor, secondary: PaintColor, accent: PaintColor, dark: Bool) {
        self.bg = bg
        self.fg = fg
        self.secondary = secondary
        self.accent = accent
        self.dark = dark
    }

    /// The scene for `theme`, with the user's color customizations (they're
    /// part of the resolved theme). Translucent colors are composited over
    /// the chat background.
    init(theme: ResolvedTheme) {
        let dark = theme.kind == .dark
        let background = theme.color(ThemeKey.chatBackground).composited(over: dark ? .black : .white)
        func opaque(_ key: String) -> PaintColor { PaintColor(theme.color(key).composited(over: background)) }
        self.init(
            bg: PaintColor(background),
            fg: opaque(ThemeKey.chatForeground),
            secondary: opaque(ThemeKey.chatSecondaryForeground),
            accent: opaque(ThemeKey.accent),
            dark: dark
        )
    }

    /// Draws the scene filling `size`.
    func draw<Surface: Painter>(_ painter: inout Surface, size: CGSize) {
        WelcomeArt.drawScene(&painter, theme: self, size: size)
    }

    /// The scene as a standalone SVG document, `size` points.
    func svg(size: CGSize, title: String? = nil) -> String {
        let document = SVGDocument(size: size, title: title)
        document.draw { draw(&$0, size: size) }
        return document.svgString
    }
}

/// The welcome scene's drawing code.
nonisolated enum WelcomeArt {
    static func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
}

nonisolated extension WelcomeArt {
    // MARK: Palette

    /// The background's colors, all mixed from the theme's four: the sky,
    /// the mountains from far to near, the water, and the light (the moon
    /// or the sun).
    struct Palette {
        let night: Bool
        let skyTop, skyLow, far, farLow, mass, massLow, spur, spurLow, front, lit: PaintColor
        let waterFar, waterNear, waterEdge, light, glow, star, mare: PaintColor
        init(_ t: WelcomeScene) {
            night = t.dark
            if t.dark {
                let hue = t.bg.mix(with: t.accent, by: 0.20)
                skyTop = t.bg.mix(with: PaintColor.black, by: 0.30)
                skyLow = t.bg.mix(with: t.accent, by: 0.14).mix(with: t.fg, by: 0.06)
                far = hue.mix(with: t.fg, by: 0.24); farLow = skyLow.mix(with: hue, by: 0.3)
                mass = hue.mix(with: t.fg, by: 0.15); massLow = t.bg.mix(with: t.accent, by: 0.10)
                spur = t.bg.mix(with: t.fg, by: 0.07).mix(with: t.accent, by: 0.08); spurLow = t.bg.mix(with: PaintColor.black, by: 0.18)
                front = t.bg.mix(with: PaintColor.black, by: 0.46)
                light = PaintColor.white.mix(with: t.accent, by: 0.08)
                lit = light
                glow = PaintColor.white.mix(with: t.accent, by: 0.35)
                star = PaintColor.white.mix(with: t.accent, by: 0.14)
                mare = light.mix(with: t.secondary, by: 0.42).mix(with: t.bg, by: 0.08)
                waterFar = skyLow.mix(with: light, by: 0.25)
                waterNear = t.bg.mix(with: t.accent, by: 0.22).mix(with: PaintColor.black, by: 0.10)
                waterEdge = t.bg.mix(with: PaintColor.black, by: 0.25)
            } else {
                let land = t.secondary.mix(with: t.accent, by: 0.20)
                skyTop = t.bg.mix(with: t.accent, by: 0.12)
                skyLow = t.bg.mix(with: PaintColor.white, by: 0.6)
                far = t.bg.mix(with: land, by: 0.22); farLow = skyLow.mix(with: far, by: 0.4)
                mass = t.bg.mix(with: land, by: 0.40); massLow = t.bg.mix(with: land, by: 0.24)
                spur = t.bg.mix(with: land, by: 0.58); spurLow = t.bg.mix(with: land, by: 0.42)
                front = t.bg.mix(with: t.fg, by: 0.70)
                light = t.accent.mix(with: PaintColor.white, by: 0.30)
                lit = PaintColor.white
                glow = t.accent
                star = t.bg.mix(with: t.fg, by: 0.55)
                mare = light
                waterFar = skyLow.mix(with: t.accent, by: 0.20)
                waterNear = t.bg.mix(with: t.accent, by: 0.42).mix(with: t.fg, by: 0.10)
                waterEdge = t.bg.mix(with: t.fg, by: 0.35).mix(with: t.accent, by: 0.15)
            }
        }
    }

    // MARK: The scene

    static func drawScene<Surface: Painter>(_ ctx: inout Surface, theme: WelcomeScene, size: CGSize) {
        let W = size.width, H = size.height
        let p = Palette(theme)
        func s(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x * W, y: q.y * H) }
        let lightC = s(P(0.74, 0.24))
        let frame = CGRect(x: 0, y: 0, width: W, height: H)
        let full = Path(frame)
        ctx.clip(to: full)

        // Fade into the window: soft sides and bottom.
        let clear = PaintColor.black.opacity(0), solid = PaintColor.black.opacity(1)
        var scene = LayerStyle()
        scene.fades = [
            LayerStyle.Fade(rect: frame, paint: .linearGradient(PaintGradient(stops: [.init(color: clear, location: 0), .init(color: PaintColor.black.opacity(0.4), location: 0.05),
                                                                                     .init(color: solid, location: 0.16), .init(color: solid, location: 0.84),
                                                                                     .init(color: PaintColor.black.opacity(0.4), location: 0.95), .init(color: clear, location: 1)]),
                                                                startPoint: s(P(0, 0.5)), endPoint: s(P(1, 0.5)))),
            LayerStyle.Fade(rect: frame, paint: .linearGradient(PaintGradient(stops: [.init(color: clear, location: 0), .init(color: solid, location: 0.10),
                                                                                     .init(color: solid, location: 0.82), .init(color: clear, location: 1)]),
                                                                startPoint: s(P(0.5, 0)), endPoint: s(P(0.5, 1)))),
        ]
        ctx.drawLayer(scene) { g in
            // Sky.
            g.fill(full, with: .linearGradient(PaintGradient(colors: [p.skyTop, p.skyLow]), startPoint: s(P(0.5, 0)), endPoint: s(P(0.5, 0.62))))

            // Vela and the stars (night), clouds and birds (day).
            let xs = vela.map(\.x), ys = vela.map(\.y)
            let box = CGRect(x: 0.07 * W, y: 0.05 * H, width: 0.46 * W, height: 0.19 * H)
            let sc = min(box.width / (xs.max()! - xs.min()!), box.height / (ys.max()! - ys.min()!))
            func sp(_ x: Double, _ y: Double) -> CGPoint {
                let fw = (xs.max()! - xs.min()!) * sc
                return CGPoint(x: box.minX + (box.width - fw) / 2 + (xs.max()! - x) * sc, y: box.minY + (ys.max()! - y) * sc)
            }
            let velaPts = vela.map { sp($0.x, $0.y) }
            // Sizes and turns, picked at random once: very very large,
            // very large, large.
            var pick = SceneRandom(state: 0x5EE5)
            let classes: [CGFloat] = [2.7, 2.0, 1.5]
            let velaSize: [CGFloat] = velaPts.indices.map { _ in classes[Int(pick.range(0, 2.999))] * W / 300 }
            let velaTurn: [Double] = velaPts.indices.map { _ in pick.range(0, .pi / 2) }
            if p.night {
                var rng = SceneRandom(state: 0xA11CE)
                var placed = 0
                var stars: [(CGPoint, CGFloat, Double, Double)] = []   // point, radius, brightness, tint
                while placed < 140 {
                    let q = CGPoint(x: CGFloat(rng.unit()) * W, y: CGFloat(pow(rng.unit(), 1.3)) * 0.56 * H)
                    if hypot(q.x - lightC.x, q.y - lightC.y) < W * 0.12 { continue }
                    if velaPts.indices.contains(where: { hypot(velaPts[$0].x - q.x, velaPts[$0].y - q.y) < velaSize[$0] * 7 }) { continue }
                    placed += 1
                    // Most are faint; few are bright (as magnitudes go).
                    let bright = pow(rng.unit(), 2.4)
                    stars.append((q, CGFloat(0.35 + bright * 0.9) * W / 300, 0.35 + bright * 0.6, rng.range(-1, 1)))
                }
                g.group("stars") { g in
                    let warm = PaintColor(red: 1, green: 0.86, blue: 0.70), cool = PaintColor(red: 0.78, green: 0.86, blue: 1)
                    for (q, r, b, tint) in stars {
                        let color = p.star.mix(with: tint > 0 ? warm : cool, by: abs(tint) * 0.35)
                        if b > 0.7 {
                            drawStar(&g, q, core: r, color: color, glow: 4.5, spikes: b > 0.88 ? 4.5 : 0, angle: 0.12, opacity: b)
                        } else {
                            g.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(b)))
                        }
                    }
                    for (i, q) in velaPts.enumerated() {
                        let r = velaSize[i]
                        let biggest = r > 2.5 * W / 300
                        drawStar(&g, q, core: r, color: p.star, glow: 5.5, spikes: biggest ? 5.5 : (r > 1.8 * W / 300 ? 3.8 : 0), angle: 0.12 + velaTurn[i] * 0.12)
                    }
                }
                g.group("moon") { g in drawMoon(&g, lightC, 0.068 * W, p) }
            } else {
                func cloud(_ g: inout Surface, _ x: CGFloat, _ y: CGFloat, _ k: CGFloat) {
                    var body = Path()
                    for (dx, dy, r) in [(-0.9, 0.12, 0.42), (-0.35, -0.14, 0.62), (0.32, -0.04, 0.52), (0.88, 0.14, 0.38)] as [(CGFloat, CGFloat, CGFloat)] {
                        body.addEllipse(in: CGRect(x: (x + dx * k) * W - r * k * W, y: y * H + dy * k * W - r * k * W, width: r * k * W * 2, height: r * k * W * 2))
                    }
                    body.addRoundedRect(in: CGRect(x: (x - 1.25 * k) * W, y: y * H, width: 2.5 * k * W, height: 0.5 * k * W), cornerSize: CGSize(width: 0.25 * k * W, height: 0.25 * k * W))
                    g.fill(body, with: .linearGradient(PaintGradient(colors: [PaintColor.white.opacity(0.95), p.far.mix(with: PaintColor.white, by: 0.3).opacity(0.95)]),
                                                      startPoint: CGPoint(x: x * W, y: y * H - k * W * 0.7), endPoint: CGPoint(x: x * W, y: y * H + k * W * 0.5)))
                    // A flat shaded underside instead of an outline.
                    var under = g
                    under.clip(to: body)
                    under.fill(Path(CGRect(x: (x - 1.4 * k) * W, y: y * H + 0.18 * k * W, width: 2.8 * k * W, height: k * W)), with: .color(p.far.mix(with: PaintColor.white, by: 0.15).opacity(0.9)))
                }
                g.group("clouds") { g in
                    cloud(&g, 0.22, 0.18, 0.05); cloud(&g, 0.48, 0.10, 0.035); cloud(&g, 0.10, 0.34, 0.03)
                }
                var birds = Path()
                for (x, y, k) in [(0.40, 0.24, 1.0), (0.45, 0.28, 0.8), (0.36, 0.29, 0.7)] as [(CGFloat, CGFloat, CGFloat)] {
                    let c = s(P(x, y)), w = 4.5 * k * W / 300
                    birds.move(to: CGPoint(x: c.x - w, y: c.y - w * 0.35)); birds.addQuadCurve(to: c, control: CGPoint(x: c.x - w * 0.4, y: c.y - w * 0.55))
                    birds.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y - w * 0.35), control: CGPoint(x: c.x + w * 0.4, y: c.y - w * 0.55))
                }
                g.group("birds") { g in g.stroke(birds, with: .color(p.star), style: StrokeStyle(lineWidth: 1.1 * W / 300, lineCap: .round)) }
                g.group("sun") { g in drawSun(&g, lightC, 0.058 * W, p) }
            }

            // The far range across the valley's end.
            let farTop = SceneShapes.roughen([P(0, 0.56), P(0.10, 0.50), P(0.20, 0.54), P(0.30, 0.47), P(0.40, 0.53), P(0.50, 0.49), P(0.60, 0.545),
                                  P(0.68, 0.565), P(0.74, 0.535), P(0.82, 0.50), P(0.90, 0.47), P(1, 0.53)], levels: 3, rough: 0.35, seed: 3)
            let farPath = SceneShapes.mass(farTop, W: W, H: H, bottom: 0.80)
            g.fill(farPath, with: .linearGradient(PaintGradient(colors: [p.far, p.farLow]), startPoint: s(P(0.5, 0.47)), endPoint: s(P(0.5, 0.64))))

            // The valley's walls: big masses either side, then nearer spurs
            // that cross in front of the river.
            func mountain(_ pts: [CGPoint], seed: UInt64, top: PaintColor, low: PaintColor, from: CGFloat, to: CGFloat, litFaces: Bool) -> [CGPoint] {
                let line = SceneShapes.roughen(pts, levels: 4, rough: 0.30, seed: seed)
                let path = SceneShapes.mass(line, W: W, H: H)
                g.fill(path, with: .linearGradient(PaintGradient(colors: [top, low]), startPoint: s(P(0.5, from)), endPoint: s(P(0.5, to))))
                if litFaces {
                    // Faces turned toward the light (on the right): lighter wedges.
                    for i in 1..<pts.count - 1 where pts[i].y < pts[i - 1].y && pts[i].y < pts[i + 1].y {
                        let peak = pts[i], valley = pts[i + 1]
                        var face = Path()
                        face.move(to: s(peak))
                        face.addLine(to: s(valley))
                        face.addLine(to: s(P(peak.x + (valley.x - peak.x) * 0.15, valley.y + 0.04)))
                        face.closeSubpath()
                        var clipped = g
                        clipped.clip(to: path)
                        clipped.fill(face, with: .linearGradient(PaintGradient(colors: [p.lit.opacity(p.night ? 0.16 : 0.30), p.lit.opacity(0)]),
                                                                 startPoint: s(peak), endPoint: s(P(peak.x, valley.y + 0.04))))
                    }
                }
                return line
            }
            // Left and right masses.
            _ = mountain([P(-0.02, 0.42), P(0.08, 0.36), P(0.17, 0.31), P(0.26, 0.39), P(0.33, 0.37), P(0.42, 0.47), P(0.52, 0.55), P(0.61, 0.62), P(0.665, 0.665), P(0.70, 0.75)],
                         seed: 11, top: p.mass, low: p.massLow, from: 0.25, to: 0.75, litFaces: true)
            _ = mountain([P(0.73, 0.70), P(0.735, 0.63), P(0.78, 0.56), P(0.83, 0.46), P(0.89, 0.37), P(0.95, 0.31), P(1.02, 0.36)],
                         seed: 12, top: p.mass, low: p.massLow, from: 0.27, to: 0.72, litFaces: true)
            // Mist at the valley floor between the masses and the spurs.
            g.fill(Path(CGRect(x: 0, y: 0.56 * H, width: W, height: 0.22 * H)),
                   with: .linearGradient(PaintGradient(colors: [p.skyLow.opacity(0), p.skyLow.opacity(p.night ? 0.30 : 0.45), p.skyLow.opacity(0)]),
                                         startPoint: s(P(0.5, 0.56)), endPoint: s(P(0.5, 0.78))))
            // The river, a ribbon winding toward you: drawn whole, then the
            // mountains in front hide parts of it.
            let center = SceneShapes.spline([P(0.705, 0.575), P(0.68, 0.62), P(0.70, 0.675), P(0.645, 0.73), P(0.55, 0.775), P(0.47, 0.85), P(0.41, 1.06)], per: 20)
            func width(_ t: CGFloat) -> CGFloat { 0.006 + pow(t, 1.8) * 0.42 }
            func ribbon(_ scale: CGFloat) -> Path {
                var left: [CGPoint] = [], right: [CGPoint] = []
                for i in center.indices {
                    let a = center[max(0, i - 1)], b = center[min(center.count - 1, i + 1)]
                    let dx = (b.x - a.x) * W, dy = (b.y - a.y) * H
                    let len = max(0.0001, hypot(dx, dy))
                    let nx = -dy / len, ny = dx / len
                    let t = CGFloat(i) / CGFloat(center.count - 1)
                    let w = width(t) * W * 0.5 * scale
                    let c = s(center[i])
                    left.append(CGPoint(x: c.x + nx * w, y: c.y + ny * w * 0.55))
                    right.append(CGPoint(x: c.x - nx * w, y: c.y - ny * w * 0.55))
                }
                var path = Path()
                path.move(to: left[0]); for q in left.dropFirst() { path.addLine(to: q) }
                for q in right.reversed() { path.addLine(to: q) }
                path.closeSubpath()
                return path
            }
            // The valley floor the river runs across.
            var floor = Path()
            floor.move(to: s(P(-0.02, 0.76)))
            floor.addCurve(to: s(P(1.02, 0.74)), control1: s(P(0.35, 0.72)), control2: s(P(0.70, 0.70)))
            floor.addLine(to: s(P(1.02, 1.05))); floor.addLine(to: s(P(-0.02, 1.05))); floor.closeSubpath()
            g.fill(floor, with: .linearGradient(PaintGradient(colors: [p.spurLow.mix(with: p.massLow, by: 0.5), p.front.mix(with: p.spurLow, by: 0.5)]),
                                                startPoint: s(P(0.5, 0.70)), endPoint: s(P(0.5, 1.0))))
            let river = ribbon(1)
            // Banks darker, the middle catching the sky.
            g.fill(river, with: .linearGradient(PaintGradient(colors: [p.waterFar, p.waterNear]), startPoint: s(P(0.7, 0.58)), endPoint: s(P(0.4, 1.0))))
            do {
                var w = g
                w.clip(to: river)
                w.stroke(river, with: .color(p.waterEdge.opacity(0.55)), lineWidth: 3.2 * W / 300)
                w.fill(ribbon(0.5), with: .linearGradient(PaintGradient(colors: [p.waterFar.mix(with: p.lit, by: 0.25).opacity(0.9), p.waterNear.mix(with: p.lit, by: 0.12).opacity(0.6)]),
                                                          startPoint: s(P(0.7, 0.58)), endPoint: s(P(0.4, 1.0))))
                // The light's reflection: a broken column under it.
                var rng = SceneRandom(state: 77)
                var column = Path()
                var y = 0.58 * H
                while y < H {
                    let t = (y / H - 0.58) / 0.42
                    let half = (0.010 + t * 0.040) * W * CGFloat(rng.range(0.55, 1.15))
                    let hgt = (0.006 + t * 0.020) * H
                    let x = lightC.x + CGFloat(rng.range(-0.006, 0.006)) * W
                    column.addEllipse(in: CGRect(x: x - half, y: y, width: half * 2, height: hgt))
                    y += hgt * CGFloat(rng.range(1.35, 1.9))
                }
                w.fill(column, with: .linearGradient(PaintGradient(colors: [p.light.opacity(0.85), p.light.opacity(0.10)]), startPoint: s(P(0.7, 0.58)), endPoint: s(P(0.7, 1.0))))
                // Ripples: soft lens shapes a shade lighter and darker.
                var light = Path(), dark = Path()
                for _ in 0..<26 {
                    let t = CGFloat(rng.range(0.1, 1))
                    let yy = (0.60 + t * 0.40) * H
                    let xx = CGFloat(rng.range(0.25, 0.75)) * W
                    // Short and full, so they read as patches of moving
                    // water rather than lines.
                    let len = (0.008 + t * 0.026) * W
                    let lift = (1.6 + t * 4.2) * W / 600
                    let lens = Path { q in
                        q.move(to: CGPoint(x: xx - len, y: yy))
                        q.addQuadCurve(to: CGPoint(x: xx + len, y: yy), control: CGPoint(x: xx, y: yy - lift))
                        q.addQuadCurve(to: CGPoint(x: xx - len, y: yy), control: CGPoint(x: xx, y: yy + lift * 0.5))
                    }
                    if rng.unit() < 0.5 { light.addPath(lens) } else { dark.addPath(lens) }
                }
                // Tinted like the water, never white.
                w.fill(light, with: .color(p.waterFar.mix(with: p.lit, by: 0.25).opacity(p.night ? 0.20 : 0.28)))
                w.fill(dark, with: .color(p.waterEdge.opacity(0.18)))
            }

            // Spurs: wedges reaching over the river's middle reach, so it
            // winds behind them and comes out wide in front.
            func spur(_ top: [CGPoint], under: [CGPoint], seed: UInt64) -> [CGPoint] {
                let line = SceneShapes.roughen(top, levels: 4, rough: 0.28, seed: seed)
                var path = Path()
                for (i, q) in line.enumerated() { if i == 0 { path.move(to: s(q)) } else { path.addLine(to: s(q)) } }
                for q in SceneShapes.spline(under, per: 6) { path.addLine(to: s(q)) }
                path.closeSubpath()
                g.fill(path, with: .linearGradient(PaintGradient(colors: [p.spur, p.spurLow]), startPoint: s(P(0.5, 0.57)), endPoint: s(P(0.5, 0.86))))
                return line
            }
            let rightSpur = spur([P(1.02, 0.58), P(0.95, 0.575), P(0.88, 0.60), P(0.80, 0.65), P(0.72, 0.695), P(0.655, 0.735)],
                                 under: [P(0.655, 0.735), P(0.70, 0.765), P(0.80, 0.79), P(0.92, 0.80), P(1.02, 0.80)], seed: 21)
            let leftSpur = spur([P(-0.02, 0.60), P(0.08, 0.58), P(0.18, 0.61), P(0.30, 0.66), P(0.42, 0.71), P(0.535, 0.765)],
                                under: [P(0.535, 0.765), P(0.47, 0.80), P(0.34, 0.825), P(0.16, 0.835), P(-0.02, 0.84)], seed: 22)

            // Trees along the spurs' ridges.
            var rng = SceneRandom(state: 909)
            var trees = Path()
            for line in [rightSpur, leftSpur] {
                for q in line where q.y > 0.56 && q.y < 0.86 && rng.unit() < 0.30 {
                    let h = (0.035 + (q.y - 0.56) * 0.07) * H * CGFloat(rng.range(0.8, 1.2))
                    trees.addPath(SceneShapes.tree(CGPoint(x: q.x * W + CGFloat(rng.range(-2, 2)), y: q.y * H + h * 0.25), h))
                }
            }
            g.fill(trees, with: .color(p.spurLow.mix(with: p.night ? PaintColor.black : theme.fg, by: p.night ? 0.30 : 0.25)))

            // Near banks: dark, with tall trees and grass, framing the view.
            let leftBank = SceneShapes.roughen([P(-0.02, 0.84), P(0.08, 0.86), P(0.16, 0.92), P(0.22, 1.05)], levels: 3, rough: 0.2, seed: 31)
            let rightBank = SceneShapes.roughen([P(0.64, 1.05), P(0.72, 0.92), P(0.84, 0.86), P(1.02, 0.83)], levels: 3, rough: 0.2, seed: 32)
            for bank in [leftBank, rightBank] {
                var path = Path()
                path.move(to: s(P(bank[0].x, 1.05)))
                for q in bank { path.addLine(to: s(q)) }
                path.addLine(to: s(P(bank.last!.x, 1.05))); path.closeSubpath()
                g.fill(path, with: .linearGradient(PaintGradient(colors: [p.front.mix(with: p.spurLow, by: 0.4), p.front]), startPoint: s(P(0.5, 0.83)), endPoint: s(P(0.5, 1))))
            }
            // Night: a stargazer on a knoll at the lower left, at a
            // telescope aimed at the moon.
            if p.night {
                g.group("stargazer") { g in
                    let k0 = s(P(0.10, 0.92)), k1 = s(P(0.16, 0.80)), k2 = s(P(0.29, 0.79)), k3 = s(P(0.36, 0.90))
                    var knoll = Path()
                    knoll.move(to: k0)
                    knoll.addCurve(to: k3, control1: k1, control2: k2)
                    knoll.addLine(to: s(P(0.36, 1.05))); knoll.addLine(to: s(P(0.10, 1.05))); knoll.closeSubpath()
                    g.fill(knoll, with: .linearGradient(PaintGradient(colors: [p.front.mix(with: p.spurLow, by: 0.30), p.front]),
                                                        startPoint: s(P(0.5, 0.80)), endPoint: s(P(0.5, 0.95))))
                    /// The knoll's top (screen y) at screen x, for feet and tripod legs.
                    func knollTop(_ x: CGFloat) -> CGFloat {
                        func bez(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                            let m = 1 - t
                            return m * m * m * a + 3 * m * m * t * b + 3 * m * t * t * c + t * t * t * d
                        }
                        var lo: CGFloat = 0, hi: CGFloat = 1
                        for _ in 0..<24 { let t = (lo + hi) / 2; if bez(t, k0.x, k1.x, k2.x, k3.x) < x { lo = t } else { hi = t } }
                        return bez(lo, k0.y, k1.y, k2.y, k3.y)
                    }
                    drawStargazer(&g, theme: theme, p: p, foot: s(P(0.215, 0.826)), u: H * 0.0027, moon: lightC, ground: knollTop)
                }
            }

            if !p.night {
                // Along the river's near reach, heading upstream.
                let from = s(P(0.47, 0.85)), to = s(P(0.55, 0.775))
                g.group("kayaker") { g in drawKayaker(&g, theme: theme, p: p, at: s(P(0.505, 0.818)), heading: to - from, k: W / 300, sun: lightC) }
            }

            var big = Path()
            for (x, y, h) in [(0.04, 0.88, 0.22), (0.09, 0.90, 0.16), (0.90, 0.88, 0.20), (0.96, 0.87, 0.25), (0.84, 0.90, 0.13)] as [(CGFloat, CGFloat, CGFloat)] {
                big.addPath(SceneShapes.tree(s(P(x, y)), h * H))
            }
            var grass = Path()
            for bank in [leftBank, rightBank] {
                for q in bank where rng.unit() < 0.7 {
                    let base = s(q)
                    let h = CGFloat(rng.range(4, 9)) * W / 300
                    let lean = CGFloat(rng.range(-2.5, 2.5)) * W / 300
                    grass.move(to: CGPoint(x: base.x - 1, y: base.y + 1))
                    grass.addQuadCurve(to: CGPoint(x: base.x + lean, y: base.y - h), control: CGPoint(x: base.x - 0.4, y: base.y - h * 0.5))
                    grass.addQuadCurve(to: CGPoint(x: base.x + 1, y: base.y + 1), control: CGPoint(x: base.x + 0.4, y: base.y - h * 0.5))
                }
            }
            g.fill(big, with: .color(p.front))
            g.fill(grass, with: .color(p.front))
        }
    }
}
