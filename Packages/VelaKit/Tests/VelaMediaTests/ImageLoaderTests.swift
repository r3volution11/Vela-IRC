// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import VelaMedia

@Suite struct ImageLoaderTests {
    let server = StubServer()

    private func makeLoader(memoryLimit: Int = 64 * 1024 * 1024) -> ImageLoader {
        ImageLoader(session: server.makeSession(), memoryLimit: memoryLimit)
    }

    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test func loadsPNG() async throws {
        let png = try TestImages.png(width: 3, height: 2)
        server.route("https://img.example.com/a.png", .data(png, contentType: "image/png"))
        let image = try await makeLoader().load(url("https://img.example.com/a.png"), maxBytes: 1024 * 1024)
        #expect(image.pixelSize == CGSize(width: 3, height: 2))
        #expect(image.frameCount == 1)
        #expect(!image.isAnimated)
        #expect(image.utType == UTType.png.identifier)
        #expect(image.contentType == .png)
        #expect(image.data == png)

        let request = try #require(server.requests.first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == LinkPreviewService.defaultUserAgent)
        #expect(request.value(forHTTPHeaderField: "Accept")?.contains("image/") == true)
    }

    @Test func loadsAnimatedGIF() async throws {
        let gif = try TestImages.animatedGIF(width: 5, height: 4)
        server.route("https://img.example.com/anim.gif", .data(gif, contentType: "image/gif"))
        let image = try await makeLoader().load(url("https://img.example.com/anim.gif"), maxBytes: 1024 * 1024)
        #expect(image.frameCount == 2)
        #expect(image.isAnimated)
        #expect(image.pixelSize == CGSize(width: 5, height: 4))
        #expect(image.utType == UTType.gif.identifier)
    }

