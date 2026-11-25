// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import VelaCore
import VelaIntelligence
import VelaStore

/// How far back a Recap from Siri or Shortcuts goes: the window's quick
/// picks.
public enum RecapSpanOption: String, AppEnum, Sendable {
    case sinceUnread, lastHalfHour, lastHour, lastFourHours, today, lastDay, lastThreeDays, lastWeek

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Time Span")
    public static let caseDisplayRepresentations: [RecapSpanOption: DisplayRepresentation] = [
        .sinceUnread: "Since my first unread message",
        .lastHalfHour: "The last 30 minutes",
        .lastHour: "The last hour",
        .lastFourHours: "The last 4 hours",
        .today: "Today",
        .lastDay: "The last day",
        .lastThreeDays: "The last 3 days",
        .lastWeek: "The last week",
    ]

    var span: RecapScope.Span {
        switch self {
        case .sinceUnread: .sinceUnread
        case .lastHalfHour: .last(minutes: 30)
        case .lastHour: .last(minutes: 60)
        case .lastFourHours: .last(minutes: 240)
        case .today: .today
        case .lastDay: .last(minutes: 1_440)
        case .lastThreeDays: .last(minutes: 4_320)
        case .lastWeek: .last(minutes: 10_080)
        }
    }
}

/// Opens a Recap in Vela: a report of a channel, a network or everything,
/// for anyone or one person, over a span. Vela opens to it; the summary is
/// written there, by Apple Intelligence on this Mac or the model you chose,
/// or the log shows when that model can't run. Nothing is said aloud from
/// the messages.
public struct RecapIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Recap"
    public static let description = IntentDescription(
        "Opens a Recap in Vela: a report of what was said in a channel, on a network or everywhere, by anyone or one person, since your first unread message or over a time span. Apple Intelligence writes it on this Mac, or the model you chose in Vela's settings; otherwise Vela shows the messages as a log.",
        categoryName: "Messages",
        searchKeywords: ["recap", "summary", "summarize", "report", "log", "history", "apple intelligence"]
    )
    public static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Channel", description: "A channel or private conversation. Leave empty for every channel.")
    public var channel: ChannelEntity?

    @Parameter(title: "Person", description: "A nick: their messages, messages that name them, and your private conversation with them.")
    public var person: String?

    @Parameter(title: "Network", description: "Every channel on one network.")
    public var network: NetworkEntity?

    @Parameter(title: "Time Span", default: .sinceUnread)
    public var span: RecapSpanOption

    @Dependency private var app: AppModel
    @Dependency private var services: IntelligenceServices

    public static var parameterSummary: some ParameterSummary {
        Summary("Recap \(\.$channel) \(\.$span)") {
            \.$person
            \.$network
        }
    }

    public init() {}

    public init(channel: ChannelEntity? = nil, person: String? = nil, network: NetworkEntity? = nil, span: RecapSpanOption = .sinceUnread) {
        self.channel = channel
        self.person = person
        self.network = network
        self.span = span
    }

    /// What Siri says instead, while Recap is turned off (`intelligence.recap`).
    @MainActor
    static func refusal(_ settings: SettingsStore) -> String? {
        settings[.intelligenceRecap] ? nil : "Recap is turned off in Vela's settings."
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await app.ready()
        if let refusal = Self.refusal(app.settings) { throw IntentFailure(refusal) }
        let scope = try Self.scope(channel: channel, person: person, network: network, span: span, app: app, services: services)
        services.recaps.open(scope)
        return .result(dialog: "\(Self.dialog(for: scope, app: app))")
    }

    /// The Recap asked for: the channel, else the network, else every
    /// network. A person's Recap of a channel covers its network too, so it
    /// includes your private conversation with them.
    @MainActor
    static func scope(
        channel: ChannelEntity?,
        person: String?,
        network: NetworkEntity?,
        span: RecapSpanOption,
        app: AppModel,
        services: IntelligenceServices
    ) throws -> RecapScope {
        // The same Recap as a vela://recap link or AppleScript's open recap.
        let conversation = try channel.map { try app.target(for: $0).buffer.id }
        let networkID = try network.map { try app.session(for: $0).id }
        return VelaAutomation.recapScope(conversation: conversation, network: networkID, person: person, span: span, services: services)
    }

    /// "Opening a Recap of #vela in Vela."
    @MainActor
    static func dialog(for scope: RecapScope, app: AppModel) -> String {
        let name: String
        if let person = scope.person {
            name = person
        } else {
            switch scope.place {
            case .buffer(let id): name = app.lookup(id)?.buffer.name ?? "the channel"
            case .network(let id): name = app.session(for: id)?.displayName ?? "the network"
            case .everywhere: name = "all your networks"
            }
        }
        return "Opening a Recap of \(name) in Vela."
    }
}
