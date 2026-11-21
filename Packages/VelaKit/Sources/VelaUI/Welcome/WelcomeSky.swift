// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Savage
import SwiftUI

nonisolated extension WelcomeArt {
    // MARK: The moon

    static func drawMoon<Surface: Painter>(_ g: inout Surface, _ c: CGPoint, _ r: CGFloat, _ p: Palette) {
        // Glow: two soft halos.
        g.fill(Path(ellipseIn: CGRect(x: c.x - r * 3.2, y: c.y - r * 3.2, width: r * 6.4, height: r * 6.4)),
               with: .radialGradient(PaintGradient(colors: [p.glow.opacity(0.16), p.glow.opacity(0.05), p.glow.opacity(0)]), center: c, startRadius: r, endRadius: r * 3.2))
        let disk = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        // The disk, a touch warmer in the middle.
        g.fill(disk, with: .radialGradient(PaintGradient(colors: [PaintColor.white.opacity(1), p.light.opacity(1)]), center: CGPoint(x: c.x + r * 0.15, y: c.y - r * 0.1), startRadius: 0, endRadius: r))
        var inside = g
        inside.clip(to: disk)
        // The seas, softened at the edges.
        inside.drawLayer(LayerStyle(blur: r * 0.035)) { m in
            func sea(_ pts: [(CGFloat, CGFloat)], _ o: Double) {
                let poly = SceneShapes.roughen(pts.map { P($0.0, $0.1) } + [P(pts[0].0, pts[0].1)], levels: 3, rough: 0.22, seed: UInt64(pts.count * 31 + Int(o * 100)))
                var path = Path()
                for (i, q) in SceneShapes.spline(poly, per: 3).enumerated() {
                    let s = CGPoint(x: c.x + q.x * r, y: c.y + q.y * r)
                    if i == 0 { path.move(to: s) } else { path.addLine(to: s) }
                }
                path.closeSubpath()
                m.fill(path, with: .color(p.mare.opacity(o)))
            }
            // Oceanus Procellarum.
            sea([(-0.86, -0.28), (-0.62, -0.38), (-0.48, -0.08), (-0.42, 0.24), (-0.52, 0.48), (-0.74, 0.40), (-0.88, 0.10)], 0.62)
            // Imbrium.
            sea([(-0.52, -0.48), (-0.30, -0.66), (-0.06, -0.58), (-0.02, -0.36), (-0.24, -0.22), (-0.48, -0.26)], 0.70)
            // Serenitatis.
            sea([(0.04, -0.46), (0.22, -0.50), (0.30, -0.32), (0.18, -0.20), (0.02, -0.26)], 0.66)
            // Tranquillitatis.
            sea([(0.18, -0.16), (0.40, -0.18), (0.50, 0.02), (0.38, 0.14), (0.20, 0.08)], 0.62)
            // Crisium.
            sea([(0.62, -0.32), (0.76, -0.30), (0.80, -0.16), (0.66, -0.10), (0.58, -0.20)], 0.72)
            // Fecunditatis and Nectaris.
            sea([(0.46, 0.16), (0.62, 0.18), (0.64, 0.42), (0.48, 0.46), (0.40, 0.30)], 0.48)
            // Nubium and Cognitum.
            sea([(-0.42, 0.20), (-0.14, 0.22), (-0.10, 0.42), (-0.30, 0.50), (-0.46, 0.38)], 0.50)
            // Vaporum and Insularum, small.
            sea([(-0.12, -0.18), (0.02, -0.18), (0.04, -0.06), (-0.10, -0.04)], 0.44)
        }
        // Highland texture: many tiny craters.
        var rng = SceneRandom(state: 4242)
        var pits = Path()
        for _ in 0..<70 {
            let a = rng.range(0, 6.283), d = sqrt(rng.unit()) * 0.92
            let q = CGPoint(x: c.x + CGFloat(cos(a) * d) * r, y: c.y + CGFloat(sin(a) * d) * r)
            let s = CGFloat(rng.range(0.008, 0.025)) * r
            pits.addEllipse(in: CGRect(x: q.x - s, y: q.y - s, width: s * 2, height: s * 2))
        }
        inside.fill(pits, with: .color(p.mare.opacity(0.35)))
        // Tycho and Copernicus, with faint rays.
        for (x, y, size, rays) in [(-0.12, 0.70, 0.045, 14), (-0.36, -0.06, 0.035, 9)] as [(CGFloat, CGFloat, CGFloat, Int)] {
            let q = CGPoint(x: c.x + x * r, y: c.y + y * r)
            var rays_ = Path()
            var rr = SceneRandom(state: UInt64(rays * 97))
            for k in 0..<rays {
                let a = Double(k) / Double(rays) * 6.283 + rr.range(-0.2, 0.2)
                let len = CGFloat(rr.range(0.25, 0.7)) * r
                rays_.move(to: q); rays_.addLine(to: CGPoint(x: q.x + CGFloat(cos(a)) * len, y: q.y + CGFloat(sin(a)) * len))
            }
            inside.stroke(rays_, with: .color(PaintColor.white.opacity(0.30)), lineWidth: max(0.5, r * 0.012))
            inside.fill(Path(ellipseIn: CGRect(x: q.x - size * r, y: q.y - size * r, width: size * 2 * r, height: size * 2 * r)), with: .color(PaintColor.white))
            inside.fill(Path(ellipseIn: CGRect(x: q.x - size * r * 0.45, y: q.y - size * r * 0.45, width: size * r * 0.9, height: size * r * 0.9)), with: .color(p.mare.opacity(0.5)))
        }
        // Limb: a touch darker toward the edge.
        inside.fill(disk, with: .radialGradient(PaintGradient(colors: [p.mare.opacity(0), p.mare.opacity(0.30)]), center: c, startRadius: r * 0.7, endRadius: r))
    }

    static func drawSun<Surface: Painter>(_ g: inout Surface, _ c: CGPoint, _ r: CGFloat, _ p: Palette) {
        g.fill(Path(ellipseIn: CGRect(x: c.x - r * 3.4, y: c.y - r * 3.4, width: r * 6.8, height: r * 6.8)),
               with: .radialGradient(PaintGradient(colors: [p.glow.opacity(0.22), p.glow.opacity(0.06), p.glow.opacity(0)]), center: c, startRadius: r, endRadius: r * 3.4))
        for (scale, o) in [(1.75, 0.10), (1.35, 0.14)] as [(CGFloat, Double)] {
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * scale, y: c.y - r * scale, width: r * scale * 2, height: r * scale * 2)), with: .color(p.glow.opacity(o)))
        }
        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
               with: .radialGradient(PaintGradient(colors: [PaintColor.white.mix(with: p.light, by: 0.3), p.light]), center: c, startRadius: 0, endRadius: r))
    }

    // MARK: Stars

    /// Vela's eight brightest stars: right ascension offset and declination,
    /// in degrees.
    static let vela: [(name: String, x: Double, y: Double)] = [
        ("γ", 11.24, -47.33), ("δ", 5.46, -54.72), ("λ", 1.64, -43.43), ("κ", -0.67, -55.01),
        ("ψ", -2.09, -40.47), ("φ", -6.38, -54.57), ("q", -9.30, -42.12), ("μ", -14.57, -49.42),
    ]

    /// A star as it looks: a round bright core, a soft glow around it and, for
    /// the brightest, faint short spikes that fade toward their tips.
    static func drawStar<Surface: Painter>(_ g: inout Surface, _ c: CGPoint, core r: CGFloat, color: PaintColor, glow: CGFloat, spikes: CGFloat, angle: Double, opacity: Double = 1) {
        if glow > 0 {
            let gr = r * glow
            g.fill(Path(ellipseIn: CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2)),
                   with: .radialGradient(PaintGradient(colors: [color.opacity(0.40 * opacity), color.opacity(0.10 * opacity), color.opacity(0)]), center: c, startRadius: r * 0.5, endRadius: gr))
        }
        if spikes > 0 {
            let len = r * spikes
            for k in 0..<2 {
                let a = angle + Double(k) * .pi / 2
                let dx = CGFloat(cos(a)) * len, dy = CGFloat(sin(a)) * len
                var line = Path()
                line.move(to: CGPoint(x: c.x - dx, y: c.y - dy)); line.addLine(to: CGPoint(x: c.x + dx, y: c.y + dy))
                g.stroke(line, with: .linearGradient(PaintGradient(stops: [.init(color: color.opacity(0), location: 0), .init(color: color.opacity(0.55 * opacity), location: 0.5),
                                                                      .init(color: color.opacity(0), location: 1)]),
                                                     startPoint: CGPoint(x: c.x - dx, y: c.y - dy), endPoint: CGPoint(x: c.x + dx, y: c.y + dy)),
                         style: StrokeStyle(lineWidth: max(0.4, r * 0.32), lineCap: .round))
            }
        }
        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
               with: .radialGradient(PaintGradient(colors: [PaintColor.white.opacity(opacity), color.opacity(opacity)]), center: c, startRadius: 0, endRadius: r))
    }
}
