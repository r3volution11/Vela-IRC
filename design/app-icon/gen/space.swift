// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Vela "Horizon Sail" — background layer generator.
// Renders the planet limb, atmospheric rim, rising sun, the light ray through
// the V's notch and a sparse star field into a 1024x1024 Display-P3 PNG with
// alpha (the document fill shows through empty space).
//   swift gen/space.swift <out.png> [default|dark] [gen/derived.json]
// derived.json is written by gen/sails.py from params.json, so the sun and
// ray always sit under the V's point and inside its notch.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "space.png"
let variant = args.count > 2 ? args[2] : "default"
let dark = variant == "dark"
let derivedPath = args.count > 3 ? args[3] : "gen/derived.json"
let derived = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: derivedPath))) as! [String: Any]
func num(_ k: String) -> Double { (derived[k] as! NSNumber).doubleValue }
func pair(_ k: String) -> (Double, Double) { let a = derived[k] as! [NSNumber]; return (a[0].doubleValue, a[1].doubleValue) }

let N = 1024
// ---- Geometry (canvas points, y grows downward) ----
let cx = 512.0
let limbTop = num("limbTop")  // y of the horizon at the centre line
let R = num("planetRadius")   // planet radius
let cy = limbTop + R          // planet centre (far below the canvas)
let sunX = pair("point").0
let sun = (x: sunX, y: cy - sqrt(R * R - (sunX - cx) * (sunX - cx)) + 10.0)  // just below the limb, peeking
let sunAng = atan2(sun.x - cx, cy - sun.y)
let notch = pair("notch")
let rayDir = pair("rayDir")   // unit vector pointing up the notch

// ---- Palette (Display P3, 0..1) ----
typealias C3 = (Double, Double, Double)
let rimCore: C3  = (0.86, 1.00, 1.00)   // near-white aqua line
let rimCyan: C3  = (0.22, 0.86, 1.00)   // cyan glow
let haze: C3     = (0.04, 0.50, 0.66)   // teal haze
let hazeBlue: C3 = (0.05, 0.18, 0.56)   // outer blue scattering layer
let bodyDeep: C3 = dark ? (0.004, 0.014, 0.026) : (0.008, 0.026, 0.046)
let bodyLimb: C3 = (0.02, 0.30, 0.38)   // lit teal surface near the limb
let sunCore: C3  = (1.00, 1.00, 1.00)
let sunGlow: C3  = (0.62, 0.98, 1.00)
let nebulaA: C3  = (0.20, 0.16, 0.52)   // faint indigo wash, upper left
let nebulaB: C3  = (0.04, 0.26, 0.42)   // faint teal wash, upper right

func add(_ a: inout C3, _ c: C3, _ k: Double) { a.0 += c.0 * k; a.1 += c.1 * k; a.2 += c.2 * k }
func mix(_ a: C3, _ b: C3, _ t: Double) -> C3 { (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t) }
func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, v)) }
func sstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = clamp((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t) }

// ---- Glass outlines (stars are kept out from behind the sails) ----
let outlines: [[(Double, Double)]] = (derived["outlines"] as! [[[NSNumber]]]).map { $0.map { ($0[0].doubleValue, $0[1].doubleValue) } }
func inside(_ x: Double, _ y: Double, _ poly: [(Double, Double)]) -> Bool {
    var c = false; var j = poly.count - 1
    for i in 0..<poly.count {
        let (xi, yi) = poly[i], (xj, yj) = poly[j]
        if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi { c.toggle() }
        j = i
    }
    return c
}
func nearGlass(_ x: Double, _ y: Double) -> Bool {
    for dx in [-14.0, 0, 14] { for dy in [-14.0, 0, 14] {
        if outlines.contains(where: { inside(x + dx, y + dy, $0) }) { return true } } }
    return false
}

// ---- Stars (deterministic) ----
struct Star { var x, y, r, a: Double; var halo: Bool }
var seed: UInt64 = 0x5EED_7E1A
func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
var stars: [Star] = []
func heightAbove(_ x: Double, _ y: Double) -> Double { hypot(x - cx, y - cy) - R }
while stars.count < 64 {
    let x = rnd() * 1024, y = rnd() * 1024
    if heightAbove(x, y) < 40 || nearGlass(x, y) { continue }
    let big = rnd() < 0.10
    stars.append(Star(x: x, y: y, r: big ? 2.4 + rnd() * 1.2 : 0.7 + rnd() * 1.1,
                      a: big ? 0.95 : 0.25 + rnd() * 0.55, halo: big))
}
// A couple of hand-placed brighter stars to balance the composition.
for s in [Star(x: 640, y: 70, r: 2.2, a: 0.85, halo: true),
          Star(x: 76, y: 640, r: 2.6, a: 0.9, halo: true)] where !nearGlass(s.x, s.y) { stars.append(s) }