    @Test func rejectsByContentLength() async throws {
        let png = try TestImages.png(width: 64, height: 64)
        server.route("https://img.example.com/big.png", .data(png, contentType: "image/png"))
        await #expect(throws: MediaError.tooLarge) {
            try await makeLoader().load(url("https://img.example.com/big.png"), maxBytes: png.count - 1)
        }
    }

    @Test func rejectsWhileStreamingWithoutContentLength() async throws {
        var response = StubResponse.data(Data(repeating: 0xFF, count: 200_000), contentType: "image/jpeg", includeLength: false)
        response.chunkSize = 8 * 1024
        server.route("https://img.example.com/stream.jpg", response)
        await #expect(throws: MediaError.tooLarge) {
            try await makeLoader().load(url("https://img.example.com/stream.jpg"), maxBytes: 50_000)
        }
    }

    @Test func rejectsUndecodableBytes() async throws {
        server.route("https://img.example.com/fake.png", .data(Data("definitely not a png".utf8), contentType: "image/png"))
        await #expect(throws: MediaError.unsupportedContent) {
            try await makeLoader().load(url("https://img.example.com/fake.png"), maxBytes: 1024)
        }
    }

    @Test func rejectsHTMLWithoutDownloadingIt() async throws {
        server.route("https://img.example.com/page", .html("<html>not an image</html>"))
        await #expect(throws: MediaError.unsupportedContent) {
            try await makeLoader().load(url("https://img.example.com/page"), maxBytes: 1024 * 1024)
        }
    }

    @Test func httpError() async throws {
        server.route("https://img.example.com/missing.png", .status(404))
        await #expect(throws: MediaError.http(404)) {
            try await makeLoader().load(url("https://img.example.com/missing.png"), maxBytes: 1024)
        }
    }

    @Test func cachesInMemory() async throws {
        let png = try TestImages.png(width: 2, height: 2)
        server.route("https://img.example.com/c.png", .data(png, contentType: "image/png"))
        let loader = makeLoader()
        _ = try await loader.load(url("https://img.example.com/c.png"), maxBytes: 1024 * 1024)
        _ = try await loader.load(url("https://img.example.com/c.png"), maxBytes: 1024 * 1024)
        #expect(server.requests.count == 1)
        #expect(await loader.cachedImage(for: url("https://img.example.com/c.png")) != nil)

        // A cached image still respects a smaller cap.
        await #expect(throws: MediaError.tooLarge) {
            try await loader.load(url("https://img.example.com/c.png"), maxBytes: 10)
        }

        await loader.removeAllCachedImages()
        #expect(await loader.cachedImage(for: url("https://img.example.com/c.png")) == nil)
    }

    @Test func memoryCacheEvictsByCost() async throws {
        let png = try TestImages.png(width: 8, height: 8)
        server.route("https://img.example.com/1.png", .data(png, contentType: "image/png"))
        server.route("https://img.example.com/2.png", .data(png, contentType: "image/png"))
        let loader = makeLoader(memoryLimit: png.count + png.count / 2)
        _ = try await loader.load(url("https://img.example.com/1.png"), maxBytes: 1024 * 1024)
        _ = try await loader.load(url("https://img.example.com/2.png"), maxBytes: 1024 * 1024)
        #expect(await loader.cachedImage(for: url("https://img.example.com/1.png")) == nil)
        #expect(await loader.cachedImage(for: url("https://img.example.com/2.png")) != nil)
    }

    @Test func deduplicatesConcurrentLoads() async throws {
        var response = StubResponse.data(try TestImages.png(width: 2, height: 2), contentType: "image/png")
        response.delay = 0.3
        server.route("https://img.example.com/slow.png", response)
        let loader = makeLoader()
        let target = url("https://img.example.com/slow.png")

        let sizes = try await withThrowingTaskGroup(of: CGSize.self) { group in
            for _ in 0..<6 {
                group.addTask { try await loader.load(target, maxBytes: 1024 * 1024).pixelSize }
            }
            return try await group.reduce(into: [CGSize]()) { $0.append($1) }
        }
        #expect(sizes == Array(repeating: CGSize(width: 2, height: 2), count: 6))
        #expect(server.requests.count == 1)
    }

    @Test func cancellationAbortsDownload() async throws {
        var response = StubResponse.data(try TestImages.png(width: 2, height: 2), contentType: "image/png")
        response.delay = 10
        server.route("https://img.example.com/stuck.png", response)
        let loader = makeLoader()
        let target = url("https://img.example.com/stuck.png")

        let started = Date()
        let task = Task { try await loader.load(target, maxBytes: 1024 * 1024) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func downsamples() async throws {
        let png = try TestImages.png(width: 400, height: 200)
        server.route("https://img.example.com/wide.png", .data(png, contentType: "image/png"))
        let loader = makeLoader()
        let thumbnail = try await loader.downsampledImage(url("https://img.example.com/wide.png"), maxPixelSize: 100, maxBytes: 1024 * 1024)
        #expect(thumbnail.width == 100)
        #expect(thumbnail.height == 50)

        // Thumbnails and the source are cached.
        let again = try await loader.downsampledImage(url("https://img.example.com/wide.png"), maxPixelSize: 100, maxBytes: 1024 * 1024)
        #expect(again.width == 100)
        #expect(server.requests.count == 1)
    }

    @Test func policyVariantEnforcesDomainsAndRedirects() async throws {
        let png = try TestImages.png(width: 2, height: 2)
        server.route("https://img.example.com/ok.png", .data(png, contentType: "image/png"))
        server.route("https://img.example.com/hop.png", .redirect(to: "http://10.0.0.5/internal.png"))
        let loader = makeLoader()

        let image = try await loader.load(url("https://img.example.com/ok.png"), policy: MediaPolicy())
        #expect(image.pixelSize == CGSize(width: 2, height: 2))

        let blocked = MediaPolicy(siteRules: SiteRules(["example.com": "block"]))
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .userBlocked, domain: "example.com"))) {
            try await loader.load(url("https://img.example.com/ok.png"), policy: blocked)
        }
        await #expect(throws: MediaError.blockedByPolicy) {
            try await loader.load(url("https://img.example.com/hop.png"), policy: MediaPolicy())
        }
        #expect(server.requests(to: "http://10.0.0.5/internal.png").isEmpty)
        await #expect(throws: MediaError.tooLarge) {
            try await loader.load(url("https://img.example.com/ok.png"), policy: MediaPolicy(maxImageBytes: 8))
        }
    }

    @Test func textOnlySitesNeverLoadImagesEvenFromMemory() async throws {
        let png = try TestImages.png(width: 2, height: 2)
        server.route("https://img.example.com/ok.png", .data(png, contentType: "image/png"))
        let loader = makeLoader()
        let target = url("https://img.example.com/ok.png")
        _ = try await loader.load(target, policy: MediaPolicy())
        #expect(await loader.cachedImage(for: target, policy: MediaPolicy()) != nil)

        let textOnly = MediaPolicy(siteRules: SiteRules(["example.com": "textOnly"]))
        await #expect(throws: MediaError.blockedByPolicy) { try await loader.load(target, policy: textOnly) }
        await #expect(throws: MediaError.blockedByPolicy) {
            try await loader.downsampledImage(target, maxPixelSize: 1, policy: textOnly)
        }
        #expect(await loader.cachedImage(for: target, policy: textOnly) == nil)
        let imagesOff = MediaPolicy(imagesAllowed: false)
        await #expect(throws: MediaError.blockedByPolicy) { try await loader.load(target, policy: imagesOff) }
        let adult = MediaPolicy(extraAdultDomains: ["img.example.com"])
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .adultSite, domain: "img.example.com"))) {
            try await loader.load(target, policy: adult)
        }
        #expect(server.requests.count == 1)
    }

    @Test func redirectIntoRefusedSiteIsReasoned() async throws {
        let png = try TestImages.png(width: 2, height: 2)
        server.route("https://img.example.com/hop.png", .redirect(to: "https://cdn.nsfw.example/a.png"))
        server.route("https://cdn.nsfw.example/a.png", .data(png, contentType: "image/png"))
        let loader = makeLoader()
        let target = url("https://img.example.com/hop.png")

        let adult = MediaPolicy(extraAdultDomains: ["nsfw.example"])
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .adultSite, domain: "nsfw.example"))) {
            try await loader.load(target, policy: adult)
        }
        #expect(server.requests(to: "https://cdn.nsfw.example/a.png").isEmpty)

        // Allowed once it loads, and the cached copy still remembers where it came from.
        _ = try await loader.load(target, policy: MediaPolicy(extraAdultDomains: ["nsfw.example"], allowedOnce: ["nsfw.example"]))
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .adultSite, domain: "nsfw.example"))) {
            try await loader.load(target, policy: adult)
        }
        #expect(await loader.cachedImage(for: target, policy: adult) == nil)
        #expect(await loader.cachedImage(for: target) != nil)
    }

    @Test func policyThumbnails() async throws {
        let png = try TestImages.png(width: 200, height: 100)
        server.route("https://img.example.com/wide.png", .data(png, contentType: "image/png"))
        let loader = makeLoader()
        let thumbnail = try await loader.downsampledImage(url("https://img.example.com/wide.png"), maxPixelSize: 50, policy: MediaPolicy())
        #expect(thumbnail.width == 50)
        let blocked = MediaPolicy(siteRules: SiteRules(["img.example.com": "block"]))
        await #expect(throws: MediaError.siteBlocked(SiteBlock(reason: .userBlocked, domain: "img.example.com"))) {
            try await loader.downsampledImage(url("https://img.example.com/wide.png"), maxPixelSize: 50, policy: blocked)
        }
    }

    @Test func inspectEnforcesPixelBudgets() throws {
        // Scaled-down stand-ins for decompression bombs: small files, many pixels.
        let still = try TestImages.png(width: 100, height: 100)
        #expect(throws: MediaError.tooLarge) { try ImageLoader.inspect(still, maxPixelArea: 9_999) }
        #expect(try ImageLoader.inspect(still, maxPixelArea: 10_000).frameCount == 1)

        let animated = try TestImages.animatedGIF(width: 50, height: 50)
        #expect(throws: MediaError.tooLarge) {
            try ImageLoader.inspect(animated, maxPixelArea: 1_000_000, maxAnimatedPixelArea: 2_000)
        }
        #expect(ImageLoader.maxAnimatedPixelArea < ImageLoader.maxPixelArea)
    }
}

