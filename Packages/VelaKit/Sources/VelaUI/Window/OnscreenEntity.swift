// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import SwiftUI
import VelaCore
import VelaIntents

extension View {
    /// Tells Siri and Apple Intelligence which channel is on screen, so
    /// "summarize this" or "reply to this channel" mean this one: the view
    /// carries the channel's App Intents entity, and so does a user
    /// activity that's current while the window is.
    func onscreenEntity(buffer: BufferModel, session: NetworkSession) -> some View {
        modifier(OnscreenEntityModifier(bufferID: buffer.id, title: buffer.name, network: session.displayName))
    }
}

private struct OnscreenEntityModifier: ViewModifier {
    let bufferID: BufferID
    let title: String
    let network: String

    func body(content: Content) -> some View {
        let identifier = OnscreenEntities.identifier(for: bufferID)
        content
            .appEntityIdentifier(identifier)
            .userActivity(OnscreenEntities.activityType, element: identifier) { identifier, activity in
                activity.title = "\(title) on \(network)"
                activity.isEligibleForHandoff = false
                activity.isEligibleForSearch = false
                activity.isEligibleForPublicIndexing = false
                activity.appEntityIdentifier = identifier
            }
    }
}
