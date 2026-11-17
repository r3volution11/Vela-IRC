// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import CoreSpotlight
import Foundation
import GeoToolbox
import LinkPresentation
import VelaCore
import VelaIRC

// Siri on macOS 27 understands messaging apps through the `.messages`
// schema domain (Apple's UnicornChat sample, WWDC26 session 240). These
// entities describe Vela's conversations, people and messages in its terms.
// Channel and private-conversation names are what Siri and Spotlight see;
// message text is only handed over when Siri asks about one message, for
// example one in a notification.

// MARK: - Conversation

/// A channel or private conversation, as the `.messages` domain sees it.
/// Shares its identifier with ``ChannelEntity``.
@available(macOS 27, *)
@AppEntity(schema: .messages.conversation)
struct ConversationEntity: IndexedEntity {
    static let defaultQuery = ConversationQuery()

    var id: String

    /// Who a reply goes to: the channel itself, or the other person in a
    /// private conversation (see ``MessagePersonEntity``).
    var recipients: [MessagePersonEntity]

    /// "#vela", or a nick.
    var displayName: String

    /// The network's name. (Never a message: this is indexed.)
    var previewText: AttributedString

    /// The channel name; nil for a private conversation.
    var conversationName: String?

    var isRead: Bool

    var attributes: Set<ConversationAttribute>

    /// When the newest line arrived.
    var dateLastActive: Date?

    var isPrivate: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "\(previewText)",
            image: .init(systemName: isPrivate ? "person.crop.circle" : "number")
        )
    }

    /// Indexed so Siri can find conversations by name, but ``ChannelEntity``
    /// is the Spotlight result people see.
    var hideInSpotlight: Bool { true }

    @MainActor
    init(buffer: BufferModel, session: NetworkSession) {
        self.id = buffer.id.description
        self.isPrivate = buffer.kind == .query
        self.recipients = [MessagePersonEntity(buffer: buffer, session: session)]
        self.displayName = buffer.name
        self.previewText = AttributedString(session.displayName)
        self.conversationName = buffer.kind == .channel ? buffer.name : nil
        self.isRead = buffer.unreadCount == 0
        self.attributes = buffer.isMuted ? [.muted] : []
        self.dateLastActive = buffer.lines.last?.time
    }

    @MainActor
    init?(bufferID: BufferID, in app: AppModel) {
        guard let target = app.lookup(bufferID), target.buffer.kind != .server else { return nil }
        self.init(buffer: target.buffer, session: target.session)
    }

    @MainActor
    static func all(in app: AppModel) -> [ConversationEntity] {
        app.conversationBuffers.compactMap { ConversationEntity(bufferID: $0.id, in: app) }
    }
}

@available(macOS 27, *)
@AppEnum(schema: .messages.conversationAttribute)
enum ConversationAttribute: String, AppEnum {
    case muted

    static let caseDisplayRepresentations: [ConversationAttribute: DisplayRepresentation] = [
        .muted: "Muted",
    ]
}

@available(macOS 27, *)
struct ConversationQuery: EntityStringQuery {
    @Dependency private var app: AppModel

    @MainActor
    func entities(for identifiers: [ConversationEntity.ID]) async throws -> [ConversationEntity] {
        await app.ready()
        return identifiers.compactMap { BufferID(string: $0).flatMap { ConversationEntity(bufferID: $0, in: app) } }
    }

    @MainActor
    func entities(matching string: String) async throws -> [ConversationEntity] {
        await app.ready()
        return ChannelEntity.matching(string, in: app).compactMap { channel in
            channel.bufferID.flatMap { ConversationEntity(bufferID: $0, in: app) }
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [ConversationEntity] {
        await app.ready()
        return ConversationEntity.all(in: app)
    }
}

// MARK: - Recipients

/// Who a message goes to. The `.messages` domain only sends to people, so
/// on IRC this is any message target: a nick, or a channel ("#vela"), which
/// takes messages the same way. Identified like a buffer:
/// "<network-uuid>/<folded-name>".
@available(macOS 27, *)
@AppEntity(schema: .messages.messagePerson)
struct MessagePersonEntity: IndexedEntity {
    static let defaultQuery = MessagePersonQuery()

    var id: String

    var person: IntentPerson

    /// The nick or channel name, as written.
    var name: String
    var networkName: String
    var isChannel: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(networkName)",
            image: .init(systemName: isChannel ? "number" : "person.crop.circle")
        )
    }

    /// Indexed so Siri can find "#vela" by name; Spotlight shows
    /// ``ChannelEntity`` instead.
    var hideInSpotlight: Bool { true }

    init(name: String, networkID: UUID, networkName: String, isChannel: Bool, fold: (String) -> String, isMe: Bool = false) {
        let id = BufferID(networkID: networkID, foldedName: fold(name)).description
        self.id = id
        self.name = name
        self.networkName = networkName
        self.isChannel = isChannel
        self.person = IntentPerson(
            identifier: .applicationDefined(id),
            name: .displayName(name),
            handle: .init(applicationDefined: name, label: networkName),
            isMe: isMe
        )
    }

