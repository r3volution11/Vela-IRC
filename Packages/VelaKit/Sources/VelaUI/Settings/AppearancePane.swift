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
            subtitle: "Every surface in Vela is drawn from a theme. Pick one, follow the system's light and dark mode, or make your own.",
            pane: .appearance
        ) {
            QuickPresetsStrip(navigate: navigate)

            if themeStore.draft != nil {
                SettingsCallout(.info, "Previewing an unsaved theme", message: "The Theme Editor is showing its work in progress everywhere. Save or close it to go back to your theme.") {
                    Button("Show Theme Editor") { openWindow(id: WindowID.themeEditor) }
                        .buttonStyle(ThemedButtonStyle())
                }
            }

            messageBox

            SettingsSection(
                "Theme",
                footer: followSystem
                    ? "Choosing a theme here turns off Match System Appearance. Right-click a theme to use it for Dark or Light Mode instead."
                    : nil
            ) {
                // The accent rows come first so they're visible without
                // scrolling past the whole gallery.
                ForEach(accentThemes) { entry in
                    if let palette = AccentActions.palette(for: entry.info, themeStore: themeStore) {
                        AccentRow(palette: palette, mode: entry.mode)
                    }
                }
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

            DockIconSection()

            SettingsSection("Details") {
                let overrides = AccentCustomizations.handWrittenCount(in: settings[.appearanceColorCustomizations])
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

    // MARK: Message box

    /// The message box border: a style for every theme, and a color per
    /// theme (for both themes with Match System Appearance, as for accents).
    private var messageBox: some View {
        @Bindable var settings = app.settings
        let style = settings[.appearanceMessageBoxBorder]
        let detail = switch style {
        case .none: "No border, just the field's background."
        case .subtle: "A quiet line that stays the same while you type."
        case .accent: "The line turns the accent color while you type."
        }
        return SettingsSection("Message box") {
            SettingsSegmentedRow(
                title: "Border",
                detail: detail,
                selection: $settings[.appearanceMessageBoxBorder],
                options: [(MessageBoxBorder.none, "None"), (.subtle, "Subtle"), (.accent, "Accent when typing")]
            )
            ForEach(accentThemes) { entry in
                if let palette = MessageBoxBorderActions.palette(for: entry.info, themeStore: themeStore) {
                    MessageBoxBorderColorRow(palette: palette, info: entry.info, mode: entry.mode)
                        .themedDisabled(style == MessageBoxBorder.none)
                }
            }
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

    /// A theme whose accent row shows under the gallery.
    private struct AccentTarget: Identifiable {
        let info: ThemeInfo
        /// "Dark Mode" or "Light Mode" when both preferred themes are shown.
        let mode: String?
        var id: String { info.id }
    }

    /// The themes whose accent rows show under the gallery: the theme in use,
    /// or with Match System Appearance on, the Dark and Light Mode themes.
    private var accentThemes: [AccentTarget] {
        let settings = app.settings
        guard settings[.appearanceFollowSystem] else {
            return themeStore.info(for: settings[.appearanceTheme]).map { [AccentTarget(info: $0, mode: nil)] } ?? []
        }
        let dark = themeStore.info(for: settings[.appearancePreferredDarkTheme])
        let light = themeStore.info(for: settings[.appearancePreferredLightTheme])
        if let dark, let light, dark.id == light.id { return [AccentTarget(info: dark, mode: nil)] }
        return [
            dark.map { AccentTarget(info: $0, mode: "Dark Mode") },
            light.map { AccentTarget(info: $0, mode: "Light Mode") },
        ].compactMap { $0 }
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

/// A theme's accent choices: its own accent ("Default") and the other colors
/// it ships, as round swatches. Picking one recolors everything that uses
/// the accent in that theme only.
private struct AccentRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    let palette: AccentPalette
    /// "Dark Mode" or "Light Mode" when both preferred themes are shown.
    let mode: String?

    var body: some View {
        let choice = AccentActions.choice(in: palette, settings: app.settings)
        SettingsRow(mode.map { "\($0) accent" } ?? "Accent color", detail: detail(for: choice)) {
            HStack(spacing: 2) {
                ForEach(palette.swatches) { swatch in
                    AccentSwatchButton(swatch: swatch, isSelected: choice.swatch == swatch) {
                        AccentActions.select(swatch, in: palette, settings: app.settings)
                    }
                    if swatch.isDefault, palette.swatches.count > 1 {
                        SettingsHairline(vertical: true)
                            .frame(height: 16)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(palette.themeName) accent color")
        }
    }

    private func detail(for choice: AccentChoice) -> String {
        if case .custom = choice {
            return "settings.json sets a different accent for \(palette.themeName)."
        }
        if palette.swatches.count < 2 {
            return "\(palette.themeName) has no other colors that work as an accent."
        }
        return "Choose from \(palette.themeName)'s own colors."
    }
}

/// A theme's message box border colors: its own border ("Default"), its
/// quiet neutrals, its accent and other colors, then Custom… for any color.
/// The color shows focused or not.
private struct MessageBoxBorderColorRow: View {
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.theme) private var theme
    let palette: MessageBoxBorderPalette
    let info: ThemeInfo
    /// "Dark Mode" or "Light Mode" when both preferred themes are shown.
    let mode: String?

    var body: some View {
        let choice = MessageBoxBorderActions.choice(in: palette, settings: app.settings)
        SettingsRow(mode.map { "\($0) border color" } ?? "Border color", detail: detail(for: choice)) {
            HStack(spacing: 2) {
                ForEach(palette.swatches) { swatch in
                    AccentSwatchButton(
                        color: swatch.color,
                        title: swatch.title,
                        accessibilityLabel: swatch.accessibilityLabel,
                        isSelected: choice.swatch == swatch
                    ) {
                        MessageBoxBorderActions.select(swatch, in: palette, settings: app.settings)
                    }
                    if swatch.isDefault { divider }
                }
                divider
                customWell(choice: choice)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(palette.themeName) message box border color")
        }
    }

    private var divider: some View {
        SettingsHairline(vertical: true)
            .frame(height: 16)
            .padding(.horizontal, 4)
    }

    /// A color well for any color, ringed when the color is one of no swatch.
    private func customWell(choice: MessageBoxBorderChoice) -> some View {
        var isCustom = false
        if case .custom = choice { isCustom = true }
        // The panel starts from the border as it's drawn now.
        let current: ThemeColor = switch choice {
        case .custom(let color): color
        case .swatch(let swatch) where !swatch.isDefault: swatch.color
        case .swatch: themeStore.resolvedTheme(for: info)?.color(ThemeKey.inputBorder) ?? palette.defaultSwatch.color
        }
        return HStack(spacing: 6) {
            Text("Custom…")
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .fixedSize()
                .accessibilityHidden(true)
            ColorPicker(
                "Custom border color",
                selection: Binding(
                    get: { current.color },
                    set: { MessageBoxBorderActions.select(ThemeColor(swiftUIColor: $0), in: palette, settings: app.settings) }
                ),
                supportsOpacity: true
            )
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .padding(3)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isCustom ? theme[ThemeKey.settingsForeground] : .clear, lineWidth: 2)
            )
            .help("Any color")
            .accessibilityAddTraits(isCustom ? .isSelected : [])
        }
    }

    private func detail(for choice: MessageBoxBorderChoice) -> String {
        if case .custom = choice, !MessageBoxBorderActions.hasPickedColor(in: palette, settings: app.settings) {
            return "settings.json sets input.border for \(palette.themeName)."
        }
        return "\(palette.themeName)'s own colors, or any color. Shown while you type, too."
    }
}

/// One round color swatch, ringed when selected.
private struct AccentSwatchButton: View {
    @Environment(\.theme) private var theme
    let color: ThemeColor
    let title: String
    let accessibilityLabel: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(color: ThemeColor, title: String, accessibilityLabel: String, isSelected: Bool, action: @escaping () -> Void) {
        self.color = color
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.isSelected = isSelected
        self.action = action
    }

    init(swatch: AccentSwatch, isSelected: Bool, action: @escaping () -> Void) {
        self.init(color: swatch.color, title: swatch.title, accessibilityLabel: swatch.accessibilityLabel, isSelected: isSelected, action: action)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isSelected ? theme[ThemeKey.settingsForeground] : (isHovered ? theme[ThemeKey.settingsSecondaryForeground].opacity(0.5) : .clear),
                        lineWidth: 2
                    )
                Circle()
                    .fill(color.color)
                    .overlay(Circle().strokeBorder(theme[ThemeKey.settingsBorder], lineWidth: 1))
                    .padding(4)
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
