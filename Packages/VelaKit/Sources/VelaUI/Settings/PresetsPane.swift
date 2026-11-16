// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// One-click configurations. Presets write navigation, layout, density and
/// media keys only; the theme and everything else stay as they are.
struct PresetsPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    let navigate: (SettingsPane) -> Void

    var body: some View {
        let active = app.settings.matchingPreset()
        SettingsPage(
            "Presets",
            subtitle: "Start from a ready-made setup, then fine-tune anything you like. Presets change layout, density and media — never your theme."
        ) {
            CurrentPresetBanner(active: active)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)],
                spacing: 16
            ) {
                ForEach(SettingsPreset.all) { preset in
                    PresetCard(preset: preset, isActive: preset.id == active?.id) {
                        withAnimation(.snappy(duration: 0.25)) { app.settings.apply(preset) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Make it yours")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                Text("Every value a preset sets can be changed on its own, and anything a preset doesn't mention is left untouched.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    SettingsLinkButton("Layout", systemImage: "rectangle.split.3x1") { navigate(.layout) }
                    SettingsLinkButton("Messages", systemImage: "text.bubble") { navigate(.messages) }
                    SettingsLinkButton("Media", systemImage: "photo.on.rectangle.angled") { navigate(.media) }
                    SettingsLinkButton("Themes", systemImage: "paintpalette") { navigate(.appearance) }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
    }
}

/// "Current setup: Modern Chat" or "Custom".
struct CurrentPresetBanner: View {
    @Environment(\.theme) private var theme
    let active: SettingsPreset?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: active?.systemImage ?? "slider.horizontal.3")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme[ThemeKey.accentForeground])
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme[ThemeKey.accent]))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Current setup:")
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    Text(active?.name ?? "Custom")
                        .fontWeight(.semibold)
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                }
                .font(.system(size: 13))
                Text(active == nil
                     ? "Your settings don't match a preset exactly. Apply one to start over, or keep fine-tuning."
                     : "Everything matches this preset. Changing any of its settings makes your setup custom.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme[ThemeKey.accent].opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme[ThemeKey.accent].opacity(0.35))
        )
        .accessibilityElement(children: .combine)
    }
}

/// A large preset card: illustration, name, summary and Apply.
private struct PresetCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    let preset: SettingsPreset
    let isActive: Bool
    let apply: () -> Void

    @State private var showsValues = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LayoutSchematic(config: LayoutSchematicConfig(preset: preset, settings: app.settings), theme: theme)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme[ThemeKey.settingsBorder])
                )
            HStack(spacing: 8) {
                Image(systemName: preset.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme[ThemeKey.accent])
                    .accessibilityHidden(true)
                Text(preset.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                Spacer(minLength: 4)
                if isActive {
                    SettingsPill(text: "Active", prominent: true)
                }
            }
            Text(preset.summary)
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Button {
                    showsValues.toggle()
                } label: {
                    Text("\(preset.values.count) settings")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme[ThemeKey.accentText])
                        .underline(showsValues)
                }
                .buttonStyle(.plain)
                .help("Show what this preset changes")
                .accessibilityLabel("Show the \(preset.values.count) settings \(preset.name) changes")
                .popover(isPresented: $showsValues, arrowEdge: .bottom) {
                    PresetValuesPopover(preset: preset)
                }
                Spacer()
                Button(isActive ? "Applied" : "Apply", action: apply)
                    .buttonStyle(ThemedButtonStyle(prominent: !isActive))
                    .themedDisabled(isActive)
                    .accessibilityLabel(isActive ? "\(preset.name) is applied" : "Apply \(preset.name)")
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme[ThemeKey.settingsControlBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? theme[ThemeKey.accent] : theme[ThemeKey.settingsBorder], lineWidth: isActive ? 2 : 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(preset.name) preset\(isActive ? ", active" : "")")
    }
}

/// The exact keys and values a preset writes.
private struct PresetValuesPopover: View {
    @Environment(\.theme) private var theme
    let preset: SettingsPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(preset.name) sets")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.popoverForeground])
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                ForEach(preset.values.keys.sorted(), id: \.self) { key in
                    GridRow {
                        Text(key)
                            .foregroundStyle(theme[ThemeKey.popoverForeground])
                        Text(SettingsFormat.json(preset.values[key] ?? .null))
                            .foregroundStyle(theme[ThemeKey.accentText])
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                }
            }
        }
        .padding(14)
        .background(theme[ThemeKey.popoverBackground])
    }
}
