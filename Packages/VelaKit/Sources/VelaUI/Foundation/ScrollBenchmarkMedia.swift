// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers
import VelaCore
import VelaMedia

/// Local stand-ins for everything the scroll benchmark's channel links to
/// (`ScrollBenchmarkContent`): photos, animated GIFs, GIPHY's MP4s, YouTube
/// thumbnails and oEmbed answers, and pages with OpenGraph tags and their
/// images. Drawn once at launch from fixed seeds, so they're the same in
/// every run, and served by `ScrollBenchmarkURLProtocol` to the media
/// sessions (`MediaSessionHooks`). Every other request gets a 404: nothing
/// reaches the network.
///
/// Only installed by `ScrollBenchmark`, in demo mode.
nonisolated enum ScrollBenchmarkMedia {
    /// Routes the media sessions here and starts drawing the assets in the
    /// background. Call before anything makes a media session.
    static func install() {
        MediaSessionHooks.protocolClasses = [ScrollBenchmarkURLProtocol.self]
        DispatchQueue.global(qos: .userInitiated).async { _ = Assets.shared }
    }

    struct Response {
        var status: Int
        var mimeType: String
        var body: Data
    }

    /// What was asked for, for the benchmark's report.
    struct Counts: Sendable {
        var served: [String: Int] = [:]
        var notFound: [String] = []
        var notFoundCount = 0
    }

    static let counts = Mutex(Counts())

    static func response(for url: URL) -> Response {
        let response = route(url)
        counts.withLock { counts in
            if let response {
                counts.served[response.kind, default: 0] += 1
            } else {
                counts.notFoundCount += 1
                if counts.notFound.count < 40 { counts.notFound.append(url.absoluteString) }
            }
        }
        return response?.response ?? Response(status: 404, mimeType: "text/plain", body: Data("not found".utf8))
    }

    // MARK: Routing

    private static func route(_ url: URL) -> (kind: String, response: Response)? {
        guard let host = url.host()?.lowercased() else { return nil }
        let segments = url.path().split(separator: "/").map(String.init)
        let assets = Assets.shared

        func number(_ text: String) -> Int {
            Int(text.split(separator: ".").first.map(String.init)?.split(separator: "-").first.map(String.init) ?? "") ?? 0
        }

        switch host {
        case ScrollBenchmarkContent.photoHost where segments.first == "p":
            let index = number(segments.last ?? "")
            return ("photo", jpeg(assets.photos[index % assets.photos.count]))
        case ScrollBenchmarkContent.gifHost where segments.first == "gifs":
            let index = number(segments.last ?? "")
            return ("gif", Response(status: 200, mimeType: "image/gif", body: assets.gifs[index % assets.gifs.count]))
        case "media.giphy.com" where segments.count == 3:
            let variant = abs(segments[1].hashValueStable) % assets.videos.count
            if segments[2].hasSuffix(".mp4") {
                return ("giphy-mp4", Response(status: 200, mimeType: "video/mp4", body: assets.videos[variant]))
            }
            return ("giphy-image", Response(status: 200, mimeType: "image/gif", body: assets.gifs[variant % assets.gifs.count]))
        case "i.ytimg.com" where segments.count == 3:
            let variant = abs(segments[1].hashValueStable) % assets.thumbnails.count
            return ("youtube-thumbnail", jpeg(assets.thumbnails[variant]))
        case "www.youtube.com" where segments.first == "oembed":
            return ("youtube-oembed", Response(status: 200, mimeType: "application/json", body: oEmbed(for: url)))
        case _ where ScrollBenchmarkContent.pageHosts.contains(host):
            switch segments.first {
            case "articles", "scroll-benchmark":
                return ("page", Response(status: 200, mimeType: "text/html", body: page(url: url, host: host, index: number(segments.last ?? ""))))
            case "og":
                let index = number(segments.last ?? "")
                return ("page-image", jpeg(assets.cardImages[index % assets.cardImages.count]))
            case "favicon.png", "favicon.ico":
                return ("favicon", Response(status: 200, mimeType: "image/png", body: assets.favicon))
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func jpeg(_ data: Data) -> Response {
        Response(status: 200, mimeType: "image/jpeg", body: data)
    }

    private static func page(url: URL, host: String, index: Int) -> Data {
        let site = host.split(separator: ".").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? host
        let slug = url.lastPathComponent.split(separator: "-").dropFirst().joined(separator: " ")
        let title = slug.isEmpty ? "The scroll benchmark" : "\(slug.prefix(1).uppercased())\(slug.dropFirst()), part \(index)"
        let description = "Notes from the \(site) team on \(slug.isEmpty ? "scrolling" : slug): what changed, what we measured, and what's next. Entry \(index) of an ongoing series."
        let hue = ["#3366cc", "#cc5533", "#2a9d8f", "#8e44ad", "#d4a017", "#1e7b4f"][index % 6]
        let html = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <title>\(title) · \(site)</title>
        <meta property="og:type" content="article">
        <meta property="og:title" content="\(title)">
        <meta property="og:description" content="\(description)">
        <meta property="og:site_name" content="\(site)">
        <meta property="og:image" content="https://\(host)/og/\(index).jpg">
        <meta property="og:image:width" content="1200">
        <meta property="og:image:height" content="630">
        <meta name="theme-color" content="\(hue)">
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon.png">
        </head><body><article><h1>\(title)</h1><p>\(description)</p></article></body></html>
        """
        return Data(html.utf8)
    }

    private static func oEmbed(for url: URL) -> Data {
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value ?? ""
        let id = URLComponents(string: page)?.queryItems?.first { $0.name == "v" }?.value ?? "bench000000"
        let number = Int(id.dropFirst(5)) ?? 0
        let object: [String: Any] = [
            "type": "video",
            "version": "1.0",
            "title": "Benchmark video \(number): \(["a tour of the theme engine", "scrolling at 120 Hz", "IRCv3 in ten minutes", "building Vela"][number % 4])",
            "author_name": "Vela Benchmarks",
            "author_url": "https://www.youtube.com/@vela-benchmarks",
            "provider_name": "YouTube",
            "provider_url": "https://www.youtube.com/",
            "thumbnail_url": "https://i.ytimg.com/vi/\(id)/hqdefault.jpg",
            "thumbnail_width": 480,
            "thumbnail_height": 360,
            "width": 200,
            "height": 113,
            "html": "<iframe width=\"200\" height=\"113\" src=\"https://www.youtube.com/embed/\(id)?feature=oembed\"></iframe>",
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    // MARK: Assets

    /// Everything the stand-ins serve, drawn once (the first request waits).
    final class Assets: Sendable {
        static let shared = Assets()

        let photos: [Data]
        let cardImages: [Data]
        let thumbnails: [Data]
        let gifs: [Data]
        let videos: [Data]
        let favicon: Data

        private init() {
            // Photo shapes people post: landscape, portrait, 16:9, square, wide.
            let photoSizes = [(1600, 1067), (1200, 1600), (1280, 720), (1080, 1080), (2048, 1365), (900, 1200)]
            photos = photoSizes.enumerated().map { index, size in
                Painter.jpeg(width: size.0, height: size.1, seed: UInt64(100 + index))
            }
            cardImages = (0..<4).map { Painter.jpeg(width: 1200, height: 630, seed: UInt64(200 + $0)) }
            // hqdefault.jpg: 4:3 with the 16:9 frame letterboxed in black.
            thumbnails = (0..<3).map { Painter.jpeg(width: 480, height: 360, seed: UInt64(300 + $0), letterbox: 45) }
            gifs = [(320, 240), (400, 300), (360, 360)].enumerated().map { index, size in
                Painter.gif(width: size.0, height: size.1, frames: 20, seed: UInt64(400 + index))
            }
            videos = (0..<2).map { Painter.mp4(width: 480, height: 270, frames: 45, seed: UInt64(500 + $0)) }
            favicon = Painter.png(width: 32, height: 32, seed: 600)
        }
    }

    /// Draws the stand-ins: gradients with scattered translucent shapes,
    /// busy enough to compress (and decode) like real pictures.
    private enum Painter {
        static func context(width: Int, height: Int) -> CGContext? {
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }

        static func draw(in context: CGContext, width: Int, height: Int, seed: UInt64, phase: Double = 0, letterbox: Int = 0) {
            var random = ScrollBenchmarkContent.Random(seed: seed)
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            let hue = Double(random.int(360)) / 360
            let colors = [color(hue: hue, saturation: 0.55, brightness: 0.85), color(hue: hue + 0.12, saturation: 0.7, brightness: 0.35)]
            if let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: rect.width, y: rect.height), options: [])
            }
            let scale = Double(max(width, height)) / 1_000
            for index in 0..<140 {
                let size = Double(random.int(in: 8...120)) * scale
                var x = Double(random.int(width))
                let y = Double(random.int(height))
                if phase != 0 { x += sin(phase + Double(index)) * 40 * scale }
                context.setFillColor(color(hue: hue + Double(random.int(100)) / 250, saturation: 0.6, brightness: 0.9, alpha: 0.35))
                context.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size * 0.8))
            }
            if letterbox > 0 {
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: letterbox))
                context.fill(CGRect(x: 0, y: height - letterbox, width: width, height: letterbox))
            }
        }

        static func color(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) -> CGColor {
            // HSB to RGB.
            let h = (hue - floor(hue)) * 6
            let c = brightness * saturation
            let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
            let m = brightness - c
            let (r, g, b): (Double, Double, Double) = switch Int(h) {
            case 0: (c, x, 0)
            case 1: (x, c, 0)
            case 2: (0, c, x)
            case 3: (0, x, c)
            case 4: (x, 0, c)
            default: (c, 0, x)
            }
            return CGColor(srgbRed: r + m, green: g + m, blue: b + m, alpha: alpha)
        }

        static func image(width: Int, height: Int, seed: UInt64, phase: Double = 0, letterbox: Int = 0) -> CGImage? {
            guard let context = context(width: width, height: height) else { return nil }
            draw(in: context, width: width, height: height, seed: seed, phase: phase, letterbox: letterbox)
            return context.makeImage()
        }

        static func encode(_ images: [CGImage], type: UTType, properties: [CFString: Any] = [:], frameProperties: [CFString: Any] = [:]) -> Data {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil) else { return Data() }
            CGImageDestinationSetProperties(destination, properties as CFDictionary)
            for image in images {
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            }
            CGImageDestinationFinalize(destination)
            return data as Data
        }

        static func jpeg(width: Int, height: Int, seed: UInt64, letterbox: Int = 0) -> Data {
            guard let image = image(width: width, height: height, seed: seed, letterbox: letterbox) else { return Data() }
            return encode([image], type: .jpeg, frameProperties: [kCGImageDestinationLossyCompressionQuality: 0.82])
        }

        static func png(width: Int, height: Int, seed: UInt64) -> Data {
            guard let image = image(width: width, height: height, seed: seed) else { return Data() }
            return encode([image], type: .png)
        }

        static func gif(width: Int, height: Int, frames: Int, seed: UInt64) -> Data {
            let images = (0..<frames).compactMap { frame in
                image(width: width, height: height, seed: seed, phase: Double(frame) / Double(frames) * 2 * .pi)
            }
            return encode(
                images,
                type: .gif,
                properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]],
                frameProperties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.07]]
            )
        }

        /// An H.264 MP4 at 15 frames a second, like a GIF site's rendition.
        static func mp4(width: Int, height: Int, frames: Int, seed: UInt64) -> Data {
            let url = FileManager.default.temporaryDirectory.appending(path: "VelaDemo-bench-\(seed)-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: url) }
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return Data() }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
            guard writer.canAdd(input) else { return Data() }
            writer.add(input)
            guard writer.startWriting() else { return Data() }
            writer.startSession(atSourceTime: .zero)
            for frame in 0..<frames {
                while !input.isReadyForMoreMediaData { usleep(1_000) }
                guard let pool = adaptor.pixelBufferPool else { break }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { break }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let context = CGContext(
                    data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                ) {
                    draw(in: context, width: width, height: height, seed: seed, phase: Double(frame) / Double(frames) * 2 * .pi)
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 15))
            }
            input.markAsFinished()
            let done = DispatchSemaphore(value: 0)
            writer.finishWriting { done.signal() }
            done.wait()
            return (try? Data(contentsOf: url)) ?? Data()
        }
    }
}

private extension String {
    /// A hash that's the same in every run (`hashValue` is seeded per process).
    nonisolated var hashValueStable: Int {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Int(truncatingIfNeeded: hash >> 1)
    }
}

/// Answers the media sessions' requests from `ScrollBenchmarkMedia`, at
/// once and in full. Never touches the network.
nonisolated final class ScrollBenchmarkURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let answer = ScrollBenchmarkMedia.response(for: url)
        let headers = [
            "Content-Type": answer.mimeType,
            "Content-Length": String(answer.body.count),
            "Cache-Control": "no-store",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
