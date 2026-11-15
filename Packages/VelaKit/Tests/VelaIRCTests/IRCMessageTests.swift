// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIRC

// Test vectors from https://github.com/ircdocs/parser-tests (CC0).

struct SplitCase: Sendable, CustomTestStringConvertible {
    var input: String
    var tags: [String: String] = [:]
    var source: String?
    var verb: String
    var params: [String] = []

    var testDescription: String { input.debugDescription }
}

private let splitCases: [SplitCase] = [
    SplitCase(input: "foo bar baz asdf", verb: "foo", params: ["bar", "baz", "asdf"]),
    SplitCase(input: ":coolguy foo bar baz asdf", source: "coolguy", verb: "foo", params: ["bar", "baz", "asdf"]),
    SplitCase(input: "foo bar baz :asdf quux", verb: "foo", params: ["bar", "baz", "asdf quux"]),
    SplitCase(input: "foo bar baz :", verb: "foo", params: ["bar", "baz", ""]),
    SplitCase(input: "foo bar baz ::asdf", verb: "foo", params: ["bar", "baz", ":asdf"]),
    SplitCase(input: ":coolguy foo bar baz :asdf quux", source: "coolguy", verb: "foo", params: ["bar", "baz", "asdf quux"]),
    SplitCase(input: ":coolguy foo bar baz :  asdf quux ", source: "coolguy", verb: "foo", params: ["bar", "baz", "  asdf quux "]),
    SplitCase(input: ":coolguy PRIVMSG bar :lol :) ", source: "coolguy", verb: "PRIVMSG", params: ["bar", "lol :) "]),
    SplitCase(input: ":coolguy foo bar baz :", source: "coolguy", verb: "foo", params: ["bar", "baz", ""]),
    SplitCase(input: ":coolguy foo bar baz :  ", source: "coolguy", verb: "foo", params: ["bar", "baz", "  "]),
    SplitCase(input: "@a=b;c=32;k;rt=ql7 foo", tags: ["a": "b", "c": "32", "k": "", "rt": "ql7"], verb: "foo"),
    SplitCase(
        input: "@a=b\\\\and\\nk;c=72\\s45;d=gh\\:764 foo",
        tags: ["a": "b\\and\nk", "c": "72 45", "d": "gh;764"],
        verb: "foo"
    ),
    SplitCase(input: "@c;h=;a=b :quux ab cd", tags: ["c": "", "h": "", "a": "b"], source: "quux", verb: "ab", params: ["cd"]),
    SplitCase(input: ":src JOIN #chan", source: "src", verb: "JOIN", params: ["#chan"]),
    SplitCase(input: ":src JOIN :#chan", source: "src", verb: "JOIN", params: ["#chan"]),
    SplitCase(input: ":src AWAY", source: "src", verb: "AWAY"),
    SplitCase(input: ":src AWAY ", source: "src", verb: "AWAY"),
    SplitCase(input: ":cool\tguy foo bar baz", source: "cool\tguy", verb: "foo", params: ["bar", "baz"]),
    SplitCase(
        input: ":coolguy!ag@net\u{03}5w\u{03}ork.admin PRIVMSG foo :bar baz",
        source: "coolguy!ag@net\u{03}5w\u{03}ork.admin",
        verb: "PRIVMSG",
        params: ["foo", "bar baz"]
    ),
    SplitCase(
        input: ":coolguy!~ag@n\u{02}et\u{03}05w\u{0f}ork.admin PRIVMSG foo :bar baz",
        source: "coolguy!~ag@n\u{02}et\u{03}05w\u{0f}ork.admin",
        verb: "PRIVMSG",
        params: ["foo", "bar baz"]
    ),
    SplitCase(
        input: "@tag1=value1;tag2;vendor1/tag3=value2;vendor2/tag4= :irc.example.com COMMAND param1 param2 :param3 param3",
        tags: ["tag1": "value1", "tag2": "", "vendor1/tag3": "value2", "vendor2/tag4": ""],
        source: "irc.example.com",
        verb: "COMMAND",
        params: ["param1", "param2", "param3 param3"]
    ),
    SplitCase(
        input: ":irc.example.com COMMAND param1 param2 :param3 param3",
        source: "irc.example.com",
        verb: "COMMAND",
        params: ["param1", "param2", "param3 param3"]
    ),
    SplitCase(
        input: "@tag1=value1;tag2;vendor1/tag3=value2;vendor2/tag4 COMMAND param1 param2 :param3 param3",
        tags: ["tag1": "value1", "tag2": "", "vendor1/tag3": "value2", "vendor2/tag4": ""],
        verb: "COMMAND",
        params: ["param1", "param2", "param3 param3"]
    ),
    SplitCase(input: "COMMAND", verb: "COMMAND"),
    SplitCase(input: "@foo=\\\\\\\\\\:\\\\s\\s\\r\\n COMMAND", tags: ["foo": "\\\\;\\s \r\n"], verb: "COMMAND"),
    SplitCase(
        input: ":gravel.mozilla.org 432  #momo :Erroneous Nickname: Illegal characters",
        source: "gravel.mozilla.org",
        verb: "432",
        params: ["#momo", "Erroneous Nickname: Illegal characters"]
    ),
    SplitCase(input: ":gravel.mozilla.org MODE #tckk +n ", source: "gravel.mozilla.org", verb: "MODE", params: ["#tckk", "+n"]),
    SplitCase(
        input: ":services.esper.net MODE #foo-bar +o foobar  ",
        source: "services.esper.net",
        verb: "MODE",
        params: ["#foo-bar", "+o", "foobar"]
    ),
    SplitCase(input: "@tag1=value\\\\ntest COMMAND", tags: ["tag1": "value\\ntest"], verb: "COMMAND"),
    SplitCase(input: "@tag1=value\\1 COMMAND", tags: ["tag1": "value1"], verb: "COMMAND"),
    SplitCase(input: "@tag1=value1\\ COMMAND", tags: ["tag1": "value1"], verb: "COMMAND"),
    SplitCase(input: "@tag1=1;tag2=3;tag3=4;tag1=5 COMMAND", tags: ["tag1": "5", "tag2": "3", "tag3": "4"], verb: "COMMAND"),
    SplitCase(
        input: "@tag1=1;tag2=3;tag3=4;tag1=5;vendor/tag2=8 COMMAND",
        tags: ["tag1": "5", "tag2": "3", "tag3": "4", "vendor/tag2": "8"],
        verb: "COMMAND"
    ),
    SplitCase(input: ":SomeOp MODE #channel :+i", source: "SomeOp", verb: "MODE", params: ["#channel", "+i"]),
    SplitCase(
        input: ":SomeOp MODE #channel +oo SomeUser :AnotherUser",
        source: "SomeOp",
        verb: "MODE",
        params: ["#channel", "+oo", "SomeUser", "AnotherUser"]
    ),
]

