// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

// GIF search for the message box's picker: the services Vela can search
// (behind `GIFSearchProvider`), what a result holds, and what can go wrong.
// Requests go straight from the Mac to the service; nothing in between.

/// The GIF search services Vela knows.
public enum GIFSearchServiceID: String, Sendable, Hashable, CaseIterable {
    case klipy
    case giphy
}

/// How explicit results may be, from G (everyone) to R (adults).
public enum GIFContentRating: String, Sendable, Hashable, CaseIterable {
    case g
    case pg
    case pg13
    case r
}

/// What the picker asks for: what's trending, or a search.
public enum GIFQuery: Sendable, Hashable {
    case trending
    case search(String)

    /// A search for `text`, or trending when it's blank. The text is
    /// trimmed and its spaces collapsed; its case is kept (it's what the
    /// user typed).
    public init(text: String) {
        let words = text.split(whereSeparator: \.isWhitespace)
        self = words.isEmpty ? .trending : .search(words.joined(separator: " "))
    }

    /// The search text, nil for trending.
    public var text: String? {
        if case .search(let text) = self { return text }
        return nil
    }
}

/// Which page of results to fetch next, in the service's own terms.
public enum GIFPageToken: Sendable, Hashable {
    /// A page number, from 1 (KLIPY).
    case page(Int)
    /// How many results to skip (GIPHY).
    case offset(Int)
}

/// One file of a GIF: a still, an animation or the GIF to send.
public struct GIFRendition: Sendable, Hashable {
    public var url: URL
    /// Pixels, when the service said.
    public var width: Int?
    public var height: Int?
    /// Bytes, when the service said (not always exact).
    public var byteCount: Int?

    public init(url: URL, width: Int? = nil, height: Int? = nil, byteCount: Int? = nil) {
        self.url = url
        self.width = width
        self.height = height
        self.byteCount = byteCount
    }

    var pixelWidth: Int { width ?? 0 }
}

/// A GIF in the results.
public struct GIFSearchResult: Sendable, Hashable, Identifiable {
    /// The service's id for it (unique within a result list).
    public var id: String
    public var title: String
    /// Still images for the grid, smallest first (a JPG or a still GIF).
    public var stills: [GIFRendition]
    /// Animated previews for the grid, smallest first (WebP, or GIF
    /// without one).
    public var animations: [GIFRendition]
    /// A tiny blurred image shown until the preview loads (KLIPY's
    /// `blur_preview`), already decoded from its data URI.
    public var placeholder: Data?
    /// The link put in the message: a GIF the service hosts, exactly as
    /// the service gave it.
    public var shareURL: URL
    /// The GIF's own page on the service's website, when the service says
    /// which it is and `shareURL` doesn't (KLIPY's `klipy.com/gifs/<slug>`).
    /// Sending the GIF remembers it (`SentGIFPages`) for the message's
    /// "via KLIPY" caption.
    public var pageURL: URL?
    /// Who made it or where it's from ("@haydiroket", "tumblr.com"), when
    /// the service says.
    public var attribution: String?
    /// Width over height, 1 when unknown.
    public var aspectRatio: CGFloat

    public init(
        id: String,
        title: String,
        stills: [GIFRendition],
        animations: [GIFRendition],
        placeholder: Data? = nil,
        shareURL: URL,
        pageURL: URL? = nil,
        attribution: String? = nil,
        aspectRatio: CGFloat = 1
    ) {
        self.id = id
        self.title = title
        self.stills = stills
        self.animations = animations
        self.placeholder = placeholder
        self.shareURL = shareURL
        self.pageURL = pageURL
        self.attribution = attribution
        self.aspectRatio = aspectRatio
    }

    /// The smallest still at least `pixelWidth` wide (else the largest).
    public func still(forPixelWidth pixelWidth: Int) -> GIFRendition? {
        Self.smallest(in: stills, atLeast: pixelWidth)
    }

    /// The smallest animation at least `pixelWidth` wide (else the largest).
    public func animation(forPixelWidth pixelWidth: Int) -> GIFRendition? {
        Self.smallest(in: animations, atLeast: pixelWidth)
    }

    static func smallest(in renditions: [GIFRendition], atLeast pixelWidth: Int) -> GIFRendition? {
        renditions.first { $0.pixelWidth >= pixelWidth } ?? renditions.last
    }

    /// For VoiceOver and the tooltip: "Hello, GIF by @haydiroket".
    public var accessibilityDescription: String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = name.isEmpty ? "GIF" : name
        guard let attribution, !attribution.isEmpty else { return base }
        return "\(base), by \(attribution)"
    }
}

