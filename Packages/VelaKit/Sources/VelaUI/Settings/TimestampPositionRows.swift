// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Settings → Messages → Timestamps: where times go in the current layout,
/// and a disclosure with the other two layouts, since each layout keeps
/// its own position (`chat.timestampPosition.*`).
struct TimestampPositionRows: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var showsOtherLayouts = false

    var body: some View {
        let current = app.settings[.chatLayout]
        let others = ChatLayout.allCases.filter { $0 != current }
        SettingsSegmentedRow(
            title: "Position",
            detail: Self.detail(for: current),
            selection: binding(for: current),
            options: Self.options
        )
        // The summary goes while the rows below show the same thing.
        SettingsRow("Other layouts", detail: showsOtherLayouts ? nil : summary(of: others)) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { showsOtherLayouts.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(showsOtherLayouts ? "Hide" : "Show")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(showsOtherLayouts ? 90 : 0))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme[ThemeKey.accentText])
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .accessibilityLabel(showsOtherLayouts ? "Hide other layouts' timestamp positions" : "Show other layouts' timestamp positions")
        }
        if showsOtherLayouts {
            ForEach(others, id: \.self) { layout in
                SettingsSegmentedRow(
                    title: Self.name(of: layout),
                    detail: layout == .grouped ? "Only a group's first message; hover the others." : nil,
                    selection: binding(for: layout),
                    options: Self.options
                )
                .padding(.leading, 14)
            }
        }
    }

    private func binding(for layout: ChatLayout) -> Binding<TimestampPosition> {
        let settings = app.settings
        let key = SettingKey<TimestampPosition>.chatTimestampPosition(for: layout)
        return Binding(
            get: { settings[key] },
            set: { position in withAnimation(.snappy(duration: 0.2)) { settings[key] = position } }
        )
    }

    /// "Classic: Left · Compact columns: Left".
    private func summary(of layouts: [ChatLayout]) -> String {
        layouts.map { layout in
            let position = app.settings[SettingKey<TimestampPosition>.chatTimestampPosition(for: layout)]
            return "\(Self.name(of: layout)): \(Self.label(of: position))"
        }.joined(separator: " · ")
    }

    static let options: [(value: TimestampPosition, label: String)] = TimestampPosition.allCases.map { ($0, label(of: $0)) }

    static func label(of position: TimestampPosition) -> String {
        switch position {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    /// The names the layout cards above use.
    static func name(of layout: ChatLayout) -> String {
        switch layout {
        case .classic: "Classic"
        case .grouped: "Modern"
        case .columns: "Compact columns"
        }
    }

    static func detail(for layout: ChatLayout) -> String {
        switch layout {
        case .classic: "Where times go in Classic. Each layout keeps its own."
        case .grouped: "Where times go in Modern: on a group's first message. Hover the others to see theirs."
        case .columns: "Where times go in Compact columns. Each layout keeps its own."
        }
    }
}
