// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import VelaCore

/// "Search Vela for…": opens Vela's message search with your words. Its
/// system kind (show in-app search results) is what Spotlight offers as
/// "Search in Vela" when you type there.
public struct SearchMessagesIntent: ShowInAppSearchResultsIntent {
    public static let title: LocalizedStringResource = "Search Messages"
    public static let description = IntentDescription(
        "Opens message search in Vela with your words: your saved messages, and those Vela has open.",
        categoryName: "Messages",
        searchKeywords: ["search", "find", "look up", "messages", "history", "grep"]
    )
    public static let searchScopes: [StringSearchScope] = [.general]
    public static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Search For", requestValueDialog: "What do you want to find?")
    public var criteria: StringSearchCriteria

    @Dependency private var app: AppModel

    public static var parameterSummary: some ParameterSummary {
        Summary("Search Vela for \(\.$criteria)")
    }

    public init() {}

    public init(term: String) {
        self.criteria = StringSearchCriteria(term: term)
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        await app.ready()
        guard let query = VelaLink.cleanQuery(criteria.term) else {
            throw IntentFailure("What do you want to find?")
        }
        guard let automation = VelaAutomation.shared else { throw IntentFailure("Vela isn't ready yet.") }
        automation.search(query)
        return .result()
    }
}

/// Opens a private conversation with someone (also what Spotlight runs for
/// a person): shows it, reopens it if you closed it, or starts it.
public struct OpenPersonIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Private Conversation"
    public static let description = IntentDescription(
        "Opens your private conversation with someone in Vela, reopening it if you closed it.",
        categoryName: "Channels",
        searchKeywords: ["message", "DM", "direct message", "private message", "query", "chat with", "person"]
    )
    public static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Person", requestValueDialog: "Who?")
    public var target: PersonEntity

    @Dependency private var app: AppModel

    public static var parameterSummary: some ParameterSummary {
        Summary("Open conversation with \(\.$target)")
    }

    public init() {}

    public init(target: PersonEntity) {
        self.target = target
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        await app.ready()
        try target.open(in: app)
        return .result()
    }
}