@Test("msg-split vectors", arguments: splitCases)
func parsesSplitVectors(_ testCase: SplitCase) throws {
    let message = try #require(IRCMessage(line: testCase.input))
    #expect(message.tags == testCase.tags)
    #expect(message.source?.raw == testCase.source)
    // Commands are normalized to uppercase.
    #expect(message.command == testCase.verb.uppercased())
    #expect(message.params == testCase.params)
}

struct JoinCase: Sendable, CustomTestStringConvertible {
    var tags: [String: String] = [:]
    var source: String?
    var verb: String
    var params: [String] = []
    var matches: Set<String>

    var testDescription: String { matches.sorted().first ?? verb }
}

private let joinCases: [JoinCase] = [
    JoinCase(verb: "foo", params: ["bar", "baz", "asdf"], matches: ["FOO bar baz asdf", "FOO bar baz :asdf"]),
    JoinCase(source: "src", verb: "AWAY", matches: [":src AWAY"]),
    JoinCase(source: "src", verb: "AWAY", params: [""], matches: [":src AWAY :"]),
    JoinCase(source: "coolguy", verb: "foo", params: ["bar", "baz", "asdf"], matches: [":coolguy FOO bar baz asdf", ":coolguy FOO bar baz :asdf"]),
    JoinCase(verb: "foo", params: ["bar", "baz", "asdf quux"], matches: ["FOO bar baz :asdf quux"]),
    JoinCase(verb: "foo", params: ["bar", "baz", ""], matches: ["FOO bar baz :"]),
    JoinCase(verb: "foo", params: ["bar", "baz", ":asdf"], matches: ["FOO bar baz ::asdf"]),
    JoinCase(source: "coolguy", verb: "foo", params: ["bar", "baz", "asdf quux"], matches: [":coolguy FOO bar baz :asdf quux"]),
    JoinCase(source: "coolguy", verb: "foo", params: ["bar", "baz", "  asdf quux "], matches: [":coolguy FOO bar baz :  asdf quux "]),
    JoinCase(source: "coolguy", verb: "PRIVMSG", params: ["bar", "lol :) "], matches: [":coolguy PRIVMSG bar :lol :) "]),
    JoinCase(source: "coolguy", verb: "foo", params: ["bar", "baz", ""], matches: [":coolguy FOO bar baz :"]),
    JoinCase(source: "coolguy", verb: "foo", params: ["bar", "baz", "  "], matches: [":coolguy FOO bar baz :  "]),
    JoinCase(source: "coolguy", verb: "foo", params: ["b\tar", "baz"], matches: [":coolguy FOO b\tar baz", ":coolguy FOO b\tar :baz"]),
    JoinCase(
        tags: ["asd": ""],
        source: "coolguy",
        verb: "foo",
        params: ["bar", "baz", "  "],
        matches: ["@asd :coolguy FOO bar baz :  ", "@asd= :coolguy FOO bar baz :  "]
    ),
    JoinCase(
        tags: ["a": "b\\and\nk", "d": "gh;764"],
        verb: "foo",
        matches: ["@a=b\\\\and\\nk;d=gh\\:764 FOO", "@d=gh\\:764;a=b\\\\and\\nk FOO"]
    ),
    JoinCase(
        tags: ["a": "b\\and\nk", "d": "gh;764"],
        verb: "foo",
        params: ["par1", "par2"],
        matches: [
            "@a=b\\\\and\\nk;d=gh\\:764 FOO par1 par2",
            "@a=b\\\\and\\nk;d=gh\\:764 FOO par1 :par2",
            "@d=gh\\:764;a=b\\\\and\\nk FOO par1 par2",
            "@d=gh\\:764;a=b\\\\and\\nk FOO par1 :par2",
        ]
    ),
    JoinCase(tags: ["foo": "\\\\;\\s \r\n"], verb: "COMMAND", matches: ["@foo=\\\\\\\\\\:\\\\s\\s\\r\\n COMMAND"]),
]

