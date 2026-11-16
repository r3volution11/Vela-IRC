// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VelaCore
import VelaStore
import VelaTheme

/// The Theme menu: every installed theme (dark ones, then light ones, the
/// active one checked), system-appearance matching, the editor and
/// file-level actions. SwiftUI refreshes the list each time the menu opens,
/// so themes loaded or imported later show up.
struct ThemeMenuItems: View {
    @Environment(\.openWindow) private var openWindow
    let app: AppModel
    let themeStore: ThemeStore

    var body: some View {
        let currentID = themeStore.currentInfo?.id
        let themes = themeStore.themes

        // Dark themes, then light ones. (Menu `Section`s would each add their
        // own separators, doubling them up between groups.)
        ForEach(themes.filter { $0.kind == .dark }) { info in
            themeToggle(info, isCurrent: info.id == currentID)
        }
        Divider()
        ForEach(themes.filter { $0.kind == .light }) { info in
            themeToggle(info, isCurrent: info.id == currentID)
        }

        Divider()

        Toggle("Match System Appearance", isOn: Binding(
            get: { app.settings[.appearanceFollowSystem] },
            set: { app.settings[.appearanceFollowSystem] = $0 }
        ))

        Divider()

        Button("Theme Editor…") { openWindow(id: WindowID.themeEditor) }
        Button("Import Theme…") { ThemeFileActions.importThemes(into: themeStore, settings: app.settings) }
        Button("Reveal Themes Folder") { ThemeFileActions.revealThemesFolder(of: themeStore) }

        Divider()

        Button("Open settings.json") { ThemeFileActions.openSettingsFile(app.settings) }
    }

    private func themeToggle(_ info: ThemeInfo, isCurrent: Bool) -> some View {
        Toggle(info.name, isOn: Binding(
            get: { isCurrent },
            set: { _ in ThemeFileActions.select(info, settings: app.settings) }
        ))
    }
}

/// AppKit-backed theme actions shared by the menu (and usable from settings).
@MainActor
enum ThemeFileActions {
    /// Makes `info` the fixed theme (turning off system matching).
    static func select(_ info: ThemeInfo, settings: SettingsStore) {
        settings[.appearanceFollowSystem] = false
        settings[.appearanceTheme] = info.name
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
            select(first, settings: settings)
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