@Suite struct InFlightTasksTests {
    @Test func sharesAndCancelsWhenLastWaiterLeaves() async {
        var tasks = InFlightTasks<String, Int>()
        let (first, firstID) = tasks.join("a") { _ in
            Task { try await Task.sleep(for: .seconds(30)); return 1 }
        }
        let (second, secondID) = tasks.join("a") { _ in
            Issue.record("A second task must not be started")
            return Task { 2 }
        }
        #expect(first == second)
        #expect(firstID == secondID)

        tasks.leave("a", id: firstID)
        #expect(!first.isCancelled)
        tasks.leave("a", id: secondID)
        #expect(first.isCancelled)
        #expect(tasks.count == 0)
    }

    @Test func finishIgnoresStaleIDs() {
        var tasks = InFlightTasks<String, Int>()
        let (_, oldID) = tasks.join("a") { _ in Task { 1 } }
        tasks.finish("a", id: oldID)
        let (_, newID) = tasks.join("a") { _ in Task { 2 } }
        #expect(newID != oldID)
        tasks.finish("a", id: oldID)
        #expect(tasks.count == 1)
        tasks.finish("a", id: newID)
        #expect(tasks.count == 0)
    }
}

@Suite struct LRUCacheTests {
    @Test func evictsLeastRecentlyUsed() {
        var cache = LRUCache<String, Int>(countLimit: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        _ = cache.value(for: "a")
        cache.insert(3, for: "c")
        #expect(cache.peek("a") == 1)
        #expect(cache.peek("b") == nil)
        #expect(cache.peek("c") == 3)
        #expect(cache.count == 2)
    }

    @Test func evictsByCost() {
        var cache = LRUCache<String, Int>(countLimit: 10, costLimit: 100)
        cache.insert(1, for: "a", cost: 60)
        cache.insert(2, for: "b", cost: 30)
        cache.insert(3, for: "c", cost: 30)
        #expect(cache.peek("a") == nil)
        #expect(cache.totalCost == 60)
        cache.insert(4, for: "huge", cost: 1_000)
        #expect(cache.peek("huge") == nil)
        #expect(cache.count == 2)
        cache.insert(5, for: "b", cost: 10)
        #expect(cache.totalCost == 40)
    }
}
