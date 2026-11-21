// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// A standalone SVG being written by `SVGPainter`: shapes as paths,
/// gradients in user space, clip paths, masks for fades and cut-outs, and
/// `feGaussianBlur` for blurs. Nothing is rasterized.
nonisolated final class SVGDocument {
    let size: CGSize
    private var defs: [String] = []
    private var body: [String] = []
    /// The groups now open in `body`, outermost first.
    private var open: [Group] = []
    private var serial = 0
    private var names: Set<String> = []

    /// A `<g>` with its attributes. Each one is distinct, so two groups with
    /// the same attributes never merge.
    struct Group: Equatable {
        let serial: Int
        let attributes: String
    }

    init(size: CGSize) {
        self.size = size
    }

    var bounds: CGRect { CGRect(origin: .zero, size: size) }

    func makeID(_ prefix: String) -> String {
        serial += 1
        return "\(prefix)\(serial)"
    }

    func group(_ attributes: String) -> Group {
        serial += 1
        return Group(serial: serial, attributes: attributes)
    }

    /// An `id` for a named group: the name, made unique if it's used again.
    func uniqueName(_ name: String) -> String {
        var candidate = name
        var n = 1
        while names.contains(candidate) {
            n += 1
            candidate = "\(name)-\(n)"
        }
        names.insert(candidate)
        return candidate
    }

    func addDef(_ text: String) {
        defs.append(text)
    }

    /// Writes `element` inside the groups `chain`, reusing the groups
    /// already open where they match.
    func emit(_ element: String, in chain: [Group]) {
        var shared = 0
        while shared < open.count, shared < chain.count, open[shared] == chain[shared] { shared += 1 }
        for _ in shared..<open.count { body.append("</g>") }
        open.removeLast(open.count - shared)
        for group in chain[shared...] {
            body.append("<g \(group.attributes)>")
            open.append(group)
        }
        body.append(element)
    }

    /// The finished document.
    func text(title: String? = nil) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(Self.number(size.width))" height="\#(Self.number(size.height))" viewBox="0 0 \#(Self.number(size.width)) \#(Self.number(size.height))">"#,
        ]
        if let title { lines.append("<title>\(Self.escaped(title))</title>") }
        lines.append("<defs>")
        lines += defs
        lines.append("</defs>")
        lines += body
        lines += Array(repeating: "</g>", count: open.count)
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Formatting

    /// A coordinate to two decimal places, without trailing zeros.
    static func number(_ value: CGFloat) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == 0 { return "0" }
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int(rounded)) }
        return String(Double(rounded))
    }

    /// Opacities and gradient offsets, to four places.
    static func fraction(_ value: Double) -> String {
        let rounded = (min(1, max(0, value)) * 10_000).rounded() / 10_000
        if rounded == 0 { return "0" }
        if rounded == 1 { return "1" }
        return String(rounded)
    }

    static func hex(_ color: SceneRGB) -> String {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        let value = byte(color.r) << 16 | byte(color.g) << 8 | byte(color.b)
        let digits = String(value, radix: 16, uppercase: false)
        return "#" + String(repeating: "0", count: 6 - digits.count) + digits
    }

    static func pathData(_ path: Path) -> String {
        var d = ""
        func add(_ p: CGPoint) {
            d += number(p.x)
            d += " "
            d += number(p.y)
        }
        path.forEach { element in
            switch element {
            case .move(let p):
                d += "M"; add(p)
            case .line(let p):
                d += "L"; add(p)
            case .quadCurve(let p, let c):
                d += "Q"; add(c); d += " "; add(p)
            case .curve(let p, let c1, let c2):
                d += "C"; add(c1); d += " "; add(c2); d += " "; add(p)
            case .closeSubpath:
                d += "Z"
            }
        }
        return d
    }

    static func transformAttribute(_ t: CGAffineTransform) -> String {
        guard !t.isIdentity else { return "" }
        let values = [t.a, t.b, t.c, t.d, t.tx, t.ty].map { String(Double(($0 * 10_000).rounded() / 10_000)) }
        return #" transform="matrix(\#(values.joined(separator: " ")))""#
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Writes what the scene draws into an `SVGDocument`.
nonisolated struct SVGPainter: ScenePainter {
    let document: SVGDocument
    private var chain: [SVGDocument.Group] = []
    private var transform: CGAffineTransform = .identity
    /// Flat colors laid over everything drawn here, innermost first (a
    /// layer's wash: source atop, which on each shape is a plain mix).
    private var washes: [SceneTone] = []
    /// Shapes entirely inside this rect are left out (they'd be clipped away).
    private var omitWithin: CGRect?

    init(document: SVGDocument) {
        self.document = document
    }

    // MARK: Shapes

    func fill(_ path: Path, with paint: ScenePaint, style: FillStyle) {
        guard !path.isEmpty, shows(path.boundingRect) else { return }
        var element = #"<path d="\#(SVGDocument.pathData(path))" "# + paintAttributes(paint, "fill")
        if style.isEOFilled { element += #" fill-rule="evenodd""# }
        element += SVGDocument.transformAttribute(transform) + "/>"
        document.emit(element, in: chain)
    }

    func stroke(_ path: Path, with paint: ScenePaint, style: StrokeStyle) {
        let reach = style.lineWidth / 2 * (style.lineJoin == .miter ? style.miterLimit : 1)
        guard !path.isEmpty, shows(path.boundingRect.insetBy(dx: -reach, dy: -reach)) else { return }
        var element = #"<path d="\#(SVGDocument.pathData(path))" fill="none" "# + paintAttributes(paint, "stroke")
        element += #" stroke-width="\#(SVGDocument.number(style.lineWidth))""#
        switch style.lineCap {
        case .round: element += #" stroke-linecap="round""#
        case .square: element += #" stroke-linecap="square""#
        default: break
        }
        switch style.lineJoin {
        case .round: element += #" stroke-linejoin="round""#
        case .bevel: element += #" stroke-linejoin="bevel""#
        default: element += #" stroke-miterlimit="\#(SVGDocument.number(style.miterLimit))""#
        }
        element += SVGDocument.transformAttribute(transform) + "/>"
        document.emit(element, in: chain)
    }

    private func shows(_ bounds: CGRect) -> Bool {
        guard let omitWithin else { return true }
        return !omitWithin.contains(bounds.applying(transform))
    }

    // MARK: State

    mutating func clip(to path: Path) {
        let id = document.makeID("clip")
        document.addDef(#"<clipPath id="\#(id)"><path d="\#(SVGDocument.pathData(path))"\#(SVGDocument.transformAttribute(transform))/></clipPath>"#)
        chain.append(document.group(#"clip-path="url(#\#(id))""#))
    }

    /// `frame` less `hole`: the hole wound the other way, so it's a hole
    /// under the nonzero rule (macOS's SVG renderer ignores `clip-rule`).
    static func outside(_ hole: CGRect, within frame: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: frame.minX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        path.closeSubpath()
        path.move(to: CGPoint(x: hole.minX, y: hole.minY))
        path.addLine(to: CGPoint(x: hole.minX, y: hole.maxY))
        path.addLine(to: CGPoint(x: hole.maxX, y: hole.maxY))
        path.addLine(to: CGPoint(x: hole.maxX, y: hole.minY))
        path.closeSubpath()
        return path
    }

    mutating func translateBy(x: CGFloat, y: CGFloat) {
        transform = transform.translatedBy(x: x, y: y)
    }

    mutating func scaleBy(x: CGFloat, y: CGFloat) {
        transform = transform.scaledBy(x: x, y: y)
    }

    func group(_ name: String, _ content: (inout SVGPainter) -> Void) {
        var inner = self
        inner.chain.append(document.group(#"id="\#(document.uniqueName(name))""#))
        content(&inner)
    }

    // MARK: Layers

    /// The group just inside every masked group. A mask applies to what it
    /// masks as a whole, but Apple's SVG renderers (NSImage and Quick Look;
    /// WebKit, so Safari) mask each shape in the group on its own, so where
    /// shapes overlap they come out too opaque. A group with an opacity is
    /// drawn as one, so this one, a hair under 1 (a change no one can see),
    /// gets them right. NSImage also applies a group's opacity again to
    /// every group with an opacity inside it, so no group gets a lower one:
    /// a layer's opacity goes in its mask.
    static let wholeGroup = #"opacity="0.9999""#

    /// Masks what this painter draws from now on with the mask `id`.
    private mutating func mask(with id: String) {
        chain.append(document.group(#"mask="url(#\#(id))""#))
        chain.append(document.group(Self.wholeGroup))
    }

    func drawLayer(_ layer: SceneLayer, _ content: (inout SVGPainter) -> Void) {
        var outer = self
        if layer.cuts != nil || layer.opacity < 1 {
            outer.mask(with: layerMask(opacity: layer.opacity, cuts: layer.cuts))
        }

        // A wash or fade over the whole picture applies everywhere. One over
        // part of it leaves the rest alone: draw the layer twice, plain
        // outside that rect (reaching a point into it, so no seam opens) and
        // composited inside it.
        func coversAll(_ rect: CGRect) -> Bool { rect.applying(transform).contains(document.bounds) }
        let partial = ((layer.wash.map { [$0.rect] } ?? []) + layer.fades.map(\.rect)).filter { !coversAll($0) }
        let region = partial.first
        precondition(partial.allSatisfy { $0 == region }, "SVGPainter: a layer's partial wash and fades must share one rect")
        func composite(_ painter: inout SVGPainter, inside: Bool) {
            for fade in layer.fades.reversed() where inside || coversAll(fade.rect) {
                painter.mask(with: fadeMask(fade))
            }
            if let wash = layer.wash, inside || coversAll(wash.rect) {
                painter.washes.insert(wash.tone, at: 0)
            }
            if layer.blur > 0 {
                painter.chain.append(document.group(#"filter="url(#\#(blurFilter(layer.blur)))""#))
            }
        }
        if let region {
            var plain = outer
            let reach = region.insetBy(dx: 1, dy: 1)
            plain.clip(to: Self.outside(reach, within: document.bounds.insetBy(dx: -document.size.width, dy: -document.size.height)))
            plain.omitWithin = reach.applying(transform)
            composite(&plain, inside: false)
            content(&plain)
            outer.clip(to: Path(region))
        }
        var inner = outer
        composite(&inner, inside: true)
        content(&inner)
    }

    // MARK: Paints and definitions

    private func washed(_ tone: SceneTone) -> SceneTone {
        var rgb = tone.rgb
        for wash in washes { rgb = rgb.mix(wash.rgb, wash.opacity) }
        return SceneTone(rgb: rgb, opacity: tone.opacity)
    }

    /// `fill="…"` or `stroke="…"`, with an opacity when there is one.
    private func paintAttributes(_ paint: ScenePaint, _ kind: String) -> String {
        if case .color(let tone) = paint {
            let color = washed(tone)
            var text = #"\#(kind)="\#(SVGDocument.hex(color.rgb))""#
            if color.opacity < 1 { text += #" \#(kind)-opacity="\#(SVGDocument.fraction(color.opacity))""# }
            return text
        }
        return #"\#(kind)="url(#\#(gradient(paint, recolor: washed)))""#
    }

    /// A gradient definition in user space; its id.
    private func gradient(_ paint: ScenePaint, recolor: (SceneTone) -> SceneTone) -> String {
        func stops(_ stops: [SceneGradient.Stop], remap: (CGFloat) -> CGFloat = { $0 }) -> String {
            stops.map { stop in
                let color = recolor(stop.color)
                var text = #"<stop offset="\#(SVGDocument.fraction(Double(remap(stop.location))))" stop-color="\#(SVGDocument.hex(color.rgb))""#
                if color.opacity < 1 { text += #" stop-opacity="\#(SVGDocument.fraction(color.opacity))""# }
                return text + "/>"
            }.joined()
        }
        let n = SVGDocument.number
        switch paint {
        case .color:
            preconditionFailure("not a gradient")
        case .linearGradient(let gradient, let start, let end):
            let id = document.makeID("lg")
            document.addDef(#"<linearGradient id="\#(id)" gradientUnits="userSpaceOnUse" x1="\#(n(start.x))" y1="\#(n(start.y))" x2="\#(n(end.x))" y2="\#(n(end.y))">\#(stops(gradient.stops))</linearGradient>"#)
            return id
        case .radialGradient(let gradient, let center, let startRadius, let endRadius):
            // SVG radii start at the center: map the stops onto 0…endRadius.
            let id = document.makeID("rg")
            let r = max(endRadius, 0.0001)
            let remap = { (location: CGFloat) in (startRadius + location * (endRadius - startRadius)) / r }
            document.addDef(#"<radialGradient id="\#(id)" gradientUnits="userSpaceOnUse" cx="\#(n(center.x))" cy="\#(n(center.y))" r="\#(n(r))">\#(stops(gradient.stops, remap: remap))</radialGradient>"#)
            return id
        }
    }

    /// A luminance mask keeping what's under `fade.rect` by the paint's
    /// opacity: the paint redrawn in white.
    private func fadeMask(_ fade: SceneLayer.Fade) -> String {
        let white = { (tone: SceneTone) in SceneTone(rgb: .white, opacity: tone.opacity) }
        let paint: String
        if case .color(let tone) = fade.paint {
            paint = ##"fill="#fff" fill-opacity="\##(SVGDocument.fraction(tone.opacity))""##
        } else {
            paint = #"fill="url(#\#(gradient(fade.paint, recolor: white)))""#
        }
        return mask(#"<path d="\#(SVGDocument.pathData(Path(fade.rect)))" \#(paint)\#(SVGDocument.transformAttribute(transform))/>"#)
    }

    /// A luminance mask for a layer's opacity, clearing what's under the
    /// cut-outs by their opacity.
    private func layerMask(opacity: Double, cuts: (path: Path, opacity: Double)?) -> String {
        let all = SVGDocument.pathData(Path(document.bounds))
        var content = ##"<path d="\##(all)" fill="#fff""##
        if opacity < 1 { content += #" fill-opacity="\#(SVGDocument.fraction(opacity))""# }
        content += "/>"
        if let cuts {
            content += ##"<path d="\##(SVGDocument.pathData(cuts.path))" fill="#000" fill-opacity="\##(SVGDocument.fraction(cuts.opacity))"\##(SVGDocument.transformAttribute(transform))/>"##
        }
        return mask(content)
    }

    private func mask(_ content: String) -> String {
        let id = document.makeID("mask")
        let area = document.bounds
        let n = SVGDocument.number
        document.addDef(#"<mask id="\#(id)" maskUnits="userSpaceOnUse" x="\#(n(area.minX))" y="\#(n(area.minY))" width="\#(n(area.width))" height="\#(n(area.height))">\#(content)</mask>"#)
        return id
    }

    private func blurFilter(_ radius: CGFloat) -> String {
        let id = document.makeID("blur")
        let area = document.bounds.insetBy(dx: -radius * 3, dy: -radius * 3)
        let n = SVGDocument.number
        document.addDef(#"<filter id="\#(id)" filterUnits="userSpaceOnUse" x="\#(n(area.minX))" y="\#(n(area.minY))" width="\#(n(area.width))" height="\#(n(area.height))" color-interpolation-filters="sRGB"><feGaussianBlur stdDeviation="\#(n(radius))"/></filter>"#)
        return id
    }
}
