// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntents
import VelaStore
import VelaTheme

/// Settings → Integrations: the tools that work with Vela, each with its
/// icon, what it does, whether it's installed, its buttons and its guide.
/// Alfred (with the workflow the app carries), Raycast, Shortcuts and Siri,
/// Spotlight (with its two settings), and AppleScript and `vela://` links.
///
/// Which apps are installed is looked up when the pane appears and when
/// Vela becomes active again, never polled.
struct IntegrationsPane: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var apps = IntegrationApps()
    @State private var workflowVersion: String?
    @State private var alfredProblem: String?
    @State private var dictionaryProblem: String?

    static let subtitle = "Use Vela from Alfred, Raycast, Siri, Shortcuts, Spotlight and your own scripts. Everything here runs on this Mac."

    var body: some View {
        SettingsPage("Integrations", subtitle: Self.subtitle, pane: .integrations) {
            alfred
            raycast
            shortcuts
            spotlight
            appleScript
        }
        .onAppear { apps.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            apps.refresh()
        }
        .task { workflowVersion = await AlfredWorkflow.bundledVersion() }
    }

    // MARK: Alfred

    private var alfred: some View {
        let alfred = apps.alfred
        let isBundled = AlfredWorkflow.bundledURL != nil
        return IntegrationCard(
            "Alfred",
            icon: .of(alfred, or: "hat.widebrim"),
            summary: "Type “vela” in Alfred to jump to a channel or private conversation, send a message, or open Catch me up or a Recap. The workflow comes with Vela, and needs Alfred 5 or later with the Powerpack.",
            status: AlfredWorkflow.status(alfred: alfred, workflowVersion: workflowVersion, isBundled: isBundled),
            learnMore: AlfredWorkflow.guideURL
        ) {
            if let alfred, AlfredWorkflow.supports(alfred) {
                Button("Install Workflow…") {
                    alfredProblem = nil
                    AlfredWorkflow.install(with: alfred) { alfredProblem = $0 }
                }
                .buttonStyle(ThemedButtonStyle(prominent: true))
                .themedDisabled(!isBundled)
                .accessibilityHint("Opens Vela's workflow in \(AlfredWorkflow.name(of: alfred)), which asks before it imports it.")
            } else {
                Button("Get Alfred") { openURL(AlfredWorkflow.getAlfredURL) }
                    .buttonStyle(ThemedButtonStyle())
                    .accessibilityHint("Opens alfredapp.com in your browser.")
            }
            SourceCodeLink(url: AlfredWorkflow.repositoryURL, of: "the workflow")
        } rows: {
            if let alfredProblem {
                ProblemRow(message: alfredProblem)
            }
        }
    }

    // MARK: Raycast

    private var raycast: some View {
        let raycast = apps.raycast
        let inStore = RaycastExtension.isInStore
        return IntegrationCard(
            "Raycast",
            icon: .of(raycast, or: "rays"),
            summary: "Search your channels and private conversations, send a message or catch up from Raycast, with your mentions in the menu bar if you like.",
            status: RaycastExtension.status(raycast: raycast),
            learnMore: RaycastExtension.guideURL,
            footer: inStore ? nil : "Until the extension is in the Raycast Store, you can add it from its source code, with Node.js. Its page on GitHub says how."
        ) {
            if inStore {
                Button("Open in Raycast Store") { openURL(RaycastExtension.storeURL(raycastInstalled: raycast != nil)) }
                    .buttonStyle(ThemedButtonStyle(prominent: raycast != nil))
                    .accessibilityHint(raycast != nil ? "Shows the Vela extension in Raycast, where you can install it." : "Opens the Vela extension's Store page in your browser.")
            } else {
                Button("View on GitHub") { openURL(RaycastExtension.repositoryURL) }
                    .buttonStyle(ThemedButtonStyle())
                    .accessibilityHint("Opens the extension's source code on GitHub in your browser.")
            }
            if raycast == nil {
                Button("Get Raycast") { openURL(RaycastExtension.getRaycastURL) }
                    .buttonStyle(ThemedButtonStyle())
                    .accessibilityHint("Opens raycast.com in your browser.")
            }
            if inStore {
                SourceCodeLink(url: RaycastExtension.repositoryURL, of: "the extension")
            }
        }
    }

    // MARK: Shortcuts and Siri

    private var shortcuts: some View {
        IntegrationCard(
            "Shortcuts and Siri",
            icon: .of(apps.shortcuts, or: "square.on.square"),
            summary: "Ask Siri to catch you up, check your mentions or send a message, and use Vela's actions in your own shortcuts and automations. There's nothing to set up.",
            learnMore: ShortcutsIntegration.guideURL,
            footer: "On macOS 27 or later, Siri can also send and draft messages, and knows which channel is open, so “reply to this” works."
        ) {
            Button("Open Shortcuts", action: ShortcutsIntegration.openShortcuts)
                .buttonStyle(ThemedButtonStyle())
                .themedDisabled(apps.shortcuts == nil)
                .accessibilityHint("Opens the Shortcuts app, where Vela's actions are under Apps.")
        } rows: {
            SiriPhrasesRow(phrases: ShortcutsIntegration.phrases)
            ShortcutsActionsRow(titles: ShortcutsIntegration.actionTitles)
        }
    }

    // MARK: Spotlight

    private var spotlight: some View {
        @Bindable var settings = app.settings
        return IntegrationCard(
            "Spotlight",
            icon: .of(apps.spotlight, or: "magnifyingglass"),
            summary: "Find your channels and the people you talk to, run Vela's actions such as Send Message or Catch Me Up, or choose Search in Vela to search your messages.",
            learnMore: SpotlightIntegration.guideURL
        ) {
            EmptyView()
        } rows: {
            SettingsToggle(
                "Show channels in Spotlight",
                detail: "Channel names, and the people you talk to in private, in Spotlight's results. Siri still finds them by name when this is off.",
                isOn: $settings[.intelligenceSpotlightChannels]
            )
            SettingsToggle(
                "Search messages in Spotlight",
                detail: SpotlightIntegration.messagesDetail(saves: settings[.historySave]),
                isOn: Binding(
                    get: { settings[.historySave] && settings[.intelligenceSpotlightMessages] },
                    set: { settings[.intelligenceSpotlightMessages] = $0 }
                )
            )
            .themedDisabled(!settings[.historySave])
        }
    }

    // MARK: AppleScript and links

    private var appleScript: some View {
        let scriptEditor = apps.scriptEditor
        return IntegrationCard(
            "AppleScript and vela:// links",
            icon: .of(scriptEditor, or: "applescript"),
            summary: "Script Vela from Script Editor, the terminal or Shortcuts' Run AppleScript, and open channels, drafts, a Recap or message search with vela:// links. Links only show things; a script can send messages once you allow its app.",
            status: IntegrationStatus(.info, "Scripting version \(VelaAutomation.scriptingVersion)"),
            learnMore: AppleScriptIntegration.guideURL
        ) {
            Button("Open Dictionary") {
                guard let scriptEditor else { return }
                dictionaryProblem = nil
                AppleScriptIntegration.openDictionary(in: scriptEditor) { dictionaryProblem = $0 }
            }
            .buttonStyle(ThemedButtonStyle())
            .themedDisabled(scriptEditor == nil)
            .accessibilityHint("Opens Vela's AppleScript dictionary in Script Editor.")
        } rows: {
            if let dictionaryProblem {
                ProblemRow(message: dictionaryProblem)
            }
            LinkExamplesRow(examples: AppleScriptIntegration.linkExamples())
        }
    }
}

