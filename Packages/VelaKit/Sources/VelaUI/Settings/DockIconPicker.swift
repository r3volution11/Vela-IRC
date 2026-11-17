// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Settings → Appearance → Dock icon: the six icons as thumbnails, the one
/// in use ringed. `DockIconController` puts the choice in the Dock.
struct DockIconSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let settings = app.settings
        let current = settings[.appearanceAppIcon]
        SettingsSection("Dock icon", footer: DockIcon.note) {
            SettingsRow("App icon", detail: "\(DockIcon.title(current)). \(DockIcon.summary(current)).") {
                HStack(spacing: 4) {
                    ForEach(AppIcon.allCases, id: \.self) { icon in
                        DockIconButton(icon: icon, isSelected: icon == current) {
                            settings[.appearanceAppIcon] = icon
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("App icon")
            }
        }
    }
}

/// One icon thumbnail, ringed when it's the one in use.
private struct DockIconButton: View {
    @Environment(\.theme) private var theme
    let icon: AppIcon
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    /// The thumbnail's frame. The render keeps the macOS grid's margins, so
    /// the icon's body is 824/1024 of it and the ring sits just outside.
    private static let size: CGFloat = 44
    private static let ring: CGFloat = 42

    var body: some View {
        Button(action: action) {
            ZStack {
                if let image = DockIcon.image(for: icon) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: Self.size, height: Self.size)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 26))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                }
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme[ThemeKey.accent] : (isHovered ? theme[ThemeKey.settingsSecondaryForeground].opacity(0.5) : .clear),
                        lineWidth: 2
                    )
                    .frame(width: Self.ring, height: Self.ring)
            }
            .frame(width: Self.size, height: Self.size)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(DockIcon.title(icon))
        .accessibilityLabel("\(DockIcon.title(icon)) icon")
        .accessibilityHint("\(DockIcon.summary(icon)).")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
