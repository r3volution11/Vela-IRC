// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Testing
@testable import VelaUI

private typealias Kind = ProtectedTextRanges.Kind

/// The protected text, as (substring, kind) pairs in order.
private func spans(_ text: String, nicks: [String] = [], channelTypes: Set<Character> = ["#", "&"]) -> [(String, Kind)] {
    let ranges = ProtectedTextRanges.compute(text: text, nicks: nicks, channelTypes: channelTypes)
    return ranges.spans.map { ((text as NSString).substring(with: $0.range), $0.kind) }
}

private func has(_ found: [(String, Kind)], _ text: String, _ kind: Kind) -> Bool {
    found.contains { $0.0 == text && $0.1 == kind }
}

/// The range of the first `needle` in `text`.
private func range(of needle: String, in text: String) -> NSRange {
    (text as NSString).range(of: needle)
}

@Suite("Protected text ranges: commands")
struct ProtectedCommandTests {
    @Test func plainTextHasNoCommand() {
        #expect(spans("hello there, how are you").isEmpty)
    }

    @Test func otherCommandsProtectTheWholeLine() {
        let found = spans("/join #vela key")
        #expect(has(found, "/join", .command))
        #expect(has(found, " #vela key", .arguments))
        #expect(has(found, "#vela", .channel))

        let kick = ProtectedTextRanges.compute(text: "/kick troll go away")
        #expect(kick.intersects(range(of: "away", in: "/kick troll go away")))
        // Arguments keep their spelling underlines (a kick reason is prose)…
        #expect(!kick.hidesSpelling(in: range(of: "away", in: "/kick troll go away")))
        // …but the command itself doesn't.
        #expect(kick.hidesSpelling(in: range(of: "kick", in: "/kick troll go away")))
    }

    @Test func doubleSlashIsPlainText() {
        let text = "//join is how you join"
        let found = spans(text)
        #expect(!found.contains { $0.1 == .command || $0.1 == .arguments })
        #expect(!ProtectedTextRanges.compute(text: text).intersects(range(of: "join", in: text)))
    }

    @Test func leadingNewlinesDontHideACommand() {
        #expect(has(spans("\n/nick vela_"), "/nick", .command))
        // A leading space does (the line is sent as a message).
        #expect(spans(" /nick vela_").isEmpty)
    }

    @Test func commandNamesIgnoreCase() {
        let found = spans("/MSG Doug hi")
        #expect(has(found, "/MSG", .command))
        #expect(has(found, "Doug", .target))
    }

    @Test(arguments: ["/msg", "/privmsg", "/notice", "/query", "/q"])
    func targetsAreProtectedAndTheMessageIsProse(_ command: String) {
        let text = "\(command) someone helo wrold"
        let ranges = ProtectedTextRanges.compute(text: text)
        let found = spans(text)
        #expect(has(found, command, .command))
        #expect(has(found, "someone", .target))
        #expect(!ranges.intersects(range(of: "helo", in: text)))
        #expect(!ranges.intersects(range(of: "wrold", in: text)))
    }

    @Test func queryWithoutAMessage() {
        let found = spans("/query alice")
        #expect(has(found, "alice", .target))
        #expect(found.count == 2)
    }

    @Test(arguments: ["/me", "/say", "/away", "/quit"])
    func proseCommandsLeaveTheirTextCheckable(_ command: String) {
        let text = "\(command) gone fishin for teh day"
        let ranges = ProtectedTextRanges.compute(text: text)
        #expect(has(spans(text), command, .command))
        #expect(!ranges.intersects(range(of: "teh", in: text)))
        #expect(!ranges.intersects(range(of: "gone", in: text)))
    }

    @Test(arguments: ["/topic", "/part", "/leave"])
    func channelArgumentIsATarget(_ command: String) {
        let text = "\(command) #vela see you tomorow"
        let ranges = ProtectedTextRanges.compute(text: text)
        let found = spans(text)
        #expect(has(found, "#vela", .target))
        #expect(!ranges.intersects(range(of: "tomorow", in: text)))

        // Without a channel, everything after the command is prose.
        let bare = "\(command) see you tomorow"
        let bareFound = spans(bare)
        #expect(!bareFound.contains { $0.1 == .target })
        #expect(!ProtectedTextRanges.compute(text: bare).intersects(range(of: "see", in: bare)))
    }

    @Test func proseInsideCommandsStillProtectsTokens() {
        let text = "/me waves at bob in #swift, see https://swift.org"
        let found = spans(text, nicks: ["bob"])
        #expect(has(found, "bob", .nick))
        #expect(has(found, "#swift", .channel))
        #expect(has(found, "https://swift.org", .link))
        #expect(!ProtectedTextRanges.compute(text: text, nicks: ["bob"]).intersects(range(of: "waves", in: text)))
    }
}

