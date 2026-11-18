// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// A fetched preview plus whether the policy refused part of the work.
struct PreviewFetchResult: Sendable {
    var preview: LinkPreview
    /// A request (oEmbed, a page for metadata) was refused by the policy, or
    /// the page was a bot check the browser engine wasn't allowed to (or
    /// couldn't) get past, so the preview lacks something a more permissive
    /// policy, or another try, would add. Such previews are cached in memory
    /// only, for the policy that built them.
    var degraded = false
}

/// Does the network work behind `LinkPreviewService`, off the service's actor.
///
/// Every request and redirect hop is checked with `MediaPolicy.allows(_:)`;
/// image, thumbnail and favicon URLs are recorded as found and checked with
/// `allowsImage(_:)` only when they are loaded.
///
/// A page link whose page turns out to be a bot check, or an empty page made
/// only of scripts (`BotCheckDetector`), is loaded again with `browser`, a
/// real browser engine, when `allowsBrowserFallback` says so. Embeds, GIF
/// sites, Reddit and media files never are: they have their own ways in.
struct PreviewFetcher: Sendable {
    let session: URLSession
    let userAgent: String
    var browser: (any BrowserMetadataLoading)?

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
        case .gif(let info):
            return try await gifPreview(url, info: info, policy: policy)
        case .page:
            // Reddit shows a challenge page instead of a post; its oEmbed says more.
            if let post = RedditLinks.post(url) {
                return try await redditPostPreview(url, finalURL: url, post: post, policy: policy)
            }
            return try await pagePreview(url, policy: policy)
        }
    }

    // MARK: - Reddit

    /// A `v.redd.it` video: where it redirects names the post (and its
    /// subreddit), the post's oEmbed gives the title and author, and the HLS
    /// playlist the shape and whether there's sound. Each is best effort:
    /// whatever fails (Reddit's rate limit, say) leaves the facade plainer,
    /// and the preview is kept in memory only, so it's tried again later.
    private func redditVideoPreview(_ url: URL, info: EmbedInfo, policy: MediaPolicy) async throws -> PreviewFetchResult {
        var embed = info
        var degraded = false
        var finalURL = url
        var declaresAdult: Bool?

        if let videoPage = info.canonicalPageURL, policy.allows(videoPage) {
            switch try await attempt({ try await finalLocation(of: videoPage, policy: policy) }) {
            case .success(let landed): finalURL = landed
            case .refused, .failed: degraded = true
            }
        }
        if RedditLinks.isAgeGate(finalURL) { declaresAdult = true }

        let post = RedditLinks.post(finalURL)
        embed.community = post?.community
        if let post, let endpoint = OEmbedEndpoint.reddit(post: post.oEmbedURL) {
            if policy.allows(endpoint) {
                switch try await attempt({ try await fetchOEmbed(endpoint, policy: policy) }) {
                case .success(let oEmbed):
                    embed.title = oEmbed.title
                    embed.authorName = oEmbed.authorName.map { "u/" + $0 }
                    embed.community = embed.community ?? RedditLinks.community(inEmbedHTML: oEmbed.html)
                case .refused, .failed:
                    degraded = true
                }
            } else {
                degraded = true
            }
        }
        embed.title = embed.title ?? RedditLinks.title(fromSlug: post?.slug)

        if policy.allows(info.embedURL) {
            let playlist = info.embedURL
            switch try await attempt({ try await fetchText(playlist, accept: HLSPlaylist.accept, maxBytes: HLSPlaylist.maxBytes, policy: policy) }) {
            case .success(let text):
                if let summary = HLSPlaylist.summary(text) {
                    embed.isGIF = !summary.hasAudio
                    if let ratio = summary.aspectRatio, (0.2...5).contains(ratio) { embed.aspectRatio = ratio }
                }
            case .refused, .failed:
                degraded = true
            }
        }

        let preview = LinkPreview(
            url: url,
            finalURL: post?.canonicalURL ?? finalURL,
            kind: .embed,
            title: embed.title,
            summary: [embed.community, embed.authorName].compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
            siteName: EmbedProvider.reddit.displayName,
            faviconURL: RedditLinks.faviconURL,
            themeColor: EmbedProvider.reddit.brandColor,
            embed: embed,
            declaresAdult: declaresAdult
        )
        return PreviewFetchResult(preview: preview, degraded: degraded)
    }

    /// A link to a Reddit post: a card from the post's oEmbed (its page is
    /// a challenge for browsers). Without it, the title in the address.
    private func redditPostPreview(
        _ url: URL, finalURL: URL, post: RedditLinks.Post, policy: MediaPolicy
    ) async throws -> PreviewFetchResult {
        var title: String?
        var author: String?
        var community = post.community
        var degraded = false
        if let endpoint = OEmbedEndpoint.reddit(post: post.oEmbedURL) {
            if policy.allows(endpoint) {
                switch try await attempt({ try await fetchOEmbed(endpoint, policy: policy) }) {
                case .success(let oEmbed):
                    title = oEmbed.title
                    author = oEmbed.authorName
                    community = community ?? RedditLinks.community(inEmbedHTML: oEmbed.html)
                case .refused, .failed:
                    degraded = true
                }
            } else {
                degraded = true
            }
        }
        let summary = [community, author.map { "Posted by u/\($0)" }].compactMap { $0 }.joined(separator: " · ")
        return PreviewFetchResult(preview: LinkPreview(
            url: url,
            finalURL: finalURL,
            kind: .page,
            title: title ?? RedditLinks.title(fromSlug: post.slug) ?? "Reddit post",
            summary: summary.nilIfEmpty,
            siteName: EmbedProvider.reddit.displayName,
            faviconURL: RedditLinks.faviconURL,
            themeColor: EmbedProvider.reddit.brandColor,
            contentType: "text/html"
        ), degraded: degraded)
    }

    /// Where `url` redirects to, without reading the page there.
    private func finalLocation(of url: URL, policy: MediaPolicy) async throws -> URL {
        let options = HTTPFetcher.Options(
            maxBytes: Self.maxHTMLBytes,
            overflow: .truncate,
            checkRedirect: { policy.requestError(for: $0) },
            inspectResponse: { _ in .skip }
        )
        let result = try await HTTPFetcher.fetch(makeRequest(url, accept: Self.htmlAccept), session: session, options: options)
        return result.finalURL ?? url
    }

    /// A small text file (a playlist).
    private func fetchText(_ url: URL, accept: String, maxBytes: Int, policy: MediaPolicy) async throws -> String {
        let options = HTTPFetcher.Options(maxBytes: maxBytes, overflow: .fail, checkRedirect: { policy.requestError(for: $0) })
        let result = try await HTTPFetcher.fetch(makeRequest(url, accept: accept), session: session, options: options)
        return String(decoding: result.body, as: UTF8.self)
    }

    // MARK: - GIF sites

    /// A GIF site's animation.
    ///
    /// - A link to the animation itself (a Tenor or GIPHY file, an Imgur
    ///   `.gifv`) needs no request: the view loads the rendition, with the
    ///   policy's checks, when it is drawn.
    /// - A page link the classifier resolved (`giphy.com/gifs/…-<id>`) is
    ///   only fetched for its title, which the decider asks for when a text
    ///   card is shown instead (a text-only site). That is best effort.
    /// - Any other page (`tenor.com/view/…`, `tenor.com/<code>.gif`,
    ///   `gph.is/…`) is fetched, redirects and all, and the animation read
    ///   from its OpenGraph tags, or from where a short link led. A page
    ///   without one gets an ordinary link card.
    private func gifPreview(_ url: URL, info: GIFInfo, policy: MediaPolicy) async throws -> PreviewFetchResult {
        let offline = PreviewFetchResult(preview: LinkPreview(
            url: url, kind: .gif, siteName: info.provider.displayName, mediaURL: info.primaryURL, gif: info
        ))
        if info.isResolved {
            let ext = url.pathExtension.lowercased()
            let isFile = ext == "gifv" || MediaClassifier.imageExtensions.contains(ext)
                || MediaClassifier.videoExtensions.contains(ext)
            if isFile { return offline }
            switch try await attempt({ try await fetchGIFPage(url, policy: policy) }) {
            case .success(let fetched):
                return gifPagePreview(url, fetched: fetched, info: info) ?? offline
            case .refused:
                var degraded = offline
                degraded.degraded = true
                return degraded
            case .failed:
                return offline
            }
        }

        let fetched = try await fetchPage(url, policy: policy)
        if let preview = gifPagePreview(url, fetched: fetched, info: info) { return preview }
        return try await pagePreview(url, fetched: fetched, policy: policy, mayUseBrowser: false)
    }

    /// A GIF page, after one same-site `<meta http-equiv="refresh">`: GIPHY
    /// answers a page's other address (`/gifs/<id>` or `/gifs/<slug>-<id>`)
    /// with a page that only redirects to the one with the tags.
    private func fetchGIFPage(_ url: URL, policy: MediaPolicy) async throws -> PageFetch {
        let fetched = try await fetchPage(url, policy: policy)
        guard case .html(let metadata, let finalURL, _, _) = fetched, metadata.title == nil,
              let target = metadata.refreshURL, target != finalURL,
              SiteRules.normalizedHost(target) == SiteRules.normalizedHost(finalURL), policy.allows(target)
        else { return fetched }
        return try await fetchPage(target, policy: policy)
    }

    /// The animation a fetched GIF page (or what a short link led to) shows, if any.
    private func gifPagePreview(_ url: URL, fetched: PageFetch, info: GIFInfo) -> PreviewFetchResult? {
        switch fetched {
        case .media(let kind, let finalURL, let contentType, let declaresAdult):
            var gif = GIFInfo(provider: info.provider)
            if kind == .video { gif.videoURL = url } else { gif.imageURL = url }
            return PreviewFetchResult(preview: LinkPreview(
                url: url, finalURL: finalURL, kind: .gif, siteName: info.provider.displayName,
                mediaURL: url, gif: gif, contentType: contentType, declaresAdult: declaresAdult
            ))

        case .html(let metadata, let finalURL, let contentType, _):
            var gif: GIFInfo?
            if info.isResolved {
                gif = info
            } else if finalURL != url, case .gif(let landed) = MediaClassifier.classify(finalURL), landed.isResolved {
                // gph.is/… → giphy.com/gifs/…-<id>: the address names the animation.
                gif = landed
            } else {
                var isSticker = info.isSticker
                if case .gif(let landed) = MediaClassifier.classify(finalURL), landed.isSticker { isSticker = true }
                gif = GIFResolver.resolve(metadata, provider: info.provider, isSticker: isSticker)
            }
            guard var gif else { return nil }
            gif.title = gif.title ?? metadata.title

            var imageSize: CGSize?
            if metadata.imageURL != nil, let width = metadata.imageWidth, let height = metadata.imageHeight {
                imageSize = CGSize(width: width, height: height)
            }
            return PreviewFetchResult(preview: LinkPreview(
                url: url,
                finalURL: finalURL,
                kind: .gif,
                title: metadata.title ?? Self.displayHost(finalURL),
                summary: metadata.summary,
                siteName: metadata.siteName ?? info.provider.displayName,
                imageURL: metadata.imageURL,
                imageSize: imageSize,
                faviconURL: metadata.faviconURL ?? URL(string: "/favicon.ico", relativeTo: finalURL)?.absoluteURL,
                themeColor: metadata.themeColor,
                mediaURL: gif.primaryURL,
                gif: gif,
                contentType: contentType,
                declaresAdult: metadata.declaresAdult
            ))
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
        if info.provider == .reddit { return try await redditVideoPreview(url, info: info, policy: policy) }
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
        case html(HTMLMetadata, finalURL: URL, contentType: String?, check: PageCheck?)
        case media(LinkPreview.Kind, finalURL: URL, contentType: String?, declaresAdult: Bool)

        var metadata: HTMLMetadata? {
            if case .html(let metadata, _, _, _) = self { return metadata }
            return nil
        }
    }

    /// A page that was a bot check (or a script-only shell), and the status it came with.
    private struct PageCheck {
        var botCheck: BotCheck
        var status: Int
    }

    /// A page link: the page, and the browser engine if it's a bot check.
    private func pagePreview(_ url: URL, policy: MediaPolicy) async throws -> PreviewFetchResult {
        let readsChallenges = browser != nil && policy.browserFallback
        let fetched = try await fetchPage(url, policy: policy, readsChallenges: readsChallenges)
        return try await pagePreview(url, fetched: fetched, policy: policy, mayUseBrowser: true)
    }

    private func pagePreview(
        _ url: URL, fetched: PageFetch, policy: MediaPolicy, mayUseBrowser: Bool
    ) async throws -> PreviewFetchResult {
        switch fetched {
        case .media(let kind, let finalURL, let contentType, let declaresAdult):
            return PreviewFetchResult(preview: LinkPreview(
                url: url, finalURL: finalURL, kind: kind, mediaURL: url, contentType: contentType,
                declaresAdult: declaresAdult
            ))

        case .html(var metadata, var finalURL, let contentType, let check):
            // A shortener or redirect may land on a known video site.
            if finalURL != url, case .embed(let info) = MediaClassifier.classify(finalURL) {
                return try await embedPreview(url, finalURL: finalURL, info: info, policy: policy, pageMetadata: metadata)
            }
            // … or on a Reddit post (`redd.it/<id>`, a share link), or its age check.
            if finalURL != url, let post = RedditLinks.post(finalURL) {
                return try await redditPostPreview(url, finalURL: finalURL, post: post, policy: policy)
            }

            var degraded = false
            var usedBrowser = false
            if let check, mayUseBrowser {
                // A bot check or a script-only page: the browser engine sees the real one.
                if let page = try await browserPage(url, finalURL: finalURL, metadata: metadata, policy: policy) {
                    let ratedAdult = metadata.declaresAdult
                    metadata = page.metadata
                    if ratedAdult { metadata.declaresAdult = true }
                    finalURL = page.finalURL
                    usedBrowser = true
                } else if !(200..<300).contains(check.status) {
                    // Without it, a check served as an error is the error it was before.
                    throw MediaError.http(check.status)
                } else {
                    // Kept in memory only: another try (or the setting turned on) may do better.
                    degraded = true
                }
            }
            if RedditLinks.isAgeGate(finalURL) { metadata.declaresAdult = true }
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
                declaresAdult: metadata.declaresAdult,
                loadedWithBrowserEngine: usedBrowser ? true : nil
            )
            return PreviewFetchResult(preview: preview, degraded: degraded)
        }
    }

    // MARK: - Browser engine

    /// The page as the browser engine sees it, when the fallback is allowed
    /// and gets past the check; nil otherwise.
    private func browserPage(_ url: URL, finalURL: URL, metadata: HTMLMetadata, policy: MediaPolicy) async throws -> BrowserPage? {
        guard let browser, Self.allowsBrowserFallback(url: url, finalURL: finalURL, metadata: metadata, policy: policy)
        else { return nil }
        do {
            let page = try await browser.load(finalURL, policy: policy)
            // The engine checks every navigation; this is the last word.
            return policy.allows(page.finalURL) ? page : nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    /// Whether a page link whose page was a bot check may be loaded in the
    /// browser engine: the setting is on, the policy lets Vela request both
    /// the link and where it led (so never a blocked site, an adult-listed
    /// one, a private network address or a non-web URL), neither belongs to
    /// a site Vela has a dedicated way into (video and GIF sites, Reddit),
    /// and the page doesn't label itself adult while adult previews are hidden.
    ///
    /// "Text only" sites qualify: the engine never loads images. Auto-load
    /// and per-channel media need no check here: with either off, nothing is
    /// fetched until the user clicks Load (`PreviewDecider`).
    static func allowsBrowserFallback(url: URL, finalURL: URL, metadata: HTMLMetadata, policy: MediaPolicy) -> Bool {
        guard policy.browserFallback else { return false }
        if metadata.declaresAdult, policy.filterAdultSites { return false }
        for target in [url, finalURL] {
            guard policy.allows(target), case .page = MediaClassifier.classify(target),
                  RedditLinks.post(target) == nil, !RedditLinks.isAgeGate(target),
                  let host = SiteRules.normalizedHost(target), SiteRules.providerMainDomain(forHost: host) == nil
            else { return false }
        }
        return true
    }

    /// Fetches a page's `<head>` (or finds it's an image or video).
    ///
    /// With `readsChallenges`, a 403, 405, 429 or 503 answer is read too, to
    /// tell a bot check from an ordinary error page (which still fails with
    /// `MediaError.http`). Any page is checked with `BotCheckDetector`.
    private func fetchPage(_ url: URL, policy: MediaPolicy, readsChallenges: Bool = false) async throws -> PageFetch {
        let maxImageBytes = policy.maxImageBytes
        let options = HTTPFetcher.Options(
            maxBytes: Self.maxHTMLBytes,
            overflow: .truncate,
            acceptsStatus: { status in
                (200..<300).contains(status) || (readsChallenges && BotCheckDetector.challengeStatuses.contains(status))
            },
            checkRedirect: { policy.requestError(for: $0) },
            inspectResponse: { response in
                let isError = !(200..<300).contains(response.statusCode)
                guard let mime = response.normalizedMIMEType else {
                    if isError { throw MediaError.http(response.statusCode) }
                    return .read
                }
                if Self.isHTML(mime) { return .read }
                if isError { throw MediaError.http(response.statusCode) }
                if mime == "application/octet-stream" { return .read }
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
        let status = result.response.statusCode
        let check = BotCheckDetector.assess(result.response, html: html, metadata: metadata)
            .map { PageCheck(botCheck: $0, status: status) }
        if !(200..<300).contains(status), check == nil { throw MediaError.http(status) }
        return .html(metadata, finalURL: finalURL, contentType: mime ?? "text/html", check: check)
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

    /// An absolute `http(s)` URL from an oEmbed field. A protocol-relative
    /// one (`//cdn.example/x.jpg`, as Streamable's thumbnails are) is https.
    static func webURL(_ raw: String?) -> URL? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if text.hasPrefix("//") { text = "https:" + text }
        guard let url = URL(string: text),
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

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
