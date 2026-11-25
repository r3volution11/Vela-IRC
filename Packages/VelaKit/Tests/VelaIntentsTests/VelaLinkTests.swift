// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntents

/// `vela://` links, parsed: every route, the forms people write by hand,
/// and links made to mislead.
@Suite("vela:// links")
struct VelaLinkTests {
    private func parse(_ string: String) -> VelaLink? {
        URL(string: string).flatMap(VelaLink.parse)
    }

    private let network = UUID(uuidString: "6B1D9C6E-1234-4C5D-8E9F-0A1B2C3D4E5F")!

    // MARK: Routes

    @Test func show() {
        #expect(parse("vela://") == .show)
        #expect(parse("vela://show") == .show)
        #expect(parse("VELA://Show") == .show)
        #expect(parse("vela-dev://show") == .show)
        // Anything more makes it something else.
        #expect(parse("vela://show?x=1") == nil)
        #expect(parse("vela://show/extra") == nil)
    }

    @Test func open() {
        #expect(parse("vela://open?network=Libera.Chat&channel=%23vela") == .open(ConversationReference(.channel("#vela"), network: "Libera.Chat")))
        #expect(parse("vela://open?channel=vela") == .open(ConversationReference(.channel("vela"))))
        #expect(parse("vela://open?nick=marisol&network=OFTC") == .open(ConversationReference(.nick("marisol"), network: "OFTC")))
        // Network names may have spaces; channel names and nicks can't.
        #expect(parse("vela://open?network=Ergo%20Testnet&channel=%23ergo") == .open(ConversationReference(.channel("#ergo"), network: "Ergo Testnet")))
        #expect(parse("vela://open?id=\(network.uuidString)/%23vela") == .open(ConversationReference(.id(BufferID(networkID: network, foldedName: "#vela")))))
        // Names of parameters ignore case; their values keep theirs.
        #expect(parse("vela://OPEN?Network=Libera.Chat&Channel=%23Vela") == .open(ConversationReference(.channel("#Vela"), network: "Libera.Chat")))
    }

    @Test func openNeedsExactlyOneTarget() {
        #expect(parse("vela://open") == nil)
        #expect(parse("vela://open?network=Libera.Chat") == nil)
        #expect(parse("vela://open?channel=%23a&nick=b") == nil)
        #expect(parse("vela://open?channel=%23a&text=hi") == nil)
        #expect(parse("vela://open?id=not-an-id") == nil)
    }

    @Test func join() {
        #expect(parse("vela://join/%23vela") == .join(channel: "#vela", network: nil))
        #expect(parse("vela://join?channel=%23vela&network=Libera.Chat") == .join(channel: "#vela", network: "Libera.Chat"))
        #expect(parse("vela://join/%23vela?network=Libera.Chat") == .join(channel: "#vela", network: "Libera.Chat"))
        // A channel in the path and the query could be either.
        #expect(parse("vela://join/%23a?channel=%23b") == nil)
        #expect(parse("vela://join") == nil)
        #expect(parse("vela://join?channel=%23a&key=secret") == nil)
    }

    /// A "#" typed as it is starts the URL's fragment: it's put back.
    @Test func unencodedHashes() {
        #expect(parse("vela://join/#vela") == .join(channel: "#vela", network: nil))
        #expect(parse("vela://open?network=Libera.Chat&channel=#vela") == .open(ConversationReference(.channel("#vela"), network: "Libera.Chat")))
        #expect(parse("vela://join/##linux") == .join(channel: "##linux", network: nil))
    }

    @Test func catchUp() {
        #expect(parse("vela://catchup") == .catchUp(nil))
        #expect(parse("vela://catch-up?channel=%23vela") == .catchUp(ConversationReference(.channel("#vela"))))
        #expect(parse("vela://catchup?network=Libera.Chat&channel=%23vela") == .catchUp(ConversationReference(.channel("#vela"), network: "Libera.Chat")))
        #expect(parse("vela://catchup?text=hi") == nil)
    }

