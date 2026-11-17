// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntents

/// Channels as Siri and Shortcuts see them: identifiers, names, matching
/// and suggestions, against the demo networks (Libera.Chat, OFTC, Ergo).
@Suite("Channel entities")
struct ChannelEntityTests {
    private func entity(_ name: String, _ network: String, isPrivate: Bool = false) -> ChannelEntity {
        ChannelEntity(id: "\(UUID().uuidString)/\(name)", name: name, network: network, isPrivate: isPrivate, unreadCount: 0, mentionCount: 0)
    }

    private func names(_ entities: [ChannelEntity]) -> [String] {
        entities.map(\.name)
    }

    // MARK: Ranking

    @Test func exactNameBeatsLongerNames() {
        let all = [entity("#vela-offtopic", "Libera.Chat"), entity("#vela", "Libera.Chat"), entity("#novela", "OFTC")]
        #expect(names(ChannelEntity.rank(all, matching: "#vela")) == ["#vela", "#vela-offtopic", "#novela"])
    }

    @Test func hashIsOptionalAndCaseIgnored() {
        let all = [entity("#swift", "Libera.Chat"), entity("#Vela", "Libera.Chat")]
        #expect(names(ChannelEntity.rank(all, matching: "vela")) == ["#Vela"])
        #expect(names(ChannelEntity.rank(all, matching: "VELA")) == ["#Vela"])
        #expect(names(ChannelEntity.rank(all, matching: "#vela")) == ["#Vela"])
    }

    @Test func networkNarrowsTheMatch() {
        let all = [entity("#vela", "OFTC"), entity("#vela", "Libera.Chat"), entity("#swift", "Libera.Chat")]
        let matches = ChannelEntity.rank(all, matching: "vela on libera")
        #expect(matches.count == 1)
        #expect(matches.first?.network == "Libera.Chat")
    }

    @Test func networkAloneListsItsChannels() {
        let all = [entity("#debian", "OFTC"), entity("#vela", "Libera.Chat"), entity("#tor", "OFTC")]
        #expect(names(ChannelEntity.rank(all, matching: "oftc")) == ["#debian", "#tor"])
    }

    @Test func privateConversationsMatchByNick() {
        let all = [entity("#vela", "Libera.Chat"), entity("marisol", "Libera.Chat", isPrivate: true)]
        #expect(names(ChannelEntity.rank(all, matching: "mari")) == ["marisol"])
    }

    @Test(arguments: ["", "   ", "nothing-like-it", "the channel"])
    func noMatches(_ query: String) {
        let all = [entity("#vela", "Libera.Chat"), entity("#swift", "Libera.Chat")]
        #expect(ChannelEntity.rank(all, matching: query).isEmpty)
    }

    // MARK: Demo model

    @MainActor
    @Test func suggestionsFollowTheSidebarWithoutConsoles() async {
        let app = AppModel.demo()
        await app.ready()
        let all = ChannelEntity.all(in: app)
        let expected = app.orderedBuffers.filter { $0.kind != .server }.map(\.name)
        #expect(names(all) == expected)
        #expect(!all.contains { $0.name == "Libera.Chat" })
        #expect(all.first { $0.name == "marisol" }?.isPrivate == true)
        #expect(all.first { $0.name == "#vela" }?.network == "Libera.Chat")
    }

    @MainActor
    @Test func identifiersAreBufferIDs() async throws {
        let app = AppModel.demo()
        await app.ready()
        let libera = try #require(app.sessions.first { $0.displayName == "Libera.Chat" })
        let vela = try #require(libera.buffer(named: "#vela"))
        let entity = ChannelEntity(buffer: vela, session: libera)
        #expect(entity.id == vela.id.description)
        #expect(entity.bufferID == vela.id)
        #expect(ChannelEntity(bufferID: vela.id, in: app)?.name == "#vela")
        // Consoles and closed buffers aren't channels.
        #expect(ChannelEntity(bufferID: libera.serverBuffer.id, in: app) == nil)
        #expect(ChannelEntity(bufferID: BufferID(networkID: libera.id, foldedName: "#gone"), in: app) == nil)
    }

    @MainActor
    @Test func countsComeFromTheBuffer() async throws {
        let app = AppModel.demo()
        await app.ready()
        let entity = try #require(ChannelEntity.matching("#swift", in: app).first)
        #expect(entity.name == "#swift")
        #expect(entity.unreadCount == 4)
        let query = try #require(ChannelEntity.matching("marisol", in: app).first)
        #expect(query.mentionCount == 1)
    }

    @MainActor
    @Test func demoMatchingPrefersTheExactChannel() async {
        let app = AppModel.demo()
        await app.ready()
        #expect(ChannelEntity.matching("vela", in: app).first?.name == "#vela")
        #expect(ChannelEntity.matching("#vela-off", in: app).first?.name == "#vela-offtopic")
        #expect(Set(ChannelEntity.matching("oftc", in: app).map(\.network)) == ["OFTC"])
    }

    // MARK: Networks

    @Test func networksMatchByNameOrServer() {
        let libera = NetworkEntity(id: UUID(), name: "Libera.Chat", host: "irc.libera.chat", isConnected: true)
        let oftc = NetworkEntity(id: UUID(), name: "OFTC", host: "irc.oftc.net", isConnected: false)
        #expect(NetworkEntity.rank([oftc, libera], matching: "lib").map(\.name) == ["Libera.Chat"])
        #expect(NetworkEntity.rank([oftc, libera], matching: "oftc.net").map(\.name) == ["OFTC"])
        #expect(NetworkEntity.rank([oftc, libera], matching: "irc").map(\.name) == ["OFTC", "Libera.Chat"])
        #expect(NetworkEntity.rank([oftc, libera], matching: " ").isEmpty)
    }
}
