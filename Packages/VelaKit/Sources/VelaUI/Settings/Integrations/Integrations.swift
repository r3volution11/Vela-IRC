// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import AppKit
import Observation
import VelaIntents
import ZIPFoundation

// What Settings → Integrations knows about the tools that work with Vela:
// which apps are installed, the Alfred workflow the app carries, the Raycast
// extension, and the actions their buttons and the palette's commands run.
// Everything here is sandbox-safe: Launch Services lookups, opening files
// and links with NSWorkspace, and reading the app's own bundle.

// MARK: - Installed apps

/// An installed app another tool belongs to, as Launch Services knows it.
struct InstalledApp: Equatable {
    let url: URL
    /// `CFBundleShortVersionString`, such as "5.8.1".
    let version: String?

    /// The version's first number: 5 for "5.8.1".
    var majorVersion: Int? {
        version.flatMap { Int($0.prefix { $0.isNumber }) }
    }

    /// The app with `bundleID`: the copy that's running, if one is (so a
    /// Mac with two versions uses the one you use), else the one Launch
    /// Services prefers. Nil if it isn't installed.
    static func find(_ bundleID: String) -> InstalledApp? {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL
        guard let url = running ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return InstalledApp(url: url, version: Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String)
    }
}

/// The apps Settings → Integrations shows, looked up when the pane appears
/// and when Vela becomes active again (you may have just installed one),
/// never on a timer. A lookup asks Launch Services' database and reads
/// the app's Info.plist: well under a millisecond each.
@MainActor
@Observable
final class IntegrationApps {
    private(set) var alfred: InstalledApp?
    private(set) var raycast: InstalledApp?
    private(set) var shortcuts: InstalledApp?
    private(set) var spotlight: InstalledApp?
    private(set) var scriptEditor: InstalledApp?

    @ObservationIgnored private let find: @MainActor (String) -> InstalledApp?

    init(find: @escaping @MainActor (String) -> InstalledApp? = InstalledApp.find) {
        self.find = find
    }

    func refresh() {
        update(\.alfred, AlfredWorkflow.bundleID)
        update(\.raycast, RaycastExtension.bundleID)
        update(\.shortcuts, ShortcutsIntegration.bundleID)
        update(\.spotlight, SpotlightIntegration.bundleID)
        update(\.scriptEditor, AppleScriptIntegration.scriptEditorBundleID)
    }

    /// Writes only a change, so the pane isn't redrawn for nothing.
    private func update(_ keyPath: ReferenceWritableKeyPath<IntegrationApps, InstalledApp?>, _ bundleID: String) {
        let app = find(bundleID)
        if self[keyPath: keyPath] != app { self[keyPath: keyPath] = app }
    }
}

// MARK: - Alfred

/// The Alfred workflow, from github.com/r3volution11/vela-alfred-workflow.
/// The app carries a built copy (Vela/Integrations/Vela.alfredworkflow,
/// refreshed with scripts/update-alfred-workflow.sh), which Install
/// Workflow opens in Alfred; Alfred then shows its own import sheet.
enum AlfredWorkflow {
    /// Alfred 4, 5 and 6 share it.
    static let bundleID = "com.runningwithcrayons.Alfred"
    /// The workflow needs Alfred 5 or later (and the Powerpack, which
    /// Vela can't see).
    static let minimumMajorVersion = 5
    static let getAlfredURL = URL(string: "https://www.alfredapp.com")!
    static let repositoryURL = URL(string: "https://github.com/r3volution11/vela-alfred-workflow")!
    static let guideURL = URL(string: "https://velairc.app/guide/alfred-and-raycast#alfred")!

    /// The workflow in the app's Resources, if this build has it.
    static var bundledURL: URL? {
        Bundle.main.url(forResource: "Vela", withExtension: "alfredworkflow")
    }

    /// Whether `alfred` can run the workflow. An Alfred whose version can't
    /// be read gets the benefit of the doubt.
    static func supports(_ alfred: InstalledApp) -> Bool {
        (alfred.majorVersion ?? minimumMajorVersion) >= minimumMajorVersion
    }

    /// "Alfred 6", or just "Alfred".
    static func name(of alfred: InstalledApp) -> String {
        alfred.majorVersion.map { "Alfred \($0)" } ?? "Alfred"
    }

