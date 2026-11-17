// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import VelaCore

/// An IRC network (or bouncer), for Shortcuts. Its identifier is the
/// network's UUID.
public struct NetworkEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Network",
        numericFormat: "\(placeholder: .int) networks"
    )
    public static let defaultQuery = NetworkQuery()

    public let id: UUID

    @Property(title: "Name")
    public var name: String

    @Property(title: "Server")
    public var host: String

    @Property(title: "Connected")
    public var isConnected: Bool

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(host)",
            image: .init(systemName: "network")
        )
    }

    public init(id: UUID, name: String, host: String, isConnected: Bool) {
        self.id = id
        self.name = name
        self.host = host
        self.isConnected = isConnected
    }
}

extension NetworkEntity {
    @MainActor
    public init(session: NetworkSession) {
        self.init(id: session.id, name: session.displayName, host: session.config.host, isConnected: session.isConnected)
    }

    /// Every network, in sidebar order.
    @MainActor
    public static func all(in app: AppModel) -> [NetworkEntity] {
        app.sessions.map(NetworkEntity.init(session:))
    }

    /// Networks whose name or server contains `query` (case-insensitive),
    /// names that start with it first.
    public static func rank(_ entities: [NetworkEntity], matching query: String) -> [NetworkEntity] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        func score(_ entity: NetworkEntity) -> Int? {
            let name = entity.name.lowercased()
            if name == needle { return 3 }
            if name.hasPrefix(needle) { return 2 }
            if name.contains(needle) || entity.host.lowercased().contains(needle) { return 1 }
            return nil
        }
        return entities.enumerated()
            .compactMap { index, entity in score(entity).map { (entity, $0, index) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }
}

public struct NetworkQuery: EntityStringQuery {
    @Dependency private var app: AppModel

    public init() {}

    @MainActor
    public func entities(for identifiers: [NetworkEntity.ID]) async throws -> [NetworkEntity] {
        await app.ready()
        return identifiers.compactMap { app.session(for: $0).map(NetworkEntity.init(session:)) }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [NetworkEntity] {
        await app.ready()
        return NetworkEntity.rank(NetworkEntity.all(in: app), matching: string)
    }

    @MainActor
    public func suggestedEntities() async throws -> [NetworkEntity] {
        await app.ready()
        return NetworkEntity.all(in: app)
    }
}
