// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// "Catch me up" on the New marker, when Catch me up is on, Apple
/// Intelligence is ready and at least `intelligence.catchUpThreshold`
/// messages are new. Hidden while the card is open.
struct CatchUpMarkerButton: View {
    @Environment(\.chatStyle) private var style
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(MessageListController.self) private var controller

    var body: some View {
        let buffer = controller.buffer
        let unread = CatchUpEligibility.unreadLineCount(buffer.lines, after: buffer.unreadMarkerAfter)
        let shows = CatchUpEligibility.showsButton(
            isEnabled: app.settings[.intelligenceCatchUp],
            status: intelligence.availability.status,
            unreadLines: unread,
            threshold: app.settings[.intelligenceCatchUpThreshold]
        )
        if shows, intelligence.catchUp.cards[buffer.id] == nil {
            Button {
                CatchUpActions.open(buffer, session: controller.session, app: app, store: intelligence.catchUp)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: max(9, style.fontSize - 3), weight: .semibold))
                    Text("Catch me up")
                }
            }
            .buttonStyle(CatchUpCapsuleButtonStyle())
            .help("Summarize the \(CatchUpActions.messagesLabel(unread)) you missed with Apple Intelligence")
            .accessibilityLabel("Catch me up")
            .accessibilityHint("Summarizes the \(CatchUpActions.messagesLabel(unread)) you missed, on this Mac")
            .onAppear {
                if CatchUpDemo.takeLaunchRequest(isDemo: app.isDemo) {
                    CatchUpActions.open(buffer, session: controller.session, app: app, store: intelligence.catchUp)
                }
            }
        }
    }
}
