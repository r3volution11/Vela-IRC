// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VelaCore
import VelaStore
import VelaTheme

/// Theme gallery, light/dark following, theme import and the editor.
struct AppearancePane: View {
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    let navigate: (SettingsPane) -> Void

    @State private var filter: KindFilter = .all
    @State private var importResult: ImportResult?
    @State private var themePendingDeletion: ThemeInfo?
    @State private var deletionError: String?

    enum KindFilter: String, CaseIterable {
        case all = "All"
        case dark = "Dark"
        case light = "Light"
    }

    struct ImportResult: Equatable {
        var imported: [ThemeInfo]
        var failures: [String]
    }

    var body: some View {
        @Bindable var settings = app.settings
        let followSystem = settings[.appearanceFollowSystem]

        SettingsPage(
            "Appearance",
            subtitle: "Every surface in Vela is drawn from a theme. Pick one, follow the system's light and dark mode, or make your own."
        ) {
            QuickPresetsStrip(navigate: navigate)

            if themeStore.draft != nil {
                SettingsCallout(.info, "Previewing an unsaved theme", message: "The Theme Editor is showing its work in progress everywhere. Save or close it to go back to your theme.") {
                    Button("Show Theme Editor") { openWindow(id: WindowID.themeEditor) }
                        .buttonStyle(ThemedButtonStyle())
                }
            }

            SettingsSection(
                "Theme",
                footer: followSystem
                    ? "Choosing a theme here turns off Match System Appearance. Right-click a theme to use it for Dark or Light Mode instead."
                    : nil
            ) {
                gallery
            } accessory: {
                Picker("Show", selection: $filter) {
                    ForEach(KindFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Show themes")
            }

            SettingsSection("System appearance") {
                SettingsToggle(
                    "Match system appearance",
                    detail: "Switch between a dark and a light theme when macOS changes between Dark and Light Mode.",
                    isOn: $settings[.appearanceFollowSystem]
                )
                if followSystem {
                    SettingsRow("Dark Mode theme", labelsControl: true) { themePicker(.appearancePreferredDarkTheme, kind: .dark, label: "Dark Mode theme") }
                    SettingsRow("Light Mode theme", labelsControl: true) { themePicker(.appearancePreferredLightTheme, kind: .light, label: "Light Mode theme") }
                } else {
                    SettingsRow("Theme", labelsControl: true) { themePicker(.appearanceTheme, kind: nil, label: "Theme") }
                }
            }

            SettingsSection(
                "Make your own",
                footer: "Themes are JSON files of color tokens, like VS Code themes. Vela reloads them the moment you save, and keeps the last working version if a file has a mistake."
            ) {
                SettingsRow("Theme Editor", detail: "Change any color with a live preview of the whole app, then save or export it.") {
                    Button("Customize…") { openEditor(base: nil) }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                }
                SettingsRow("Import a theme", detail: "Vela or VS Code themes (.json), or a VS Code extension (.vsix).") {
                    Button("Import Theme…", action: importThemes)
                        .buttonStyle(ThemedButtonStyle())
                }
                SettingsRow("Themes folder", detail: "Drop theme files here, or edit them in your favorite editor.") {
                    Button("Reveal Themes Folder") { SettingsFiles.openFolder(themeStore.userThemesDirectory) }
                        .buttonStyle(ThemedButtonStyle())
                }
            }

            if let importResult { importCallout(importResult) }
            if let deletionError {
                SettingsCallout(.error, "Couldn't delete the theme", message: deletionError)
            }
            problems

            SettingsSection("Details") {
                let overrides = settings[.appearanceColorCustomizations].count
                SettingsRow(
                    "Color overrides",
                    detail: overrides == 0
                        ? "Adjust any theme without editing it: add \"appearance.colorCustomizations\" to settings.json, e.g. {\"accent\": \"#FF8A65\"}."
                        : "\(overrides) \(overrides == 1 ? "override" : "overrides") from appearance.colorCustomizations \(overrides == 1 ? "is" : "are") applied on top of your themes."
                ) {
                    Button("Open settings.json") { SettingsFiles.openSettingsJSON(app.settings) }
                        .buttonStyle(ThemedButtonStyle())
                }
                SettingsRow(
                    "Translucency",
                    detail: "Themes can let macOS draw the sidebar or the whole window with Liquid Glass materials by setting \"vibrancy\" to \"sidebar\" or \"window\". Opaque themes keep every color exactly as designed."
                ) {
                    SettingsPill(text: "\(theme.name): \(theme.vibrancy.rawValue)")
                }
            }
        }
        .confirmationDialog(
            "Delete “\(themePendingDeletion?.name ?? "theme")”?",
            isPresented: Binding(
                get: { themePendingDeletion != nil },
                set: { if !$0 { themePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Theme", role: .destructive) {
                if let info = themePendingDeletion { delete(info) }
                themePendingDeletion = nil
            }
        } message: {
            Text("The theme file is removed from your Themes folder. This can't be undone.")
        }
    }

    // MARK: Gallery

    private var visibleThemes: [ThemeInfo] {
        themeStore.themes.filter { info in
            switch filter {
            case .all: true
            case .dark: info.kind == .dark
            case .light: info.kind == .light
            }
        }
    }

    @ViewBuilder
    private var gallery: some View {
        let themes = visibleThemes
        if themes.isEmpty {
            Text(themeStore.themes.isEmpty ? "Loading themes…" : "No \(filter.rawValue.lowercased()) themes.")
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .padding(14)
        } else {
            let config = galleryConfig
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 136, maximum: 190), spacing: 12, alignment: .top)], spacing: 14) {
                ForEach(themes) { info in
                    ThemeCard(
                        info: info,
                        resolved: themeStore.resolvedTheme(for: info),
                        config: config,
                        isCurrent: themeStore.currentInfo?.id == info.id,
                        roles: roles(for: info)
                    ) {
                        select(info)
                    }
                    .contextMenu { contextMenu(for: info) }
                }
            }
            .padding(12)
        }
    }

