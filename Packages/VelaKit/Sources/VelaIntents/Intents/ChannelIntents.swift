// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import VelaCore

/// Opens a channel or private conversation in Vela's window (also what
/// Spotlight runs for a channel result).
public struct OpenChannelIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Channel"
    public static let description = IntentDescription(
        "Opens a channel or private conversation in Vela.",
        categoryName: "Channels"
    )
    public static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Channel", requestValueDialog: "Which channel?")
    public var target: ChannelEntity

    @Dependency private var app: AppModel

    public static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    public init() {}

    public init(target: ChannelEntity) {
        self.target = target
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        await app.ready()
        let (_, buffer) = try app.target(for: target)
        app.requestShow(buffer.id)
        return .result()
    }
}

/// Sends a plain message (never a command) to a channel or conversation.
public struct SendMessageIntent: AppIntent {
    public static let title: LocalizedStringResource = "Send Message"
    public static let description = IntentDescription(
        "Sends a message to a channel or private conversation. Text starting with “/” is sent as is, not run as a command.",
        categoryName: "Messages"
    )
    public static let supportedModes: IntentModes = .background

    @Parameter(
        title: "Message",
        inputOptions: String.IntentInputOptions(capitalizationType: .sentences, multiline: false, autocorrect: true),
        requestValueDialog: "What's the message?"
    )
    public var message: String

    @Parameter(title: "Channel", requestValueDialog: "Which channel?")
    public var channel: ChannelEntity

    @Dependency private var app: AppModel

    public static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) to \(\.$channel)")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await app.ready()
        let (session, buffer) = try app.target(for: channel)
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            text = try await $message.requestValue("What's the message?")
        }
        // Siri reads it back before sending; a tap in Shortcuts doesn't ask.
        try await requestConfirmation(
            conditions: .lowConfidenceSource,
            actionName: .send,
            dialog: "Send “\(text)” to \(buffer.name)?"
        )
        do {
            try await app.send(text, to: buffer.id)
        } catch {
            throw IntentFailure.wrapping(error)
        }
        return .result(dialog: "Sent to \(buffer.name) on \(session.displayName).")
    }
}

/// Joins a channel without switching to it.
public struct JoinChannelIntent: AppIntent {
    public static let title: LocalizedStringResource = "Join Channel"
    public static let description = IntentDescription(
        "Joins a channel on one of your networks.",
        categoryName: "Channels"
    )
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Channel", description: "The channel's name, like #vela.", requestValueDialog: "Which channel?")
    public var channel: String

    @Parameter(
        title: "Network",
        description: "Leave empty to use the only network you're connected to, or the one you're looking at.",
        requestValueDialog: "On which network?"
    )
    public var network: NetworkEntity?

    @Parameter(title: "Key", description: "The channel's password, if it has one.")
    public var key: String?

    @Dependency private var app: AppModel

    public static var parameterSummary: some ParameterSummary {
        Summary("Join \(\.$channel) on \(\.$network)") {
            \.$key
        }
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<ChannelEntity> {
        await app.ready()
        let session = try await resolveNetwork()
        let buffer: BufferModel
        do {
            buffer = try await app.join(channel, on: session.id, key: key)
        } catch {
            throw IntentFailure.wrapping(error)
        }
        let joined = await app.waitUntil(timeout: .seconds(8)) { buffer.isJoined }
        let entity = ChannelEntity(buffer: buffer, session: session)
        let dialog: IntentDialog = joined
            ? "Joined \(buffer.name) on \(session.displayName)."
            : "Joining \(buffer.name) on \(session.displayName)…"
        return .result(value: entity, dialog: dialog)
    }

    @MainActor
    private func resolveNetwork() async throws -> NetworkSession {
        if let network { return try app.session(for: network) }
        let connected = app.sessions.filter { $0.isConnected && !$0.isBouncerControl }
        if connected.count == 1 { return connected[0] }
        if let selected = app.selectedSession, selected.isConnected, !selected.isBouncerControl { return selected }
        let chosen = try await $network.requestValue("On which network?")
        return try app.session(for: chosen)
    }
}

/// Clears every unread count and mention.
public struct MarkAllAsReadIntent: AppIntent {
    public static let title: LocalizedStringResource = "Mark All as Read"
    public static let description = IntentDescription(
        "Marks every channel and conversation as read.",
        categoryName: "Channels"
    )
    public static let supportedModes: IntentModes = .background

    @Dependency private var app: AppModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await app.ready()
        let count = app.markAllRead()
        return .result(dialog: count == 0 ? "Everything's already read." : "Marked everything as read.")
    }
}
