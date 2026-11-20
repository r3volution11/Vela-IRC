// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import VelaIRC

@Suite struct CaseMappingTests {
    @Test func asciiFoldsOnlyLetters() {
        #expect(CaseMapping.ascii.fold("Nick[]\\~") == "nick[]\\~")
        #expect(CaseMapping.ascii.equal("FOO", "foo"))
        #expect(!CaseMapping.ascii.equal("foo[", "foo{"))
    }

    @Test func rfc1459FoldsBracketsAndTilde() {
        #expect(CaseMapping.rfc1459.fold("Nick[]\\~") == "nick{}|^")
        #expect(CaseMapping.rfc1459.equal("foo[", "FOO{"))
        #expect(CaseMapping.rfc1459.equal("a~", "A^"))
    }

    @Test func strictRFC1459LeavesTilde() {
        #expect(CaseMapping.strictRFC1459.fold("Nick[]\\~") == "nick{}|~")
        #expect(!CaseMapping.strictRFC1459.equal("a~", "a^"))
    }

    /// Folding works on UTF-8 bytes: only ASCII changes, wherever it is,
    /// and text that's already folded comes back as is.
    @Test func asciiMappingsLeaveOtherTextAlone() {
        #expect(CaseMapping.rfc1459.fold("Ünal[X]~é") == "Ünal{x}^é")
        #expect(CaseMapping.ascii.fold("ÉCOLE[🎉]") == "École[🎉]")
        #expect(CaseMapping.rfc1459.fold("already{folded}") == "already{folded}")
        #expect(CaseMapping.rfc1459.fold("") == "")
        #expect(CaseMapping.strictRFC1459.fold("ZZ") == "zz")
    }

    @Test func rfc7613FoldsUnicode() {
        #expect(CaseMapping.rfc7613.equal("ÉCOLE", "école"))
        #expect(!CaseMapping.ascii.equal("ÉCOLE", "école"))
    }

    @Test func rawValues() {
        #expect(CaseMapping(rawValue: "strict-rfc1459") == .strictRFC1459)
        #expect(CaseMapping(rawValue: "rfc7613") == .rfc7613)
    }
}

@Suite struct ISupportTests {
    @Test func defaultsBeforeAny005() {
        let isupport = ISupport()
        #expect(isupport.caseMapping == .rfc1459)
        #expect(isupport.prefixSymbols == ["@", "+"])
        #expect(isupport.channelTypes == ["#", "&"])
        #expect(isupport.isChannel("#vela"))
        #expect(!isupport.isChannel("vela"))
        #expect(!isupport.isChannel(""))
    }

    @Test func parsesPrefixAndRanks() {
        var isupport = ISupport()
        isupport.apply(["PREFIX=(qaohv)~&@%+", "CASEMAPPING=ascii", "NETWORK=Libera.Chat"])
        #expect(isupport.prefixModes == ["q", "a", "o", "h", "v"])
        #expect(isupport.prefixSymbols == ["~", "&", "@", "%", "+"])
        #expect(isupport.symbol(forMode: "h") == "%")
        #expect(isupport.rank(ofSymbol: "~") == 0)
        #expect(isupport.rank(ofSymbol: "+") == 4)
        #expect(isupport.rank(ofSymbol: nil) == 5)
        #expect(isupport.rank(ofSymbol: "!") == 5)
        #expect(isupport.caseMapping == .ascii)
        #expect(isupport.network == "Libera.Chat")

        let split = isupport.splitPrefixes("@+nick")
        #expect(split.prefixes == "@+")
        #expect(split.nick == "nick")
        #expect(isupport.splitPrefixes("plain").prefixes == "")
    }

    @Test func emptyPrefixMeansNoPrefixes() {
        var isupport = ISupport()
        isupport.apply(["PREFIX="])
        #expect(isupport.prefixes.isEmpty)
        #expect(isupport.splitPrefixes("@nick").nick == "@nick")
    }

    @Test func parsesChanModes() {
        var isupport = ISupport()
        isupport.apply(["CHANMODES=IXZbew,k,FHJLWdfjlx,ABCDKMNOPQRSTcgimnprstuz", "CHANTYPES=#"])
        let modes = isupport.channelModes
        #expect(modes.list == Set("IXZbew"))
        #expect(modes.always == ["k"])
        #expect(modes.whenSet.contains("l"))
        #expect(modes.flag.contains("n"))
        #expect(isupport.channelTypes == ["#"])
        #expect(!isupport.isChannel("&local"))
    }

    @Test func negationRemovesTokens() {
        var isupport = ISupport()
        isupport.apply(["MONITOR=100", "WHOX", "CHATHISTORY=50", "BOT=B"])
        #expect(isupport.monitorLimit == 100)
        #expect(isupport.supportsWHOX)
        #expect(isupport.chatHistoryLimit == 50)
        #expect(isupport.botMode == "B")
        isupport.apply(["-MONITOR", "-whox"])
        #expect(isupport.monitorLimit == nil)
        #expect(!isupport.supportsMonitor)
        #expect(!isupport.supportsWHOX)
        #expect(isupport.chatHistoryLimit == 50)
    }

    @Test func valueEscapes() {
        var isupport = ISupport()
        isupport.apply(["NETWORK=Example\\x20Net", "TRUNC=ab\\x2", "UTF=caf\\xC3\\xA9", "BAD=\\xZZ"])
        #expect(isupport.network == "Example Net")
        // A truncated escape must not crash and is kept literally.
        #expect(isupport.tokens["TRUNC"] == "ab\\x2")
        #expect(isupport.tokens["UTF"] == "café")
        #expect(isupport.tokens["BAD"] == "\\xZZ")
    }

    @Test func numericAccessors() {
        let isupport = ISupport(tokens: [
            "NICKLEN=30", "CHANNELLEN=64", "TOPICLEN=390", "AWAYLEN=200", "KICKLEN=255",
            "MODES=4", "STATUSMSG=@+", "UTF8ONLY", "BOUNCER_NETID=7",
        ])
        #expect(isupport.nickLength == 30)
        #expect(isupport.channelLength == 64)
        #expect(isupport.topicLength == 390)
        #expect(isupport.awayLength == 200)
        #expect(isupport.kickLength == 255)
        #expect(isupport.modesPerLine == 4)
        #expect(isupport.statusMessagePrefixes == ["@", "+"])
        #expect(isupport.utf8Only)
        #expect(isupport.bouncerNetworkID == "7")
    }

    @Test func clientTagDeny() {
        #expect(ISupport().allowsClientTag("+typing"))
        let denyAll = ISupport(tokens: ["CLIENTTAGDENY=*,-draft/react,-typing"])
        #expect(denyAll.allowsClientTag("+typing"))
        #expect(denyAll.allowsClientTag("draft/react"))
        #expect(!denyAll.allowsClientTag("+draft/reply"))
        let denySome = ISupport(tokens: ["CLIENTTAGDENY=typing"])
        #expect(!denySome.allowsClientTag("+typing"))
        #expect(denySome.allowsClientTag("+draft/reply"))
    }
}