@Test("msg-join vectors", arguments: joinCases)
func serializesJoinVectors(_ testCase: JoinCase) {
    let message = IRCMessage(
        tags: testCase.tags,
        source: testCase.source.map(IRCSource.init(raw:)),
        command: testCase.verb,
        params: testCase.params
    )
    #expect(testCase.matches.contains(message.serialized), "got \(message.serialized.debugDescription)")
    // And it parses back to the same atoms.
    #expect(IRCMessage(line: message.serialized) == message)
}

@Test("userhost-split vectors", arguments: [
    ("coolguy", "coolguy", nil, nil),
    ("coolguy!ag@127.0.0.1", "coolguy", "ag", "127.0.0.1"),
    ("coolguy!~ag@localhost", "coolguy", "~ag", "localhost"),
    ("coolguy@127.0.0.1", "coolguy", nil, "127.0.0.1"),
    ("coolguy!ag", "coolguy", "ag", nil),
    ("coolguy!ag@net\u{03}5w\u{03}ork.admin", "coolguy", "ag", "net\u{03}5w\u{03}ork.admin"),
    ("coolguy!~ag@n\u{02}et\u{03}05w\u{0f}ork.admin", "coolguy", "~ag", "n\u{02}et\u{03}05w\u{0f}ork.admin"),
] as [(String, String, String?, String?)])
func parsesSources(raw: String, nick: String, user: String?, host: String?) {
    let source = IRCSource(raw: raw)
    #expect(source.nick == nick)
    #expect(source.user == user)
    #expect(source.host == host)
    #expect(source.raw == raw)
}

@Suite struct IRCMessageParsingTests {
    @Test func stripsCRLFAndBareLF() throws {
        // "\r\n" is a single Character in Swift; the parser must still trim it.
        let crlf = try #require(IRCMessage(line: "PING :abc\r\n"))
        #expect(crlf.params == ["abc"])
        let lf = try #require(IRCMessage(line: "PING :abc\n"))
        #expect(lf.params == ["abc"])
    }

    @Test func rejectsEmptyAndMalformedLines() {
        #expect(IRCMessage(line: "") == nil)
        #expect(IRCMessage(line: "\r\n") == nil)
        #expect(IRCMessage(line: "@only-tags") == nil)
        #expect(IRCMessage(line: ":only-source") == nil)
        #expect(IRCMessage(line: "@a=b :src") == nil)
    }

    @Test func combiningMarksDoNotHideDelimiters() throws {
        // A combining acute accent would merge with the preceding ':' or ' '
        // into one grapheme cluster.
        let message = try #require(IRCMessage(line: ":n!u@h PRIVMSG #c :\u{301}hi there"))
        #expect(message.params == ["#c", "\u{301}hi there"])
        let middle = try #require(IRCMessage(line: "CMD a \u{301}b c"))
        #expect(middle.params == ["a", "\u{301}b", "c"])
        // (Kept out of the macro: #require's expansion mangles "\\\u{...}".)
        let taggedLine = "@k=v" + "\\" + "\u{301} CMD"
        let tagged = try #require(IRCMessage(line: taggedLine))
        #expect(tagged.tags["k"] == "v\u{301}")
    }

