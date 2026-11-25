// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import CryptoKit
import Foundation
import Testing
import VelaCore
import VelaIntents
import VelaStore
@testable import VelaUI

/// Settings → Integrations: where it sits, what each card says for what's
/// installed, the bundled Alfred workflow against its record, and the
/// palette's commands.
@MainActor
@Suite("Integrations")
struct IntegrationsTests {
    /// The repository, from this file's place in it.
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // VelaUITests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // VelaKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository

    private func app(_ version: String?) -> InstalledApp {
        InstalledApp(url: URL(fileURLWithPath: "/Applications/Some.app"), version: version)
    }

    // MARK: The pane

    @Test func thePaneIsRightAfterTheAIPanes() throws {
        #expect(SettingsPane.integrations.title == "Integrations")
        #expect(SettingsPane.groups.contains([.intelligence, .aiProviders, .aiPrivacy, .integrations]))
        #expect(SettingsPane.groups.flatMap { $0 } == SettingsPane.allCases)
        // Its settings (Spotlight's) belong to Intelligence in settings.json,
        // so the pane has no "Show in settings editor" link of its own.
        #expect(SettingsCategory.categories(forPane: SettingsPane.integrations.rawValue).isEmpty)
    }

    // MARK: Alfred

    @Test func alfredsStatusSaysWhatsInstalled() {
        let ready = AlfredWorkflow.status(alfred: app("6.0"), workflowVersion: "1.0.0", isBundled: true)
        #expect(ready == IntegrationStatus(.ready, "Alfred 6 is installed", detail: "Workflow 1.0.0 included"))
        let old = AlfredWorkflow.status(alfred: app("4.8.1"), workflowVersion: "1.0.0", isBundled: true)
        #expect(old.kind == .attention)
        #expect(old.text == "Alfred 4 is installed; the workflow needs Alfred 5 or later")
        let missing = AlfredWorkflow.status(alfred: nil, workflowVersion: nil, isBundled: true)
        #expect(missing == IntegrationStatus(.missing, "Alfred isn't installed"))
        let notBundled = AlfredWorkflow.status(alfred: app("5.8.1"), workflowVersion: nil, isBundled: false)
        #expect(notBundled.detail == "The workflow isn't in this build")
        // An Alfred whose version can't be read gets the benefit of the doubt.
        #expect(AlfredWorkflow.supports(app(nil)))
        #expect(AlfredWorkflow.name(of: app(nil)) == "Alfred")
        #expect(AlfredWorkflow.supports(app("5.0")))
        #expect(!AlfredWorkflow.supports(app("4.8.1")))
    }

    /// The bundled workflow is the file integrations/alfred-workflow.json
    /// records, as CI's `scripts/update-alfred-workflow.sh --check` checks,
    /// and the pane reads its version from the file itself.
    @Test func theBundledWorkflowMatchesItsRecord() throws {
        let workflow = Self.repository.appending(path: "Vela/Integrations/Vela.alfredworkflow")
        let recordData = try Data(contentsOf: Self.repository.appending(path: "integrations/alfred-workflow.json"))
        let record = try #require(try JSONSerialization.jsonObject(with: recordData) as? [String: Any])
        let sha = SHA256.hash(data: try Data(contentsOf: workflow)).map { String(format: "%02x", $0) }.joined()
        #expect(sha == record["sha256"] as? String)
        let version = try #require(AlfredWorkflow.version(ofWorkflowAt: workflow))
        #expect(version == record["version"] as? String)
        #expect(AlfredWorkflow.version(ofWorkflowAt: Self.repository.appending(path: "README.md")) == nil)
    }

    // MARK: Raycast

    @Test func raycastsStoreLinkAndStatus() {
        #expect(RaycastExtension.storeURL(raycastInstalled: true).absoluteString == "raycast://extensions/r3volution11/vela-irc")
        #expect(RaycastExtension.storeURL(raycastInstalled: false).absoluteString == "https://www.raycast.com/r3volution11/vela-irc")
        #expect(RaycastExtension.status(raycast: app("1.90"), isInStore: false) == IntegrationStatus(.ready, "Raycast is installed", detail: "Coming to the Raycast Store"))
        #expect(RaycastExtension.status(raycast: nil, isInStore: true) == IntegrationStatus(.missing, "Raycast isn't installed"))
    }

    // MARK: Looking apps up

