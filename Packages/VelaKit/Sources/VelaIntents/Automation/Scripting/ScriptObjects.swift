// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import VelaCore

// The objects of Vela's AppleScript dictionary (Vela/Vela.sdef): networks
// and conversations. Each holds only an id and reads the live model when a
// script asks for a property, on the main thread, where Cocoa scripting
// runs. They're cheap to make: a script's `every conversation` makes one
// per buffer, nothing more.
//
// Their Objective-C names and keys are what the sdef names (cocoa class,
// cocoa key), so they never change; ScriptingDictionaryTests checks the two
// match.

/// Four-character codes of the dictionary's enumerations, as Cocoa
/// scripting passes them (an `NSNumber` of the code).
nonisolated enum ScriptCode {
    static func of(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    // conversation kind
    static let channel = of("VKch")
    static let privateConversation = of("VKpv")

    // recap span
    static let spans: [FourCharCode: RecapSpanOption] = [
        of("VSun"): .sinceUnread,
        of("VS30"): .lastHalfHour,
        of("VS1h"): .lastHour,
        of("VS4h"): .lastFourHours,
        of("VStd"): .today,
        of("VS1d"): .lastDay,
        of("VS3d"): .lastThreeDays,
        of("VS1w"): .lastWeek,
    ]
}

/// The application's script object, for specifiers that start from it.
nonisolated private var applicationDescription: NSScriptClassDescription? {
    NSScriptClassDescription(for: NSApplication.self)
}

// MARK: - Network

/// `network`: one of your networks.
@objc(VelaScriptNetwork)
nonisolated public final class ScriptNetwork: NSObject, @unchecked Sendable {
    public let networkID: UUID

    public init(networkID: UUID) {
        self.networkID = networkID
    }

    private func read<T: Sendable>(_ fallback: T, _ body: @MainActor (NetworkSession) -> T) -> T {
        MainActor.assumeIsolated {
            guard let session = VelaAutomation.shared?.app.session(for: networkID) else { return fallback }
            return body(session)
        }
    }

    /// `id`: the network's UUID. Never changes.
    @objc public var uniqueID: String { networkID.uuidString }

    /// `name`: as Vela shows it ("Libera.Chat").
    @objc public var name: String { read("") { $0.displayName } }

    /// `connected`
    @objc public var connected: Bool { read(false) { $0.isConnected } }

    /// `nickname`: your nick there.
    @objc public var nickname: String { read("") { $0.nick } }

    /// `conversations`: its channels and private conversations.
    @objc public var velaConversations: [ScriptConversation] {
        read([]) { session in
            session.buffers.filter { $0.kind != .server }.map { ScriptConversation(bufferID: $0.id) }
        }
    }

    @objc(valueInVelaConversationsWithUniqueID:)
    public func valueInVelaConversations(withUniqueID id: String) -> ScriptConversation? {
        guard let bufferID = BufferID(string: id), bufferID.networkID == networkID else { return nil }
        return read(nil) { session in
            guard let buffer = session.buffer(id: bufferID), buffer.kind != .server else { return nil }
            return ScriptConversation(bufferID: buffer.id)
        }
    }

    @objc(valueInVelaConversationsWithName:)
    public func valueInVelaConversations(withName name: String) -> ScriptConversation? {
        read(nil) { session in
            ScriptLookup.conversation(named: name, in: session).map { ScriptConversation(bufferID: $0.id) }
        }
    }

    /// `open recap network …`: Cocoa scripting hands commands on a network
    /// to the network (the sdef's responds-to).
    @objc(handleVelaScriptCommand:)
    public func handleVelaScriptCommand(_ command: NSScriptCommand) -> Any? {
        (command as? VelaScriptCommand)?.perform(direct: self)
    }

    public override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let application = applicationDescription else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: application, containerSpecifier: nil, key: "velaNetworks", uniqueID: uniqueID)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        (object as? ScriptNetwork)?.networkID == networkID
    }

    public override var hash: Int { networkID.hashValue }
}

// MARK: - Conversation

