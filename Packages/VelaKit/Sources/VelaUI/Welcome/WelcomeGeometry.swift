// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore

// Shapes and small math for the welcome scene.

/// The seeded generator (SplitMix64): the scene's random stars, rocks and
/// ripples come out the same every time.
typealias SceneRandom = ScrollBenchmarkContent.Random

nonisolated extension ScrollBenchmarkContent.Random {
    init(state: UInt64) {
        self.init(seed: state)
    }

    /// A value in 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    /// A value in a..<b.
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
}

nonisolated extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    var unit: CGPoint { self * (1 / max(0.0001, hypot(x, y))) }
    /// A quarter turn.
    var turned: CGPoint { CGPoint(x: -y, y: x) }
}

/// A point or direction in the kayaker's small 3D model.
nonisolated struct SceneVector {
    var x, y, z: CGFloat
    init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) { self.x = x; self.y = y; self.z = z }
    static func + (a: SceneVector, b: SceneVector) -> SceneVector { SceneVector(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: SceneVector, b: SceneVector) -> SceneVector { SceneVector(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: SceneVector, s: CGFloat) -> SceneVector { SceneVector(a.x * s, a.y * s, a.z * s) }
    func dot(_ b: SceneVector) -> CGFloat { x * b.x + y * b.y + z * b.z }
    func cross(_ b: SceneVector) -> SceneVector { SceneVector(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var unit: SceneVector { self * (1 / max(0.0001, sqrt(dot(self)))) }
}

nonisolated enum SceneShapes {
    /// Midpoint displacement: a rougher line through `points`, the same each time.
    static func roughen(_ points: [CGPoint], levels: Int, rough: CGFloat, seed: UInt64) -> [CGPoint] {
        var rng = SceneRandom(state: seed)
        var p = points
        for level in 0..<levels {
            var out = [p[0]]
            out.reserveCapacity(p.count * 2)
            for i in 0..<p.count - 1 {
                let a = p[i], b = p[i + 1]
                let len = hypot(b.x - a.x, b.y - a.y)
                let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + CGFloat(rng.range(-1, 1)) * rough * len / CGFloat(level + 1))
                out.append(m)
                out.append(b)
            }
            p = out
        }
        return p
    }

    /// Catmull-Rom through points, `per` samples between each pair.
    static func spline(_ pts: [CGPoint], per: Int = 16) -> [CGPoint] {
        var out: [CGPoint] = []
        out.reserveCapacity((pts.count - 1) * per + 1)
        for i in 0..<pts.count - 1 {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            for s in 0..<per {
                let t = CGFloat(s) / CGFloat(per), t2 = t * t, t3 = t2 * t
                func f(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                out.append(CGPoint(x: f(p0.x, p1.x, p2.x, p3.x), y: f(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        out.append(pts.last!)
        return out
    }

    /// A filled shape from a top line down to the bottom of the frame.
    static func mass(_ top: [CGPoint], W: CGFloat, H: CGFloat, bottom: CGFloat = 1.05) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: top[0].x * W, y: bottom * H))
        for q in top { p.addLine(to: CGPoint(x: q.x * W, y: q.y * H)) }
        p.addLine(to: CGPoint(x: top.last!.x * W, y: bottom * H))
        p.closeSubpath()
        return p
    }

    /// A fir: four stacked triangles on a short trunk.
    static func tree(_ base: CGPoint, _ h: CGFloat) -> Path {
        var p = Path()
        let w = h * 0.36
        for (i, scale) in [1.0, 0.80, 0.58, 0.36].enumerated() {
            let bottom = base.y - h * CGFloat(0.06 + 0.21 * Double(i))
            let top = bottom - h * 0.36
            p.move(to: CGPoint(x: base.x, y: top))
            p.addLine(to: CGPoint(x: base.x + w * scale, y: bottom))
            p.addLine(to: CGPoint(x: base.x - w * scale, y: bottom))
            p.closeSubpath()
        }
        p.addRect(CGRect(x: base.x - h * 0.03, y: base.y - h * 0.08, width: h * 0.06, height: h * 0.08))
        return p
    }

    /// A closed shape through `q`: smooth (Catmull-Rom) or straight.
    static func closed(_ q: [CGPoint], smooth: Bool = true) -> Path {
        var path = Path()
        guard q.count > 2 else { return path }
        let n = q.count
        path.move(to: q[0])
        for i in 0..<n {
            let p1 = q[i], p2 = q[(i + 1) % n]
            if smooth {
                let p0 = q[(i + n - 1) % n], p3 = q[(i + 2) % n]
                path.addCurve(to: p2, control1: p1 + (p2 - p0) * (1.0 / 6), control2: p2 - (p3 - p1) * (1.0 / 6))
            } else {
                path.addLine(to: p2)
            }
        }
        path.closeSubpath()
        return path
    }

    /// A limb or a rod: round ends, radius `ra` at `a` to `rb` at `b`.
    static func capsule(_ a: CGPoint, _ b: CGPoint, _ ra: CGFloat, _ rb: CGFloat) -> Path {
        let t = (b - a).unit, n = t.turned
        var q: [CGPoint] = []
        q.reserveCapacity(14)
        for i in 0...6 { let th = Double(i) / 6 * .pi; q.append(b + n * (rb * CGFloat(cos(th))) + t * (rb * CGFloat(sin(th)))) }
        for i in 0...6 { let th = Double(i) / 6 * .pi; q.append(a - n * (ra * CGFloat(cos(th))) - t * (ra * CGFloat(sin(th)))) }
        return closed(q, smooth: false)
    }

    /// A tube section with square ends: half-width `ra` at `a`, `rb` at `b`.
    static func band(_ a: CGPoint, _ b: CGPoint, _ ra: CGFloat, _ rb: CGFloat) -> Path {
        let n = (b - a).unit.turned
        return closed([a + n * ra, b + n * rb, b - n * rb, a - n * ra], smooth: false)
    }
}
