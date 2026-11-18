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
/// - Concurrent requests for the same URL under the same policy share one
///   fetch; it is cancelled when every caller waiting on it has been cancelled.
/// - Results are kept in a ~500-entry in-memory LRU and, when given, in a
///   persistent `LinkPreviewCache`. Persistent entries older than
///   `maxCacheAge`, or built in an older `LinkPreview.formatVersion`, are refetched.
/// - A preview the policy partly refused (e.g. its oEmbed endpoint is on a
///   blocked site) is kept in memory only, for that policy.
/// - Failures are remembered briefly, per policy, so re-rendering scrollback
///   does not hammer a broken site while unblocking a site or "Show once"
///   takes effect at once.
/// - All requests send the honest `defaultUserAgent`, no cookies, and
///   every request (including redirect hops and oEmbed endpoints) is checked
///   with `MediaPolicy.allows(_:)`. Image, thumbnail and favicon URLs are
///   recorded as found; `ImageLoader` checks `allowsImage(_:)` when loading them.
/// - A page that answers with a bot check (or an empty, script-only page)
///   is loaded again with `browser` when `MediaPolicy.browserFallback`
///   allows (see `PreviewFetcher`). The result is cached like any other.
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

    private struct MemoryEntry {
        var preview: LinkPreview
        /// Set for degraded previews: the (fetch-relevant) policy they were built under.
        var degradedUnder: MediaPolicy?

        func isUsable(under policy: MediaPolicy) -> Bool {
            degradedUnder.map { $0 == policy.fetchKey } ?? true
        }
    }

    /// A URL under a fetch-relevant policy.
    private struct RequestKey: Hashable {
        var url: String
        var policy: MediaPolicy
    }

    private let fetcher: PreviewFetcher
    private let cache: (any LinkPreviewCache)?
    private let maxCacheAge: TimeInterval
    private var memory = LRUCache<String, MemoryEntry>(countLimit: 500)
    private var failures = LRUCache<RequestKey, FailureRecord>(countLimit: 500)
    private var inFlight = InFlightTasks<RequestKey, LinkPreview>()

    /// How long a failed fetch is remembered before it is retried.
    static let policyFailureTTL: TimeInterval = 15 * 60
    static let networkFailureTTL: TimeInterval = 2 * 60

    public init(
        session: URLSession = LinkPreviewService.makeDefaultSession(),
        cache: (any LinkPreviewCache)? = nil,
        userAgent: String = LinkPreviewService.defaultUserAgent,
        maxCacheAge: TimeInterval = 7 * 24 * 60 * 60,
        browser: (any BrowserMetadataLoading)? = BrowserMetadataFetcher.shared
    ) {
        self.fetcher = PreviewFetcher(session: session, userAgent: userAgent, browser: browser)
        self.cache = cache
        self.maxCacheAge = maxCacheAge
    }

    /// Returns a preview for `url`, fetching it if needed.
    ///
    /// Throws `MediaError.siteBlocked` (or `.blockedByPolicy` for a forbidden
    /// URL) without touching the network when the policy refuses the URL, and
    /// the same errors when a redirect leads somewhere refused. Whether to
    /// call this automatically or only after a click is `PreviewDecider`'s call.
    /// A returned preview may still point at a site the policy now blocks
    /// (e.g. from the cache); `PreviewDecider` checks that too.
    public func preview(for url: URL, policy: MediaPolicy) async throws -> LinkPreview {
        if let refusal = policy.requestError(for: url) { throw refusal }
        let urlKey = url.absoluteString
        let key = RequestKey(url: urlKey, policy: policy.fetchKey)

        if let hit = memory.value(for: urlKey), hit.isUsable(under: policy) { return hit.preview }
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

    private func leave(_ key: RequestKey, id: UInt64) {
        inFlight.leave(key, id: id)
    }

    /// The in-memory preview for `url`, if any, without fetching.
    /// Lets the UI render a known card synchronously on the service's actor.
    public func cachedPreview(for url: URL) -> LinkPreview? {
        memory.value(for: url.absoluteString)?.preview
    }

    /// The in-memory preview for `url` that `preview(for:policy:)` would
    /// return under `policy`, without fetching.
    public func cachedPreview(for url: URL, policy: MediaPolicy) -> LinkPreview? {
        guard policy.requestError(for: url) == nil,
              let entry = memory.value(for: url.absoluteString), entry.isUsable(under: policy)
        else { return nil }
        return entry.preview
    }

    /// Forgets in-memory previews and remembered failures (not the persistent cache).
    public func removeAllCachedPreviews() {
        memory.removeAll()
        failures.removeAll()
    }

    private func load(_ url: URL, key: RequestKey, id: UInt64, policy: MediaPolicy) async throws -> LinkPreview {
        defer { inFlight.finish(key, id: id) }
        do {
            if let cache, let stored = await cache.cachedPreview(for: url), stored.isCurrentFormat,
               Date().timeIntervalSince(stored.fetchedAt) < maxCacheAge {
                memory.insert(MemoryEntry(preview: stored), for: key.url)
                return stored
            }
            let result = try await fetcher.preview(for: url, policy: policy)
            let preview = result.preview
            memory.insert(MemoryEntry(preview: preview, degradedUnder: result.degraded ? key.policy : nil), for: key.url)
            failures.removeValue(for: key)
            if let cache, !result.degraded { await cache.storePreview(preview) }
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
