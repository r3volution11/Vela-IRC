// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

/// End-to-end checks against a real IRCv3 server (Ergo's public testnet).
/// Opt-in: `VELA_LIVE_TESTS=1 swift test --filter LiveSession`.
@MainActor
@Suite("Live session (Ergo testnet)", .enabled(if: ProcessInfo.processInfo.environment["VELA_LIVE_TESTS"] == "1"))
struct LiveSessionTests {
    final class LiveHost: SessionHost {
        var behavior = SessionBehavior()
        var notable: [ChatLine] = []

        func clientConfig(for session: NetworkSession) -> IRCClientConfig {
            var config = IRCClientConfig(host: session.config.host, port: session.config.port, useTLS: true, nick: session.config.nick)
            config.versionReply = "Vela live test"
            return config
        }
        func isBufferVisible(_ id: BufferID) -> Bool { false }
        func activeBuffer(in session: NetworkSession) -> BufferModel? { nil }
        func session(_ session: NetworkSession, didReceiveNotable line: ChatLine, in buffer: BufferModel) { notable.append(line) }
        func session(_ session: NetworkSession, didUpdateBouncerNetworks networks: [BouncerNetwork]) {}
        func sessionDidChangeConfig(_ session: NetworkSession) {}
        func sessionDidChangeUnreadCounts(_ session: NetworkSession) {}
    }

    @Test(.timeLimit(.minutes(1)))
    func registersJoinsAndEchoes() async throws {
        let suffix = String(UUID().uuidString.prefix(6)).lowercased()
        let nick = "vela\(suffix)"
        let channel = "#vela-test-\(suffix)"
        let config = NetworkConfig(name: "Ergo Testnet", host: "testnet.ergo.chat", port: 6697, nick: nick, autoJoin: [AutoJoinChannel(name: channel)])
        let session = NetworkSession(config: config, database: nil)
        let host = LiveHost()
        session.host = host
        session.connect()
        defer { session.disconnect(reason: "Vela live test done") }

        try await waitUntil(timeout: .seconds(20)) { session.connectionState == .connected }
        #expect(session.capabilities.contains("message-tags"))
        #expect(session.capabilities.contains("echo-message"))
        #expect(session.capabilities.contains("server-time"))

        try await waitUntil(timeout: .seconds(15)) { session.buffer(named: channel)?.isJoined == true }
        let buffer = try #require(session.buffer(named: channel))
        try await waitUntil(timeout: .seconds(10)) { buffer.member(named: nick, caseMapping: session.isupport.caseMapping) != nil }
        #expect(buffer.member(named: nick, caseMapping: session.isupport.caseMapping)?.prefixes.contains("@") == true)

        session.submit("hello from Vela's live test", in: buffer)
        try await waitUntil(timeout: .seconds(10)) {
            buffer.lines.contains { $0.isSelf && $0.text == "hello from Vela's live test" && $0.msgid != nil }
        }
        let echoed = try #require(buffer.lines.last { $0.isSelf && $0.kind == .message })
        #expect(echoed.msgid != nil, "echo-message should carry the server msgid")
    }
}
