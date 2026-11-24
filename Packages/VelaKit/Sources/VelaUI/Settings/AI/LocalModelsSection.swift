// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import SwiftUI
import VelaIntelligence
import VelaStore
import VelaTheme

/// What Settings → AI Providers found of Ollama and LM Studio: which is
/// installed (Launch Services) and which is running (its model list on
/// this Mac's loopback address, a second at most, off the main actor).
/// Looked for when the pane appears, on Look Again, when Vela becomes
/// active again, and once a few seconds after Open; never on a timer.
@MainActor
@Observable
final class LocalModelsFinder {
    private(set) var states: [LocalModelServer: LocalServerState] = [:]
    private(set) var installed: [LocalModelServer: InstalledApp] = [:]
    /// A look is under way.
    private(set) var isLooking = false
    /// At least one look has finished.
    private(set) var hasLooked = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let find: @MainActor (String) -> InstalledApp?

    /// How long after Open Ollama (or LM Studio) to look again: its server
    /// takes a moment to start.
    static let lookAfterOpening: Duration = .seconds(3)

    init(find: @escaping @MainActor (String) -> InstalledApp? = InstalledApp.find) {
        self.find = find
    }

    /// Looks again, unless a look is already under way.
    func look(with models: AIModels) {
        guard models.canAddProviders, task == nil else { return }
        refreshInstalled()
        isLooking = true
        task = Task { [weak self] in
            let found = await models.detectLocalServers()
            guard let self else { return }
            if states != found { states = found }
            isLooking = false
            hasLooked = true
            task = nil
        }
    }

    /// Opens the app, then looks again once its server has had time to start.
    func open(_ server: LocalModelServer, models: AIModels) {
        guard let app = installed[server] else { return }
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        Task { [weak self] in
            try? await Task.sleep(for: Self.lookAfterOpening)
            self?.look(with: models)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLooking = false
    }

    private func refreshInstalled() {
        var found: [LocalModelServer: InstalledApp] = [:]
        for server in LocalModelServer.allCases {
            if let app = find(server.bundleIdentifier) { found[server] = app }
        }
        if installed != found { installed = found }
    }

    /// What to show for `server`, given what was found and whether a
    /// provider is already connected to it.
    static func offer(state: LocalServerState?, installed: Bool, connected: AIProviderEntry?) -> LocalModelOffer {
        switch (state, connected) {
        case (.running(let models)?, nil): return .connect(models: models)
        case (.running(let models)?, let entry?): return .connected(entry, running: true, models: models.count)
        case (_, let entry?): return .connected(entry, running: false, models: 0)
        case (_, nil): return installed ? .open : .none
        }
    }
}

/// One server's line on AI Providers.
enum LocalModelOffer: Equatable {
    /// Running, and not connected yet.
    case connect(models: [AIModelInfo])
    /// Already a provider; whether it answered just now.
    case connected(AIProviderEntry, running: Bool, models: Int)
    /// Installed, but its server didn't answer.
    case open
    /// Neither installed nor running.
    case none
}

/// Settings → AI Providers → On this Mac: Ollama or LM Studio, found
/// running with "Connect" (a provider in one click: no key, no account),
/// found installed with "Open", or, with neither, where to get them.
struct LocalModelsSection: View {
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    let finder: LocalModelsFinder
    /// Opens the setup sheet for a provider just connected.
    let connected: (AIProviderEntry) -> Void

    var body: some View {
        let models = intelligence.models
        let offers = LocalModelServer.allCases.map { server in
            (server, LocalModelsFinder.offer(
                state: finder.states[server],
                installed: finder.installed[server] != nil,
                connected: models.provider(for: server)
            ))
        }
        let shown = offers.filter { $0.1 != .none }
        SettingsSection("On this Mac", footer: Self.footer) {
            if !models.canAddProviders {
                getThemRow
            } else if !finder.hasLooked, shown.isEmpty {
                lookingRow
            } else if shown.isEmpty {
                getThemRow
            } else {
                ForEach(shown, id: \.0) { item in
                    row(item.0, item.1)
                }
            }
        } accessory: {
            if models.canAddProviders {
                HStack(spacing: 6) {
                    if finder.isLooking {
                        ProgressView().controlSize(.mini).accessibilityLabel("Looking")
                    }
                    SettingsLinkButton("Look Again", systemImage: "arrow.clockwise") { finder.look(with: models) }
                        .fixedSize()
                        .disabled(finder.isLooking)
                        .accessibilityHint("Checks whether Ollama or LM Studio is running on this Mac")
                }
            }
        }
    }

