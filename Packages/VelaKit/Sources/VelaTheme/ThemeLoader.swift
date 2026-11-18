// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// Reads Vela theme files (JSON with comments and trailing commas).
public enum ThemeLoader {
    /// File extensions recognized as theme files.
    public static let fileExtensions: Set<String> = ["json", "jsonc"]

    /// A theme file that loaded, and what in it was skipped.
    public struct Checked: Sendable {
        public let definition: ThemeDefinition
        /// Unknown keys and tokens, and values left out (see `ThemeProblems`).
        public let problems: [ThemeProblem]
    }

    /// Loads and validates a theme file.
    public static func load(contentsOf url: URL) throws -> ThemeDefinition {
        try loadChecked(contentsOf: url).definition
    }

    /// Loads and validates a theme file, also reporting typos and values
    /// that were skipped. Throws only for problems that stop the theme from
    /// loading (bad JSON, a missing name or type, a malformed color).
    public static func loadChecked(contentsOf url: URL) throws -> Checked {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ThemeError.unreadable(path: url.lastPathComponent, reason: error.localizedDescription)
        }
        return try decodeChecked(data)
    }

    /// Decodes and validates theme JSON(C).
    public static func decode(_ data: Data) throws -> ThemeDefinition {
        try decodeChecked(data).definition
    }

    /// Decodes and validates theme JSON(C), also reporting typos and values
    /// that were skipped.
    public static func decodeChecked(_ data: Data) throws -> Checked {
        let definition: ThemeDefinition
        do {
            definition = try JSONC.decode(ThemeDefinition.self, from: data)
        } catch {
            throw ThemeError.from(decoding: error)
        }
        try definition.validate()
        return Checked(definition: definition, problems: ThemeProblems.check(data))
    }

    /// The theme id for a file: its name without the extension.
    public static func themeID(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// The bundled `BuiltInThemes` folder.
    public static var builtInThemesDirectory: URL {
        Bundle.module.url(forResource: "BuiltInThemes", withExtension: nil)
            ?? Bundle.module.bundleURL.appendingPathComponent("BuiltInThemes", isDirectory: true)
    }

    /// Theme files directly inside `directory`, sorted by file name. URLs are
    /// built from `directory` as given (symlinks such as /var → /private/var
    /// aren't resolved), so they compare equal to URLs callers construct.
    public static func themeFiles(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { !$0.hasPrefix(".") && fileExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { directory.appendingPathComponent($0, isDirectory: false) }
    }

    /// Loads every theme in `directory`, collecting per-file errors instead of
    /// stopping at the first one, and the problems in the files that loaded.
    public static func loadDirectory(_ directory: URL) -> (
        themes: [(url: URL, definition: ThemeDefinition)],
        errors: [URL: String],
        problems: [URL: [ThemeProblem]]
    ) {
        var themes: [(url: URL, definition: ThemeDefinition)] = []
        var errors: [URL: String] = [:]
        var problems: [URL: [ThemeProblem]] = [:]
        for url in themeFiles(in: directory) {
            do {
                let checked = try loadChecked(contentsOf: url)
                themes.append((url, checked.definition))
                if !checked.problems.isEmpty { problems[url] = checked.problems }
            } catch {
                errors[url] = error.localizedDescription
            }
        }
        return (themes, errors, problems)
    }

    /// Every bundled theme, keyed by id. Loaded once.
    public static var builtInDefinitions: [String: ThemeDefinition] { BuiltInCache.shared.definitions }

    /// A bundled theme by id or (case-insensitive) name.
    public static func builtInDefinition(named reference: String) throws -> ThemeDefinition? {
        let definitions = builtInDefinitions
        if let match = definitions.first(where: { $0.key.caseInsensitiveCompare(reference) == .orderedSame }) {
            return match.value
        }
        return definitions.values.first { $0.name.caseInsensitiveCompare(reference) == .orderedSame }
    }

    private final class BuiltInCache: Sendable {
        static let shared = BuiltInCache()
        let definitions: [String: ThemeDefinition]

        init() {
            var result: [String: ThemeDefinition] = [:]
            for (url, definition) in ThemeLoader.loadDirectory(ThemeLoader.builtInThemesDirectory).themes {
                result[ThemeLoader.themeID(for: url)] = definition
            }
            definitions = result
        }
    }
}
