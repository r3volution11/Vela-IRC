// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

/// Checks every live sample in `MediaSites` against the real site: that
/// the sites still serve what Vela expects. Off unless asked for:
///
///     VELA_LIVE_MEDIA_TESTS=1 swift test --package-path Packages/VelaKit --filter LiveMediaSiteTests
///     scripts/check-media-sites.sh      # the same, with a readable report
///
/// - `VELA_LIVE_MEDIA_SITES=tenor,giphy` checks only those sites (ids in `MediaSites`).
/// - `VELA_MEDIA_REPORT=<file>` appends each site's report to the file.
/// - The older switches still work: `VELA_LIVE_GIF_TESTS=1` checks the GIF
///   sites and `VELA_LIVE_REDDIT_TESTS=1` the Reddit ones.
enum LiveMediaGate {
    static let environment = ProcessInfo.processInfo.environment

    /// The sites to check, in registry order; empty when the suite is off.
    static let sites: [MediaSite] = {
        var categories: Set<MediaSite.Category> = []
        if environment["VELA_LIVE_MEDIA_TESTS"].map(isOn) == true { categories = Set(MediaSite.Category.allCases) }
        if environment["VELA_LIVE_GIF_TESTS"].map(isOn) == true { categories.insert(.gifs) }
        if environment["VELA_LIVE_REDDIT_TESTS"].map(isOn) == true { categories.insert(.reddit) }
        var sites = MediaSites.all.filter { categories.contains($0.category) }
        if let only = environment["VELA_LIVE_MEDIA_SITES"]?.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }),
           !only.isEmpty {
            sites = sites.filter { only.contains($0.id) }
        }
        return sites
    }()

    static var isEnabled: Bool { !sites.isEmpty }

    /// Set but not "0", "false" or "no".
    private static func isOn(_ value: String) -> Bool {
        !["", "0", "false", "no"].contains(value.lowercased())
    }

    static func appendToReport(_ text: String) {
        guard let path = environment["VELA_MEDIA_REPORT"], !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }
}

@Suite("Live media sites", .enabled(if: LiveMediaGate.isEnabled), .serialized)
struct LiveMediaSiteTests {
    /// One site at a time, each sample one request chain at a time.
    @Test(arguments: LiveMediaGate.sites.map(\.id))
    func siteStillWorks(_ id: String) async throws {
        let site = try #require(MediaSites.site(id))
        let result = await MediaSiteChecker().check(site)
        print(result.report, terminator: "")
        LiveMediaGate.appendToReport(result.report)
        for failure in result.failures {
            Issue.record("\(site.name): \(failure)")
        }
    }
}
