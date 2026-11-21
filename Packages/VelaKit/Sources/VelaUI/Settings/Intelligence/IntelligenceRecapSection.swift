// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

/// Settings → Apple Intelligence → Recap: whether it's offered
/// (`intelligence.recap`). Not dimmed while Apple Intelligence is off: a
/// Recap's log doesn't need it.
struct IntelligenceRecapSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        SettingsSection("Recap", footer: Self.footer) {
            SettingsToggle("Offer Recap", detail: Self.detail, isOn: $settings[.intelligenceRecap])
        }
    }

    static let detail = "Go → Recap… (⇧⌘R), the right-click menus, the command palette, the Catch me up card and Siri."

    static let footer = "A report of what was said in a channel, on a network or everywhere, by anyone or one person, since your first unread message or over a span you pick. Summaries are made on this Mac; a log needs no Apple Intelligence. Nothing is saved: a Recap lasts as long as its window."
}
