// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore

@MainActor
@Suite("Buffer and network order")
struct OrderingTests {
    private func makeSession(autoJoin: [String] = [], database: VelaDatabase? = nil) -> (NetworkSession, FakeHost) {
        let host = FakeHost()
        let config = NetworkConfig(name: "Test", host: "irc.test", nick: "doug", autoJoin: autoJoin.map { AutoJoinChannel(name: $0) })
        let session = NetworkSession(config: config, database: database)
        session.host = host
        session.nick = "doug"
        session.connectionState = .connected
        var support = ISupport()
        support.apply(["PREFIX=(ov)@+", "CHANTYPES=#", "CASEMAPPING=rfc1459"])
        session.isupport = support
        return (session, host)
    }

    private func feed(_ session: NetworkSession, _ lines: String...) {
        for line in lines { session.handle(.message(IRCMessage(line: line)!, batch: nil)) }
    }

    private func names(_ buffers: [BufferModel]) -> [String] { buffers.map(\.name) }

    // MARK: Buffers

    @Test func newBuffersGoAfterOthersOfTheirKind() {
        let (session, _) = makeSession()
        feed(session, ":doug!d@host JOIN #zeta", ":doug!d@host JOIN #alpha",
             ":bob!b@host PRIVMSG doug :hi", ":alice!a@host PRIVMSG doug :hey",
             ":doug!d@host JOIN #mid")
        #expect(names(session.channels) == ["#zeta", "#alpha", "#mid"])
        #expect(names(session.queries) == ["bob", "alice"])
        #expect(names(session.buffers) == ["#zeta", "#alpha", "#mid", "bob", "alice"])
        #expect(!session.isBufferOrderAlphabetical)
    }

    @Test func movingStaysWithinChannelsOrQueries() throws {
        let (session, _) = makeSession()
        feed(session, ":doug!d@host JOIN #a", ":doug!d@host JOIN #b", ":doug!d@host JOIN #c",
             ":bob!b@host PRIVMSG doug :hi", ":alice!a@host PRIVMSG doug :hey")
        let c = try #require(session.buffer(named: "#c"))
        session.moveBuffer(c, toIndex: 0)
        #expect(names(session.channels) == ["#c", "#a", "#b"])
        #expect(session.channels.map(\.sortOrder) == [0, 1, 2])

        // Out-of-range indexes clamp to the group.
        let alice = try #require(session.buffer(named: "alice"))
        session.moveBuffer(alice, toIndex: -5)
        #expect(names(session.buffers) == ["#c", "#a", "#b", "alice", "bob"])

        let a = try #require(session.buffer(named: "#a"))
        session.moveBuffer(a, by: 1)
        #expect(names(session.channels) == ["#c", "#b", "#a"])
        session.moveBuffer(a, by: 1)   // already last
        #expect(names(session.channels) == ["#c", "#b", "#a"])
    }

    @Test func sortingAlphabeticallyRestoresNameOrder() throws {
        let (session, _) = makeSession()
        feed(session, ":doug!d@host JOIN #b", ":doug!d@host JOIN #a",
             ":zed!z@host PRIVMSG doug :hi", ":amy!a@host PRIVMSG doug :hey")
        session.sortBuffersAlphabetically()
        #expect(names(session.buffers) == ["#a", "#b", "amy", "zed"])
        #expect(session.isBufferOrderAlphabetical)
        // New ones still go at the end afterwards.
        feed(session, ":doug!d@host JOIN #0day")
        #expect(names(session.channels) == ["#a", "#b", "#0day"])
    }

    @Test func movingChannelsReordersAutoJoin() throws {
        let (session, host) = makeSession(autoJoin: ["#a", "#b", "#closed", "#C"])
        feed(session, ":doug!d@host JOIN #a", ":doug!d@host JOIN #b", ":doug!d@host JOIN #c")
        let c = try #require(session.buffer(named: "#c"))
        session.moveBuffer(c, toIndex: 0)
        // #closed isn't open, so it keeps its slot; the open ones follow the sidebar.
        #expect(session.config.autoJoin.map(\.name) == ["#C", "#a", "#closed", "#b"])
        #expect(host.configChanges == 1)

        // Moving a query leaves auto-join alone.
        feed(session, ":bob!b@host PRIVMSG doug :hi", ":amy!a@host PRIVMSG doug :hi")
        session.moveBuffer(try #require(session.buffer(named: "amy")), toIndex: 0)
        #expect(host.configChanges == 1)
    }

    @Test func restoredBuffersKeepTheirSavedOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VelaOrder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try VelaDatabase(url: directory.appendingPathComponent("vela.sqlite"))
        let (session, _) = makeSession(database: database)
        for (name, order) in [("#a", 2), ("#b", 0), ("#c", 1), ("#d", 0)] {
            try await database.upsertBuffer(BufferRecord(networkID: session.id, name: name, foldedName: name, kind: "channel", sortOrder: order))
        }
        await session.restoreBuffers()
        // Saved positions first; equal positions (never reordered) by name.
        #expect(names(session.channels) == ["#b", "#d", "#c", "#a"])
    }

    // MARK: Networks

    private func network(_ name: String, parent: NetworkSession? = nil) -> NetworkSession {
        var config = NetworkConfig(name: name, host: "\(name.lowercased()).test", nick: "doug")
        config.parentNetworkID = parent?.id
        return NetworkSession(config: config, database: nil)
    }

    @Test func movingNetworksAmongSiblings() throws {
        let app = AppModel.demo()
        let solo = network("Solo")
        let bouncer = network("Bouncer")
        let one = network("One", parent: bouncer)
        let two = network("Two", parent: bouncer)
        let other = network("Other")
        app.installDemoSessions([solo, bouncer, one, two, other])
        let order = { app.sessions.map(\.config.name) }

        #expect(app.networkSiblings(of: two.id).map(\.config.name) == ["One", "Two"])
        #expect(app.networkSiblings(of: other.id).map(\.config.name) == ["Solo", "Bouncer", "Other"])

        // A bouncer's networks reorder among themselves.
        app.moveNetwork(two.id, toIndex: 0)
        #expect(order() == ["Solo", "Bouncer", "Two", "One", "Other"])

        // A bouncer moves with its networks.
        app.moveNetwork(bouncer.id, toIndex: 2)
        #expect(order() == ["Solo", "Other", "Bouncer", "Two", "One"])
        app.moveNetwork(other.id, by: -1)
        #expect(order() == ["Other", "Solo", "Bouncer", "Two", "One"])

        // Indexes clamp; a child can't leave its bouncer.
        app.moveNetwork(one.id, toIndex: 99)
        #expect(order() == ["Other", "Solo", "Bouncer", "Two", "One"])
        app.moveNetwork(solo.id, toIndex: -3)
        #expect(order() == ["Solo", "Other", "Bouncer", "Two", "One"])
    }
}
