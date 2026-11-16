// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

/// Read-only check against a real ZNC bouncer. Nothing is sent to IRC beyond
/// registration; the connection is dropped without QUIT. Credentials come from
/// the environment only:
///
///     VELA_ZNC_HOST=… VELA_ZNC_PORT=… VELA_ZNC_PASS='user/network:password' \
///     [VELA_ZNC_TLS=1] swift test --filter LiveBouncer
@MainActor
@Suite("Live ZNC bouncer", .enabled(if: ProcessInfo.processInfo.environment["VELA_ZNC_HOST"] != nil))
struct LiveBouncerTests {
    final class Host: SessionHost {
        var behavior = SessionBehavior()
        let password: String
        let tls: Bool
        init(password: String, tls: Bool) {
            self.password = password
            self.tls = tls
        }
        func clientConfig(for session: NetworkSession) -> IRCClientConfig {
            var config = IRCClientConfig(host: session.config.host, port: session.config.port, useTLS: tls, nick: session.config.nick)
            config.allowInvalidCertificates = tls
            config.serverPassword = password
            config.respondsToCTCP = false
            return config
        }
        func isBufferVisible(_ id: BufferID) -> Bool { false }
        func activeBuffer(in session: NetworkSession) -> BufferModel? { nil }
        func session(_ session: NetworkSession, didReceiveNotable line: ChatLine, in buffer: BufferModel) {}
        func session(_ session: NetworkSession, didUpdateBouncerNetworks networks: [BouncerNetwork]) {}
        func sessionDidChangeConfig(_ session: NetworkSession) {}
        func sessionDidChangeUnreadCounts(_ session: NetworkSession) {}
    }

    @Test(.timeLimit(.minutes(1)))
    func attachesAndReceivesChannels() async throws {
        let env = ProcessInfo.processInfo.environment
        let host = try #require(env["VELA_ZNC_HOST"])
        let port = UInt16(env["VELA_ZNC_PORT"] ?? "6697") ?? 6697
        let password = try #require(env["VELA_ZNC_PASS"])
        let tls = env["VELA_ZNC_TLS"] == "1"
        let user = String(password.split(separator: ":").first?.split(separator: "/").first ?? "vela")

        var config = NetworkConfig(name: "ZNC", host: host, port: port, useTLS: tls, nick: user)
        config.bouncerKind = .znc
        let session = NetworkSession(config: config, database: nil)
        let sessionHost = Host(password: password, tls: tls)
        session.host = sessionHost
        session.connect()

        try await waitUntil(timeout: .seconds(20)) { session.connectionState == .connected }
        // Give ZNC time to replay JOINs, NAMES, topics and buffered playback.
        try await Task.sleep(for: .seconds(6))

        let channels = session.channels
        print("ZNC  nick=\(session.nick) network=\(session.isupport.network ?? "?")")
        print("ZNC  caps=\(session.capabilities.sorted().joined(separator: " "))")
        for channel in channels {
            let history = channel.lines.filter(\.isHistory).count
            print("ZNC  \(channel.name): joined=\(channel.isJoined) members=\(channel.memberCount) topic=\(channel.topic != nil) lines=\(channel.lines.count) playback=\(history)")
        }
        print("ZNC  queries=\(session.queries.count) serverLines=\(session.serverBuffer.lines.count)")
        if let error = session.lastError { print("ZNC  lastError=\(error)") }

        let connected = session.connectionState == .connected
        let allJoined = channels.allSatisfy { $0.isJoined }
        let anyMembers = channels.contains { $0.memberCount > 0 }
        #expect(connected)
        #expect(!channels.isEmpty, "ZNC should replay the channels you're in")
        #expect(allJoined)
        #expect(anyMembers, "NAMES should populate members")
    }
}