    @Test func appsAreLookedUpOnlyWhenAsked() {
        var asked: [String] = []
        let apps = IntegrationApps { bundleID in
            asked.append(bundleID)
            return bundleID == AlfredWorkflow.bundleID ? InstalledApp(url: URL(fileURLWithPath: "/Applications/Alfred 5.app"), version: "5.8.1") : nil
        }
        #expect(asked.isEmpty)
        apps.refresh()
        #expect(Set(asked) == [
            AlfredWorkflow.bundleID, RaycastExtension.bundleID, ShortcutsIntegration.bundleID,
            SpotlightIntegration.bundleID, AppleScriptIntegration.scriptEditorBundleID,
        ])
        #expect(apps.alfred?.majorVersion == 5)
        #expect(apps.raycast == nil)
    }

    // MARK: Shortcuts and Siri

    /// Every App Shortcut's action is listed, and every example phrase is
    /// one of the App Shortcuts' phrases (Vela/VelaShortcuts.swift).
    @Test func shortcutsListWhatTheAppOffers() throws {
        let source = try String(contentsOf: Self.repository.appending(path: "Vela/VelaShortcuts.swift"), encoding: .utf8)
        let listed = Set(ShortcutsIntegration.actionTypes.map { String(describing: $0) })
        let shortcutIntents = source.matches(of: /intent: (\w+)\(\)/).map { String($0.1) }
        #expect(!shortcutIntents.isEmpty)
        for intent in shortcutIntents {
            #expect(listed.contains(intent), "\(intent) isn't listed")
        }
        #expect(ShortcutsIntegration.actionTitles.contains("Catch Me Up"))
        #expect(ShortcutsIntegration.actionTitles.count == ShortcutsIntegration.actionTypes.count)

        // "Open \(\.$target) in \(.applicationName)" matches "Open #vela on Libera.Chat in Vela".
        let templates = source.matches(of: /"([^"\n]*\\\(\.applicationName\)[^"\n]*)"/).map { String($0.1) }
        #expect(templates.count > 20)
        let patterns = try templates.map { template in
            let named = template.replacingOccurrences(of: "\\(.applicationName)", with: "Vela")
            let literals = named.split(separator: /\\\(\\\.\$\w+\)/, omittingEmptySubsequences: false)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
            return try NSRegularExpression(pattern: "^" + literals.joined(separator: ".+") + "$")
        }
        for phrase in ShortcutsIntegration.phrases {
            let range = NSRange(phrase.startIndex..., in: phrase)
            #expect(patterns.contains { $0.firstMatch(in: phrase, range: range) != nil }, "“\(phrase)” isn't an App Shortcut phrase")
        }
    }

    // MARK: AppleScript and links

    @Test func linkExamplesAreLinksVelaFollows() throws {
        #expect(AppleScriptIntegration.linkScheme == "vela")
        for scheme in ["vela", "vela-dev"] {
            let examples = AppleScriptIntegration.linkExamples(scheme: scheme)
            #expect(examples.count == 4)
            for example in examples {
                let url = try #require(URL(string: example.link))
                #expect(url.scheme == scheme)
                #expect(VelaLink.parse(url) != nil, "\(example.link)")
            }
        }
        #expect(AppleScriptIntegration.linkExamples().first?.link == "vela://open?channel=%23vela&network=Libera.Chat")
    }

    // MARK: Commands

    @Test func paletteCommands() throws {
        var shown = 0
        var installed: [InstalledApp] = []
        var storeOpened = 0
        var alfred: InstalledApp?
        func commands(bundled: Bool = true, inStore: Bool = false) -> [VelaCommand] {
            VelaCommandCatalog.integrationCommands(
                isWorkflowBundled: bundled,
                isRaycastInStore: inStore,
                findAlfred: { alfred },
                showPane: { shown += 1 },
                installWorkflow: { installed.append($0) },
                openRaycastStore: { storeOpened += 1 }
            )
        }
        let list = commands()
        #expect(list.map(\.paletteTitle) == ["Settings: Integrations", "Integrations: Install Alfred Workflow…"])
        let pane = try #require(list.first)
        pane.perform()
        #expect(shown == 1)

        // Without Alfred 5 or later, installing shows the pane, with Get Alfred.
        let install = try #require(list.last)
        install.perform()
        #expect(shown == 2 && installed.isEmpty)
        alfred = app("4.8.1")
        install.perform()
        #expect(shown == 3 && installed.isEmpty)
        alfred = app("6.0")
        install.perform()
        #expect(installed == [app("6.0")])

        #expect(commands(bundled: false).last?.isEnabled == false)
        let withStore = commands(inStore: true)
        #expect(withStore.map(\.paletteTitle).last == "Integrations: Open in Raycast Store")
        withStore.last?.perform()
        #expect(storeOpened == 1)
        // Until the extension is in the Store, there's no command for it.
        #expect(!RaycastExtension.isInStore || commands(inStore: true).count == 3)
    }

    @Test func paletteFindsIntegrationsByToolName() throws {
        let list = VelaCommandCatalog.integrationCommands(showPane: {}, installWorkflow: { _ in }, openRaycastStore: {})
        let pane = try #require(list.first { $0.id == "settings.integrations" })
        for word in ["alfred", "raycast", "spotlight", "applescript"] {
            #expect(pane.keywords.contains(word))
        }
    }
}

@MainActor
extension LinkSelectionTests {
    /// Settings → Integrations in an offscreen window, used as VoiceOver
    /// would. Whether Alfred or Raycast is installed depends on the Mac, so
    /// only what's always there is checked.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Integrations pane, hosted", .serialized)
    struct IntegrationsPaneHostedTests {
        @Test func everyCardHasItsControls() async throws {
            let host = try await PresetsPaneHost(theme: "Palenight", size: CGSize(width: 820, height: 2200), pane: .integrations)
            defer { host.close() }
            for tool in ["Alfred", "Raycast", "Shortcuts and Siri", "Spotlight", "AppleScript and vela:// links"] {
                #expect(host.element(labeled: "Learn more about \(tool)") != nil, "\(tool)")
            }
            #expect(host.element(labeled: "Install Workflow…") != nil || host.element(labeled: "Get Alfred") != nil)
            #expect(host.element(labeled: "Source code of the workflow") != nil)
            #expect(host.element(labeled: "Open Shortcuts") != nil)
            #expect(host.element(labeled: "Show channels in Spotlight") != nil)
            #expect(host.element(labeled: "Search messages in Spotlight") != nil)
            #expect(host.element(labeled: "Open Dictionary") != nil)
            #expect(host.element(labeled: "Copy link: Show #vela on Libera.Chat") != nil)
        }
    }
}