    /// The `version` in a workflow's info.plist. The workflow is a zip
    /// archive; only its info.plist is read.
    nonisolated static func version(ofWorkflowAt url: URL) -> String? {
        guard let archive = try? Archive(url: url, accessMode: .read),
              let entry = archive["info.plist"],
              entry.uncompressedSize < 4_000_000
        else { return nil }
        var data = Data()
        guard (try? archive.extract(entry, skipCRC32: false) { data.append($0) }) != nil,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["version"] as? String
    }

    /// The bundled workflow's version, read once, off the main actor.
    static func bundledVersion() async -> String? {
        if let cached = cachedVersion { return cached }
        guard let url = bundledURL else { return nil }
        let version = await Task.detached(priority: .utility) { version(ofWorkflowAt: url) }.value
        cachedVersion = version
        return version
    }

    @MainActor private static var cachedVersion: String?

    /// Opens the workflow in `alfred`, which asks before importing it (and
    /// offers to update a copy you already have). Alfred reads it straight
    /// from the app's Resources; nothing is copied. Calls `completion` with
    /// what went wrong, if anything.
    static func install(with alfred: InstalledApp, completion: @escaping @MainActor (String?) -> Void = { _ in }) {
        guard let workflow = bundledURL else {
            completion("This copy of Vela doesn't include the workflow.")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let failure = "\(name(of: alfred)) couldn't open the workflow"
        NSWorkspace.shared.open([workflow], withApplicationAt: alfred.url, configuration: configuration) { _, error in
            let message = error.map { "\(failure): \($0.localizedDescription)" }
            Task { @MainActor in completion(message) }
        }
    }

    /// What the card's status line says.
    static func status(alfred: InstalledApp?, workflowVersion: String?, isBundled: Bool) -> IntegrationStatus {
        let workflow = isBundled ? workflowVersion.map { "Workflow \($0) included" } : "The workflow isn't in this build"
        guard let alfred else { return IntegrationStatus(.missing, "Alfred isn't installed", detail: workflow) }
        guard supports(alfred) else {
            return IntegrationStatus(.attention, "\(name(of: alfred)) is installed; the workflow needs Alfred \(minimumMajorVersion) or later", detail: workflow)
        }
        return IntegrationStatus(.ready, "\(name(of: alfred)) is installed", detail: workflow)
    }
}

// MARK: - Raycast

/// The Raycast extension, from github.com/r3volution11/vela-raycast-extension,
/// published in the Raycast Store as r3volution11/vela-irc. Raycast installs
/// extensions only from its Store, so there's no file to install.
enum RaycastExtension {
    /// Whether the extension is in the Raycast Store yet. Until it is, the
    /// card says it's coming and links to its source code, and the palette
    /// has no "Open in Raycast Store". Set it to true once it's published.
    static let isInStore = false

    static let bundleID = "com.raycast.macos"
    static let storeDeepLink = URL(string: "raycast://extensions/r3volution11/vela-irc")!
    static let storeWebURL = URL(string: "https://www.raycast.com/r3volution11/vela-irc")!
    static let repositoryURL = URL(string: "https://github.com/r3volution11/vela-raycast-extension")!
    static let getRaycastURL = URL(string: "https://www.raycast.com")!
    static let guideURL = URL(string: "https://velairc.app/guide/alfred-and-raycast#raycast")!

    /// The extension's Store page: in Raycast when it's installed, on the
    /// web otherwise.
    static func storeURL(raycastInstalled: Bool) -> URL {
        raycastInstalled ? storeDeepLink : storeWebURL
    }

    static func openStore() {
        NSWorkspace.shared.open(storeURL(raycastInstalled: InstalledApp.find(bundleID) != nil))
    }

    static func status(raycast: InstalledApp?, isInStore: Bool = isInStore) -> IntegrationStatus {
        let detail = isInStore ? nil : "Coming to the Raycast Store"
        guard raycast != nil else { return IntegrationStatus(.missing, "Raycast isn't installed", detail: detail) }
        return IntegrationStatus(.ready, "Raycast is installed", detail: detail)
    }
}

// MARK: - Shortcuts and Siri

/// Siri and the Shortcuts app: Vela's App Intents and App Shortcuts.
enum ShortcutsIntegration {
    static let bundleID = "com.apple.shortcuts"
    static let guideURL = URL(string: "https://velairc.app/guide/siri-shortcuts")!