@Suite("Protected text ranges: tokens")
struct ProtectedTokenTests {
    @Test func links() {
        let text = "see https://example.com/a_b?x=1, or www.apple.com."
        let found = spans(text)
        #expect(has(found, "https://example.com/a_b?x=1", .link))
        #expect(has(found, "www.apple.com", .link))
    }

    @Test func channels() {
        let found = spans("come to #swift-lang. or (&local) maybe")
        #expect(has(found, "#swift-lang", .channel))
        #expect(has(found, "&local", .channel))
        // Not after a letter, and not a lone prefix.
        #expect(spans("I like C# and R&D, # alone").isEmpty)
        // Only this network's prefixes.
        #expect(!spans("&local", channelTypes: ["#"]).contains { $0.1 == .channel })
    }

    @Test func nicksAreCaseInsensitiveAndWordBounded() {
        let text = "Doug and DOUG met dougie and doug's friend"
        let found = spans(text, nicks: ["doug"]).filter { $0.1 == .nick }.map(\.0)
        #expect(found == ["Doug", "DOUG", "doug"])
    }

    @Test func nicksWithSpecialCharacters() {
        let found = spans("ask foo|away or [bar] or baz_ about it", nicks: ["foo|away", "bar", "baz"])
            .filter { $0.1 == .nick }.map(\.0)
        #expect(found == ["foo|away", "bar", "baz"])
    }

    @Test func nicksUseUTF16Offsets() throws {
        let text = "👍 doug"
        let span = try #require(ProtectedTextRanges.compute(text: text, nicks: ["doug"]).spans.first)
        #expect(span.range == NSRange(location: 3, length: 4))
    }

    @Test func addressPrefix() {
        #expect(has(spans("doug: try it now"), "doug:", .address))
        #expect(has(spans("hi\n  alice: and you"), "alice:", .address))
        // Not without a space after the colon, and not mid-line.
        #expect(!spans("doug:hi").contains { $0.1 == .address })
        #expect(!spans("hey doug: hi").contains { $0.1 == .address })
        #expect(!spans("http://example.com").contains { $0.1 == .address })
    }

    @Test func emojiCodes() {
        let found = spans("nice :thumbsup: and :tada")
        #expect(has(found, ":thumbsup:", .emoji))
        #expect(has(found, ":tada", .emoji))
        // Times and addresses aren't emoji.
        #expect(!spans("at 10:30 ok").contains { $0.1 == .emoji })
    }

    @Test func codeSpans() {
        #expect(has(spans("use `git rebase -i` now"), "`git rebase -i`", .code))
        // Unclosed: to the end of the line.
        #expect(has(spans("try `foo bar\nnext line"), "`foo bar", .code))
        #expect(has(spans("a ```let x = `y` ``` b"), "```let x = `y` ```", .code))
    }

    @Test func mergedAndClippedRanges() {
        let text = "/join #a,#b"
        let ranges = ProtectedTextRanges.compute(text: text)
        // The command and its arguments touch, so they merge into one.
        #expect(ranges.mergedRanges == [NSRange(location: 0, length: 11)])
        #expect(ranges.ranges(in: NSRange(location: 6, length: 2)) == [NSRange(location: 6, length: 2)])
        #expect(ProtectedTextRanges.compute(text: "plain words").ranges(in: NSRange(location: 0, length: 11)).isEmpty)
    }
}

@Suite("Text checking filter")
struct TextCheckingFilterTests {
    private let text = "/msg doug teh cat said “hi” -- see `x--y` :thum"

    private var protected: ProtectedTextRanges {
        ProtectedTextRanges.compute(text: text, nicks: ["doug"])
    }

    private var length: Int { (text as NSString).length }

    private func kept(_ results: [NSTextCheckingResult], inserted: [NSRange] = [], allowsSubstitutions: Bool = true) -> [NSTextCheckingResult] {
        TextCheckingFilter.filter(
            results, textLength: length, protected: protected, inserted: inserted, allowsSubstitutions: allowsSubstitutions
        )
    }

    private func r(_ needle: String) -> NSRange { range(of: needle, in: text) }

    @Test func correctionsSkipCommandsAndTargets() {
        let command = NSTextCheckingResult.correctionCheckingResult(range: r("/msg"), replacementString: "/mag")
        let target = NSTextCheckingResult.correctionCheckingResult(range: r("doug"), replacementString: "dough")
        let prose = NSTextCheckingResult.correctionCheckingResult(range: r("teh"), replacementString: "the")
        #expect(kept([command, target, prose]) == [prose])
    }

