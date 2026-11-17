// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence

/// "Catch Me Up" in a channel's or conversation's context menu, when
/// something in it is unread and Apple Intelligence is ready. Opens the
/// buffer at its New marker with the summary card.
struct CatchUpBufferMenuItems: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    let buffer: BufferModel
    let session: NetworkSession

    var body: some View {
        if CatchUpEligibility.canOffer(
            status: intelligence.availability.status,
            hasUnread: CatchUpActions.hasUnread(buffer, app: app),
            kind: buffer.kind
        ) {
            Button("Catch Me Up") {
                CatchUpActions.open(buffer, session: session, app: app, store: intelligence.catchUp)
            }
        }
    }
}
