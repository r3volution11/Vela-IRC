// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VelaMedia

enum Fixtures {
    struct MissingFixture: Error { let name: String }

    static func string(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw MissingFixture(name: name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// Builds small images in memory so tests need no binary fixtures.
enum TestImages {
    struct EncodingFailed: Error {}

    static func solidImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func png(width: Int, height: Int) throws -> Data {
        guard let image = solidImage(width: width, height: height, red: 1, green: 0, blue: 0) else {
            throw EncodingFailed()
        }
        return try encode([image], type: .png)
    }

    /// A two-frame animated GIF.
    static func animatedGIF(width: Int = 4, height: Int = 4) throws -> Data {
        guard let first = solidImage(width: width, height: height, red: 1, green: 0, blue: 0),
              let second = solidImage(width: width, height: height, red: 0, green: 0, blue: 1)
        else { throw EncodingFailed() }
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1],
        ] as CFDictionary
        let fileProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary
        return try encode([first, second], type: .gif, frameProperties: frameProperties, fileProperties: fileProperties)
    }

    private static func encode(
        _ images: [CGImage],
        type: UTType,
        frameProperties: CFDictionary? = nil,
        fileProperties: CFDictionary? = nil
    ) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, type.identifier as CFString, images.count, nil
        ) else { throw EncodingFailed() }
        if let fileProperties { CGImageDestinationSetProperties(destination, fileProperties) }
        for image in images {
            CGImageDestinationAddImage(destination, image, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw EncodingFailed() }
        return data as Data
    }
}

/// An in-memory `LinkPreviewCache` for tests.
actor MemoryPreviewCache: LinkPreviewCache {
    private var stored: [String: LinkPreview] = [:]
    private(set) var storeCount = 0

    func cachedPreview(for url: URL) async -> LinkPreview? {
        stored[url.absoluteString]
    }

    func storePreview(_ preview: LinkPreview) async {
        storeCount += 1
        stored[preview.url.absoluteString] = preview
    }
}
