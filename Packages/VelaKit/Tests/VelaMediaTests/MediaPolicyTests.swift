// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaMedia

@Suite struct MediaPolicyTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test func defaults() {
        let policy = MediaPolicy()
        #expect(policy.autoLoad)
        #expect(policy.showLinkCards)
        #expect(policy.loadVideoEmbeds)
        #expect(policy.maxImageBytes == 10 * 1024 * 1024)
        #expect(!policy.restrictToAllowedDomains)
        #expect(policy.allows(url("https://example.com/a.png")))
        #expect(policy.allows(url("http://example.com/")))
    }

    @Test func onlyHTTPSchemes() {
        let policy = MediaPolicy()
        #expect(!policy.allows(url("ftp://example.com/a.png")))
        #expect(!policy.allows(url("file:///etc/passwd")))
        #expect(!policy.allows(url("data:text/plain,hi")))
    }

    @Test func blockedDomainsMatchOnLabelBoundaries() {
        let policy = MediaPolicy(blockedDomains: ["example.com"])
        #expect(!policy.allows(url("https://example.com/")))
        #expect(!policy.allows(url("https://img.example.com/x.png")))
        #expect(!policy.allows(url("https://a.b.EXAMPLE.com/")))
        #expect(!policy.allows(url("https://example.com./")))
        #expect(policy.allows(url("https://badexample.com/")))
        #expect(policy.allows(url("https://example.com.evil.net/")))
        #expect(policy.allows(url("https://example.org/")))
    }

    @Test func domainEntriesAreNormalized() {
        for entry in ["*.example.com", ".example.com", "EXAMPLE.COM", "https://example.com/path", " example.com ",
                      "example.com:8443", "example.com."] {
            let policy = MediaPolicy(blockedDomains: [entry])
            #expect(!policy.allows(url("https://cdn.example.com/a")), "\(entry)")
            #expect(policy.allows(url("https://notexample.com/a")), "\(entry)")
        }
        #expect(MediaPolicy(blockedDomains: ["", "   ", "*."]).allows(url("https://example.com")))
    }

    @Test func allowListRestriction() {
        var policy = MediaPolicy(allowedDomains: ["imgur.com", "youtube.com"], restrictToAllowedDomains: true)
        #expect(policy.allows(url("https://i.imgur.com/a.png")))
        #expect(policy.allows(url("https://www.youtube.com/watch?v=dQw4w9WgXcQ")))
        #expect(!policy.allows(url("https://example.com/")))
        #expect(!policy.allows(url("https://notimgur.com/")))

        // Blocking wins over allowing.
        policy.blockedDomains = ["i.imgur.com"]
        #expect(!policy.allows(url("https://i.imgur.com/a.png")))
        #expect(policy.allows(url("https://imgur.com/gallery/x")))

        // The allow list is ignored unless restriction is on.
        policy.restrictToAllowedDomains = false
        #expect(policy.allows(url("https://example.com/")))
    }

    @Test(arguments: [
        "http://localhost/", "http://localhost:8080/admin", "http://app.localhost/", "http://127.0.0.1/",
        "http://10.0.0.1/", "http://172.16.5.4/", "http://172.31.255.255/", "http://192.168.1.1/reboot",
        "http://169.254.169.254/latest/meta-data/", "http://100.64.0.1/", "http://0.0.0.0/",
        "http://[::1]/", "http://[fe80::1]/", "http://[fd12:3456::1]/", "http://[::ffff:192.168.0.1]/",
        "http://router/", "http://nas.local/", "http://printer.lan/", "http://box.home.arpa/",
    ])
    func privateNetworkHostsAreBlockedByDefault(_ string: String) {
        #expect(!MediaPolicy().allows(url(string)))
        #expect(MediaPolicy(allowPrivateNetworkHosts: true).allows(url(string)))
    }

    @Test(arguments: ["http://172.32.0.1/", "http://8.8.8.8/", "http://[2606:4700::1111]/", "http://192.169.0.1/"])
    func publicIPLiteralsAreAllowed(_ string: String) {
        #expect(MediaPolicy().allows(url(string)))
    }

    @Test func automaticPreviewSwitches() {
        let page = url("https://example.com/article")
        let video = url("https://youtu.be/dQw4w9WgXcQ")
        let image = url("https://example.com/cat.png")

        #expect(MediaPolicy().permitsAutomaticPreview(of: page))
        #expect(!MediaPolicy(autoLoad: false).permitsAutomaticPreview(of: image))
        #expect(!MediaPolicy(showLinkCards: false).permitsAutomaticPreview(of: page))
        #expect(MediaPolicy(showLinkCards: false).permitsAutomaticPreview(of: image))
        #expect(!MediaPolicy(loadVideoEmbeds: false).permitsAutomaticPreview(of: video))
        #expect(MediaPolicy(loadVideoEmbeds: false).permitsAutomaticPreview(of: page))
        #expect(!MediaPolicy(blockedDomains: ["youtu.be"]).permitsAutomaticPreview(of: video))
    }

    @Test func codableRoundTripAndMissingKeys() throws {
        let policy = MediaPolicy(
            autoLoad: false, blockedDomains: ["a.com"], allowedDomains: ["b.com"],
            restrictToAllowedDomains: true, maxImageBytes: 1234
        )
        let data = try JSONEncoder().encode(policy)
        #expect(try JSONDecoder().decode(MediaPolicy.self, from: data) == policy)

        let partial = try JSONDecoder().decode(MediaPolicy.self, from: Data(#"{"autoLoad": false}"#.utf8))
        #expect(partial == MediaPolicy(autoLoad: false))
    }
}
