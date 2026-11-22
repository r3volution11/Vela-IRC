// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Draws the Alfred workflow's result icons: a channel (#) and a private
// conversation (a person), each plain, with a mention badge, and a dimmed
// channel for one you've left. Dark navy tiles with a cyan glyph, like
// Vela's own icon. Everything is drawn with paths (no fonts or symbol sets),
// so the PNGs can be made again exactly:
//
//     swift integrations/alfred/icons/make-icons.swift integrations/alfred/icons
//
// The workflow's own icon (integrations/alfred/icon.png) is Vela's app icon,
// docs/vela-icon.png; scripts/build-alfred-workflow.sh doesn't redraw these.

import AppKit
import CoreGraphics
import Foundation

let size: CGFloat = 256

struct RGB {
    let r: CGFloat, g: CGFloat, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

// The app icon's colors: the navy tile and the V's cyan gradient.
let tileTop = RGB(0x13_23_44)
let tileBottom = RGB(0x06_0D_1F)
let glyphTop = RGB(0x2B_A6_E8)
let glyphBottom = RGB(0x86_EC_F6)
let dimmedTop = RGB(0x5D_6B_82)
let dimmedBottom = RGB(0x8A_96_AA)
let badge = RGB(0xFF_5A_6E)

enum Glyph { case channel, person }

func draw(_ glyph: Glyph, mention: Bool, dimmed: Bool) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setShouldAntialias(true)

    // The tile: a rounded square with the app icon's margin and corners.
    let inset: CGFloat = 20
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 50, cornerHeight: 50, transform: nil)
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let tileGradient = CGGradient(colorsSpace: space, colors: [tileTop.cg(), tileBottom.cg()] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(tileGradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    context.restoreGState()
    context.addPath(tilePath)
    context.setStrokeColor(RGB(0x2B_3C_5E).cg(0.9))
    context.setLineWidth(2)
    context.strokePath()

    // The glyph, as a clip filled with the gradient.
    let glyphPath = CGMutablePath()
    switch glyph {
    case .channel:
        // "#": two slanted uprights and two crossbars, with round ends.
        let width: CGFloat = 17
        let uprights: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 108, y: 62), CGPoint(x: 96, y: 194)),
            (CGPoint(x: 160, y: 62), CGPoint(x: 148, y: 194)),
        ]
        let crossbars: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 72, y: 148), CGPoint(x: 186, y: 148)),
            (CGPoint(x: 68, y: 108), CGPoint(x: 182, y: 108)),
        ]
        for (start, end) in uprights + crossbars {
            let line = CGMutablePath()
            line.move(to: start)
            line.addLine(to: end)
            glyphPath.addPath(line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1))
        }
    case .person:
        // A head and shoulders.
        glyphPath.addEllipse(in: CGRect(x: 98, y: 128, width: 60, height: 60))
        let shoulders = CGMutablePath()
        shoulders.move(to: CGPoint(x: 66, y: 64))
        shoulders.addCurve(to: CGPoint(x: 190, y: 64), control1: CGPoint(x: 70, y: 138), control2: CGPoint(x: 186, y: 138))
        shoulders.closeSubpath()
        glyphPath.addPath(shoulders)
    }
    context.saveGState()
    context.addPath(glyphPath)
    context.clip(using: .winding)
    let colors = dimmed ? [dimmedTop.cg(), dimmedBottom.cg()] : [glyphTop.cg(), glyphBottom.cg()]
    let glyphGradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(glyphGradient, start: CGPoint(x: 0, y: 200), end: CGPoint(x: 0, y: 56), options: [])
    context.restoreGState()

    // The mention badge: a dot in the top-right corner, ringed in the tile's navy.
    if mention {
        let dot = CGRect(x: 168, y: 168, width: 64, height: 64)
        context.setFillColor(tileBottom.cg())
        context.fillEllipse(in: dot.insetBy(dx: -8, dy: -8))
        context.setFillColor(badge.cg())
        context.fillEllipse(in: dot)
    }

    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
let icons: [(String, Glyph, Bool, Bool)] = [
    ("channel", .channel, false, false),
    ("channel-mention", .channel, true, false),
    ("channel-left", .channel, false, true),
    ("private", .person, false, false),
    ("private-mention", .person, true, false),
]
for (name, glyph, mention, dimmed) in icons {
    let url = output.appending(path: "\(name).png")
    try draw(glyph, mention: mention, dimmed: dimmed).write(to: url)
    print(url.path)
}
