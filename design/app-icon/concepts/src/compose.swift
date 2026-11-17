// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Lays out ictool renders of the concept .icon documents.
//
//   swift compose.swift pad    <full-bleed.png> <out.png> <canvas>   macOS grid: 824/1024 body + shadow
//   swift compose.swift small  <body.png> <out.png> <canvas> <inset> real-size icon with its body at <inset>
//   swift compose.swift legibility <out.png> <title> <64.png> <32.png> <16.png>
//   swift compose.swift modes  <out.png> <title> <label=png>...      appearance strip
//   swift compose.swift contact <out.png> <spec.json>
//   swift compose.swift alternates <out.png> <spec.json>
//   swift compose.swift strip  <out.png> <light|dark> <label=padded.png>...   labelled row (website)
//
// Everything is drawn in a 16-bit Display P3 context and quantised to 8 bits
// with a little noise, so the dark gradients don't band.
import AppKit

let P3 = CGColorSpace(name: CGColorSpace.displayP3)!

final class Canvas {
    let w: Int, h: Int
    let ctx: CGContext
    init(_ w: Int, _ h: Int) {
        self.w = w; self.h = h
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 16, bytesPerRow: 0, space: P3,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
        ctx.interpolationQuality = .high
        // flip to a top-left origin so layouts read naturally
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    }
    func image(_ path: String) -> CGImage {
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
        return CGImageSourceCreateImageAtIndex(src, 0, nil)!
    }
    func draw(_ img: CGImage, _ r: CGRect, nearest: Bool = false) {
        ctx.saveGState()
        ctx.interpolationQuality = nearest ? .none : .high
        ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        ctx.restoreGState()
    }
    func fill(_ r: CGRect, _ c: CGColor) { ctx.setFillColor(c); ctx.fill(r) }
    func gradient(_ r: CGRect, _ a: CGColor, _ b: CGColor, diagonal: Bool = true) {
        let g = CGGradient(colorsSpace: P3, colors: [a, b] as CFArray, locations: [0, 1])!
        ctx.saveGState(); ctx.clip(to: r)
        ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY),
                               end: CGPoint(x: diagonal ? r.maxX : r.minX, y: r.maxY), options: [])
        ctx.restoreGState()
    }
    func radial(_ c: CGPoint, _ radius: CGFloat, _ col: CGColor) {
        let clear = col.copy(alpha: 0)!
        let g = CGGradient(colorsSpace: P3, colors: [col, clear] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
    }
    func text(_ s: String, _ p: CGPoint, size: CGFloat, weight: NSFont.Weight = .semibold,
              color: NSColor, align: NSTextAlignment = .left, width: CGFloat = 2000, mono: Bool = false) {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let para = NSMutableParagraphStyle(); para.alignment = align
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        str.draw(in: CGRect(x: p.x, y: p.y, width: width, height: size * 1.6))
        NSGraphicsContext.restoreGraphicsState()
    }
    /// Shadowed icon: draws a full-bleed body image at r with a soft macOS-like drop shadow.
    func icon(_ img: CGImage, _ r: CGRect, shadow: Bool = true) {
        ctx.saveGState()
        if shadow {
            let s = r.width
            ctx.setShadow(offset: CGSize(width: 0, height: s * 0.014), blur: s * 0.036,
                          color: CGColor(gray: 0, alpha: 0.34))
        }
        draw(img, r)
        ctx.restoreGState()
    }
    func save(_ path: String) {
        // 16-bit -> 8-bit with +-0.5 LSB noise (dither), Display P3 tag kept.
        let src = ctx.data!.assumingMemoryBound(to: UInt16.self)
        let rowWords = ctx.bytesPerRow / 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
        let dst = rep.bitmapData!
        var seed: UInt32 = 0x9E3779B9
        for y in 0..<h {
            for x in 0..<w {
                for c in 0..<4 {
                    seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                    let v = Double(src[y * rowWords + x * 4 + c]) / 65535.0 * 255.0
                    let n = c == 3 ? 0.0 : Double(seed & 0xFFFF) / 65535.0 - 0.5
                    dst[y * w * 4 + x * 4 + c] = UInt8(max(0, min(255, (v + n).rounded())))
                }
            }
        }
        let tagged = rep.retagging(with: NSColorSpace.displayP3)!
        try! tagged.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}

func p3(_ hex: String, _ a: CGFloat = 1) -> CGColor {
    var v: UInt64 = 0; Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    // hex here is authored as sRGB; convert into the P3 canvas
    return CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                   blue: CGFloat(v & 255) / 255, alpha: a)
}
func ns(_ hex: String, _ a: CGFloat = 1) -> NSColor { NSColor(cgColor: p3(hex, a))! }

