// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore

extension VelaCommandCatalog {
    /// Your own AI models in the palette: "AI: Set Default Model…" and
    /// "AI: Manage Providers…", and, where there's another model to
    /// choose, "Buffer: Catch Me Up With…" and "Buffer: Recap With…".
    var aiModelCommands: [VelaCommand] {
        guard let intelligence = context.intelligence else { return [] }
        let context = context
        return Self.aiModelCommands(
            app: context.app,
            intelligence: intelligence,
            openPalette: { Self.togglePalette(.models($0), uiState: context.uiState, openWindow: context.openWindow) },
            manageProviders: { AIModelActions.openSettings(uiState: context.uiState, openSettings: context.openSettings) }
        )
    }

    /// Static, so tests can build them; `openPalette` opens the palette's
    /// model list for a purpose.
    static func aiModelCommands(
        app: AppModel,
        intelligence: IntelligenceServices,
        openPalette: @escaping (AIModelPickerPurpose) -> Void,
        manageProviders: @escaping () -> Void
    ) -> [VelaCommand] {
        let models = intelligence.models
        var commands = [
            VelaCommand(
                id: "ai.setDefaultModel", category: .ai, title: "Set Default Model…",
                keywords: ["model", "openai", "anthropic", "claude", "gemini", "ollama", "apple intelligence", "provider", "llm"],
                detail: models.title(for: models.modelSettings.defaultModel)
            ) {
                openPalette(.defaultModel)
            },
            VelaCommand(
                id: "ai.manageProviders", category: .ai, title: "Manage Providers…",
                keywords: ["api key", "openai", "anthropic", "claude", "gemini", "ollama", "lm studio", "models", "byok"]
            ) {
                manageProviders()
            },
        ]
        guard models.hasChoices, let buffer = app.selectedBuffer else { return commands }
        if app.settings[.intelligenceCatchUp], buffer.kind != .server {
            commands.append(VelaCommand(
                id: "buffer.catchUpWith", category: .buffer, title: "Catch Me Up With…",
                keywords: ["summary", "summarize", "model", "openai", "anthropic", "claude", "gemini", "ollama", "unread"]
            ) {
                openPalette(.catchUp(buffer.id))
            })
        }
        if RecapActions.isOffered(app.settings) {
            var scope = RecapActions.scope(for: buffer, intelligence: intelligence)
            scope.output = .summary
            commands.append(VelaCommand(
                id: "buffer.recapWith", category: .buffer, title: "Recap With…",
                keywords: ["recap", "summary", "report", "model", "openai", "anthropic", "claude", "gemini", "ollama"]
            ) {
                openPalette(.recap(scope))
            })
        }
        return commands
    }
}
