// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore

/// Settings → Apple Intelligence → Catch me up: the button on the New
/// marker and how many new messages it waits for. Dimmed while Apple
/// Intelligence isn't available (the pane's status callout says why).
struct IntelligenceCatchUpSection: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence

    /// The threshold menu's choices.
    static let thresholds = [10, 25, 50, 100]

    var body: some View {
        @Bindable var settings = app.settings
        let available = intelligence.availability.status.isAvailable
        SettingsSection(
            "Catch me up",
            footer: "A button on the New marker summarizes what you missed. Summaries are made on this Mac and can contain mistakes."
        ) {
            SettingsToggle("Offer Catch me up in busy channels", isOn: $settings[.intelligenceCatchUp])
            SettingsMenuRow(
                title: "Show the button after",
                selection: $settings[.intelligenceCatchUpThreshold],
                options: Self.options(including: settings[.intelligenceCatchUpThreshold])
            )
            .disabled(!settings[.intelligenceCatchUp])
            .opacity(settings[.intelligenceCatchUp] ? 1 : 0.5)
        }
        .disabled(!available)
        .opacity(available ? 1 : 0.55)
    }

    /// 10, 25, 50 and 100 new messages, plus `current` when it's something
    /// else (set in settings.json).
    static func options(including current: Int) -> [(value: Int, label: String)] {
        var values = thresholds
        if !values.contains(current), current > 0 { values.append(current) }
        return values.sorted().map { ($0, $0 == 1 ? "1 new message" : "\($0) new messages") }
    }
}
