// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Identifies a buffer (server, channel or query) within a network. The
/// name is case-folded by the caller using the network's CASEMAPPING.
public struct BufferKey: Codable, Sendable, Hashable {
    public var networkID: UUID
    public var foldedName: String

    public init(networkID: UUID, foldedName: String) {
        self.networkID = networkID
        self.foldedName = foldedName
    }
}

/// A persisted chat line. `kind` is an app-defined string such as
/// `"privmsg"`, `"notice"`, `"action"`, `"join"`; the store does not
/// interpret it.
public struct MessageRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var networkID: UUID
    /// Case-folded buffer name.
    public var bufferName: String
    /// IRCv3 `msgid`, used for de-duplication, replies, reactions, redaction.
    public var msgid: String?
    public var time: Date
    public var kind: String
    public var nick: String?
    public var userHost: String?
    public var account: String?
    public var text: String
    public var isSelf: Bool
    public var isHighlight: Bool
    /// `+draft/reply` target msgid.
    public var replyTo: String?
    /// Remaining message tags worth keeping.
    public var tags: [String: String]
    public var isRedacted: Bool

    public init(
        id: UUID = UUID(),
        networkID: UUID,
        bufferName: String,
        msgid: String? = nil,
        time: Date,
        kind: String,
        nick: String? = nil,
        userHost: String? = nil,
        account: String? = nil,
        text: String,
        isSelf: Bool = false,
        isHighlight: Bool = false,
        replyTo: String? = nil,
        tags: [String: String] = [:],
        isRedacted: Bool = false
    ) {
        self.id = id
        self.networkID = networkID
        self.bufferName = bufferName
        self.msgid = msgid
        self.time = time
        self.kind = kind
        self.nick = nick
        self.userHost = userHost
        self.account = account
        self.text = text
        self.isSelf = isSelf
        self.isHighlight = isHighlight
        self.replyTo = replyTo
        self.tags = tags
        self.isRedacted = isRedacted
    }

    public var bufferKey: BufferKey {
        BufferKey(networkID: networkID, foldedName: bufferName)
    }
}

/// One user's reaction (`+draft/react`) to a message.
public struct ReactionRecord: Codable, Sendable, Hashable {
    public var msgid: String
    public var nick: String
    public var emoji: String

    public init(msgid: String, nick: String, emoji: String) {
        self.msgid = msgid
        self.nick = nick
        self.emoji = emoji
    }
}

/// Per-buffer UI state that should survive relaunches.
public struct BufferRecord: Codable, Sendable, Hashable {
    public var networkID: UUID
    /// Display name as last seen (original case).
    public var name: String
    public var foldedName: String
    /// `"server"`, `"channel"` or `"query"`.
    public var kind: String
    public var lastReadAt: Date?
    public var isPinned: Bool
    public var isMuted: Bool
    public var sortOrder: Int
    /// Whether the channel should be rejoined on the next connect. The
    /// session clears it when the user `/part`s.
    public var autoRejoin: Bool
    /// A channel detached on a bouncer (ZNC or soju): the bouncer stays in
    /// it and keeps its history, but doesn't send it to Vela until it's
    /// joined again. The bouncer doesn't join Vela into it after a
    /// reconnect, so this is the only record of it.
    public var isDetached: Bool
    /// A detached channel taken out of Vela's list (Hide Channel). It stays
    /// on the bouncer, and the row keeps its state for when it's shown.
    public var isHidden: Bool
    /// A channel left on a network without a bouncer: the auto-join entry
    /// it had and where, so joining it again puts the entry back.
    public var leftAutoJoin: LeftAutoJoin?

    public init(
        networkID: UUID,
        name: String,
        foldedName: String,
        kind: String,
        lastReadAt: Date? = nil,
        isPinned: Bool = false,
        isMuted: Bool = false,
        sortOrder: Int = 0,
        autoRejoin: Bool = true,
        isDetached: Bool = false,
        isHidden: Bool = false,
        leftAutoJoin: LeftAutoJoin? = nil
    ) {
        self.networkID = networkID
        self.name = name
        self.foldedName = foldedName
        self.kind = kind
        self.lastReadAt = lastReadAt
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.sortOrder = sortOrder
        self.autoRejoin = autoRejoin
        self.isDetached = isDetached
        self.isHidden = isHidden
        self.leftAutoJoin = leftAutoJoin
    }

    public var key: BufferKey {
        BufferKey(networkID: networkID, foldedName: foldedName)
    }

    private enum CodingKeys: String, CodingKey {
        case networkID, name, foldedName, kind, lastReadAt, isPinned, isMuted, sortOrder, autoRejoin
        case isDetached, isHidden, leftAutoJoin
    }

    /// Only `networkID` and `foldedName` are required; everything else has
    /// a default so older encodings keep decoding.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let foldedName = try container.decode(String.self, forKey: .foldedName)
        self.init(
            networkID: try container.decode(UUID.self, forKey: .networkID),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? foldedName,
            foldedName: foldedName,
            kind: try container.decodeIfPresent(String.self, forKey: .kind) ?? "channel",
            lastReadAt: try container.decodeIfPresent(Date.self, forKey: .lastReadAt),
            isPinned: try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            isMuted: try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false,
            sortOrder: try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0,
            autoRejoin: try container.decodeIfPresent(Bool.self, forKey: .autoRejoin) ?? true,
            isDetached: try container.decodeIfPresent(Bool.self, forKey: .isDetached) ?? false,
            isHidden: try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false,
            leftAutoJoin: try container.decodeIfPresent(LeftAutoJoin.self, forKey: .leftAutoJoin)
        )
    }
}

/// The auto-join entry of a channel you left, and its place in the
/// network's auto-join list (see ``BufferRecord/leftAutoJoin``). Its key,
/// if it has one, stays in the Keychain.
public struct LeftAutoJoin: Codable, Sendable, Hashable {
    public var entry: AutoJoinChannel
    public var index: Int

    public init(entry: AutoJoinChannel, index: Int) {
        self.entry = entry
        self.index = index
    }
}

/// Which kinds of history are saved on disk (see
/// ``VelaDatabase/savedHistory()``). Buffer state isn't history: it's
/// saved either way.
public struct SavedHistory: Sendable, Hashable {
    public var hasMessages: Bool
    public var hasReactions: Bool
    public var hasLinkPreviews: Bool

    public init(hasMessages: Bool = false, hasReactions: Bool = false, hasLinkPreviews: Bool = false) {
        self.hasMessages = hasMessages
        self.hasReactions = hasReactions
        self.hasLinkPreviews = hasLinkPreviews
    }

    /// Nothing saved: "Delete Saved History" has nothing to delete.
    public var isEmpty: Bool { !hasMessages && !hasReactions && !hasLinkPreviews }
}

/// Row counts of the database's tables (``VelaDatabase/storageCounts()``).
public struct StorageCounts: Sendable, Hashable {
    public var messages: Int
    /// Messages in the full-text index.
    public var fullTextEntries: Int
    public var reactions: Int
    public var linkPreviews: Int
    public var buffers: Int

    public init(messages: Int = 0, fullTextEntries: Int = 0, reactions: Int = 0, linkPreviews: Int = 0, buffers: Int = 0) {
        self.messages = messages
        self.fullTextEntries = fullTextEntries
        self.reactions = reactions
        self.linkPreviews = linkPreviews
        self.buffers = buffers
    }
}
