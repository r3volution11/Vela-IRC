// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaUI

@Suite("What's New: changelog and launch")
struct WhatsNewUITests {
    static let changelog = """
        # Changelog

        Intro paragraph.

        ## Unreleased

        ## 1.2.0 - 2027-02-03

        Short intro with a [link](https://example.com).

        ### Privacy

        - **Bold start.** A sentence that
          continues on the next line.
          - A nested point with `code`.
        - See the [roadmap](ROADMAP.md) and the [guide](/guide/chat-logs).

        1. First step
        2. Second step

        ## [1.1.0] - 2027-01-10

        ### Fixes

        - Something fixed.
        """

    // MARK: Sections

    @Test func sectionsInOrder() {
        let sections = Changelog.sections(in: Self.changelog)
        #expect(sections.map(\.version) == ["Unreleased", "1.2.0", "1.1.0"])
        #expect(sections[1].date == "2027-02-03")
        #expect(sections[2].date == "2027-01-10")
        #expect(sections[0].body.isEmpty)
        #expect(sections[2].body == "### Fixes\n\n- Something fixed.")
    }

    @Test func sectionForTheVersion() {
        let section = Changelog.section(for: "1.1.0", in: Self.changelog)
        #expect(section?.version == "1.1.0")
        #expect(section?.body.contains("Something fixed.") == true)
    }

    @Test func fallsBackToTheNewestSectionWithEntries() {
        // No 1.3.0 yet, and Unreleased is empty.
        #expect(Changelog.section(for: "1.3.0", in: Self.changelog)?.version == "1.2.0")
        // A development build: Unreleased has what's coming.
        let withUnreleased = Self.changelog.replacingOccurrences(of: "## Unreleased\n", with: "## Unreleased\n\n- Coming soon.\n")
        #expect(Changelog.section(for: "1.3.0", in: withUnreleased)?.version == "Unreleased")
        #expect(Changelog.section(for: "1.0.0", in: "# Changelog\n\nNothing yet.") == nil)
    }

    // MARK: Blocks

    @Test func blocksAndNesting() throws {
        let body = try #require(Changelog.section(for: "1.2.0", in: Self.changelog)).body
        let blocks = Changelog.blocks(from: body)
        #expect(blocks == [
            .paragraph("Short intro with a [link](https://example.com)."),
            .heading(level: 3, text: "Privacy"),
            .item(level: 0, marker: nil, text: "**Bold start.** A sentence that continues on the next line."),
            .item(level: 1, marker: nil, text: "A nested point with `code`."),
            .item(level: 0, marker: nil, text: "See the [roadmap](ROADMAP.md) and the [guide](/guide/chat-logs)."),
            .item(level: 0, marker: "1.", text: "First step"),
            .item(level: 0, marker: "2.", text: "Second step"),
        ])
    }

    @Test func inlineMarkdownAndLinks() {
        let text = Changelog.inline("**Bold** and `code`, the [roadmap](ROADMAP.md), the [guide](/guide/chat-logs) and [a site](https://example.com).")
        #expect(String(text.characters) == "Bold and code, the roadmap, the guide and a site.")
        let links = text.runs.compactMap(\.link).map(\.absoluteString)
        #expect(links == [
            "https://github.com/r3volution11/Vela-IRC/blob/main/ROADMAP.md",
            "https://velairc.app/guide/chat-logs",
            "https://example.com",
        ])
        let bold = text.runs.first { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        #expect(bold.map { String(text[$0.range].characters) } == "Bold")
    }

    // MARK: The bundled changelog

    @Test func bundledChangelogIsTheRepositorys() throws {
        let bundled = try #require(Changelog.bundledText())
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "CHANGELOG.md")
        #expect(bundled == (try String(contentsOf: repository, encoding: .utf8)))
        let released = try #require(Changelog.section(for: "1.0.0", in: bundled))
        #expect(released.date == "2026-11-18")
        #expect(!Changelog.blocks(from: released.body).isEmpty)
    }

    @Test func windowContent() {
        let exact = WhatsNewContent.make(version: "1.2.0", changelog: Self.changelog)
        #expect(exact.version == "1.2.0")
        // "February 3, 2027", in the Mac's language.
        #expect(exact.subtitle?.contains("2027") == true)
        #expect(exact.subtitle != "2027-02-03")
        #expect(exact.blocks.count == 7)
        #expect(exact.displayBlocks.count == 7)

        let fallback = WhatsNewContent.make(version: "1.3.0", changelog: Self.changelog)
        #expect(fallback.subtitle == "Notes from Vela 1.2.0")

        let missing = WhatsNewContent.make(version: "1.3.0", changelog: nil)
        #expect(missing.blocks.isEmpty)
        #expect(Changelog.fullChangelogURL.absoluteString == "https://velairc.app/changelog")
    }

    // MARK: Launch

    @MainActor
    @Test func automationRunsNeverShowIt() {
        let plain = ["/Applications/Vela.app/Contents/MacOS/Vela"]
        #expect(!WhatsNewLaunch.isSuppressed(isDemo: false, arguments: plain, environment: [:]))
        #expect(WhatsNewLaunch.isSuppressed(isDemo: true, arguments: plain, environment: [:]))
        for flags in [["--demo"], ["--demo", "--snapshot", "/tmp/a.png"], ["--demo", "--scroll-benchmark"], ["--bench-output", "x"], ["--settings-pane", "messages"]] {
            #expect(WhatsNewLaunch.isSuppressed(isDemo: false, arguments: plain + flags, environment: [:]), "\(flags)")
        }
        #expect(WhatsNewLaunch.isSuppressed(isDemo: false, arguments: plain, environment: ["XCTestConfigurationFilePath": "/x"]))
    }
}
