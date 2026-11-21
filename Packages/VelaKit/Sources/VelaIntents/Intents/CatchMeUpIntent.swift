// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore

/// Summarizes what you missed in a channel with Apple Intelligence. Siri
/// speaks the overview; the snippet lists the topics. A stretch too long
/// to wait for opens Vela to the channel instead, with the Catch me up
/// card summarizing all of it (see ``SiriCatchUp``), or, when it's longer
/// than a card reads, a Recap of it (``RecapIntent``).
public struct CatchMeUpIntent: AppIntent {
    /// What Siri says instead of catching up, if it can't at all: while
    /// Catch me up is turned off (`intelligence.catchUp`).
    @MainActor
    static func refusal(_ settings: SettingsStore) -> String? {
        settings[.intelligenceCatchUp] ? nil : "Catch me up is turned off in Vela's settings."
    }

    public static let title: LocalizedStringResource = "Catch Me Up"
    // Private Cloud Compute is in development builds only for now
    // (PrivateCloudComputeAvailability), so a release doesn't mention it.
    // The description is App Intents metadata, fixed when Vela is built;
    // scripts/verify-release.sh checks a release's.
    #if DEBUG
    public static let description = IntentDescription(
        "Summarizes what you missed in a channel or conversation with Apple Intelligence, on this Mac. Long stretches use Private Cloud Compute if you turn it on in Vela's settings, or open in Vela.",
        categoryName: "Messages",
        searchKeywords: ["summary", "summarize", "unread", "apple intelligence"]
    )
    #else
    public static let description = IntentDescription(
        "Summarizes what you missed in a channel or conversation with Apple Intelligence, on this Mac. Long stretches open in Vela.",
        categoryName: "Messages",
        searchKeywords: ["summary", "summarize", "unread", "apple intelligence"]
    )
    #endif
    /// In the background, and in front when a long stretch opens Vela to
    /// its card (`continueInForeground`).
    public static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

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

        let store = services.catchUp
        // Where the card goes: under the New marker, as when it's clicked.
        let marker = buffer.unreadMarkerAfter ?? buffer.lastReadAt
        var request = CatchUpRequest(buffer: buffer, session: session, since: marker)
        // Read since it was caught up on: the stretch summarized this session.
        var isEarlierStretch = false
        if request.lines.isEmpty, let latest = store.latestRequest(for: buffer.id) {
            request = latest
            isEarlierStretch = true
        }
        let nothingNew = "There's nothing new in \(buffer.name)."
        guard !request.lines.isEmpty else {
            return .result(dialog: "\(nothingNew)", view: CatchUpSnippetView(content: .nothingNew(header)))
        }
        let catchUp = SiriCatchUp(request)
        do {
            // Through the store: a summary already cached, or being written
            // for an open card, is shared rather than made again.
            switch try await catchUp.summarize(with: store) {
            case .summary(let summary):
                let dialog = catchUp.dialog(for: summary)
                return .result(dialog: "\(dialog)", view: CatchUpSnippetView(content: .summary(header, summary)))
            case .openInVela(let held):
                // A summary Siri started stays with the card, and stops
                // only if Vela doesn't open after all.
                defer { if held { store.release(request) } }
                let dialog = try await openCard(catchUp, marker: marker, isEarlierStretch: isEarlierStretch, in: buffer)
                return .result(
                    dialog: "\(dialog)",
                    view: CatchUpSnippetView(content: .openedInVela(header, messageCount: request.lines.count))
                )
            }
        } catch CatchUpError.nothingToSummarize {
            return .result(dialog: "\(nothingNew)", view: CatchUpSnippetView(content: .nothingNew(header)))
        } catch let error as CatchUpError {
            // Including "Apple Intelligence is busy…" when a long catch-up
            // hits the background rate limit.
            throw IntentFailure(error.errorDescription ?? "Apple Intelligence couldn't summarize this conversation.")
        }
    }

    /// Opens the Catch me up card for a stretch too long for Siri to wait
    /// for. Brings Vela forward to the channel when it can (Siri says
    /// it's opening Vela first); otherwise the card starts summarizing
    /// where it'll be when the channel is next opened. Returns what Siri
    /// says. The card sits under `marker`, the buffer's New marker, or
    /// where it was for the stretch summarized earlier this session.
    @MainActor
    private func openCard(
        _ catchUp: SiriCatchUp,
        marker: Date?,
        isEarlierStretch: Bool,
        in buffer: BufferModel
    ) async throws -> String {
        let store = services.catchUp
        let mode = systemContext.currentMode
        let inFront = mode == .foreground || mode.canContinueInForeground
        // Longer than a card reads: a Recap covers it, in a window of its own.
        let recap = inFront && !isEarlierStretch && catchUp.handsToRecap(recapOffered: app.settings[.intelligenceRecap])
        if mode != .foreground, mode.canContinueInForeground {
            try await continueInForeground("\(recap ? catchUp.recapOpeningDialog : catchUp.openingDialog)", alwaysConfirm: false)
        }
        if recap {
            services.recaps.open(RecapScope(place: .buffer(buffer.id), span: .sinceUnread, output: .summary))
            return catchUp.recapOpenedDialog
        }
        if isEarlierStretch {
            store.reopen(buffer.id, reveal: inFront)
        } else {
            store.open(catchUp.request, marker: marker, reveal: inFront)
        }
        guard inFront else { return catchUp.backgroundDialog }
        app.requestShow(buffer.id)
        return catchUp.openedDialog
    }
}
