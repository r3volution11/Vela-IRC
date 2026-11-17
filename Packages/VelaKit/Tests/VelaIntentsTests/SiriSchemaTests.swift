// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntents
import VelaStore

/// The macOS 27 `.messages` entities and the Spotlight snapshot: what they
/// reveal, and how their identifiers map back to buffers and lines.
@MainActor
@Suite("Siri entities")
struct SiriSchemaTests {
    private func demo() async throws -> (AppModel, NetworkSession) {
        let app = AppModel.demo()
        await app.ready()
        return (app, try #require(app.sessions.first { $0.displayName == "Libera.Chat" }))
    }

    @Test func conversationsShowNamesNotMessages() async throws {
        guard #available(macOS 27, *) else { return }
        let (app, libera) = try await demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        let conversation = try #require(ConversationEntity(bufferID: vela.id, in: app))
        #expect(conversation.id == vela.id.description)
        #expect(conversation.displayName == "#vela")
        #expect(String(conversation.previewText.characters) == "Libera.Chat")
        #expect(conversation.conversationName == "#vela")
        // A reply to a channel goes to the channel.
        #expect(conversation.recipients.map(\.name) == ["#vela"])
        #expect(conversation.recipients.first?.isChannel == true)
        #expect(conversation.hideInSpotlight)

        let marisol = try #require(libera.buffer(named: "marisol"))
        let query = try #require(ConversationEntity(bufferID: marisol.id, in: app))
        #expect(query.conversationName == nil)
        #expect(query.recipients.map(\.name) == ["marisol"])
        #expect(query.recipients.first?.id == marisol.id.description)
        #expect(!query.isRead)
    }

    @Test func messageIdentifiersRoundTrip() async throws {
        guard #available(macOS 27, *) else { return }
        let (app, libera) = try await demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        let line = try #require(vela.lines.last { $0.kind == .message && !$0.isSelf })
        let id = MessageEntity.id(line: line.id, buffer: vela.id)
        let parsed = try #require(MessageEntity.parse(id))
        #expect(parsed.line == line.id)
        #expect(parsed.buffer == vela.id)
        let message = try #require(MessageEntity(id: id, in: app))
        #expect(message.author.name == line.nick)
        #expect(message.conversation.displayName == "#vela")
        #expect(message.body.map { String($0.characters) } == line.text)
        #expect(MessageEntity.parse("nonsense") == nil)
        #expect(MessageEntity(id: MessageEntity.id(line: UUID(), buffer: vela.id), in: app) == nil)
    }

    @Test func recipientsResolveToTheirNames() async throws {
        guard #available(macOS 27, *) else { return }
        let (app, libera) = try await demo()
        let person = MessagePersonEntity(nick: "Marisol", session: libera)
        #expect(person.id == "\(libera.id.uuidString)/marisol")
        // The open conversation spells it the way it was written.
        #expect(MessagePersonEntity(id: person.id, in: app)?.name == "marisol")
        #expect(MessagePersonEntity(id: "\(libera.id.uuidString)/kenji", in: app)?.name == "kenji")
        #expect(MessagePersonEntity(id: "\(libera.id.uuidString)/doug", in: app)?.person.isMe == true)
        let vela = try #require(MessagePersonEntity(id: "\(libera.id.uuidString)/#vela", in: app))
        #expect(vela.isChannel)
        #expect(vela.name == "#vela")
        #expect(MessagePersonEntity.all(in: app).map(\.id) == ChannelEntity.all(in: app).map(\.id))
    }

    @Test func messageSearchFindsRecentLines() async throws {
        guard #available(macOS 27, *) else { return }
        let (app, _) = try await demo()
        let results = MessageEntity.recent(matching: "sidebar rail", in: app)
        #expect(results.first?.author.name == "wren")
        #expect(MessageEntity.recent(matching: "  ", in: app).isEmpty)
        #expect(MessageEntity.recent(matching: "e", in: app).count == MessageEntity.searchLimit)
    }

    @Test func messageTextJoinsContentAndLinks() {
        guard #available(macOS 27, *) else { return }
        #expect(messageText(content: AttributedString("look"), links: [URL(string: "https://ircv3.net")!]) == "look https://ircv3.net")
        #expect(messageText(content: nil, links: []) == "")
        #expect(messageText(content: AttributedString("  brb "), links: []) == "brb")
    }

    @Test func destinationsMapToBuffers() async throws {
        guard #available(macOS 27, *) else { return }
        let (app, libera) = try await demo()
        let vela = try #require(libera.buffer(named: "#vela"))
        let conversation = try #require(ConversationEntity(bufferID: vela.id, in: app))
        let channel = try #require(conversation.recipients.first)
        #expect(try app.bufferID(for: channel) == vela.id)
        // Someone you haven't talked to gets a private conversation.
        let id = try app.bufferID(for: MessagePersonEntity(nick: "kenji", session: libera))
        #expect(libera.buffer(id: id)?.kind == .query)
        #expect(libera.buffer(id: id)?.name == "kenji")
        // A channel you're not in isn't joined behind your back.
        let elsewhere = MessagePersonEntity(name: "#elsewhere", networkID: libera.id, networkName: "Libera.Chat", isChannel: true, fold: libera.foldName)
        #expect(throws: (any Error).self) { try app.bufferID(for: elsewhere) }
        #expect(libera.buffer(named: "#elsewhere") == nil)
    }

    // MARK: Spotlight

    @Test func spotlightSnapshotHasNamesOnly() async throws {
        let (app, libera) = try await demo()
        let snapshot = SpotlightChannelIndexer.snapshot(of: app)
        #expect(snapshot.isEnabled)
        #expect(snapshot.channels.count == ChannelEntity.all(in: app).count)
        #expect(!snapshot.channels.contains { $0.contains(BufferID.serverBufferName) })
        // Unread counts don't change what's indexed.
        let vela = try #require(libera.buffer(named: "#vela"))
        vela.unreadCount += 3
        #expect(SpotlightChannelIndexer.snapshot(of: app) == snapshot)
        app.settings[.intelligenceSpotlightChannels] = false
        #expect(SpotlightChannelIndexer.snapshot(of: app).isEnabled == false)
    }

    @Test func onscreenIdentifiersUseTheBufferID() {
        let id = BufferID(networkID: UUID(), foldedName: "#vela")
        #expect(OnscreenEntities.identifier(for: id).identifier == id.description)
    }
}
