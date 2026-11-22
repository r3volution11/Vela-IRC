// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore

/// Settings → Intelligence → Recap: whether it's offered
/// (`intelligence.recap`), and its model where there's a choice. Not
/// dimmed while Apple Intelligence is off: a Recap's log doesn't need it.
struct IntelligenceRecapSection: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence

    var body: some View {
        @Bindable var settings = app.settings
        SettingsSection("Recap", footer: Self.footer) {
            SettingsToggle("Offer Recap", detail: Self.detail, isOn: $settings[.intelligenceRecap])
            if intelligence.models.hasChoices || settings.isSet(.intelligenceRecapModel) {
                AIModelSettingRow(
                    title: "Model",
                    detail: "Which model writes a Recap's summary. The window's Change Model menu tries another.",
                    key: .intelligenceRecapModel,
                    followsDefault: true
                )
                .disabled(!settings[.intelligenceRecap])
                .opacity(settings[.intelligenceRecap] ? 1 : 0.5)
            }
        }
    }

    static let detail = "Go → Recap… (⇧⌘R), the right-click menus, the command palette, the Catch me up card and Siri."

    static let footer = "A report of what was said in a channel, on a network or everywhere, by anyone or one person, since your first unread message or over a span you pick. Summaries are made on this Mac, or by the model you chose; a log needs no model. Nothing is saved: a Recap lasts as long as its window."
}
