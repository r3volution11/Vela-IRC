// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import SwiftUI
import VelaCore

/// Says which channels and conversations mention you, and lists them.
public struct CheckMentionsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Check Mentions"
    public static let description = IntentDescription(
        "Tells you which channels and private conversations have new mentions.",
        categoryName: "Messages",
        searchKeywords: ["highlights", "unread", "notifications"]
    )
    public static let supportedModes: IntentModes = .background

    @Dependency private var app: AppModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView & ReturnsValue<[ChannelEntity]> {
        await app.ready()
        let summary = app.mentionSummary
        let entities = summary.entries.compactMap { ChannelEntity(bufferID: $0.bufferID, in: app) }
        return .result(
            value: entities,
            dialog: "\(MentionsSpeech.dialog(for: summary))",
            view: MentionsSnippetView(entries: summary.entries)
        )
    }
}

/// What "Check Mentions" says.
public enum MentionsSpeech {
    /// "You have no new mentions.", "You have 3 mentions in #vela.",
    /// "You have 2 new messages from marisol.", "You have 5 mentions in
    /// #vela, #swift and marisol."
    public nonisolated static func dialog(for summary: MentionSummary) -> String {
        let entries = summary.entries
        guard let first = entries.first else { return "You have no new mentions." }
        if entries.count == 1 {
            return first.isPrivate
                ? "You have \(IntentText.count(first.mentions, "new message", "new messages")) from \(first.name)."
                : "You have \(IntentText.count(first.mentions, "mention", "mentions")) in \(first.name)."
        }
        let total = IntentText.count(summary.totalMentions, "mention", "mentions")
        if entries.count > 4 {
            return "You have \(total) in \(entries.count) channels and conversations."
        }
        return "You have \(total) in \(IntentText.list(entries.map(\.name)))."
    }
}

/// Marks you away on every connected network, waiting a few seconds for
/// networks still connecting (Siri may have just launched Vela).
public struct SetAwayIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Away"
    public static let description = IntentDescription(
        "Marks you as away on every network you're connected to, like /away.",
        categoryName: "Status"
    )
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Message", description: "What people see when they message you. Leave empty for “Away”.")
    public var message: String?

    @Dependency private var app: AppModel

    public static var parameterSummary: some ParameterSummary {
        Summary("Set away with \(\.$message)")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await app.ready()
        do {
            let sessions = try await app.setAway(message)
            return .result(dialog: "You're away on \(IntentText.list(sessions.map(\.displayName))).")
        } catch {
            throw IntentFailure.wrapping(error)
        }
    }
}

/// Marks you back on every connected network, waiting like Set Away.
public struct SetBackIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Back"
    public static let description = IntentDescription(
        "Marks you as back on every network you're connected to, like /back.",
        categoryName: "Status"
    )
    public static let supportedModes: IntentModes = .background

    @Dependency private var app: AppModel

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await app.ready()
        do {
            let sessions = try await app.setBack()
            return .result(dialog: "You're back on \(IntentText.list(sessions.map(\.displayName))).")
        } catch {
            throw IntentFailure.wrapping(error)
        }
    }
}

/// Connects to a network.
public struct ConnectNetworkIntent: AppIntent {
    public static let title: LocalizedStringResource = "Connect Network"
    public static let description = IntentDescription(
        "Connects to one of your networks.",
        categoryName: "Networks"
    )
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Network", requestValueDialog: "Which network?")
    public var network: NetworkEntity

    @Dependency private var app: AppModel

    public static var parameterSummary: some ParameterSummary {
        Summary("Connect to \(\.$network)")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await app.ready()
        let session = try app.session(for: network)
        if session.isConnected {
            return .result(dialog: "You're already connected to \(session.displayName).")
        }
        session.connect()
        let connected = await app.waitUntil(timeout: .seconds(10)) { session.isConnected }
        return .result(dialog: connected
            ? "Connected to \(session.displayName)."
            : "Connecting to \(session.displayName)…")
    }
}

/// Disconnects from a network.
public struct DisconnectNetworkIntent: AppIntent {
    public static let title: LocalizedStringResource = "Disconnect Network"
    public static let description = IntentDescription(
        "Disconnects from one of your networks.",
        categoryName: "Networks"
    )
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Network", requestValueDialog: "Which network?")
    public var network: NetworkEntity

    @Dependency private var app: AppModel

    public static var parameterSummary: some ParameterSummary {
        Summary("Disconnect from \(\.$network)")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await app.ready()
        let session = try app.session(for: network)
        guard session.connectionState != .disconnected else {
            return .result(dialog: "You're not connected to \(session.displayName).")
        }
        session.disconnect()
        return .result(dialog: "Disconnected from \(session.displayName).")
    }
}
