// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import VelaCore

@MainActor
@Suite("Input commands")
struct InputCommandTests {
    @Test(arguments: [
        ("hello", InputCommand.say("hello")),
        ("//slash at start", .say("/slash at start")),
        ("/me waves", .action("waves")),
        ("/msg alice hi there", .message(target: "alice", text: "hi there")),
        ("/query bob", .query(nick: "bob", text: nil)),
        ("/q bob yo", .query(nick: "bob", text: "yo")),
        ("/join #a,#b key1", .join(channels: ["#a", "#b"], keys: ["key1"])),
        ("/part", .part(channel: nil, reason: nil)),
        ("/part #a later", .part(channel: "#a", reason: "later")),
        ("/part see you", .part(channel: nil, reason: "see you")),
        ("/nick vela", .nick("vela")),
        ("/topic #a New topic", .topic(channel: "#a", text: "New topic")),
        ("/topic", .topic(channel: nil, text: nil)),
        ("/op alice bob", .memberMode(sign: "+", mode: "o", nicks: ["alice", "bob"])),
        ("/devoice carol", .memberMode(sign: "-", mode: "v", nicks: ["carol"])),
        ("/ctcp alice version", .ctcp(target: "alice", command: "VERSION", argument: nil)),
        ("/raw PRIVMSG #a :x", .raw("PRIVMSG #a :x")),
        ("/away lunch", .away("lunch")),
        ("/back", .back),
        ("/quit bye all", .quit("bye all")),
        ("/foo bar", .unknown(command: "foo", args: "bar")),
        ("/msg", .usage("/msg <target> <message>")),
    ])
    func parses(input: String, expected: InputCommand) {
        #expect(InputCommand.parse(input) == expected)
    }

    @Test func blankInputIsIgnored() {
        #expect(InputCommand.parse("   ") == nil)
        #expect(InputCommand.parse("") == nil)
    }

    @Test func highlightMatcherUsesWordBoundaries() {
        let matcher = HighlightMatcher(nick: "doug", words: ["vela"])
        #expect(matcher.matches("hey doug"))
        #expect(matcher.matches("Doug: ping"))
        #expect(matcher.matches("I love Vela!"))
        #expect(!matcher.matches("doughnut"))
        #expect(!matcher.matches("doug_"))
        #expect(!matcher.matches("[doug]bot"))
    }

    @Test func ignoreMatcherGlobs() {
        let matcher = IgnoreMatcher(masks: ["spam*", "*!*@evil.example"])
        #expect(matcher.matches("spammer!x@y"))
        #expect(matcher.matches("alice!a@evil.example"))
        #expect(!matcher.matches("alice!a@good.example"))
    }
}
