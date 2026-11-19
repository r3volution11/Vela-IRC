// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import CoreGraphics
import Foundation

/// A GIF site's MP4 rendition, downloaded and checked, ready to loop.
public struct LoadedLoopingVideo: Sendable, Hashable {
    /// The video on disk, in a temporary folder of Vela's own.
    public let fileURL: URL
    /// Display size in pixels (the track's transform applied).
    public let pixelSize: CGSize
    public let byteCount: Int

    public init(fileURL: URL, pixelSize: CGSize, byteCount: Int) {
        self.fileURL = fileURL
        self.pixelSize = pixelSize
        self.byteCount = byteCount
    }
}

/// Downloads the MP4s that GIF sites serve in place of GIFs, with the same
/// rules as `ImageLoader`: `MediaPolicy.allowsImage(_:)` for the URL and
/// every redirect hop, `maxImageBytes` as the cap (checked against
/// Content-Length up front and while streaming), no cookies, and the honest
/// user agent. The player only ever reads the checked file, never the network.
///
/// Files live in a temporary folder that is emptied the first time this
/// loader is used in a session; the most recently used are kept, up to
/// `countLimit` files and `byteLimit` bytes.
public actor LoopingVideoLoader {
    public static let shared = LoopingVideoLoader()

    /// Frames larger than this are refused.
    public static let maxPixelArea = ImageLoader.maxAnimatedPixelArea

    public static let videoAccept = "video/mp4,video/*;q=0.9,*/*;q=0.5"

    /// A cookie-less, cache-less session: the files themselves are the cache.
    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.waitsForConnectivity = false
        MediaSessionHooks.apply(to: configuration)
        return URLSession(configuration: configuration)
    }

    /// `<tmp>/<bundle id>.gif-videos`: its own per app, so another copy of
    /// Vela never empties it.
    public static var defaultDirectory: URL {
        let name = (Bundle.main.bundleIdentifier ?? "VelaKit") + ".gif-videos"
        return FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
    }

    private struct Entry {
        var video: LoadedLoopingVideo
        /// Where the bytes came from after redirects.
        var finalURL: URL?
        var lastUse: UInt64
    }

    private struct LoadKey: Hashable {
        var url: URL
        var maxBytes: Int
        var policy: MediaPolicy
    }

    private let session: URLSession
    private let userAgent: String
    private let directory: URL
    private let countLimit: Int
    private let byteLimit: Int
    private var entries: [URL: Entry] = [:]
    private var totalBytes = 0
    private var clock: UInt64 = 0
    private var directoryReady = false
    private var inFlight = InFlightTasks<LoadKey, LoadedLoopingVideo>()

    public init(
        session: URLSession = LoopingVideoLoader.makeDefaultSession(),
        directory: URL = LoopingVideoLoader.defaultDirectory,
        countLimit: Int = 400,
        byteLimit: Int = 256 * 1024 * 1024,
        userAgent: String = LinkPreviewService.defaultUserAgent
    ) {
        self.session = session
        self.directory = directory
        self.countLimit = max(1, countLimit)
        self.byteLimit = max(1, byteLimit)
        self.userAgent = userAgent
    }

    /// Downloads (or returns from disk) the MP4 at `url`.
    ///
    /// Throws `MediaError.blockedByPolicy` / `.siteBlocked` when the policy
    /// refuses the URL or a redirect, `.tooLarge` past `maxImageBytes`,
    /// `.tooManyPixels` past `maxPixelArea`, and `.unsupportedContent` when
    /// the response isn't an MP4 that AVFoundation can read.
    public func load(_ url: URL, policy: MediaPolicy) async throws -> LoadedLoopingVideo {
        if let refusal = policy.imageError(for: url) { throw refusal }
        if let entry = entries[url] {
            if let refusal = redirectRefusal(entry, url: url, policy: policy) { throw refusal }
            guard entry.video.byteCount <= policy.maxImageBytes else { throw MediaError.tooLarge }
            touch(url)
            return entry.video
        }

        let maxBytes = policy.maxImageBytes
        let key = LoadKey(url: url, maxBytes: maxBytes, policy: policy.fetchKey)
        let session = self.session
        let userAgent = self.userAgent
        let checkRedirect: @Sendable (URL) -> MediaError? = { policy.imageError(for: $0) }
        let (task, id) = inFlight.join(key) { id in
            Task {
                defer { self.inFlight.finish(key, id: id) }
                let directory = try self.preparedDirectory()
                let (video, finalURL) = try await Self.download(
                    url, maxBytes: maxBytes, session: session, userAgent: userAgent,
                    directory: directory, checkRedirect: checkRedirect
                )
                self.store(video, finalURL: finalURL, for: url)
                return video
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(key, id: id) }
        }
    }

    /// The video for `url` if it is on disk and `policy` allows it, without fetching.
    public func cachedVideo(for url: URL, policy: MediaPolicy) -> LoadedLoopingVideo? {
        guard policy.imageError(for: url) == nil, let entry = entries[url],
              redirectRefusal(entry, url: url, policy: policy) == nil,
              entry.video.byteCount <= policy.maxImageBytes
        else { return nil }
        touch(url)
        return entry.video
    }

    /// Deletes every file.
    public func removeAll() {
        for entry in entries.values { try? FileManager.default.removeItem(at: entry.video.fileURL) }
        entries.removeAll()
        totalBytes = 0
    }

    // MARK: - Internals

    private func leave(_ key: LoadKey, id: UInt64) {
        inFlight.leave(key, id: id)
    }

    /// A file that arrived through a redirect the policy now refuses.
    private func redirectRefusal(_ entry: Entry, url: URL, policy: MediaPolicy) -> MediaError? {
        guard let finalURL = entry.finalURL, finalURL != url else { return nil }
        return policy.imageError(for: finalURL)
    }

    private func touch(_ url: URL) {
        clock &+= 1
        entries[url]?.lastUse = clock
    }

    /// Empties the folder (files from an earlier session) the first time.
    private func preparedDirectory() throws -> URL {
        if !directoryReady {
            let manager = FileManager.default
            try? manager.removeItem(at: directory)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            directoryReady = true
        }
        return directory
    }

    private func store(_ video: LoadedLoopingVideo, finalURL: URL?, for url: URL) {
        clock &+= 1
        if let old = entries[url] {
            totalBytes -= old.video.byteCount
            if old.video.fileURL != video.fileURL { try? FileManager.default.removeItem(at: old.video.fileURL) }
        }
        entries[url] = Entry(video: video, finalURL: finalURL, lastUse: clock)
        totalBytes += video.byteCount
        while entries.count > countLimit || totalBytes > byteLimit {
            guard let oldest = entries.filter({ $0.key != url }).min(by: { $0.value.lastUse < $1.value.lastUse }) else { break }
            entries[oldest.key] = nil
            totalBytes -= oldest.value.video.byteCount
            try? FileManager.default.removeItem(at: oldest.value.video.fileURL)
        }
    }

    @concurrent
    private static func download(
        _ url: URL,
        maxBytes: Int,
        session: URLSession,
        userAgent: String,
        directory: URL,
        checkRedirect: @escaping @Sendable (URL) -> MediaError?
    ) async throws -> (LoadedLoopingVideo, finalURL: URL?) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(videoAccept, forHTTPHeaderField: "Accept")
        let options = HTTPFetcher.Options(
            maxBytes: maxBytes,
            overflow: .fail,
            checkRedirect: checkRedirect,
            inspectResponse: { response in
                // Pages, images and anything else aren't worth downloading.
                if let mime = response.normalizedMIMEType,
                   mime.hasPrefix("text/") || mime.hasPrefix("image/") || mime.hasPrefix("audio/")
                    || mime == "application/json" {
                    throw MediaError.unsupportedContent
                }
                return .read
            }
        )
        let result = try await HTTPFetcher.fetch(request, session: session, options: options)
        guard isMP4(result.body) else { throw MediaError.unsupportedContent }

        let fileURL = directory.appending(path: UUID().uuidString + ".mp4", directoryHint: .notDirectory)
        try result.body.write(to: fileURL, options: .atomic)
        do {
            let size = try await videoSize(of: fileURL)
            let area = Int(size.width).multipliedReportingOverflow(by: Int(size.height))
            guard !area.overflow, area.partialValue <= maxPixelArea else { throw MediaError.tooManyPixels }
            let video = LoadedLoopingVideo(fileURL: fileURL, pixelSize: size, byteCount: result.body.count)
            return (video, result.finalURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            if let error = error as? MediaError { throw error }
            if error is CancellationError { throw error }
            throw MediaError.unsupportedContent
        }
    }

    /// An ISO base media file (MP4): `ftyp` at offset 4.
    static func isMP4(_ data: Data) -> Bool {
        data.count >= 12 && data.dropFirst(4).prefix(4).elementsEqual("ftyp".utf8)
    }

    /// The video track's display size.
    @concurrent
    static func videoSize(of fileURL: URL) async throws -> CGSize {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaError.unsupportedContent
        }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        let size = CGSize(width: abs(rect.width).rounded(), height: abs(rect.height).rounded())
        guard size.width > 0, size.height > 0 else { throw MediaError.unsupportedContent }
        return size
    }
}
