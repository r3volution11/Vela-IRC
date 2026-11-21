// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Savage
import SwiftUI
import Testing
import VelaCore
import VelaFoundation
import VelaStore
import VelaTheme
@testable import VelaUI

/// Renders and compares pictures of the welcome scene, offscreen.
@MainActor
enum WelcomeSceneRendering {
    /// Premultiplied sRGB pixels, 8 bits a channel.
    struct Bitmap {
        let width: Int
        let height: Int
        var bytes: [UInt8]

        func pixel(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
            let i = (y * width + x) * 4
            return (Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255, Double(bytes[i + 3]) / 255)
        }

        /// Median luminance of the pixels in `rect` (fractions of the
        /// picture), so a few stars don't count.
        func luma(in rect: CGRect) -> Double {
            let x0 = Int(rect.minX * Double(width)), x1 = max(x0 + 1, Int(rect.maxX * Double(width)))
            let y0 = Int(rect.minY * Double(height)), y1 = max(y0 + 1, Int(rect.maxY * Double(height)))
            var values: [Double] = []
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let p = pixel(x, y)
                    values.append(0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b)
                }
            }
            return values.sorted()[values.count / 2]
        }

        /// How far apart two pictures of the same size are.
        func difference(from other: Bitmap, threshold: Int = 16) -> (mean: Double, over: Double, max: Int) {
            precondition(width == other.width && height == other.height)
            var total = 0, over = 0, worst = 0
            for i in stride(from: 0, to: bytes.count, by: 4) {
                var pixelWorst = 0
                for c in 0..<4 {
                    let d = abs(Int(bytes[i + c]) - Int(other.bytes[i + c]))
                    total += d
                    pixelWorst = max(pixelWorst, d)
                }
                if pixelWorst > threshold { over += 1 }
                worst = max(worst, pixelWorst)
            }
            return (Double(total) / Double(bytes.count), Double(over) / Double(width * height), worst)
        }
    }

    static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func bitmap(of context: CGContext) -> Bitmap {
        let count = context.bytesPerRow * context.height
        let pointer = context.data!.bindMemory(to: UInt8.self, capacity: count)
        return Bitmap(width: context.width, height: context.height, bytes: Array(UnsafeBufferPointer(start: pointer, count: count)))
    }

    static func bitmap(_ image: CGImage) -> Bitmap {
        let context = context(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bitmap(of: context)
    }

    /// The scene drawn by the app's Canvas.
    static func canvasImage(_ scene: WelcomeScene, size: CGSize, scale: CGFloat = 1) -> CGImage? {
        let renderer = ImageRenderer(content: WelcomeSceneView(scene: scene).frame(width: size.width, height: size.height))
        renderer.scale = scale
        return renderer.cgImage
    }

    static func render(_ scene: WelcomeScene, size: CGSize, scale: CGFloat = 1) -> Bitmap? {
        canvasImage(scene, size: size, scale: scale).map(bitmap)
    }

    /// An SVG drawn by macOS's own SVG renderer (NSImage), at a pixel size.
    static func rasterize(svg: String, width: Int, height: Int) -> Bitmap? {
        guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
        let context = context(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap(of: context)
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Every built-in theme, resolved.
    static func builtInThemes() -> [(info: ThemeInfo, theme: ResolvedTheme)] {
        let store = ThemeStore(userThemesDirectory: FileManager.default.temporaryDirectory.appending(path: "VelaWelcome-\(UUID().uuidString)"))
        store.reload()
        return store.themes.filter { $0.source == .builtIn }.compactMap { info in
            store.resolvedTheme(for: info).map { (info, $0) }
        }
    }
}

/// Records what the scene asks a painter to do, drawing nothing.
private struct RecordingPainter: Painter {
    final class Log {
        var groups: [String] = []
        var fills = 0
        var strokes = 0
        var layers = 0
    }

    let log: Log

    func fill(_ path: Path, with paint: Paint, style: FillStyle) { log.fills += 1 }
    func stroke(_ path: Path, with paint: Paint, style: StrokeStyle) { log.strokes += 1 }
    mutating func clip(to path: Path) {}
    mutating func translateBy(x: CGFloat, y: CGFloat) {}
    mutating func scaleBy(x: CGFloat, y: CGFloat) {}
    mutating func rotate(by angle: Angle) {}
    mutating func concatenate(_ matrix: CGAffineTransform) {}

    func drawLayer(_ style: LayerStyle, _ content: (inout RecordingPainter) throws -> Void) rethrows {
        log.layers += 1
        var inner = self
        try content(&inner)
    }

    func group(_ name: String, _ content: (inout RecordingPainter) throws -> Void) rethrows {
        log.groups.append(name)
        var inner = self
        try content(&inner)
    }
}

@MainActor
@Suite("Welcome scene")
struct WelcomeSceneTests {
    let night = WelcomeScene(theme: .fallbackDark)    // Palenight
    let day = WelcomeScene(theme: .fallbackLight)     // Lighter
    let size = CGSize(width: 600, height: 380)

    private func groups(_ scene: WelcomeScene) -> [String] {
        var painter = RecordingPainter(log: .init())
        scene.draw(&painter, size: size)
        return painter.log.groups
    }

    @Test func themeKindPicksTheTimeOfDay() {
        #expect(night.dark)
        #expect(!day.dark)
        #expect(night.bg == PaintColor(ThemeColor(hex: "#292D3E")!))
        #expect(night.accent == PaintColor(ThemeColor(hex: "#C792EA")!))
        #expect(day.fg == PaintColor(ThemeColor(hex: "#37474F")!))
        #expect(day.secondary == PaintColor(ThemeColor(hex: "#607D8B")!))
    }

    @Test func darkThemeDrawsNight() throws {
        let image = try #require(WelcomeSceneRendering.render(night, size: size))
        // The moon is bright; the sky around the stars is dark.
        let moon = image.luma(in: CGRect(x: 0.72, y: 0.22, width: 0.04, height: 0.04))
        let sky = image.luma(in: CGRect(x: 0.40, y: 0.10, width: 0.20, height: 0.10))
        #expect(moon > 0.75, "moon \(moon)")
        #expect(sky < 0.2, "sky \(sky)")
        #expect(groups(night).contains("moon"))
        #expect(groups(night).contains("stars"))
        #expect(!groups(night).contains("sun"))
    }

    @Test func lightThemeDrawsDay() throws {
        let image = try #require(WelcomeSceneRendering.render(day, size: size))
        // The sun takes the accent's teal; the sky is light.
        let sun = image.pixel(Int(0.74 * size.width), Int(0.24 * size.height))
        #expect(sun.b > sun.r + 0.1, "sun \(sun)")
        let sky = image.luma(in: CGRect(x: 0.40, y: 0.10, width: 0.20, height: 0.10))
        #expect(sky > 0.75, "sky \(sky)")
        #expect(groups(day).contains("sun"))
        #expect(groups(day).contains("clouds"))
        #expect(!groups(day).contains("moon"))
    }

    @Test func stargazerAtNightKayakerByDay() {
        #expect(groups(night).contains("stargazer"))
        #expect(!groups(night).contains("kayaker"))
        #expect(groups(day).contains("kayaker"))
        #expect(!groups(day).contains("stargazer"))
        // And in the SVG, as named groups.
        let nightSVG = night.svg(size: size), daySVG = day.svg(size: size)
        #expect(nightSVG.contains(#"id="stargazer""#) && !nightSVG.contains(#"id="kayaker""#))
        #expect(daySVG.contains(#"id="kayaker""#) && !daySVG.contains(#"id="stargazer""#))
    }

    /// Pixels clearly warmer than the scene's cool colors (the stargazer's
    /// red lamp, the kayak's hull) in `rect`.
    private func warmPixels(_ image: WelcomeSceneRendering.Bitmap, in rect: CGRect) -> Int {
        var warm = 0
        for y in Int(rect.minY * Double(image.height))..<Int(rect.maxY * Double(image.height)) {
            for x in Int(rect.minX * Double(image.width))..<Int(rect.maxX * Double(image.width)) {
                let p = image.pixel(x, y)
                if p.r > p.b + 0.2, p.r > p.g + 0.1 { warm += 1 }
            }
        }
        return warm
    }

    @Test func figuresShowWhereTheyStand() throws {
        let stargazer = CGRect(x: 0.15, y: 0.72, width: 0.16, height: 0.14)
        let kayaker = CGRect(x: 0.45, y: 0.74, width: 0.12, height: 0.12)
        let nightImage = try #require(WelcomeSceneRendering.render(night, size: size, scale: 2))
        let dayImage = try #require(WelcomeSceneRendering.render(day, size: size, scale: 2))
        #expect(warmPixels(nightImage, in: stargazer) > 20)
        #expect(warmPixels(nightImage, in: kayaker) == 0)
        #expect(warmPixels(dayImage, in: kayaker) > 100)
        #expect(warmPixels(dayImage, in: stargazer) == 0)
    }

    @Test(arguments: [CGSize(width: 24, height: 15), CGSize(width: 320, height: 203), CGSize(width: 2400, height: 1520)])
    func anySizeDraws(_ size: CGSize) throws {
        for scene in [night, day] {
            let image = try #require(WelcomeSceneRendering.render(scene, size: size))
            #expect(image.width == Int(size.width))
            #expect(image.luma(in: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)) > 0)
        }
    }

    @Test func sameInputsSamePicture() throws {
        // The Canvas dithers its gradients, so two renders differ by a
        // level here and there, never more.
        let a = try #require(WelcomeSceneRendering.render(night, size: size))
        let b = try #require(WelcomeSceneRendering.render(night, size: size))
        #expect(a.difference(from: b).max <= 3)
        #expect(night.svg(size: size) == night.svg(size: size))
    }

    @Test func themeColorsChangeThePicture() throws {
        let base = try #require(WelcomeSceneRendering.render(night, size: size))
        for change in [\WelcomeScene.accent, \.bg, \.fg, \.secondary] as [WritableKeyPath<WelcomeScene, PaintColor>] {
            var scene = night
            scene[keyPath: change] = PaintColor(red: 0.9, green: 0.4, blue: 0.1)
            let changed = try #require(WelcomeSceneRendering.render(scene, size: size))
            #expect(changed.difference(from: base).mean > 0.01, "\(change)")
        }
    }

    @Test func colorCustomizationsFlowThrough() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "VelaWelcome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThemeStore(userThemesDirectory: root, settings: ThemeSettings(
            themeName: "Palenight", followSystemAppearance: false,
            colorCustomizations: ["accent": .string("#FF6A00"), "[Palenight]": .object(["chat.background": .string("#101018")])]
        ))
        store.reload()
        let scene = WelcomeScene(theme: store.current)
        #expect(scene.accent == PaintColor(ThemeColor(hex: "#FF6A00")!))
        #expect(scene.bg == PaintColor(ThemeColor(hex: "#101018")!))
        #expect(scene != night)
    }

    @Test func translucentColorsAreComposited() {
        var colors = ResolvedTheme.fallbackLight.colors
        colors[ThemeKey.chatSecondaryForeground] = ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        let theme = ResolvedTheme(id: "t", name: "T", kind: .light, vibrancy: .none, colors: colors, nickColors: [], ircColors: [])
        let scene = WelcomeScene(theme: theme)
        let bg = ThemeColor(hex: "#FAFAFA")!
        #expect(abs(scene.secondary.red - bg.red / 2) < 0.002)
    }
}

