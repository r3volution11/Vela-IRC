// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import CoreSpotlight
import Foundation
import VelaCore

/// Someone you talk to in private, for Spotlight and Shortcuts: each open
/// private conversation, and those you closed since Vela started (still
/// in File → Recently Closed). Its identifier is the conversation's
/// `BufferID.description` ("<network-uuid>/<folded-nick>"), the same as
/// ``ChannelEntity``'s, so either opens the same conversation.
///
/// Spotlight lists people while `intelligence.spotlightChannels` is on,
/// names and networks only, never messages; choosing one opens (or
/// reopens) the conversation with ``OpenPersonIntent``.
public struct PersonEntity: AppEntity, IndexedEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Person",
        numericFormat: "\(placeholder: .int) people"
    )
    public static let defaultQuery = PersonQuery()

    public let id: String

    /// Their nick, as last seen.
    @Property(title: "Nick")
    public var nick: String

    @Property(title: "Network")
    public var network: String

    @Property(title: "Unread Messages")
    public var unreadCount: Int

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(nick)",
            subtitle: "Private conversation on \(network)",
            image: .init(systemName: "person.crop.circle"),
            synonyms: Self.synonyms(nick: nick, network: network).map { LocalizedStringResource(stringLiteral: $0) }
        )
    }

    /// "message marisol", "DM marisol", "marisol on Libera.Chat".
    static func synonyms(nick: String, network: String) -> [String] {
        var result = ["message \(nick)", "DM \(nick)", "chat with \(nick)"]
        if !network.isEmpty { result.append("\(nick) on \(network)") }
        return result
    }

    /// Spotlight gets the nick and network only, never messages.
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.displayName = nick
        attributes.contentDescription = "Private conversation on \(network)"
        attributes.keywords = [nick, network, "private message", "DM", "query"]
        return attributes
    }

    public init(id: String, nick: String, network: String, unreadCount: Int) {
        self.id = id
        self.nick = nick
        self.network = network
        self.unreadCount = unreadCount
    }

    /// The private conversation it stands for.
    public var bufferID: BufferID? { BufferID(string: id) }
}

extension PersonEntity {
    @MainActor
    init(buffer: BufferModel, session: NetworkSession) {
        self.init(id: buffer.id.description, nick: buffer.name, network: session.displayName, unreadCount: buffer.unreadCount)
    }

    @MainActor
    init(closed: ClosedBuffer, in app: AppModel) {
        self.init(id: closed.id.description, nick: closed.name, network: app.networkName(for: closed), unreadCount: closed.unreadCount)
    }

    /// The person behind `bufferID`: an open private conversation, or one
    /// closed since Vela started.
    @MainActor
    public init?(bufferID: BufferID, in app: AppModel) {
        if let target = app.lookup(bufferID) {
            guard target.buffer.kind == .query else { return nil }
            self.init(buffer: target.buffer, session: target.session)
        } else if let closed = app.recentlyClosed.first(where: { $0.id == bufferID && $0.kind == .query }),
                  app.session(for: bufferID.networkID) != nil {
            self.init(closed: closed, in: app)
        } else {
            return nil
        }
    }

    /// Everyone you talk to in private: open conversations in sidebar
    /// order, then those closed since Vela started, newest first.
    @MainActor
    public static func all(in app: AppModel) -> [PersonEntity] {
        let open = app.conversationBuffers.filter { $0.kind == .query }.compactMap { buffer in
            app.session(for: buffer.id.networkID).map { PersonEntity(buffer: buffer, session: $0) }
        }
        let openIDs = Set(open.map(\.id))
        let sessions = Set(app.automationSessions.map(\.id))
        let closed = app.recentlyClosed
            .filter { $0.kind == .query && sessions.contains($0.id.networkID) && !openIDs.contains($0.id.description) }
            .map { PersonEntity(closed: $0, in: app) }
        return open + closed
    }

    /// People whose nick (or network) matches `query`, best first.
    @MainActor
    public static func matching(_ query: String, in app: AppModel) -> [PersonEntity] {
        let people = all(in: app)
        let ranked = ChannelEntity.rank(
            people.map { ChannelEntity(id: $0.id, name: $0.nick, network: $0.network, isPrivate: true, unreadCount: 0, mentionCount: 0) },
            matching: query
        )
        let byID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ranked.compactMap { byID[$0.id] }
    }

    /// Opens their conversation: shows it if it's open, reopens it if you
    /// closed it, or starts it (as `/query` does; nothing is sent).
    @MainActor
    func open(in app: AppModel) throws {
        guard let bufferID, let session = app.session(for: bufferID.networkID) else { throw IntentFailure(.unknownBuffer) }
        if let buffer = session.buffer(id: bufferID) {
            app.requestShow(buffer.id)
        } else if let closed = app.recentlyClosed.first(where: { $0.id == bufferID }) {
            app.reopen(closed)
            app.requestShow(bufferID)
        } else {
            let buffer = session.ensureBuffer(name: nick, kind: .query)
            app.requestShow(buffer.id)
        }
    }
}

/// Finds people for Shortcuts and Siri: by identifier, by nick, and
/// suggestions (everyone you talk to).
public struct PersonQuery: EntityStringQuery {
    @Dependency private var app: AppModel

    public init() {}

    @MainActor
    public func entities(for identifiers: [PersonEntity.ID]) async throws -> [PersonEntity] {
        await app.ready()
        return identifiers.compactMap { BufferID(string: $0).flatMap { PersonEntity(bufferID: $0, in: app) } }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [PersonEntity] {
        await app.ready()
        return PersonEntity.matching(string, in: app)
    }

    @MainActor
    public func suggestedEntities() async throws -> [PersonEntity] {
        await app.ready()
        return PersonEntity.all(in: app)
    }
}
