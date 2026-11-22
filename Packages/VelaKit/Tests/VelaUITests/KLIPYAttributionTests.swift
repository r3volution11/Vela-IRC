// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaMedia
import VelaTheme
@testable import VelaUI

/// KLIPY's logos, as KLIPY's attribution guidelines ask: "Powered by KLIPY"
/// in the GIF picker, and its watermark on KLIPY's GIFs in the conversation.
/// Drawn offscreen (`ImageRenderer`) and read back pixel by pixel.
@MainActor
@Suite("KLIPY attribution")
struct KLIPYAttributionTests {
    typealias Bitmap = WelcomeSceneRendering.Bitmap

    private static func render(_ view: some View, scale: CGFloat = 2) throws -> Bitmap {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        return WelcomeSceneRendering.bitmap(image)
    }

    private static func luma(_ p: (r: Double, g: Double, b: Double, a: Double)) -> Double {
        0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
    }

    /// The lightest pixel in `rect` (points, from the top left).
    private static func lightest(in bitmap: Bitmap, _ rect: CGRect, scale: CGFloat = 2) -> Double {
        var best = 0.0
        for y in Int(rect.minY * scale)..<min(bitmap.height, Int(rect.maxY * scale)) {
            for x in Int(rect.minX * scale)..<min(bitmap.width, Int(rect.maxX * scale)) {
                best = max(best, luma(bitmap.pixel(x, y)))
            }
        }
        return best
    }

    // MARK: The files

    @Test func everyLogoIsBundledAndDrawnOncePerSize() throws {
        for logo in KLIPYLogo.allCases {
            let url = try #require(logo.resourceURL(), "no \(logo.rawValue).svg")
            #expect(url.deletingLastPathComponent().lastPathComponent == "KLIPY")
            #expect(logo.image != nil, "macOS can't read \(url.lastPathComponent)")
            let expected: CGFloat = logo == .watermark ? 375.1 / 102.5 : 2335.63 / 396.67
            #expect(abs(logo.aspectRatio - expected) < 0.01, "\(logo)")
            // Exactly the pixels it covers, made once.
            let drawn = try #require(logo.rendered(height: 16, scale: 2))
            #expect(drawn.height == 32)
            #expect(drawn.width == Int((32 * expected).rounded()))
            #expect(logo.rendered(height: 16, scale: 2) === drawn)
            #expect(logo.rendered(height: 16, scale: 1)?.height == 16)
        }
    }

    // MARK: The picker

    @Test func thePickerShowsKLIPYsLogoInTheThemesShade() throws {
        #expect(GIFAttributionBar.logo(for: KLIPYProvider(), dark: true) == .poweredByWhite)
        #expect(GIFAttributionBar.logo(for: KLIPYProvider(), dark: false) == .poweredByGray)
        // Other services keep their text.
        #expect(GIFAttributionBar.logo(for: GIPHYProvider(), dark: true) == nil)
        #expect(GIFAttributionBar.logo(for: FakeGIFProvider(), dark: false) == nil)

        // As KLIPY made them: white on a dark theme, #6D6D6D gray on a light one.
        for (theme, shade) in [(ResolvedTheme.fallbackDark, 1.0), (.fallbackLight, 0x6D / 255.0)] {
            let bar = GIFAttributionBar(provider: KLIPYProvider()) {}
                .frame(width: 360)
                .background(theme[ThemeKey.popoverBackground])
                .environment(\.theme, theme)
            let bitmap = try Self.render(bar)
            let background = Self.luma(bitmap.pixel(4, 4))
            // The logo's ink: the pixel farthest from the background, left of the link.
            var ink = background
            for y in 0..<bitmap.height {
                for x in 0..<(110 * 2) {
                    let value = Self.luma(bitmap.pixel(x, y))
                    if abs(value - background) > abs(ink - background) { ink = value }
                }
            }
            #expect(abs(ink - shade) < 0.06, "\(theme.name): the logo's ink is \(ink), not \(shade)")
        }
    }

    // MARK: The watermark

    @Test func onlyKLIPYsGIFsCarryAWatermark() {
        #expect(GIFProvider.allCases.filter(\.showsWatermark) == [.klipy])
    }

