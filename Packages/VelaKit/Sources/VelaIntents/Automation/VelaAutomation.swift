// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaIntelligence
import VelaIRC
import VelaStore

/// What automation asks of the window, which only the scene layer can do.
/// VelaUI provides it; tests stand in for it.
@MainActor
public protocol AutomationPresenter: AnyObject {
    /// Brings Vela to the front, opening the main window if it's closed,
    /// without changing what's selected.
    func activate()
    /// Opens message search with a query, maybe narrowed to one network or
    /// conversation.
    func openSearch(_ request: MessageSearchRequest)
    /// Opens Join Channel for a network with `channel` filled in. You
    /// press Join.
    func offerToJoin(_ channel: String, networkID: UUID)
    /// A short notice in the main window, such as why a link did nothing.
    func notice(_ message: String)
}

/// A request to open message search.
nonisolated public struct MessageSearchRequest: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public var query: String
    /// One conversation, or nil.
    public var bufferID: BufferID?
    /// One network, or nil (ignored with a conversation).
    public var networkID: UUID?

    public init(query: String, bufferID: BufferID? = nil, networkID: UUID? = nil) {
        self.query = query
        self.bufferID = bufferID
        self.networkID = networkID
    }
}

/// What Vela's automation can do, shared by `vela://` links
/// (``VelaLinkRouter``), the AppleScript dictionary (Scripting/) and,
/// where they overlap, the App Intents: finding networks and
/// conversations by name or id, showing them, Catch me up, Recap, search,
/// and (for AppleScript only) sending, joining and marking read.
///
/// Everything runs on the main actor and is quick: lookups go through the
/// open buffers, never the database.
@MainActor
public final class VelaAutomation {
    public let app: AppModel
    public let services: IntelligenceServices
    public weak var presenter: (any AutomationPresenter)?

    /// The running app's automation, for Cocoa scripting (which can't be
    /// handed it). Set by the scene layer at launch.
    public static var shared: VelaAutomation?

    /// The AppleScript dictionary's version, its application's `scripting
    /// version`, which the Alfred workflow and the Raycast extension read.
    /// Raised only when a change could break scripts, the Alfred workflow
    /// or the Raycast extension: a term, code or cocoa key removed or
    /// renamed, or a command that behaves differently. Adding to the
    /// dictionary never raises it.
    nonisolated public static let scriptingVersion = 1

    public init(app: AppModel, services: IntelligenceServices, presenter: (any AutomationPresenter)? = nil) {
        self.app = app
        self.services = services
        self.presenter = presenter
    }

    // MARK: Finding networks

