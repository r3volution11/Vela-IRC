// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

/// Settings → Apple Intelligence → Siri & Shortcuts.
struct IntelligenceSiriSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        SettingsSection("Siri & Shortcuts") {
            SettingsToggle(
                "Show channels in Spotlight",
                detail: "Channel and conversation names only, never messages.",
                isOn: $settings[.intelligenceSpotlightChannels]
            )
        }
    }
}