@MainActor
@Suite("Welcome scene layout")
struct WelcomeLayoutTests {
    @Test func sceneScalesWithinItsRange() throws {
        // Too small: no scene.
        #expect(WelcomeLayout.sceneSize(in: CGSize(width: 340, height: 600), textHeight: 80) == nil)
        #expect(WelcomeLayout.sceneSize(in: CGSize(width: 900, height: 300), textHeight: 80) == nil)
        // In between: as wide as fits, its shape kept.
        let mid = try #require(WelcomeLayout.sceneSize(in: CGSize(width: 520, height: 700), textHeight: 80))
        #expect(Int(mid.width) == 520 - 64)
        #expect(abs(mid.width / mid.height - WelcomeScene.aspectRatio) < 0.01)
        let short = try #require(WelcomeLayout.sceneSize(in: CGSize(width: 1400, height: 400), textHeight: 80))
        #expect(short.height <= 400 - 48 - 80)
        // Large: capped.
        let large = try #require(WelcomeLayout.sceneSize(in: CGSize(width: 3000, height: 2000), textHeight: 80))
        #expect(large.width == WelcomeLayout.maxSceneWidth)
        #expect(WelcomeLayout.titleSize(sceneWidth: 720) == 48)
        #expect(WelcomeLayout.titleSize(sceneWidth: nil) == 22)
    }

