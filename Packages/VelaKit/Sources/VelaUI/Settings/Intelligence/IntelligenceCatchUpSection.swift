// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

/// Settings → Apple Intelligence → Catch me up.
struct IntelligenceCatchUpSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        SettingsSection("Catch me up") {
            SettingsToggle("Offer Catch me up in busy channels", isOn: $settings[.intelligenceCatchUp])
        }
    }
}
