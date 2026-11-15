// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Persistent storage for previews (implemented by VelaStore).
public protocol LinkPreviewCache: Sendable {
    func cachedPreview(for url: URL) async -> LinkPreview?
    func storePreview(_ preview: LinkPreview) async
}

/// Builds `LinkPreview`s for URLs seen in chat.
///
/// - Concurrent requests for the same URL share one fetch; it is cancelled
///   when every caller waiting on it has been cancelled.
/// - Results are kept in a ~500-entry in-memory LRU and, when given, in a
///   persistent `LinkPreviewCache`. Persistent entries older than
///   `maxCacheAge` are refetched.
/// - Failures are remembered briefly so re-rendering scrollback does not
///   hammer a broken site.
/// - All requests send the honest `defaultUserAgent`, no cookies, and
///   every URL (including redirect targets, oEmbed endpoints, card images
///   and favicons) is checked against the `MediaPolicy`.
public actor LinkPreviewService {
    public static let defaultUserAgent = "Vela/0.1 (Macintosh; link preview; +https://github.com/r3volution11/Vela-IRC)"

    /// A cookie-less, cache-less session with short timeouts.
    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = PreviewFetcher.requestTimeout
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private struct FailureRecord {
        var error: any Error
        var expires: Date
    }

    private let fetcher: PreviewFetcher
    private let cache: (any LinkPreviewCache)?
    private let maxCacheAge: TimeInterval
    private var memory = LRUCache<String, LinkPreview>(countLimit: 500)
    private var failures = LRUCache<String, FailureRecord>(countLimit: 500)
    private var inFlight = InFlightTasks<String, LinkPreview>()

    /// How long a failed fetch is remembered before it is retried.
    static let policyFailureTTL: TimeInterval = 15 * 60
    static let networkFailureTTL: TimeInterval = 2 * 60

    public init(
        session: URLSession = LinkPreviewService.makeDefaultSession(),
        cache: (any LinkPreviewCache)? = nil,
        userAgent: String = LinkPreviewService.defaultUserAgent,
        maxCacheAge: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.fetcher = PreviewFetcher(session: session, userAgent: userAgent)
        self.cache = cache
        self.maxCacheAge = maxCacheAge
    }

    /// Returns a preview for `url`, fetching it if needed.
    ///
    /// Throws `MediaError.blockedByPolicy` without touching the network when
    /// the policy disallows the URL. Callers decide separately (see
    /// `MediaPolicy.permitsAutomaticPreview(of:)`) whether to call this
    /// automatically or only after a click.
    public func preview(for url: URL, policy: MediaPolicy) async throws -> LinkPreview {
        guard policy.allows(url) else { throw MediaError.blockedByPolicy }
        let key = url.absoluteString

        if let hit = memory.value(for: key) { return hit }
        if let failure = failures.peek(key) {
            if failure.expires > Date() { throw failure.error }
            failures.removeValue(for: key)
        }

        let (task, id) = inFlight.join(key) { id in
            Task { try await self.load(url, key: key, id: id, policy: policy) }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(key, id: id) }
        }
    }

    private func leave(_ key: String, id: UInt64) {
        inFlight.leave(key, id: id)
    }

    /// The in-memory preview for `url`, if any, without fetching.
    /// Lets the UI render a known card synchronously on the service's actor.
    public func cachedPreview(for url: URL) -> LinkPreview? {
        memory.value(for: url.absoluteString)
    }

    /// Forgets in-memory previews and remembered failures (not the persistent
    /// cache). Call it when the `MediaPolicy` changes: cached cards were
    /// built under the old policy (e.g. a card image on a now-blocked host).
    public func removeAllCachedPreviews() {
        memory.removeAll()
        failures.removeAll()
    }

    private func load(_ url: URL, key: String, id: UInt64, policy: MediaPolicy) async throws -> LinkPreview {
        defer { inFlight.finish(key, id: id) }
        do {
            if let cache, let stored = await cache.cachedPreview(for: url),
               Date().timeIntervalSince(stored.fetchedAt) < maxCacheAge {
                memory.insert(stored, for: key)
                return stored
            }
            let preview = try await fetcher.preview(for: url, policy: policy)
            memory.insert(preview, for: key)
            failures.removeValue(for: key)
            if let cache { await cache.storePreview(preview) }
            return preview
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let ttl = error is MediaError ? Self.policyFailureTTL : Self.networkFailureTTL
            failures.insert(FailureRecord(error: error, expires: Date().addingTimeInterval(ttl)), for: key)
            throw error
        }
    }
}
