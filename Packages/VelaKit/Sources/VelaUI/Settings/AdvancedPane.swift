// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaFoundation
import VelaStore
import VelaTheme

/// Behavior toggles, files, and a searchable reference of every setting.
struct AdvancedPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var query = ""

    var body: some View {
        @Bindable var settings = app.settings

        SettingsPage("Advanced", subtitle: "Behavior, history and the files behind it all. Everything here also lives in settings.json.") {
            SettingsSection("Behavior") {
                SettingsToggle(
                    "Reconnect automatically",
                    detail: "Retry after a dropped connection, and after your Mac wakes.",
                    isOn: $settings[.connectionAutoReconnect]
                )
            }

            SettingsSection("History", footer: "Older messages are removed from this Mac when Vela starts.") {
                SettingsMenuRow(
                    title: "Keep messages",
                    selection: $settings[.historyRetentionDays],
                    options: MessagesPane.options(
                        [0, 7, 30, 90, 180, 365, 730],
                        current: settings[.historyRetentionDays],
                        label: Self.retentionLabel
                    )
                )
            }

            SettingsSection(
                "Files",
                footer: "settings.json is plain JSON with comments, like VS Code's. Edits made there apply as soon as you save."
            ) {
                SettingsRow("settings.json", detail: (app.settings.fileURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath) {
                    Button("Open settings.json") { SettingsFiles.openSettingsJSON(app.settings) }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                }
                SettingsRow("Data folder", detail: "Settings, networks, themes and message history.") {
                    Button("Reveal Data Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([app.settings.fileURL.deletingLastPathComponent()])
                    }
                    .buttonStyle(ThemedButtonStyle())
                }
            }

            problems

            SettingsSection("All settings") {
                SettingsReference(query: $query)
            } accessory: {
                Text("\(SettingsCatalog.all.count) keys")
                    .font(.system(size: 11))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            }
        }
    }

    @ViewBuilder
    private var problems: some View {
        if let error = app.settings.lastError {
            SettingsCallout(.error, "settings.json has a problem", message: error) {
                Button("Open settings.json") { SettingsFiles.openSettingsJSON(app.settings) }
                    .buttonStyle(ThemedButtonStyle())
            }
        }
        if let error = app.networkStore.lastError {
            SettingsCallout(.error, "networks.json has a problem", message: error)
        }
        if let error = app.lastError {
            SettingsCallout(.warning, "Startup problem", message: error)
        }
    }

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

/// A searchable, read-only list of every known setting with its default and
/// current value, like VS Code's settings search.
private struct SettingsReference: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Binding var query: String

    var body: some View {
        let results = filtered
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .accessibilityHidden(true)
                ThemedTextField("Search settings, e.g. “font” or “tabs.”", text: $query, accessibilityName: "Search settings")
            }
            .padding(10)

            SettingsHairline()

            if results.isEmpty {
                Text("No settings match “\(query)”.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .padding(14)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.key) { index, descriptor in
                        if index == 0 || results[index - 1].category != descriptor.category {
                            Text(descriptor.category)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                                .textCase(.uppercase)
                                .padding(.horizontal, 14)
                                .padding(.top, index == 0 ? 10 : 14)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                        SettingReferenceRow(descriptor: descriptor, current: app.settings.value(forKey: descriptor.key))
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var filtered: [SettingDescriptor] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return SettingsCatalog.all }
        return SettingsCatalog.all.filter { descriptor in
            let haystack = "\(descriptor.key) \(descriptor.summary)".lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }
}

private struct SettingReferenceRow: View {
    @Environment(\.theme) private var theme
    let descriptor: SettingDescriptor
    let current: JSONValue?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(descriptor.key)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .textSelection(.enabled)
                if current != nil {
                    SettingsPill(text: "Modified", prominent: true)
                }
                Spacer(minLength: 8)
                Text(SettingsFormat.json(current ?? descriptor.defaultValue))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(current != nil ? theme[ThemeKey.accentText] : theme[ThemeKey.settingsSecondaryForeground])
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if !descriptor.summary.isEmpty {
                Text(descriptor.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
            }
            if current != nil {
                Text("Default: \(SettingsFormat.json(descriptor.defaultValue))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copy Key") { copy(descriptor.key) }
            Button("Copy as JSON") {
                copy("\(SettingsFormat.json(.string(descriptor.key))): \(SettingsFormat.json(current ?? descriptor.defaultValue))")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
