// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore

/// Settings → Apple Intelligence → Catch me up: the button on the New
/// marker, how many new messages it waits for and, on macOS 27 or later,
/// Private Cloud Compute for long catch-ups. Dimmed while Apple
/// Intelligence isn't available (the pane's status callout says why).
struct IntelligenceCatchUpSection: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence

    /// The threshold menu's choices.
    static let thresholds = [10, 25, 50, 100]

    var body: some View {
        @Bindable var settings = app.settings
        let available = intelligence.availability.status.isAvailable
        let usesCloud = Self.offersPrivateCloudCompute && settings[.intelligencePrivateCloudCompute]
        SettingsSection(
            "Catch me up",
            footer: Self.footer(showsNewLine: settings[.chatShowUnreadMarker], privateCloudCompute: usesCloud)
        ) {
            SettingsToggle("Offer Catch me up in busy channels", isOn: $settings[.intelligenceCatchUp])
            SettingsMenuRow(
                title: "Show the button after",
                selection: $settings[.intelligenceCatchUpThreshold],
                options: Self.options(including: settings[.intelligenceCatchUpThreshold])
            )
            .disabled(!settings[.intelligenceCatchUp])
            .opacity(settings[.intelligenceCatchUp] ? 1 : 0.5)
            if Self.offersPrivateCloudCompute {
                SettingsToggle(
                    "Use Private Cloud Compute for long catch-ups",
                    detail: Self.privateCloudComputeDetail,
                    isOn: $settings[.intelligencePrivateCloudCompute]
                )
                .disabled(!settings[.intelligenceCatchUp])
                .opacity(settings[.intelligenceCatchUp] ? 1 : 0.5)
            }
        }
        .disabled(!available)
        .opacity(available ? 1 : 0.55)
    }

    /// Private Cloud Compute is offered on macOS 27 or later, where
    /// Foundation Models has it.
    static var offersPrivateCloudCompute: Bool {
        if #available(macOS 27.0, *) { true } else { false }
    }

    /// What turning on `intelligence.privateCloudCompute` means, plainly.
    static let privateCloudComputeDetail = "Long catch-ups are sent to Apple's Private Cloud Compute, encrypted. They aren't stored, and Apple can't read them. Short catch-ups, translation and everything else stay on this Mac."

    /// The button lives on the New line; with the line turned off
    /// (`chat.showUnreadMarker`), say where Catch me up is instead. Where
    /// summaries are made follows `privateCloudCompute`.
    static func footer(showsNewLine: Bool, privateCloudCompute: Bool = false) -> String {
        let privacy = privateCloudCompute
            ? "Summaries are made on this Mac, long ones with Private Cloud Compute, and can contain mistakes."
            : "Summaries are made on this Mac and can contain mistakes."
        guard showsNewLine else {
            return "The New line is off in Settings → Messages, so the button doesn't show. Right-click a channel or use the command palette to catch up. \(privacy)"
        }
        return "A button on the New line summarizes what you missed. \(privacy)"
    }

    /// 10, 25, 50 and 100 new messages, plus `current` when it's something
    /// else (set in settings.json).
    static func options(including current: Int) -> [(value: Int, label: String)] {
        var values = thresholds
        if !values.contains(current), current > 0 { values.append(current) }
        return values.sorted().map { ($0, $0 == 1 ? "1 new message" : "\($0) new messages") }
    }
}
