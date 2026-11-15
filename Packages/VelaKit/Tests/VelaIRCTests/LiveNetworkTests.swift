// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaIRC

/// Opt-in tests against real servers. Run with
/// `VELA_LIVE_TESTS=1 swift test --filter LiveNetworkTests`.
@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["VELA_LIVE_TESTS"] != nil),
    .timeLimit(.minutes(1))
)
struct LiveNetworkTests {
    @Test func tlsConnectsToLibera() async throws {
        let transport = NetworkTransport(host: "irc.libera.chat", port: 6697, useTLS: true)
        let stream = try await transport.open()
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first != nil)
        await transport.close()
    }

    @Test func rejectsInvalidCertificate() async throws {
        let transport = NetworkTransport(host: "self-signed.badssl.com", port: 443, useTLS: true)
        await #expect {
            _ = try await transport.open()
        } throws: { error in
            guard case IRCTransportError.certificateRejected = error else { return false }
            return true
        }
    }

    @Test func rejectsWrongHost() async throws {
        let transport = NetworkTransport(host: "wrong.host.badssl.com", port: 443, useTLS: true)
        await #expect(throws: IRCTransportError.self) { _ = try await transport.open() }
    }

    @Test func acceptsInvalidCertificateWhenAllowed() async throws {
        let transport = NetworkTransport(host: "self-signed.badssl.com", port: 443, useTLS: true, allowInvalidCertificates: true)
        _ = try await transport.open()
        await transport.close()
    }

    @Test func unknownHostFails() async throws {
        let transport = NetworkTransport(host: "no-such-host.invalid", port: 6697, useTLS: true)
        await #expect(throws: IRCTransportError.self) { _ = try await transport.open() }
    }
}
