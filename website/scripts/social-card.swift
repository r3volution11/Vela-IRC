// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Draws velairc.app's 1200×630 social card (Open Graph / Twitter): the app
// icon, name and tagline on Palenight, beside a demo-mode screenshot.
//
//   swift website/scripts/social-card.swift <icon.png> <screenshot.png> <out.png>
//
// website/scripts/screenshots.sh runs this and converts the result to JPEG.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let icon = NSImage(contentsOfFile: arguments[1]),
      let screenshot = NSImage(contentsOfFile: arguments[2])
else {
    FileHandle.standardError.write(Data("usage: social-card.swift <icon.png> <screenshot.png> <out.png>\n".utf8))
    exit(1)
}

/// `#RRGGBB` with an optional alpha.
func color(_ hex: String, _ alpha: CGFloat = 1) -> NSColor {
    let value = Int(hex.dropFirst(), radix: 16) ?? 0
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha
    )
}

let width: CGFloat = 1200
let height: CGFloat = 630
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// Palenight ground with a lavender glow behind the text and a blue one
// behind the window.
color("#292D3E").setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
NSGradient(colors: [color("#C792EA", 0.30), color("#C792EA", 0)])?
    .draw(fromCenter: NSPoint(x: 150, y: 560), radius: 0, toCenter: NSPoint(x: 150, y: 560), radius: 560, options: [])
NSGradient(colors: [color("#82AAFF", 0.18), color("#82AAFF", 0)])?
    .draw(fromCenter: NSPoint(x: 1000, y: 120), radius: 0, toCenter: NSPoint(x: 1000, y: 120), radius: 620, options: [])

// The window, bleeding off the right edge, with a soft shadow.
let shotWidth: CGFloat = 800
let shotHeight = shotWidth * screenshot.size.height / screenshot.size.width
let shotRect = NSRect(x: 560, y: (height - shotHeight) / 2 - 6, width: shotWidth, height: shotHeight)
let windowShape = NSBezierPath(roundedRect: shotRect, xRadius: 16, yRadius: 16)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 48
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
color("#1B1E2B").setFill()
windowShape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
windowShape.addClip()
screenshot.draw(in: shotRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
color("#FFFFFF", 0.10).setStroke()
windowShape.lineWidth = 1
windowShape.stroke()

// Icon, name, tagline and address.
icon.draw(in: NSRect(x: 58, y: 392, width: 148, height: 148))

NSAttributedString(string: "Vela", attributes: [
    .font: NSFont.systemFont(ofSize: 92, weight: .bold),
    .foregroundColor: color("#EEFFFF"),
    .kern: -1.5,
]).draw(at: NSPoint(x: 70, y: 268))

let paragraph = NSMutableParagraphStyle()
paragraph.lineSpacing = 4
NSAttributedString(string: "A modern, deeply themable IRC client for macOS", attributes: [
    .font: NSFont.systemFont(ofSize: 32, weight: .medium),
    .foregroundColor: color("#BFC7D5"),
    .paragraphStyle: paragraph,
]).draw(with: NSRect(x: 72, y: 150, width: 440, height: 110), options: [.usesLineFragmentOrigin])

NSAttributedString(string: "velairc.app", attributes: [
    .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
    .foregroundColor: color("#C792EA"),
]).draw(at: NSPoint(x: 72, y: 82))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: arguments[3]))
} catch {
    FileHandle.standardError.write(Data("couldn't write \(arguments[3]): \(error.localizedDescription)\n".utf8))
    exit(1)
}
