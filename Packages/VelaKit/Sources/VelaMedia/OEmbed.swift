// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The subset of an oEmbed JSON response Vela uses.
struct OEmbedResponse: Decodable, Sendable, Hashable {
    var type: String?
    var title: String?
    var authorName: String?
    var providerName: String?
    var thumbnailURL: String?
    var thumbnailWidth: Double?
    var thumbnailHeight: Double?
    var width: Double?
    var height: Double?
    /// The embed markup (Reddit's names the subreddit).
    var html: String?

    private enum CodingKeys: String, CodingKey {
        case type, title, width, height, html
        case authorName = "author_name"
        case providerName = "provider_name"
        case thumbnailURL = "thumbnail_url"
        case thumbnailWidth = "thumbnail_width"
        case thumbnailHeight = "thumbnail_height"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = Self.string(container, .type)
        title = Self.string(container, .title)
        authorName = Self.string(container, .authorName)
        providerName = Self.string(container, .providerName)
        thumbnailURL = Self.string(container, .thumbnailURL)
        thumbnailWidth = Self.number(container, .thumbnailWidth)
        thumbnailHeight = Self.number(container, .thumbnailHeight)
        width = Self.number(container, .width)
        height = Self.number(container, .height)
        html = Self.string(container, .html)
    }

    /// Providers disagree on types ("width": 480 vs "480" vs "100%");
    /// anything unusable becomes nil instead of failing the whole response.
    private static func number(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    private static func string(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Width / height of the player, when both are known.
    var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return width / height
    }
}

enum OEmbedEndpoint {
    /// The oEmbed endpoint for an embed, or nil for providers without an
    /// unauthenticated endpoint (Twitch) or whose endpoint needs the post the
    /// video belongs to (Reddit: `reddit(post:)`).
    static func url(for embed: EmbedInfo) -> URL? {
        guard let page = embed.canonicalPageURL else { return nil }
        let base: String
        switch embed.provider {
        case .youtube: base = "https://www.youtube.com/oembed"
        case .vimeo: base = "https://vimeo.com/api/oembed.json"
        case .streamable: base = "https://api.streamable.com/oembed.json"
        case .twitch, .reddit: return nil
        }
        // The page URL must be fully percent-encoded or its own '&' and '?'
        // would leak into the endpoint's query.
        var query = "url=" + encode(page.absoluteString)
        if embed.provider == .youtube { query = "format=json&" + query }
        return URL(string: base + "?" + query)
    }

    /// Reddit's endpoint for a post's page.
    static func reddit(post: URL) -> URL? {
        URL(string: "https://www.reddit.com/oembed?url=" + encode(post.absoluteString))
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