    @Test func theWatermarkFollowsTheGIFsSize() {
        // A thumbnail, small GIFs, and anything bigger.
        #expect(GIFCornerLayout.watermarkHeight(for: CGSize(width: 120, height: 80)) == 9)
        #expect(GIFCornerLayout.watermarkHeight(for: CGSize(width: 300, height: 200)) == 10)
        #expect(GIFCornerLayout.watermarkHeight(for: CGSize(width: 220, height: 400)) == 11)
        #expect(GIFCornerLayout.watermarkHeight(for: CGSize(width: 498, height: 280)) == 12)
        #expect(GIFCornerLayout.watermarkHeight(for: CGSize(width: 720, height: 600)) == 12)
    }

    /// Where the watermark goes on a GIF of `size`, with no badge beside it.
    private static func watermarkRect(in size: CGSize, inset: CGFloat = 8) -> CGRect {
        let height = GIFCornerLayout.watermarkHeight(for: size)
        let width = (height * KLIPYLogo.watermark.aspectRatio).rounded()
        return CGRect(x: inset, y: size.height - inset - height, width: width, height: height)
    }

    /// The corner on its own: the watermark in the corner, the badge after
    /// it, or above it when the GIF is too narrow.
    @Test func theBadgeMovesAlongForTheWatermark() throws {
        let badge = Color(red: 1, green: 0, blue: 0).frame(width: 24, height: 16)
        func corner(_ size: CGSize, watermark: Bool) -> some View {
            Color.black
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .bottomLeading) {
                    GIFCornerMarks(watermark: watermark, compact: false) { badge }
                }
        }
        /// The red badge's frame, in points.
        func badgeFrame(_ bitmap: Bitmap) -> CGRect? {
            var xs: [Int] = [], ys: [Int] = []
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    let p = bitmap.pixel(x, y)
                    if p.r > 0.9, p.g < 0.1 { xs.append(x); ys.append(y) }
                }
            }
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
            return CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2, width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2)
        }

        let size = CGSize(width: 240, height: 160)
        let plain = try #require(badgeFrame(try Self.render(corner(size, watermark: false))))
        #expect(plain == CGRect(x: 8, y: 160 - 8 - 16, width: 24, height: 16))

        let marked = try Self.render(corner(size, watermark: true))
        let mark = Self.watermarkRect(in: size)
        let moved = try #require(badgeFrame(marked))
        #expect(moved.minX == mark.maxX + 5)
        #expect(moved.maxY == plain.maxY)
        // The watermark, centered on the badge's row: light on black.
        let row = CGRect(x: mark.minX, y: moved.midY - mark.height / 2, width: mark.width, height: mark.height)
        #expect(Self.lightest(in: marked, row) > 0.45)
        #expect(Self.lightest(in: marked, row) < 0.9, "drawn with KLIPY's own transparency")

        // Too narrow for both side by side: the badge goes above.
        let narrow = CGSize(width: 64, height: 120)
        let stacked = try Self.render(corner(narrow, watermark: true))
        let above = try #require(badgeFrame(stacked))
        let narrowMark = Self.watermarkRect(in: narrow)
        #expect(above.minX == 8)
        #expect(above.maxY == narrowMark.minY - 5)
        #expect(Self.lightest(in: stacked, narrowMark) > 0.45)
    }

    // MARK: Inline GIFs

    private static let size = CGSize(width: 240, height: 160)

    /// A black picture of `size`, remembered for `url` as an inline GIF's
    /// first frame, so it draws at once (nothing is downloaded).
    private static func remember(_ url: URL, compact: Bool = false) {
        let context = WelcomeSceneRendering.context(width: Int(size.width), height: Int(size.height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let budget = EmbedImagePipeline.pixelBudget(forPoints: compact ? InlineImageView.compactMaxWidth : InlineImageView.fullMaxWidth)
        EmbedMemory.shared.remember(still: context.makeImage()!, for: StillImageKey(url: url, maxPixelSize: budget))
        EmbedMemory.shared.remember(pixelSize: size, for: url)
    }

    private static func unique(_ template: String) -> URL {
        URL(string: template.replacingOccurrences(of: "ID", with: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()))!
    }

    private static func gif(_ info: GIFInfo, link: URL, compact: Bool = false, blurred: Bool = false) -> some View {
        InlineGIFView(linkURL: link, gif: info, policy: MediaPolicy(), compact: compact, maxImageHeight: 300, onHide: {})
            .environment(\.embedBlur, EmbedBlur(isBlurred: blurred))
            .environment(\.theme, .fallbackDark)
    }

    /// A KLIPY GIF or WebP plays from the file itself (`InlineImageView`);
    /// a still one has no badge, so the corner is the watermark's alone.
    @Test(arguments: [GIFProvider.klipy, .giphy, .tenor, .imgur])
    func theWatermarkIsOnKLIPYsGIFsOnly(_ provider: GIFProvider) throws {
        let file = Self.unique("https://static.klipy.com/ii/ID/3d/31/a.gif")
        Self.remember(file)
        let bitmap = try Self.render(Self.gif(GIFInfo(provider: provider, imageURL: file), link: file))
        let mark = Self.watermarkRect(in: Self.size)
        if provider == .klipy {
            #expect(Self.lightest(in: bitmap, mark) > 0.45, "no watermark")
        }
        // Nothing else is drawn on the GIF: the rest of it, inside its
        // border and clear of its rounded corners, stays black.
        let inside = CGRect(origin: .zero, size: Self.size).insetBy(dx: 2, dy: 2)
        let corner: CGFloat = 8
        var stray = 0.0
        for y in Int(inside.minY * 2)..<Int(inside.maxY * 2) {
            for x in Int(inside.minX * 2)..<Int(inside.maxX * 2) {
                let point = CGPoint(x: CGFloat(x) / 2, y: CGFloat(y) / 2)
                let nearSide = point.x < corner || point.x > Self.size.width - corner
                let nearEnd = point.y < corner || point.y > Self.size.height - corner
                if nearSide && nearEnd { continue }
                if provider == .klipy, mark.insetBy(dx: -1, dy: -1).contains(point) { continue }
                stray = max(stray, Self.luma(bitmap.pixel(x, y)))
            }
        }
        #expect(stray < 0.05, "\(provider): something light at \(stray)")
    }

    /// A KLIPY `.mp4` plays as the video copy (`LoopingGIFView`), its first
    /// frame showing until it plays: the watermark goes in the corner, with
    /// the "GIF" badge after it.
    @Test func theWatermarkIsOnKLIPYsVideoCopiesToo() throws {
        let video = Self.unique("https://static.klipy.com/ii/ID/3d/31/a.mp4")
        Self.remember(video)
        let klipy = try Self.render(Self.gif(GIFInfo(provider: .klipy, videoURL: video), link: video))
        let mark = Self.watermarkRect(in: Self.size)
        // Centered on the badge's row (17 points tall or so), left of the badge.
        let row = CGRect(x: mark.minX, y: Self.size.height - 8 - 20, width: mark.width, height: 20)
        #expect(Self.lightest(in: klipy, row) > 0.45, "no watermark")
        // GIPHY's has the badge in the corner. KLIPY's badge has moved along,
        // its "GIF" where GIPHY's GIF is bare.
        let giphy = try Self.render(Self.gif(GIFInfo(provider: .giphy, videoURL: video), link: video))
        let movedBadge = CGRect(x: mark.maxX + 5 + 14, y: Self.size.height - 8 - 20, width: 10, height: 20)
        #expect(Self.lightest(in: giphy, movedBadge) < 0.05)
        #expect(Self.lightest(in: klipy, movedBadge) > 0.3, "the badge didn't move along")
    }

    /// Thumbnails too, inset as their badge is.
    @Test func theWatermarkIsOnThumbnails() throws {
        let file = Self.unique("https://static.klipy.com/ii/ID/3d/31/a.webp")
        Self.remember(file, compact: true)
        let bitmap = try Self.render(Self.gif(GIFInfo(provider: .klipy, imageURL: file), link: file, compact: true))
        // 240 × 160 fits a thumbnail as 120 × 80.
        let mark = Self.watermarkRect(in: CGSize(width: 120, height: 80), inset: 4)
        #expect(mark.height == 9)
        #expect(Self.lightest(in: bitmap, mark) > 0.45, "no watermark")
    }

    /// Until it's clicked, a blurred GIF is a stand-in: no picture, no watermark.
    @Test func aBlurredGIFHasNoWatermark() throws {
        let file = Self.unique("https://static.klipy.com/ii/ID/3d/31/a.gif")
        Self.remember(file)
        let shown = try Self.render(Self.gif(GIFInfo(provider: .klipy, imageURL: file), link: file))
        let blurred = try Self.render(Self.gif(GIFInfo(provider: .klipy, imageURL: file), link: file, blurred: true))
        let mark = Self.watermarkRect(in: Self.size)
        #expect(Self.lightest(in: shown, mark) > 0.45)
        // The stand-in's corner is all one shade.
        var shades: [Double] = []
        for y in Int(mark.minY * 2)..<Int(mark.maxY * 2) {
            for x in Int(mark.minX * 2)..<Int(mark.maxX * 2) { shades.append(Self.luma(blurred.pixel(x, y))) }
        }
        let spread = (shades.max() ?? 0) - (shades.min() ?? 0)
        #expect(spread < 0.05, "something drawn in the blurred GIF's corner (\(spread))")
    }

    /// Before its picture is there (a placeholder), and when it fails (a
    /// chip), a KLIPY GIF shows no watermark.
    @Test func noWatermarkWithoutThePicture() throws {
        // Remembered size, no picture yet: the placeholder.
        let loading = Self.unique("https://static.klipy.com/ii/ID/3d/31/a.gif")
        EmbedMemory.shared.remember(pixelSize: Self.size, for: loading)
        let placeholder = try Self.render(Self.gif(GIFInfo(provider: .klipy, imageURL: loading), link: loading))
        let mark = Self.watermarkRect(in: Self.size)
        var shades: [Double] = []
        for y in Int(mark.minY * 2)..<Int(mark.maxY * 2) {
            for x in Int(mark.minX * 2)..<Int(mark.maxX * 2) { shades.append(Self.luma(placeholder.pixel(x, y))) }
        }
        #expect((shades.max() ?? 0) - (shades.min() ?? 0) < 0.05, "something drawn on the placeholder")
    }
}

extension LinkSelectionTests {
    /// KLIPY's watermark, hosted in an offscreen window and clicked as AppKit
    /// delivers clicks: it takes none, and VoiceOver doesn't see it.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that send events to offscreen windows.
    @MainActor
    @Suite("KLIPY's watermark")
    struct GIFWatermarkHostedTests {
        private final class Taps {
            var count = 0
        }

        @Test func theWatermarkTakesNoClicksAndVoiceOverSkipsIt() async throws {
            let taps = Taps()
            let size = CGSize(width: 240, height: 160)
            // A button the size of a GIF, with the corner over it (as a GIF's
            // own click opens the viewer).
            let view = Button { taps.count += 1 } label: {
                Color.black.frame(width: size.width, height: size.height)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("The GIF")
            .overlay(alignment: .bottomLeading) {
                GIFCornerMarks(watermark: true, compact: false) { EmptyView() }
            }
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFrontRegardless()
            NSApp.perform(PickerHost.enhancedInterface, with: NSNumber(value: true))
            defer {
                window.orderOut(nil)
                window.contentView = nil
            }
            for _ in 0..<40 where PickerHost.element(labeled: "The GIF", in: host) == nil {
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(PickerHost.element(labeled: "The GIF", in: host) != nil)
            // Nothing for the watermark: no element names KLIPY, and the only
            // image-like thing is the GIF's own button.
            let labels = PickerHost.labels(in: host)
            #expect(!labels.contains { $0.localizedCaseInsensitiveContains("klipy") }, "\(labels)")
            #expect(Self.roles(in: host).filter { $0 == .image }.isEmpty)

            // A click on the watermark's middle (window points run up from the
            // bottom) reaches the GIF under it.
            let height = GIFCornerLayout.watermarkHeight(for: size)
            let width = (height * KLIPYLogo.watermark.aspectRatio).rounded()
            let point = CGPoint(x: 8 + width / 2, y: 8 + height / 2)
            for (number, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
                let event = try #require(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 9100 + number, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
                ))
                NSApp.sendEvent(event)
                try await Task.sleep(for: .milliseconds(30))
            }
            for _ in 0..<20 where taps.count == 0 {
                try await Task.sleep(for: .milliseconds(30))
            }
            #expect(taps.count == 1, "the click on the watermark didn't reach the GIF")
        }

        private static func roles(in root: AnyObject) -> [NSAccessibility.Role] {
            let own = (root.accessibilityRole?() ?? nil).map { [$0] } ?? []
            return own + ((root.accessibilityChildren?() ?? nil) ?? []).flatMap { roles(in: $0 as AnyObject) }
        }
    }
}
