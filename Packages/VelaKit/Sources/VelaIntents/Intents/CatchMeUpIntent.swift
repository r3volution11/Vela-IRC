// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import SwiftUI
import VelaCore
import VelaIntelligence

/// Summarizes what you missed in a channel with Apple Intelligence, on this
/// Mac. Siri speaks the overview; the snippet lists the topics.
public struct CatchMeUpIntent: AppIntent {
    public static let title: LocalizedStringResource = "Catch Me Up"
    public static let description = IntentDescription(
        "Summarizes what you missed in a channel or conversation. Apple Intelligence writes the summary on this Mac.",
        categoryName: "Messages",
        searchKeywords: ["summary", "summarize", "unread", "apple intelligence"]
    )
    public static let supportedModes: IntentModes = .background

    @Parameter(
        title: "Channel",
        description: "Leave empty for the channel with the most unread messages."
    )
    public var channel: ChannelEntity?

    @Dependency private var app: AppModel
    @Dependency private var services: IntelligenceServices

    public static var parameterSummary: some ParameterSummary {
        Summary("Catch me up on \(\.$channel)")
    }

    public init() {}

    public init(channel: ChannelEntity?) {
        self.channel = channel
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        await app.ready()
        let target: (session: NetworkSession, buffer: BufferModel)
        if let channel {
            target = try app.target(for: channel)
        } else if let buffer = app.busiestUnreadBuffer, let session = app.session(for: buffer.id.networkID) {
            target = (session, buffer)
        } else {
            return .result(dialog: "You're all caught up.", view: CatchUpSnippetView(content: .caughtUp))
        }
        let (session, buffer) = target
        let header = CatchUpSnippetView.Header(channel: buffer.name, network: session.displayName)

        services.availability.refresh()
        let status = services.availability.status
        guard status.isAvailable else { throw IntentFailure(status.detail) }

        let request = CatchUpRequest(buffer: buffer, session: session)
        let nothingNew = "There's nothing new in \(buffer.name)."
        guard !request.lines.isEmpty else {
            return .result(dialog: "\(nothingNew)", view: CatchUpSnippetView(content: .nothingNew(header)))
        }
        do {
            // Through the store: a summary already cached, or being written
            // for an open card, is shared rather than made again.
            let summary = try await services.catchUp.summary(for: request)
            let overview = summary.overview.trimmingCharacters(in: .whitespacesAndNewlines)
            let dialog = overview.isEmpty ? "Here's what you missed in \(buffer.name)." : overview
            return .result(dialog: "\(dialog)", view: CatchUpSnippetView(content: .summary(header, summary)))
        } catch CatchUpError.nothingToSummarize {
            return .result(dialog: "\(nothingNew)", view: CatchUpSnippetView(content: .nothingNew(header)))
        } catch let error as CatchUpError {
            // Including "Apple Intelligence is busy…" when a long catch-up
            // hits the background rate limit.
            throw IntentFailure(error.errorDescription ?? "Apple Intelligence couldn't summarize this conversation.")
        }
    }
}
