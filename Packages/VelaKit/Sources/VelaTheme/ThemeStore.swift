// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaFoundation

/// Owns the theme list, the active `ResolvedTheme`, live reload of the user
/// Themes folder and system light/dark following.
///
/// The app sets `settings` from settings.json; `current` re-resolves
/// whenever settings, the system appearance, a user theme file or the editor
/// `draft` changes.
@MainActor
@Observable
public final class ThemeStore {
    /// Built-in themes plus user themes, sorted by name. A user theme with
    /// the same id as a built-in replaces it.
    public private(set) var themes: [ThemeInfo] = []

    /// The theme views should draw with.
    public private(set) var current: ResolvedTheme

    /// The `ThemeInfo` behind `current` (`nil` while showing a draft or a
    /// fallback).
    public private(set) var currentInfo: ThemeInfo?

    /// Theme files that failed to load or resolve, with a readable message.
    /// A user theme that breaks while being edited keeps its last good
    /// version in `themes` and gets an entry here until it's fixed.
    public private(set) var loadErrors: [URL: String] = [:]

    /// Problems in `settings.colorCustomizations` (unknown tokens, bad colors).
    public private(set) var customizationProblems: [String] = []

    /// Why `draft` couldn't be resolved, if it couldn't (e.g. a missing include).
    public private(set) var draftError: String?

    /// The system's light/dark setting, used when following the system.
    public private(set) var systemAppearance: ThemeKind

    /// Theme settings from settings.json. Changing them re-resolves `current`.
    public var settings: ThemeSettings {
        didSet {
            guard settings != oldValue else { return }
            if settings.colorCustomizations != oldValue.colorCustomizations {
                customizationProblems = ThemeOverrides.problems(in: settings.colorCustomizations)
                resolvedCache.removeAll()
            }
            refresh()
        }
    }

    /// The theme editor's working copy. While non-nil, `current` shows it
    /// (live preview, without the user's color customizations).
    public var draft: ThemeDefinition? {
        didSet {
            guard draft != oldValue else { return }
            refresh()
        }
    }

    public let userThemesDirectory: URL

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var builtIns: [String: Entry] = [:]
    @ObservationIgnored private var userDefinitions: [URL: ThemeDefinition] = [:]
    @ObservationIgnored private var resolvedCache: [String: ResolvedTheme] = [:]
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var appearanceObservation: SystemAppearance.Observation?
    @ObservationIgnored private var builtInsLoaded = false
    @ObservationIgnored private var builtInErrors: [URL: String] = [:]

    private struct Entry {
        let info: ThemeInfo
        let definition: ThemeDefinition
    }

