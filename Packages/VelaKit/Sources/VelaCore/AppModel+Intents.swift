// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaIRC

// What Siri, Shortcuts and Spotlight can do with Vela. Each call reports
// failure as an `AppActionError` (a session reports problems only as lines
// in a buffer, which nobody sees when Siri is asking).

/// Why Siri or Shortcuts couldn't do something. The descriptions are what
/// Siri says, so they're short and plain.
nonisolated public enum AppActionError: Error, Equatable, LocalizedError {
    case unknownBuffer
    case unknownNetwork
    /// Network consoles take commands, not messages.
    case serverBuffer(network: String)
    case notConnected(network: String)
    case notJoined(channel: String, network: String)
    case noConnectedNetworks
    case emptyMessage
    case invalidChannelName(String)

    public var errorDescription: String? {
        switch self {
        case .unknownBuffer: "Vela couldn't find that channel."
        case .unknownNetwork: "Vela couldn't find that network."
        case .serverBuffer(let network): "You can't send messages to the \(network) console."
        case .notConnected(let network): "You're not connected to \(network)."
        case .notJoined(let channel, let network): "You're not in \(channel) on \(network)."
        case .noConnectedNetworks: "You're not connected to any networks."
        case .emptyMessage: "There's nothing to send."
        case .invalidChannelName(let name): "“\(name)” isn't a channel name."
        }
    }
}

/// Channels and conversations that mention you, for "Check Mentions".
nonisolated public struct MentionSummary: Sendable, Hashable {
    public struct Entry: Sendable, Hashable, Identifiable {
        public var bufferID: BufferID
        public var name: String
        public var networkName: String
        public var isPrivate: Bool
        /// Highlights (in a private conversation, every new message).
        public var mentions: Int
        public var unread: Int

        public var id: BufferID { bufferID }

        public init(bufferID: BufferID, name: String, networkName: String, isPrivate: Bool, mentions: Int, unread: Int) {
            self.bufferID = bufferID
            self.name = name
            self.networkName = networkName
            self.isPrivate = isPrivate
            self.mentions = mentions
            self.unread = unread
        }
    }

    /// In sidebar order.
    public var entries: [Entry]

    public var totalMentions: Int { entries.reduce(0) { $0 + $1.mentions } }
    public var isEmpty: Bool { entries.isEmpty }

    public init(entries: [Entry]) {
        self.entries = entries
    }
}

extension AppModel {
    // MARK: Buffers

    /// Channels and private conversations (no network consoles), in sidebar order.
    public var conversationBuffers: [BufferModel] {
        orderedBuffers.filter { $0.kind != .server }
    }

    /// The buffer and its session for `bufferID`, if it's open.
    public func lookup(_ bufferID: BufferID) -> (session: NetworkSession, buffer: BufferModel)? {
        guard let session = session(for: bufferID.networkID), let buffer = session.buffer(id: bufferID) else { return nil }
        return (session, buffer)
    }

    /// The unmuted channel or conversation with the most unread lines (ties
    /// go to more mentions, then sidebar order), for "Catch Me Up".
    public var busiestUnreadBuffer: BufferModel? {
        var best: BufferModel?
        for buffer in conversationBuffers where !buffer.isMuted && buffer.unreadCount > 0 {
            guard let current = best else {
                best = buffer
                continue
            }
            if buffer.unreadCount > current.unreadCount
                || (buffer.unreadCount == current.unreadCount && buffer.highlightCount > current.highlightCount) {
                best = buffer
            }
        }
        return best
    }

    // MARK: Mentions

    /// Buffers with mentions, in sidebar order.
    public var mentionSummary: MentionSummary {
        let entries = conversationBuffers.compactMap { buffer -> MentionSummary.Entry? in
            guard buffer.highlightCount > 0, let session = session(for: buffer.id.networkID) else { return nil }
            return MentionSummary.Entry(
                bufferID: buffer.id,
                name: buffer.name,
                networkName: session.displayName,
                isPrivate: buffer.kind == .query,
                mentions: buffer.highlightCount,
                unread: buffer.unreadCount
            )
        }
        return MentionSummary(entries: entries)
    }

    // MARK: Sending

    /// Sends `text` to a channel or private conversation as an ordinary
    /// message.
    ///
    /// The text is never read as a command: "/help" from Siri is sent as the
    /// words "/help", the way the composer sends text after the "//" escape.
    /// It goes straight to the session's message path (`InputCommand.say`)
    /// rather than through `NetworkSession.submit(_:in:replyTo:)`, so it's
    /// never parsed. Long text is split like typed messages.
    ///
    /// If the network is still connecting (Vela was just launched to run
    /// this), waits up to `connectionTimeout` for it, and for the channel to
    /// be joined again.
    public func send(_ text: String, to bufferID: BufferID, connectionTimeout: Duration = .seconds(10)) async throws {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw AppActionError.emptyMessage }
        guard let target = lookup(bufferID) else { throw AppActionError.unknownBuffer }
        let (session, buffer) = target
        guard buffer.kind != .server else { throw AppActionError.serverBuffer(network: session.displayName) }

