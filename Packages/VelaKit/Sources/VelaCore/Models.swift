// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaFoundation
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

    /// Parses ``description``. The UUID is case-insensitive; the name is
    /// everything after the first `/` (it may contain `/` itself) and must
    /// not be empty.
    public init?(string: String) {
        guard let slash = string.firstIndex(of: "/"),
              let networkID = UUID(uuidString: String(string[..<slash]))
        else { return nil }
        let name = String(string[string.index(after: slash)...])
        guard !name.isEmpty else { return nil }
        self.init(networkID: networkID, foldedName: name)
    }
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
    /// A channel detached on a bouncer: the bouncer stays in it and keeps
    /// its history, but Vela isn't in it (`isJoined` is false) until it's
    /// joined again. It shows dimmed, like a channel you left.
    public internal(set) var isDetached = false
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

    /// Adds a line in time order. Returns false, adding nothing, for a
    /// copy of a line already here (see `isCopy(_:of:)`).
    @discardableResult
    func append(_ line: ChatLine, limit: Int) -> Bool {
        if let msgid = line.msgid, lines.suffix(200).contains(where: { $0.msgid == msgid }) { return false }
        if line.isHistory, line.msgid == nil, containsCopy(of: line) { return false }
        if let last = lines.last, last.time > line.time {
            insertSorted([line])
        } else {
            lines.append(line)
        }
        if let nick = Self.speaker(of: line) { nickColors?.noteSpeaker(nick) }
        if lines.count > limit + 200 {
            lines.removeFirst(lines.count - limit)
            hasMoreHistory = true
        }
        return true
    }

    /// Merges lines (any order), skipping lines already here (by id or
    /// msgid) and, for history, copies of them (see `isCopy(_:of:)`),
    /// including copies within `newLines`. Live lines that merely arrive
    /// out of order are never taken for copies.
    func insertSorted(_ newLines: [ChatLine]) {
        guard !newLines.isEmpty else { return }
        let knownMsgids = Set(lines.compactMap(\.msgid))
        let knownIDs = Set(lines.map(\.id))
        var fresh: [ChatLine] = []
        for line in newLines.sorted(by: { $0.time < $1.time }) {
            if knownIDs.contains(line.id) { continue }
            if let msgid = line.msgid {
                if knownMsgids.contains(msgid) { continue }
            } else if line.isHistory, containsCopy(of: line) || fresh.reversed().prefix(while: { line.time.timeIntervalSince($0.time) <= Self.copyWindow }).contains(where: { Self.isCopy(line, of: $0) }) {
                continue
            }
            fresh.append(line)
        }
        guard !fresh.isEmpty else { return }
        lines = (lines + fresh).sorted { $0.time < $1.time }
        for nick in fresh.compactMap(Self.speaker(of:)) { nickColors?.noteEarlierSpeaker(nick) }
    }

    // MARK: Nick colors

    /// Who has which nick color here; built on first use for a palette.
    @ObservationIgnored private var nickColors: NickColorAssigner?

    /// `nick`'s color in this conversation, as an index into the palette
    /// `palette` describes. People talking here get different colors (see
    /// `NickColorAssigner`); a nick that hasn't spoken gets its usual one.
    public func nickColorIndex(for nick: String, palette: NickPaletteGeometry) -> Int {
        if nickColors?.palette.signature != palette.signature || nickColors?.palette.count != palette.count {
            // First use, or the theme changed: replay the conversation.
            // From the lines' storage, not `lines`: this runs inside a row's
            // body, which would then re-run on the next line to arrive.
            var assigner = NickColorAssigner(palette: palette)
            for nick in _lines.compactMap(Self.speaker(of:)) { assigner.noteSpeaker(nick) }
            nickColors = assigner
        }
        return nickColors?.index(for: nick) ?? 0
    }

    /// The nick that said `line`, if it's something someone else said
    /// (your own nick has its own color).
    private nonisolated static func speaker(of line: ChatLine) -> String? {
        line.kind.isConversation && !line.isSelf ? line.nick : nil
    }

    // MARK: Copies

    /// How far apart two copies of one message can be stamped. A bouncer
    /// replaying what it buffered (ZNC sends no msgids) stamps each line
    /// with its own clock, and our own lines were stamped locally.
    nonisolated static let copyWindow = VelaDatabase.copyWindow

    /// Whether `line` repeats `other`: something said (not an event) by the
    /// same nick with the same text, stamped within `copyWindow`. Lines
    /// that both have msgids are only ever matched by msgid.
    nonisolated static func isCopy(_ line: ChatLine, of other: ChatLine) -> Bool {
        guard line.kind.isConversation, line.kind == other.kind,
              line.msgid == nil || other.msgid == nil,
              line.nick == other.nick, line.text == other.text else { return false }
        return abs(line.time.timeIntervalSince(other.time)) <= copyWindow
    }

    /// Whether a line here is a copy of `line`. Lines are in time order, so
    /// only those within `copyWindow` of it are compared.
    func containsCopy(of line: ChatLine) -> Bool {
        guard line.kind.isConversation else { return false }
        let start = line.time.addingTimeInterval(-Self.copyWindow)
        // First line at or after `start`.
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time < start { low = mid + 1 } else { high = mid }
        }
        var index = low
        while index < lines.count, lines[index].time.timeIntervalSince(line.time) <= Self.copyWindow {
            if Self.isCopy(line, of: lines[index]) { return true }
            index += 1
        }
        return false
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
