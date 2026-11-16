// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// A fetched preview plus whether the policy refused part of the work.
struct PreviewFetchResult: Sendable {
    var preview: LinkPreview
    /// A request (oEmbed, a page for metadata) was refused by the policy, so
    /// the preview lacks something a more permissive policy would add. Such
    /// previews are cached in memory only, for the policy that built them.
    var degraded = false
}

/// Does the network work behind `LinkPreviewService`, off the service's actor.
///
/// Every request and redirect hop is checked with `MediaPolicy.allows(_:)`;
/// image, thumbnail and favicon URLs are recorded as found and checked with
/// `allowsImage(_:)` only when they are loaded.
struct PreviewFetcher: Sendable {
    let session: URLSession
    let userAgent: String

    /// At most this much HTML is read; metadata lives in `<head>`.
    static let maxHTMLBytes = 512 * 1024
    static let maxJSONBytes = 256 * 1024
    static let requestTimeout: TimeInterval = 10

    static let htmlAccept = "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8"
    static let imageAccept = "image/avif,image/webp,image/apng,image/*;q=0.9,*/*;q=0.5"
    static let videoAccept = "video/*;q=0.9,*/*;q=0.5"

    @concurrent
    func preview(for url: URL, policy: MediaPolicy) async throws -> PreviewFetchResult {
        switch MediaClassifier.classify(url) {
        case .image(let mediaURL):
            return try await directMediaPreview(url, mediaURL: mediaURL, kind: .image, policy: policy)
        case .video(let mediaURL):
            return try await directMediaPreview(url, mediaURL: mediaURL, kind: .video, policy: policy)
        case .embed(let info):
            return try await embedPreview(url, finalURL: url, info: info, policy: policy, pageMetadata: nil)
        case .page:
            return try await pagePreview(url, policy: policy)
        }
    }

    // MARK: - Direct media

