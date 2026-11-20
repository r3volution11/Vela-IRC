// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// Message layout, typography, timestamps, conversation noise and typing.
struct MessagesPane: View {
    @Environment(AppModel.self) private var app
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style

    /// Keeps the custom pattern field open while it's empty.
    @State private var editsCustomTimestamp = false

    var body: some View {
        @Bindable var settings = app.settings

        SettingsPage("Messages", subtitle: "How conversations look and how you type: layout, timestamps, noise and spelling.", pane: .messages) {
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

            SettingsSection("Timestamps", footer: "Timestamps show as “\(timestampSample)”.") {
                SettingsToggle("Show timestamps", isOn: $settings[.chatShowTimestamps])
                TimestampPositionRows()
                SettingsSegmentedRow(
                    title: "Clock",
                    detail: "System follows your Mac's 24-hour time setting.",
                    selection: $settings[.chatClock],
                    options: [(.system, "System"), (.twelveHour, "12-hour"), (.twentyFourHour, "24-hour")]
                )
                .themedDisabled(usesCustomTimestamp)
                SettingsToggle("Show seconds", isOn: $settings[.chatTimestampSeconds])
                    .themedDisabled(usesCustomTimestamp)
                SettingsToggle(
                    "Custom format",
                    detail: "Use your own Unicode date pattern, like HH:mm:ss or h:mm a.",
                    isOn: customTimestamp
                )
                if usesCustomTimestamp {
                    SettingsRow("Pattern", labelsControl: true) {
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
                SettingsToggle("Colored nicknames", detail: "Give everyone a color from the theme's nick palette. People talking in the same channel get different colors.", isOn: $settings[.chatColorNicks])
                SettingsToggle(
                    "Color nicks in messages",
                    detail: settings[.chatColorNicks]
                        ? "When a message mentions someone in the channel, their nick has their color there too."
                        : "Needs Colored nicknames.",
                    isOn: $settings[.chatColorNicksInText]
                )
                .themedDisabled(!settings[.chatColorNicks])
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

            SettingsSection(
                "Unread messages",
                footer: "Show newest also applies when you come back to Vela. Unread counts in the sidebar and on tabs work the same either way."
            ) {
                SettingsSegmentedRow(
                    title: "When you open a channel",
                    detail: "Where you stopped reading, or the newest messages with nothing to scroll down to.",
                    selection: $settings[.chatOpenAt],
                    options: [(.firstUnread, "Jump to first unread"), (.newest, "Show newest")]
                )
                SettingsToggle(
                    "Show the New line",
                    detail: "A line above the first message you haven't read. Off, messages appear just as they came in.",
                    isOn: $settings[.chatShowUnreadMarker]
                )
            }

            typingSection

            SettingsSection("Memory", footer: settings[.historySave]
                ? "Older messages stay on disk and load as you scroll up."
                : "Older messages load from the server as you scroll up, if it keeps history."
            ) {
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

            HistorySection()

            ChatLogsSection()
        }
    }

    // MARK: Typing

    /// The message box's spelling, substitutions and Writing Tools. Three
    /// of them follow macOS until they're changed here.
    private var typingSection: some View {
        @Bindable var settings = app.settings
        let system = SystemTextSettings.shared.values

        return SettingsSection("Typing", footer: "Commands, nicks, channel names, links and code are never corrected.") {
            SettingsToggle(
                "Check spelling while typing",
                detail: "Underline misspelled words in the message box.",
                isOn: $settings[.inputSpellCheck]
            )
            SettingsToggle(
                "Check grammar",
                detail: "Underline grammar mistakes along with spelling.",
                isOn: $settings[.inputGrammarCheck]
            )
            SystemFollowingToggleRow(
                "Correct spelling automatically",
                detail: "Fix misspelled words as you type.",
                value: $settings[.inputAutocorrect],
                system: system.autocorrect,
                reset: { settings.reset(.inputAutocorrect) }
            )
            SystemFollowingToggleRow(
                "Use text replacements",
                detail: "Expand the text replacements you set up in macOS.",
                value: $settings[.inputTextReplacements],
                system: system.textReplacements,
                reset: { settings.reset(.inputTextReplacements) }
            ) {
                SettingsLinkButton("Edit Text Replacements…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .help("Open System Settings → Keyboard")
                .accessibilityHint("Opens Keyboard settings, where text replacements are edited.")
            }
            SystemFollowingToggleRow(
                "Smart quotes and dashes",
                detail: "Use curly quotes, and turn double hyphens into dashes.",
                value: $settings[.inputSmartPunctuation],
                system: system.smartPunctuation,
                reset: { settings.reset(.inputSmartPunctuation) }
            )
            SettingsToggle("Writing Tools", detail: writingToolsDetail, isOn: $settings[.inputWritingTools])
            SettingsToggle(
                "Send typing indicators",
                detail: "Let others see when you're typing, on servers that support it.",
                isOn: $settings[.inputSendTypingIndicators]
            )
        }
    }

    private var writingToolsDetail: String {
        let base = "Proofread and rewrite your message with Apple Intelligence."
        let status = intelligence.availability.status
        return status.isAvailable ? base : "\(base) \(status.title)."
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

    /// On while `chat.timestampFormat` holds a pattern (or its field is open).
    private var usesCustomTimestamp: Bool {
        editsCustomTimestamp || !app.settings[.chatTimestampFormat].allSatisfy(\.isWhitespace)
    }

    /// Turning it on starts from the pattern in effect; off removes the
    /// custom pattern so the clock settings apply again.
    private var customTimestamp: Binding<Bool> {
        Binding(
            get: { usesCustomTimestamp },
            set: { isOn in
                editsCustomTimestamp = isOn
                if isOn {
                    app.settings[.chatTimestampFormat] = style.timestampPattern
                } else {
                    app.settings.reset(.chatTimestampFormat)
                }
            }
        )
    }

    private static let sampleDate: Date = {
        Calendar.current.date(bySettingHour: 14, minute: 5, second: 9, of: Date()) ?? Date()
    }()

    /// The sample time in the pattern chat uses right now.
    private var timestampSample: String {
        let text = style.timestamp(Self.sampleDate)
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

/// A switch for a setting that follows macOS until it's changed in Vela.
/// It shows the effective value, with "Same as macOS" under it while it
/// follows, or a "Use macOS Setting" button once it's been changed.
private struct SystemFollowingToggleRow<Links: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let detail: String
    @Binding var value: SystemFollowingBool
    /// What macOS says.
    let system: Bool
    let reset: () -> Void
    let links: Links

    init(
        _ title: String,
        detail: String,
        value: Binding<SystemFollowingBool>,
        system: Bool,
        reset: @escaping () -> Void,
        @ViewBuilder links: () -> Links = { EmptyView() }
    ) {
        self.title = title
        self.detail = detail
        _value = value
        self.system = system
        self.reset = reset
        self.links = links()
    }

    private var follows: Bool { value == .system }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .accessibilityHidden(true)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                HStack(spacing: 12) {
                    if follows {
                        Text("Same as macOS")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                            .accessibilityHidden(true)
                    } else {
                        SettingsLinkButton("Use macOS Setting", action: reset)
                            .help("Follow System Settings → Keyboard → Text Input (\(system ? "on" : "off") there)")
                            .accessibilityLabel("Use macOS Setting for \(title)")
                            .accessibilityHint("macOS has it \(system ? "on" : "off").")
                    }
                    links
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: Binding(
                get: { value.resolved(system: system) },
                set: { value = SystemFollowingBool($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityHint(follows ? "\(detail) Same as macOS." : "\(detail) Changed from the macOS setting.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 40)
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