    @Test func recap() {
        #expect(parse("vela://recap") == .recap(RecapLink()))
        #expect(parse("vela://recap?network=Libera.Chat") == .recap(RecapLink(network: "Libera.Chat")))
        #expect(parse("vela://recap?network=Libera.Chat&channel=%23vela&span=today") == .recap(RecapLink(
            conversation: ConversationReference(.channel("#vela"), network: "Libera.Chat"), span: .today
        )))
        #expect(parse("vela://recap?person=%40marisol&span=1w") == .recap(RecapLink(person: "marisol", span: .lastWeek)))
        #expect(parse("vela://recap?span=never") == nil)
        #expect(parse("vela://recap?text=hi") == nil)
    }

    @Test(arguments: [
        ("unread", RecapSpanOption.sinceUnread), ("sinceUnread", .sinceUnread), ("30m", .lastHalfHour), ("lastHour", .lastHour),
        ("1h", .lastHour), ("4h", .lastFourHours), ("today", .today), ("1d", .lastDay), ("day", .lastDay),
        ("3d", .lastThreeDays), ("week", .lastWeek), ("LASTWEEK", .lastWeek),
    ])
    func recapSpans(_ value: String, _ span: RecapSpanOption) {
        #expect(RecapSpanOption(linkValue: value) == span)
    }

    @Test func draft() {
        #expect(parse("vela://draft?channel=%23vela&text=hello%20there") == .draft(ConversationReference(.channel("#vela")), text: "hello there"))
        #expect(parse("vela://draft?nick=marisol&network=OFTC&text=hi") == .draft(ConversationReference(.nick("marisol"), network: "OFTC"), text: "hi"))
        // "+" is a plus, as RFC 3986 says, not a space.
        #expect(parse("vela://draft?channel=%23c&text=1+1") == .draft(ConversationReference(.channel("#c")), text: "1+1"))
        // Multi-line text keeps its lines, with Windows line endings made plain.
        #expect(parse("vela://draft?channel=%23c&text=a%0D%0Ab") == .draft(ConversationReference(.channel("#c")), text: "a\nb"))
        #expect(parse("vela://draft?channel=%23vela") == nil)
        #expect(parse("vela://draft?text=hi") == nil)
        #expect(parse("vela://draft?channel=%23vela&text=%20%20") == nil)
    }

    @Test func search() {
        #expect(parse("vela://search?q=deploy%20friday") == .search(query: "deploy friday", in: nil))
        #expect(parse("vela://search?query=deploy") == .search(query: "deploy", in: nil))
        #expect(parse("vela://search?q=deploy&network=Libera.Chat") == .search(query: "deploy", in: .network("Libera.Chat")))
        #expect(parse("vela://search?q=deploy&channel=%23vela") == .search(query: "deploy", in: .conversation(ConversationReference(.channel("#vela")))))
        #expect(parse("vela://search") == nil)
        #expect(parse("vela://search?q=a&query=b") == nil)
        #expect(parse("vela://search?q=%0A") == nil)
    }

    /// Every route made with ``VelaLink/url(scheme:)`` reads back the same.
    @Test func canonicalLinksRoundTrip() throws {
        let links: [VelaLink] = [
            .show,
            .open(ConversationReference(.channel("#c++"), network: "Libera.Chat")),
            .open(ConversationReference(.nick("mari_sol"))),
            .open(ConversationReference(.id(BufferID(networkID: network, foldedName: "#vela")))),
            .join(channel: "#vela", network: nil),
            .join(channel: "&local", network: "Ergo"),
            .catchUp(nil),
            .catchUp(ConversationReference(.channel("#vela"), network: "OFTC")),
            .recap(RecapLink()),
            .recap(RecapLink(conversation: ConversationReference(.channel("#vela")), person: "marisol", span: .lastFourHours)),
            .recap(RecapLink(network: "Libera.Chat", span: .today)),
            .draft(ConversationReference(.channel("#vela")), text: "a & b = c + d #e?\nline two"),
            .search(query: "50% off & more", in: .network("Libera.Chat")),
            .search(query: "x", in: .conversation(ConversationReference(.nick("marisol")))),
        ]
        for link in links {
            for scheme in ["vela", "vela-dev"] {
                let url = try #require(link.url(scheme: scheme))
                #expect(VelaLink.parse(url) == link, "\(url)")
            }
        }
    }

    // MARK: Hostile and malformed

    @Test(arguments: [
        "https://velairc.app/open?channel=%23vela",  // another scheme
        "velax://show",
        "vela://unknown",
        "vela://open?channel=%23a&channel=%23b",  // the same parameter twice
        "vela://open?channel=%23a%20b",  // a space in a channel name
        "vela://open?channel=%23a,%23b",  // two channels
        "vela://open?channel=%23a%07",  // BEL
        "vela://open?channel=%23a%00",  // NUL
        "vela://open?nick=evil%E2%80%AEtxt",  // a direction override
        "vela://open?channel=",
        "vela://join/",
        "vela://draft?channel=%23vela&text=%07%01",  // only control characters
    ])
    func refused(_ string: String) {
        #expect(parse(string) == nil, "\(string)")
    }

    @Test func overlongValuesAreRefused() {
        let long = String(repeating: "a", count: VelaLink.maximumNameLength + 1)
        #expect(parse("vela://open?channel=%23\(long)") == nil)
        #expect(parse("vela://open?network=\(long)&channel=%23a") == nil)
        let text = String(repeating: "x", count: VelaLink.maximumDraftLength + 1)
        #expect(parse("vela://draft?channel=%23a&text=\(text)") == nil)
        let query = String(repeating: "q", count: VelaLink.maximumQueryLength + 1)
        #expect(parse("vela://search?q=\(query)") == nil)
    }

    /// Text for the message box loses whatever could hide what you'd send:
    /// IRC formatting codes, other control characters and direction
    /// overrides. Newlines and tabs stay.
    @Test func draftTextIsCleaned() {
        #expect(VelaLink.cleanDraft("hi\u{03}4,4hidden\u{0F} there") == "hi4,4hidden there")
        #expect(VelaLink.cleanDraft("abc\u{202E}fed\u{202C}") == "abcfed")
        #expect(VelaLink.cleanDraft("one\ttwo\nthree") == "one\ttwo\nthree")
        #expect(VelaLink.cleanDraft("\u{02}\u{1F}") == nil)
    }

    // MARK: Drafts in the message box

    /// What a link's text does to the message box: it's added, never runs
    /// as a command, and never replaces what you were typing.
    @Test func linkDraftsAreAddedSafely() {
        // An empty box gets the text.
        #expect(ShowRequest.composerText(existing: nil, draft: "hello", appending: true) == "hello")
        #expect(ShowRequest.composerText(existing: "  ", draft: "hello", appending: true) == "hello")
        // Text that starts with "/" is escaped, so Return sends it as text.
        #expect(ShowRequest.composerText(existing: nil, draft: "/quit bye", appending: true) == "//quit bye")
        #expect(InputCommand.parse(ShowRequest.composerText(existing: nil, draft: "/msg NickServ DROP", appending: true)!) == .say("/msg NickServ DROP"))
        // What you were typing stays, with the text after it.
        #expect(ShowRequest.composerText(existing: "half typed", draft: "hello", appending: true) == "half typed hello")
        #expect(ShowRequest.composerText(existing: "half typed ", draft: "hello", appending: true) == "half typed hello")
        #expect(ShowRequest.composerText(existing: "first", draft: "a\nb", appending: true) == "first\na\nb")
        // A command you're typing is left alone.
        #expect(ShowRequest.composerText(existing: "/msg bob ", draft: "hello", appending: true) == nil)
        // Siri's drafts still replace, as before.
        #expect(ShowRequest.composerText(existing: "old", draft: "new", appending: false) == "new")
    }
}
