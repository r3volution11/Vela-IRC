// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import VelaIRC

private func cap(_ line: String) -> IRCMessage {
    IRCMessage(line: line)!
}

@Suite struct CapNegotiatorTests {
    @Test func multilineLSAccumulatesUntilFinalLine() {
        var negotiator = CapNegotiator(desired: ["sasl", "server-time", "batch", "away-notify"])
        #expect(negotiator.handle(cap(":irc.test CAP * LS * :multi-prefix sasl=PLAIN,EXTERNAL")) == .lsPartial)
        #expect(!negotiator.lsComplete)
        #expect(!negotiator.canEnd)
        let event = negotiator.handle(cap(":irc.test CAP * LS :server-time batch draft/foo=bar"))
        #expect(event == .lsComplete(available: [
            "multi-prefix": "", "sasl": "PLAIN,EXTERNAL", "server-time": "", "batch": "", "draft/foo": "bar",
        ]))
        #expect(negotiator.lsComplete)
        #expect(negotiator.serverSupportsCap)
        #expect(negotiator.saslMechanisms == ["PLAIN", "EXTERNAL"])
        #expect(negotiator.value(for: "draft/foo") == "bar")
        #expect(negotiator.requestable == ["sasl", "server-time", "batch"])

        let requests = negotiator.nextRequests()
        #expect(requests.map(\.serialized) == ["CAP REQ :batch sasl server-time"])
        #expect(negotiator.pending == ["sasl", "server-time", "batch"])
        #expect(!negotiator.canEnd)
        // Nothing new to ask while requests are pending.
        #expect(negotiator.nextRequests().isEmpty)

        #expect(negotiator.handle(cap(":irc.test CAP vela ACK :batch sasl server-time"))
            == .acknowledged(enabled: ["batch", "sasl", "server-time"], disabled: []))
        #expect(negotiator.enabled == ["batch", "sasl", "server-time"])
        #expect(negotiator.canEnd)
    }

    @Test func chunkedRequestsStayUnder510Bytes() {
        let caps = (0..<120).map { "vendor.example/capability-number-\($0)" }
        let lines = CapNegotiator.requestLines(caps)
        #expect(lines.count > 1)
        var seen: [String] = []
        for line in lines {
            #expect(line.serialized.utf8.count <= 510)
            #expect(line.command == "CAP")
            #expect(line.params.first == "REQ")
            seen += line.params[1].split(separator: " ").map(String.init)
        }
        #expect(Set(seen) == Set(caps))
        #expect(seen.count == caps.count)

        // Tight limit: every line still fits.
        let tight = CapNegotiator.requestLines(["aaaa", "bbbb", "cccc"], maxLineLength: 19)
        #expect(tight.map(\.serialized) == ["CAP REQ :aaaa bbbb", "CAP REQ cccc"])
    }

    @Test func nakOfGroupRetriesIndividually() {
        var negotiator = CapNegotiator(desired: ["a", "b", "c"])
        _ = negotiator.handle(cap("CAP * LS :a b c"))
        #expect(negotiator.nextRequests().map(\.serialized) == ["CAP REQ :a b c"])
        #expect(negotiator.handle(cap("CAP * NAK :a b c")) == .rejected(["a", "b", "c"]))
        #expect(negotiator.pending.isEmpty)
        let retries = negotiator.nextRequests().map(\.serialized)
        #expect(retries == ["CAP REQ a", "CAP REQ b", "CAP REQ c"])
        _ = negotiator.handle(cap("CAP * ACK a"))
        _ = negotiator.handle(cap("CAP * NAK b"))
        _ = negotiator.handle(cap("CAP * ACK c"))
        #expect(negotiator.enabled == ["a", "c"])
        #expect(negotiator.rejected == ["b"])
        #expect(negotiator.canEnd)
        #expect(negotiator.nextRequests().isEmpty)
    }

    @Test func newAndDel() {
        var negotiator = CapNegotiator(desired: ["away-notify", "batch"])
        _ = negotiator.handle(cap("CAP * LS :batch"))
        _ = negotiator.nextRequests()
        _ = negotiator.handle(cap("CAP * ACK :batch"))

        #expect(negotiator.handle(cap(":irc.test CAP vela NEW :away-notify extended-join")) == .added(["away-notify": "", "extended-join": ""]))
        #expect(negotiator.nextRequests().map(\.serialized) == ["CAP REQ away-notify"])
        _ = negotiator.handle(cap("CAP vela ACK :away-notify"))
        #expect(negotiator.enabled == ["batch", "away-notify"])

        #expect(negotiator.handle(cap(":irc.test CAP vela DEL :away-notify")) == .removed(["away-notify"]))
        #expect(negotiator.enabled == ["batch"])
        #expect(negotiator.available["away-notify"] == nil)
    }

    @Test func ackWithDisableAndDeprecatedModifiers() {
        var negotiator = CapNegotiator(desired: ["a", "b"])
        _ = negotiator.handle(cap("CAP * LS :a b"))
        _ = negotiator.nextRequests()
        #expect(negotiator.handle(cap("CAP * ACK :~a =b")) == .acknowledged(enabled: ["a", "b"], disabled: []))
        #expect(negotiator.handle(cap("CAP * ACK :-b")) == .acknowledged(enabled: [], disabled: ["b"]))
        #expect(negotiator.enabled == ["a"])
    }

    @Test func listReplaceEnabled() {
        var negotiator = CapNegotiator(desired: [])
        #expect(negotiator.handle(cap("CAP * LIST * :a b")) == .listPartial)
        #expect(negotiator.handle(cap("CAP * LIST :c")) == .list(["a", "b", "c"]))
        #expect(negotiator.enabled == ["a", "b", "c"])
    }

    @Test func stsIsNeverRequested() {
        var negotiator = CapNegotiator(desired: ["sts", "batch"])
        _ = negotiator.handle(cap("CAP * LS :sts=port=6697,duration=2592000,preload batch"))
        #expect(negotiator.nextRequests().map(\.serialized) == ["CAP REQ batch"])
        #expect(negotiator.stsPolicy == STSPolicy(port: 6697, duration: 2_592_000, preload: true))
    }

    @Test func emptyLSIsComplete() {
        var negotiator = CapNegotiator(desired: ["batch"])
        #expect(negotiator.handle(cap("CAP * LS :")) == .lsComplete(available: [:]))
        #expect(negotiator.nextRequests().isEmpty)
        #expect(negotiator.canEnd)
    }

    @Test func ignoresNonCap() {
        var negotiator = CapNegotiator(desired: [])
        #expect(negotiator.handle(cap(":s 001 vela :hi")) == .ignored)
        #expect(!negotiator.serverSupportsCap)
    }

    @Test func stsPolicyParsing() {
        #expect(STSPolicy(value: "") == nil)
        #expect(STSPolicy(value: "port=6697") == STSPolicy(port: 6697))
        #expect(STSPolicy(value: "duration=300,unknown=1") == STSPolicy(duration: 300))
        #expect(STSPolicy(value: "port=notanumber")?.port == nil)
    }
}