    /// The network `reference` names: its id (a UUID), or its name as Vela
    /// shows it, ignoring case.
    public func network(_ reference: String) throws -> NetworkSession {
        let name = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessions = app.automationSessions
        if let id = UUID(uuidString: name), let session = sessions.first(where: { $0.id == id }) {
            return session
        }
        let matches = sessions.filter { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
        guard let first = matches.first else { throw AutomationError.unknownNetwork(name) }
        guard matches.count == 1 else { throw AutomationError.ambiguousNetwork(name) }
        return first
    }

    // MARK: Finding conversations

    /// The open channel or private conversation `reference` names. Without
    /// a network, the network you're looking at is tried first; a name on
    /// more than one of the others is ambiguous.
    public func conversation(_ reference: ConversationReference) throws -> (session: NetworkSession, buffer: BufferModel) {
        let sessions = try candidateSessions(for: reference)
        switch reference.target {
        case .id(let id):
            guard sessions.contains(where: { $0.id == id.networkID }), let target = app.lookup(id), target.buffer.kind != .server else {
                throw AutomationError.unknownConversation(reference.description)
            }
            return target
        case .channel(let name), .nick(let name):
            let kind: BufferKind = if case .channel = reference.target { .channel } else { .query }
            let matches = sessions.compactMap { session -> (session: NetworkSession, buffer: BufferModel)? in
                let lookup = kind == .channel ? Self.channelName(name, in: session) : name
                guard let buffer = session.buffer(named: lookup), buffer.kind == kind else { return nil }
                return (session, buffer)
            }
            return try pick(matches, for: reference)
        }
    }

    /// Like ``conversation(_:)``, but a nick with no private conversation
    /// yet gets one, as `/query` does (nothing is sent): on the network
    /// named, else the one you're looking at, else your only network.
    public func conversationOpeningQuery(_ reference: ConversationReference) throws -> (session: NetworkSession, buffer: BufferModel) {
        do {
            return try conversation(reference)
        } catch AutomationError.unknownConversation(let name) {
            guard case .nick(let nick) = reference.target else { throw AutomationError.unknownConversation(name) }
            let session: NetworkSession
            if let network = reference.network {
                session = try self.network(network)
            } else if let selected = app.selectedSession, app.automationSessions.contains(where: { $0 === selected }) {
                session = selected
            } else if app.automationSessions.count == 1 {
                session = app.automationSessions[0]
            } else {
                throw AutomationError.ambiguousConversation(nick)
            }
            guard Self.isNick(nick, in: session) else { throw AutomationError.unknownConversation(name) }
            return (session, session.ensureBuffer(name: nick, kind: .query))
        }
    }

    /// The networks a reference may be on: the one it names, or every network.
    private func candidateSessions(for reference: ConversationReference) throws -> [NetworkSession] {
        if let network = reference.network { return [try self.network(network)] }
        return app.automationSessions
    }

    /// One match: the only one, or the one on the network you're looking at.
    private func pick(
        _ matches: [(session: NetworkSession, buffer: BufferModel)],
        for reference: ConversationReference
    ) throws -> (session: NetworkSession, buffer: BufferModel) {
        if matches.count == 1 { return matches[0] }
        guard !matches.isEmpty else { throw AutomationError.unknownConversation(reference.description) }
        if let selected = app.selectedSession, let match = matches.first(where: { $0.session === selected }) {
            return match
        }
        throw AutomationError.ambiguousConversation(reference.description)
    }

    /// `name` as a channel name on `session`: "#" added when it has no
    /// channel prefix there.
    static func channelName(_ name: String, in session: NetworkSession) -> String {
        session.isupport.isChannel(name) ? name : "#" + name
    }

    /// Whether `name` could be a nick on `session`: not a channel name, and
    /// none of the characters IRC masks and prefixes use.
    static func isNick(_ name: String, in session: NetworkSession) -> Bool {
        guard let first = name.first, !session.isupport.isChannel(name), !first.isNumber, first != "-" else { return false }
        return !name.contains { "!@*?:,. ".contains($0) || $0.isWhitespace }
    }

    // MARK: Showing

    /// Brings Vela forward to `buffer`, maybe with text added to its message
    /// box (after what's there: see ``ShowRequest/composerText(existing:draft:appending:)``)
    /// or scrolled to a message.
    public func show(_ buffer: BufferModel, draft: String? = nil, line: LineReference? = nil) {
        app.requestShow(buffer.id, draft: draft, appendingDraft: draft != nil, line: line)
    }

    /// Opens `buffer` with its Catch me up card, as its menu item does.
    /// Throws, without opening anything, while Catch me up is off or the
    /// model it uses can't run: Apple Intelligence, unless it uses one of
    /// your own providers' models, which don't need it (as for Siri and
    /// Recap).
    public func openCatchUp(_ buffer: BufferModel, session: NetworkSession) throws {
        guard buffer.kind != .server else { throw AutomationError.serverBuffer(network: session.displayName) }
        guard app.settings[.intelligenceCatchUp] else { throw AutomationError.turnedOff("Catch me up") }
        services.availability.refresh()
        let status = services.status(for: .catchUp)
        guard status.isAvailable else { throw AutomationError.intelligenceUnavailable(status.detail) }
        services.catchUp.openCard(for: buffer, session: session, app: app)
        app.requestShow(buffer.id)
    }

    /// The conversation Catch me up picks without one: the unmuted one with
    /// the most unread messages.
    public var busiestUnread: (session: NetworkSession, buffer: BufferModel)? {
        guard let buffer = app.busiestUnreadBuffer, let session = app.session(for: buffer.id.networkID) else { return nil }
        return (session, buffer)
    }

    /// The Recap asked for: one conversation, else one network, else every
    /// network. A person's Recap of a conversation covers its network, so
    /// it includes your private conversation with them. Summarized when
    /// Recap's model can run (Apple Intelligence, or your own provider's),
    /// a log otherwise.
    public func recapScope(conversation: BufferID? = nil, network: UUID? = nil, person: String? = nil, span: RecapSpanOption = .sinceUnread) -> RecapScope {
        Self.recapScope(conversation: conversation, network: network, person: person, span: span, services: services)
    }

    /// ``recapScope(conversation:network:person:span:)``, for the Open Recap
    /// action too.
    static func recapScope(conversation: BufferID?, network: UUID?, person: String?, span: RecapSpanOption, services: IntelligenceServices) -> RecapScope {
        let person = person?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let place: RecapScope.Place
        if let conversation {
            place = person?.isEmpty == false ? .network(conversation.networkID) : .buffer(conversation)
        } else if let network {
            place = .network(network)
        } else {
            place = .everywhere
        }
        services.availability.refresh()
        // A model of your own writes summaries without Apple Intelligence.
        let output: RecapScope.Output = services.status(for: .recap).isAvailable ? .summary : .log
        return RecapScope(place: place, person: person, span: span.span, output: output)
    }

    /// Opens a Recap window. Throws while Recap is turned off.
    public func openRecap(_ scope: RecapScope) throws {
        guard app.settings[.intelligenceRecap] else { throw AutomationError.turnedOff("Recap") }
        services.recaps.open(scope)
    }

    /// Opens message search with `query`.
    public func search(_ query: String, bufferID: BufferID? = nil, networkID: UUID? = nil) {
        presenter?.openSearch(MessageSearchRequest(query: query, bufferID: bufferID, networkID: networkID))
    }

    /// Shows `channel` if you're in it; otherwise opens Join Channel with it
    /// filled in. Never joins by itself: for links, which anyone can make.
    public func offerToJoin(_ channel: String, on session: NetworkSession) throws {
        let name = try AppModel.channelName(channel, isChannel: session.isupport.isChannel)
        if let buffer = session.buffer(named: name), buffer.kind == .channel, buffer.isJoined {
            show(buffer)
            return
        }
        presenter?.offerToJoin(name, networkID: session.id)
    }

    // MARK: Acting (AppleScript)

    /// The most lines a message may have before it needs
    /// `allowing multiple lines`: what the message box sends without
    /// asking (more than this asks before sending).
    public static let lineConfirmationThreshold = 3
    /// The most IRC messages one send may become, long lines split.
    public static let maximumIRCMessages = 50

    /// Sends `text` to a joined channel or an open private conversation, as
    /// plain text: "/help" is sent as the words "/help", never run as a
    /// command. Long text is split as the message box splits it, and goes
    /// out at the network's pace (flood protection). More than
    /// ``lineConfirmationThreshold`` lines need `allowingMultipleLines`, as
    /// the message box asks first. Waits a few seconds for a network that's
    /// still connecting.
    public func send(_ text: String, to buffer: BufferModel, in session: NetworkSession, allowingMultipleLines: Bool, connectionTimeout: Duration = .seconds(10)) async throws {
        guard buffer.kind != .server else { throw AutomationError.serverBuffer(network: session.displayName) }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw AutomationError.emptyMessage }
        let lines = message.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }.count
        if lines > Self.lineConfirmationThreshold, !allowingMultipleLines {
            throw AutomationError.tooManyLines(lines, limit: Self.lineConfirmationThreshold)
        }
        let messages = IRCMessage.chatLines(target: buffer.name, text: message).count
        guard messages <= Self.maximumIRCMessages else {
            throw AutomationError.messageTooLong(messages, limit: Self.maximumIRCMessages)
        }
        do {
            try await app.send(message, to: buffer.id, connectionTimeout: connectionTimeout)
        } catch {
            throw AutomationError.wrapping(error)
        }
    }

    /// Joins `channel` (adding "#" if it has no prefix) without switching to
    /// it, and waits a few seconds for the server to confirm. Returns the
    /// channel's buffer, joined or still joining.
    public func join(_ channel: String, on session: NetworkSession, key: String? = nil, timeout: Duration = .seconds(8)) async throws -> BufferModel {
        let buffer: BufferModel
        do {
            buffer = try await app.join(channel, on: session.id, key: key)
        } catch {
            throw AutomationError.wrapping(error)
        }
        _ = await app.waitUntil(timeout: timeout) { buffer.isJoined }
        return buffer
    }

    /// Marks everything in `buffer` read.
    public func markRead(_ buffer: BufferModel, in session: NetworkSession) {
        session.markRead(buffer)
    }

    /// Marks every buffer read; returns how many had something unread.
    @discardableResult
    public func markAllRead() -> Int {
        app.markAllRead()
    }

    /// Marks you away on every connected network, like `/away`. Returns
    /// their names.
    public func setAway(_ message: String?) async throws -> [String] {
        do {
            return try await app.setAway(message).map(\.displayName)
        } catch {
            throw AutomationError.wrapping(error)
        }
    }

    /// Marks you back on every connected network, like `/back`.
    public func setBack() async throws -> [String] {
        do {
            return try await app.setBack().map(\.displayName)
        } catch {
            throw AutomationError.wrapping(error)
        }
    }

    // MARK: Reading

    /// What's unread in `buffer`, counted as Siri counts it (from the read
    /// position as well as live counts).
    public func unread(_ buffer: BufferModel) -> UnreadTally {
        app.unreadTally(for: buffer)
    }

    /// Channels and private conversations with something unread, in sidebar
    /// order. Muted ones count only with mentions.
    public var unreadConversations: [BufferModel] {
        app.conversationBuffers.filter { buffer in
            let tally = app.unreadTally(for: buffer)
            return buffer.isMuted ? tally.mentions > 0 : tally.unread > 0
        }
    }
}