// ---- Render ----
var px = [UInt8](repeating: 0, count: N * N * 4)
for j in 0..<N {
    for i in 0..<N {
        // 2x2 supersample for clean limb edge
        var accP: C3 = (0, 0, 0); var accA = 0.0
        for sj in 0..<2 { for si in 0..<2 {
            let x = Double(i) + 0.25 + 0.5 * Double(si)
            let y = Double(j) + 0.25 + 0.5 * Double(sj)
            let h = heightAbove(x, y)
            let ang = atan2(x - cx, cy - y)                    // 0 at top centre
            let sunF = 0.16 + 0.84 * exp(-pow((ang - sunAng) / 0.36, 2))  // rim brightest at sunrise
            var glow: C3 = (0, 0, 0)
            var body: C3 = (0, 0, 0)
            var aBody = 0.0
            if h >= 0 {
                add(&glow, rimCore, exp(-h / 5.5) * 1.15 * sunF)
                add(&glow, rimCyan, exp(-h / 26) * 0.62 * sunF)
                add(&glow, haze, exp(-h / 120) * 0.30 * (0.35 + 0.65 * sunF))
                add(&glow, hazeBlue, exp(-pow((h - 34) / 40, 2)) * 0.22 * (0.3 + 0.7 * sunF))
                add(&glow, haze, exp(-h / 380) * 0.10)
                // faint nebula washes
                let dA = hypot(x - 150, y - 210), dB = hypot(x - 900, y - 160)
                add(&glow, nebulaA, exp(-pow(dA / 330, 2)) * (dark ? 0.10 : 0.16))
                add(&glow, nebulaB, exp(-pow(dB / 300, 2)) * (dark ? 0.08 : 0.12))
            }
            if h < 1 {
                aBody = clamp(0.5 - h)                         // anti-aliased limb
                let depth = -h
                body = mix(bodyLimb, bodyDeep, 1 - exp(-depth / 70) * (0.25 + 0.75 * sunF))
                // broad soft terminator light near the sun
                let ds = hypot(x - sun.x, y - sun.y)
                add(&body, rimCyan, exp(-ds / 210) * 0.10)
                // faint sun glint on the surface just below the sunrise
                let gx = (x - sun.x) / 150, gy = (depth - 34) / 22
                add(&body, rimCyan, exp(-(gx * gx + gy * gy)) * 0.10)
                // very faint cloud bands following the curvature
                let band = 0.5 + 0.5 * sin(depth / 23 + 0.8 * sin(ang * 9))
                add(&body, haze, band * exp(-depth / 120) * 0.05 * (0.4 + 0.6 * sunF))
                // inner side of the bright rim line
                add(&body, rimCore, exp(-depth / 3.0) * 0.9 * sunF)
            }
            // Sun: core is occluded by the planet (peeking over the limb)
            let ds = hypot(x - sun.x, (y - sun.y) * 1.0)
            let occl = h >= 0 ? 1.0 : exp(h / 4)
            add(&glow, sunCore, exp(-pow(ds / 26, 2)) * 1.6 * occl)
            add(&glow, sunGlow, exp(-ds / 60) * 0.75 * occl)
            add(&glow, rimCyan, exp(-ds / 200) * 0.18 * (h >= 0 ? 1 : 0.5))
            // light pouring up through the V's notch, along the notch bisector
            // (the ray is anchored at the notch vertex; below it the sails hide it)
            let rx = x - notch.0, ry = y - notch.1
            let along = rx * rayDir.0 + ry * rayDir.1          // > 0 above the notch vertex
            let across = rx * rayDir.1 - ry * rayDir.0
            let up = along + (sun.y - notch.1)                  // distance from the sun's height
            if up > 0 {
                let e = sqrt(pow(across / 70, 2) + pow(up / 330, 2))
                add(&glow, rimCyan, exp(-e * 1.6) * 0.15)
                add(&glow, sunGlow, exp(-abs(across) / 2.2) * exp(-up / 160) * 0.40)
                add(&glow, rimCyan, exp(-abs(across) / 14) * exp(-up / 210) * 0.10)
            }
            // anamorphic streak hugging the horizon
            let dyS = abs(y - sun.y + 4), dxS = abs(x - sun.x)
            add(&glow, sunGlow, exp(-dyS / 3.0) * exp(-dxS / 150) * 0.45 * occl)

            var P: C3 = (body.0 * aBody + glow.0, body.1 * aBody + glow.1, body.2 * aBody + glow.2)
            let m = max(P.0, max(P.1, P.2))
            let A = max(aBody, min(1, m))
            P = (min(P.0, A), min(P.1, A), min(P.2, A))
            accP.0 += P.0; accP.1 += P.1; accP.2 += P.2; accA += A
        } }
        var P: C3 = (accP.0 / 4, accP.1 / 4, accP.2 / 4); var A = accA / 4
        // stars (only in space)
        let x = Double(i) + 0.5, y = Double(j) + 0.5
        for s in stars {
            let d = hypot(x - s.x, y - s.y)
            if d > 40 { continue }
            var k = s.a * clamp(s.r + 0.5 - d)                // disc
            if s.halo { k += s.a * 0.35 * exp(-d / (s.r * 2.2)) }
            if k <= 0 { continue }
            let tint: C3 = s.halo ? (0.86, 0.95, 1.0) : (0.92, 0.96, 1.0)
            P.0 += tint.0 * k; P.1 += tint.1 * k; P.2 += tint.2 * k
            A = A + (1 - A) * clamp(k)
            P = (min(P.0, A), min(P.1, A), min(P.2, A))
        }
        let o = (j * N + i) * 4
        px[o] = UInt8(clamp(P.0) * 255 + 0.5)
        px[o + 1] = UInt8(clamp(P.1) * 255 + 0.5)
        px[o + 2] = UInt8(clamp(P.2) * 255 + 0.5)
        px[o + 3] = UInt8(clamp(A) * 255 + 0.5)
    }
}

let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let provider = CGDataProvider(data: Data(px) as CFData)!
let img = CGImage(width: N, height: N, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: N * 4, space: cs,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
