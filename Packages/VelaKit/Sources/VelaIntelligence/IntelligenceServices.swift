// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaStore

/// The Apple Intelligence services one Vela instance uses. Created by the
/// scene layer, put in the SwiftUI environment, and registered with App
/// Intents so Siri and Shortcuts use the same instances.
@Observable
public final class IntelligenceServices {
    public let availability: IntelligenceAvailability
    @ObservationIgnored public let summarizer: any ConversationSummarizer
    /// Catch me up cards and cached summaries, shared by the message list
    /// and the Siri / Shortcuts intent.
    @ObservationIgnored public let catchUp: CatchUpStore

    public init(availability: IntelligenceAvailability, summarizer: any ConversationSummarizer) {
        self.availability = availability
        self.summarizer = summarizer
        self.catchUp = CatchUpStore(summarizer: summarizer)
    }

    /// The real models: on this Mac, and Private Cloud Compute for long
    /// catch-ups while `settings` allow it (`intelligence.privateCloudCompute`).
    public static func live(settings: SettingsStore) -> IntelligenceServices {
        let availability = IntelligenceAvailability.live()
        return IntelligenceServices(
            availability: availability,
            summarizer: FoundationModelSummarizer(availability: availability) { [weak settings] in
                settings?[.intelligencePrivateCloudCompute] ?? false
            }
        )
    }

    /// Canned results, for demo mode and screenshots (works on any Mac).
    public static func demo() -> IntelligenceServices {
        IntelligenceServices(availability: .fixed(.available), summarizer: CannedSummarizer())
    }
}