    private func emptyApp() -> AppModel {
        let root = FileManager.default.temporaryDirectory.appending(path: "VelaWelcome-\(UUID().uuidString)")
        return AppModel(
            settings: SettingsStore(fileURL: root.appending(path: "settings.json"), watchForChanges: false),
            networkStore: NetworkConfigStore(fileURL: root.appending(path: "networks.json")),
            database: nil,
            isDemo: true
        )
    }

    @Test(arguments: [CGSize(width: 260, height: 220), CGSize(width: 480, height: 420), CGSize(width: 1100, height: 760), CGSize(width: 3200, height: 2000)])
    func emptyStateRendersAtAnySize(_ size: CGSize) throws {
        for theme in [ResolvedTheme.fallbackDark, .fallbackLight] {
            let view = EmptyStateView()
                .environment(emptyApp())
                .environment(UIState())
                .environment(\.theme, theme)
                .frame(width: size.width, height: size.height)
                .background(theme[ThemeKey.chatBackground])
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int(size.width))
            let bitmap = WelcomeSceneRendering.bitmap(image)
            // With room for it, the scene shows above the middle: the moon
            // or the sun lights its upper right.
            if let scene = WelcomeLayout.sceneSize(in: size, textHeight: 80) {
                let top = (size.height - scene.height - 80) / 2
                let light = CGPoint(x: (size.width - scene.width) / 2 + scene.width * 0.74, y: top + scene.height * 0.24)
                let p = bitmap.pixel(Int(light.x), Int(light.y))
                let background = PaintColor(theme.color(ThemeKey.chatBackground))
                let distance = abs(p.r - background.red) + abs(p.g - background.green) + abs(p.b - background.blue)
                #expect(distance > 0.3, "\(size) \(theme.name): \(p)")
            }
        }
    }
}