    /// The user's own layout, without media, so each card previews "my Vela in this theme".
    private var galleryConfig: LayoutSchematicConfig {
        var config = LayoutSchematicConfig(settings: app.settings)
        config.showMedia = false
        return config
    }

    private func roles(for info: ThemeInfo) -> [String] {
        guard app.settings[.appearanceFollowSystem] else { return [] }
        var roles: [String] = []
        if info.matches(app.settings[.appearancePreferredDarkTheme]) { roles.append("Dark Mode") }
        if info.matches(app.settings[.appearancePreferredLightTheme]) { roles.append("Light Mode") }
        return roles
    }

    @ViewBuilder
    private func contextMenu(for info: ThemeInfo) -> some View {
        Button("Use “\(info.name)”") { select(info) }
        Button("Use in Dark Mode") {
            app.settings[.appearancePreferredDarkTheme] = info.name
            app.settings[.appearanceFollowSystem] = true
        }
        Button("Use in Light Mode") {
            app.settings[.appearancePreferredLightTheme] = info.name
            app.settings[.appearanceFollowSystem] = true
        }
        Divider()
        Button("Customize in Theme Editor…") { openEditor(base: info) }
        if info.source == .user {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([info.url]) }
            Divider()
            Button("Delete Theme…", role: .destructive) { themePendingDeletion = info }
        }
    }

    private func select(_ info: ThemeInfo) {
        // Same rule as Select Theme (⌃⌘T): with Match System Appearance on,
        // this sets the theme for the current appearance and keeps matching.
        ThemeFileActions.select(info, settings: app.settings, systemAppearance: themeStore.systemAppearance)
    }

    private func delete(_ info: ThemeInfo) {
        do {
            try themeStore.deleteUserTheme(info)
            deletionError = nil
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func openEditor(base: ThemeInfo?) {
        if let base { ThemeEditorHandoff.shared.requestedBase = base }
        openWindow(id: WindowID.themeEditor)
    }

    // MARK: Pickers

    private func themePicker(_ key: SettingKey<String>, kind: ThemeKind?, label: String) -> some View {
        let reference = app.settings[key]
        let resolvedID = themeStore.info(for: reference)?.id
        let candidates = themeStore.themes.filter { kind == nil || $0.kind == kind || $0.id == resolvedID }
        return Picker(label, selection: Binding(
            get: { resolvedID ?? reference },
            set: { id in app.settings[key] = themeStore.themes.first { $0.id == id }?.name ?? id }
        )) {
            if resolvedID == nil {
                Text("\(reference) (missing)").tag(reference)
            }
            ForEach(candidates) { info in
                Text(info.name).tag(info.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    // MARK: Import

    private func importThemes() {
        let panel = NSOpenPanel()
        panel.title = "Import Theme"
        panel.message = "Choose Vela or VS Code themes (.json) or VS Code extensions (.vsix)."
        panel.prompt = "Import"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.json]
            + ["jsonc", "vsix"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        var imported: [ThemeInfo] = []
        var failures: [String] = []
        for url in panel.urls {
            do {
                imported += try themeStore.importTheme(from: url)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        importResult = ImportResult(imported: imported, failures: failures)
    }

    @ViewBuilder
    private func importCallout(_ result: ImportResult) -> some View {
        if !result.imported.isEmpty {
            let names = result.imported.map { "“\($0.name)”" }.joined(separator: ", ")
            SettingsCallout(.success, "Imported \(names)", message: "Imported themes live in your Themes folder.") {
                if let first = result.imported.first {
                    Button("Use “\(first.name)”") {
                        select(first)
                        importResult = nil
                    }
                    .buttonStyle(ThemedButtonStyle(prominent: true))
                }
                Button("Dismiss") { importResult = nil }
                    .buttonStyle(ThemedButtonStyle())
            }
        }
        if !result.failures.isEmpty {
            SettingsCallout(.error, "Some files couldn't be imported", message: result.failures.joined(separator: "\n")) {
                Button("Dismiss") { importResult = nil }
                    .buttonStyle(ThemedButtonStyle())
            }
        }
    }

    // MARK: Problems

    @ViewBuilder
    private var problems: some View {
        let errors = themeStore.loadErrors.sorted { $0.key.lastPathComponent < $1.key.lastPathComponent }
        ForEach(errors, id: \.key) { url, message in
            SettingsCallout(.error, "Couldn't load \(url.lastPathComponent)", message: message) {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(ThemedButtonStyle())
            }
        }
        if !themeStore.customizationProblems.isEmpty {
            SettingsCallout(
                .warning,
                "Problems in appearance.colorCustomizations",
                message: themeStore.customizationProblems.joined(separator: "\n")
            ) {
                Button("Open settings.json") { SettingsFiles.openSettingsJSON(app.settings) }
                    .buttonStyle(ThemedButtonStyle())
            }
        }
    }
}

/// One theme in the gallery: a miniature window drawn in that theme.
private struct ThemeCard: View {
    @Environment(\.theme) private var theme
    let info: ThemeInfo
    let resolved: ResolvedTheme?
    let config: LayoutSchematicConfig
    let isCurrent: Bool
    let roles: [String]
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    if let resolved {
                        LayoutSchematic(config: config, theme: resolved)
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(theme[ThemeKey.settingsBackground])
                            .aspectRatio(1.6, contentMode: .fit)
                            .overlay {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(theme[ThemeKey.statusWarning])
                            }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme[ThemeKey.settingsBorder])
                )
                .scaleEffect(isHovered && !isCurrent ? 1.02 : 1)
                .animation(.snappy(duration: 0.15), value: isHovered)

                HStack(spacing: 4) {
                    Text(info.name)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(theme[ThemeKey.settingsForeground])
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 2)
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme[ThemeKey.accent])
                    }
                }
                HStack(spacing: 4) {
                    Text(info.kind == .dark ? "Dark" : "Light")
                    if info.source == .user {
                        Text("· Yours")
                    }
                    ForEach(roles, id: \.self) { role in
                        Text("· \(role)")
                            .foregroundStyle(theme[ThemeKey.accentText])
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .lineLimit(1)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? theme[ThemeKey.accent].opacity(0.12) : (isHovered ? theme[ThemeKey.settingsForeground].opacity(0.05) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isCurrent ? theme[ThemeKey.accent] : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(info.source == .user ? "\(info.name) — \(info.url.lastPathComponent)" : info.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(info.name), \(info.kind == .dark ? "dark" : "light") theme\(info.source == .user ? ", yours" : "")")
        .accessibilityValue(([isCurrent ? "In use" : nil] + roles.map { "Used in \($0)" }).compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}

/// Compact preset chooser shown at the top of Appearance.
struct QuickPresetsStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    let navigate: (SettingsPane) -> Void

    var body: some View {
        let active = app.settings.matchingPreset()
        SettingsSection(
            "Layout preset",
            footer: "Presets arrange navigation, messages and media in one click; they don't change your theme."
        ) {
            HStack(spacing: 8) {
                ForEach(SettingsPreset.all) { preset in
                    let isActive = preset.id == active?.id
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { app.settings.apply(preset) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: preset.systemImage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isActive ? theme[ThemeKey.accentForeground] : theme[ThemeKey.accent])
                            Text(preset.name)
                                .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                                .foregroundStyle(isActive ? theme[ThemeKey.accentForeground] : theme[ThemeKey.settingsForeground])
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isActive ? theme[ThemeKey.accent] : theme[ThemeKey.settingsBackground])
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(isActive ? .clear : theme[ThemeKey.settingsBorder])
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(preset.summary)
                    .accessibilityLabel(preset.name)
                    .accessibilityHint(preset.summary)
                    .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(10)
        } accessory: {
            HStack(spacing: 10) {
                if active == nil {
                    SettingsPill(text: "Custom")
                }
                SettingsLinkButton("All presets") { navigate(.presets) }
            }
        }
    }
}

/// Opening settings.json and folders in Finder.
enum SettingsFiles {
    /// Writes pending changes, creates an empty file if needed, and opens
    /// settings.json in the default editor.
    static func openSettingsJSON(_ settings: SettingsStore) {
        settings.flush()
        let url = settings.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data("{\n}\n".utf8).write(to: url, options: .atomic)
        }
        NSWorkspace.shared.open(url)
    }

    /// Opens a folder (created if missing) in Finder.
    static func openFolder(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
