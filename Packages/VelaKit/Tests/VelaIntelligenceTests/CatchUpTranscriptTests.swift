// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIntelligence

@Suite("Catch me up transcript")
struct CatchUpTranscriptTests {
    typealias F = CatchUpFixtures

    @Test func numbersMessagesAndActions() {
        let transcript = CatchUpTranscript(lines: [
            F.line("alice", "hello there"),
            F.line("bob", "waves", action: true),
        ], ownNick: "doug")
        #expect(transcript.entries.map(\.text) == ["[1] alice: hello there", "[2] * bob waves"])
        #expect(transcript.text == "[1] alice: hello there\n[2] * bob waves")
    }

    @Test func dropsEmptyLinesAndCollapsesWhitespace() {
        let transcript = CatchUpTranscript(lines: [
            F.line("alice", "   "),
            F.line("", "no nick"),
            F.line("bob", "two\nlines\t and   spaces "),
        ], ownNick: "doug")
        #expect(transcript.entries.map(\.text) == ["[1] bob: two lines and spaces"])
        #expect(transcript.availableLines == 1)
    }

    @Test func reducesLinksToTheirHost() {
        let text = CatchUpTranscript.clean("see https://www.youtube.com/watch?v=aqz-KE-bpKQ and www.Example.org/a/b?c=d, or ftp://files.host.net/x")
        #expect(text == "see (link to youtube.com) and (link to example.org), or (link to files.host.net)")
        #expect(CatchUpTranscript.clean("docs at https://swift.org/blog/.") == "docs at (link to swift.org).")
        #expect(CatchUpTranscript.clean("no links here") == "no links here")
    }

    @Test func truncatesLongLines() {
        let long = String(repeating: "word ", count: 200)
        let cleaned = CatchUpTranscript.clean(long)
        #expect(cleaned.count <= CatchUpTranscript.maximumLineLength)
        #expect(cleaned.hasSuffix("…"))
        let entry = CatchUpTranscript(lines: [F.line("alice", long)], ownNick: "doug").entries[0]
        #expect(entry.message.count <= CatchUpTranscript.maximumLineLength)
    }

    @Test func keepsTheNewestLinesAndMapsNumbersBackToIDs() {
        let lines = F.chatter(10)
        let transcript = CatchUpTranscript(lines: lines, ownNick: "doug", maximumLines: 4)
        #expect(transcript.entries.count == 4)
        #expect(transcript.isCapped)
        #expect(transcript.entries.map(\.number) == [1, 2, 3, 4])
        // Number 1 is the oldest line kept: the seventh.
        #expect(transcript.lineID(forNumber: 1) == lines[6].id)
        #expect(transcript.lineID(forNumber: 4) == lines[9].id)
        #expect(transcript.lineID(forNumber: 0) == nil)
        #expect(transcript.lineID(forNumber: 5) == nil)
    }

    @Test func capsAtSixHundredLinesByDefault() {
        let transcript = CatchUpTranscript(lines: F.chatter(700), ownNick: "doug")
        #expect(transcript.entries.count == 600)
        #expect(transcript.availableLines == 700)
    }

    @Test func matchesNicksAsWritten() {
        let transcript = CatchUpTranscript(lines: [F.line("Kenji", "hi"), F.line("ada_", "yo")], ownNick: "doug")
        #expect(transcript.canonicalNick("kenji") == "Kenji")
        #expect(transcript.canonicalNick("@Kenji") == "Kenji")
        #expect(transcript.canonicalNick("ADA_") == "ada_")
        #expect(transcript.canonicalNick("doug") == "doug")
        #expect(transcript.canonicalNick("nobody") == nil)
        #expect(transcript.nicks == ["Kenji", "ada_"])
    }

    @Test func noticesMentionsOfTheReader() {
        let mentioned = CatchUpTranscript(lines: [F.line("wren", "doug: can you review?")], ownNick: "doug")
        #expect(mentioned.mentionsOwnNick)
        let partialWord = CatchUpTranscript(lines: [F.line("wren", "dougie says hi")], ownNick: "doug")
        #expect(!partialWord.mentionsOwnNick)
        let ownLine = CatchUpTranscript(lines: [F.line("doug", "doug is me")], ownNick: "doug")
        #expect(!ownLine.mentionsOwnNick)
        let caseInsensitive = CatchUpTranscript(lines: [F.line("wren", "thanks Doug!")], ownNick: "doug")
        #expect(caseInsensitive.mentionsOfOwnNick.count == 1)
    }
}
