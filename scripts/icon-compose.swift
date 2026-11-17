// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Lays out a full-bleed icon render (from ictool), or renders an SVG, for a
// specific use, in sRGB.
//
//   swift scripts/icon-compose.swift <full-bleed.png or .svg> <out.png> <size> <padded|tight|opaque>
//
//   padded  macOS icon grid: the body is 824/1024 of the canvas, with a soft
//           drop shadow, like the icon in Finder and the Dock.
//   tight   The image fills the canvas. Used for the PNG favicons, from the
//           favicon's SVG.
//   opaque  A full square with no transparency (apple-touch-icon). iOS
//           rounds the corners itself.
import AppKit

let args = CommandLine.arguments
guard args.count == 5, let source = NSImage(contentsOfFile: args[1]), let size = Int(args[3]) else {
    FileHandle.standardError.write(Data("usage: icon-compose.swift <in.png or .svg> <out.png> <size> <padded|tight|opaque>\n".utf8))
    exit(1)
}
let mode = args[4]
let side = CGFloat(size)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    .retagging(with: .sRGB)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

switch mode {
case "padded":
    let body = (side * 824 / 1024).rounded()
    let origin = ((side - body) / 2).rounded()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
    shadow.shadowBlurRadius = side * 0.03
    shadow.set()
    source.draw(in: NSRect(x: origin, y: origin + side * 0.006, width: body, height: body))
case "tight":
    source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
case "opaque":
    // Fill with the colour just inside the icon's top edge, so the corners
    // (outside the squircle) blend with the artwork.
    var fill = NSColor.black
    if let bitmap = source.representations.first as? NSBitmapImageRep {
        fill = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: Int(Double(bitmap.pixelsHigh) * 0.04)) ?? fill
    }
    fill.withAlphaComponent(1).setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()
    source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
default:
    FileHandle.standardError.write(Data("unknown mode \(mode)\n".utf8))
    exit(1)
}

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: args[2]))
