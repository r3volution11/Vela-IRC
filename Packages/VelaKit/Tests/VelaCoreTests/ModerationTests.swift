// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

private func support(_ tokens: String...) -> ISupport {
    ISupport(tokens: tokens)
}

private func privileges(_ prefix: String?, own: String) -> ChannelPrivileges {
    let isupport = prefix.map { support("PREFIX=\($0)") } ?? ISupport()
    return ChannelPrivileges(isupport: isupport, ownPrefixes: own)
}

// MARK: Privileges

@Suite("Channel privileges")
struct ChannelPrivilegesTests {
    @Test func defaultPrefixIsOpAndVoice() {
        let op = privileges(nil, own: "@")
        #expect(op.ranks == ["o", "v"])
        #expect(op.isOperator)
        #expect(op.canModerate)
        // Ops op, deop, voice and devoice others, and kick and ban them.
        #expect(op.canChange("o", adding: true, targetModes: [], targetIsSelf: false))
        #expect(op.canChange("o", adding: false, targetModes: ["o"], targetIsSelf: false))
        #expect(op.canChange("v", adding: true, targetModes: [], targetIsSelf: false))
        #expect(op.canChange("v", adding: false, targetModes: ["v"], targetIsSelf: false))
        #expect(op.canRemove(targetModes: [], targetIsSelf: false))
        #expect(op.canRemove(targetModes: ["o"], targetIsSelf: false))
        // Nothing that changes nothing, and never kicking yourself.
        #expect(!op.canChange("o", adding: true, targetModes: ["o"], targetIsSelf: false))
        #expect(!op.canChange("v", adding: false, targetModes: [], targetIsSelf: false))
        #expect(!op.canRemove(targetModes: ["o"], targetIsSelf: true))
        // No halfops here.
        #expect(!op.canChange("h", adding: true, targetModes: [], targetIsSelf: false))
    }

    @Test func voicedAndRegularUsersModerateNothing() {
        for own in ["+", ""] {
            let user = privileges(nil, own: own)
            #expect(!user.canModerate)
            #expect(!user.canChange("v", adding: true, targetModes: [], targetIsSelf: false))
            #expect(!user.canChange("o", adding: true, targetModes: [], targetIsSelf: true))
            #expect(!user.canRemove(targetModes: [], targetIsSelf: false))
        }
        // But you can always give up your own voice.
        #expect(privileges(nil, own: "+").canChange("v", adding: false, targetModes: ["v"], targetIsSelf: true))
    }

    @Test func ownModesCanAlwaysBeRemoved() {
        let owner = privileges("(qaohv)~&@%+", own: "~@")
        #expect(owner.canChange("q", adding: false, targetModes: ["q", "o"], targetIsSelf: true))
        #expect(owner.canChange("o", adding: false, targetModes: ["q", "o"], targetIsSelf: true))
        let halfop = privileges("(qaohv)~&@%+", own: "%")
        #expect(halfop.canChange("h", adding: false, targetModes: ["h"], targetIsSelf: true))
        // Removing someone else's halfop is another matter.
        #expect(!halfop.canChange("h", adding: false, targetModes: ["h"], targetIsSelf: false))
    }

    @Test func fullPrefixRanks() {
        let prefix = "(qaohv)~&@%+"
        let owner = privileges(prefix, own: "~")
        let admin = privileges(prefix, own: "&")
        let op = privileges(prefix, own: "@")
        let halfop = privileges(prefix, own: "%")

        func assignable(_ p: ChannelPrivileges) -> [Character] {
            p.ranks.filter { p.canChange($0, adding: true, targetModes: [], targetIsSelf: false) }
        }
        // An owner sets a, o, h and v; an admin can't give a; an op gives
        // o, h and v; a halfop only voices.
        #expect(assignable(owner) == ["a", "o", "h", "v"])
        #expect(assignable(admin) == ["o", "h", "v"])
        #expect(assignable(op) == ["o", "h", "v"])
        #expect(assignable(halfop) == ["v"])

        // Ops and up act on people at or below their own rank.
        #expect(op.canRemove(targetModes: ["o"], targetIsSelf: false))
        #expect(!op.canRemove(targetModes: ["a"], targetIsSelf: false))
        #expect(!op.canRemove(targetModes: ["q"], targetIsSelf: false))
        #expect(admin.canRemove(targetModes: ["a"], targetIsSelf: false))
        #expect(!admin.canRemove(targetModes: ["q"], targetIsSelf: false))
        #expect(owner.canRemove(targetModes: ["q", "o"], targetIsSelf: false))
        // ...and that goes for their ranks too: an op can't deop an owner.
        #expect(!op.canChange("o", adding: false, targetModes: ["q", "o"], targetIsSelf: false))
        #expect(owner.canChange("o", adding: false, targetModes: ["a", "o"], targetIsSelf: false))

        // Halfops act only on people below halfop.
        #expect(halfop.canRemove(targetModes: [], targetIsSelf: false))
        #expect(halfop.canRemove(targetModes: ["v"], targetIsSelf: false))
        #expect(!halfop.canRemove(targetModes: ["h"], targetIsSelf: false))
        #expect(!halfop.canRemove(targetModes: ["o"], targetIsSelf: false))
        #expect(halfop.canChange("v", adding: false, targetModes: ["v"], targetIsSelf: false))
        #expect(!halfop.canChange("v", adding: true, targetModes: ["o"], targetIsSelf: false))
    }