        let clock = ContinuousClock()
        let deadline = clock.now + connectionTimeout
        let wasConnected = session.isConnected
        try await waitForConnection(session, timeout: connectionTimeout)
        if buffer.kind == .channel, !buffer.isJoined, !wasConnected {
            // Channels are rejoined right after connecting.
            _ = await waitUntil(timeout: max(.zero, deadline - clock.now)) { buffer.isJoined }
        }
        // The buffer may have been closed meanwhile.
        guard session.buffer(id: bufferID) != nil else { throw AppActionError.unknownBuffer }
        guard session.isConnected else { throw AppActionError.notConnected(network: session.displayName) }
        if buffer.kind == .channel, !buffer.isJoined {
            throw AppActionError.notJoined(channel: buffer.name, network: session.displayName)
        }
        session.perform(.say(message), in: buffer, replyTo: nil)
        if isDemo {
            // Demo sessions have no connection to echo it back.
            session.add(ChatLine(kind: .message, nick: session.nick, text: message, isSelf: true), to: buffer)
        }
    }

    /// Waits until `session` is connected. A connection in progress gets up
    /// to `timeout`; one that hasn't started gets a moment (Vela may have
    /// just launched and be about to connect), then this gives up.
    public func waitForConnection(_ session: NetworkSession, timeout: Duration = .seconds(10)) async throws {
        guard !session.isConnected else { return }
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start + timeout
        let grace = start + min(timeout, .milliseconds(1500))
        while !session.isConnected {
            let now = clock.now
            if now >= deadline || (session.connectionState == .disconnected && now >= grace) {
                throw AppActionError.notConnected(network: session.displayName)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Polls `condition` until it holds or `timeout` passes. Returns whether it held.
    public func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline, (try? await Task.sleep(for: .milliseconds(100))) != nil else {
                return condition()
            }
        }
        return true
    }

    // MARK: Joining

    /// Joins `channel` on a network, like `/join`, without switching to it.
    /// A name without a channel prefix gets "#". Returns the channel's
    /// buffer (it's joined once the server confirms; see ``waitUntil(timeout:_:)``).
    @discardableResult
    public func join(_ channel: String, on networkID: UUID, key: String?, connectionTimeout: Duration = .seconds(10)) async throws -> BufferModel {
        guard let session = session(for: networkID) else { throw AppActionError.unknownNetwork }
        let name = try Self.channelName(channel, isChannel: session.isupport.isChannel)
        try await waitForConnection(session, timeout: connectionTimeout)
        let buffer = session.ensureBuffer(name: name, kind: .channel)
        if !buffer.isJoined {
            let key = key?.trimmingCharacters(in: .whitespaces)
            let params = if let key, !key.isEmpty { [buffer.name, key] } else { [buffer.name] }
            session.send(IRCMessage(command: "JOIN", params: params))
            if isDemo { buffer.isJoined = true }
        }
        return buffer
    }

    /// `input` as a channel name: trimmed, with "#" added when it has no
    /// channel prefix. Spaces, commas and BEL aren't allowed in channel names.
    nonisolated static func channelName(_ input: String, isChannel: (String) -> Bool) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains(where: { $0.isWhitespace || $0 == "," || $0 == "\u{07}" }) else {
            throw AppActionError.invalidChannelName(input)
        }
        return isChannel(name) ? name : "#" + name
    }

    // MARK: Away

    /// Networks `/away` and `/back` go to: connected ones that chat (not a
    /// bouncer's control connection).
    public var awayTargets: [NetworkSession] {
        sessions.filter { $0.isConnected && !$0.isBouncerControl }
    }

    /// Marks you away on every connected network, like `/away`. Returns the
    /// networks it was sent to.
    @discardableResult
    public func setAway(_ message: String?) throws -> [NetworkSession] {
        let targets = awayTargets
        guard !targets.isEmpty else { throw AppActionError.noConnectedNetworks }
        let text = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        for session in targets {
            session.perform(.away(text?.isEmpty == false ? text : nil), in: session.serverBuffer, replyTo: nil)
        }
        return targets
    }

    /// Marks you back on every connected network, like `/back`.
    @discardableResult
    public func setBack() throws -> [NetworkSession] {
        let targets = awayTargets
        guard !targets.isEmpty else { throw AppActionError.noConnectedNetworks }
        for session in targets {
            session.perform(.back, in: session.serverBuffer, replyTo: nil)
        }
        return targets
    }

    // MARK: Read state

    /// Marks every buffer read, like Go → Mark All as Read. Returns how many
    /// buffers had something unread.
    @discardableResult
    public func markAllRead() -> Int {
        var count = 0
        for session in sessions {
            for buffer in session.allBuffers where buffer.unreadCount > 0 || buffer.highlightCount > 0 {
                session.markRead(buffer)
                count += 1
            }
        }
        return count
    }

    // MARK: Composer

    public func session(_ session: NetworkSession, didSendComposerMessageIn buffer: BufferModel) {
        onComposerMessage?(buffer, session)
    }
}

extension SessionHost {
    public func session(_ session: NetworkSession, didSendComposerMessageIn buffer: BufferModel) {}
}