    /// The channel, or the other person, of a conversation.
    @MainActor
    init(buffer: BufferModel, session: NetworkSession) {
        self.init(name: buffer.name, networkID: session.id, networkName: session.displayName,
                  isChannel: buffer.kind == .channel, fold: session.foldName)
    }

    /// Someone by nick (an author, say).
    @MainActor
    init(nick: String, session: NetworkSession, isMe: Bool = false) {
        self.init(name: nick, networkID: session.id, networkName: session.displayName,
                  isChannel: false, fold: session.foldName, isMe: isMe)
    }

    /// The target behind `id`, named as last seen.
    @MainActor
    init?(id: String, in app: AppModel) {
        guard let parsed = BufferID(string: id), let session = app.session(for: parsed.networkID) else { return nil }
        if let buffer = session.buffer(id: parsed), buffer.kind != .server {
            self.init(buffer: buffer, session: session)
        } else {
            let nick = Self.displayNick(folded: parsed.foldedName, in: session)
            self.init(nick: nick, session: session, isMe: session.foldName(session.nick) == parsed.foldedName)
        }
    }

    /// A nick as people write it, from a channel's member list; the folded
    /// form if no channel has it.
    @MainActor
    static func displayNick(folded: String, in session: NetworkSession) -> String {
        if session.foldName(session.nick) == folded { return session.nick }
        for channel in session.channels {
            if let member = channel.member(named: folded, caseMapping: session.isupport.caseMapping) { return member.nick }
        }
        return folded
    }

    /// Every channel and private conversation, in sidebar order.
    @MainActor
    static func all(in app: AppModel) -> [MessagePersonEntity] {
        app.conversationBuffers.compactMap { buffer in
            app.session(for: buffer.id.networkID).map { MessagePersonEntity(buffer: buffer, session: $0) }
        }
    }
}

@available(macOS 27, *)
struct MessagePersonQuery: EntityStringQuery {
    @Dependency private var app: AppModel

    @MainActor
    func entities(for identifiers: [MessagePersonEntity.ID]) async throws -> [MessagePersonEntity] {
        await app.ready()
        return identifiers.compactMap { MessagePersonEntity(id: $0, in: app) }
    }

    /// Your channels and conversations that match (see
    /// ``ChannelEntity/matching(_:in:)``), then channel members whose nick
    /// contains `string`.
    @MainActor
    func entities(matching string: String) async throws -> [MessagePersonEntity] {
        await app.ready()
        var seen = Set<String>()
        var results = ChannelEntity.matching(string, in: app).compactMap { channel in
            channel.bufferID.flatMap { id in app.lookup(id).map { MessagePersonEntity(buffer: $0.buffer, session: $0.session) } }
        }
        results.forEach { seen.insert($0.id) }
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return results }
        var members: [MessagePersonEntity] = []
        for session in app.sessions {
            for channel in session.channels {
                for member in channel.members where members.count < 25 && member.nick.lowercased().contains(needle) {
                    let entity = MessagePersonEntity(nick: member.nick, session: session)
                    if seen.insert(entity.id).inserted { members.append(entity) }
                }
            }
        }
        results += members.sorted { ($0.name.lowercased() == needle ? 0 : 1) < ($1.name.lowercased() == needle ? 0 : 1) }
        return results
    }

    @MainActor
    func suggestedEntities() async throws -> [MessagePersonEntity] {
        await app.ready()
        return MessagePersonEntity.all(in: app)
    }
}

// MARK: - Messages

/// One line someone said. Identified by "<line-uuid>/<buffer-id>"; only
/// lines still in memory can be looked up.
@available(macOS 27, *)
@AppEntity(schema: .messages.message)
struct MessageEntity: AppEntity {
    static let defaultQuery = MessageQuery()

    var id: String

    var messageType: MessageType

    var author: MessagePersonEntity

    var isRead: Bool

    var attributes: Set<MessageAttribute>

    var conversation: ConversationEntity

    var date: Date

    var subject: AttributedString?

    var body: AttributedString?

    var attachments: [IntentFile]

    var audioMessage: IntentFile?

    var customAttachments: [CustomAttachment]

    var locations: [PlaceDescriptor]

    var links: [LinkPresentation.LinkMetadata]

    var messageEffect: MessageEffect?

    var reaction: MessageReaction?

    var referencedMessage: MessageEntity?