    @Test func anUnusualPrefix() {
        // A rank above owner (InspIRCd's custom prefixes allow this), and no
        // halfop.
        let prefix = "(yqaov)!~&@+"
        let owner = privileges(prefix, own: "~")
        #expect(owner.ranks == ["y", "q", "a", "o", "v"])
        #expect(!owner.canChange("y", adding: true, targetModes: [], targetIsSelf: false))
        #expect(!owner.canChange("q", adding: true, targetModes: [], targetIsSelf: false))
        #expect(owner.canChange("a", adding: true, targetModes: [], targetIsSelf: false))
        #expect(!owner.canRemove(targetModes: ["y"], targetIsSelf: false))
        #expect(owner.canRemove(targetModes: ["q"], targetIsSelf: false))
        let top = privileges(prefix, own: "!")
        #expect(top.canChange("q", adding: true, targetModes: [], targetIsSelf: false))
        // Without halfops, a voiced user has nothing to do.
        #expect(!privileges(prefix, own: "+").canModerate)
    }

    @Test func multiplePrefixesUseTheHighest() {
        let isupport = support("PREFIX=(qaohv)~&@%+")
        let p = ChannelPrivileges(isupport: isupport, ownPrefixes: "%+")
        #expect(p.ownModes == ["h", "v"])
        #expect(p.ownRank == 3)
        #expect(ChannelPrivileges.modes(forSymbols: "~@", isupport: isupport) == ["q", "o"])
    }
}

// MARK: Quiets

@Suite("Quiet support")
struct QuietSupportTests {
    @Test func solanumHasAQuietListMode() {
        // Libera.Chat.
        let libera = support("PREFIX=(ov)@+", "CHANMODES=eIbq,k,flj,CFLMPQSTcgimnprstuz", "EXTBAN=$,ajrxz")
        #expect(libera.quietMethod == .listMode("q"))
        #expect(QuietMethod.listMode("q").change(for: "*!*@spam.example") == ("q", "*!*@spam.example"))
    }

    @Test func inspIRCdMutesWithAnExtban() {
        let insp = support("PREFIX=(qaohv)~&@%+", "CHANMODES=IXbegw,k,FHJLfjl,BCDMNOPRSTcimnprstz", "EXTBAN=,ACNOQRSTUcjmprsz")
        #expect(insp.quietMethod == .extban("m:"))
        let change = QuietMethod.extban("m:").change(for: "*!*@spam.example")
        #expect(change.mode == "b")
        #expect(change.argument == "m:*!*@spam.example")
    }

    @Test func unrealQuietsWithAnExtban() {
        let unreal = support("PREFIX=(qaohv)~&@%+", "CHANMODES=beI,fkL,lFH,cdimnprstzCDGKMNOPQRSTVZ", "EXTBAN=~,GOSTacfjmnpqrt")
        #expect(unreal.quietMethod == .extban("~q:"))
    }

    @Test func otherwiseThereIsNone() {
        // Ergo: no quiet mode, no extbans.
        #expect(support("PREFIX=(qaohv)~&@%+", "CHANMODES=Ibe,k,fl,CEMRUimnstu").quietMethod == nil)
        // q as a prefix (owner) isn't a quiet, even if listed in CHANMODES.
        #expect(support("PREFIX=(qaohv)~&@%+", "CHANMODES=beIq,k,l,imnpst").quietMethod == nil)
        // Extbans without a mute type.
        #expect(support("CHANMODES=beI,k,l,imnpst", "EXTBAN=$,ajrxz").quietMethod == nil)
        #expect(support("CHANMODES=beI,k,l,imnpst", "EXTBAN=,ACjr").quietMethod == nil)
        // No CHANMODES at all.
        #expect(ISupport().quietMethod == nil)
    }