/// The scene's SVG. What each drawing call writes is Savage's to test (its
/// SVG output suite); here, the whole scene.
@MainActor
@Suite("Welcome scene SVG")
struct WelcomeSceneSVGTests {
    private func parse(_ text: String) throws -> XMLElement {
        try #require(try XMLDocument(xmlString: text, options: []).rootElement())
    }

    /// Every element named `name` under `node`.
    private func all(_ name: String, in node: XMLNode) -> [XMLElement] {
        var found: [XMLElement] = []
        for child in node.children ?? [] {
            if let element = child as? XMLElement {
                if element.localName == name { found.append(element) }
                found += all(name, in: element)
            }
        }
        return found
    }

    private func attribute(_ name: String, _ element: XMLElement?) -> String? {
        element?.attribute(forName: name)?.stringValue
    }

    @Test(arguments: [true, false])
    func theWholeSceneIsValidVectorSVG(_ dark: Bool) throws {
        let scene = WelcomeScene(theme: dark ? .fallbackDark : .fallbackLight)
        let text = scene.svg(size: CGSize(width: 1600, height: 1013), title: "Welcome to Vela")
        let root = try parse(text)
        #expect(attribute("width", root) == "1600")
        #expect(attribute("height", root) == "1013")
        #expect(attribute("viewBox", root) == "0 0 1600 1013")
        #expect(all("title", in: root).first?.stringValue == "Welcome to Vela")
        // Vectors only: no embedded pictures.
        #expect(all("image", in: root).isEmpty)
        #expect(!text.contains("data:"))
        // Every id is unique and every reference resolves.
        var ids = Set<String>()
        var duplicates: [String] = []
        func collect(_ node: XMLNode) {
            for child in node.children ?? [] {
                guard let element = child as? XMLElement else { continue }
                if let id = attribute("id", element), !ids.insert(id).inserted { duplicates.append(id) }
                collect(element)
            }
        }
        collect(root)
        #expect(duplicates.isEmpty)
        let references = text.matches(of: /url\(#([^)]+)\)/).map { String($0.1) }
        #expect(!references.isEmpty)
        #expect(references.allSatisfy(ids.contains))
        // The scene's layers: the fade into the window, and the moon's soft
        // seas (night) or the kayaker's reflection (day).
        #expect(all("mask", in: root).count >= 2)
        #expect(!all("clipPath", in: root).isEmpty)
        #expect(!all("radialGradient", in: root).isEmpty)
        #expect(all("feGaussianBlur", in: root).count == (dark ? 1 : 0))
        #expect(ids.contains(dark ? "stargazer" : "kayaker"))
    }
}

/// The SVG against the Canvas: rasterized by NSImage at the same size.
@MainActor
@Suite("Welcome scene SVG fidelity")
struct WelcomeSceneFidelityTests {
    @Test(arguments: [true, false])
    func svgMatchesTheCanvas(_ dark: Bool) throws {
        let scene = WelcomeScene(theme: dark ? .fallbackDark : .fallbackLight)
        let size = CGSize(width: 600, height: 380), scale: CGFloat = 2
        let canvas = try #require(WelcomeSceneRendering.render(scene, size: size, scale: scale))
        let svg = try #require(WelcomeSceneRendering.rasterize(svg: scene.svg(size: size), width: canvas.width, height: canvas.height))
        let difference = canvas.difference(from: svg)
        print("Welcome scene fidelity (\(dark ? "night" : "day"), \(canvas.width)×\(canvas.height) px): mean \(String(format: "%.3f", difference.mean))/255 a channel, \(String(format: "%.3f", difference.over * 100))% of pixels off by more than 16, worst \(difference.max)")
        #expect(difference.mean < 1.0)
        #expect(difference.over < 0.005)
    }
}

/// Writes the welcome scene's PNG and SVG exports
/// (`design/welcome-scene/export.sh` runs this).
@MainActor
@Suite("Welcome scene export", .enabled(if: ProcessInfo.processInfo.environment["VELA_WELCOME_EXPORT"] != nil))
struct WelcomeSceneExport {
    static let size = CGSize(width: 1600, height: 1013)

    private func write(_ scene: WelcomeScene, to base: URL) throws {
        let image = try #require(WelcomeSceneRendering.canvasImage(scene, size: Self.size, scale: 2))
        try #require(WelcomeSceneRendering.png(image)).write(to: base.appendingPathExtension("png"))
        try scene.svg(size: Self.size, title: "Welcome to Vela").write(to: base.appendingPathExtension("svg"), atomically: true, encoding: .utf8)
    }

    @Test func exportEveryTheme() throws {
        let folder = URL(filePath: try #require(ProcessInfo.processInfo.environment["VELA_WELCOME_EXPORT"]), directoryHint: .isDirectory)
        let themes = folder.appending(path: "themes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
        try write(WelcomeScene(theme: .fallbackDark), to: folder.appending(path: "vela-welcome-night"))
        try write(WelcomeScene(theme: .fallbackLight), to: folder.appending(path: "vela-welcome-day"))
        let builtIns = WelcomeSceneRendering.builtInThemes()
        #expect(builtIns.count >= 20)
        for (info, theme) in builtIns {
            let time = theme.kind == .dark ? "night" : "day"
            try write(WelcomeScene(theme: theme), to: themes.appending(path: "vela-welcome-\(time)-\(info.id)"))
        }
    }
}

/// How long one draw takes (`VELA_WELCOME_BENCHMARK=1`).
@MainActor
@Suite("Welcome scene draw time", .enabled(if: ProcessInfo.processInfo.environment["VELA_WELCOME_BENCHMARK"] == "1"))
struct WelcomeSceneBenchmark {
    private static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    @Test func drawAt720() throws {
        let size = CGSize(width: 720, height: 456)
        for (name, scene) in [("night", WelcomeScene(theme: .fallbackDark)), ("day", WelcomeScene(theme: .fallbackLight))] {
            // Three measures, each less an empty Canvas's: the drawing code
            // alone (what the Canvas closure costs on the main thread), a
            // render by SwiftUI's own renderer (ImageRenderer's image), and a
            // render into a bitmap by Core Graphics on the CPU (the slowest
            // way to get the pixels).
            var recorded: [Double] = []
            let recording = Canvas { context, size in
                let start = DispatchTime.now().uptimeNanoseconds
                var painter = CanvasPainter(context: context)
                scene.draw(&painter, size: size)
                recorded.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
            .frame(width: size.width, height: size.height)
            func time(_ view: some View, scale: CGFloat, cpu: Bool) -> Double {
                var times: [Double] = []
                for _ in 0..<25 {
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = scale
                    let bitmap = WelcomeSceneRendering.context(width: Int(size.width * scale), height: Int(size.height * scale))
                    bitmap.scaleBy(x: scale, y: scale)
                    let start = DispatchTime.now().uptimeNanoseconds
                    if cpu {
                        renderer.render { _, draw in draw(bitmap) }
                    } else {
                        _ = renderer.cgImage
                    }
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                }
                return Self.median(times)
            }
            let empty = Canvas { _, _ in }.frame(width: size.width, height: size.height)
            func ms(_ value: Double) -> String { String(format: "%.2f ms", value) }
            for scale: CGFloat in [1, 2] {
                recorded = []
                let swiftUI = time(recording, scale: scale, cpu: false) - time(empty, scale: scale, cpu: false)
                let drawing = Self.median(recorded)
                let coreGraphics = time(recording, scale: scale, cpu: true) - time(empty, scale: scale, cpu: true)
                print("Welcome scene draw (\(name), 720×456 @\(Int(scale))x): drawing code \(ms(drawing)), SwiftUI render \(ms(swiftUI)), Core Graphics on the CPU \(ms(coreGraphics))")
            }
        }
    }
}
