// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import FoundationModels
import Observation

/// Whether Apple Intelligence's on-device model can run on this Mac, and if
/// not, why (in words a person can act on).
nonisolated public enum IntelligenceStatus: Equatable, Sendable {
    case available
    /// Turned off in System Settings → Apple Intelligence & Siri.
    case turnedOff
    /// This Mac can't run Apple Intelligence (it needs Apple silicon).
    case deviceNotEligible
    /// Turned on, but the model is still downloading or getting ready.
    case modelNotReady
    /// The Mac's language isn't one Apple Intelligence supports yet.
    case unsupportedLanguage
    /// Anything else the system reports.
    case unavailable(String)

    public var isAvailable: Bool { self == .available }

    /// A short title, e.g. for a settings row.
    public var title: String {
        switch self {
        case .available: "Apple Intelligence is on"
        case .turnedOff: "Apple Intelligence is off"
        case .deviceNotEligible: "Not available on this Mac"
        case .modelNotReady: "Apple Intelligence is getting ready"
        case .unsupportedLanguage: "Language not supported yet"
        case .unavailable: "Apple Intelligence isn't available"
        }
    }

    /// One sentence on what it means and what to do.
    public var detail: String {
        switch self {
        case .available:
            "Summaries run on this Mac. Nothing you read or write is sent anywhere."
        case .turnedOff:
            "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri to use Catch me up and Writing Tools."
        case .deviceNotEligible:
            "Apple Intelligence needs a Mac with Apple silicon. Translation still works."
        case .modelNotReady:
            "macOS is still downloading the Apple Intelligence model. Try again in a little while."
        case .unsupportedLanguage:
            "Apple Intelligence doesn't support your Mac's language yet."
        case .unavailable(let reason):
            reason
        }
    }

    /// Where to fix it, if System Settings can.
    public var settingsURL: URL? {
        switch self {
        case .turnedOff, .unsupportedLanguage:
            URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")
        default:
            nil
        }
    }
}

/// Tracks ``IntelligenceStatus``. The live instance re-checks whenever Vela
/// becomes active, so turning Apple Intelligence on in System Settings
/// shows up without a relaunch.
@Observable
public final class IntelligenceAvailability {
    public private(set) var status: IntelligenceStatus

    @ObservationIgnored private let probe: () -> IntelligenceStatus
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// - Parameter probe: Returns the current status; called on refresh.
    public init(probe: @escaping () -> IntelligenceStatus) {
        self.probe = probe
        self.status = probe()
    }

    /// A fixed status, for demo mode and tests.
    public static func fixed(_ status: IntelligenceStatus) -> IntelligenceAvailability {
        IntelligenceAvailability { status }
    }

    /// The real status from `SystemLanguageModel.default`.
    public static func live() -> IntelligenceAvailability {
        let availability = IntelligenceAvailability(probe: systemStatus)
        availability.observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak availability] _ in
            MainActor.assumeIsolated { availability?.refresh() }
        }
        return availability
    }

    public func refresh() {
        let current = probe()
        if current != status { status = current }
    }

    private static func systemStatus() -> IntelligenceStatus {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale.current) ? .available : .unsupportedLanguage
        case .unavailable(.appleIntelligenceNotEnabled):
            return .turnedOff
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(let reason):
            return .unavailable(String(describing: reason))
        }
    }
}
