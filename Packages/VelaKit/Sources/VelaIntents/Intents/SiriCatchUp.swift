// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaIntelligence

/// What "Catch Me Up" summarizes when Siri or Shortcuts asks, and what it
/// says.
///
/// Siri waits while the summary is written, in the background, where
/// Apple Intelligence also limits how much an app may ask of it. So Siri
/// gets the newest ``maximumLines`` lines at most: a stretch of ordinary
/// chat the on-device model summarizes in one pass, even with the
/// 4,096-token context of macOS 26.0–26.3, rather than the several passes
/// the in-channel card may take for up to `CatchUpRequest.maximumLines`.
/// When older lines are left out, the dialog says so. A summary of the
/// whole stretch that's already made (by the card, say) is used as it is.
///
/// Measured with the live model on macOS 27.2 (`CatchUpLiveModelTests`'
/// conversation, an M5 Pro): 100 lines took 11 s in one pass with both
/// the 8,192-token context and a 4,096-token one; 120 lines needed three
/// passes (21 s) with 4,096 tokens, and 240 lines 20 s with 8,192. Slower
/// Macs take longer, so the cap leaves room.
struct SiriCatchUp {
    /// The newest lines Siri summarizes at most.
    static let maximumLines = 100

    /// Everything new in the buffer.
    let full: CatchUpRequest
    /// What's summarized when nothing is cached: `full`, or its newest lines.
    let request: CatchUpRequest

    init(_ full: CatchUpRequest, maximumLines: Int = Self.maximumLines) {
        self.full = full
        var request = full
        request.lines = Array(full.lines.suffix(max(1, maximumLines)))
        self.request = request
    }

    /// A finished summary and what it covers.
    struct Result: Equatable {
        var summary: CatchUpSummary
        /// Lines the summary covers.
        var summarized: Int
        /// Lines that were new.
        var available: Int

        var isPartial: Bool { summarized < available }
    }

    /// Summarizes through `store`: the whole stretch's cached summary if
    /// there is one, otherwise ``request``. Errors are `CatchUpError`s.
    func summarize(with store: CatchUpStore) async throws -> Result {
        if let cached = store.cachedSummary(for: full) {
            return Result(summary: cached, summarized: full.lines.count, available: full.lines.count)
        }
        let summary = try await store.summary(for: request)
        return Result(summary: summary, summarized: request.lines.count, available: full.lines.count)
    }

    /// What Siri says: the overview, after a note on what it covers when
    /// older lines were left out.
    func dialog(for result: Result) -> String {
        let overview = result.summary.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = full.bufferName
        guard result.isPartial else {
            return overview.isEmpty ? "Here's what you missed in \(name)." : overview
        }
        let scope = "the latest \(result.summarized) of \(result.available) messages in \(name)"
        return overview.isEmpty ? "Here's what happened in \(scope)." : "From \(scope): \(overview)"
    }
}