    var notificationIdentifier: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(body ?? Self.deletedPlaceholder)",
            subtitle: "\(author.name) in \(conversation.displayName)"
        )
    }

    /// What a deleted (redacted) message shows instead of its text, as in
    /// the message list.
    static var deletedPlaceholder: AttributedString { "Message deleted" }

    static func id(line: UUID, buffer: BufferID) -> String {
        "\(line.uuidString)/\(buffer.description)"
    }

    /// The line and buffer an ``id(line:buffer:)`` names.
    static func parse(_ id: String) -> (line: UUID, buffer: BufferID)? {
        guard let slash = id.firstIndex(of: "/"),
              let line = UUID(uuidString: String(id[..<slash])),
              let buffer = BufferID(string: String(id[id.index(after: slash)...]))
        else { return nil }
        return (line, buffer)
    }

    @MainActor
    init(line: ChatLine, buffer: BufferModel, session: NetworkSession) {
        let nick = line.nick ?? (line.isSelf ? session.nick : buffer.name)
        self.id = Self.id(line: line.id, buffer: buffer.id)
        self.messageType = .unspecified
        self.author = MessagePersonEntity(nick: nick, session: session, isMe: line.isSelf)
        self.isRead = line.isSelf || line.time <= (buffer.lastReadAt ?? .distantPast)
        self.attributes = line.isHighlight ? [.mention] : []
        self.conversation = ConversationEntity(buffer: buffer, session: session)
        self.date = line.time
        // A deleted message's text stays in memory; Siri never gets it.
        self.body = line.isRedacted ? nil : AttributedString(IRCFormatting.strip(line.text))
        self.attachments = []
        self.customAttachments = []
        self.locations = []
        self.links = []
        self.messageEffect = line.kind == .action ? .action : nil
        self.notificationIdentifier = nil
    }

    @MainActor
    init?(id: String, in app: AppModel) {
        guard let parsed = Self.parse(id),
              let target = app.lookup(parsed.buffer),
              let line = target.buffer.lines.last(where: { $0.id == parsed.line })
        else { return nil }
        self.init(line: line, buffer: target.buffer, session: target.session)
    }
}

@available(macOS 27, *)
struct MessageQuery: EntityStringQuery {
    @Dependency private var app: AppModel

    @MainActor
    func entities(for identifiers: [MessageEntity.ID]) async throws -> [MessageEntity] {
        await app.ready()
        return identifiers.compactMap { MessageEntity(id: $0, in: app) }
    }

    /// Recent messages (still in memory) whose text or author contains
    /// `string`, newest first. Nothing is indexed; this runs only when Siri
    /// asks, on this Mac.
    @MainActor
    func entities(matching string: String) async throws -> [MessageEntity] {
        await app.ready()
        return MessageEntity.recent(matching: string, in: app)
    }
}

@available(macOS 27, *)
extension MessageEntity {
    /// How many messages a search returns at most, and how far back it looks
    /// in each conversation.
    static let searchLimit = 10
    static let searchDepth = 200

    @MainActor
    static func recent(matching query: String, in app: AppModel) -> [MessageEntity] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var found: [(line: ChatLine, buffer: BufferModel, session: NetworkSession)] = []
        for buffer in app.conversationBuffers {
            guard let session = app.session(for: buffer.id.networkID) else { continue }
            for line in buffer.lines.suffix(searchDepth) where line.kind.isConversation && !line.isRedacted {
                if line.text.localizedCaseInsensitiveContains(needle)
                    || (line.nick?.localizedCaseInsensitiveContains(needle) ?? false) {
                    found.append((line, buffer, session))
                }
            }
        }
        return found
            .sorted { $0.line.time > $1.line.time }
            .prefix(searchLimit)
            .map { MessageEntity(line: $0.line, buffer: $0.buffer, session: $0.session) }
    }
}

@available(macOS 27, *)
@AppEnum(schema: .messages.messageType)
enum MessageType: String, AppEnum {
    case unspecified

    static let caseDisplayRepresentations: [MessageType: DisplayRepresentation] = [
        .unspecified: "Message",
    ]
}

@available(macOS 27, *)
@AppEnum(schema: .messages.messageAttribute)
enum MessageAttribute: String, AppEnum {
    /// The message mentions you (a highlight).
    case mention

    static let caseDisplayRepresentations: [MessageAttribute: DisplayRepresentation] = [
        .mention: "Mentions You",
    ]
}

@available(macOS 27, *)
@AppEnum(schema: .messages.messageEffect)
enum MessageEffect: String, AppEnum {
    /// An IRC action ("/me waves").
    case action

    static let caseDisplayRepresentations: [MessageEffect: DisplayRepresentation] = [
        .action: "Action",
    ]
}

/// IRC reactions are emoji (`+draft/react`).
@available(macOS 27, *)
@UnionValue
enum MessageReaction {
    case attributedString(AttributedString)
}

/// IRC has no attachments other than links; Vela never returns these.
@available(macOS 27, *)
@AppEntity(schema: .messages.customAttachment)
struct CustomAttachment: AppEntity {
    static let defaultQuery = CustomAttachmentQuery()

    var id: UUID

    var sourceName: AttributedString?

    var description: AttributedString?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(description ?? "")")
    }

    struct CustomAttachmentQuery: EntityQuery {
        func entities(for identifiers: [CustomAttachment.ID]) async throws -> [CustomAttachment] {
            []
        }
    }
}