// Desktop-like backdrops
func lightDesk(_ cv: Canvas, _ r: CGRect) {
    cv.gradient(r, p3("#EEF1F6"), p3("#D3DAE4"))
    cv.ctx.saveGState(); cv.ctx.clip(to: r)
    cv.radial(CGPoint(x: r.minX + r.width * 0.15, y: r.minY), r.width * 0.45, p3("#FFFFFF", 0.55))
    cv.radial(CGPoint(x: r.maxX, y: r.maxY), r.width * 0.4, p3("#B9C8DC", 0.35))
    cv.ctx.restoreGState()
}
func darkDesk(_ cv: Canvas, _ r: CGRect) {
    cv.gradient(r, p3("#22263A"), p3("#0E1018"))
    cv.ctx.saveGState(); cv.ctx.clip(to: r)
    cv.radial(CGPoint(x: r.minX + r.width * 0.2, y: r.minY), r.width * 0.45, p3("#3A3560", 0.35))
    cv.radial(CGPoint(x: r.maxX, y: r.maxY), r.width * 0.4, p3("#0B2A40", 0.45))
    cv.ctx.restoreGState()
}

let args = CommandLine.arguments
switch args[1] {
case "pad":
    let side = Int(args[4])!
    let cv = Canvas(side, side)
    let s = CGFloat(side), body = (s * 824 / 1024).rounded(), o = ((s - body) / 2).rounded()
    cv.icon(cv.image(args[2]), CGRect(x: o, y: o - s * 0.006, width: body, height: body))
    cv.save(args[3])

case "small":
    let side = Int(args[4])!, inset = CGFloat(Int(args[5])!)
    let cv = Canvas(side, side)
    let img = cv.image(args[2])
    let b = CGFloat(img.width)
    cv.ctx.saveGState()
    cv.ctx.setShadow(offset: CGSize(width: 0, height: max(0.5, b * 0.015)), blur: max(1, b * 0.04),
                     color: CGColor(gray: 0, alpha: 0.3))
    cv.draw(img, CGRect(x: inset, y: inset, width: b, height: b), nearest: true)
    cv.ctx.restoreGState()
    cv.save(args[3])

case "legibility":
    // Light and dark rows: 64/32/16 at 1x, then the same magnified 6x (nearest neighbour).
    let title = args[3]
    let imgs = args[4...6].map { path -> CGImage in Canvas(1, 1).image(path) }
    let mag: CGFloat = 6
    let W = 1180, rowH = 530, H = 80 + rowH * 2
    let cv = Canvas(W, H)
    cv.fill(CGRect(x: 0, y: 0, width: W, height: H), p3("#F7F8FA"))
    cv.text(title + "  ·  legibility at 64, 32 and 16 px (left: actual size; right: the same pixels at 6×)",
            CGPoint(x: 32, y: 26), size: 20, color: ns("#1B1F27"))
    for (row, dark) in [false, true].enumerated() {
        let r = CGRect(x: 0, y: 80 + row * rowH, width: W, height: rowH)
        dark ? darkDesk(cv, r) : lightDesk(cv, r)
        let ink = dark ? ns("#C9D1DE") : ns("#3A4252")
        var x: CGFloat = 40
        let base = r.minY + 56
        for (i, img) in imgs.enumerated() {
            let s = CGFloat(img.width)
            cv.draw(img, CGRect(x: x, y: base + 64 - s, width: s, height: s), nearest: true)
            cv.text(["64", "32", "16"][i], CGPoint(x: x, y: base + 76), size: 13, weight: .medium, color: ink)
            x += s + 34
        }
        x = 300
        for (i, img) in imgs.enumerated() {
            let s = CGFloat(img.width) * mag
            cv.draw(img, CGRect(x: x, y: base + 384 - s, width: s, height: s), nearest: true)
            cv.text(["64 px × 6", "32 px × 6", "16 px × 6"][i], CGPoint(x: x, y: base + 392), size: 13, weight: .medium, color: ink)
            x += s + 36
        }
    }
    cv.save(args[2])

case "modes":
    let title = args[3]
    let items = args.dropFirst(4).map { a -> (String, String) in
        let p = a.split(separator: "=", maxSplits: 1).map(String.init); return (p[0], p[1]) }
    let cell = 300, pad = 36
    let W = pad + items.count * (cell + pad), H = 460
    let cv = Canvas(W, H)
    cv.fill(CGRect(x: 0, y: 0, width: W, height: H), p3("#F7F8FA"))
    cv.text(title + "  ·  macOS 26 appearances, rendered by ictool from the .icon",
            CGPoint(x: pad, y: 22), size: 20, color: ns("#1B1F27"))
    for (i, (label, path)) in items.enumerated() {
        let x = pad + i * (cell + pad)
        let r = CGRect(x: x - pad / 2, y: 70, width: cell + pad, height: H - 70)
        // Light-mode appearances on a light desktop, dark ones on a dark desktop
        let dark = label.lowercased().contains("dark") || label == "Dark"
        dark ? darkDesk(cv, r) : lightDesk(cv, r)
        let img = cv.image(path)
        let body = CGFloat(cell) * 824 / 1024
        cv.icon(img, CGRect(x: CGFloat(x) + (CGFloat(cell) - body) / 2, y: 100 + (CGFloat(cell) - body) / 2, width: body, height: body))
        cv.text(label, CGPoint(x: CGFloat(x), y: 410), size: 16, weight: .medium,
                color: dark ? ns("#DCE2EC") : ns("#2A303C"), align: .center, width: CGFloat(cell))
    }
    cv.save(args[2])

case "contact":
    // spec: [{"letter":"A","title":"Chamfer","big":"…512 full-bleed png","s32":"…","s16":"…"}]
    let spec = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as! [[String: String]]
    let big: CGFloat = 512, colW: CGFloat = 640, margin: CGFloat = 64
    let bandH: CGFloat = 760, header: CGFloat = 150
    let W = Int(margin * 2 + colW * CGFloat(spec.count)), H = Int(header + bandH * 2)
    let cv = Canvas(W, H)
    cv.fill(CGRect(x: 0, y: 0, width: W, height: H), p3("#F7F8FA"))
    cv.text("Vela app icon: concepts A–F", CGPoint(x: margin, y: 36), size: 44, weight: .bold, color: ns("#11151C"))
    cv.text("Each concept at 512 px on the macOS grid (824/1024 body), with the same icon at its real 32 px and 16 px sizes beside it. Rendered by ictool (Icon Composer) with Liquid Glass, Default appearance.",
            CGPoint(x: margin, y: 96), size: 20, weight: .regular, color: ns("#4A5262"), width: CGFloat(W) - margin * 2)
    for (band, dark) in [false, true].enumerated() {
        let r = CGRect(x: 0, y: header + CGFloat(band) * bandH, width: CGFloat(W), height: bandH)
        dark ? darkDesk(cv, r) : lightDesk(cv, r)
        let ink = dark ? ns("#E6EAF2") : ns("#141820"), sub = dark ? ns("#9AA4B5") : ns("#5A6272")
        cv.text(dark ? "Dark desktop" : "Light desktop", CGPoint(x: margin, y: r.minY + 22), size: 18, weight: .medium, color: sub)
        for (i, s) in spec.enumerated() {
            let x = margin + CGFloat(i) * colW
            let top = r.minY + 80
            cv.text(s["letter"]!, CGPoint(x: x, y: top), size: 40, weight: .heavy, color: ink)
            cv.text(s["title"]!, CGPoint(x: x + 44, y: top + 12), size: 26, weight: .medium, color: ink)
            let body = (big * 824 / 1024).rounded()
            let o = (big - body) / 2
            cv.icon(cv.image(s["big"]!), CGRect(x: x + o - 22, y: top + 70 + o, width: body, height: body))
            // real-size small icons, pixel aligned, bottom-aligned with the big one
            let s32 = cv.image(s["s32"]!), s16 = cv.image(s["s16"]!)
            let bx = (x + big - 4).rounded(), by = (top + 70 + big - 60).rounded()
            cv.draw(s32, CGRect(x: bx, y: by, width: 32, height: 32), nearest: true)
            cv.draw(s16, CGRect(x: bx + 46, y: by + 16, width: 16, height: 16), nearest: true)
            cv.text("32", CGPoint(x: bx + 7, y: by + 40), size: 12, weight: .medium, color: sub)
            cv.text("16", CGPoint(x: bx + 46, y: by + 40), size: 12, weight: .medium, color: sub)
        }
    }
    cv.save(args[2])

case "alternates":
    // spec: {"rows":[{"title":"A Chamfer","items":[{"label":"Vela","big":"…","s32":"…"}]}]}
    let spec = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as! [String: Any]
    let rows = spec["rows"] as! [[String: Any]]
    let cols = (rows.first!["items"] as! [[String: String]]).count
    let cell: CGFloat = 340, gap: CGFloat = 36, margin: CGFloat = 64, header: CGFloat = 150
    let rowH: CGFloat = 520
    let W = Int(margin * 2 + CGFloat(cols) * cell + CGFloat(cols - 1) * gap)
    let H = Int(header + rowH * CGFloat(rows.count) * 2)
    let cv = Canvas(W, H)
    cv.fill(CGRect(x: 0, y: 0, width: W, height: H), p3("#F7F8FA"))
    cv.text("Vela app icon: alternate colourways for A, D and E (Glint)", CGPoint(x: margin, y: 36), size: 44, weight: .bold, color: ns("#11151C"))
    cv.text("Colourways are drawn from, or tuned to sit beside, the navy and sail palette of the previous icon (Horizon Sail). Each is an Icon Composer document, shown at 340 px (macOS grid) with its real 32 px size beneath. Glint's are Vela's Dock icons.",
            CGPoint(x: margin, y: 96), size: 20, weight: .regular, color: ns("#4A5262"), width: CGFloat(W) - margin * 2)
    var y = header
    for dark in [false, true] {
        for row in rows {
            let r = CGRect(x: 0, y: y, width: CGFloat(W), height: rowH)
            dark ? darkDesk(cv, r) : lightDesk(cv, r)
            let ink = dark ? ns("#E6EAF2") : ns("#141820"), sub = dark ? ns("#9AA4B5") : ns("#5A6272")
            cv.text((row["title"] as! String) + (dark ? "  ·  dark desktop" : "  ·  light desktop"),
                    CGPoint(x: margin, y: y + 24), size: 24, weight: .semibold, color: ink)
            for (i, it) in (row["items"] as! [[String: String]]).enumerated() {
                let x = margin + CGFloat(i) * (cell + gap)
                let body = (cell * 824 / 1024).rounded(), o = (cell - body) / 2
                cv.icon(cv.image(it["big"]!), CGRect(x: x + o, y: y + 70 + o, width: body, height: body))
                cv.text(it["label"]!, CGPoint(x: x, y: y + 70 + cell + 6), size: 18, weight: .medium, color: ink,
                        align: .center, width: cell)
                let s32 = cv.image(it["s32"]!)
                cv.draw(s32, CGRect(x: (x + cell / 2 - 16).rounded(), y: (y + 70 + cell + 44).rounded(), width: 32, height: 32), nearest: true)
            }
            y += rowH
        }
    }
    cv.save(args[2])

case "strip":
    // A row of padded (macOS grid) icons with labels on a desktop, for the
    // website: strip <out.png> <light|dark> <label=padded.png>...
    let dark = args[3] == "dark"
    let items = args.dropFirst(4).map { a -> (String, String) in
        let p = a.split(separator: "=", maxSplits: 1).map(String.init); return (p[0], p[1]) }
    let cell: CGFloat = 200, gap: CGFloat = 20, margin: CGFloat = 40
    let W = Int(margin * 2 + CGFloat(items.count) * cell + CGFloat(items.count - 1) * gap), H = 316
    let cv = Canvas(W, H)
    let r = CGRect(x: 0, y: 0, width: W, height: H)
    dark ? darkDesk(cv, r) : lightDesk(cv, r)
    for (i, (label, path)) in items.enumerated() {
        let x = margin + CGFloat(i) * (cell + gap)
        cv.draw(cv.image(path), CGRect(x: x, y: 34, width: cell, height: cell))
        cv.text(label, CGPoint(x: x, y: 34 + cell + 14), size: 22, weight: .medium,
                color: dark ? ns("#DCE2EC") : ns("#2A303C"), align: .center, width: cell)
    }
    cv.save(args[2])

default:
    FileHandle.standardError.write(Data("unknown command\n".utf8)); exit(1)
}
