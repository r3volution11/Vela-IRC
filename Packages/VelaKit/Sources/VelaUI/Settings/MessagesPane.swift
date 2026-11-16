// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Message layout, typography, timestamps and conversation noise.
struct MessagesPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var editsCustomTimestamp = false

    private static let timestampPresets = ["HH:mm", "h:mm a", "HH:mm:ss"]
    private static let customTag = "\u{0}custom"

    var body: some View {
        @Bindable var settings = app.settings

        SettingsPage("Messages", subtitle: "How conversations look: layout, type, timestamps and what counts as noise.") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Layout")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
                HStack(alignment: .top, spacing: 12) {
                    layoutCard(.classic, title: "Classic", subtitle: "One line per message, like a terminal client.")
                    layoutCard(.grouped, title: "Modern", subtitle: "Messages grouped under a name and avatar.")
                    layoutCard(.columns, title: "Compact columns", subtitle: "Time, name and text in aligned columns.")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preview")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("Updates as you change settings")
                        .font(.system(size: 11))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                }
                .padding(.horizontal, 4)
                MessageSamplePreview()
            }

            SettingsSection("Text") {
                SettingsRow("Font", detail: "The typeface for chat messages.", labelsControl: true) {
                    fontPicker(selection: $settings[.chatFontFamily])
                }
                FontSizeRow(size: $settings[.chatFontSize])
                SettingsToggle(
                    "Use a monospace font",
                    detail: "Render all chat text in the monospace font, like irssi or WeeChat.",
                    isOn: $settings[.chatMonospace]
                )
                SettingsRow("Monospace font", detail: "Also used for code and the fixed-width parts of the columns layout.", labelsControl: true) {
                    monospacePicker(selection: $settings[.chatMonospaceFontFamily])
                }
                SettingsSliderRow(
                    title: "Line spacing",
                    detail: "Extra space between the lines of one message.",
                    value: $settings[.chatLineSpacing],
                    range: 0...10,
                    step: 0.5,
                    format: SettingsFormat.points
                )
                SettingsSliderRow(
                    title: "Message spacing",
                    detail: "Space between messages and message groups.",
                    value: $settings[.chatMessageSpacing],
                    range: 0...24,
                    format: SettingsFormat.points
                )
            }

            SettingsSection("Timestamps") {
                SettingsToggle("Show timestamps", isOn: $settings[.chatShowTimestamps])
                SettingsRow("Format", detail: "Uses Unicode date patterns, e.g. HH:mm:ss or h:mm a.", labelsControl: true) {
                    Picker("Timestamp format", selection: timestampSelection) {
                        ForEach(Self.timestampPresets, id: \.self) { format in
                            Text(Self.sample(format)).tag(format)
                        }
                        Divider()
                        Text("Custom…").tag(Self.customTag)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if isCustomTimestamp {
                    SettingsRow("Custom format", detail: "Shows as “\(Self.sample(settings[.chatTimestampFormat]))”.", labelsControl: true) {
                        ThemedTextField("HH:mm", text: $settings[.chatTimestampFormat], monospaced: true, accessibilityName: "Custom timestamp format")
                            .frame(width: 140)
                    }
                }
            }
            .opacity(settings[.chatShowTimestamps] ? 1 : 0.85)

            SettingsSection("Conversation") {
                SettingsSegmentedRow(
                    title: "Joins and parts",
                    detail: "Joins, parts, quits and nick changes.",
                    selection: $settings[.chatShowJoinPart],
                    options: [(.show, "Show"), (.collapse, "Collapse"), (.hide, "Hide")]
                )
                SettingsToggle("Colored nicknames", detail: "Give everyone a stable color from the theme's nick palette.", isOn: $settings[.chatColorNicks])
                SettingsToggle("Avatars", detail: "Show initials avatars next to message groups in the Modern layout.", isOn: $settings[.chatShowAvatars])
                SettingsMenuRow(
                    title: "Group messages within",
                    detail: "Messages from the same person this close together share one header.",
                    selection: $settings[.chatGroupingInterval],
                    options: Self.options(
                        [60, 120, 300, 600, 900, 1800, 3600],
                        current: settings[.chatGroupingInterval],
                        label: Self.duration
                    )
                )
                SettingsSliderRow(
                    title: "Name column width",
                    detail: "Used by the Compact columns layout.",
                    value: $settings[.chatColumnsNickWidth],
                    range: 60...240,
                    step: 5,
                    format: SettingsFormat.points
                )
                SettingsToggle("mIRC formatting", detail: "Show colors, bold and italics sent by other clients. Off shows plain text.", isOn: $settings[.chatRenderFormatting])
                SettingsToggle("Large emoji", detail: "Show messages that are only emoji bigger.", isOn: $settings[.chatLargeEmoji])
            }

            SettingsSection("Memory", footer: "Older messages stay on disk and load as you scroll up.") {
                SettingsMenuRow(
                    title: "Messages kept in memory",
                    detail: "Per channel or conversation.",
                    selection: $settings[.chatScrollbackInMemory],
                    options: Self.options(
                        [500, 1000, 2000, 5000, 10000],
                        current: settings[.chatScrollbackInMemory],
                        label: { $0.formatted() }
                    )
                )
            }
        }
    }

    // MARK: Layout cards

    private func layoutCard(_ layout: ChatLayout, title: String, subtitle: String) -> some View {
        var config = LayoutSchematicConfig(settings: app.settings)
        config.chatLayout = layout
        config.showMedia = false
        return SettingsChoiceCard(
            title,
            subtitle: subtitle,
            isSelected: app.settings[.chatLayout] == layout,
            action: { withAnimation(.snappy(duration: 0.2)) { app.settings[.chatLayout] = layout } },
            preview: {
                LayoutSchematic(config: config, theme: theme, scope: .messages)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme[ThemeKey.settingsBorder])
                    )
            }
        )
    }

    // MARK: Fonts

    private func fontPicker(selection: Binding<String>) -> some View {
        let current = selection.wrappedValue
        return Picker("Chat font", selection: selection) {
            Text("System").tag("")
            Divider()
            if !current.isEmpty && !FontCatalog.families.contains(current) {
                Text("\(current) (not installed)").tag(current)
            }
            ForEach(FontCatalog.families, id: \.self) { family in
                Text(family).tag(family)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 200)
    }

    private func monospacePicker(selection: Binding<String>) -> some View {
        let current = selection.wrappedValue
        let families = FontCatalog.monospacedFamilies
        return Picker("Monospace font", selection: selection) {
            Text("SF Mono (System)").tag("SF Mono")
            Divider()
            if current != "SF Mono" && !current.isEmpty && !families.contains(current) {
                Text("\(current) (not installed)").tag(current)
            }
            ForEach(families.filter { $0 != "SF Mono" }, id: \.self) { family in
                Text(family).tag(family)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 200)
    }

    // MARK: Timestamps

    private var isCustomTimestamp: Bool {
        editsCustomTimestamp || !Self.timestampPresets.contains(app.settings[.chatTimestampFormat])
    }

    private var timestampSelection: Binding<String> {
        Binding(
            get: { isCustomTimestamp ? Self.customTag : app.settings[.chatTimestampFormat] },
            set: { tag in
                if tag == Self.customTag {
                    editsCustomTimestamp = true
                } else {
                    editsCustomTimestamp = false
                    app.settings[.chatTimestampFormat] = tag
                }
            }
        )
    }

    private static let sampleDate: Date = {
        Calendar.current.date(bySettingHour: 14, minute: 5, second: 9, of: Date()) ?? Date()
    }()

    static func sample(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        let text = formatter.string(from: sampleDate)
        return text.isEmpty ? "(empty)" : text
    }

    // MARK: Options

    /// Fixed choices plus the current value when it was set by hand.
    static func options<Value: Hashable & Comparable>(
        _ values: [Value],
        current: Value,
        label: (Value) -> String
    ) -> [(value: Value, label: String)] {
        var all = values
        if !all.contains(current) { all.append(current); all.sort() }
        return all.map { ($0, label($0)) }
    }

    static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds)) seconds" }
        if seconds < 3600 {
            let minutes = seconds / 60
            let text = minutes.rounded() == minutes ? "\(Int(minutes))" : String(format: "%.1f", minutes)
            return minutes == 1 ? "1 minute" : "\(text) minutes"
        }
        let hours = seconds / 3600
        return hours == 1 ? "1 hour" : String(format: "%g hours", hours)
    }
}

