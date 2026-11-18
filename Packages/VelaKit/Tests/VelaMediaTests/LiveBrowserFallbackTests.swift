// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network
import Testing
@testable import VelaMedia

/// What the browser-engine fallback costs on a real page behind a bot check,
/// with and without the content blocking. Off unless asked for:
///
///     VELA_BROWSER_FALLBACK_MEASURE=1 swift test --package-path Packages/VelaKit --filter LiveBrowserFallbackMeasurement
///
/// `VELA_BROWSER_FALLBACK_URL` measures another page (default: the IMDb
/// sample in `MediaSites`). Whether the fallback works at all is checked by
/// the live media sites suite (`VELA_LIVE_MEDIA_SITES=imdb`).
@MainActor
@Suite(
    "Live browser fallback measurement",
    .enabled(if: ProcessInfo.processInfo.environment["VELA_BROWSER_FALLBACK_MEASURE"].map { !["", "0", "false", "no"].contains($0) } ?? false),
    .serialized
)
struct LiveBrowserFallbackMeasurement {
    static let url = URL(string: ProcessInfo.processInfo.environment["VELA_BROWSER_FALLBACK_URL"]
        ?? "https://www.imdb.com/title/tt8310612/")!

    @Test(arguments: [true, false])
    func measure(blocking: Bool) async throws {
        // Every byte the web view sends and receives goes through a local
        // proxy that counts it, TLS and all.
        let proxy = try CountingProxy()
        let endpoint = try await proxy.start()
        defer { proxy.stop() }
        var options = BrowserMetadataFetcher.Options(blocksSubresources: blocking, collectsStats: true)
        options.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: endpoint)]
        let fetcher = BrowserMetadataFetcher(options: options)

        let page = try await fetcher.load(Self.url, policy: MediaPolicy())
        let stats = try #require(page.stats)
        // What was still arriving when the load stopped counts too.
        try await Task.sleep(for: .seconds(1))
        let hosts = proxy.hostTotals.map { total in
            "    \(total.host): \(total.tunnels) connection\(total.tunnels == 1 ? "" : "s"), \(Self.kilobytes(total.bytesIn)) in, \(Self.kilobytes(total.bytesOut)) out"
        }
        let report = """
        \(blocking ? "With" : "Without") content blocking: \(String(format: "%.2f", stats.seconds)) s to metadata, \
        \(stats.documents) documents, \(stats.requests) requests finished, \
        \(Self.kilobytes(proxy.bytesIn)) received and \(Self.kilobytes(proxy.bytesOut)) sent over \(proxy.tunnels) connections
        \(hosts.joined(separator: "\n"))
          title: \(page.metadata.title ?? "none")
          description: \(page.metadata.summary ?? "none")
          image: \(page.metadata.imageURL?.absoluteString ?? "none")
          landed on: \(page.finalURL.absoluteString)

        """
        print(report, terminator: "")
        LiveMediaGate.appendToReport(report)
        #expect(page.metadata.title != nil)
    }

    static func kilobytes(_ bytes: Int) -> String {
        bytes < 1024 * 1024 ? "\(bytes / 1024) KB" : String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// The whole preview, as Vela builds it: the quick fetch, then the engine.
    @Test func endToEnd() async throws {
        let start = ContinuousClock.now
        let preview = try await LinkPreviewService().preview(for: Self.url, policy: MediaPolicy())
        let elapsed = ContinuousClock.now - start
        let report = """
        Whole preview: \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))), \
        browser engine: \(preview.loadedWithBrowserEngine == true ? "yes" : "no")
          title: \(preview.title ?? "none")
          description: \(preview.summary ?? "none")
          image: \(preview.imageURL?.absoluteString ?? "none")

        """
        print(report, terminator: "")
        LiveMediaGate.appendToReport(report)
        #expect(preview.loadedWithBrowserEngine == true)
    }
}
