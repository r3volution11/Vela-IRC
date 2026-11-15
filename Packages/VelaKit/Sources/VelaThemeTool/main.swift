// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import VelaTheme

let usage = """
    Usage: vela-theme-tool <command> [arguments]

    Commands:
      schema                     Print the JSON Schema for theme files
                                 (schemas/vela-theme.schema.json).
      customizations-schema      Print the JSON Schema for settings colorCustomizations.
      tokens                     Print the Markdown token reference (docs/THEMES.md).
      check [theme ...]          Resolve themes (built-in ids/names or file paths;
                                 default: all built-ins) and report contrast.
                                 Exits 1 if any check fails. Add --verbose to list passes.
      import <file>              Convert a VS Code theme (.json) or extension (.vsix)
                                 to Vela theme JSON on stdout.
      preview <theme> <out.png>  Render a mock Vela window using the theme.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Resolves a theme given a file path or a built-in id/name.
func loadTheme(_ reference: String) throws -> ResolvedTheme {
    let url = URL(fileURLWithPath: reference)
    let definition: ThemeDefinition
    let id: String
    if FileManager.default.fileExists(atPath: url.path) {
        definition = try ThemeLoader.load(contentsOf: url)
        id = ThemeLoader.themeID(for: url)
    } else if let builtIn = try ThemeLoader.builtInDefinition(named: reference) {
        definition = builtIn
        id = ThemeLoader.builtInDefinitions.first { $0.value == builtIn }?.key ?? reference
    } else {
        throw ThemeError.includeNotFound(reference)
    }
    return try ThemeResolver.resolve(definition, id: id, includeLoader: { reference in
        let sibling = url.deletingLastPathComponent().appendingPathComponent(reference)
        if FileManager.default.fileExists(atPath: sibling.path) {
            return try ThemeLoader.load(contentsOf: sibling)
        }
        return try ThemeLoader.builtInDefinition(named: reference)
    }, overrides: [:])
}

var arguments = Array(CommandLine.arguments.dropFirst())
let verbose = arguments.contains("--verbose")
arguments.removeAll { $0 == "--verbose" }

switch arguments.first {
case "schema":
    print(ThemeSchema.themeFileSchemaJSON(), terminator: "")

case "customizations-schema":
    let data = (try? ThemeSchema.colorCustomizationsSchema().prettyPrinted()) ?? Data()
    print(String(decoding: data, as: UTF8.self))

case "tokens":
    print(ThemeSchema.markdownTokenTable(), terminator: "")

case "check":
    var references = Array(arguments.dropFirst())
    if references.isEmpty {
        references = ThemeLoader.builtInDefinitions.keys.sorted()
    }
    var failures = 0
    for reference in references {
        do {
            let theme = try loadTheme(reference)
            let findings = ThemeAudit.audit(theme)
            let failed = findings.filter { !$0.passes }
            failures += failed.count
            let body = theme.color(ThemeKey.chatForeground).contrastRatio(against: theme.color(ThemeKey.chatBackground))
            print(String(format: "%@ %@ (%@, body %.2f:1)", failed.isEmpty ? "✓" : "✗", theme.name, theme.kind.rawValue, body))
            for finding in findings where verbose || !finding.passes {
                print("    \(finding.passes ? " " : "!") \(finding)")
            }
        } catch {
            failures += 1
            print("✗ \(reference): \(error.localizedDescription)")
        }
    }
    exit(failures == 0 ? 0 : 1)

case "import":
    guard arguments.count == 2 else { fail(usage) }
    let url = URL(fileURLWithPath: arguments[1])
    do {
        let definitions: [ThemeDefinition]
        if url.pathExtension.lowercased() == "vsix" {
            definitions = try VSCodeThemeImporter.importVSIX(at: url)
        } else {
            definitions = [try VSCodeThemeImporter.importTheme(data: Data(contentsOf: url), fileName: url.lastPathComponent)]
        }
        for definition in definitions {
            print(String(decoding: definition.jsonData(), as: UTF8.self), terminator: "")
        }
    } catch {
        fail(error.localizedDescription)
    }

case "preview":
    guard arguments.count == 3 else { fail(usage) }
    do {
        let theme = try loadTheme(arguments[1])
        try renderPreview(theme, to: URL(fileURLWithPath: arguments[2]))
    } catch {
        fail(error.localizedDescription)
    }

default:
    fail(usage)
}