    @Test func emojiAndUnicodeRoundTrip() throws {
        let line = "@+draft/react=👍🏽 :ñick!ü@höst PRIVMSG #çhan :héllo 👨‍👩‍👧 wörld"
        let message = try #require(IRCMessage(line: line))
        #expect(message.source?.nick == "ñick")
        #expect(message.tags["+draft/react"] == "👍🏽")
        #expect(message.params == ["#çhan", "héllo 👨‍👩‍👧 wörld"])
        #expect(message.serialized == line)
    }

    @Test func tagValuesRoundTrip() throws {
        let values = ["", "plain", "a;b", "a b", "back\\slash", "cr\rlf\n", "\\s literal", ";;  \\\\", "trailing\\", "😀;\u{301} \r\n"]
        for value in values {
            let message = IRCMessage(tags: ["k": value, "+vendor/x": value], command: "TAGMSG", params: ["#c"])
            let parsed = try #require(IRCMessage(line: message.serialized))
            #expect(parsed.tags == message.tags, "value \(value.debugDescription)")
        }
    }

    @Test func escapingIsCharacterByCharacter() {
        #expect(IRCMessage.escapeTagValue("a;b c\\d\r\n") == "a\\:b\\sc\\\\d\\r\\n")
        // CRLF as one grapheme must still be escaped.
        #expect(IRCMessage.escapeTagValue("x\r\ny") == "x\\r\\ny")
        #expect(IRCMessage.unescapeTagValue(Substring("\\\\n")) == "\\n")
        #expect(IRCMessage.unescapeTagValue(Substring("\\x\\")) == "x")
    }

    @Test func commonTagAccessors() throws {
        let message = try #require(IRCMessage(line:
            "@time=2023-01-02T03:04:05.678Z;msgid=abc;batch=b1;label=L;account=acct;+draft/reply=parent :n!u@h PRIVMSG #c :hi"
        ))
        #expect(message.msgid == "abc")
        #expect(message.batchID == "b1")
        #expect(message.label == "L")
        #expect(message.account == "acct")
        #expect(message.replyTo == "parent")
        let time = try #require(message.serverTime)
        #expect(abs(time.timeIntervalSince1970 - 1_672_628_645.678) < 0.001)
        #expect(IRCTime.parse("2023-01-02T03:04:05Z") != nil)
        #expect(abs(try #require(IRCTime.parse(IRCTime.format(time))).timeIntervalSince(time)) < 0.001)
    }

    @Test func numericDetection() throws {
        #expect(try #require(IRCMessage(line: ":s 001 n :hi")).isNumeric)
        #expect(try #require(IRCMessage(line: ":s PRIVMSG n :hi")).isNumeric == false)
        #expect(IRCNumeric.isError("433"))
        #expect(IRCNumeric.isError("001") == false)
    }
}

@Suite struct IRCMessageSerializationTests {
    @Test func trailingRules() {
        #expect(IRCMessage("PRIVMSG", "#c", "hello").serialized == "PRIVMSG #c hello")
        #expect(IRCMessage("PRIVMSG", "#c", "hello world").serialized == "PRIVMSG #c :hello world")
        #expect(IRCMessage("PRIVMSG", "#c", "").serialized == "PRIVMSG #c :")
        #expect(IRCMessage("PRIVMSG", "#c", ":)").serialized == "PRIVMSG #c ::)")
        #expect(IRCMessage("QUIT").serialized == "QUIT")
        #expect(IRCMessage("NICK", "vela").serialized == "NICK vela")
        // A combining mark after ':' must not defeat the leading-colon check.
        #expect(IRCMessage("PRIVMSG", "#c", ":\u{301}").serialized == "PRIVMSG #c ::\u{301}")
        #expect(IRCMessage("PRIVMSG", "#c", "a \u{301}").serialized == "PRIVMSG #c :a \u{301}")
    }

    @Test func commandIsUppercased() {
        #expect(IRCMessage("privmsg", "#c", "x").command == "PRIVMSG")
    }

    @Test func tagsAreSortedAndEscaped() {
        let message = IRCMessage(tags: ["b": "x y", "a": "", "+c": "1;2"], command: "TAGMSG", params: ["#c"])
        #expect(message.serialized == "@+c=1\\:2;a;b=x\\sy TAGMSG #c")
    }

