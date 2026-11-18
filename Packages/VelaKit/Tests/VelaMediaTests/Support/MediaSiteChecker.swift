// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
@testable import VelaMedia

/// Resolves a site's live samples against the real site, the way Vela does:
/// `MediaClassifier`, then `LinkPreviewService` when Vela would fetch a
/// preview, then `ImageLoader`, `LoopingVideoLoader` or a plain request for
/// what the preview points at, all with a default `MediaPolicy` and Vela's
/// own user agent.
///
/// Polite by design: samples run one at a time, each with a single chain of
/// requests and the app's timeouts. A failing sample is tried again after a
/// pause (twice at most), so a blip doesn't fail the run.
struct MediaSiteChecker: Sendable {
    var policy = MediaPolicy()
    var retryDelays: [Duration] = [.seconds(5), .seconds(15)]
    /// Where `LoopingVideoLoader` keeps the MP4s it downloads.
    var videoDirectory = FileManager.default.temporaryDirectory
        .appending(path: "vela-live-media-\(UUID().uuidString)", directoryHint: .isDirectory)

    struct SampleResult: Sendable {
        var sample: MediaSite.Sample
        /// What each check found, for the report.
        var details: [String]
        var failures: [String]
        /// What failed on attempts before the last, for the report.
        var earlierFailures: [String] = []
        var attempts: Int
        var seconds: Double
        var passed: Bool { failures.isEmpty }
    }

    struct SiteResult: Sendable {
        var site: MediaSite
        var samples: [SampleResult]
        var failures: [String] { samples.flatMap { result in result.failures.map { "\(result.sample.link): \($0)" } } }
        var passed: Bool { samples.allSatisfy(\.passed) }

        /// A block of the human-readable report. The first line starts with
        /// PASS, FAIL or SKIP, then the site's name.
        var report: String {
            guard !samples.isEmpty else {
                return "SKIP  \(site.name): \(site.liveNote ?? "no live samples")\n"
            }
            let count = samples.count == 1 ? "1 link" : "\(samples.count) links"
            var lines = ["\(passed ? "PASS" : "FAIL")  \(site.name) (\(count))"]
            for result in samples {
                var heading = "      \(result.passed ? "✓" : "✗") \(result.sample.link)  "
                heading += String(format: "%.1f s", result.seconds)
                if result.attempts > 1 { heading += ", \(result.attempts) attempts" }
                lines.append(heading)
                for failure in result.failures { lines.append("          ✗ \(failure)") }
                for failure in result.earlierFailures { lines.append("          (earlier: \(failure))") }
                if !result.details.isEmpty { lines.append("          " + result.details.joined(separator: " · ")) }
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }

    func check(_ site: MediaSite) async -> SiteResult {
        var results: [SampleResult] = []
        for sample in site.liveSamples {
            results.append(await check(sample))
        }
        return SiteResult(site: site, samples: results)
    }

    func check(_ sample: MediaSite.Sample) async -> SampleResult {
        let start = ContinuousClock.now
        var attempt = 1
        var outcome = await run(sample)
        var earlier: [String] = []
        while !outcome.failures.isEmpty, attempt <= retryDelays.count, !Task.isCancelled {
            earlier += outcome.failures.map { "attempt \(attempt): \($0)" }
            try? await Task.sleep(for: retryDelays[attempt - 1])
            attempt += 1
            outcome = await run(sample)
        }
        // Only what the last attempt doesn't say again: a blip, or a different failure.
        let final = Set(outcome.failures)
        earlier.removeAll { failure in final.contains { failure.hasSuffix(": " + $0) } }
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return SampleResult(
            sample: sample, details: outcome.details, failures: outcome.failures,
            earlierFailures: earlier, attempts: attempt, seconds: seconds
        )
    }

    // MARK: - One attempt

    private struct CheckFailure: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    /// One attempt at every check of a sample, with fresh loaders (so no
    /// failure or result is remembered from the last attempt).
    private func run(_ sample: MediaSite.Sample) async -> (details: [String], failures: [String]) {
        guard let url = sample.url else { return ([], ["not a URL"]) }
        let resolver = Resolver(url: url, policy: policy, videoDirectory: videoDirectory)
        var details: [String] = []
        var failures: [String] = []
        for check in sample.live {
            do {
                details.append(try await resolver.run(check))
            } catch {
                failures.append("\(check.label): \(Self.describe(error))")
            }
        }
        return (details, failures)
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as CheckFailure:
            return error.description
        case let error as MediaError:
            switch error {
            case .http(let status): return "HTTP \(status)"
            case .tooLarge: return "larger than the size limit"
            case .tooManyPixels: return "too many pixels"
            case .unsupportedContent: return "not something Vela can show"
            case .invalidResponse: return "a malformed response"
            case .blockedByPolicy: return "refused by the default media policy"
            case .siteBlocked(let block): return "blocked (\(block.reason.rawValue), \(block.domain))"
            }
        case let error as URLError:
            return "network error \(error.code.rawValue): \(error.localizedDescription)"
        default:
            return String(describing: error)
        }
    }

