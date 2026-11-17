// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Summarizes with Apple's on-device Foundation Models.
///
/// Placeholder until the Catch me up work lands: reports the model's status
/// as unavailable.
public final class FoundationModelSummarizer: ConversationSummarizer {
    private let availability: IntelligenceAvailability

    public init(availability: IntelligenceAvailability) {
        self.availability = availability
    }

    public nonisolated func summarize(_ request: CatchUpRequest) -> AsyncThrowingStream<CatchUpSummary, Error> {
        AsyncThrowingStream { $0.finish(throwing: CatchUpError.failed("Not implemented yet.")) }
    }
}
