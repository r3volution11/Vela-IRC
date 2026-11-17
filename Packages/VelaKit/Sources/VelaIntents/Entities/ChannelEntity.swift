// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import CoreSpotlight
import Foundation
import VelaCore

/// A channel or private conversation, for Siri, Shortcuts and Spotlight.
/// Its identifier is the buffer's `BufferID.description`
/// ("<network-uuid>/<folded-name>").
public struct ChannelEntity: AppEntity, IndexedEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Channel",
        numericFormat: "\(placeholder: .int) channels"
    )
    public static let defaultQuery = ChannelQuery()

    public let id: String

    /// "#vela", or a nick for a private conversation.
    @Property(title: "Name")
    public var name: String

    @Property(title: "Network")
    public var network: String

    @Property(title: "Private Conversation")
    public var isPrivate: Bool

    @Property(title: "Unread Messages")
    public var unreadCount: Int

    @Property(title: "Mentions")
    public var mentionCount: Int

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(network)",
            image: .init(systemName: isPrivate ? "person.crop.circle" : "number")
        )
    }

    /// Spotlight gets the name and network only, never messages.
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.displayName = name
        attributes.contentDescription = network
        attributes.keywords = [name, Self.bareName(name), network]
        return attributes
    }

    public init(id: String, name: String, network: String, isPrivate: Bool, unreadCount: Int, mentionCount: Int) {
        self.id = id
        self.name = name
        self.network = network
        self.isPrivate = isPrivate
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
    }

    /// The buffer it stands for.
    public var bufferID: BufferID? { BufferID(string: id) }

    /// `name` without channel prefixes: "vela" for "#vela".
    static func bareName(_ name: String) -> String {
        String(name.drop { "#&!+".contains($0) })
    }
}

extension ChannelEntity {
    @MainActor
    public init(buffer: BufferModel, session: NetworkSession) {
        self.init(
            id: buffer.id.description,
            name: buffer.name,
            network: session.displayName,
            isPrivate: buffer.kind == .query,
            unreadCount: buffer.unreadCount,
            mentionCount: buffer.highlightCount
        )
    }

    /// The entity for an open buffer, if `bufferID` is one.
    @MainActor
    public init?(bufferID: BufferID, in app: AppModel) {
        guard let target = app.lookup(bufferID), target.buffer.kind != .server else { return nil }
        self.init(buffer: target.buffer, session: target.session)
    }

    /// Every channel and private conversation, in sidebar order.
    @MainActor
    public static func all(in app: AppModel) -> [ChannelEntity] {
        app.conversationBuffers.compactMap { buffer in
            app.session(for: buffer.id.networkID).map { ChannelEntity(buffer: buffer, session: $0) }
        }
    }

    /// Entities whose name (with or without "#") or network matches
    /// `query`, best matches first: exact names, then names that start with
    /// it, then names that contain it, then every channel of a matching
    /// network. "vela libera" matches #vela on Libera.Chat.
    @MainActor
    public static func matching(_ query: String, in app: AppModel) -> [ChannelEntity] {
        rank(all(in: app), matching: query)
    }

    /// The ranking behind ``matching(_:in:)``, on plain values.
    public static func rank(_ entities: [ChannelEntity], matching query: String) -> [ChannelEntity] {
        let words = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .filter { !["in", "on", "the", "channel"].contains($0) }
        guard !words.isEmpty else { return [] }

        func score(_ entity: ChannelEntity) -> Int? {
            let name = entity.name.lowercased()
            let bare = bareName(name)
            let network = entity.network.lowercased()
            var total = 0
            for word in words {
                let bareWord = bareName(word)
                guard !bareWord.isEmpty else { continue }
                if bare == bareWord || name == word {
                    total += 100
                } else if bare.hasPrefix(bareWord) {
                    total += 60
                } else if bare.contains(bareWord) {
                    total += 30
                } else if network == word || network.hasPrefix(word) || network.split(separator: ".").contains(where: { $0 == word }) {
                    total += 10
                } else if network.contains(word) {
                    total += 5
                } else {
                    return nil
                }
            }
            return total > 0 ? total : nil
        }

        return entities.enumerated()
            .compactMap { index, entity in score(entity).map { (entity, $0, index) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }
}

/// Finds channels for Siri and Shortcuts: by identifier, by name ("vela",
/// "#vela", "vela on libera"), and suggestions in sidebar order.
public struct ChannelQuery: EntityStringQuery {
    @Dependency private var app: AppModel

    public init() {}

    @MainActor
    public func entities(for identifiers: [ChannelEntity.ID]) async throws -> [ChannelEntity] {
        await app.ready()
        return identifiers.compactMap { BufferID(string: $0).flatMap { ChannelEntity(bufferID: $0, in: app) } }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [ChannelEntity] {
        await app.ready()
        return ChannelEntity.matching(string, in: app)
    }

    @MainActor
    public func suggestedEntities() async throws -> [ChannelEntity] {
        await app.ready()
        return ChannelEntity.all(in: app)
    }
}