    // MARK: - Resolving

    /// Fetches what a sample's checks need, once each.
    private actor Resolver {
        let url: URL
        let policy: MediaPolicy
        let classification: MediaClassification
        let videoDirectory: URL
        private var fetchedPreview: LinkPreview?

        /// For the checker's own requests (players, playlists, the start of video files).
        static let session = LinkPreviewService.makeDefaultSession()

        init(url: URL, policy: MediaPolicy, videoDirectory: URL) {
            self.url = url
            self.policy = policy
            self.classification = MediaClassifier.classify(url)
            self.videoDirectory = videoDirectory
        }

        /// The preview `LinkPreviewService` builds, from a fresh service.
        func preview() async throws -> LinkPreview {
            if let fetchedPreview { return fetchedPreview }
            let preview = try await LinkPreviewService().preview(for: url, policy: policy)
            fetchedPreview = preview
            return preview
        }

        /// The GIF, from the link when it names the animation (Vela fetches
        /// nothing then), else from the preview.
        func gif() async throws -> GIFInfo {
            if let fetchedPreview, let gif = fetchedPreview.gif { return gif }
            if case .gif(let info) = classification, info.isResolved { return info }
            guard let gif = try await preview().gif else { throw CheckFailure("the preview has no GIF") }
            return gif
        }

        /// The video embed, from the preview once there is one.
        func embed() async throws -> EmbedInfo {
            if let fetchedPreview, let embed = fetchedPreview.embed { return embed }
            if case .embed(let info) = classification { return info }
            guard let embed = try await preview().embed else { throw CheckFailure("the preview has no video") }
            return embed
        }

        func run(_ check: MediaSite.LiveCheck) async throws -> String {
            switch check {
            case .kind(let kind):
                let preview = try await preview()
                guard preview.kind == kind else { throw CheckFailure("a \(preview.kind.rawValue) preview, not \(kind.rawValue)") }
                return kind.rawValue

            case .title(let text):
                let preview = try await preview()
                let title = preview.title ?? preview.embed?.title ?? preview.gif?.title
                guard let title else { throw CheckFailure("no title") }
                guard title.localizedCaseInsensitiveContains(text) else {
                    throw CheckFailure("“\(Self.short(title))” doesn't contain “\(text)”")
                }
                return "title “\(Self.short(title))”"

            case .author(let text):
                let preview = try await preview()
                let author = preview.embed?.authorName ?? preview.summary
                guard let author, author.localizedCaseInsensitiveContains(text) else {
                    throw CheckFailure("“\(author ?? "nothing")” doesn't contain “\(text)”")
                }
                return "by \(Self.short(author))"

            case .community(let community):
                let found = try await preview().embed?.community
                guard found == community else { throw CheckFailure("“\(found ?? "nothing")”, not “\(community)”") }
                return community

            case .landsOn(let prefix):
                let address = Self.address(try await preview().finalURL)
                guard address.hasPrefix(prefix) else { throw CheckFailure("landed on \(address)") }
                return "landed on \(Self.short(address))"

            case .thumbnail:
                let preview = try await preview()
                guard let thumbnail = preview.embed?.thumbnailURL ?? preview.imageURL else {
                    throw CheckFailure("no thumbnail")
                }
                let image = try await ImageLoader().load(thumbnail, policy: policy)
                return "thumbnail \(Self.size(image.pixelSize))"

            case .player:
                let player = EmbedPlayerHTML.playerURL(for: try await embed(), autoplay: false)
                var request = URLRequest(url: player, timeoutInterval: PreviewFetcher.requestTimeout)
                request.setValue(LinkPreviewService.defaultUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(PreviewFetcher.htmlAccept, forHTTPHeaderField: "Accept")
                // The player page's origin, as the iframe in EmbedPlayerHTML sends it.
                if let host = EmbedPlayerHTML.baseURL.host() {
                    request.setValue("https://\(host)/", forHTTPHeaderField: "Referer")
                }
                let result = try await HTTPFetcher.fetch(
                    request, session: Self.session,
                    options: .init(maxBytes: 64 * 1024, overflow: .truncate)
                )
                guard let mime = result.mimeType, PreviewFetcher.isHTML(mime) else {
                    throw CheckFailure("the player is \(result.mimeType ?? "untyped"), not a page")
                }
                return "player \(result.response.statusCode) \(mime)"

            case .hlsPlaylist:
                let embed = try await embed()
                var request = URLRequest(url: embed.embedURL, timeoutInterval: PreviewFetcher.requestTimeout)
                request.setValue(LinkPreviewService.defaultUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(HLSPlaylist.accept, forHTTPHeaderField: "Accept")
                let result = try await HTTPFetcher.fetch(
                    request, session: Self.session,
                    options: .init(maxBytes: HLSPlaylist.maxBytes, overflow: .fail)
                )
                guard let summary = HLSPlaylist.summary(String(decoding: result.body, as: UTF8.self)) else {
                    throw CheckFailure("not an HLS master playlist")
                }
                // The preview read the same playlist (when there is one).
                if let fetchedPreview, fetchedPreview.embed?.isGIF == nil {
                    throw CheckFailure("the preview didn't read the playlist")
                }
                let resolution = summary.largestResolution.map(Self.size) ?? "no resolution"
                return "HLS \(resolution), \(summary.hasAudio ? "with sound" : "no sound")"

            case .loopingVideo:
                guard let video = try await gif().videoURL else { throw CheckFailure("no MP4 copy") }
                let loader = LoopingVideoLoader(directory: videoDirectory)
                let loaded = try await loader.load(video, policy: policy)
                await loader.removeAll()
                return "MP4 \(Self.size(loaded.pixelSize)), \(Self.bytes(loaded.byteCount))"

            case .animatedImage:
                guard let imageURL = try await gif().imageURL else { throw CheckFailure("no GIF or WebP rendition") }
                let image = try await ImageLoader().load(imageURL, policy: policy)
                guard image.isAnimated else { throw CheckFailure("\(imageURL.lastPathComponent) isn't animated") }
                return "\(imageURL.pathExtension.uppercased()) \(Self.size(image.pixelSize)), \(image.frameCount) frames, \(Self.bytes(image.data.count))"

            case .image(let animated):
                let imageURL: URL
                if case .image(let classified) = classification {
                    imageURL = classified
                } else if let media = try await preview().mediaURL {
                    imageURL = media
                } else {
                    throw CheckFailure("no image")
                }
                let image = try await ImageLoader().load(imageURL, policy: policy)
                guard image.isAnimated == animated else {
                    throw CheckFailure(animated ? "not animated" : "animated, unexpectedly")
                }
                let frames = image.isAnimated ? ", \(image.frameCount) frames" : ""
                return "image \(Self.size(image.pixelSize))\(frames), \(Self.bytes(image.data.count))"

            case .videoFile:
                let preview = try await preview()
                guard let type = preview.contentType, type.hasPrefix("video/") else {
                    throw CheckFailure("served as \(preview.contentType ?? "nothing in particular")")
                }
                var request = URLRequest(url: preview.mediaURL ?? url, timeoutInterval: PreviewFetcher.requestTimeout)
                request.setValue(LinkPreviewService.defaultUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(PreviewFetcher.videoAccept, forHTTPHeaderField: "Accept")
                request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
                let result = try await HTTPFetcher.fetch(
                    request, session: Self.session,
                    options: .init(maxBytes: 64 * 1024, overflow: .truncate)
                )
                let atom = String(decoding: result.body.dropFirst(4).prefix(4), as: UTF8.self)
                guard ["ftyp", "moov", "mdat", "wide", "free", "skip"].contains(atom) else {
                    throw CheckFailure("doesn't start like a movie file")
                }
                return "\(type), starts with \(atom)"
            }
        }

        static func short(_ text: String, limit: Int = 60) -> String {
            text.count <= limit ? text : text.prefix(limit - 1) + "…"
        }

        /// `www.reddit.com/comments/x` → `reddit.com/comments/x`.
        static func address(_ url: URL) -> String {
            var host = SiteRules.normalizedHost(url) ?? ""
            if host.hasPrefix("www.") { host.removeFirst(4) }
            return host + url.path(percentEncoded: false)
        }

        static func size(_ size: CGSize) -> String {
            "\(Int(size.width))×\(Int(size.height))"
        }

        static func bytes(_ count: Int) -> String {
            count < 1024 * 1024 ? "\(count / 1024) KB" : String(format: "%.1f MB", Double(count) / 1_048_576)
        }
    }
}

extension MediaSite.LiveCheck {
    /// The check's name in the report.
    var label: String {
        switch self {
        case .kind: "kind"
        case .title: "title"
        case .author: "author"
        case .community: "community"
        case .landsOn: "redirect"
        case .thumbnail: "thumbnail"
        case .player: "player"
        case .hlsPlaylist: "HLS playlist"
        case .loopingVideo: "MP4 copy"
        case .animatedImage: "animated image"
        case .image: "image"
        case .videoFile: "video file"
        }
    }
}
