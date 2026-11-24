// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaStore

/// The Apple Intelligence services one Vela instance uses, and your own AI
/// models (``models``). Created by the scene layer, put in the SwiftUI
/// environment, and registered with App Intents so Siri and Shortcuts use
/// the same instances.
@Observable
public final class IntelligenceServices {
    public let availability: IntelligenceAvailability
    @ObservationIgnored public let summarizer: any ConversationSummarizer
    /// Catch me up cards and cached summaries, shared by the message list
    /// and the Siri / Shortcuts intent.
    @ObservationIgnored public let catchUp: CatchUpStore
    /// Writes Recaps: the same model as Catch me up, taking turns with it.
    @ObservationIgnored public let recapSummarizer: any RecapSummarizer
    /// Recap windows asked for from outside a window (Siri, Shortcuts).
    public let recaps = RecapRequests()
    /// Your own providers and the model each feature uses (Settings → AI
    /// Providers, and each feature's section in Settings → Intelligence).
    /// Apple's alone in demo mode.
    @ObservationIgnored public let models: AIModels

    public init(
        availability: IntelligenceAvailability,
        summarizer: any ConversationSummarizer,
        recapSummarizer: (any RecapSummarizer)? = nil,
        models: AIModels? = nil
    ) {
        self.availability = availability
        self.summarizer = summarizer
        self.catchUp = CatchUpStore(summarizer: summarizer)
        self.recapSummarizer = recapSummarizer ?? (summarizer as? any RecapSummarizer) ?? CannedSummarizer(stepDelay: .zero)
        self.models = models ?? .appleOnly(availability: availability)
    }

    /// The real models: on this Mac, Private Cloud Compute for long
    /// catch-ups while `settings` allow it (`intelligence.privateCloudCompute`),
    /// in development builds only for now (`PrivateCloudComputeAvailability`),
    /// and your own providers (`intelligence.providers`, keys in the
    /// Keychain) for the features set to use them.
    public static func live(settings: SettingsStore) -> IntelligenceServices {
        let availability = IntelligenceAvailability.live()
        let usesPrivateCloudCompute: () -> Bool = { [weak settings] in
            PrivateCloudComputeAvailability.isBuiltIn && (settings?[.intelligencePrivateCloudCompute] ?? false)
        }
        let models = AIModels(
            settings: settings,
            keys: AIKeyStore(keychain: .shared),
            catalog: AIModelCatalog(cacheURL: modelListCacheURL),
            availability: availability,
            offersPrivateCloudCompute: {
                guard usesPrivateCloudCompute() else { return false }
                if #available(macOS 27.0, *) { return true } else { return false }
            }
        )
        let apple = FoundationModelSummarizer(availability: availability, usesPrivateCloudCompute: usesPrivateCloudCompute)
        return IntelligenceServices(
            availability: availability,
            summarizer: ModelRoutingSummarizer(apple: apple, models: models),
            models: models
        )
    }

    /// Where providers' model lists are kept between launches: the app's
    /// Caches folder (model names and limits only).
    static var modelListCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "Vela", directoryHint: .isDirectory)
            .appending(path: "ai-models.json", directoryHint: .notDirectory)
    }

    /// Whether `feature` can be offered now: Apple Intelligence's status
    /// when it uses Apple's model, available when it uses one of your
    /// providers' (see ``AIModels/status(for:)``).
    public func status(for feature: AIFeature) -> IntelligenceStatus {
        models.status(for: feature)
    }

    /// Canned results, for demo mode and screenshots (works on any Mac).
    public static func demo() -> IntelligenceServices {
        IntelligenceServices(availability: .fixed(.available), summarizer: CannedSummarizer())
    }
}

/// Recap windows to open, asked for where there's no window to open them
/// from: Siri and Shortcuts (``RecapIntent``), or a long catch-up Siri
/// hands over. The scene layer opens each one.
@Observable
public final class RecapRequests {
    /// The latest request. Each is distinct, so asking twice opens twice.
    public private(set) var latest: RecapOpenRequest?

    public init() {}

    public func open(_ scope: RecapScope) {
        latest = RecapOpenRequest(scope: scope)
    }
}

nonisolated public struct RecapOpenRequest: Equatable, Sendable {
    public let id = UUID()
    public let scope: RecapScope
}
