// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization
import Testing
@testable import VelaMedia

/// Answers GIF search requests from a handler, records them, and can make
/// them slow (cancellable). Nothing leaves the Mac.
final class FakeGIFTransport: GIFSearchTransport, Sendable {
    struct Answer: Sendable {
        var status: Int
        var body: Data
        var delay: Duration = .zero
    }

    private let handler: @Sendable (URLRequest) throws -> Answer
    private let state = Mutex<(requests: [URLRequest], cancelled: Int)>(([], 0))

    init(_ handler: @escaping @Sendable (URLRequest) throws -> Answer) {
        self.handler = handler
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
    var cancelled: Int { state.withLock { $0.cancelled } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        state.withLock { $0.requests.append(request) }
        let answer = try handler(request)
        do {
            if answer.delay > .zero { try await Task.sleep(for: answer.delay) }
        } catch {
            state.withLock { $0.cancelled += 1 }
            throw URLError(.cancelled)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (answer.body, response)
    }

    static func fixture(_ name: String, status: Int = 200, delay: Duration = .zero) throws -> FakeGIFTransport {
        let body = Data(try Fixtures.string(name).utf8)
        return FakeGIFTransport { _ in Answer(status: status, body: body, delay: delay) }
    }
}

/// A clock tests move by hand.
final class TestClock: Sendable {
    private let current = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { current.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

private func response(_ status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private func queryItems(_ request: URLRequest?) -> [String: String] {
    let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

@Suite("KLIPY")
struct KLIPYProviderTests {
    let klipy = KLIPYProvider()

    @Test func buildsTrendingAndSearchRequests() throws {
        let trending = try #require(klipy.request(for: .trending, page: nil, rating: .r, apiKey: "test-key"))
        #expect(trending.url?.host() == "api.klipy.com")
        #expect(trending.url?.path() == "/api/v1/test-key/gifs/trending")
        #expect(trending.httpMethod == "GET")
        let items = queryItems(trending)
        #expect(items["page"] == "1")
        #expect(items["per_page"] == "24")
        #expect(items["content_filter"] == "off")
        #expect(items["format_filter"] == "gif,webp,jpg")
        #expect(items["q"] == nil)
        // Nothing that identifies the user, and no ad parameters.
        #expect(items["customer_id"] == nil)
        #expect(!items.keys.contains { $0.hasPrefix("ad-") })

        let search = try #require(klipy.request(for: .search("cats & dogs+1"), page: .page(3), rating: .pg13, apiKey: "test-key"))
        #expect(search.url?.path() == "/api/v1/test-key/gifs/search")
        let searchItems = queryItems(search)
        #expect(searchItems["q"] == "cats & dogs+1")
        #expect(searchItems["page"] == "3")
        #expect(searchItems["content_filter"] == "low")
        #expect(search.url?.absoluteString.contains("q=cats%20%26%20dogs%2B1") == true, "\(search.url!)")
        #expect(search.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(klipy.request(for: .trending, page: nil, rating: .r, apiKey: "") == nil)
    }

    @Test(arguments: [(GIFContentRating.g, "high"), (.pg, "medium"), (.pg13, "low"), (.r, "off")])
    func mapsTheRatingToContentFilter(_ rating: GIFContentRating, _ filter: String) throws {
        #expect(KLIPYProvider.contentFilter(for: rating) == filter)
        let request = try #require(klipy.request(for: .search("hi"), page: nil, rating: rating, apiKey: "k"))
        #expect(queryItems(request)["content_filter"] == filter)
    }

    @Test func decodesResultsInOrderWithoutAds() throws {
        let data = Data(try Fixtures.string("klipy-search.json").utf8)
        let page = try klipy.decode(data, response: response(), query: .search("hello"), page: nil)
        #expect(page.results.map(\.id) == ["hello-hi-662", "wave-goodbye-31"])
        #expect(page.next == .page(2))

        let first = page.results[0]
        #expect(first.title == "Hello")
        #expect(first.shareURL.absoluteString == "https://static.klipy.com/ii/935d7ab9d8c6202580a668421940ec81/14/af/hello-hi-662-md.gif")
        #expect(first.stills.map(\.url.lastPathComponent) == ["hello-hi-662-xs.jpg", "hello-hi-662-sm.jpg"])
        #expect(first.animations.map(\.url.lastPathComponent) == ["hello-hi-662-xs.webp", "hello-hi-662-sm.webp"])
        #expect(first.placeholder?.starts(with: [0xFF, 0xD8]) == true)
        #expect(abs(first.aspectRatio - 498.0 / 374.0) < 0.02)
        // The smallest preview that's big enough for the cell.
        #expect(first.animation(forPixelWidth: 80)?.url.lastPathComponent == "hello-hi-662-xs.webp")
        #expect(first.animation(forPixelWidth: 200)?.url.lastPathComponent == "hello-hi-662-sm.webp")
        #expect(first.still(forPixelWidth: 600)?.url.lastPathComponent == "hello-hi-662-sm.jpg")
        #expect(first.accessibilityDescription == "Hello")
        // The page, from the slug: never sent, only remembered for the caption.
        #expect(page.results.map(\.pageURL?.absoluteString) == ["https://klipy.com/gifs/hello-hi-662", "https://klipy.com/gifs/wave-goodbye-31"])
    }

    @Test func knowsAPageOnlyFromASlug() throws {
        #expect(KLIPYProvider.pageURL(slug: "awesome-ok--ksMzbJP8D")?.absoluteString == "https://klipy.com/gifs/awesome-ok--ksMzbJP8D")
        #expect(KLIPYProvider.pageURL(slug: " cc-220--ksMzbJP8D\n")?.absoluteString == "https://klipy.com/gifs/cc-220--ksMzbJP8D")
        #expect(KLIPYProvider.pageURL(slug: "café-ok")?.absoluteString == "https://klipy.com/gifs/caf%C3%A9-ok")
        #expect(KLIPYProvider.pageURL(slug: "a?b#c")?.absoluteString == "https://klipy.com/gifs/a%3Fb%23c")
        for slug in [nil, "", "  ", "a/b", ".", ".."] {
            #expect(KLIPYProvider.pageURL(slug: slug) == nil, "\(slug ?? "nil")")
        }
        // A result without a slug has an id, but no page.
        let json = #"""
        {"result":true,"data":{"data":[{"id":7,"title":"No slug","type":"gif","file":{"md":{"gif":{"url":"https://static.klipy.com/ii/d7aec6f6f171607374b2065c836f92f4/3d/31/08K8MgEk.gif","width":480,"height":270}}}}],"has_next":false}}
        """#
        let page = try klipy.decode(Data(json.utf8), response: response(), query: .trending, page: nil)
        let result = try #require(page.results.first)
        #expect(result.id == "7")
        #expect(result.pageURL == nil)
    }

    @Test func endsWhenThereIsNoNextPage() throws {
        let json = #"{"result":true,"data":{"data":[],"current_page":4,"per_page":24,"has_next":false}}"#
        let page = try klipy.decode(Data(json.utf8), response: response(), query: .trending, page: .page(4))
        #expect(page.results.isEmpty)
        #expect(page.next == nil)
    }

    @Test func reportsARefusedKeyAndTheRateLimit() throws {
        let invalid = Data(try Fixtures.string("klipy-invalid-key.json").utf8)
        #expect(throws: GIFSearchError.invalidKey) { try klipy.decode(invalid, response: response(404), query: .trending, page: nil) }
        #expect(throws: GIFSearchError.invalidKey) { try klipy.decode(Data("{}".utf8), response: response(401), query: .trending, page: nil) }
        #expect(throws: GIFSearchError.rateLimited) { try klipy.decode(Data(), response: response(429), query: .trending, page: nil) }
        let limit = #"{"result":false,"errors":{"message":["Rate limit exceeded"]}}"#
        #expect(throws: GIFSearchError.rateLimited) { try klipy.decode(Data(limit.utf8), response: response(403), query: .trending, page: nil) }
        #expect(throws: GIFSearchError.server(502)) { try klipy.decode(Data("<html>".utf8), response: response(502), query: .trending, page: nil) }
        #expect(throws: GIFSearchError.badResponse) { try klipy.decode(Data("nope".utf8), response: response(), query: .trending, page: nil) }
    }

    @Test func linksToTheSearchOnKLIPY() {
        #expect(klipy.websiteURL(for: .trending).absoluteString == "https://klipy.com/gifs")
        #expect(klipy.websiteURL(for: .search("cats")).absoluteString == "https://klipy.com/search/cats")
        #expect(klipy.websiteURL(for: GIFQuery(text: "  funny   cats ")).absoluteString == "https://klipy.com/search/funny-cats")
        #expect(klipy.websiteURL(for: .search("cats & dogs/100%?")).absoluteString == "https://klipy.com/search/cats-%26-dogs%2F100%25%3F")
        #expect(klipy.websiteURL(for: .search("café")).absoluteString == "https://klipy.com/search/caf%C3%A9")
        #expect(klipy.searchPlaceholder == "Search KLIPY")
        #expect(klipy.attribution == "Powered by KLIPY")
        // KLIPY's logo stands in for the text, as its guidelines ask.
        #expect(klipy.attributionLogo == .klipy)
        #expect(klipy.viewOnSiteTitle == "View on KLIPY")
    }
}

@Suite("GIPHY")
struct GIPHYProviderTests {
    let giphy = GIPHYProvider()

    @Test func buildsRequestsWithoutTracking() throws {
        let trending = try #require(giphy.request(for: .trending, page: nil, rating: .r, apiKey: "abc"))
        #expect(trending.url?.absoluteString.hasPrefix("https://api.giphy.com/v1/gifs/trending?") == true)
        let items = queryItems(trending)
        #expect(items["api_key"] == "abc")
        #expect(items["rating"] == "r")
        #expect(items["limit"] == "24")
        #expect(items["offset"] == "0")
        #expect(items["random_id"] == nil)
        #expect(items["customer_id"] == nil)

        let long = String(repeating: "x", count: 80)
        let search = try #require(giphy.request(for: .search(long), page: .offset(48), rating: .pg13, apiKey: "abc"))
        #expect(search.url?.path() == "/v1/gifs/search")
        #expect(queryItems(search)["q"]?.count == 50)
        #expect(queryItems(search)["offset"] == "48")
        #expect(queryItems(search)["rating"] == "pg-13")
    }

    @Test(arguments: [(GIFContentRating.g, "g"), (.pg, "pg"), (.pg13, "pg-13"), (.r, "r")])
    func mapsTheRating(_ rating: GIFContentRating, _ value: String) {
        #expect(GIPHYProvider.rating(for: rating) == value)
    }

    @Test func decodesResultsWithTheirURLsUntouched() throws {
        let data = Data(try Fixtures.string("giphy-search.json").utf8)
        let page = try giphy.decode(data, response: response(), query: .search("surf"), page: nil)
        #expect(page.results.map(\.id) == ["l0HlyLQsbvhciAuKA", "3o7buiO0t8uLXHBDXO"])
        #expect(page.next == .offset(2))
        let first = page.results[0]
        // The GIF as GIPHY gives it, tracking token and all.
        #expect(first.shareURL.absoluteString == "https://media3.giphy.com/media/l0HlyLQsbvhciAuKA/giphy.gif?cid=9f0f64258d093c222a5c058e0ba384203b07211f39c5ec49&rid=giphy.gif&ct=g")
        #expect(first.stills.map { $0.url.lastPathComponent } == ["100w_s.gif", "200w_s.gif"])
        #expect(first.animations.map { $0.url.lastPathComponent } == ["100w.webp", "200w.webp"])
        #expect(first.animations[0].url.query()?.contains("cid=") == true)
        #expect(first.stills[0].width == 100)
        #expect(first.attribution == "@haydiroket")
        #expect(first.accessibilityDescription == "summer surf GIF, by @haydiroket")
        // GIPHY's links name the GIF, and its caption opens the link: no page is kept.
        #expect(first.pageURL == nil)
        // No user: the site it came from.
        #expect(page.results[1].attribution == "reddit.com")
    }

    @Test func reportsErrors() throws {
        let unauthorized = Data(try Fixtures.string("giphy-unauthorized.json").utf8)
        #expect(throws: GIFSearchError.invalidKey) { try giphy.decode(unauthorized, response: response(401), query: .trending, page: nil) }
        // The status in the body counts too.
        #expect(throws: GIFSearchError.invalidKey) { try giphy.decode(unauthorized, response: response(200), query: .trending, page: nil) }
        #expect(throws: GIFSearchError.rateLimited) { try giphy.decode(Data(), response: response(429), query: .trending, page: nil) }
        // GIPHY's "synthetic" answer to a failure: an empty 200.
        let synthetic = #"{"data":[],"meta":{"status":200,"msg":"OK","response_id":""}}"#
        #expect(throws: GIFSearchError.server(503)) { try giphy.decode(Data(synthetic.utf8), response: response(), query: .trending, page: nil) }
    }

    @Test func stopsAtGIPHYsLastPage() throws {
        let json = #"{"data":[],"pagination":{"total_count":5000,"count":24,"offset":480},"meta":{"status":200,"msg":"OK","response_id":"x"}}"#
        #expect(try giphy.decode(Data(json.utf8), response: response(), query: .trending, page: .offset(480)).next == nil)
        #expect(try giphy.decode(Data(json.utf8), response: response(), query: .search("a"), page: .offset(480)).next == .offset(504))
    }

    @Test func linksToTheSearchOnGIPHY() {
        #expect(giphy.websiteURL(for: .trending).absoluteString == "https://giphy.com/trending-gifs")
        #expect(giphy.websiteURL(for: .search("funny cats")).absoluteString == "https://giphy.com/search/funny-cats")
        #expect(giphy.websiteURL(for: .search("a#b?c")).absoluteString == "https://giphy.com/search/a%23b%3Fc")
        #expect(giphy.attribution == "Powered by GIPHY")
        #expect(giphy.attributionLogo == nil)
        #expect(giphy.searchPlaceholder == "Search GIPHY")
    }
}

@Suite("GIF search client")
struct GIFSearchClientTests {
    private static func klipyAnswer() throws -> FakeGIFTransport.Answer {
        FakeGIFTransport.Answer(status: 200, body: Data(try Fixtures.string("klipy-search.json").utf8))
    }

    @Test func trendingIsFetchedOncePerRatingAndExpires() async throws {
        let answer = try Self.klipyAnswer()
        let transport = FakeGIFTransport { _ in answer }
        let clock = TestClock()
        let client = GIFSearchClient(provider: KLIPYProvider(), apiKey: "k", transport: transport, now: { clock.now })
        _ = try await client.page(.trending, rating: .r)
        _ = try await client.page(.trending, rating: .r)
        #expect(await client.requestCount == 1)
        // Another rating is another list.
        _ = try await client.page(.trending, rating: .g)
        #expect(await client.requestCount == 2)
        clock.advance(GIFSearchClient.trendingLifetime - 1)
        _ = try await client.page(.trending, rating: .r)
        #expect(await client.requestCount == 2)
        clock.advance(2)
        _ = try await client.page(.trending, rating: .r)
        #expect(await client.requestCount == 3)
    }

    @Test func searchesAreKeptForTheSession() async throws {
        let answer = try Self.klipyAnswer()
        let transport = FakeGIFTransport { _ in answer }
        let client = GIFSearchClient(provider: KLIPYProvider(), apiKey: "k", transport: transport)
        _ = try await client.page(.search("Cats"), rating: .r)
        _ = try await client.page(GIFQuery(text: " cats "), rating: .r)
        #expect(await client.requestCount == 1)
        _ = try await client.page(.search("cats"), page: .page(2), rating: .r)
        #expect(await client.requestCount == 2)
        // The oldest of more than 20 searches is let go.
        for index in 0..<GIFSearchClient.searchCacheLimit {
            _ = try await client.page(.search("query \(index)"), rating: .r)
        }
        #expect(await client.requestCount == 2 + GIFSearchClient.searchCacheLimit)
        _ = try await client.page(.search("query 19"), rating: .r)
        #expect(await client.requestCount == 2 + GIFSearchClient.searchCacheLimit)
        _ = try await client.page(.search("cats"), rating: .r)
        #expect(await client.requestCount == 3 + GIFSearchClient.searchCacheLimit)
    }

    @Test func giphyAnswersAreNotKept() async throws {
        let body = Data(try Fixtures.string("giphy-search.json").utf8)
        let transport = FakeGIFTransport { _ in .init(status: 200, body: body) }
        let client = GIFSearchClient(provider: GIPHYProvider(), apiKey: "k", transport: transport)
        _ = try await client.page(.trending, rating: .r)
        _ = try await client.page(.trending, rating: .r)
        #expect(await client.requestCount == 2)
        #expect(await client.cachedPage(.trending, rating: .r) == nil)
    }

    @Test func theRateLimitStopsRequestsUntilTryAgain() async throws {
        let limited = Mutex(true)
        let answer = try Self.klipyAnswer()
        let transport = FakeGIFTransport { _ in
            limited.withLock { $0 } ? .init(status: 429, body: Data()) : answer
        }
        let clock = TestClock()
        let client = GIFSearchClient(provider: KLIPYProvider(), apiKey: "k", transport: transport, now: { clock.now })
        await #expect(throws: GIFSearchError.rateLimited) { try await client.page(.search("cats"), rating: .r) }
        // Typing on doesn't knock again.
        await #expect(throws: GIFSearchError.rateLimited) { try await client.page(.search("cats and"), rating: .r) }
        await #expect(throws: GIFSearchError.rateLimited) { try await client.page(.trending, rating: .r) }
        #expect(await client.requestCount == 1)
        // Try again waits a minute.
        #expect(await client.retryAllowedAt() == clock.now.addingTimeInterval(GIFSearchClient.retryDelay))
        await #expect(throws: GIFSearchError.rateLimited) { try await client.page(.search("cats"), rating: .r, retry: true) }
        #expect(await client.requestCount == 1)
        clock.advance(GIFSearchClient.retryDelay)
        #expect(await client.retryAllowedAt() == nil)
        limited.withLock { $0 = false }
        let page = try await client.page(.search("cats"), rating: .r, retry: true)
        #expect(page.results.count == 2)
        #expect(await client.requestCount == 2)
        #expect(await client.stopped == nil)
    }

    @Test func aRefusedKeyStopsRequestsUntilTryAgain() async throws {
        let transport = try FakeGIFTransport.fixture("klipy-invalid-key.json", status: 404)
        let client = GIFSearchClient(provider: KLIPYProvider(), apiKey: "bad", transport: transport)
        await #expect(throws: GIFSearchError.invalidKey) { try await client.page(.trending, rating: .r) }
        await #expect(throws: GIFSearchError.invalidKey) { try await client.page(.search("cats"), rating: .r) }
        #expect(await client.requestCount == 1)
        await #expect(throws: GIFSearchError.invalidKey) { try await client.page(.trending, rating: .r, retry: true) }
        #expect(await client.requestCount == 2)
    }

    @Test func noConnectionIsOffline() async throws {
        let transport = FakeGIFTransport { _ in throw URLError(.notConnectedToInternet) }
        let client = GIFSearchClient(provider: KLIPYProvider(), apiKey: "k", transport: transport)
        await #expect(throws: GIFSearchError.offline) { try await client.page(.trending, rating: .r) }
        // Not held back: the next try goes out.
        await #expect(throws: GIFSearchError.offline) { try await client.page(.trending, rating: .r) }
        #expect(await client.requestCount == 2)
    }

    @Test func cancellingStopsTheRequest() async throws {
        let answer = try Self.klipyAnswer()
        let transport = FakeGIFTransport { _ in .init(status: 200, body: answer.body, delay: .seconds(5)) }
        let client = GIFSearchClient(provider: KLIPYProvider(), apiKey: "k", transport: transport)
        let task = Task { try await client.page(.search("slow"), rating: .r) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        for _ in 0..<40 where transport.cancelled == 0 {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(transport.cancelled == 1)
        // Nothing was kept from it.
        #expect(await client.cachedPage(.search("slow"), rating: .r) == nil)
    }

    @Test func theSameRequestAtOnceIsSentOnce() async throws {
        let answer = try Self.klipyAnswer()
        let transport = FakeGIFTransport { _ in .init(status: 200, body: answer.body, delay: .milliseconds(200)) }
        let client = GIFSearchClient(provider: KLIPYProvider(), apiKey: "k", transport: transport)
        async let first = client.page(.trending, rating: .r)
        async let second = client.page(.trending, rating: .r)
        let (a, b) = try await (first, second)
        #expect(a == b)
        #expect(await client.requestCount == 1)
    }
}

/// Real requests to KLIPY and GIPHY, for when there's a key to try:
///
///     VELA_LIVE_GIF_TESTS=1 VELA_KLIPY_API_KEY=… [VELA_GIPHY_API_KEY=…] \
///         swift test --package-path Packages/VelaKit --filter LiveGIFSearchTests
///
/// or `scripts/check-gif-search.sh`. Each run spends four requests per key.
@Suite("Live GIF search", .enabled(if: ProcessInfo.processInfo.environment["VELA_LIVE_GIF_TESTS"] == "1"))
struct LiveGIFSearchTests {
    private func check(_ provider: any GIFSearchProvider, key: String) async throws {
        let client = GIFSearchClient(provider: provider, apiKey: key)
        let trending = try await client.page(.trending, rating: .r)
        #expect(!trending.results.isEmpty, "\(provider.displayName): no trending results")
        let search = try await client.page(.search("cat"), rating: .g)
        #expect(!search.results.isEmpty, "\(provider.displayName): no results for cat")
        #expect(search.next != nil)
        if let next = search.next {
            let more = try await client.page(.search("cat"), page: next, rating: .g)
            #expect(!more.results.isEmpty)
        }
        let first = try #require(search.results.first)
        print("\(provider.displayName): \(trending.results.count) trending, \(search.results.count) for cat; first: \(first.title) \(first.shareURL)")
        // The preview and the GIF itself load.
        let loader = ImageLoader(session: URLSessionGIFTransport.makeSession())
        if let still = first.still(forPixelWidth: 200) {
            _ = try await loader.load(still.url, maxBytes: 2_000_000)
        }
        if let animation = first.animation(forPixelWidth: 200) {
            let image = try await loader.load(animation.url, maxBytes: 4_000_000)
            #expect(image.frameCount >= 1)
        }
        let gif = try await loader.load(first.shareURL, maxBytes: 20_000_000)
        #expect(gif.frameCount > 1, "\(first.shareURL) isn't animated")
        await #expect(throws: GIFSearchError.invalidKey) {
            try await GIFSearchClient(provider: provider, apiKey: "vela-invalid-key-check").page(.trending, rating: .r)
        }
    }

    @Test func klipy() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["VELA_KLIPY_API_KEY"], "Set VELA_KLIPY_API_KEY")
        try await check(KLIPYProvider(), key: key)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VELA_GIPHY_API_KEY"] != nil))
    func giphy() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["VELA_GIPHY_API_KEY"])
        try await check(GIPHYProvider(), key: key)
    }
}
