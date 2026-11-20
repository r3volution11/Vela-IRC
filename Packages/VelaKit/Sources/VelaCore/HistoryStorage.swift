// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// What a session does with message history in the database
/// (`history.save`). Buffer state (channels, read positions, mute, order,
/// auto-rejoin) is saved in every mode.
nonisolated public enum HistoryStorage: Sendable, Equatable {
    /// Messages, reactions and redactions are saved, and history loads
    /// from disk. `history.save` on.
    case saveAndLoad
    /// Nothing new is saved, but history saved before still loads: saving
    /// was turned off with "Keep What's Saved".
    case loadOnly
    /// Nothing is saved or loaded: messages live in memory while Vela runs.
    case memoryOnly

    /// For `history.save` and whether the database holds saved messages.
    public init(saves: Bool, hasSavedMessages: Bool) {
        self = saves ? .saveAndLoad : (hasSavedMessages ? .loadOnly : .memoryOnly)
    }

    /// New messages and reactions are written to disk.
    public var saves: Bool { self == .saveAndLoad }

    /// History is read from disk: at launch, when scrolling up, and for
    /// reactions and redactions of saved messages.
    public var loads: Bool { self != .memoryOnly }
}

extension SessionHost {
    public var historyStorage: HistoryStorage { .saveAndLoad }
}