    @Test func lineBreaksCannotBeInjected() {
        let message = IRCMessage("PRIVMSG", "#c", "hi\r\nQUIT :pwned")
        #expect(!message.serialized.unicodeScalars.contains("\r"))
        #expect(!message.serialized.unicodeScalars.contains("\n"))
        #expect(message.serialized == "PRIVMSG #c :hi  QUIT :pwned")
    }

    @Test func sourceSerialization() {
        let message = IRCMessage(source: IRCSource(nick: "n", user: "u", host: "h"), command: "JOIN", params: ["#c"])
        #expect(message.serialized == ":n!u@h JOIN #c")
        #expect(IRCSource(raw: "irc.example.com").isServer)
        #expect(IRCSource(raw: "nick").isServer == false)
        #expect(IRCSource(raw: "n!u@h").userHost == "u@h")
    }
}

@Suite struct ChatLineTests {
    @Test func shortTextIsOneLine() {
        let lines = IRCMessage.chatLines(target: "#c", text: "hello", tags: ["+draft/reply": "x"])
        #expect(lines.map(\.serialized) == ["@+draft/reply=x PRIVMSG #c hello"])
    }

    @Test func splitsOnNewlinesAndDropsEmptyLines() {
        let lines = IRCMessage.chatLines(target: "#c", text: "one\ntwo\r\n\nthree", tags: ["label": "l"])
        #expect(lines.map { $0.params[1] } == ["one", "two", "three"])
        #expect(lines[0].tags == ["label": "l"])
        #expect(lines[1].tags.isEmpty)
    }

    @Test func splitsLongTextAtSpacesWithinBudget() {
        let words = (0..<200).map { "word\($0)" }.joined(separator: " ")
        let lines = IRCMessage.chatLines(command: "PRIVMSG", target: "#channel", text: words)
        #expect(lines.count > 1)
        for line in lines {
            // prefix allowance (100) + serialized line must fit in 510 bytes.
            #expect(line.serialized.utf8.count + 100 <= 510)
            #expect(!line.params[1].hasPrefix(" "))
        }
        // Splitting at spaces drops exactly the breaking spaces.
        #expect(lines.map { $0.params[1] }.joined(separator: " ") == words)
    }

    @Test func multiByteTextNeverSplitsScalarsOrGraphemes() {
        let family = "👨‍👩‍👧‍👦"  // 25 bytes, one grapheme
        let text = String(repeating: "é日本\(family)", count: 80)  // no spaces
        let lines = IRCMessage.chatLines(target: "#c", text: text)
        #expect(lines.count > 1)
        for line in lines {
            #expect(line.serialized.utf8.count + 100 <= 510)
        }
        #expect(lines.map { $0.params[1] }.joined() == text)
        let budget = 510 - (7 + 2 + 5 + 100)
        for chunk in IRCMessage.splitUTF8(text, maxBytes: budget) {
            #expect(chunk.utf8.count <= budget)
            #expect(chunk.unicodeScalars.first != "\u{200D}")  // never starts mid-ZWJ-sequence
        }
    }

    @Test func splitUTF8EdgeCases() {
        #expect(IRCMessage.splitUTF8("short", maxBytes: 10) == ["short"])
        #expect(IRCMessage.splitUTF8("aaaa bbbb cccc", maxBytes: 9) == ["aaaa bbbb", "cccc"])
        #expect(IRCMessage.splitUTF8("abcdefghij", maxBytes: 4) == ["abcd", "efgh", "ij"])
        // A leading space never yields an empty chunk.
        #expect(IRCMessage.splitUTF8(" abcdefgh", maxBytes: 4).allSatisfy { !$0.isEmpty })
        // A tail plus a wide character that still overflows is split again.
        let chunks = IRCMessage.splitUTF8("a bbbbbbbbb😀", maxBytes: 11)
        #expect(chunks.allSatisfy { $0.utf8.count <= 11 })
        #expect(chunks.joined(separator: "").replacingOccurrences(of: " ", with: "") == "abbbbbbbbb😀")
        // A single grapheme larger than the budget falls back to scalars.
        let zalgo = "a" + String(repeating: "\u{301}", count: 20)  // 41 bytes, one grapheme
        let pieces = IRCMessage.splitUTF8(zalgo, maxBytes: 10)
        #expect(pieces.allSatisfy { $0.utf8.count <= 10 })
        #expect(pieces.joined() == zalgo)
    }

    @Test func actionLinesWrapEveryChunk() {
        let text = String(repeating: "x ", count: 400)
        let lines = IRCMessage.actionLines(target: "#c", text: text)
        #expect(lines.count > 1)
        for line in lines {
            #expect(CTCP.actionText(line.params[1]) != nil)
            #expect(line.serialized.utf8.count + 100 <= 510)
        }
    }
}