    @Test func extbanToken() {
        let unreal = support("EXTBAN=~,qa")
        #expect(unreal.extendedBans?.prefix == "~")
        #expect(unreal.extendedBans?.types == ["q", "a"])
        #expect(support("EXTBAN=,m").extendedBans?.prefix == "")
        #expect(ISupport().extendedBans == nil)
    }
}

// MARK: Ban masks

@Suite("Ban masks")
struct BanMaskTests {
    @Test func eachStyle() {
        #expect(BanMask.mask(nick: "wren", userHost: "~wren@host.example", style: .host) == "*!*@host.example")
        #expect(BanMask.mask(nick: "wren", userHost: "~wren@host.example", style: .userHost) == "*!~wren@host.example")
        #expect(BanMask.mask(nick: "wren", userHost: "~wren@host.example", style: .nick) == "wren!*@*")
    }

    @Test func withoutAHostItsTheNick() {
        for style in BanMaskStyle.allCases {
            #expect(BanMask.mask(nick: "wren", userHost: nil, style: style) == "wren!*@*")
            #expect(BanMask.mask(nick: "wren", userHost: "nohost", style: style) == "wren!*@*")
        }
    }

    @Test func cloaksAndMasks() {
        #expect(BanMask.mask(nick: "wren", userHost: "wren@user/wren", style: .host) == "*!*@user/wren")
        #expect(BanMask.isMask("*!*@host"))
        #expect(BanMask.isMask("wren!*@*"))
        #expect(!BanMask.isMask("wren"))
        #expect(!BanMask.needsHost(.nick))
        #expect(BanMask.needsHost(.host))
    }
}

// MARK: Commands

@MainActor
@Suite("Moderation and CTCP commands")
struct ModerationCommandTests {
    @Test(arguments: [
        ("/kickban wren", InputCommand.kickBan(nicks: ["wren"], reason: nil)),
        ("/kb wren spamming links", .kickBan(nicks: ["wren"], reason: "spamming links")),
        ("/kb wren,theo", .kickBan(nicks: ["wren", "theo"], reason: nil)),
        ("/kb", .usage("/kickban <nick> [reason]")),
        ("/kick wren", .kick(nick: "wren", reason: nil)),
        ("/kick wren be nice", .kick(nick: "wren", reason: "be nice")),
        ("/ban wren", .ban(masks: ["wren"])),
        ("/ban wren *!*@spam.example", .ban(masks: ["wren", "*!*@spam.example"])),
        ("/unban *!*@spam.example", .unban(masks: ["*!*@spam.example"])),
        ("/quiet wren", .quiet(masks: ["wren"])),
        ("/unquiet wren theo", .unquiet(masks: ["wren", "theo"])),
        ("/quiet", .usage("/quiet <nick|mask> [nick|mask…]")),
        ("/ping wren", .ctcp(target: "wren", command: "PING", argument: nil)),
        ("/ping", .usage("/ping <nick>")),
        ("/version wren", .ctcp(target: "wren", command: "VERSION", argument: nil)),
        ("/time wren", .ctcp(target: "wren", command: "TIME", argument: nil)),
        ("/clientinfo wren", .ctcp(target: "wren", command: "CLIENTINFO", argument: nil)),
        ("/clientinfo", .usage("/clientinfo <nick>")),
        // Without a nick, or with a server's name, they ask the server.
        ("/version", .unknown(command: "version", args: "")),
        ("/time irc.libera.chat", .unknown(command: "time", args: "irc.libera.chat")),
        ("/halfop wren theo", .memberMode(sign: "+", mode: "h", nicks: ["wren", "theo"])),
        ("/dehalfop wren", .memberMode(sign: "-", mode: "h", nicks: ["wren"])),
    ])
    func parses(input: String, expected: InputCommand) {
        #expect(InputCommand.parse(input) == expected)
    }

    @Test func newCommandsComplete() {
        for name in ["kickban", "kb", "quiet", "unquiet", "ping", "version", "time", "clientinfo", "halfop", "dehalfop"] {
            #expect(InputCommand.knownCommands.contains(name), "\(name)")
        }
        #expect(InputCommand.knownCommands == InputCommand.knownCommands.sorted())
    }
}

// MARK: MODE batching

@Suite("MODE batching")
struct ModeBatchingTests {
    private func lines(_ messages: [IRCMessage]) -> [String] {
        messages.map { $0.params.joined(separator: " ") }
    }

    @Test func batchesUpToModes() {
        let messages = IRCMessage.modeLines(target: "#vela", sign: "+", mode: "o", arguments: ["a", "b", "c", "d", "e", "f", "g"], perLine: 3)
        #expect(messages.allSatisfy { $0.command == "MODE" })
        #expect(lines(messages) == ["#vela +ooo a b c", "#vela +ooo d e f", "#vela +o g"])
    }