    /// The user Themes folder inside the app's sandbox container:
    /// `~/Library/Containers/<bundle id>/Data/Library/Application Support/Vela/Themes`.
    public static var defaultUserThemesDirectory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Vela", isDirectory: true)
            .appendingPathComponent("Themes", isDirectory: true)
    }

    public init(
        userThemesDirectory: URL,
        settings: ThemeSettings = .default,
        systemAppearance: ThemeKind = SystemAppearance.current
    ) {
        self.userThemesDirectory = userThemesDirectory
        self.settings = settings
        self.systemAppearance = systemAppearance
        let kind = settings.followSystemAppearance ? systemAppearance : .dark
        self.current = ResolvedTheme.fallback(for: kind)
        self.customizationProblems = ThemeOverrides.problems(in: settings.colorCustomizations)
    }

    // MARK: - Lifecycle

    /// Loads all themes, then watches the user folder for changes (live
    /// reload) and follows the system light/dark setting. Safe to call twice.
    public func start() {
        reload()
        guard watcher == nil else { return }
        let watcher = FileWatcher(directory: userThemesDirectory) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadUserThemes()
            }
        }
        watcher.start()
        self.watcher = watcher
        appearanceObservation = SystemAppearance.observe { [weak self] kind in
            self?.updateSystemAppearance(kind)
        }
    }

    /// Stops watching the folder and the system appearance.
    public func stop() {
        watcher?.stop()
        watcher = nil
        appearanceObservation = nil
    }

    /// Reloads built-in and user themes from disk.
    public func reload() {
        loadBuiltInsIfNeeded()
        reloadUserThemes()
    }

    /// Tells the store the system appearance changed. `start()` observes
    /// this automatically; call it yourself only if you track appearance
    /// some other way.
    public func updateSystemAppearance(_ kind: ThemeKind) {
        guard kind != systemAppearance else { return }
        systemAppearance = kind
        if settings.followSystemAppearance { refresh() }
    }

    // MARK: - Lookup

    /// Finds a theme by id, then by name (case-insensitive). User themes win.
    public func info(for reference: String) -> ThemeInfo? {
        let reference = reference.trimmingCharacters(in: .whitespaces)
        return themes.first { $0.id.caseInsensitiveCompare(reference) == .orderedSame }
            ?? themes.first { $0.source == .user && $0.name.caseInsensitiveCompare(reference) == .orderedSame }
            ?? themes.first { $0.name.caseInsensitiveCompare(reference) == .orderedSame }
    }

    /// The parsed file behind a theme.
    public func definition(for info: ThemeInfo) throws -> ThemeDefinition {
        if let entry = entries[info.id], entry.info.url == info.url { return entry.definition }
        if let entry = builtIns[info.id], entry.info.url == info.url { return entry.definition }
        return try ThemeLoader.load(contentsOf: info.url)
    }

    /// A theme resolved with the user's color customizations, e.g. for
    /// previews in a theme picker. `nil` if it can't be resolved (see
    /// `loadErrors`). Cached until themes or settings change.
    public func resolvedTheme(for info: ThemeInfo) -> ResolvedTheme? {
        if let cached = resolvedCache[info.id] { return cached }
        guard let entry = entries[info.id] else { return nil }
        let overrides = ThemeOverrides(
            customizations: settings.colorCustomizations,
            themeName: info.name,
            themeID: info.id
        )
        guard let theme = try? ThemeResolver.resolve(
            entry.definition,
            id: info.id,
            includeLoader: includeLoader(for: info),
            overrides: overrides
        ) else { return nil }
        resolvedCache[info.id] = theme
        return theme
    }

    /// A definition with its `include` chain merged in, e.g. to start a new
    /// theme in the editor from an existing one.
    public func flattenedDefinition(for info: ThemeInfo) throws -> ThemeDefinition {
        try ThemeResolver.flatten(definition(for: info), includeLoader: includeLoader(for: info))
    }

    // MARK: - Writing

    /// Imports a `.json` theme (Vela or VS Code, detected automatically) or
    /// a `.vsix` extension into the user Themes folder. Names that clash
    /// with existing themes get an “(Imported)” suffix.
    @discardableResult
    public func importTheme(from url: URL) throws -> [ThemeInfo] {
        let definitions: [ThemeDefinition]
        switch url.pathExtension.lowercased() {
        case "vsix":
            definitions = try VSCodeThemeImporter.importVSIX(at: url)
        case "json", "jsonc":
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw ThemeError.unreadable(path: url.lastPathComponent, reason: error.localizedDescription)
            }
            let value: JSONValue
            do {
                value = try JSONC.value(from: data)
            } catch {
                throw ThemeError.from(decoding: error)
            }
            if VSCodeThemeImporter.looksLikeVSCodeTheme(value) {
                definitions = [try VSCodeThemeImporter.importTheme(data: data, fileName: url.lastPathComponent)]
            } else {
                definitions = [try ThemeLoader.decode(data)]
            }
        default:
            throw ThemeError.unsupportedFile(url.lastPathComponent)
        }

        try ensureUserDirectory()
        var takenNames = Set(themes.map { $0.name.lowercased() })
        var takenIDs = Set(themes.map { $0.id.lowercased() })
            .union(ThemeLoader.themeFiles(in: userThemesDirectory).map { ThemeLoader.themeID(for: $0).lowercased() })
        var written: [URL] = []
        for var definition in definitions {
            definition.name = Self.uniqueName(definition.name, taken: takenNames)
            definition.schema = definition.schema ?? ThemeDefinition.schemaURL
            takenNames.insert(definition.name.lowercased())
            let id = Self.uniqueID(Self.slug(definition.name), taken: takenIDs)
            takenIDs.insert(id)
            let fileURL = userThemesDirectory.appendingPathComponent("\(id).json")
            try write(definition, to: fileURL)
            written.append(fileURL)
        }
        reloadUserThemes()
        return written.compactMap { url in themes.first { $0.url == url } }
    }

    /// Saves a theme into the user folder, overwriting the user theme with
    /// the same name if there is one. Returns its `ThemeInfo`.
    @discardableResult
    public func saveUserTheme(_ definition: ThemeDefinition) throws -> ThemeInfo {
        try definition.validate()
        try ensureUserDirectory()
        var definition = definition
        definition.schema = definition.schema ?? ThemeDefinition.schemaURL

        let fileURL: URL
        if let existing = userDefinitions.first(where: { $0.value.name.caseInsensitiveCompare(definition.name) == .orderedSame }) {
            fileURL = existing.key
        } else {
            let takenIDs = Set(ThemeLoader.themeFiles(in: userThemesDirectory).map { ThemeLoader.themeID(for: $0).lowercased() })
            let id = Self.uniqueID(Self.slug(definition.name), taken: takenIDs)
            fileURL = userThemesDirectory.appendingPathComponent("\(id).json")
        }
        try write(definition, to: fileURL)
        reloadUserThemes()
        guard let info = themes.first(where: { $0.url == fileURL }) else {
            throw ThemeError.unreadable(path: fileURL.lastPathComponent, reason: loadErrors[fileURL] ?? "it couldn't be loaded after saving.")
        }
        return info
    }

    /// Deletes a user theme file.
    public func deleteUserTheme(_ info: ThemeInfo) throws {
        guard info.source == .user else { throw ThemeError.notAUserTheme(info.name) }
        try FileManager.default.removeItem(at: info.url)
        reloadUserThemes()
    }

    // MARK: - Loading

    private func loadBuiltInsIfNeeded() {
        guard !builtInsLoaded else { return }
        builtInsLoaded = true
        let (loaded, errors) = ThemeLoader.loadDirectory(ThemeLoader.builtInThemesDirectory)
        for (url, definition) in loaded {
            let id = ThemeLoader.themeID(for: url)
            let info = ThemeInfo(id: id, name: definition.name, kind: definition.type, source: .builtIn, url: url)
            builtIns[id] = Entry(info: info, definition: definition)
        }
        builtInErrors = errors
    }

    /// Rescans the user folder. Files that fail to parse keep their last
    /// good version and get an entry in `loadErrors`.
    func reloadUserThemes() {
        loadBuiltInsIfNeeded()
        var errors = builtInErrors
        var definitions: [URL: ThemeDefinition] = [:]
        for url in ThemeLoader.themeFiles(in: userThemesDirectory) {
            do {
                definitions[url] = try ThemeLoader.load(contentsOf: url)
            } catch {
                errors[url] = error.localizedDescription
                if let lastGood = userDefinitions[url] { definitions[url] = lastGood }
            }
        }
        userDefinitions = definitions

        var next = builtIns
        for (url, definition) in definitions {
            let id = ThemeLoader.themeID(for: url)
            let info = ThemeInfo(id: id, name: definition.name, kind: definition.type, source: .user, url: url)
            next[id] = Entry(info: info, definition: definition)
        }
        entries = next

        // Report broken includes up front rather than when a theme is picked.
        for entry in next.values where entry.info.source == .user && errors[entry.info.url] == nil {
            do {
                _ = try ThemeResolver.flatten(entry.definition, includeLoader: includeLoader(for: entry.info))
            } catch {
                errors[entry.info.url] = error.localizedDescription
            }
        }

        let sorted = next.values.map(\.info).sorted {
            switch $0.name.localizedCaseInsensitiveCompare($1.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.id < $1.id
            }
        }
        if themes != sorted { themes = sorted }
        if loadErrors != errors { loadErrors = errors }
        resolvedCache.removeAll()
        refresh()
    }

    /// Looks up included themes for `info`: user themes (other than itself)
    /// first, then built-ins, by id then name. A path ending in `.json` is
    /// resolved relative to the user Themes folder.
    private func includeLoader(for info: ThemeInfo?) -> (String) throws -> ThemeDefinition? {
        let entries = self.entries
        let builtIns = self.builtIns
        let directory = userThemesDirectory
        return { reference in
            if ThemeLoader.fileExtensions.contains((reference as NSString).pathExtension.lowercased()) {
                let url = reference.hasPrefix("/")
                    ? URL(fileURLWithPath: reference)
                    : directory.appendingPathComponent(reference)
                return try ThemeLoader.load(contentsOf: url)
            }
            let candidates = entries.values.filter { $0.info.url != info?.url }
                + builtIns.values.filter { $0.info.url != info?.url }
            return candidates.first { $0.info.id.caseInsensitiveCompare(reference) == .orderedSame }?.definition
                ?? candidates.first { $0.info.name.caseInsensitiveCompare(reference) == .orderedSame }?.definition
        }
    }

    // MARK: - Resolution

    private func refresh() {
        if let draft {
            do {
                let theme = try ThemeResolver.resolve(
                    draft,
                    id: "draft-\(Self.slug(draft.name))",
                    includeLoader: includeLoader(for: currentInfo),
                    overrides: .none
                )
                if draftError != nil { draftError = nil }
                setCurrent(theme, info: nil)
            } catch {
                draftError = error.localizedDescription
            }
            return
        }
        if draftError != nil { draftError = nil }

        let reference = settings.themeReference(systemAppearance: systemAppearance)
        let wanted = info(for: reference)
        let kind = wanted?.kind ?? (settings.followSystemAppearance ? systemAppearance : .dark)
        let fallbackName = kind == .dark ? ThemeSettings.defaultDarkTheme : ThemeSettings.defaultLightTheme
        for candidate in [wanted, info(for: fallbackName)].compactMap({ $0 }) {
            if let theme = resolvedTheme(for: candidate) {
                setCurrent(theme, info: candidate)
                return
            }
        }
        setCurrent(.fallback(for: kind), info: nil)
    }

    private func setCurrent(_ theme: ResolvedTheme, info: ThemeInfo?) {
        if current != theme { current = theme }
        if currentInfo != info { currentInfo = info }
    }

    // MARK: - Files

    private func ensureUserDirectory() throws {
        do {
            try FileManager.default.createDirectory(at: userThemesDirectory, withIntermediateDirectories: true)
        } catch {
            throw ThemeError.unreadable(path: userThemesDirectory.path, reason: error.localizedDescription)
        }
    }

    private func write(_ definition: ThemeDefinition, to url: URL) throws {
        do {
            try definition.jsonData().write(to: url, options: .atomic)
        } catch {
            throw ThemeError.unreadable(path: url.lastPathComponent, reason: error.localizedDescription)
        }
    }

    /// `Rosé Pine Moon` → `rose-pine-moon`.
    static func slug(_ name: String) -> String {
        let latin = name.applyingTransform(.toLatin, reverse: false) ?? name
        let plain = latin.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .init(identifier: "en_US_POSIX"))
        var result = ""
        for scalar in plain.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                result.unicodeScalars.append(scalar)
            } else if !result.hasSuffix("-"), !result.isEmpty {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "theme" : result
    }

    static func uniqueID(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base.lowercased()) else { return base }
        var counter = 2
        while taken.contains("\(base)-\(counter)".lowercased()) { counter += 1 }
        return "\(base)-\(counter)"
    }

    static func uniqueName(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base.lowercased()) else { return base }
        let imported = "\(base) (Imported)"
        guard taken.contains(imported.lowercased()) else { return imported }
        var counter = 2
        while taken.contains("\(base) (Imported \(counter))".lowercased()) { counter += 1 }
        return "\(base) (Imported \(counter))"
    }
}
