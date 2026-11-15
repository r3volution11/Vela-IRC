// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downloaded, validated image bytes plus what ImageIO learned about them.
/// The UI decodes `data` itself (e.g. to animate GIF/WebP/APNG frames).
public struct LoadedImage: Sendable {
    public let data: Data
    /// Display size in pixels (EXIF orientation applied).
    public let pixelSize: CGSize
    public let frameCount: Int
    public var isAnimated: Bool { frameCount > 1 }
    /// Uniform type identifier, e.g. `public.png`, `com.compuserve.gif`, `org.webmproject.webp`.
    public let utType: String?

    public init(data: Data, pixelSize: CGSize, frameCount: Int, utType: String?) {
        self.data = data
        self.pixelSize = pixelSize
        self.frameCount = frameCount
        self.utType = utType
    }
}

/// Downloads images with a byte cap, validates them with ImageIO, and keeps
/// recently used ones in memory.
///
/// `downsampledImage` returns a `CGImage`, which is `Sendable` in the
/// macOS 26 SDK, so thumbnails can be cached here and handed across actors.
public actor ImageLoader {
    public static let shared = ImageLoader()

    /// Single frames larger than this are refused to avoid decompression bombs.
    public static let maxPixelArea = 150_000_000
    /// Animated images are decoded frame by frame at full size by the UI,
    /// so their frames get a smaller budget.
    public static let maxAnimatedPixelArea = 40_000_000

    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        // Let HTTP caching avoid re-downloading images across launches.
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 256 * 1024 * 1024, directory: nil)
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private struct ThumbnailKey: Hashable {
        var url: URL
        var maxPixelSize: Int
    }

    private struct LoadKey: Hashable {
        var url: URL
        var maxBytes: Int
        var checksRedirects: Bool
    }

    private let session: URLSession
    private let userAgent: String
    private var images: LRUCache<URL, LoadedImage>
    private var thumbnails: LRUCache<ThumbnailKey, CGImage>
    private var inFlight = InFlightTasks<LoadKey, LoadedImage>()

    /// - Parameters:
    ///   - memoryLimit: Budget in bytes for cached encoded images; decoded
    ///     thumbnails get the same budget separately.
    public init(
        session: URLSession = ImageLoader.makeDefaultSession(),
        memoryLimit: Int = 128 * 1024 * 1024,
        userAgent: String = LinkPreviewService.defaultUserAgent
    ) {
        self.session = session
        self.userAgent = userAgent
        self.images = LRUCache(countLimit: 1_000, costLimit: memoryLimit)
        self.thumbnails = LRUCache(countLimit: 1_000, costLimit: memoryLimit)
    }

    /// Downloads (or returns from memory) the image at `url`.
    ///
    /// Throws `MediaError.tooLarge` if the body exceeds `maxBytes` (checked
    /// against Content-Length up front and while streaming) or the pixel
    /// budget, `MediaError.unsupportedContent` if ImageIO cannot read it.
    /// The caller is responsible for checking `MediaPolicy.allows(_:)`, or can
    /// use `load(_:policy:)`.
    public func load(_ url: URL, maxBytes: Int) async throws -> LoadedImage {
        try await load(url, maxBytes: maxBytes, allowRedirect: nil)
    }

    /// Like `load(_:maxBytes:)`, enforcing `policy` on the URL and on every
    /// redirect, with `policy.maxImageBytes` as the cap.
    public func load(_ url: URL, policy: MediaPolicy) async throws -> LoadedImage {
        guard policy.allows(url) else { throw MediaError.blockedByPolicy }
        return try await load(url, maxBytes: policy.maxImageBytes, allowRedirect: { policy.allows($0) })
    }

    /// A decoded thumbnail no larger than `maxPixelSize` on its longest side,
    /// with EXIF orientation applied. For animated images this is the first frame.
    public func downsampledImage(_ url: URL, maxPixelSize: Int, maxBytes: Int) async throws -> CGImage {
        let key = ThumbnailKey(url: url, maxPixelSize: maxPixelSize)
        if let cached = thumbnails.value(for: key) { return cached }
        let loaded = try await load(url, maxBytes: maxBytes)
        let image = try await Self.makeThumbnail(from: loaded.data, maxPixelSize: maxPixelSize)
        thumbnails.insert(image, for: key, cost: image.bytesPerRow * image.height)
        return image
    }

    /// The cached image for `url`, without fetching.
    public func cachedImage(for url: URL) -> LoadedImage? {
        images.value(for: url)
    }

    public func removeAllCachedImages() {
        images.removeAll()
        thumbnails.removeAll()
    }

    // MARK: - Loading

    private func load(
        _ url: URL, maxBytes: Int, allowRedirect: (@Sendable (URL) -> Bool)?
    ) async throws -> LoadedImage {
        if let cached = images.value(for: url) {
            guard cached.data.count <= maxBytes else { throw MediaError.tooLarge }
            return cached
        }
        // Policy-checked loads never piggyback on an unchecked download.
        let key = LoadKey(url: url, maxBytes: maxBytes, checksRedirects: allowRedirect != nil)
        let session = self.session
        let userAgent = self.userAgent
        let (task, id) = inFlight.join(key) { id in
            Task {
                defer { self.inFlight.finish(key, id: id) }
                let image = try await Self.download(
                    url, maxBytes: maxBytes, session: session, userAgent: userAgent, allowRedirect: allowRedirect
                )
                self.images.insert(image, for: url, cost: image.data.count)
                return image
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(key, id: id) }
        }
    }

    private func leave(_ key: LoadKey, id: UInt64) {
        inFlight.leave(key, id: id)
    }

    @concurrent
    private static func download(
        _ url: URL,
        maxBytes: Int,
        session: URLSession,
        userAgent: String,
        allowRedirect: (@Sendable (URL) -> Bool)?
    ) async throws -> LoadedImage {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(PreviewFetcher.imageAccept, forHTTPHeaderField: "Accept")

        let options = HTTPFetcher.Options(
            maxBytes: maxBytes,
            overflow: .fail,
            allowRedirect: allowRedirect ?? { _ in true },
            inspectResponse: { response in
                // Don't download a 10 MB HTML page hoping it is a picture.
                if let mime = response.normalizedMIMEType,
                   mime.hasPrefix("text/") || mime.hasPrefix("video/") || mime.hasPrefix("audio/")
                    || mime == "application/json" {
                    throw MediaError.unsupportedContent
                }
                return .read
            }
        )
        let result = try await HTTPFetcher.fetch(request, session: session, options: options)
        return try inspect(result.body)
    }

    // MARK: - ImageIO

    /// Validates `data` with ImageIO and reads its size, frame count and type.
    static func inspect(
        _ data: Data,
        maxPixelArea: Int = ImageLoader.maxPixelArea,
        maxAnimatedPixelArea: Int = ImageLoader.maxAnimatedPixelArea
    ) throws -> LoadedImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw MediaError.unsupportedContent
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0, CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else { throw MediaError.unsupportedContent }

        let area = width.multipliedReportingOverflow(by: height)
        let limit = frameCount > 1 ? maxAnimatedPixelArea : maxPixelArea
        guard !area.overflow, area.partialValue <= limit else { throw MediaError.tooLarge }

        // EXIF orientations 5–8 rotate by 90°.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let size = (5...8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)

        return LoadedImage(
            data: data,
            pixelSize: size,
            frameCount: frameCount,
            utType: CGImageSourceGetType(source) as String?
        )
    }

    @concurrent
    static func makeThumbnail(from data: Data, maxPixelSize: Int) async throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw MediaError.unsupportedContent }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw MediaError.unsupportedContent
        }
        return image
    }
}

extension LoadedImage {
    /// The `UTType` for `utType`, when known.
    public var contentType: UTType? { utType.flatMap(UTType.init) }
}
