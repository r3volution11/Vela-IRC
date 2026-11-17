// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A fixed summary for demo mode, screenshots and tests.
///
/// Placeholder until the Catch me up work lands.
public final class CannedSummarizer: ConversationSummarizer {
    public init() {}

    public nonisolated func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error> {
        let summary = CatchUpSummary(
            overview: "",
            topics: [],
            addressedToYou: [],
            messageCount: request.lines.count,
            isComplete: true
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(summary)
            continuation.finish()
        }
    }
}
