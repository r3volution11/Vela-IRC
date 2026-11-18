// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Settings → Messages → Chat logs: plain-text logs of what was written,
/// where they go, how big they get and what they include.
struct ChatLogsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    /// Why the last folder choice failed, if it did.
    @State private var chooseError: String?

    var body: some View {
        @Bindable var settings = app.settings
        let logs = app.chatLogs

        VStack(alignment: .leading, spacing: 10) {
            SettingsSection("Chat logs", footer: Self.footer) {
                SettingsToggle(
                    "Save chat logs",
                    detail: "Keep a plain-text copy of your channels and conversations on this Mac.",
                    isOn: $settings[.loggingEnabled]
                )
                folderRow(logs)
                SettingsMenuRow(
                    title: "Start a new file at",
                    detail: "A full file is renamed with the dates it covers.",
                    selection: $settings[.loggingMaxFileSizeMB],
                    options: Self.sizeOptions(current: settings[.loggingMaxFileSizeMB])
                )
                SettingsMenuRow(
                    title: "Files to keep",
                    detail: Self.keepDetail(sizeMB: settings[.loggingMaxFileSizeMB], keep: settings[.loggingKeepFiles]),
                    selection: $settings[.loggingKeepFiles],
                    options: Self.keepOptions(current: settings[.loggingKeepFiles])
                )
                SettingsToggle(
                    "Include channel events",
                    detail: "Joins, parts, quits, nick changes, kicks, and topic and mode changes.",
                    isOn: $settings[.loggingIncludeEvents]
                )
                SettingsToggle(
                    "Include server messages",
                    detail: "Each network's connection messages, MOTD and notices from services, in server.log.",
                    isOn: $settings[.loggingIncludeServer]
                )
                let excluded = settings[.loggingExcludedBuffers]
                if !excluded.isEmpty {
                    SettingsRow(Self.excludedTitle(excluded), detail: "Set from a channel's or network's right-click menu.") {
                        Button("Clear") { settings[.loggingExcludedBuffers] = [] }
                            .buttonStyle(ThemedButtonStyle())
                            .accessibilityLabel("Log these channels again")
                    }
                }
            }

            if case .unavailable(let path) = logs.folderStatus {
                SettingsCallout(
                    .warning,
                    "Vela can't use your chat logs folder",
                    message: "\(path.isEmpty ? "The folder you chose" : path) is missing, on a disk that isn't connected, or Vela no longer has permission to use it. Logs are saved in Vela's folder until you choose it again."
                ) {
                    Button("Choose…", action: choose).buttonStyle(ThemedButtonStyle())
                    Button("Use Vela's Folder") { logs.useDefaultFolder() }.buttonStyle(ThemedButtonStyle())
                }
            }
            if let problem = logs.problem {
                SettingsCallout(
                    .error,
                    "Some chat logs couldn't be saved",
                    message: "\(problem.message) (\(problem.date.formatted(date: .omitted, time: .shortened))). Lines that couldn't be written are left out of the logs."
                )
            }
            if let chooseError {
                SettingsCallout(.error, "Couldn't use that folder", message: chooseError)
            }
        }
    }

    // MARK: Folder

    private func folderRow(_ logs: ChatLogService) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Folder")
                    .font(.system(size: 13))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                Text(logs.folderStatus == .custom ? logs.displayPath : "Vela's folder: \(logs.displayPath)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(logs.folderURL.path)
                if logs.folderStatus == .custom {
                    SettingsLinkButton("Use Vela's Folder") { logs.useDefaultFolder() }
                        .help("Save logs in Vela's data folder again. Logs already in this folder stay there.")
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button("Choose…", action: choose)
                    .buttonStyle(ThemedButtonStyle())
                    .accessibilityLabel("Choose a folder for chat logs")
                Button("Reveal in Finder") { ChatLogActions.revealFolder(app) }
                    .buttonStyle(ThemedButtonStyle())
                    .accessibilityLabel("Reveal the chat logs folder in Finder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 40)
    }

    private func choose() {
        ChatLogActions.chooseFolder(app) { chooseError = $0 }
    }

    // MARK: Text

    static let footer = "Logs are plain text: a folder for each network, with a file for each channel or conversation. They hold what people wrote, links included, but not link previews, images, videos, translations or Catch me up summaries. To leave a channel out, right-click it and choose Don't Log This Channel."

    /// 1–100 MB, with 10 MB recommended, plus a value set by hand.
    static func sizeOptions(current: Int) -> [(value: Int, label: String)] {
        MessagesPane.options([1, 5, 10, 25, 50, 100], current: current) { size in
            size == SettingKey<Int>.loggingMaxFileSizeMB.defaultValue ? "\(size) MB (recommended)" : "\(size) MB"
        }
    }

    /// 1–20 files, with 5 recommended, then Keep all (0).
    static func keepOptions(current: Int) -> [(value: Int, label: String)] {
        var counts = [1, 3, 5, 10, 20]
        if current > 0, !counts.contains(current) { counts.append(current); counts.sort() }
        let recommended = SettingKey<Int>.loggingKeepFiles.defaultValue
        return counts.map { count in
            let label = count == 1 ? "1 file" : "\(count) files"
            return (count, count == recommended ? "\(label) (recommended)" : label)
        } + [(0, "Keep all")]
    }

    /// "Per channel, counting the current one: up to about 50 MB each."
    static func keepDetail(sizeMB: Int, keep: Int) -> String {
        guard keep > 0 else { return "Full files are never deleted." }
        let total = max(1, sizeMB) * keep
        let size = total >= 1024 ? String(format: "%g GB", (Double(total) / 1024 * 10).rounded() / 10) : "\(total) MB"
        return "Per channel, counting the current file: up to about \(size) each. The oldest are deleted."
    }

    /// "Not logged: 2 channels and 1 network".
    static func excludedTitle(_ entries: [String]) -> String {
        let networks = entries.count(where: { $0.hasSuffix("/*") })
        let channels = entries.count - networks
        func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        let parts = [channels > 0 ? count(channels, "channel") : nil, networks > 0 ? count(networks, "network") : nil]
        return "Not logged: " + parts.compactMap { $0 }.joined(separator: " and ")
    }
}