// MARK: - Pieces

/// "Source code", to a tool's repository on GitHub.
private struct SourceCodeLink: View {
    @Environment(\.openURL) private var openURL
    let url: URL
    let of: String

    var body: some View {
        SettingsLinkButton("Source code", systemImage: "chevron.left.forwardslash.chevron.right") { openURL(url) }
            .help(url.absoluteString)
            .accessibilityLabel("Source code of \(of)")
            .accessibilityHint("Opens it on GitHub in your browser.")
    }
}

/// What went wrong when a button asked another app to open something.
private struct ProblemRow: View {
    @Environment(\.theme) private var theme
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11.5))
            .foregroundStyle(theme[ThemeKey.statusWarning])
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .textSelection(.enabled)
    }
}

/// "Ask Siri" and a few example phrases.
private struct SiriPhrasesRow: View {
    @Environment(\.theme) private var theme
    let phrases: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask Siri")
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
            VStack(alignment: .leading, spacing: 3) {
                ForEach(phrases, id: \.self) { phrase in
                    Label("“\(phrase)”", systemImage: "waveform")
                        .labelStyle(SiriPhraseLabelStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

private struct SiriPhraseLabelStyle: LabelStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme[ThemeKey.accentText])
                .accessibilityHidden(true)
            configuration.title
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .textSelection(.enabled)
        }
    }
}

/// Vela's actions in the Shortcuts app, by name.
private struct ShortcutsActionsRow: View {
    @Environment(\.theme) private var theme
    let titles: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Actions in Shortcuts")
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
            Text(titles.joined(separator: ", "))
                .font(.system(size: 11.5))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// A few `vela://` links to try, each with a Copy button.
private struct LinkExamplesRow: View {
    @Environment(\.theme) private var theme
    let examples: [(title: String, link: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Links to try")
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .accessibilityAddTraits(.isHeader)
            ForEach(examples, id: \.link) { example in
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(example.title)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        Text(example.link)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(theme[ThemeKey.settingsForeground])
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(example.link, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme[ThemeKey.accentText])
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy link")
                    .accessibilityLabel("Copy link: \(example.title)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}
