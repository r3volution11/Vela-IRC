// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore

/// "Catch Me Up" in a channel's or conversation's context menu, while Catch
/// me up is on and Apple Intelligence is ready. Opens the buffer at its New
/// marker with the summary card; with nothing new, the card shows the
/// latest summary again or says there's nothing new.
struct CatchUpBufferMenuItems: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    let buffer: BufferModel
    let session: NetworkSession

    var body: some View {
        if CatchUpEligibility.canOffer(
            isEnabled: app.settings[.intelligenceCatchUp],
            status: intelligence.status(for: .catchUp),
            kind: buffer.kind
        ) {
            Button("Catch Me Up") {
                CatchUpActions.open(buffer, session: session, app: app, store: intelligence.catchUp)
            }
        }
    }
}
