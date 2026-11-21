// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// GIPHY (https://developers.giphy.com/docs/api/), with the user's own key.
///
/// - Requests go from the Mac to `api.giphy.com`, with the content rating
///   as `rating`. No `random_id` or `customer_id`, and no analytics
///   pingbacks: GIPHY recommends them, it doesn't require them, and Vela
///   doesn't track.
/// - Media URLs are used as GIPHY returns them, tracking token (`cid`)
///   included: GIPHY's terms forbid stripping them. The link that's sent
///   carries it to everyone who sees it, which Settings says.
/// - Responses aren't kept once the picker closes: GIPHY's terms forbid
///   caching them.
/// - "Powered by GIPHY" shows under the results, as GIPHY requires.
public struct GIPHYProvider: GIFSearchProvider {
    public static let apiBase = "https://api.giphy.com/v1/gifs/"
    /// GIPHY refuses longer searches (414).
    static let maxQueryLength = 50
    /// The furthest GIPHY pages: `offset` up to 4,999 for search, 499 for trending.
    static let maxSearchOffset = 4_999
    static let maxTrendingOffset = 499

    public var id: GIFSearchServiceID { .giphy }
    public var displayName: String { "GIPHY" }
    public var searchPlaceholder: String { "Search GIPHY" }
    public var attribution: String { "Powered by GIPHY" }
    public var pageSize: Int { 24 }
    public var allowsResponseCaching: Bool { false }
    public var allowsThumbnailCaching: Bool { false }

    public init() {}

    /// `rating`: GIPHY's own ratings.
    public static func rating(for rating: GIFContentRating) -> String {
        switch rating {
        case .g: "g"
        case .pg: "pg"
        case .pg13: "pg-13"
        case .r: "r"
        }
    }