/// A page of results and where the next one starts (nil at the end).
public struct GIFSearchPage: Sendable, Hashable {
    public var results: [GIFSearchResult]
    public var next: GIFPageToken?

    public init(results: [GIFSearchResult], next: GIFPageToken?) {
        self.results = results
        self.next = next
    }
}

/// Why a search came back empty-handed.
public enum GIFSearchError: Error, Sendable, Hashable {
    /// No API key: this build has none built in and none was entered.
    case notConfigured
    /// No connection to the service.
    case offline
    /// The service refused the key.
    case invalidKey
    /// Too many requests; try later (or with your own key).
    case rateLimited
    /// The service had a problem (an HTTP status).
    case server(Int)
    /// The answer couldn't be read.
    case badResponse
}

/// A GIF search service: how to ask it and how to read its answers.
///
/// Providers only build requests and decode responses; `GIFSearchClient`
/// sends them, straight from the Mac. Results are shown as the service
/// returns them: never reordered, filtered or mixed with another service's.
public protocol GIFSearchProvider: Sendable {
    var id: GIFSearchServiceID { get }
    /// "KLIPY".
    var displayName: String { get }
    /// The search field's placeholder, as the service asks ("Search KLIPY").
    var searchPlaceholder: String { get }
    /// The attribution shown under the results ("Powered by KLIPY"), and
    /// VoiceOver's name for `attributionLogo`.
    var attribution: String { get }
    /// The service's own "Powered by" logo, shown in place of `attribution`'s
    /// text; nil to show the text.
    var attributionLogo: GIFAttributionLogo? { get }
    /// Results per request.
    var pageSize: Int { get }
    /// Whether answers may be kept in memory for the session, so a search
    /// repeated (or trending reopened) costs no request. GIPHY's terms
    /// forbid caching its responses; KLIPY's allow it within the app.
    var allowsResponseCaching: Bool { get }
    /// Whether preview images may stay in memory after the picker closes.
    var allowsThumbnailCaching: Bool { get }

    /// The request for a page of `query`, or nil if it can't be built.
    func request(for query: GIFQuery, page: GIFPageToken?, rating: GIFContentRating, apiKey: String) -> URLRequest?

    /// Reads an answer. Throws ``GIFSearchError`` for errors the service
    /// reports in its body or status.
    func decode(_ data: Data, response: HTTPURLResponse, query: GIFQuery, page: GIFPageToken?) throws(GIFSearchError) -> GIFSearchPage

    /// The service's own page for `query` ("View on KLIPY").
    func websiteURL(for query: GIFQuery) -> URL
}

extension GIFSearchProvider {
    /// "View on KLIPY".
    public var viewOnSiteTitle: String { "View on \(displayName)" }

    public var attributionLogo: GIFAttributionLogo? { nil }
}

/// A GIF service's "Powered by" logo, which the picker draws in place of
/// the attribution's text (VelaUI has the files).
public enum GIFAttributionLogo: Sendable, Hashable {
    /// KLIPY's "Powered by KLIPY", as its attribution guidelines ask.
    case klipy
}

// MARK: - Shared helpers

enum GIFSearchSupport {
    /// `https://example.com/search/{term}` with the term as one path
    /// segment: spaces become hyphens (as both sites write their search
    /// pages), the rest is percent-encoded.
    static func searchPageURL(base: String, term: String) -> URL? {
        let slug = term.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;%&+=")
        guard !slug.isEmpty, let encoded = slug.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: base + encoded)
    }

    /// Bytes from a `data:…;base64,…` URI.
    static func dataFromURI(_ uri: String?) -> Data? {
        guard let uri, uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ","),
              uri[..<comma].hasSuffix(";base64")
        else { return nil }
        return Data(base64Encoded: String(uri[uri.index(after: comma)...]))
    }

    /// The common HTTP answers: a refused key, too many requests, a server error.
    static func error(forStatus status: Int) -> GIFSearchError? {
        switch status {
        case 200..<300: nil
        case 401, 403: .invalidKey
        case 429: .rateLimited
        default: .server(status)
        }
    }

    /// The request's common headers: JSON, and no cookies.
    static func jsonRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        return request
    }
}

/// Decodes a number that may arrive as a JSON number or a string (GIPHY
/// sends `"width": "200"`).
struct FlexibleInt: Decodable, Sendable, Hashable {
    let value: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = Int(exactly: double.rounded())
        } else if let string = try? container.decode(String.self) {
            value = Int(string)
        } else {
            value = nil
        }
    }
}

/// An id that may be a number or a string.
struct FlexibleID: Decodable, Sendable, Hashable {
    let value: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int64.self) {
            value = String(int)
        } else {
            value = String(try container.decode(Double.self))
        }
    }
}
