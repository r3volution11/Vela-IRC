// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaIRC
import VelaStore

/// Identifies a buffer across the app: a network plus a case-folded name.
nonisolated public struct BufferID: Hashable, Sendable, Codable, CustomStringConvertible {
    public var networkID: UUID
    public var foldedName: String

    public init(networkID: UUID, foldedName: String) {
        self.networkID = networkID
        self.foldedName = foldedName
    }

    /// The server buffer of a network uses this reserved name.
    public static let serverBufferName = "*server*"

    public var storeKey: BufferKey { BufferKey(networkID: networkID, foldedName: foldedName) }

    /// `"<network-uuid>/<folded-name>"`, used by settings such as `media.disabledBuffers`.
    public var description: String { "\(networkID.uuidString)/\(foldedName)" }
}

nonisolated public enum BufferKind: String, Sendable, Codable {
    case server, channel, query
}

nonisolated public enum ChatLineKind: String, Sendable, Codable {
    case message, action, notice
    case join, part, quit, kick, nick, topic, mode, invite
    case info, error, motd, ctcp
    case dayChange

    /// Membership/state events that can be collapsed into a summary row.
    public var isMembershipEvent: Bool {
        switch self {
        case .join, .part, .quit, .nick: true
        default: false
        }
    }

    /// Lines that represent something a person said.
    public var isConversation: Bool {
        switch self {
        case .message, .action, .notice: true
        default: false
        }
    }
}

/// One rendered line of scrollback.
nonisolated public struct ChatLine: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var msgid: String?
    public var time: Date
    public var kind: ChatLineKind
    public var nick: String?
    public var userHost: String?
    public var account: String?
    public var text: String
    public var isSelf: Bool
    public var isHighlight: Bool
    public var replyTo: String?
    public var isRedacted: Bool
    public var tags: [String: String]
    /// True for lines loaded from history (playback/chathistory/DB) rather than live.
    public var isHistory: Bool

    public init(
        id: UUID = UUID(),
        msgid: String? = nil,
        time: Date = Date(),
        kind: ChatLineKind,
        nick: String? = nil,
        userHost: String? = nil,
        account: String? = nil,
        text: String,
        isSelf: Bool = false,
        isHighlight: Bool = false,
        replyTo: String? = nil,
        isRedacted: Bool = false,
        tags: [String: String] = [:],
        isHistory: Bool = false
    ) {
        self.id = id
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
        self.isRedacted = isRedacted
        self.tags = tags
        self.isHistory = isHistory
    }

    func record(networkID: UUID, bufferName: String) -> MessageRecord {
        MessageRecord(
            id: id,
            networkID: networkID,
            bufferName: bufferName,
            msgid: msgid,
            time: time,
            kind: kind.rawValue,
            nick: nick,
            userHost: userHost,
            account: account,
            text: text,
            isSelf: isSelf,
            isHighlight: isHighlight,
            replyTo: replyTo,
            tags: tags,
            isRedacted: isRedacted
        )
    }

    init(record: MessageRecord) {
        self.init(
            id: record.id,
            msgid: record.msgid,
            time: record.time,
            kind: ChatLineKind(rawValue: record.kind) ?? .info,
            nick: record.nick,
            userHost: record.userHost,
            account: record.account,
            text: record.text,
            isSelf: record.isSelf,
            isHighlight: record.isHighlight,
            replyTo: record.replyTo,
            isRedacted: record.isRedacted,
            tags: record.tags,
            isHistory: true
        )
    }
}

/// A channel member.
nonisolated public struct Member: Identifiable, Hashable, Sendable {
    public var id: String { nick }
    public var nick: String
    /// Membership prefix symbols in rank order, e.g. `"@+"`.
    public var prefixes: String
    public var userHost: String?
    public var account: String?
    public var realname: String?
    public var isAway: Bool

    public init(nick: String, prefixes: String = "", userHost: String? = nil, account: String? = nil, realname: String? = nil, isAway: Bool = false) {
        self.nick = nick
        self.prefixes = prefixes
        self.userHost = userHost
        self.account = account
        self.realname = realname
        self.isAway = isAway
    }

    /// The highest-ranked prefix symbol, if any.
    public var topPrefix: Character? { prefixes.first }
}

/// Aggregated reactions to one message.
nonisolated public struct ReactionSummary: Hashable, Sendable, Identifiable {
    public var id: String { emoji }
    public var emoji: String
    public var nicks: [String]
    public var includesSelf: Bool
}

/// Typing state of another user in a buffer (IRCv3 `+typing`).
nonisolated public enum TypingState: String, Sendable {
    case active, paused, done
}

/// A buffer: the server console, a channel or a private conversation.
@Observable
public final class BufferModel: Identifiable, Hashable {
    public nonisolated let id: BufferID
    public var name: String
    public let kind: BufferKind