    public func request(for query: GIFQuery, page: GIFPageToken?, rating: GIFContentRating, apiKey: String) -> URLRequest? {
        guard !apiKey.isEmpty else { return nil }
        let endpoint = query == .trending ? "trending" : "search"
        guard var components = URLComponents(string: Self.apiBase + endpoint) else { return nil }
        var items = [URLQueryItem(name: "api_key", value: apiKey)]
        if let text = query.text { items.append(URLQueryItem(name: "q", value: String(text.prefix(Self.maxQueryLength)))) }
        let offset: Int = if case .offset(let offset) = page { max(0, offset) } else { 0 }
        items += [
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "rating", value: Self.rating(for: rating)),
        ]
        components.queryItems = items
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url.map(GIFSearchSupport.jsonRequest)
    }

    public func decode(_ data: Data, response: HTTPURLResponse, query: GIFQuery, page: GIFPageToken?) throws(GIFSearchError) -> GIFSearchPage {
        if let error = GIFSearchSupport.error(forStatus: response.statusCode) { throw error }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw .badResponse }
        if let status = envelope.meta?.status?.value, let error = GIFSearchSupport.error(forStatus: status) { throw error }
        // "meta.status=200, meta.response_id="" and the rest of the API
        // object is empty. This should be treated as an error state."
        if envelope.meta?.responseID == "", envelope.data.isEmpty { throw .server(503) }

        let results = envelope.data.compactMap(Self.result)
        let requested: Int = if case .offset(let offset) = page { offset } else { 0 }
        let offset = envelope.pagination?.offset?.value ?? requested
        let count = envelope.pagination?.count?.value ?? envelope.data.count
        let nextOffset = offset + count
        var hasMore = count > 0
        if let total = envelope.pagination?.totalCount?.value { hasMore = hasMore && nextOffset < total }
        else { hasMore = hasMore && count >= pageSize }
        hasMore = hasMore && nextOffset <= (query == .trending ? Self.maxTrendingOffset : Self.maxSearchOffset)
        return GIFSearchPage(results: results, next: hasMore ? .offset(nextOffset) : nil)
    }

    public func websiteURL(for query: GIFQuery) -> URL {
        if let text = query.text, let url = GIFSearchSupport.searchPageURL(base: "https://giphy.com/search/", term: text) {
            return url
        }
        return URL(string: "https://giphy.com/trending-gifs")!
    }

    // MARK: Reading results

    static func result(_ gif: GIF) -> GIFSearchResult? {
        guard let images = gif.images else { return nil }
        let stills = [images.fixedWidthSmallStill, images.fixedWidthStill].compactMap { $0?.still }
        let animations = [images.fixedWidthSmall, images.fixedWidth].compactMap { $0?.animation }
        // The GIF itself, the way GIPHY gives it (tracking token and all).
        let share = images.original?.still ?? images.downsized?.still ?? gif.url.flatMap(URL.init(string:)).map { GIFRendition(url: $0) }
        guard let share else { return nil }
        let sized = [images.original?.still, images.fixedWidth?.still].compactMap { $0 }.first { $0.pixelWidth > 0 && ($0.height ?? 0) > 0 }
        let aspect = sized.map { CGFloat($0.pixelWidth) / CGFloat(max(1, $0.height ?? 1)) } ?? 1
        return GIFSearchResult(
            id: gif.id?.value ?? share.url.absoluteString,
            title: gif.title ?? "",
            stills: stills.sorted { $0.pixelWidth < $1.pixelWidth },
            animations: animations.sorted { $0.pixelWidth < $1.pixelWidth },
            shareURL: share.url,
            attribution: attribution(for: gif),
            aspectRatio: aspect
        )
    }

    /// "@username", else the site it came from.
    static func attribution(for gif: GIF) -> String? {
        if let name = gif.user?.username ?? gif.username, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "@" + name
        }
        if let source = gif.sourceTLD, !source.isEmpty { return source }
        return nil
    }

    // MARK: Response format

    struct Envelope: Decodable {
        var data: [GIF]
        var pagination: Pagination?
        var meta: Meta?

        enum CodingKeys: String, CodingKey { case data, pagination, meta }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            data = (try? container.decode([Lossy<GIF>].self, forKey: .data))?.compactMap(\.value) ?? []
            pagination = try? container.decodeIfPresent(Pagination.self, forKey: .pagination)
            meta = try? container.decodeIfPresent(Meta.self, forKey: .meta)
        }
    }

    struct Pagination: Decodable {
        var totalCount: FlexibleInt?
        var count: FlexibleInt?
        var offset: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case count, offset
        }
    }

    struct Meta: Decodable {
        var status: FlexibleInt?
        var msg: String?
        var responseID: String?

        enum CodingKeys: String, CodingKey {
            case status, msg
            case responseID = "response_id"
        }
    }

    struct GIF: Decodable {
        var id: FlexibleID?
        var title: String?
        var url: String?
        var username: String?
        var sourceTLD: String?
        var user: User?
        var images: Images?

        enum CodingKeys: String, CodingKey {
            case id, title, url, username, user, images
            case sourceTLD = "source_tld"
        }
    }

    struct User: Decodable {
        var username: String?
    }

    struct Images: Decodable {
        var original: Image?
        var downsized: Image?
        var fixedWidth: Image?
        var fixedWidthStill: Image?
        var fixedWidthSmall: Image?
        var fixedWidthSmallStill: Image?

        enum CodingKeys: String, CodingKey {
            case original, downsized
            case fixedWidth = "fixed_width"
            case fixedWidthStill = "fixed_width_still"
            case fixedWidthSmall = "fixed_width_small"
            case fixedWidthSmallStill = "fixed_width_small_still"
        }

        init(from decoder: any Decoder) throws {
            // Some GIFs lack some renditions; one that can't be read is skipped.
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func image(_ key: CodingKeys) -> Image? { (try? container.decodeIfPresent(Image.self, forKey: key)) ?? nil }
            original = image(.original)
            downsized = image(.downsized)
            fixedWidth = image(.fixedWidth)
            fixedWidthStill = image(.fixedWidthStill)
            fixedWidthSmall = image(.fixedWidthSmall)
            fixedWidthSmallStill = image(.fixedWidthSmallStill)
        }
    }

    struct Image: Decodable {
        var url: String?
        var width: FlexibleInt?
        var height: FlexibleInt?
        var size: FlexibleInt?
        var webp: String?
        var webpSize: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case url, width, height, size, webp
            case webpSize = "webp_size"
        }

        private func rendition(_ string: String?, bytes: Int?) -> GIFRendition? {
            guard let string, let url = URL(string: string), url.scheme == "https" || url.scheme == "http" else { return nil }
            return GIFRendition(url: url, width: width?.value, height: height?.value, byteCount: bytes)
        }

        /// The `url` rendition (a GIF, or a still for `_still` renditions).
        var still: GIFRendition? { rendition(url, bytes: size?.value) }

        /// The animated WebP, else the GIF.
        var animation: GIFRendition? { rendition(webp, bytes: webpSize?.value) ?? still }
    }
}
