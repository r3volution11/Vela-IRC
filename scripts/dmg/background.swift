// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Draws the background of the disk image's window to look like velairc.app in
// dark mode: Palenight, the hero's lilac and blue glow, the "Vela" wordmark in
// the hero's gradient, an arrow from the app to the Applications folder, and
// a plate under each icon's name.
//
//   swift scripts/dmg/background.swift scripts/dmg/layout.json <out-prefix>
//
// Writes <out-prefix>.png and <out-prefix>@2x.png; scripts/make-dmg.sh joins
// them into one TIFF so Retina screens get the sharp one.
//
// Finder draws the names under the icons itself and won't let a disk image
// choose their color. Over a background picture it draws them black, even in
// dark mode (some older reports say white there). The plates are a mid-tone
// that keeps either readable: at least 4.5:1 against black and against white.

import AppKit
import CoreText

struct Layout: Decodable {
    let width: Double
    let height: Double
    let iconSize: Double
    let textSize: Double
    let app: [Double]
    let applications: [Double]
}

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let data = FileManager.default.contents(atPath: arguments[1]),
      let layout = try? JSONDecoder().decode(Layout.self, from: data)
else {
    FileHandle.standardError.write(Data("usage: background.swift <layout.json> <out-prefix>\n".utf8))
    exit(1)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// The website's dark palette (website/.vitepress/theme/vela.css).
let windowBackground: UInt32 = 0x292D3E // --vp-c-bg
let lilac: UInt32 = 0xC792EA // --vp-c-brand-1, and the hero gradient's start
let blue: UInt32 = 0x82AAFF // the hero gradient's end
let captionColor: UInt32 = 0xA6ACCD // --vp-c-text-2
// Palenight's hue at relative luminance 0.178: 4.56:1 with black text, 4.55:1 with white.
let plateColor: UInt32 = 0x6C739B

func render(scale: CGFloat, to path: String) {
    let width = layout.width
    let height = layout.height
    guard let context = CGContext(
        data: nil, width: Int(width * scale), height: Int(height * scale),
        bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(1) }
    context.scaleBy(x: scale, y: scale)

    // layout.json measures down from the top, as Finder does; Core Graphics up from the bottom.
    func point(_ x: Double, _ top: Double) -> CGPoint { CGPoint(x: x, y: height - top) }
    let app = (x: layout.app[0], y: layout.app[1])
    let applications = (x: layout.applications[0], y: layout.applications[1])
    let half = layout.iconSize / 2

    context.setFillColor(color(windowBackground))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // The hero's glow: lilac toward the app, blue toward Applications.
    func glow(_ hex: UInt32, alpha: CGFloat, center: CGPoint, radius: CGFloat) {
        let gradient = CGGradient(colorsSpace: sRGB, colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    glow(lilac, alpha: 0.24, center: point(app.x + 20, app.y - 16), radius: 240)
    glow(blue, alpha: 0.15, center: point(applications.x - 10, applications.y + 24), radius: 230)

    let heroGradient = CGGradient(colorsSpace: sRGB, colors: [color(lilac), color(blue)] as CFArray, locations: [0, 1])!

    // Text, centered on a line: Core Text in the given font, filled with a
    // color or, for the wordmark, clipped to the hero gradient.
    func text(_ string: String, font: NSFont, centerX: Double, baseline top: Double, fill: CGColor?) {
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: NSColor(cgColor: fill ?? color(0xFFFFFF)) ?? .white,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let origin = point(centerX - lineWidth / 2, top)
        context.saveGState()
        context.textPosition = origin
        if fill == nil {
            context.setTextDrawingMode(.clip)
            CTLineDraw(line, context)
            context.drawLinearGradient(
                heroGradient,
                start: CGPoint(x: origin.x, y: origin.y + ascent),
                end: CGPoint(x: origin.x + lineWidth, y: origin.y - descent),
                options: []
            )
        } else {
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }

    // The wordmark, like the website's hero.
    text("Vela", font: .systemFont(ofSize: 34, weight: .bold), centerX: width / 2, baseline: 66, fill: nil)

    // The arrow from the app to the Applications folder.
    let gap = 26.0
    let start = point(app.x + half + gap, app.y)
    let end = point(applications.x - half - gap, applications.y)
    let arrow = CGMutablePath()
    arrow.move(to: start)
    arrow.addLine(to: end)
    arrow.move(to: CGPoint(x: end.x - 11, y: end.y + 10))
    arrow.addLine(to: end)
    arrow.addLine(to: CGPoint(x: end.x - 11, y: end.y - 10))
    context.saveGState()
    context.addPath(arrow)
    context.setLineWidth(3)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(heroGradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    // A plate under each icon, where Finder writes its name.
    for icon in [app, applications] {
        let plateWidth = 116.0
        let plateHeight = 24.0
        let top = icon.y + half + 5
        let rect = CGRect(origin: point(icon.x - plateWidth / 2, top + plateHeight), size: CGSize(width: plateWidth, height: plateHeight))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: plateHeight / 2, cornerHeight: plateHeight / 2, transform: nil))
        context.setFillColor(color(plateColor))
        context.fillPath()
    }

    text(
        "Drag Vela into Applications to install it.",
        font: .systemFont(ofSize: 13, weight: .medium),
        centerX: width / 2, baseline: height - 40, fill: color(captionColor)
    )

    guard let image = context.makeImage() else { exit(1) }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: width, height: height) // 72 or 144 dpi, which tiffutil checks
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do {
        try png.write(to: URL(fileURLWithPath: path))
    } catch {
        FileHandle.standardError.write(Data("couldn't write \(path): \(error)\n".utf8))
        exit(1)
    }
}

let prefix = arguments[2]
render(scale: 1, to: "\(prefix).png")
render(scale: 2, to: "\(prefix)@2x.png")