    @Test func substitutionsSkipCodeAndEmoji() {
        let inCode = NSTextCheckingResult.dashCheckingResult(range: r("--y"), replacementString: "—y")
        let inProse = NSTextCheckingResult.dashCheckingResult(range: r("-- "), replacementString: "— ")
        let emoji = NSTextCheckingResult.replacementCheckingResult(range: r(":thum"), replacementString: ":thumb")
        let quote = NSTextCheckingResult.quoteCheckingResult(range: r("“"), replacementString: "\"")
        #expect(kept([inCode, inProse, emoji, quote]) == [inProse, quote])
    }

    @Test func spellingUnderlinesSkipNicksButStayOnProse() {
        let nick = NSTextCheckingResult.spellCheckingResult(range: r("doug"))
        let prose = NSTextCheckingResult.spellCheckingResult(range: r("teh"))
        #expect(kept([nick, prose]) == [prose])
    }

    @Test func grammarIsKept() {
        let grammar = NSTextCheckingResult.grammarCheckingResult(range: r("doug teh cat"), details: [])
        #expect(kept([grammar]) == [grammar])
    }

    @Test func insertedTextIsNeverCorrected() {
        let prose = NSTextCheckingResult.correctionCheckingResult(range: r("teh"), replacementString: "the")
        let underline = NSTextCheckingResult.spellCheckingResult(range: r("teh"))
        #expect(kept([prose, underline], inserted: [r("teh cat")]) == [underline])
    }

    @Test func staleResultsAreDropped() {
        let beyond = NSTextCheckingResult.spellCheckingResult(range: NSRange(location: length - 2, length: 5))
        #expect(kept([beyond]).isEmpty)
    }

    @Test func writingToolsPausesSubstitutions() {
        let prose = NSTextCheckingResult.correctionCheckingResult(range: r("teh"), replacementString: "the")
        let underline = NSTextCheckingResult.spellCheckingResult(range: r("teh"))
        #expect(kept([prose, underline], allowsSubstitutions: false) == [underline])
    }
}

@Suite("Inserted text ranges")
struct InsertedTextRangesTests {
    /// Applies an edit the way NSTextStorage reports it.
    private func edit(_ ranges: inout InsertedTextRanges, replacing old: NSRange, with length: Int, inserted: Bool) {
        ranges.record(
            editedRange: NSRange(location: old.location, length: length),
            changeInLength: length - old.length,
            inserted: inserted
        )
    }

    @Test func followsEditsAroundIt() {
        var ranges = InsertedTextRanges()
        edit(&ranges, replacing: NSRange(location: 0, length: 0), with: 10, inserted: true)
        #expect(ranges.ranges == [NSRange(location: 0, length: 10)])

        // Typing after it leaves it alone.
        edit(&ranges, replacing: NSRange(location: 10, length: 0), with: 3, inserted: false)
        #expect(ranges.ranges == [NSRange(location: 0, length: 10)])

        // Typing before it moves it.
        edit(&ranges, replacing: NSRange(location: 0, length: 0), with: 2, inserted: false)
        #expect(ranges.ranges == [NSRange(location: 2, length: 10)])

        // Typing inside it splits it.
        edit(&ranges, replacing: NSRange(location: 5, length: 0), with: 1, inserted: false)
        #expect(ranges.ranges == [NSRange(location: 2, length: 3), NSRange(location: 6, length: 7)])

        // Deleting across it (and the typed character) trims it; what's
        // left touches, so it's one range again.
        edit(&ranges, replacing: NSRange(location: 4, length: 4), with: 0, inserted: false)
        #expect(ranges.ranges == [NSRange(location: 2, length: 7)])
    }

    @Test func replacingEverything() {
        var ranges = InsertedTextRanges()
        edit(&ranges, replacing: NSRange(location: 0, length: 0), with: 5, inserted: false)
        edit(&ranges, replacing: NSRange(location: 0, length: 5), with: 8, inserted: true)
        #expect(ranges.ranges == [NSRange(location: 0, length: 8)])
        // Sending clears the text.
        edit(&ranges, replacing: NSRange(location: 0, length: 8), with: 0, inserted: true)
        #expect(ranges.ranges.isEmpty)
    }

    @Test func adjacentInsertionsMerge() {
        var ranges = InsertedTextRanges()
        edit(&ranges, replacing: NSRange(location: 0, length: 0), with: 4, inserted: true)
        edit(&ranges, replacing: NSRange(location: 4, length: 0), with: 6, inserted: true)
        #expect(ranges.ranges == [NSRange(location: 0, length: 10)])
    }
}
