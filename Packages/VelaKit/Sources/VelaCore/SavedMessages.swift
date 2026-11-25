// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaStore

// MARK: - Saved messages, for Spotlight

// Spotlight's index of messages (`intelligence.spotlightMessages`, off by
// default) hears about messages as they're written to the database, and
// about saved messages going away. VelaIntents' `SpotlightMessageIndexer`
// is the only listener; nothing here costs anything while it isn't one.

/// Where sessions hand messages just written to the database. Called off
/// the main actor, once per batch the session writes (every 400 ms at
/// most, per network), with only the messages that were new. It must
/// return at once: it queues the work and does it elsewhere.
nonisolated public protocol SavedMessagesSink: AnyObject, Sendable {
    func didSave(_ messages: [MessageRecord], context: SavedMessagesContext)
}

/// What a batch's messages need besides themselves: how their network and
/// buffers are named (records carry only ids and folded names).
nonisolated public struct SavedMessagesContext: Sendable, Equatable {
    public struct Buffer: Sendable, Equatable {
        /// "#vela", or a nick, as written.
        public var name: String
        public var kind: BufferKind

        public init(name: String, kind: BufferKind) {
            self.name = name
            self.kind = kind
        }
    }

    public var networkID: UUID
    public var networkName: String
    /// The batch's buffers, by folded name.
    public var buffers: [String: Buffer]

    public init(networkID: UUID, networkName: String, buffers: [String: Buffer]) {
        self.networkID = networkID
        self.networkName = networkName
        self.buffers = buffers
    }
}

/// Hears about saved messages going away, on the main actor, and supplies
/// the sink sessions write to. Set on ``AppModel/savedMessagesObserver``.
@MainActor
public protocol SavedMessagesObserver: AnyObject {
    /// Where sessions hand new messages; nil while nothing's listening.
    var sink: (any SavedMessagesSink)? { get }
    /// Saved history was deleted (Delete Saved History…).
    func savedHistoryDeleted()
    /// A channel was removed or a conversation closed.
    func conversationRemoved(_ bufferID: BufferID)
    /// A network was removed, with everything saved for it.
    func networkRemoved(_ networkID: UUID)
    /// A message was deleted by its sender (IRCv3 `REDACT`).
    func messageRedacted(_ lineID: UUID, time: Date, in bufferID: BufferID)
}

extension NetworkSession {
    /// How the buffers of `records` are named, for a ``SavedMessagesSink``.
    /// Only the batch's own buffers: a few dictionary lookups.
    func savedMessagesContext(for records: [MessageRecord]) -> SavedMessagesContext {
        var buffers: [String: SavedMessagesContext.Buffer] = [:]
        for record in records where buffers[record.bufferName] == nil {
            if record.bufferName == BufferID.serverBufferName {
                buffers[record.bufferName] = .init(name: displayName, kind: .server)
            } else if let buffer = bufferIndex[record.bufferName] {
                buffers[record.bufferName] = .init(name: buffer.name, kind: buffer.kind)
            }
        }
        return SavedMessagesContext(networkID: id, networkName: displayName, buffers: buffers)
    }
}

extension SessionHost {
    public var savedMessagesSink: (any SavedMessagesSink)? { nil }
    public func session(_ session: NetworkSession, didClose buffer: BufferModel) {}
}

// MARK: - AppModel

extension AppModel {
    public var savedMessagesSink: (any SavedMessagesSink)? {
        savedMessagesObserver?.sink
    }

    public func session(_ session: NetworkSession, didClose buffer: BufferModel) {
        savedMessagesObserver?.conversationRemoved(buffer.id)
    }
}
