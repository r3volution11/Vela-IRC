// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

/// Demo networks have no server; what you send comes back as a server
/// echoes it, so it shows in the conversation (screen recordings, UI work).
@MainActor
@Suite("Demo networks echo what you send")
struct DemoEchoTests {
    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }

    @Test func aMessageYouSendShowsAsYours() async throws {
        let app = AppModel.demo()
        let buffer = try #require(app.selectedBuffer)
        let session = try #require(app.session(for: buffer.id.networkID))
        let count = buffer.lines.count
        session.submit("https://static.klipy.com/ii/d7aec6f6f171607374b2065c836f92f4/3d/31/08K8MgEk.gif", in: buffer)
        #expect(try await waitUntil { buffer.lines.count > count })
        let line = try #require(buffer.lines.last)
        #expect(line.text == "https://static.klipy.com/ii/d7aec6f6f171607374b2065c836f92f4/3d/31/08K8MgEk.gif")
        #expect(line.isSelf)
        #expect(line.msgid?.hasPrefix("demo-") == true)
    }

    @Test func aRealNetworkWithoutAConnectionShowsNothing() async throws {
        let session = NetworkSession(config: NetworkConfig(name: "Test", host: "irc.example", nick: "doug"), database: nil)
        let buffer = session.ensureBuffer(name: "#test", kind: .channel)
        session.send(IRCMessage(command: "PRIVMSG", params: ["#test", "hello"]))
        try await Task.sleep(for: .milliseconds(100))
        #expect(buffer.lines.isEmpty)
    }
}
