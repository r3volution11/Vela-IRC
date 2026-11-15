// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import ZIPFoundation

/// Converts VS Code color themes (`*-color-theme.json`, JSONC) and `.vsix`
/// extensions into Vela theme definitions. The result is an ordinary,
/// editable Vela theme: workbench colors are mapped onto Vela tokens, the
/// terminal ANSI colors become mIRC colors 0–15 and the nick palette.
public enum VSCodeThemeImporter {
    /// Imports one VS Code color theme file. `include`s can't be followed
    /// without the rest of the extension, so they're ignored here; use
    /// `importVSIX(at:)` for themes that include other files.
    public static func importTheme(data: Data, fileName: String) throws -> ThemeDefinition {
        try importTheme(data: data, path: fileName, label: nil, uiTheme: nil, author: nil) { _, _ in nil }
    }

    /// Imports every JSON color theme contributed by a `.vsix` extension.
    public static func importVSIX(at url: URL) throws -> [ThemeDefinition] {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ThemeError.unreadable(path: url.lastPathComponent, reason: "it isn't a valid .vsix (zip) file.")
        }

        func read(_ path: String) -> Data? {
            guard let entry = archive[path] else { return nil }
            var data = Data()
            do {
                _ = try archive.extract(entry, skipCRC32: false) { chunk in data.append(chunk) }
            } catch {
                return nil
            }
            return data
        }

        guard let manifestData = read("extension/package.json") else { throw ThemeError.vsixManifestMissing }
        let manifest: JSONValue
        do {
            manifest = try JSONC.value(from: manifestData)
        } catch {
            throw ThemeError.from(decoding: error)
        }
        let strings = read("extension/package.nls.json").flatMap { try? JSONC.value(from: $0) }
        func localized(_ text: String?) -> String? {
            guard let text, text.count > 2, text.hasPrefix("%"), text.hasSuffix("%") else { return text }
            return strings?[String(text.dropFirst().dropLast())]?.stringValue ?? text
        }

        let author = manifest["author"]?.stringValue
            ?? manifest["author"]?["name"]?.stringValue
            ?? localized(manifest["publisher"]?.stringValue)

