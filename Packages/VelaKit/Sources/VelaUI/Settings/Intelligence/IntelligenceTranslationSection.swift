// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore

/// Settings → Apple Intelligence → Translation.
struct IntelligenceTranslationSection: View {
    var body: some View {
        SettingsSection("Translation") {
            SettingsRow("Translate messages", detail: "Coming soon.") { EmptyView() }
        }
    }
}
