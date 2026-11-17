// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// Settings → Advanced: the settings editor, at the pane's full height
/// (it scrolls its own list under a fixed toolbar).
struct AdvancedPane: View {
    var body: some View {
        SettingsEditorView()
    }

    /// "Keep messages" choices (`history.retentionDays`), shown on the
    /// Messages pane.
    static func retentionLabel(_ days: Int) -> String {
        switch days {
        case ..<1: "Forever"
        case 7: "1 week"
        case 30: "1 month"
        case 90: "3 months"
        case 180: "6 months"
        case 365: "1 year"
        case 730: "2 years"
        default: days == 1 ? "1 day" : "\(days) days"
        }
    }
}
