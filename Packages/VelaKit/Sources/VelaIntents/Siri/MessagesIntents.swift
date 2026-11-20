// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import GeoToolbox
import UniformTypeIdentifiers
import VelaCore

// Siri on macOS 27: send and draft messages ("send ‘brb’ to #vela in Vela",
// "reply to this"), and mark them read. Send and draft are one use-case
// group; Siri needs both. They're for Siri only: Shortcuts keeps the
// simpler Send Message action, whose parameters match IRC.

/// Where a message goes: one or more targets (nicks or channels).
@available(macOS 27, *)
@UnionValue
enum MessageDestination {
    case recipient(MessagePersonEntity)
    case recipients([MessagePersonEntity])

    var targets: [MessagePersonEntity] {
        switch self {
        case .recipient(let target): [target]
        case .recipients(let targets): targets
        }
    }
}

@available(macOS 27, *)
extension AppModel {
    /// The buffer a message to `target` goes to: an open channel or
    /// conversation, or a new private conversation with a nick (like `/msg`).
    func bufferID(for target: MessagePersonEntity) throws -> BufferID {
        try messageBuffer(for: target).id
    }

    /// ``bufferID(for:)``, and whether it opened a new private conversation.
    private func messageBuffer(for target: MessagePersonEntity) throws -> (id: BufferID, isNew: Bool) {
        guard let parsed = BufferID(string: target.id), let session = session(for: parsed.networkID) else {
            throw IntentFailure(.unknownBuffer)
        }
        if let buffer = session.buffer(id: parsed), buffer.kind != .server { return (buffer.id, false) }
        guard !session.isupport.isChannel(target.name) else {
            throw IntentFailure(.notJoined(channel: target.name, network: session.displayName))
        }
        return (session.ensureBuffer(name: target.name, kind: .query).id, true)
    }

    /// Sends `text` to each target in turn, opening private conversations
    /// as needed. One opened here that the message never reached (a target
    /// that failed, or one after it) is closed again, so a failed send
    /// leaves no empty conversation behind. Returns where it was sent.
    func sendMessage(_ text: String, to targets: [MessagePersonEntity], connectionTimeout: Duration = .seconds(10)) async throws -> [BufferID] {
        var opened: [BufferID] = []
        do {
            var bufferIDs: [BufferID] = []
            for target in targets {
                let buffer = try messageBuffer(for: target)
                if buffer.isNew { opened.append(buffer.id) }
                bufferIDs.append(buffer.id)
            }
            guard !bufferIDs.isEmpty else { throw IntentFailure(.unknownBuffer) }
            for bufferID in bufferIDs {
                try await send(text, to: bufferID, connectionTimeout: connectionTimeout)
                opened.removeAll { $0 == bufferID }
            }
            return bufferIDs
        } catch {
            for id in opened { closeUnusedConversation(id) }
            throw error
        }
    }

    /// Closes a private conversation opened for a message that wasn't sent,
    /// unless something new has happened in it meanwhile (only restored
    /// scrollback, if any, is there). You didn't close it, so it isn't in
    /// Recently Closed and can't be undone.
    private func closeUnusedConversation(_ id: BufferID) {
        guard let target = lookup(id), target.buffer.kind == .query,
              target.buffer.lines.allSatisfy(\.isHistory)
        else { return }
        close(target.buffer, reopenable: false)
    }

    /// The channel or conversation you're looking at, if any.
    var selectedConversationID: BufferID? {
        guard let buffer = selectedBuffer, buffer.kind != .server else { return nil }
        return buffer.id
    }
}

/// Text from a `.messages` intent's content and links, as one IRC message.
@available(macOS 27, *)
nonisolated func messageText(content: AttributedString?, links: [URL]) -> String {
    let text = content.map { String($0.characters) } ?? ""
    return ([text] + links.map(\.absoluteString))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

@available(macOS 27, *)
@AppIntent(schema: .messages.sendMessage)
struct SiriSendMessageIntent: AppIntent {
    static let isAssistantOnly = true

    var destination: MessageDestination
    var subject: AttributedString?
    var content: AttributedString?
    @Parameter(supportedContentTypes: [.image]) var attachments: [IntentFile]
    @Parameter(supportedContentTypes: [.audio]) var audioMessage: IntentFile?
    var locations: [PlaceDescriptor]
    var links: [URL]
    var scheduledDate: Date?

    @Dependency private var app: AppModel

    @MainActor
    func perform() async throws -> some ReturnsValue<[MessageEntity]> {
        await app.ready()
        guard attachments.isEmpty, audioMessage == nil, locations.isEmpty else {
            throw IntentFailure("IRC messages can only be text.")
        }
        guard scheduledDate == nil else { throw IntentFailure("Vela can't schedule messages.") }
        let text = messageText(content: content, links: links)
        let bufferIDs: [BufferID]
        do {
            bufferIDs = try await app.sendMessage(text, to: destination.targets)
        } catch {
            throw IntentFailure.wrapping(error)
        }
        var sent: [MessageEntity] = []
        for bufferID in bufferIDs {
            guard let target = app.lookup(bufferID) else { continue }
            let line = target.buffer.lines.last { $0.isSelf && $0.text == text }
                ?? ChatLine(kind: .message, nick: target.session.nick, text: text, isSelf: true)
            sent.append(MessageEntity(line: line, buffer: target.buffer, session: target.session))
        }
        return .result(value: sent)
    }
}

/// Puts the text in the channel's message box and opens it; you send it.
@available(macOS 27, *)
@AppIntent(schema: .messages.draftMessage)
struct SiriDraftMessageIntent: AppIntent {
    static let isAssistantOnly = true
    static let supportedModes: IntentModes = .foreground

    var destination: MessageDestination?
    var subject: AttributedString?
    var content: AttributedString?
    @Parameter(supportedContentTypes: [.image]) var attachments: [IntentFile]
    @Parameter(supportedContentTypes: [.audio]) var audioMessage: IntentFile?
    var locations: [PlaceDescriptor]
    var links: [URL]
    var scheduledDate: Date?

    @Dependency private var app: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        await app.ready()
        guard attachments.isEmpty, audioMessage == nil, locations.isEmpty else {
            throw IntentFailure("IRC messages can only be text.")
        }
        guard scheduledDate == nil else { throw IntentFailure("Vela can't schedule messages.") }
        let bufferID: BufferID
        if let target = destination?.targets.first {
            bufferID = try app.bufferID(for: target)
        } else if let selected = app.selectedConversationID {
            bufferID = selected
        } else {
            throw IntentFailure("Choose a channel to write in.")
        }
        let text = messageText(content: content, links: links)
        app.requestShow(bufferID, draft: text.isEmpty ? nil : text)
        return .result()
    }
}

/// Marks a message, and everything before it in its conversation, read.
/// Anything newer stays unread.
@available(macOS 27, *)
@AppIntent(schema: .messages.setMessageReadStatus)
struct SiriSetMessageReadStatusIntent: AppIntent {
    static let isAssistantOnly = true

    var message: MessageEntity
    var isRead: Bool

    @Dependency private var app: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MessageEntity> {
        await app.ready()
        guard isRead else { throw IntentFailure("Vela can't mark messages as unread.") }
        guard let parsed = MessageEntity.parse(message.id) else { throw IntentFailure(.unknownBuffer) }
        do {
            try app.markRead(upTo: parsed.line, in: parsed.buffer)
        } catch {
            throw IntentFailure.wrapping(error)
        }
        let updated = MessageEntity(id: message.id, in: app) ?? message
        return .result(value: updated)
    }
}
