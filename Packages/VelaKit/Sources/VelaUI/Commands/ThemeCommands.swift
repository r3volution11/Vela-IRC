// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VelaCore
import VelaStore
import VelaTheme

/// The Theme menu. Themes aren't listed here (there can be hundreds of
/// user themes); "Select Theme…" opens the palette's theme picker, which
/// previews each one live.
struct ThemeMenuItems: View {
    let commands: VelaCommandCatalog

    var body: some View {
        CommandMenuButton(commands.selectTheme)
        CommandMenuToggle(commands.toggleFollowSystem)

        Divider()

        CommandMenuButton(commands.themeEditor)
        CommandMenuButton(commands.importTheme)
        CommandMenuButton(commands.revealThemesFolder)

        Divider()

        CommandMenuButton(commands.openSettingsJSON)
    }
}

/// AppKit-backed theme actions shared by the menu and the palette (and
/// usable from settings).
@MainActor
enum ThemeFileActions {
    /// Makes `info` the active theme. With "Match System Appearance" on, it
    /// becomes the preferred theme for the current system appearance (so
    /// matching stays on); otherwise it becomes the fixed theme.
    static func select(_ info: ThemeInfo, settings: SettingsStore, systemAppearance: ThemeKind) {
        if settings[.appearanceFollowSystem] {
            switch systemAppearance {
            case .dark: settings[.appearancePreferredDarkTheme] = info.name
            case .light: settings[.appearancePreferredLightTheme] = info.name
            }
        } else {
            settings[.appearanceTheme] = info.name
        }
    }

    /// Asks for `.json`/`.vsix` files, imports them and switches to the first
    /// imported theme. Failures are reported in one alert.
    static func importThemes(into themeStore: ThemeStore, settings: SettingsStore) {
        let panel = NSOpenPanel()
        panel.title = "Import Theme"
        panel.message = "Choose a Vela or VS Code color theme (.json) or a VS Code extension (.vsix)."
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json] + ["jsonc", "vsix"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        var imported: [ThemeInfo] = []
        var failures: [String] = []
        for url in panel.urls {
            do {
                imported += try themeStore.importTheme(from: url)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if let first = imported.first {
            select(first, settings: settings, systemAppearance: themeStore.systemAppearance)
        }
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = failures.count == 1 ? "The theme couldn't be imported." : "Some themes couldn't be imported."
            alert.informativeText = failures.joined(separator: "\n\n")
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Shows the user Themes folder in Finder, creating it if needed.
    static func revealThemesFolder(of themeStore: ThemeStore) {
        let folder = themeStore.userThemesDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Saves pending changes and opens settings.json in the default editor.
    static func openSettingsFile(_ settings: SettingsStore) {
        settings.flush()
        let url = settings.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            // Nothing customized yet: start from an empty object so there's a file to open.
            try? Data("{\n}\n".utf8).write(to: url, options: .atomic)
        }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
