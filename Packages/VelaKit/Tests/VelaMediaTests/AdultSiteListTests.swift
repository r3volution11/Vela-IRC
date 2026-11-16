// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

@Suite struct AdultSiteListTests {
    @Test func suffixWalkOnLabelBoundaries() {
        let list = AdultSiteList(domains: ["example.com", "Adult.Example"])
        #expect(list.count == 2)
        #expect(list.contains(host: "example.com"))
        #expect(list.contains(host: "www.example.com"))
        #expect(list.contains(host: "a.b.EXAMPLE.com."))
        #expect(list.contains(host: "cdn.adult.example"))
        #expect(!list.contains(host: "badexample.com"))
        #expect(!list.contains(host: "example.com.evil.net"))
        #expect(!list.contains(host: "example.org"))
        #expect(!list.contains(host: "com"))
        #expect(list.matchingDomain(forHost: "img.www.example.com") == "example.com")
    }

    @Test func mostSpecificListedDomainIsReported() {
        let list = AdultSiteList(domains: ["example.com", "cdn.example.com"])
        #expect(list.matchingDomain(forHost: "a.cdn.example.com") == "cdn.example.com")
    }

    @Test func adultTopLevelDomainsAreBuiltIn() {
        let empty = AdultSiteList(domains: [])
        #expect(empty.count == 0)
        #expect(empty.contains(host: "site.xxx"))
        #expect(empty.contains(host: "a.site.porn"))
        #expect(empty.contains(host: "site.adult"))
        #expect(empty.contains(host: "SITE.SEX"))
        #expect(!empty.contains(host: "xxx.com"))
        #expect(!empty.contains(host: "sex.example"))
        #expect(empty.matchingDomain(forHost: "videos.site.xxx") == "site.xxx")
    }

    @Test func ipLiteralsNeverMatch() {
        let list = AdultSiteList(domains: ["1.2.3.4"])
        #expect(list.count == 0)
        #expect(!list.contains(host: "1.2.3.4"))
        #expect(!list.contains(host: "::1"))
    }

    @Test func parsesListFiles() throws {
        let text = "# Adult domains\r\n# source: test\r\n\r\nExample.com\r\n  spaced.example  \n*.wild.example\n"
            + "0.0.0.0 hosts.example\n127.0.0.1 localhost\ntrailing.example. # inline comment\n#commented.example\n"
            + "\tTabbed.Example\t\nlast.example"
        let list = AdultSiteList(text: text)
        #expect(list.count == 7)
        for host in ["example.com", "spaced.example", "a.wild.example", "hosts.example", "trailing.example",
                     "tabbed.example", "last.example"] {
            #expect(list.contains(host: host), "\(host)")
        }
        #expect(!list.contains(host: "commented.example"))
        #expect(!list.contains(host: "localhost"))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("adult-\(UUID().uuidString).txt")
        try Data(text.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try AdultSiteList(contentsOf: file).count == 7)
    }

    @Test func missingFileThrows() {
        #expect(throws: (any Error).self) {
            try AdultSiteList(contentsOf: URL(fileURLWithPath: "/nonexistent/adult-domains.txt"))
        }
    }

    @Test func bundledListLoads() {
        AdultSiteList.warmUp()
        // Whatever the bundled file holds, the built-in top-level domains apply
        // and ordinary sites don't match.
        #expect(AdultSiteList.bundled.contains(host: "example.xxx"))
        #expect(!AdultSiteList.bundled.contains(host: "example.com"))
    }
}
