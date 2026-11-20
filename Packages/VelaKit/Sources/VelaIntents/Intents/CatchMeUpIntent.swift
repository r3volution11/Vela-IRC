// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore

/// Summarizes what you missed in a channel with Apple Intelligence, on this
/// Mac. Siri speaks the overview; the snippet lists the topics.
public struct CatchMeUpIntent: AppIntent {
    /// What Siri says instead of catching up, if it can't at all: while
    /// Catch me up is turned off (`intelligence.catchUp`).
    @MainActor
    static func refusal(_ settings: SettingsStore) -> String? {
        settings[.intelligenceCatchUp] ? nil : "Catch me up is turned off in Vela's settings."
    }

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
        if let refusal = Self.refusal(app.settings) { throw IntentFailure(refusal) }
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

        var request = CatchUpRequest(buffer: buffer, session: session)
        // Read since it was caught up on: the stretch summarized this session.
        if request.lines.isEmpty, let latest = services.catchUp.latestRequest(for: buffer.id) { request = latest }
        // At most the newest SiriCatchUp.maximumLines lines, so Siri gets
        // its answer in one pass of the model.
        let catchUp = SiriCatchUp(request)
        let nothingNew = "There's nothing new in \(buffer.name)."
        guard !catchUp.full.lines.isEmpty else {
            return .result(dialog: "\(nothingNew)", view: CatchUpSnippetView(content: .nothingNew(header)))
        }
        do {
            // Through the store: a summary already cached (of the whole
            // stretch, or of Siri's part), or being written for an open
            // card, is shared rather than made again.
            let result = try await catchUp.summarize(with: services.catchUp)
            let dialog = catchUp.dialog(for: result)
            return .result(dialog: "\(dialog)", view: CatchUpSnippetView(content: .summary(header, result.summary)))
        } catch CatchUpError.nothingToSummarize {
            return .result(dialog: "\(nothingNew)", view: CatchUpSnippetView(content: .nothingNew(header)))
        } catch let error as CatchUpError {
            // Including "Apple Intelligence is busy…" when a long catch-up
            // hits the background rate limit.
            throw IntentFailure(error.errorDescription ?? "Apple Intelligence couldn't summarize this conversation.")
        }
    }
}
