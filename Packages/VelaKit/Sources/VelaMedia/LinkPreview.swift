// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// What VelaUI needs to render inline media or a link card for one URL.
public struct LinkPreview: Sendable, Codable, Hashable, Identifiable {
    public var id: String { url.absoluteString }

    public enum Kind: String, Sendable, Codable, Hashable {
        /// Show `mediaURL` inline as an image.
        case image
        /// Show `mediaURL` inline as a video.
        case video
        /// Show a thumbnail facade for `embed`; play via `EmbedPlayerHTML` on click.
        case embed
        /// Show the animation in `gif` inline, looping like a GIF.
        case gif
        /// Show a link card (title, summary, image, favicon, accent color).
        case page
    }

    /// The URL as it appeared in the message.
    public var url: URL
    /// Where the content was actually found, after redirects and rewrites.
    public var finalURL: URL
    public var kind: Kind
    public var title: String?
    public var summary: String?
    public var siteName: String?
    /// Card image (OpenGraph/Twitter image, or the video thumbnail for embeds).
    public var imageURL: URL?
    /// Size of `imageURL` in pixels, when the page declared it.
    public var imageSize: CGSize?
    public var faviconURL: URL?
    /// Accent color as `#RRGGBB`, from `<meta name="theme-color">`
    /// (or the provider's brand color for embeds).
    public var themeColor: String?
    /// The direct image or video URL for `.image` and `.video`; for `.gif`,
    /// the rendition loaded first (`GIFInfo.primaryURL`).
    public var mediaURL: URL?
    public var embed: EmbedInfo?
    /// The animation and its renditions, for `.gif`.
    public var gif: GIFInfo?
    /// MIME type of the main response, without parameters (e.g. `text/html`).
    public var contentType: String?
    public var fetchedAt: Date
    /// Whether the page labels itself adult (RTA label, `rating` meta,
    /// `og:restrictions:age`, `Rating` header). Nil when no page or header
    /// was inspected.
    public var declaresAdult: Bool?
    /// The format this preview was built with; persisted previews with an
    /// older (or missing) version are refetched.
    public var formatVersion: Int?

    /// Bumped whenever previews start carrying something old ones lack.
    /// 2: every image URL is kept (policy applies at load time) and `declaresAdult`.
    /// 3: links to GIF sites (Tenor, GIPHY, Imgur `.gifv`) are `.gif`, not page cards.
    public static let currentFormatVersion = 3

    /// Whether this preview was built in the current format.
    public var isCurrentFormat: Bool {
        (formatVersion ?? 0) >= Self.currentFormatVersion
    }

    public init(
        url: URL,
        finalURL: URL? = nil,
        kind: Kind,
        title: String? = nil,
        summary: String? = nil,
        siteName: String? = nil,
        imageURL: URL? = nil,
        imageSize: CGSize? = nil,
        faviconURL: URL? = nil,
        themeColor: String? = nil,
        mediaURL: URL? = nil,
        embed: EmbedInfo? = nil,
        gif: GIFInfo? = nil,
        contentType: String? = nil,
        fetchedAt: Date = Date(),
        declaresAdult: Bool? = nil,
        formatVersion: Int? = LinkPreview.currentFormatVersion
    ) {
        self.url = url
        self.finalURL = finalURL ?? url
        self.kind = kind
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.imageURL = imageURL
        self.imageSize = imageSize
        self.faviconURL = faviconURL
        self.themeColor = themeColor
        self.mediaURL = mediaURL
        self.embed = embed
        self.gif = gif
        self.contentType = contentType
        self.fetchedAt = fetchedAt
        self.declaresAdult = declaresAdult
        self.formatVersion = formatVersion
    }
}

// MARK: - Display

extension LinkPreview {
    /// Whether there is anything worth a card (a bare page with no metadata isn't).
    public var hasCardContent: Bool {
        hasCardContent(showingImages: true)
    }

    /// `hasCardContent` for a card that may or may not draw its image
    /// (text-only sites get no image).
    public func hasCardContent(showingImages: Bool) -> Bool {
        displayTitle != nil || displaySummary != nil || (showingImages && imageURL != nil)
    }

    /// The title, whitespace-collapsed; for direct images, videos and GIFs
    /// without one, the file name.
    public var displayTitle: String? {
        if let title = (title ?? embed?.title ?? gif?.title).map(Self.cleaned), !title.isEmpty { return title }
        if kind == .video || kind == .image || kind == .gif { return Self.fileName(mediaURL ?? finalURL) }
        return nil
    }

    public var displaySummary: String? {
        summary.map(Self.cleaned).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The site name, or the host without a leading `www.`.
    public var displaySiteName: String {
        if let siteName = siteName.map(Self.cleaned), !siteName.isEmpty { return siteName }
        return Self.displayHost(finalURL)
    }

    /// "example.com" for display, without a leading "www.".
    public static func displayHost(_ url: URL) -> String {
        var host = url.host(percentEncoded: false) ?? url.absoluteString
        if host.lowercased().hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private static func fileName(_ url: URL) -> String? {
        let last = url.lastPathComponent
        guard !last.isEmpty, last != "/" else { return nil }
        let name = cleaned(last.removingPercentEncoding ?? last)
        return name.isEmpty ? nil : name
    }

    private static func cleaned(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
