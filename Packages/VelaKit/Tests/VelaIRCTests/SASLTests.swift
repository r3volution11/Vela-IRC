// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIRC

private func msg(_ line: String) -> IRCMessage { IRCMessage(line: line)! }

@Suite struct SASLTests {
    @Test func plainExchange() {
        var sasl = SASLAuthenticator(mechanism: .plain(account: "jilles", password: "sesame"))
        #expect(sasl.start().serialized == "AUTHENTICATE PLAIN")
        let outcome = sasl.handle(msg("AUTHENTICATE +"))
        let expected = Data("jilles\0jilles\0sesame".utf8).base64EncodedString()
        #expect(outcome == .send([IRCMessage(command: "AUTHENTICATE", params: [expected])]))
        // A repeated "+" doesn't resend credentials.
        #expect(sasl.handle(msg("AUTHENTICATE +")) == .none)

        #expect(sasl.handle(msg(":irc.test 900 jilles jilles!u@h jilles :You are now logged in as jilles")) == .loggedIn(account: "jilles"))
        #expect(sasl.account == "jilles")
        #expect(sasl.handle(msg(":irc.test 903 jilles :SASL authentication successful"))
            == .succeeded(message: "SASL authentication successful"))
        #expect(sasl.isFinished)
    }

    @Test func externalSendsEmptyResponse() {
        var sasl = SASLAuthenticator(mechanism: .external)
        #expect(sasl.start().serialized == "AUTHENTICATE EXTERNAL")
        #expect(sasl.handle(msg("AUTHENTICATE +")) == .send([IRCMessage(command: "AUTHENTICATE", params: ["+"])]))
    }

    @Test func failureNumerics() {
        for code in ["902", "904", "905", "906"] {
            var sasl = SASLAuthenticator(mechanism: .plain(account: "a", password: "b"))
            _ = sasl.start()
            #expect(sasl.handle(msg(":s \(code) a :nope")) == .failed(message: "nope"))
            #expect(sasl.isFinished)
        }
        var already = SASLAuthenticator(mechanism: .external)
        _ = already.start()
        #expect(already.handle(msg(":s 907 a :already")) == .succeeded(message: "already"))
    }

    @Test func mechanismListAndUnexpectedChallenge() {
        var sasl = SASLAuthenticator(mechanism: .plain(account: "a", password: "b"))
        _ = sasl.start()
        #expect(sasl.handle(msg(":s 908 a PLAIN,external :are available")) == .mechanisms(["PLAIN", "EXTERNAL"]))
        #expect(sasl.serverMechanisms == ["PLAIN", "EXTERNAL"])
        // PLAIN never expects a non-empty challenge: abort.
        #expect(sasl.handle(msg("AUTHENTICATE Zm9v")) == .send([IRCMessage(command: "AUTHENTICATE", params: ["*"])]))
    }

    @Test func ignoresAuthenticateBeforeStart() {
        var sasl = SASLAuthenticator(mechanism: .external)
        #expect(sasl.handle(msg("AUTHENTICATE +")) == .none)
    }

    @Test func chunksLongPayloads() {
        // 600 raw bytes → 800 base64 bytes: exactly two full chunks + "+".
        let exact = SASLAuthenticator.responseMessages(for: Array(repeating: 0x61, count: 600))
        #expect(exact.count == 3)
        #expect(exact[0].params[0].utf8.count == 400)
        #expect(exact[1].params[0].utf8.count == 400)
        #expect(exact[2].params == ["+"])

        // 300 raw bytes → 400 base64 bytes: one full chunk + "+".
        let single = SASLAuthenticator.responseMessages(for: Array(repeating: 0x62, count: 300))
        #expect(single.map { $0.params[0].utf8.count } == [400, 1])
        #expect(single.last?.params == ["+"])

        // 400 raw bytes → 536 base64 bytes: 400 + 136, no terminator.
        let uneven = SASLAuthenticator.responseMessages(for: Array(repeating: 0x63, count: 400))
        #expect(uneven.map { $0.params[0].utf8.count } == [400, 136])
        let rejoined = uneven.map { $0.params[0] }.joined()
        #expect(Data(base64Encoded: rejoined) == Data(repeating: 0x63, count: 400))

        // Empty payload.
        #expect(SASLAuthenticator.responseMessages(for: []).map(\.serialized) == ["AUTHENTICATE +"])
    }

    @Test func plainWithLongPasswordChunksExactly() {
        // account "a" (1) + NUL + "a" + NUL = 4 bytes; 296 bytes of password → 300 raw → 400 base64.
        let password = String(repeating: "p", count: 296)
        var sasl = SASLAuthenticator(mechanism: .plain(account: "a", password: password))
        _ = sasl.start()
        guard case .send(let lines) = sasl.handle(msg("AUTHENTICATE +")) else {
            Issue.record("expected lines")
            return
        }
        #expect(lines.count == 2)
        #expect(lines[0].params[0].utf8.count == 400)
        #expect(lines[1].serialized == "AUTHENTICATE +")
    }

    @Test func mechanismNames() {
        #expect(SASLMechanism.external.name == "EXTERNAL")
        #expect(SASLMechanism.plain(account: "x", password: "y").name == "PLAIN")
        #expect(SASLMechanism.plain(account: "x", password: "y").account == "x")
        #expect(SASLAuthenticator.handles("903"))
        #expect(!SASLAuthenticator.handles("001"))
    }
}