    @Test func oneAtATimeWhenTheServerSaysSo() {
        let messages = IRCMessage.modeLines(target: "#vela", sign: "-", mode: "v", arguments: ["a", "b"], perLine: 1)
        #expect(lines(messages) == ["#vela -v a", "#vela -v b"])
    }

    @Test func longMasksSplitByLength() {
        let mask = "*!*@" + String(repeating: "x", count: 150)
        let messages = IRCMessage.modeLines(target: "#vela", sign: "+", mode: "b", arguments: [mask, mask, mask, mask], perLine: 100)
        #expect(messages.count == 2)
        for message in messages {
            #expect(message.serialized.utf8.count <= 400)
        }
        #expect(messages.flatMap { $0.params.dropFirst(2) }.count == 4)
    }

    @Test func nothingForNoArguments() {
        #expect(IRCMessage.modeLines(target: "#vela", sign: "+", mode: "o", arguments: [], perLine: 3).isEmpty)
    }

    @Test func modesToken() {
        #expect(ISupport().modeChangesPerLine == 3)
        #expect(support("MODES=4").modeChangesPerLine == 4)
        #expect(support("MODES=0").modeChangesPerLine == 1)
        #expect(support("MODES").modeChangesPerLine == .max)
    }
}

// MARK: Text helpers

@Suite("Nicks in message text")
struct NickWordsTests {
    private func word(_ text: String, at offset: Int) -> String? {
        NickWords.word(at: offset, in: text)?.word
    }

    @Test func findsTheNickAroundAnOffset() {
        let text = "<marisol> kenji: try [doug]_ now"
        #expect(word(text, at: 3) == "marisol")
        #expect(word(text, at: 10) == "kenji")
        #expect(word(text, at: 14) == "kenji")
        #expect(word(text, at: 22) == "[doug]_")
        #expect(word(text, at: 0) == nil)       // "<"
        #expect(word(text, at: 15) == nil)      // ":"
        #expect(word(text, at: 99) == nil)
    }

    @Test func rangesAreUTF16() {
        let text = "🎉 wren!"
        let found = NickWords.word(at: 3, in: text)
        #expect(found?.word == "wren")
        #expect(found?.range == 3..<7)
    }
}

@Suite("CTCP reply lines")
struct CTCPReplyTextTests {
    @Test func readableReplies() {
        #expect(CTCPReplyText.describe(command: "VERSION", argument: "HexChat 2.16.2 / Linux", from: "wren") == "wren is using HexChat 2.16.2 / Linux")
        #expect(CTCPReplyText.describe(command: "TIME", argument: "Wed Nov 18 10:15:00 2026", from: "wren") == "wren's time is Wed Nov 18 10:15:00 2026")
        #expect(CTCPReplyText.describe(command: "CLIENTINFO", argument: "ACTION PING VERSION", from: "wren") == "wren answers CTCP ACTION, PING, VERSION")
        #expect(CTCPReplyText.describe(command: "FINGER", argument: "nope", from: "wren") == "CTCP FINGER reply from wren: nope")
        #expect(CTCPReplyText.describe(command: "VERSION", argument: nil, from: "wren") == "wren didn't say which client they use")
    }

    @Test func pingRoundTrips() {
        #expect(CTCPReplyText.describe(command: "PING", argument: "123", from: "wren", roundTrip: .milliseconds(231)) == "Ping reply from wren: 231 ms")
        #expect(CTCPReplyText.describe(command: "PING", argument: "123", from: "wren", roundTrip: .milliseconds(1420)) == "Ping reply from wren: 1.42 seconds")
        #expect(CTCPReplyText.describe(command: "PING", argument: "123", from: "wren") == "Ping reply from wren")
        #expect(CTCPReplyText.sent(command: "PING", to: "wren") == "Pinging wren…")
        #expect(CTCPReplyText.sent(command: "version", to: "wren") == "Sent CTCP VERSION to wren")
    }
}

@Suite("RPL_USERHOST")
struct UserHostReplyTests {
    @Test func parsesEntries() {
        let entries = UserHostReply.parse("wren=+~wren@host.example kenji*=-k@user/kenji")
        #expect(entries.map(\.nick) == ["wren", "kenji"])
        #expect(entries.map(\.userHost) == ["~wren@host.example", "k@user/kenji"])
        #expect(UserHostReply.parse("").isEmpty)
        #expect(UserHostReply.parse("junk").isEmpty)
    }
}
