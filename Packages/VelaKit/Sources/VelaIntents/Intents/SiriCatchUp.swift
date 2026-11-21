// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaIntelligence

/// What "Catch Me Up" does when Siri or Shortcuts asks, and what it says.
///
/// Siri waits while the summary is written, in the background, where
/// Apple Intelligence also limits how much an app may ask of it. So Siri
/// answers itself only when that's quick:
///
/// - a summary of the whole stretch is already made (by the card, say),
///   and is used as it is;
/// - the on-device model reads the stretch in one pass, and it's no longer
///   than ``onDeviceTokenLimit``; or
/// - Private Cloud Compute is on and available (`intelligence.privateCloudCompute`),
///   reads the stretch in one pass, and is expected to take no longer
///   than ``patience``.
///
/// A longer stretch isn't cut short: Siri opens Vela to the channel, where
/// the Catch me up card summarizes all of it (``Outcome/openInVela``). Siri
/// also waits at most ``patience`` for a quick one (it may be waiting its
/// turn behind a card's summary, or Private Cloud Compute may have fallen
/// back to the Mac); a summary still being written then is handed to the
/// card as it is, without starting over.
///
/// Measured with the live model on macOS 27.2 (`CatchUpLiveModelTests`'
/// conversation, an M5 Pro): 100 lines took 11 s in one pass with both the
/// 8,192-token context and a 4,096-token one; 240 lines, one pass with
/// 8,192 tokens, took 20 s. Slower Macs take longer, so the token limit
/// sits near the 100 lines.
struct SiriCatchUp {
    /// The most transcript tokens Siri summarizes on this Mac itself: about
    /// 100 lines of ordinary chat, one pass even with the 4,096-token
    /// context of macOS 26.0–26.3.
    static let onDeviceTokenLimit = 2_600

    /// The longest Siri waits for a summary before handing it to the card.
    static let patience: Duration = .seconds(15)

    /// Everything new in the buffer.
    let request: CatchUpRequest

    init(_ request: CatchUpRequest) {
        self.request = request
    }

    enum Outcome: Equatable {
        /// Siri says it.
        case summary(CatchUpSummary)
        /// Too long for Siri to wait for: open Vela to the channel, with the
        /// card summarizing it. `held` is true when a summary Siri started
        /// is still being written and held for the card (see
        /// ``CatchUpStore/release(_:)``).
        case openInVela(held: Bool)
    }

    /// Whether `plan` is quick enough for Siri to wait for.
    static func answersInSiri(_ plan: CatchUpPlan) -> Bool {
        guard plan.isOnePass else { return false }
        switch plan.venue {
        case .onDevice:
            return plan.transcriptTokens <= onDeviceTokenLimit
        case .privateCloudCompute:
            let seconds = Double(patience.components.seconds)
            return (plan.estimatedSeconds ?? .infinity) <= seconds
        }
    }

    /// The summary from `store` if Siri can wait for it: cached, or quick
    /// enough to write (see the type's notes). Otherwise, or when it isn't
    /// ready within `patience`, Vela should open to the card. Errors are
    /// `CatchUpError`s.
    func summarize(with store: CatchUpStore, patience: Duration = Self.patience) async throws -> Outcome {
        if let cached = store.cachedSummary(for: request) { return .summary(cached) }
        let plan = await store.plan(for: request)
        guard Self.answersInSiri(plan) else { return .openInVela(held: false) }
        guard let summary = try await store.summary(for: request, urgent: true, patience: patience) else {
            return .openInVela(held: true)
        }
        return .summary(summary)
    }

    /// What Siri says: the overview, after a note on what it covers when
    /// the stretch was longer than a summary reads (`CatchUpRequest.maximumLines`).
    func dialog(for summary: CatchUpSummary) -> String {
        let overview = summary.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = request.bufferName
        let available = request.lines.count
        guard summary.messageCount < available, summary.messageCount >= CatchUpRequest.maximumLines else {
            return overview.isEmpty ? "Here's what you missed in \(name)." : overview
        }
        let scope = "the latest \(summary.messageCount) of \(available) messages in \(name)"
        return overview.isEmpty ? "Here's what happened in \(scope)." : "From \(scope): \(overview)"
    }

    /// What Siri says as it opens Vela for a long stretch.
    var openingDialog: String {
        "That's \(Self.messages(request.lines.count)) in \(request.bufferName). Opening Vela to catch you up."
    }

    /// Whether a stretch too long for Siri opens as a Recap rather than on
    /// the card: one longer than a card reads (``CatchUpRequest/maximumLines``),
    /// while Recap is offered. A Recap reads more, and in a window of its own.
    func handsToRecap(recapOffered: Bool) -> Bool {
        recapOffered && request.lines.count > CatchUpRequest.maximumLines
    }

    /// What Siri says as it opens a Recap for a very long stretch.
    var recapOpeningDialog: String {
        "That's \(Self.messages(request.lines.count)) in \(request.bufferName). Opening a Recap in Vela."
    }

    /// What Siri says once the Recap is open.
    var recapOpenedDialog: String {
        "Here's a Recap of \(request.bufferName). Apple Intelligence is writing it now."
    }

    /// What Siri says once Vela is in front with the card.
    var openedDialog: String {
        "Here's \(request.bufferName). Its summary is on the way."
    }

    /// What Siri says when it can't bring Vela forward (a shortcut running
    /// in the background, say): the card is summarizing it anyway.
    var backgroundDialog: String {
        "That's \(Self.messages(request.lines.count)) in \(request.bufferName), too many to summarize here. Vela is summarizing them now; open \(request.bufferName) in Vela to read it."
    }

    /// "1 message", "412 messages".
    static func messages(_ count: Int) -> String {
        count == 1 ? "1 message" : "\(count) messages"
    }
}
