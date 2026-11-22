// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// KLIPY (https://docs.klipy.com), Vela's default GIF service.
///
/// - Requests go from the Mac to `api.klipy.com`, with the app key in the
///   path, the content rating as `content_filter`, and only the formats
///   the picker uses. No `customer_id` (nothing that identifies the user),
///   no share trigger, and ads stay off (they're switched on per key in
///   KLIPY's Partner Panel; an ad item that came anyway couldn't be shown).
/// - Media loads from the URLs KLIPY returns, unchanged, and results keep
///   KLIPY's order.
/// - The search field reads "Search KLIPY", as KLIPY requires. Under the
///   results, KLIPY's "Powered by KLIPY" logo, and on KLIPY's GIFs in the
///   conversation its watermark, as its attribution guidelines recommend.
public struct KLIPYProvider: GIFSearchProvider {
    public static let apiBase = "https://api.klipy.com/api/v1/"

    public var id: GIFSearchServiceID { .klipy }
    public var displayName: String { "KLIPY" }
    public var searchPlaceholder: String { "Search KLIPY" }
    public var attribution: String { "Powered by KLIPY" }
    public var attributionLogo: GIFAttributionLogo? { .klipy }
    public var pageSize: Int { 24 }
    public var allowsResponseCaching: Bool { true }
    /// KLIPY allows "search results thumbnails stored within a user's copy
    /// of your Application".
    public var allowsThumbnailCaching: Bool { true }

    public init() {}

    /// The formats asked for: stills (JPG), animated previews (WebP) and
    /// the GIF that's sent. Smaller answers than all five.
    static let formats = "gif,webp,jpg"

    /// `content_filter`: `high` lets through G only, `medium` up to PG,
    /// `low` up to PG-13, `off` up to R (KLIPY never returns nudity).
    public static func contentFilter(for rating: GIFContentRating) -> String {
        switch rating {
        case .g: "high"
        case .pg: "medium"
        case .pg13: "low"
        case .r: "off"
        }
    }

    public func request(for query: GIFQuery, page: GIFPageToken?, rating: GIFContentRating, apiKey: String) -> URLRequest? {
        var keyAllowed = CharacterSet.urlPathAllowed
        keyAllowed.remove(charactersIn: "/?#;%")
        guard !apiKey.isEmpty, let key = apiKey.addingPercentEncoding(withAllowedCharacters: keyAllowed) else { return nil }
        let endpoint = query == .trending ? "gifs/trending" : "gifs/search"
        guard var components = URLComponents(string: Self.apiBase + key + "/" + endpoint) else { return nil }
        var items: [URLQueryItem] = []
        if let text = query.text { items.append(URLQueryItem(name: "q", value: text)) }
        let number: Int = if case .page(let number) = page { max(1, number) } else { 1 }
        items += [
            URLQueryItem(name: "page", value: String(number)),
            URLQueryItem(name: "per_page", value: String(pageSize)),
            URLQueryItem(name: "content_filter", value: Self.contentFilter(for: rating)),
            URLQueryItem(name: "format_filter", value: Self.formats),
        ]
        components.queryItems = items
        // `+` and `&` in a search are data, not separators.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url.map(GIFSearchSupport.jsonRequest)
    }

    public func decode(_ data: Data, response: HTTPURLResponse, query: GIFQuery, page: GIFPageToken?) throws(GIFSearchError) -> GIFSearchPage {
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        if response.statusCode == 429 { throw .rateLimited }
        if let reported = envelope?.reportedError(status: response.statusCode) { throw reported }
        if let error = GIFSearchSupport.error(forStatus: response.statusCode) { throw error }
        guard let body = envelope?.data else { throw .badResponse }

        let results = body.data.compactMap(Self.result)
        let current = body.currentPage?.value ?? {
            if case .page(let number) = page { return number }
            return 1
        }()
        let hasNext = body.hasNext ?? (body.data.count >= (body.perPage?.value ?? pageSize))
        return GIFSearchPage(results: results, next: hasNext && !body.data.isEmpty ? .page(current + 1) : nil)
    }

    public func websiteURL(for query: GIFQuery) -> URL {
        if let text = query.text, let url = GIFSearchSupport.searchPageURL(base: "https://klipy.com/search/", term: text) {
            return url
        }
        return URL(string: "https://klipy.com/gifs")!
    }

    /// A GIF's page on klipy.com, from its slug: `https://klipy.com/gifs/<slug>`.
    /// Nil for a blank slug or one that isn't a single path segment.
    public static func pageURL(slug: String?) -> URL? {
        guard let slug = slug?.trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty,
              !slug.contains("/"), slug != ".", slug != ".."
        else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;%")
        guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://klipy.com/gifs/" + encoded)
    }