    public internal(set) var lines: [ChatLine] = []
    public internal(set) var topic: String?
    public internal(set) var topicSetBy: String?
    public internal(set) var modes: String?
    public internal(set) var isJoined = false
    public internal(set) var unreadCount = 0
    public internal(set) var highlightCount = 0
    /// Lines newer than this are "unread" (drives the unread marker).
    public internal(set) var lastReadAt: Date?
    /// When the buffer was opened with unread lines, the read position to draw
    /// the "new messages" marker after. Nil when there's nothing new.
    public internal(set) var unreadMarkerAfter: Date?
    /// Position among the network's buffers of the same kind (channels and
    /// queries are ordered separately). Ties sort by name.
    public internal(set) var sortOrder = 0
    public internal(set) var hasMoreHistory = true
    public internal(set) var isLoadingHistory = false
    public internal(set) var typingNicks: [String] = []
    public var isMuted = false

    /// Members keyed by case-folded nick.
    internal var memberMap: [String: Member] = [:] {
        didSet { membersDirty = true }
    }
    @ObservationIgnored private var membersDirty = true
    @ObservationIgnored private var sortedMembersCache: [Member] = []
    @ObservationIgnored internal var memberRank: (Member) -> Int = { _ in 0 }

    /// msgid → emoji → nicks (insertion ordered).
    internal var reactionMap: [String: [(emoji: String, nicks: [String])]] = [:]
    @ObservationIgnored internal var typingExpiry: [String: Date] = [:]
    @ObservationIgnored internal var selfNick: () -> String = { "" }

    public init(id: BufferID, name: String, kind: BufferKind) {
        self.id = id
        self.name = name
        self.kind = kind
        if kind == .server { hasMoreHistory = false }
    }

    public nonisolated static func == (lhs: BufferModel, rhs: BufferModel) -> Bool { lhs.id == rhs.id }
    public nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Members sorted by rank, then nick.
    public var members: [Member] {
        _ = memberMap
        if membersDirty {
            sortedMembersCache = memberMap.values.sorted {
                let lr = memberRank($0), rr = memberRank($1)
                if lr != rr { return lr < rr }
                return $0.nick.localizedCaseInsensitiveCompare($1.nick) == .orderedAscending
            }
            membersDirty = false
        }
        return sortedMembersCache
    }

    public var memberCount: Int { memberMap.count }

    public func member(named nick: String, caseMapping: CaseMapping = .rfc1459) -> Member? {
        memberMap[caseMapping.fold(nick)]
    }

    public func reactions(for msgid: String?) -> [ReactionSummary] {
        guard let msgid, let entries = reactionMap[msgid] else { return [] }
        let me = selfNick().lowercased()
        return entries.filter { !$0.nicks.isEmpty }.map {
            ReactionSummary(emoji: $0.emoji, nicks: $0.nicks, includesSelf: $0.nicks.contains { $0.lowercased() == me })
        }
    }

    /// The line a reply points at, if it's loaded.
    public func line(withMsgid msgid: String) -> ChatLine? {
        lines.last { $0.msgid == msgid }
    }

    public var isChannel: Bool { kind == .channel }
    public var isServer: Bool { kind == .server }

    // MARK: Internal mutation

    func append(_ line: ChatLine, limit: Int) {
        if let msgid = line.msgid, lines.suffix(200).contains(where: { $0.msgid == msgid }) { return }
        if let last = lines.last, last.time > line.time {
            insertSorted([line])
        } else {
            lines.append(line)
        }
        if lines.count > limit + 200 {
            lines.removeFirst(lines.count - limit)
            hasMoreHistory = true
        }
    }

    /// Merges history lines (any order), skipping duplicates by msgid or id.
    func insertSorted(_ newLines: [ChatLine]) {
        guard !newLines.isEmpty else { return }
        let knownMsgids = Set(lines.compactMap(\.msgid))
        let knownIDs = Set(lines.map(\.id))
        let fresh = newLines.filter { line in
            if knownIDs.contains(line.id) { return false }
            if let msgid = line.msgid, knownMsgids.contains(msgid) { return false }
            return true
        }
        guard !fresh.isEmpty else { return }
        lines = (lines + fresh).sorted { $0.time < $1.time }
    }

    func setReaction(msgid: String, nick: String, emoji: String, active: Bool) {
        var entries = reactionMap[msgid] ?? []
        if let index = entries.firstIndex(where: { $0.emoji == emoji }) {
            var nicks = entries[index].nicks
            nicks.removeAll { $0.caseInsensitiveCompare(nick) == .orderedSame }
            if active { nicks.append(nick) }
            entries[index].nicks = nicks
        } else if active {
            entries.append((emoji, [nick]))
        }
        reactionMap[msgid] = entries
    }

    func updateTyping(nick: String, state: TypingState, now: Date = Date()) {
        switch state {
        case .active: typingExpiry[nick] = now.addingTimeInterval(6)
        case .paused: typingExpiry[nick] = now.addingTimeInterval(30)
        case .done: typingExpiry.removeValue(forKey: nick)
        }
        refreshTyping(now: now)
    }

    func refreshTyping(now: Date = Date()) {
        typingExpiry = typingExpiry.filter { $0.value > now }
        let current = typingExpiry.keys.sorted()
        if current != typingNicks { typingNicks = current }
    }

    func clearTyping(nick: String) {
        guard typingExpiry.removeValue(forKey: nick) != nil else { return }
        refreshTyping()
    }
}