    /// A HEAD request confirms the type and size; failures other than
    /// "too large", "blocked" and "gone" are tolerated because many servers
    /// mishandle HEAD.
    private func directMediaPreview(
        _ url: URL, mediaURL: URL, kind: LinkPreview.Kind, policy: MediaPolicy
    ) async throws -> PreviewFetchResult {
        if let refusal = policy.requestError(for: mediaURL) { throw refusal }
        var request = makeRequest(mediaURL, accept: kind == .image ? Self.imageAccept : Self.videoAccept)
        request.httpMethod = "HEAD"
        let options = HTTPFetcher.Options(
            maxBytes: kind == .image ? policy.maxImageBytes : .max,
            overflow: .fail,
            checkRedirect: { policy.requestError(for: $0) },
            inspectResponse: { _ in .skip }
        )

        let head: HTTPFetchResult?
        do {
            head = try await HTTPFetcher.fetch(request, session: session, options: options)
        } catch let error as MediaError {
            switch error {
            case .tooLarge, .blockedByPolicy, .siteBlocked, .http(404), .http(410): throw error
            default: head = nil
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            head = nil
        }

        var resolvedKind = kind
        if let mime = head?.mimeType {
            if Self.isHTML(mime) {
                // An "image" URL that serves a page, e.g. an image host's viewer.
                return try await pagePreview(url, policy: policy)
            }
            if mime.hasPrefix("video/") { resolvedKind = .video }
            if mime.hasPrefix("image/") { resolvedKind = .image }
        }
        return PreviewFetchResult(preview: LinkPreview(
            url: url,
            finalURL: head?.finalURL ?? mediaURL,
            kind: resolvedKind,
            mediaURL: mediaURL,
            contentType: head?.mimeType,
            declaresAdult: head.map { Self.ratingDeclaresAdult($0.response) }
        ))
    }

    // MARK: - Embeds

    private func embedPreview(
        _ url: URL, finalURL: URL, info: EmbedInfo, policy: MediaPolicy, pageMetadata: HTMLMetadata?
    ) async throws -> PreviewFetchResult {
        var embed = info
        var summary: String?
        var siteName = info.provider.displayName
        var imageSize: CGSize?
        var degraded = false
        var declaresAdult = pageMetadata?.declaresAdult

        var oEmbed: OEmbedResponse?
        if let endpoint = OEmbedEndpoint.url(for: info) {
            if policy.allows(endpoint) {
                switch try await attempt({ try await fetchOEmbed(endpoint, policy: policy) }) {
                case .success(let response): oEmbed = response
                case .refused: degraded = true
                case .failed: break
                }
            } else {
                degraded = true
            }
        }

        if let oEmbed {
            embed.title = oEmbed.title ?? embed.title
            embed.authorName = oEmbed.authorName ?? embed.authorName
            if let thumbnail = Self.webURL(oEmbed.thumbnailURL) {
                embed.thumbnailURL = thumbnail
                if let width = oEmbed.thumbnailWidth, let height = oEmbed.thumbnailHeight, width > 0, height > 0 {
                    imageSize = CGSize(width: width, height: height)
                }
            }
            // YouTube reports its default player size, not the video's shape.
            if info.provider != .youtube, let ratio = oEmbed.aspectRatio, (0.2...5).contains(ratio) {
                embed.aspectRatio = ratio
            }
            if let provider = oEmbed.providerName { siteName = provider }
        } else if info.provider == .twitch || pageMetadata != nil {
            // Twitch has no unauthenticated oEmbed; use the page's OpenGraph tags.
            var metadata = pageMetadata
            if metadata == nil {
                if policy.allows(url) {
                    switch try await attempt({ try await fetchPage(url, policy: policy).metadata }) {
                    case .success(let fetched): metadata = fetched
                    case .refused: degraded = true
                    case .failed: break
                    }
                } else {
                    degraded = true
                }
            }
            if let metadata {
                embed.title = embed.title ?? metadata.title
                summary = metadata.summary
                if let image = metadata.imageURL {
                    embed.thumbnailURL = image
                    if let width = metadata.imageWidth, let height = metadata.imageHeight {
                        imageSize = CGSize(width: width, height: height)
                    }
                }
                declaresAdult = metadata.declaresAdult
            }
        }

        let preview = LinkPreview(
            url: url,
            finalURL: finalURL,
            kind: .embed,
            title: embed.title,
            summary: summary,
            siteName: siteName,
            imageURL: embed.thumbnailURL,
            imageSize: imageSize,
            themeColor: info.provider.brandColor,
            embed: embed,
            declaresAdult: declaresAdult
        )
        return PreviewFetchResult(preview: preview, degraded: degraded)
    }

    private func fetchOEmbed(_ endpoint: URL, policy: MediaPolicy) async throws -> OEmbedResponse {
        let request = makeRequest(endpoint, accept: "application/json")
        let options = HTTPFetcher.Options(
            maxBytes: Self.maxJSONBytes,
            overflow: .fail,
            checkRedirect: { policy.requestError(for: $0) }
        )
        let result = try await HTTPFetcher.fetch(request, session: session, options: options)
        return try JSONDecoder().decode(OEmbedResponse.self, from: result.body)
    }

    // MARK: - Pages

    private enum PageFetch {
        case html(HTMLMetadata, finalURL: URL, contentType: String?)
        case media(LinkPreview.Kind, finalURL: URL, contentType: String?, declaresAdult: Bool)

        var metadata: HTMLMetadata? {
            if case .html(let metadata, _, _) = self { return metadata }
            return nil
        }
    }

    private func pagePreview(_ url: URL, policy: MediaPolicy) async throws -> PreviewFetchResult {
        switch try await fetchPage(url, policy: policy) {
        case .media(let kind, let finalURL, let contentType, let declaresAdult):
            return PreviewFetchResult(preview: LinkPreview(
                url: url, finalURL: finalURL, kind: kind, mediaURL: url, contentType: contentType,
                declaresAdult: declaresAdult
            ))

        case .html(let metadata, let finalURL, let contentType):
            // A shortener or redirect may land on a known video site.
            if finalURL != url, case .embed(let info) = MediaClassifier.classify(finalURL) {
                return try await embedPreview(url, finalURL: finalURL, info: info, policy: policy, pageMetadata: metadata)
            }

            var metadata = metadata
            var degraded = false
            if metadata.title == nil || metadata.imageURL == nil, let endpoint = metadata.oEmbedURL {
                var oEmbed: OEmbedResponse?
                if policy.allows(endpoint) {
                    switch try await attempt({ try await fetchOEmbed(endpoint, policy: policy) }) {
                    case .success(let response): oEmbed = response
                    case .refused: degraded = true
                    case .failed: break
                    }
                } else {
                    degraded = true
                }
                if let oEmbed {
                    metadata.title = metadata.title ?? oEmbed.title
                    metadata.siteName = metadata.siteName ?? oEmbed.providerName
                    if metadata.imageURL == nil, let thumbnail = Self.webURL(oEmbed.thumbnailURL) {
                        metadata.imageURL = thumbnail
                        metadata.imageWidth = oEmbed.thumbnailWidth.map { Int($0) }
                        metadata.imageHeight = oEmbed.thumbnailHeight.map { Int($0) }
                    }
                }
            }

            var imageSize: CGSize?
            if metadata.imageURL != nil, let width = metadata.imageWidth, let height = metadata.imageHeight {
                imageSize = CGSize(width: width, height: height)
            }
            let favicon = metadata.faviconURL ?? URL(string: "/favicon.ico", relativeTo: finalURL)?.absoluteURL
            let preview = LinkPreview(
                url: url,
                finalURL: finalURL,
                kind: .page,
                title: metadata.title ?? Self.displayHost(finalURL),
                summary: metadata.summary,
                siteName: metadata.siteName,
                imageURL: metadata.imageURL,
                imageSize: imageSize,
                faviconURL: favicon,
                themeColor: metadata.themeColor,
                contentType: contentType,
                declaresAdult: metadata.declaresAdult
            )
            return PreviewFetchResult(preview: preview, degraded: degraded)
        }
    }

    private func fetchPage(_ url: URL, policy: MediaPolicy) async throws -> PageFetch {
        let maxImageBytes = policy.maxImageBytes
        let options = HTTPFetcher.Options(
            maxBytes: Self.maxHTMLBytes,
            overflow: .truncate,
            checkRedirect: { policy.requestError(for: $0) },
            inspectResponse: { response in
                guard let mime = response.normalizedMIMEType else { return .read }
                if Self.isHTML(mime) || mime == "application/octet-stream" { return .read }
                if mime.hasPrefix("image/") {
                    if response.expectedContentLength > Int64(maxImageBytes) { throw MediaError.tooLarge }
                    return .skip
                }
                if mime.hasPrefix("video/") { return .skip }
                throw MediaError.unsupportedContent
            },
            shouldStop: { body, chunkStart in
                Self.containsHeadEnd(body, from: max(0, chunkStart - 6))
            }
        )
        let result = try await HTTPFetcher.fetch(
            makeRequest(url, accept: Self.htmlAccept), session: session, options: options
        )
        let finalURL = result.finalURL ?? url
        let mime = result.mimeType
        let ratedAdult = Self.ratingDeclaresAdult(result.response)

        if let mime, mime.hasPrefix("image/") {
            return .media(.image, finalURL: finalURL, contentType: mime, declaresAdult: ratedAdult)
        }
        if let mime, mime.hasPrefix("video/") {
            return .media(.video, finalURL: finalURL, contentType: mime, declaresAdult: ratedAdult)
        }
        if let sniffed = Self.sniffImageType(result.body) {
            // Served without a useful Content-Type; ImageLoader applies the byte cap later.
            return .media(.image, finalURL: finalURL, contentType: sniffed, declaresAdult: ratedAdult)
        }
        if mime == "application/octet-stream" { throw MediaError.unsupportedContent }

        let html = HTMLTextDecoder.decode(
            result.body,
            contentType: result.response.value(forHTTPHeaderField: "Content-Type"),
            isTruncated: !result.isComplete
        )
        var metadata = HTMLMetadataParser.parse(html: html, baseURL: finalURL)
        if ratedAdult { metadata.declaresAdult = true }
        return .html(metadata, finalURL: finalURL, contentType: mime ?? "text/html")
    }

    // MARK: - Helpers

    private func makeRequest(_ url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: Self.requestTimeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(Self.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        return request
    }

    private enum Attempt<T: Sendable>: Sendable {
        case success(T)
        /// The policy refused a request (directly or on a redirect).
        case refused
        case failed
    }

    /// Runs a best-effort `operation`; only cancellation is rethrown.
    private func attempt<T: Sendable>(_ operation: () async throws -> T) async throws -> Attempt<T> {
        do {
            return .success(try await operation())
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MediaError where error.isPolicyRefusal {
            return .refused
        } catch {
            return .failed
        }
    }

    /// A `Rating` response header declaring adult content.
    static func ratingDeclaresAdult(_ response: HTTPURLResponse) -> Bool {
        guard let rating = response.value(forHTTPHeaderField: "Rating") else { return false }
        return HTMLMetadataParser.isAdultRating(rating) || rating.lowercased().contains("rtalabel.org")
    }

    /// An absolute `http(s)` URL from an oEmbed field.
    static func webURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host() != nil
        else { return nil }
        return url
    }

    static let acceptLanguage: String = {
        let languages = Locale.preferredLanguages.prefix(4)
        guard !languages.isEmpty else { return "en;q=0.9, *;q=0.5" }
        var parts: [String] = []
        for (index, language) in languages.enumerated() {
            parts.append(index == 0 ? language : "\(language);q=\(String(format: "%.1f", 1.0 - Double(index) * 0.1))")
        }
        parts.append("*;q=0.5")
        return parts.joined(separator: ", ")
    }()

    static func isHTML(_ mime: String) -> Bool {
        mime == "text/html" || mime == "application/xhtml+xml"
    }

    static func displayHost(_ url: URL) -> String {
        var host = url.host(percentEncoded: false) ?? url.absoluteString
        if host.lowercased().hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Case-insensitive search for `</head` starting at `offset`.
    static func containsHeadEnd(_ data: Data, from offset: Int) -> Bool {
        let needle: [UInt8] = Array("</head".utf8)
        guard data.count - offset >= needle.count else { return false }
        return data.withUnsafeBytes { raw -> Bool in
            let bytes = raw.bindMemory(to: UInt8.self)
            var i = offset
            let last = bytes.count - needle.count
            while i <= last {
                if bytes[i] == 0x3C {   // '<'
                    var j = 1
                    while j < needle.count, HTMLTagScanner.lowercase(bytes[i + j]) == needle[j] { j += 1 }
                    if j == needle.count { return true }
                }
                i += 1
            }
            return false
        }
    }

    /// Recognizes common image formats by their magic bytes, for servers
    /// that send no or a generic Content-Type.
    static func sniffImageType(_ data: Data) -> String? {
        let head = [UInt8](data.prefix(16))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if head.starts(with: Array("GIF87a".utf8)) || head.starts(with: Array("GIF89a".utf8)) { return "image/gif" }
        if head.count >= 12, head.starts(with: Array("RIFF".utf8)), Array(head[8..<12]) == Array("WEBP".utf8) {
            return "image/webp"
        }
        return nil
    }
}
