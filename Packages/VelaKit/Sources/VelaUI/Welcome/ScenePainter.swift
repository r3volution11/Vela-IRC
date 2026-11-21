// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaTheme

// The welcome scene draws through `ScenePainter`, so one drawing has two
// outputs: `CanvasPainter` draws it in the app (a SwiftUI Canvas) and
// `SVGPainter` writes it as a standalone SVG. The painter offers only what
// the scene uses: fills and strokes with a flat color or a linear or radial
// gradient, clipping, translate and scale, and layers with an opacity, a
// blur, a flat wash, cut-outs and fades.

// MARK: Colors and paints

/// An sRGB color, each channel 0…1.
nonisolated struct SceneRGB: Hashable {
    var r, g, b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// A theme color's channels (its alpha is dropped: composite it first).
    init(_ color: ThemeColor) {
        self.init(r: color.red, g: color.green, b: color.blue)
    }

    static let white = SceneRGB(r: 1, g: 1, b: 1)
    static let black = SceneRGB(r: 0, g: 0, b: 0)

    /// `t` of the way from this color to `o`.
    func mix(_ o: SceneRGB, _ t: Double) -> SceneRGB {
        SceneRGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }

    /// This color at `opacity`.
    func c(_ opacity: Double = 1) -> SceneTone { SceneTone(rgb: self, opacity: opacity) }

    /// This color, opaque.
    var color: SceneTone { c() }

    var swiftUI: Color { Color(.sRGB, red: r, green: g, blue: b) }

    var luma: Double { r * 0.3 + g * 0.59 + b * 0.11 }
    func times(_ s: Double) -> SceneRGB { SceneRGB(r: r * s, g: g * s, b: b * s) }
    /// The same hue at a given brightness.
    func atLuma(_ target: Double) -> SceneRGB { times(target / max(0.001, luma)) }
    var hue: Double {
        let mx = max(r, g, b), mn = min(r, g, b)
        guard mx > mn else { return 0 }
        let h = mx == r ? (g - b) / (mx - mn) : mx == g ? 2 + (b - r) / (mx - mn) : 4 + (r - g) / (mx - mn)
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// A color with an opacity.
nonisolated struct SceneTone: Hashable {
    var rgb: SceneRGB
    var opacity: Double

    var swiftUI: Color { Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity) }
}

/// Gradient stops, like SwiftUI's `Gradient`.
nonisolated struct SceneGradient {
    struct Stop {
        var color: SceneTone
        var location: CGFloat
    }

    var stops: [Stop]

    init(stops: [Stop]) {
        self.stops = stops
    }

    /// Colors spaced evenly from 0 to 1.
    init(colors: [SceneTone]) {
        let last = CGFloat(max(1, colors.count - 1))
        stops = colors.enumerated().map { Stop(color: $0.element, location: CGFloat($0.offset) / last) }
    }

    var swiftUI: Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.color.swiftUI, location: $0.location) })
    }
}

/// What a fill or stroke is painted with. Gradients are in the drawing's
/// own coordinates and pad past their ends.
nonisolated enum ScenePaint {
    case color(SceneTone)
    case linearGradient(SceneGradient, startPoint: CGPoint, endPoint: CGPoint)
    case radialGradient(SceneGradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)

    var shading: GraphicsContext.Shading {
        switch self {
        case .color(let tone):
            .color(tone.swiftUI)
        case .linearGradient(let gradient, let start, let end):
            .linearGradient(gradient.swiftUI, startPoint: start, endPoint: end)
        case .radialGradient(let gradient, let center, let startRadius, let endRadius):
            .radialGradient(gradient.swiftUI, center: center, startRadius: startRadius, endRadius: endRadius)
        }
    }
}

/// A group drawn on its own, then composited: blurred, then washed, cut and
/// faded (in that order), then drawn at `opacity`.
nonisolated struct SceneLayer {
    struct Fade {
        /// Where the layer is kept by `paint`'s opacity. Outside it, the
        /// layer is left alone.
        var rect: CGRect
        var paint: ScenePaint
    }

    var opacity: Double = 1
    /// A Gaussian blur; the radius is its standard deviation.
    var blur: CGFloat = 0
    /// A flat color laid over what the layer drew, inside `rect` (source atop).
    var wash: (tone: SceneTone, rect: CGRect)?
    /// Clears the layer under `path` by `opacity` (destination out).
    var cuts: (path: Path, opacity: Double)?
    /// Keeps the layer by each paint's opacity, in turn (destination in).
    var fades: [Fade] = []
}

// MARK: The painter

nonisolated protocol ScenePainter {
    func fill(_ path: Path, with paint: ScenePaint, style: FillStyle)
    func stroke(_ path: Path, with paint: ScenePaint, style: StrokeStyle)
    /// Clips what this painter draws from now on (copies keep their own clip).
    mutating func clip(to path: Path)
    mutating func translateBy(x: CGFloat, y: CGFloat)
    mutating func scaleBy(x: CGFloat, y: CGFloat)
    /// Draws `content` as a layer, then composites it (see `SceneLayer`).
    /// `content` may be called more than once.
    func drawLayer(_ layer: SceneLayer, _ content: (inout Self) -> Void)
    /// A named part of the drawing (an SVG group with that `id`).
    func group(_ name: String, _ content: (inout Self) -> Void)
}

nonisolated extension ScenePainter {
    func fill(_ path: Path, with paint: ScenePaint) {
        fill(path, with: paint, style: FillStyle())
    }

    func stroke(_ path: Path, with paint: ScenePaint, lineWidth: CGFloat) {
        stroke(path, with: paint, style: StrokeStyle(lineWidth: lineWidth))
    }
}

// MARK: Drawing in the app

/// Draws through a SwiftUI `GraphicsContext`.
nonisolated struct CanvasPainter: ScenePainter {
    var context: GraphicsContext

    func fill(_ path: Path, with paint: ScenePaint, style: FillStyle) {
        context.fill(path, with: paint.shading, style: style)
    }

    func stroke(_ path: Path, with paint: ScenePaint, style: StrokeStyle) {
        context.stroke(path, with: paint.shading, style: style)
    }

    mutating func clip(to path: Path) {
        context.clip(to: path)
    }

    mutating func translateBy(x: CGFloat, y: CGFloat) {
        context.translateBy(x: x, y: y)
    }

    mutating func scaleBy(x: CGFloat, y: CGFloat) {
        context.scaleBy(x: x, y: y)
    }

    func drawLayer(_ layer: SceneLayer, _ content: (inout CanvasPainter) -> Void) {
        var host = context
        if layer.opacity < 1 { host.opacity = layer.opacity }
        host.drawLayer { layerContext in
            if layer.blur > 0 { layerContext.addFilter(.blur(radius: layer.blur)) }
            var inner = CanvasPainter(context: layerContext)
            content(&inner)
            if let wash = layer.wash {
                layerContext.blendMode = .sourceAtop
                layerContext.fill(Path(wash.rect), with: .color(wash.tone.swiftUI))
            }
            if let cuts = layer.cuts {
                layerContext.blendMode = .destinationOut
                layerContext.fill(cuts.path, with: .color(.black.opacity(cuts.opacity)))
            }
            if !layer.fades.isEmpty {
                layerContext.blendMode = .destinationIn
                for fade in layer.fades {
                    layerContext.fill(Path(fade.rect), with: fade.paint.shading)
                }
            }
        }
    }

    func group(_ name: String, _ content: (inout CanvasPainter) -> Void) {
        var inner = self
        content(&inner)
    }
}
