// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// CHANGELOG.md, as bundled with the app (Resources/CHANGELOG.md is a
/// link to the repository's own, so it's always the one being released),
/// and the parts What's New shows.
enum Changelog {
    /// Where "Full changelog" goes.
    static let fullChangelogURL = URL(string: "https://velairc.app/changelog")!
    /// Relative links in the changelog are to files in the repository.
    static let repositoryURL = URL(string: "https://github.com/r3volution11/Vela-IRC/blob/main/")!
    static let websiteURL = URL(string: "https://velairc.app")!

    /// The bundled CHANGELOG.md, or nil if it's missing.
    static func bundledText() -> String? {
        guard let url = Bundle.module.url(forResource: "CHANGELOG", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// One `## ` section: `## 1.0.0 - 2026-11-18`, or `## Unreleased`.
    struct Section: Equatable {
        /// `1.0.0`, or `Unreleased`.
        var version: String
        /// `2026-11-18`, when the heading has one.
        var date: String?
        /// The markdown under the heading, trimmed.
        var body: String
    }

    /// Every `## ` section, newest first (as written).
    static func sections(in markdown: String) -> [Section] {
        var sections: [Section] = []
        var heading: String?
        var body: [Substring] = []
        func finish() {
            guard let heading else { return }
            let (version, date) = parseHeading(heading)
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(Section(version: version, date: date, body: text))
        }
        var inFence = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```") { inFence.toggle() }
            if !inFence, line.hasPrefix("## ") {
                finish()
                heading = String(line.dropFirst(3))
                body = []
            } else if heading != nil {
                body.append(line)
            }
        }
        finish()
        return sections
    }

    /// `"[1.0.0] - 2026-11-18"` → `("1.0.0", "2026-11-18")`.
    private static func parseHeading(_ heading: String) -> (version: String, date: String?) {
        let parts = heading.split(separator: " - ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let version = (parts.first ?? heading).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return (version, parts.count > 1 ? parts[1] : nil)
    }

    /// The section for `version`; failing that, the newest section with
    /// something in it (a build whose version has no section yet).
    static func section(for version: String, in markdown: String) -> Section? {
        let all = sections(in: markdown)
        return all.first { $0.version == version && !$0.body.isEmpty } ?? all.first { !$0.body.isEmpty }
    }

    // MARK: Blocks

    /// What a section's markdown is drawn as.
    enum Block: Equatable {
        /// `### Privacy` (level 3) and deeper.
        case heading(level: Int, text: String)
        case paragraph(String)
        /// A list item; `level` 0 is the outermost list. `marker` is nil for
        /// a bullet, or the number of a numbered item (`"1."`).
        case item(level: Int, marker: String?, text: String)
    }

    /// Splits `markdown` into headings, paragraphs and list items. Inline
    /// markdown (bold, links, code) is left for ``inline(_:)``. Lines that
    /// continue a paragraph or item are joined to it.
    static func blocks(from markdown: String) -> [Block] {
        var blocks: [Block] = []
        var current: Block?
        func flush() {
            if let current { blocks.append(current) }
            current = nil
        }
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                continue
            }
            if let level = headingLevel(trimmed) {
                flush()
                blocks.append(.heading(level: level, text: String(trimmed.dropFirst(level + 1))))
                continue
            }
            let indent = line.prefix(while: { $0 == " " }).count
            if let (marker, text) = listItem(trimmed) {
                flush()
                current = .item(level: indent / 2, marker: marker, text: text)
                continue
            }
            // A continuation line.
            switch current {
            case .paragraph(let text): current = .paragraph(text + " " + trimmed)
            case .item(let level, let marker, let text): current = .item(level: level, marker: marker, text: text + " " + trimmed)
            default: current = .paragraph(trimmed)
            }
        }
        flush()
        return blocks
    }

    /// 3 for `### Title`, nil for anything that isn't a heading.
    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    /// `- text` and `* text` (bullets), `1. text` (numbered).
    private static func listItem(_ line: String) -> (marker: String?, text: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return (nil, String(line.dropFirst(2)))
        }
        let digits = line.prefix(while: \.isNumber)
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return ("\(digits).", String(line.dropFirst(digits.count + 2)))
        }
        return nil
    }

    // MARK: Inline markdown

    /// Bold, italics, code and links, as an `AttributedString`. Relative
    /// links point at the website (`/guide/…`) or the repository
    /// (`ROADMAP.md`). Text that isn't valid markdown is shown as written.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard var string = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        for run in string.runs {
            guard let link = run.link, link.scheme == nil else { continue }
            string[run.range].link = resolve(link.relativeString)
        }
        return string
    }

    /// A relative link from the changelog, made absolute.
    static func resolve(_ link: String) -> URL? {
        if link.hasPrefix("/") { return URL(string: link, relativeTo: websiteURL)?.absoluteURL }
        if link.hasPrefix("#") { return URL(string: link, relativeTo: fullChangelogURL)?.absoluteURL }
        return URL(string: link, relativeTo: repositoryURL)?.absoluteURL
    }
}