    /// What to say. The example channel is Vela's own, #vela on Libera.Chat,
    /// never one of the user's: an example sends people to the channel it
    /// names. Each is one of the App Shortcuts' phrases (Vela/VelaShortcuts.swift).
    static let phrases = [
        "Catch me up in Vela",
        "Check my Vela mentions",
        "Send a message with Vela",
        "Open #vela on Libera.Chat in Vela",
        "Set me away in Vela",
    ]

    /// Vela's actions in the Shortcuts app, in the order the guide lists
    /// them. Every App Shortcut's intent is one of them.
    static let actionTypes: [any AppIntent.Type] = [
        OpenChannelIntent.self, OpenPersonIntent.self, SearchMessagesIntent.self, SendMessageIntent.self,
        JoinChannelIntent.self, CheckMentionsIntent.self, RecapIntent.self, CatchMeUpIntent.self,
        SetAwayIntent.self, SetBackIntent.self, MarkAllAsReadIntent.self,
        ConnectNetworkIntent.self, DisconnectNetworkIntent.self,
    ]

    /// The actions' names, as Shortcuts shows them.
    static var actionTitles: [String] {
        actionTypes.map { String(localized: $0.title) }
    }

    static func openShortcuts() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Spotlight

enum SpotlightIntegration {
    /// For Spotlight's icon.
    static let bundleID = "com.apple.Spotlight"
    static let guideURL = URL(string: "https://velairc.app/guide/siri-shortcuts#spotlight")!

    /// Messages in Spotlight need saved history: Spotlight indexes what's
    /// saved, and forgets it with the history.
    static func messagesDetail(saves: Bool) -> String {
        saves
            ? "Your saved messages in Spotlight's results: the newest 5,000 of each network, then each new one. Turning it off, deleting saved history or removing a channel takes them out."
            : "Needs Save message history, in Settings → Messages → History."
    }
}

// MARK: - AppleScript and links

enum AppleScriptIntegration {
    static let scriptEditorBundleID = "com.apple.ScriptEditor2"
    static let guideURL = URL(string: "https://velairc.app/guide/automation")!

    /// Opens Vela's AppleScript dictionary: Script Editor opens an app's
    /// dictionary when it's given the app.
    static func openDictionary(in scriptEditor: InstalledApp, completion: @escaping @MainActor (String?) -> Void = { _ in }) {
        NSWorkspace.shared.open([Bundle.main.bundleURL], withApplicationAt: scriptEditor.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            let message = error.map { "Script Editor couldn't open Vela's dictionary: \($0.localizedDescription)" }
            Task { @MainActor in completion(message) }
        }
    }

    /// The link scheme this build answers: `vela`, or `vela-dev` in Vela Dev
    /// (the first scheme in its Info.plist).
    static var linkScheme: String {
        let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let scheme = types.lazy.compactMap { ($0["CFBundleURLSchemes"] as? [String])?.first }.first
        return scheme.flatMap { VelaLink.schemes.contains($0) ? $0 : nil } ?? "vela"
    }

    /// A few links to try, on Vela's own channel, in this build's scheme.
    static func linkExamples(scheme: String = linkScheme) -> [(title: String, link: String)] {
        let vela = ConversationReference(.channel("#vela"), network: "Libera.Chat")
        let examples: [(String, VelaLink)] = [
            ("Show #vela on Libera.Chat", .open(vela)),
            ("Put text in its message box, for you to send", .draft(vela, text: "Hello!")),
            ("Open a Recap of today", .recap(VelaIntents.RecapLink(span: .today))),
            ("Search your messages", .search(query: "release notes", in: nil)),
        ]
        return examples.compactMap { title, link in link.url(scheme: scheme).map { (title, $0.absoluteString) } }
    }
}

// MARK: - Status

/// A card's status line: a colored dot, what's installed, and a detail.
struct IntegrationStatus: Equatable {
    enum Kind: Equatable {
        /// Installed and ready (green).
        case ready
        /// Not installed (gray).
        case missing
        /// Installed, but can't be used as it is (orange).
        case attention
        /// Just information (accent).
        case info
    }

    let kind: Kind
    let text: String
    var detail: String?

    init(_ kind: Kind, _ text: String, detail: String? = nil) {
        self.kind = kind
        self.text = text
        self.detail = detail
    }
}
