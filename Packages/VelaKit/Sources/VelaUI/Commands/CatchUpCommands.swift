// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore

extension VelaCommandCatalog {
    /// Catch me up (Apple Intelligence summaries) for the selected buffer:
    /// "Buffer: Catch Me Up", while something is new and Apple
    /// Intelligence is ready.
    var catchUpCommands: [VelaCommand] {
        let app = context.app
        guard let intelligence = context.intelligence,
              let buffer = app.selectedBuffer, let session = app.selectedSession
        else { return [] }
        let offered = CatchUpEligibility.canOffer(
            status: intelligence.availability.status,
            hasUnread: CatchUpActions.hasUnread(buffer, app: app),
            kind: buffer.kind
        )
        return [
            VelaCommand(
                id: "buffer.catchUp", category: .buffer, title: "Catch Me Up",
                keywords: ["summary", "summarize", "apple intelligence", "unread", "missed", "new messages", "tldr"],
                isEnabled: offered
            ) {
                CatchUpActions.open(buffer, session: session, app: app, store: intelligence.catchUp)
            },
        ]
    }
}
