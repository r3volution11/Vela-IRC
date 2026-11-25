// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// Settings → AI Providers: where Catch me up and Recap's models come
/// from. Apple Intelligence's status, the default model, your providers
/// (added with the setup sheet, or filled in on their rows), and Ollama or
/// LM Studio on this Mac, found when the pane appears and connected in one
/// click. Each feature's own model is in Intelligence; what each provider
/// is sent, and whether it may be, is in AI Privacy.
struct AIProvidersPane: View {
    @Environment(IntelligenceServices.self) private var intelligence
    let navigate: (SettingsPane) -> Void

    @State private var setup: AIProviderSetupRequest?
    @State private var finder = LocalModelsFinder()

    static let subtitle = "Where Catch me up and Recap's models come from: Apple Intelligence, a model running on this Mac, or OpenAI, Anthropic or Google Gemini with your own key."

    var body: some View {
        let models = intelligence.models
        SettingsPage("AI Providers", subtitle: Self.subtitle, pane: .aiProviders) {
            appleIntelligence
            SettingsSection("Default model") {
                AIModelSettingRow(
                    title: "Default model",
                    detail: "For Catch me up and Recap. Each can choose its own in Intelligence.",
                    key: .intelligenceModel
                )
            }
            AIProvidersSection(navigate: navigate) { setup = AIProviderSetupRequest(start: $0) }
            LocalModelsSection(finder: finder) { entry in
                setup = AIProviderSetupRequest(start: .connected(providerID: entry.id))
            }
        }
        .onAppear { finder.look(with: models) }
        .onDisappear { finder.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            finder.look(with: models)
        }
        .sheet(item: $setup) { request in
            AIProviderSetupSheet(request: request, defaultIsApple: models.modelSettings.defaultModel.isApple)
        }
    }

    /// Apple Intelligence's status: ready, or what it needs.
    @ViewBuilder
    private var appleIntelligence: some View {
        let status = intelligence.availability.status
        if status.isAvailable {
            SettingsCallout(.success, status.title, message: Self.appleReady)
        } else {
            SettingsCallout(.info, status.title, message: "\(status.detail) \(Self.appleUnavailable)") {
                if let url = status.settingsURL {
                    Button("Open System Settings") { NSWorkspace.shared.open(url) }
                        .buttonStyle(ThemedButtonStyle())
                }
            }
        }
    }

    static let appleReady = "Built into macOS, with nothing to set up or pay for. It's the default for Catch me up and Recap until you choose another model."

    static let appleUnavailable = "You can use a model of your own instead: one on this Mac, or from OpenAI, Anthropic or Google Gemini."
}
