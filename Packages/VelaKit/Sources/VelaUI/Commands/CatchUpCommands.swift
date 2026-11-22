// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore

extension VelaCommandCatalog {
    /// Catch me up (Apple Intelligence summaries) for the selected buffer:
    /// "Buffer: Catch Me Up", while Catch me up is on and Apple
    /// Intelligence is ready.
    var catchUpCommands: [VelaCommand] {
        guard let intelligence = context.intelligence else { return [] }
        return Self.catchUpCommands(app: context.app, intelligence: intelligence)
    }

    /// See ``catchUpCommands``. With nothing new it's still listed, noting
    /// what it will do: show the latest summary again, or say there's
    /// nothing new.
    static func catchUpCommands(app: AppModel, intelligence: IntelligenceServices) -> [VelaCommand] {
        guard let buffer = app.selectedBuffer, let session = app.selectedSession,
              CatchUpEligibility.canOffer(
                  isEnabled: app.settings[.intelligenceCatchUp],
                  status: intelligence.status(for: .catchUp),
                  kind: buffer.kind
              )
        else { return [] }
        let store = intelligence.catchUp
        return [
            VelaCommand(
                id: "buffer.catchUp", category: .buffer, title: "Catch Me Up",
                keywords: ["summary", "summarize", "apple intelligence", "unread", "missed", "new messages", "tldr"],
                detail: CatchUpEligibility.paletteDetail(
                    hasUnread: CatchUpActions.hasUnread(buffer, app: app),
                    hasEarlierSummary: store.hasEarlierSummary(for: buffer.id)
                )
            ) {
                CatchUpActions.open(buffer, session: session, app: app, store: store)
            },
        ]
    }
}