/// `conversation`: a channel or private conversation.
@objc(VelaScriptConversation)
nonisolated public final class ScriptConversation: NSObject, @unchecked Sendable {
    public let bufferID: BufferID

    public init(bufferID: BufferID) {
        self.bufferID = bufferID
    }

    private func read<T: Sendable>(_ fallback: T, _ body: @MainActor (NetworkSession, BufferModel) -> T) -> T {
        MainActor.assumeIsolated {
            guard let target = VelaAutomation.shared?.app.lookup(bufferID) else { return fallback }
            return body(target.session, target.buffer)
        }
    }

    /// `id`: "<network-uuid>/<folded-name>", the same id Shortcuts and
    /// `vela://open?id=` use. Never changes.
    @objc public var uniqueID: String { bufferID.description }

    /// `name`: "#vela", or a nick.
    @objc public var name: String { read(bufferID.foldedName) { _, buffer in buffer.name } }

    /// `network name`
    @objc public var networkName: String { read("") { session, _ in session.displayName } }

    /// `network`
    @objc public var network: ScriptNetwork { ScriptNetwork(networkID: bufferID.networkID) }

    /// `kind`: channel or private conversation.
    @objc public var scriptingKind: NSNumber {
        NSNumber(value: read(ScriptCode.channel) { _, buffer in
            buffer.kind == .query ? ScriptCode.privateConversation : ScriptCode.channel
        })
    }

    /// `unread count`: as Siri counts it, from where you last read as well
    /// as what arrived since Vela started.
    @objc public var unreadCount: Int {
        read(0) { _, buffer in VelaAutomation.shared?.unread(buffer).unread ?? buffer.unreadCount }
    }

    /// `mention count`: highlights, and every new message of a private conversation.
    @objc public var mentionCount: Int {
        read(0) { _, buffer in VelaAutomation.shared?.unread(buffer).mentions ?? buffer.highlightCount }
    }

    /// `joined`: you're in the channel. Private conversations always are.
    @objc public var joined: Bool { read(false) { _, buffer in buffer.kind == .query || buffer.isJoined } }

    /// `muted`
    @objc public var muted: Bool { read(false) { _, buffer in buffer.isMuted } }

    /// `topic`: the channel's topic; empty for a private conversation.
    @objc public var topic: String { read("") { _, buffer in buffer.topic ?? "" } }

    /// `show`, `catch up`, `open recap` and `mark read` of a conversation:
    /// Cocoa scripting hands commands on a conversation to the conversation
    /// (the sdef's responds-to), once for each one named.
    @objc(handleVelaScriptCommand:)
    public func handleVelaScriptCommand(_ command: NSScriptCommand) -> Any? {
        (command as? VelaScriptCommand)?.perform(direct: self)
    }

    public override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let application = applicationDescription else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: application, containerSpecifier: nil, key: "velaConversations", uniqueID: uniqueID)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        (object as? ScriptConversation)?.bufferID == bufferID
    }

    public override var hash: Int { bufferID.hashValue }
}

// MARK: - Lookups

/// Finding conversations by name for specifiers (`conversation "#vela"`).
@MainActor
enum ScriptLookup {
    /// `name` on `session`, compared as the network compares names, with
    /// "#" assumed for a channel name written without one.
    static func conversation(named name: String, in session: NetworkSession) -> BufferModel? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        for candidate in [trimmed, VelaAutomation.channelName(trimmed, in: session)] {
            if let buffer = session.buffer(named: candidate), buffer.kind != .server { return buffer }
        }
        return nil
    }

    /// `name` on any network, the one you're looking at first.
    static func conversation(named name: String, in app: AppModel) -> BufferModel? {
        var sessions = app.automationSessions
        if let selected = app.selectedSession, let index = sessions.firstIndex(where: { $0 === selected }) {
            sessions.insert(sessions.remove(at: index), at: 0)
        }
        for session in sessions {
            if let buffer = conversation(named: name, in: session) { return buffer }
        }
        return nil
    }
}

// MARK: - Application

/// The application's elements and properties in Vela's dictionary, as
/// keys Cocoa scripting reads from `NSApp`.
extension NSApplication {
    private var automation: VelaAutomation? { VelaAutomation.shared }

    /// `networks`, in sidebar order.
    @objc public var velaNetworks: [ScriptNetwork] {
        (automation?.app.automationSessions ?? []).map { ScriptNetwork(networkID: $0.id) }
    }

    @objc(valueInVelaNetworksWithUniqueID:)
    public func valueInVelaNetworks(withUniqueID id: String) -> ScriptNetwork? {
        guard let networkID = UUID(uuidString: id), automation?.app.automationSessions.contains(where: { $0.id == networkID }) == true else { return nil }
        return ScriptNetwork(networkID: networkID)
    }

    @objc(valueInVelaNetworksWithName:)
    public func valueInVelaNetworks(withName name: String) -> ScriptNetwork? {
        guard let session = try? automation?.network(name) else { return nil }
        return ScriptNetwork(networkID: session.id)
    }

    /// `conversations`: every channel and private conversation, in sidebar order.
    @objc public var velaConversations: [ScriptConversation] {
        (automation?.app.conversationBuffers ?? []).map { ScriptConversation(bufferID: $0.id) }
    }

    @objc(valueInVelaConversationsWithUniqueID:)
    public func valueInVelaConversations(withUniqueID id: String) -> ScriptConversation? {
        guard let bufferID = BufferID(string: id), let target = automation?.app.lookup(bufferID), target.buffer.kind != .server,
              automation?.app.automationSessions.contains(where: { $0 === target.session }) == true
        else { return nil }
        return ScriptConversation(bufferID: target.buffer.id)
    }

    @objc(valueInVelaConversationsWithName:)
    public func valueInVelaConversations(withName name: String) -> ScriptConversation? {
        guard let app = automation?.app else { return nil }
        return ScriptLookup.conversation(named: name, in: app).map { ScriptConversation(bufferID: $0.id) }
    }

    /// `unread conversations`: those with something unread (muted ones only
    /// with mentions), in sidebar order.
    @objc public var velaUnreadConversations: [ScriptConversation] {
        (automation?.unreadConversations ?? []).map { ScriptConversation(bufferID: $0.id) }
    }

    /// `current conversation`: the channel or private conversation you're
    /// looking at, if any.
    @objc public var velaCurrentConversation: ScriptConversation? {
        guard let buffer = automation?.app.selectedBuffer, buffer.kind != .server else { return nil }
        return ScriptConversation(bufferID: buffer.id)
    }

    /// `scripting version`: the dictionary's version
    /// (``VelaAutomation/scriptingVersion``). It needs no automation, so it
    /// answers while Vela is still starting.
    @objc public var velaScriptingVersion: Int { VelaAutomation.scriptingVersion }
}