    static let footer = "Models on this Mac need no key or account, and what they're sent stays on this Mac. Vela looks for Ollama and LM Studio only on this Mac, when this pane opens."

    // MARK: Rows

    private var lookingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).accessibilityHidden(true)
            Text("Looking for Ollama and LM Studio…")
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var getThemRow: some View {
        HStack(alignment: .top, spacing: 12) {
            IntegrationIconView(icon: .symbol("desktopcomputer"))
            VStack(alignment: .leading, spacing: 6) {
                Text("Run models on this Mac, free and without an account, with Ollama or LM Studio. Once one is running, Vela finds it here.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    ForEach(LocalModelServer.allCases) { server in
                        SettingsLinkButton(server.websiteURL.host() ?? server.name, systemImage: "arrow.up.right.square") {
                            openURL(server.websiteURL)
                        }
                        .fixedSize()
                        .help(server.websiteURL.absoluteString)
                        .accessibilityLabel("Get \(server.name)")
                        .accessibilityHint("Opens \(server.websiteURL.host() ?? server.name) in your browser")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    private func row(_ server: LocalModelServer, _ offer: LocalModelOffer) -> some View {
        HStack(alignment: .center, spacing: 12) {
            IntegrationIconView(icon: .of(finder.installed[server], or: "server.rack"))
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.title(server, offer))
                    .font(.system(size: 13))
                    .foregroundStyle(theme[ThemeKey.settingsForeground])
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = Self.detail(server, offer) {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            actions(server, offer)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func actions(_ server: LocalModelServer, _ offer: LocalModelOffer) -> some View {
        let models = intelligence.models
        switch offer {
        case .connect(let list):
            Button("Connect") {
                if let entry = models.connect(server, models: list) { connected(entry) }
            }
            .buttonStyle(ThemedButtonStyle(prominent: true))
            .accessibilityLabel("Connect \(server.name)")
            .accessibilityHint("Adds \(server.name) as a provider, then asks whether it may be sent messages")
        case .connected(_, let running, _):
            if running {
                SettingsPill(text: "Connected", tinted: true)
            } else if finder.installed[server] != nil {
                openButton(server)
            }
        case .open:
            openButton(server)
        case .none:
            EmptyView()
        }
    }

    private func openButton(_ server: LocalModelServer) -> some View {
        Button("Open \(server.name)") { finder.open(server, models: intelligence.models) }
            .buttonStyle(ThemedButtonStyle())
            .accessibilityHint("Opens \(server.name); Vela looks for its server again a few seconds later")
    }

    // MARK: Words

    /// "Ollama is running on this Mac, with 3 models."
    static func title(_ server: LocalModelServer, _ offer: LocalModelOffer) -> String {
        switch offer {
        case .connect(let models):
            switch models.count {
            case 0: return "\(server.name) is running on this Mac, with no models yet."
            case 1: return "\(server.name) is running on this Mac, with 1 model."
            default: return "\(server.name) is running on this Mac, with \(models.count) models."
            }
        case .connected(let entry, let running, _):
            return running ? "\(server.name) is connected as \(entry.name)." : "\(server.name) is connected as \(entry.name), but isn't running."
        case .open:
            return "\(server.name) is installed, but isn't running."
        case .none:
            return ""
        }
    }

    static func detail(_ server: LocalModelServer, _ offer: LocalModelOffer) -> String? {
        switch offer {
        case .connect(let models):
            return models.isEmpty
                ? "Download a model in \(server.name) first, or connect now and Test it later."
                : "Connect it to use its models for Catch me up and Recap. No key needed."
        case .connected(_, let running, _):
            return running ? nil : server.startHint
        case .open:
            return server.startHint
        case .none:
            return nil
        }
    }
}