    // MARK: Reading results

    static func result(_ item: Item) -> GIFSearchResult? {
        // Ads (off for Vela's key) are HTML to show in a web view; anything
        // else without files has nothing to show either.
        guard item.type ?? "gif" != "ad", let file = item.file else { return nil }
        // Grid previews come from the two small sizes (xs and sm); the
        // larger ones are for sending.
        func previews(_ pick: (Formats) -> Media?) -> [GIFRendition] {
            [file.xs, file.sm].compactMap { $0.flatMap(pick)?.rendition }.sorted { $0.pixelWidth < $1.pixelWidth }
        }
        var stills = previews { $0.jpg }
        if stills.isEmpty, let still = (file.md?.jpg ?? file.hd?.jpg)?.rendition { stills = [still] }
        let animations = previews { $0.webp ?? $0.gif }
        guard let share = (file.md?.gif ?? file.hd?.gif ?? file.sm?.gif ?? file.xs?.gif)?.rendition else { return nil }
        let id = item.slug ?? item.id?.value ?? share.url.absoluteString
        let sized = (stills + animations + [share]).first { $0.pixelWidth > 0 && ($0.height ?? 0) > 0 }
        let aspect = sized.map { CGFloat($0.pixelWidth) / CGFloat(max(1, $0.height ?? 1)) } ?? 1
        return GIFSearchResult(
            id: id,
            title: item.title ?? "",
            stills: stills,
            animations: animations,
            placeholder: GIFSearchSupport.dataFromURI(item.blurPreview),
            shareURL: share.url,
            pageURL: pageURL(slug: item.slug),
            attribution: nil,
            aspectRatio: aspect
        )
    }

    // MARK: Response format

    struct Envelope: Decodable {
        var result: Bool?
        var data: Body?
        var errors: Errors?
        /// An older error shape: `{"error": {"isError": true, "errorMessage": "…"}}`.
        var error: LegacyError?

        struct Errors: Decodable {
            var message: [String]?
        }

        struct LegacyError: Decodable {
            var errorMessage: String?
        }

        /// The error the body reports, if it says the request failed.
        func reportedError(status: Int) -> GIFSearchError? {
            let messages = (errors?.message ?? []) + [error?.errorMessage].compactMap { $0 }
            guard result == false || !messages.isEmpty || (status >= 400 && data == nil) else { return nil }
            let text = messages.joined(separator: " ").lowercased()
            if text.contains("limit") || text.contains("too many") { return .rateLimited }
            if text.contains("key") || text.contains("unauthor") || status == 401 || status == 403 { return .invalidKey }
            return status >= 400 ? GIFSearchSupport.error(forStatus: status) : .badResponse
        }
    }

    struct Body: Decodable {
        var data: [Item]
        var currentPage: FlexibleInt?
        var perPage: FlexibleInt?
        var hasNext: Bool?

        enum CodingKeys: String, CodingKey {
            case data
            case currentPage = "current_page"
            case perPage = "per_page"
            case hasNext = "has_next"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // One unreadable item doesn't lose the page.
            data = (try? container.decode([Lossy<Item>].self, forKey: .data))?.compactMap(\.value) ?? []
            currentPage = try? container.decodeIfPresent(FlexibleInt.self, forKey: .currentPage)
            perPage = try? container.decodeIfPresent(FlexibleInt.self, forKey: .perPage)
            hasNext = try? container.decodeIfPresent(Bool.self, forKey: .hasNext)
        }
    }

    struct Item: Decodable {
        var id: FlexibleID?
        var slug: String?
        var title: String?
        var type: String?
        var file: Files?
        var blurPreview: String?

        enum CodingKeys: String, CodingKey {
            case id, slug, title, type, file
            case blurPreview = "blur_preview"
        }
    }

    struct Files: Decodable {
        var hd: Formats?
        var md: Formats?
        var sm: Formats?
        var xs: Formats?
    }

    struct Formats: Decodable {
        var gif: Media?
        var webp: Media?
        var jpg: Media?
        var mp4: Media?
    }

    struct Media: Decodable {
        var url: String
        var width: FlexibleInt?
        var height: FlexibleInt?
        var size: FlexibleInt?

        var rendition: GIFRendition? {
            guard let url = URL(string: url), url.scheme == "https" || url.scheme == "http" else { return nil }
            return GIFRendition(url: url, width: width?.value, height: height?.value, byteCount: size?.value)
        }
    }
}

/// Decodes an element if it can, else gives nil, so one bad element doesn't
/// fail its array.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
