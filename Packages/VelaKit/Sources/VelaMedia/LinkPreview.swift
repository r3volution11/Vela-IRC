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
    /// The direct image or video URL for `.image` and `.video`.
    public var mediaURL: URL?
    public var embed: EmbedInfo?
    /// MIME type of the main response, without parameters (e.g. `text/html`).
    public var contentType: String?
    public var fetchedAt: Date

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
        contentType: String? = nil,
        fetchedAt: Date = Date()
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
        self.contentType = contentType
        self.fetchedAt = fetchedAt
    }
}
