// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Sends a request and returns the answer. `URLSessionGIFTransport` in the
/// app; tests answer from fixtures.
public protocol GIFSearchTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// The real transport: an ephemeral session with no cache and no cookies,
/// straight to the service.
public struct URLSessionGIFTransport: GIFSearchTransport {
    let session: URLSession

    public init(session: URLSession = URLSessionGIFTransport.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        MediaSessionHooks.apply(to: configuration)
        return URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// Asks one GIF service, with one key, for pages of results, spending as
/// few requests as it can. A test key allows 100 requests an hour for
/// everyone using the build, so:
///
/// - Trending is kept for ``trendingLifetime`` (per rating and page), and
///   the last ``searchCacheLimit`` searches for the session, when the
///   service allows keeping answers (`allowsResponseCaching`).
/// - The same request made twice at once is sent once.
/// - After the service says the key is refused or the limit is reached,
///   nothing more is sent until ``retry`` is asked for (allowed after
///   ``retryDelay`` for the limit), so typing doesn't keep knocking.
///
/// Cancelling the caller cancels its request when no one else waits for it.
/// Errors are ``GIFSearchError``, or `CancellationError`.
public actor GIFSearchClient {
    /// How long trending stays fresh.
    public static let trendingLifetime: TimeInterval = 15 * 60
    /// Searches kept for the session.
    public static let searchCacheLimit = 20
    /// How long "Try again" waits after the service said it's busy.
    public static let retryDelay: TimeInterval = 60

    public nonisolated let provider: any GIFSearchProvider
    private let apiKey: String
    private let transport: any GIFSearchTransport
    private let now: @Sendable () -> Date

    /// Requests sent so far (not answers from memory).
    public private(set) var requestCount = 0
    /// The URLs of the requests sent, in order (for tests; keys and all).
    public private(set) var sentRequests: [URL] = []

    /// Why requests are held back, and since when.
    public private(set) var stopped: (error: GIFSearchError, since: Date)?

    private struct PageKey: Hashable {
        var query: String?
        var rating: GIFContentRating
        var page: GIFPageToken?
    }

    private struct SearchKey: Hashable {
        var query: String
        var rating: GIFContentRating
    }

    private var trending: [PageKey: (page: GIFSearchPage, fetched: Date)] = [:]
    private var searches: LRUCache<SearchKey, [GIFPageToken?: GIFSearchPage]>
    private var inFlight = InFlightTasks<PageKey, GIFSearchPage>()

    public init(
        provider: any GIFSearchProvider,
        apiKey: String,
        transport: any GIFSearchTransport = URLSessionGIFTransport(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.transport = transport
        self.now = now
        self.searches = LRUCache(countLimit: Self.searchCacheLimit)
    }

    /// The same search, however it was typed: "Cats  " and "cats".
    static func cacheText(_ query: GIFQuery) -> String? {
        query.text?.lowercased()
    }

    /// A page from memory, without sending anything.
    public func cachedPage(_ query: GIFQuery, page: GIFPageToken? = nil, rating: GIFContentRating) -> GIFSearchPage? {
        guard provider.allowsResponseCaching else { return nil }
        let key = PageKey(query: Self.cacheText(query), rating: rating, page: page)
        if let text = key.query {
            return searches.value(for: SearchKey(query: text, rating: rating))?[page] ?? nil
        }
        guard let entry = trending[key], now().timeIntervalSince(entry.fetched) < Self.trendingLifetime else { return nil }
        return entry.page
    }

    /// When "Try again" can be pressed, if requests are held back for the
    /// rate limit; nil when it can be pressed now.
    public func retryAllowedAt() -> Date? {
        guard let stopped, stopped.error == .rateLimited else { return nil }
        let at = stopped.since.addingTimeInterval(Self.retryDelay)
        return at > now() ? at : nil
    }

    /// A page of `query` (`page` nil for the first), from memory or the
    /// service. `retry` sends it even after the key was refused, or the
    /// limit reached at least ``retryDelay`` ago.
    public func page(
        _ query: GIFQuery,
        page: GIFPageToken? = nil,
        rating: GIFContentRating,
        retry: Bool = false
    ) async throws -> GIFSearchPage {
        if let cached = cachedPage(query, page: page, rating: rating) { return cached }
        if let stopped {
            if !retry || retryAllowedAt() != nil { throw stopped.error }
            self.stopped = nil
        }
        let key = PageKey(query: Self.cacheText(query), rating: rating, page: page)
        let (task, id) = inFlight.join(key) { id in
            Task {
                defer { self.inFlight.finish(key, id: id) }
                return try await self.send(query, page: page, rating: rating, key: key)
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(key, id: id) }
        }
    }

    private func leave(_ key: PageKey, id: UInt64) {
        inFlight.leave(key, id: id)
    }

    private func send(_ query: GIFQuery, page: GIFPageToken?, rating: GIFContentRating, key: PageKey) async throws -> GIFSearchPage {
        guard let request = provider.request(for: query, page: page, rating: rating, apiKey: apiKey) else {
            throw GIFSearchError.notConfigured
        }
        try Task.checkCancellation()
        requestCount += 1
        if let url = request.url { sentRequests.append(url) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw Self.mapTransportError(error)
        }
        guard let http = response as? HTTPURLResponse else { throw GIFSearchError.badResponse }
        let result: GIFSearchPage
        do {
            result = try provider.decode(data, response: http, query: query, page: page)
        } catch {
            if error == .rateLimited || error == .invalidKey { stopped = (error, now()) }
            throw error
        }
        store(result, for: key)
        return result
    }

    private func store(_ result: GIFSearchPage, for key: PageKey) {
        guard provider.allowsResponseCaching else { return }
        if let text = key.query {
            let searchKey = SearchKey(query: text, rating: key.rating)
            var pages = searches.value(for: searchKey) ?? [:]
            pages[key.page] = result
            searches.insert(pages, for: searchKey)
        } else {
            trending[key] = (result, now())
        }
    }

    static func mapTransportError(_ error: any Error) -> any Error {
        if error is CancellationError { return error }
        if let error = error as? GIFSearchError { return error }
        if let error = error as? URLError {
            if error.code == .cancelled { return CancellationError() }
            return GIFSearchError.offline
        }
        return GIFSearchError.offline
    }
}