        var results: [ThemeDefinition] = []
        for theme in manifest["contributes"]?["themes"]?.arrayValue ?? [] {
            guard let relative = theme["path"]?.stringValue else { continue }
            let path = normalize("extension/" + relative)
            guard ThemeLoader.fileExtensions.contains((path as NSString).pathExtension.lowercased()),
                  let data = read(path)
            else { continue }
            let definition = try importTheme(
                data: data,
                path: path,
                label: localized(theme["label"]?.stringValue) ?? localized(theme["id"]?.stringValue),
                uiTheme: theme["uiTheme"]?.stringValue,
                author: author
            ) { include, from in
                let target = normalize(((from as NSString).deletingLastPathComponent as NSString).appendingPathComponent(include))
                return read(target).map { ($0, target) }
            }
            results.append(definition)
        }
        guard !results.isEmpty else { throw ThemeError.vsixNoThemes }
        return results
    }

    /// Whether parsed JSON looks like a VS Code color theme rather than a
    /// Vela theme.
    public static func looksLikeVSCodeTheme(_ value: JSONValue) -> Bool {
        guard let object = value.objectValue else { return false }
        if let schema = object["$schema"]?.stringValue {
            if schema.contains("vela-theme") { return false }
            if schema.hasPrefix("vscode://") { return true }
        }
        if object["tokenColors"] != nil || object["semanticTokenColors"] != nil { return true }
        if let type = object["type"]?.stringValue, vscodeOnlyTypes.contains(type) { return true }
        let keys = object["colors"]?.objectValue.map { Array($0.keys) } ?? []
        return keys.contains { key in vscodeOnlyPrefixes.contains { key.hasPrefix($0) } }
    }

    private static let vscodeOnlyTypes: Set<String> = ["vs", "vs-dark", "hc-black", "hc-light"]

    private static let vscodeOnlyPrefixes = [
        "editor.", "editorGroup", "sideBar", "activityBar", "statusBar", "terminal.", "list.", "tab.",
        "panel.", "minimap", "breadcrumb", "gitDecoration", "debugToolBar", "notifications",
    ]

    // MARK: - Parsing

    private struct SourceTheme {
        var name: String?
        var type: String?
        var author: String?
        var colors: [String: ThemeColor] = [:]
        /// Every token foreground in file order (duplicates kept for ranking).
        var tokenForegrounds: [ThemeColor] = []
    }

    typealias IncludeResolver = (_ include: String, _ fromPath: String) -> (Data, String)?

    static func importTheme(
        data: Data,
        path: String,
        label: String?,
        uiTheme: String?,
        author: String?,
        includeResolver: IncludeResolver
    ) throws -> ThemeDefinition {
        let source = try parse(data: data, path: path, includeResolver: includeResolver, depth: 0)
        let fileName = (path as NSString).lastPathComponent
        let name = nonEmpty(label) ?? nonEmpty(source.name) ?? displayName(forFile: fileName)
        return convert(source, name: name, uiTheme: uiTheme, author: author ?? source.author, fileName: fileName)
    }

    private static func parse(data: Data, path: String, includeResolver: IncludeResolver, depth: Int) throws -> SourceTheme {
        let json: JSONValue
        do {
            json = try JSONC.value(from: data)
        } catch {
            throw ThemeError.from(decoding: error)
        }
        guard json.objectValue != nil, json["colors"] != nil || json["tokenColors"] != nil || json["include"] != nil else {
            throw ThemeError.notAVSCodeTheme((path as NSString).lastPathComponent)
        }

        var theme = SourceTheme()
        if let include = json["include"]?.stringValue, depth < 8, let (includedData, includedPath) = includeResolver(include, path) {
            theme = try parse(data: includedData, path: includedPath, includeResolver: includeResolver, depth: depth + 1)
        }
        theme.name = json["name"]?.stringValue ?? theme.name
        theme.type = json["type"]?.stringValue ?? theme.type
        theme.author = json["author"]?.stringValue ?? theme.author

        for (key, value) in json["colors"]?.objectValue ?? [:] {
            if let hex = value.stringValue, let color = ThemeColor(hex: hex) {
                theme.colors[key] = color
            } else if value == .null {
                theme.colors[key] = nil
            }
        }
        for rule in json["tokenColors"]?.arrayValue ?? [] {
            if let hex = rule["settings"]?["foreground"]?.stringValue, let color = ThemeColor(hex: hex) {
                theme.tokenForegrounds.append(color)
            }
        }
        for (_, value) in json["semanticTokenColors"]?.objectValue ?? [:] {
            let hex = value.stringValue ?? value["foreground"]?.stringValue
            if let hex, let color = ThemeColor(hex: hex) {
                theme.tokenForegrounds.append(color)
            }
        }
        return theme
    }

    // MARK: - Conversion

    /// Vela token ← VS Code keys, first present wins.
    private static let mapping: [(vela: String, sources: [String])] = [
        (ThemeKey.windowBackground, ["editor.background"]),
        (ThemeKey.windowForeground, ["editor.foreground", "foreground"]),
        (ThemeKey.titleBarBackground, ["titleBar.activeBackground"]),
        (ThemeKey.titleBarForeground, ["titleBar.activeForeground"]),
        (ThemeKey.titleBarSecondaryForeground, ["titleBar.inactiveForeground"]),
        (ThemeKey.titleBarBorder, ["titleBar.border"]),
        (ThemeKey.sidebarBackground, ["sideBar.background"]),
        (ThemeKey.sidebarForeground, ["sideBar.foreground"]),
        (ThemeKey.sidebarBorder, ["sideBar.border"]),
        (ThemeKey.sidebarHeaderForeground, ["sideBarSectionHeader.foreground", "sideBarTitle.foreground"]),
        (ThemeKey.sidebarHoverBackground, ["list.hoverBackground"]),
        (ThemeKey.sidebarActiveBackground, ["list.activeSelectionBackground", "list.inactiveSelectionBackground"]),
        (ThemeKey.sidebarActiveForeground, ["list.activeSelectionForeground"]),
        (ThemeKey.sidebarBadgeBackground, ["badge.background"]),
        (ThemeKey.sidebarBadgeForeground, ["badge.foreground"]),
        (ThemeKey.sidebarHighlightBadgeBackground, ["activityBarBadge.background"]),
        (ThemeKey.sidebarHighlightBadgeForeground, ["activityBarBadge.foreground"]),
        (ThemeKey.sidebarDisconnectedForeground, ["disabledForeground"]),
        (ThemeKey.railBackground, ["activityBar.background"]),
        (ThemeKey.railForeground, ["activityBar.foreground"]),
        (ThemeKey.railInactiveForeground, ["activityBar.inactiveForeground"]),
        (ThemeKey.railActiveBackground, ["activityBar.activeBackground"]),
        (ThemeKey.railActiveIndicator, ["activityBar.activeBorder"]),
        (ThemeKey.railBadgeBackground, ["activityBarBadge.background"]),
        (ThemeKey.railBadgeForeground, ["activityBarBadge.foreground"]),
        (ThemeKey.railBorder, ["activityBar.border"]),
        (ThemeKey.chatBackground, ["editor.background"]),
        (ThemeKey.chatForeground, ["editor.foreground", "foreground"]),
        (ThemeKey.chatSecondaryForeground, ["descriptionForeground"]),
        (ThemeKey.chatTimestamp, ["editorLineNumber.foreground"]),
        (ThemeKey.chatLink, ["textLink.foreground"]),
        (ThemeKey.chatHighlightBackground, ["editor.findMatchHighlightBackground", "editor.wordHighlightBackground"]),
        (ThemeKey.chatSelectionBackground, ["editor.selectionBackground"]),
        (ThemeKey.chatFindMatchBackground, ["editor.findMatchBackground"]),
        (ThemeKey.chatHoverBackground, ["editor.lineHighlightBackground"]),
        (ThemeKey.chatCodeBackground, ["textCodeBlock.background"]),
        (ThemeKey.chatCodeForeground, ["textPreformat.foreground"]),
        (ThemeKey.inputBackground, ["input.background"]),
        (ThemeKey.inputForeground, ["input.foreground"]),
        (ThemeKey.inputPlaceholder, ["input.placeholderForeground"]),
        (ThemeKey.inputBorder, ["input.border"]),
        (ThemeKey.focusBorder, ["focusBorder"]),
        (ThemeKey.buttonBackground, ["button.background"]),
        (ThemeKey.buttonForeground, ["button.foreground"]),
        (ThemeKey.buttonHoverBackground, ["button.hoverBackground"]),
        (ThemeKey.buttonSecondaryBackground, ["button.secondaryBackground"]),
        (ThemeKey.buttonSecondaryForeground, ["button.secondaryForeground"]),
        (ThemeKey.scrollbarThumb, ["scrollbarSlider.background"]),
        (ThemeKey.scrollbarThumbHover, ["scrollbarSlider.hoverBackground"]),
        (ThemeKey.popoverBackground, ["editorWidget.background", "quickInput.background", "editorHoverWidget.background", "menu.background"]),
        (ThemeKey.popoverForeground, ["editorWidget.foreground", "quickInput.foreground", "menu.foreground"]),
        (ThemeKey.popoverBorder, ["editorWidget.border", "editorHoverWidget.border", "menu.border", "widget.border"]),
        (ThemeKey.replyQuoteBar, ["textBlockQuote.border"]),
        (ThemeKey.statusSuccess, ["terminal.ansiGreen", "gitDecoration.addedResourceForeground"]),
        (ThemeKey.statusWarning, ["editorWarning.foreground", "terminal.ansiYellow"]),
        (ThemeKey.statusError, ["editorError.foreground", "errorForeground", "terminal.ansiRed"]),
    ]

    /// Lines that should be skipped when (nearly) invisible so a later
    /// candidate gets a chance.
    private static let visibleMapping: [(vela: String, sources: [String])] = [
        (ThemeKey.paneDivider, ["editorGroup.border", "panel.border", "sideBar.border", "contrastBorder"]),
        (ThemeKey.windowBorder, ["window.activeBorder", "contrastBorder"]),
    ]

    /// Surfaces that must be opaque; translucent values are flattened onto
    /// the editor background.
    private static let opaqueKeys: Set<String> = [
        ThemeKey.windowBackground, ThemeKey.chatBackground, ThemeKey.sidebarBackground, ThemeKey.railBackground,
        ThemeKey.titleBarBackground, ThemeKey.popoverBackground, ThemeKey.buttonBackground,
        ThemeKey.sidebarHighlightBadgeBackground, ThemeKey.railBadgeBackground, ThemeKey.accent,
    ]

    /// Foreground ← background pairs with a minimum contrast. Mapped
    /// foregrounds that fail are dropped so Vela derives a readable one.
    private static let contrastGuards: [(foreground: String, background: String, minimum: Double)] = [
        (ThemeKey.chatSecondaryForeground, ThemeKey.chatBackground, 3.0),
        (ThemeKey.chatTimestamp, ThemeKey.chatBackground, 2.5),
        (ThemeKey.chatLink, ThemeKey.chatBackground, 3.0),
        (ThemeKey.chatCodeForeground, ThemeKey.chatCodeBackground, 4.5),
        (ThemeKey.sidebarForeground, ThemeKey.sidebarBackground, 3.5),
        (ThemeKey.sidebarHeaderForeground, ThemeKey.sidebarBackground, 3.0),
        (ThemeKey.sidebarActiveForeground, ThemeKey.sidebarActiveBackground, 3.5),
        (ThemeKey.sidebarBadgeForeground, ThemeKey.sidebarBadgeBackground, 3.0),
        (ThemeKey.sidebarHighlightBadgeForeground, ThemeKey.sidebarHighlightBadgeBackground, 3.0),
        (ThemeKey.sidebarDisconnectedForeground, ThemeKey.sidebarBackground, 1.8),
        (ThemeKey.railForeground, ThemeKey.railBackground, 3.0),
        (ThemeKey.railInactiveForeground, ThemeKey.railBackground, 1.8),
        (ThemeKey.railBadgeForeground, ThemeKey.railBadgeBackground, 3.0),
        (ThemeKey.titleBarForeground, ThemeKey.titleBarBackground, 3.5),
        (ThemeKey.titleBarSecondaryForeground, ThemeKey.titleBarBackground, 2.5),
        (ThemeKey.inputForeground, ThemeKey.inputBackground, 4.5),
        (ThemeKey.inputPlaceholder, ThemeKey.inputBackground, 2.2),
        (ThemeKey.buttonForeground, ThemeKey.buttonBackground, 3.0),
        (ThemeKey.buttonSecondaryForeground, ThemeKey.buttonSecondaryBackground, 3.0),
        (ThemeKey.popoverForeground, ThemeKey.popoverBackground, 4.5),
        (ThemeKey.statusSuccess, ThemeKey.chatBackground, 3.0),
        (ThemeKey.statusWarning, ThemeKey.chatBackground, 3.0),
        (ThemeKey.statusError, ThemeKey.chatBackground, 3.0),
    ]

    /// Accent candidates, best first, with the foreground VS Code pairs them with.
    private static let accentCandidates: [(key: String, foreground: String?)] = [
        ("activityBarBadge.background", "activityBarBadge.foreground"),
        ("activityBar.activeBorder", nil),
        ("button.background", "button.foreground"),
        ("focusBorder", nil),
        ("progressBar.background", nil),
        ("tab.activeBorderTop", nil),
        ("tab.activeBorder", nil),
        ("panelTitle.activeBorder", nil),
        ("textLink.foreground", nil),
        ("editorCursor.foreground", nil),
    ]

    /// mIRC 0–15 ← ANSI, in the mapping most terminal IRC clients use.
    private static let ircFromANSI: [(index: Int, sources: [String])] = [
        (0, ["terminal.ansiBrightWhite", "terminal.ansiWhite"]),
        (1, ["terminal.ansiBlack"]),
        (2, ["terminal.ansiBlue"]),
        (3, ["terminal.ansiGreen"]),
        (4, ["terminal.ansiBrightRed", "terminal.ansiRed"]),
        (5, ["terminal.ansiRed"]),
        (6, ["terminal.ansiMagenta"]),
        (7, ["terminal.ansiYellow"]),
        (8, ["terminal.ansiBrightYellow", "terminal.ansiYellow"]),
        (9, ["terminal.ansiBrightGreen", "terminal.ansiGreen"]),
        (10, ["terminal.ansiCyan"]),
        (11, ["terminal.ansiBrightCyan", "terminal.ansiCyan"]),
        (12, ["terminal.ansiBrightBlue", "terminal.ansiBlue"]),
        (13, ["terminal.ansiBrightMagenta", "terminal.ansiMagenta"]),
        (14, ["terminal.ansiBrightBlack"]),
        (15, ["terminal.ansiWhite"]),
    ]

    private static let chromaticANSI = [
        "terminal.ansiRed", "terminal.ansiGreen", "terminal.ansiYellow", "terminal.ansiBlue",
        "terminal.ansiMagenta", "terminal.ansiCyan", "terminal.ansiBrightRed", "terminal.ansiBrightGreen",
        "terminal.ansiBrightYellow", "terminal.ansiBrightBlue", "terminal.ansiBrightMagenta", "terminal.ansiBrightCyan",
    ]

    private static func convert(
        _ source: SourceTheme,
        name: String,
        uiTheme: String?,
        author: String?,
        fileName: String
    ) -> ThemeDefinition {
        let vs = source.colors
        let background = vs["editor.background"].map { $0.composited(over: .black) }
        let kind = source.type.flatMap(ThemeKind.init(lenient:))
            ?? uiTheme.flatMap(ThemeKind.init(lenient:))
            ?? background.map { $0.isDark ? .dark : .light }
            ?? .dark
        let base = background
            ?? ResolvedTheme.registryDefaults(kind).color(ThemeKey.chatBackground)

        var colors: [String: ThemeColor] = [:]
        for (vela, sources) in mapping {
            if let match = sources.lazy.compactMap({ vs[$0] }).first {
                colors[vela] = opaqueKeys.contains(vela) ? match.composited(over: base) : match
            }
        }
        for (vela, sources) in visibleMapping {
            if let match = sources.lazy.compactMap({ vs[$0] }).first(where: { $0.alpha >= 0.1 }) {
                colors[vela] = match
            }
        }

        // Accent: the first saturated, opaque-enough candidate that stands out
        // from the background.
        if let candidate = accentCandidates.first(where: { candidate in
            guard let color = vs[candidate.key], color.alpha >= 0.5 else { return false }
            let flat = color.composited(over: base)
            return flat.chroma >= 0.05 && flat.contrastRatio(against: base) >= 1.4
        }) {
            let accent = vs[candidate.key]!.composited(over: base)
            colors[ThemeKey.accent] = accent
            if let pair = candidate.foreground.flatMap({ vs[$0] }),
               pair.contrastRatio(against: accent) >= 3 {
                colors[ThemeKey.accentForeground] = pair
            }
        } else if let fromTokens = rankedTokenColors(source.tokenForegrounds, background: base).first {
            colors[ThemeKey.accent] = fromTokens
        }
        // Accent-as-text (links, own nick, mentions) must stay readable.
        if let accent = colors[ThemeKey.accent], accent.contrastRatio(against: base) < 4.5 {
            if let link = colors[ThemeKey.chatLink], link.contrastRatio(against: base) >= 4.5 {
                colors[ThemeKey.accentText] = link
            } else {
                colors[ThemeKey.accentText] = accent.ensuringContrast(4.5, against: base)
            }
        }

        // Drop mapped foregrounds that would be hard to read and let Vela
        // derive them instead.
        var resolved = ThemeResolver.resolveColors(kind: kind, explicit: colors)
        for guardrail in contrastGuards {
            guard let foreground = colors[guardrail.foreground] else { continue }
            let surface = resolved[guardrail.background]!.composited(over: resolved[ThemeKey.chatBackground]!)
            if foreground.contrastRatio(against: surface) < guardrail.minimum {
                colors[guardrail.foreground] = nil
                resolved = ThemeResolver.resolveColors(kind: kind, explicit: colors)
            }
        }
        let chatBackground = resolved[ThemeKey.chatBackground]!

        // mIRC 0–15 from the terminal palette, when the theme has one.
        var ircColors: [String: String]?
        if chromaticANSI.filter({ vs[$0] != nil }).count >= 4 {
            var mapped: [String: String] = [:]
            for (index, sources) in ircFromANSI {
                if let color = sources.lazy.compactMap({ vs[$0] }).first {
                    mapped[String(index)] = color.composited(over: chatBackground).hex
                }
            }
            ircColors = mapped
        }

        // Nick palette: chromatic ANSI colors, topped up from syntax colors.
        var nickColors: [ThemeColor] = []
        func add(_ color: ThemeColor) {
            let readable = color.composited(over: chatBackground).ensuringContrast(3.5, against: chatBackground)
            guard readable.chroma >= 0.04,
                  !nickColors.contains(where: { $0.distance(to: readable) < 0.05 })
            else { return }
            nickColors.append(readable)
        }
        for key in chromaticANSI {
            if let color = vs[key] { add(color) }
        }
        if nickColors.count < 8 {
            for color in rankedTokenColors(source.tokenForegrounds, background: chatBackground) where nickColors.count < 12 {
                add(color)
            }
        }

        var definition = ThemeDefinition(
            name: name,
            type: kind,
            author: nonEmpty(author),
            description: "Imported from the VS Code theme “\(name)” (\(fileName)).",
            colors: colors.mapValues(\.hex)
        )
        if nickColors.count >= 4 {
            definition.nickColors = nickColors.map(\.hex)
        }
        definition.ircColors = ircColors
        return definition
    }

    /// Distinct, saturated syntax colors, most used first.
    private static func rankedTokenColors(_ colors: [ThemeColor], background: ThemeColor) -> [ThemeColor] {
        var counts: [String: (color: ThemeColor, count: Int, first: Int)] = [:]
        for (offset, color) in colors.enumerated() {
            let flat = color.composited(over: background)
            guard flat.chroma >= 0.05 else { continue }
            let key = flat.hex
            if let existing = counts[key] {
                counts[key] = (existing.color, existing.count + 1, existing.first)
            } else {
                counts[key] = (flat, 1, offset)
            }
        }
        let ranked = counts.values.sorted { ($1.count, $0.first) < ($0.count, $1.first) }.map(\.color)
        var distinct: [ThemeColor] = []
        for color in ranked where !distinct.contains(where: { $0.distance(to: color) < 0.06 }) {
            distinct.append(color)
        }
        return distinct
    }

    // MARK: - Helpers

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// `tokyo-night-color-theme.json` → `Tokyo Night`.
    static func displayName(forFile fileName: String) -> String {
        var stem = (fileName as NSString).deletingPathExtension
        for suffix in ["-color-theme", "_color_theme", "-theme", ".color-theme"] where stem.lowercased().hasSuffix(suffix) {
            stem = String(stem.dropLast(suffix.count))
            break
        }
        let words = stem.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
        let name = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return name.isEmpty ? "Imported Theme" : name
    }

    /// Resolves `.` and `..` segments in a zip entry path.
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }
}