/// Font size with a slider and a stepper, 9–28 pt.
private struct FontSizeRow: View {
    @Environment(\.theme) private var theme
    @Binding var size: Double

    var body: some View {
        SettingsRow("Size", labelsControl: true) {
            HStack(spacing: 8) {
                Text("A")
                    .font(.system(size: 10))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .accessibilityHidden(true)
                Slider(value: Binding(
                    get: { min(28, max(9, size)) },
                    set: { size = $0.rounded() }
                ), in: 9...28) { Text("Font size") }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 130)
                    .accessibilityValue("\(Int(size)) points")
                Text("A")
                    .font(.system(size: 16))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .accessibilityHidden(true)
                Stepper(value: $size, in: 9...28, step: 1) {
                    Text("\(Int(size)) pt")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .frame(minWidth: 38, alignment: .trailing)
                }
                .controlSize(.small)
                .accessibilityLabel("Font size")
                .accessibilityValue("\(Int(size)) points")
            }
        }
    }
}

/// Installed font families, computed once.
enum FontCatalog {
    static let families: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    /// Families whose regular face is fixed-pitch.
    static let monospacedFamilies: [String] = families.filter { family in
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
              let name = members.first?.first as? String,
              let font = NSFont(name: name, size: 12)
        else { return false }
        return font.isFixedPitch
    }
}
