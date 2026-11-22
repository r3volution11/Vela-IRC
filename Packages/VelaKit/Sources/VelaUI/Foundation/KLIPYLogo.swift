// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

/// KLIPY's logos, which KLIPY's attribution guidelines ask apps to show:
/// "Powered by KLIPY" in the GIF picker (`GIFAttributionBar`), and the
/// "KLIPY" watermark in the corner of its GIFs in the conversation
/// (`GIFCornerMarks`).
///
/// The files in Resources/KLIPY are KLIPY's own SVGs, unchanged. They are
/// KLIPY's trademarks, not covered by Vela's license (see
/// THIRD_PARTY_NOTICES.md). Each is read the first time it's drawn and
/// drawn once at each size it's shown at, then kept: a handful of small
/// bitmaps, never redrawn per row or per frame.
enum KLIPYLogo: String, CaseIterable {
    /// "Powered by KLIPY" in white, for dark themes.
    case poweredByWhite = "powered-by-klipy-white"
    /// "Powered by KLIPY" in gray, for light themes.
    case poweredByGray = "powered-by-klipy-gray"
    /// "KLIPY" in white, with its own transparency and a dark outline that
    /// keeps it readable on white.
    case watermark = "watermark-klipy-text-light"

    /// The picker's logo: white on a dark theme, gray on a light one, as
    /// KLIPY made them (never tinted).
    static func poweredBy(dark: Bool) -> KLIPYLogo {
        dark ? .poweredByWhite : .poweredByGray
    }

    func resourceURL(in bundle: Bundle = .module) -> URL? {
        bundle.url(forResource: rawValue, withExtension: "svg", subdirectory: "KLIPY")
    }

    /// The SVG, as macOS reads it.
    var image: NSImage? {
        if let cached = Self.images[self] { return cached }
        let image = resourceURL().flatMap(NSImage.init(contentsOf:))
        Self.images[self] = .some(image)
        return image
    }

    /// Width over height, from the file's view box.
    var aspectRatio: CGFloat {
        guard let size = image?.size, size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    /// The logo drawn `height` points tall for a `scale` display: a bitmap
    /// of exactly the pixels it covers (not the SVG's own size, thousands of
    /// points wide). Made the first time, then kept.
    func rendered(height: CGFloat, scale: CGFloat) -> CGImage? {
        let pixelHeight = max(1, Int((height * max(1, scale)).rounded()))
        let key = RenderKey(logo: self, pixelHeight: pixelHeight)
        if let cached = Self.renders[key] { return cached }
        guard let image else { return nil }
        let pixelWidth = max(1, Int((CGFloat(pixelHeight) * aspectRatio).rounded()))
        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        NSGraphicsContext.restoreGraphicsState()
        let rendered = context.makeImage()
        if let rendered { Self.renders[key] = rendered }
        return rendered
    }

    private struct RenderKey: Hashable {
        var logo: KLIPYLogo
        var pixelHeight: Int
    }

    private static var images: [KLIPYLogo: NSImage?] = [:]
    private static var renders: [RenderKey: CGImage] = [:]
}
