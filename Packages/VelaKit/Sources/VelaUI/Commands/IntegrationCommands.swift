// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore

extension VelaCommandCatalog {
    /// Settings → Integrations in the palette: "Settings: Integrations",
    /// "Integrations: Install Alfred Workflow…" and, once the extension is
    /// in the Raycast Store, "Integrations: Open in Raycast Store". Building
    /// them looks nothing up; running one does.
    var integrationCommands: [VelaCommand] {
        let context = context
        return Self.integrationCommands(
            showPane: {
                context.uiState.settingsEditor.requestedPane = .integrations
                context.openSettings()
            },
            installWorkflow: { alfred in AlfredWorkflow.install(with: alfred) },
            openRaycastStore: RaycastExtension.openStore
        )
    }

    /// Static, so tests can build them. "Install Alfred Workflow…" opens the
    /// workflow in Alfred when Alfred 5 or later is installed, and shows
    /// Settings → Integrations (with Get Alfred) otherwise.
    static func integrationCommands(
        isWorkflowBundled: Bool = AlfredWorkflow.bundledURL != nil,
        isRaycastInStore: Bool = RaycastExtension.isInStore,
        findAlfred: @escaping @MainActor () -> InstalledApp? = { InstalledApp.find(AlfredWorkflow.bundleID) },
        showPane: @escaping @MainActor () -> Void,
        installWorkflow: @escaping @MainActor (InstalledApp) -> Void,
        openRaycastStore: @escaping @MainActor () -> Void
    ) -> [VelaCommand] {
        var commands = [
            VelaCommand(
                id: "settings.integrations", category: .settings, title: "Integrations",
                keywords: ["alfred", "raycast", "shortcuts", "siri", "spotlight", "applescript", "links", "vela://", "extensions", "workflow", "automation"]
            ) {
                showPane()
            },
            VelaCommand(
                id: "integrations.installAlfredWorkflow", category: .integrations, title: "Install Alfred Workflow…",
                keywords: ["alfred", "workflow", "powerpack", "launcher", "import"],
                isEnabled: isWorkflowBundled
            ) {
                if let alfred = findAlfred(), AlfredWorkflow.supports(alfred) {
                    installWorkflow(alfred)
                } else {
                    showPane()
                }
            },
        ]
        if isRaycastInStore {
            commands.append(VelaCommand(
                id: "integrations.openRaycastStore", category: .integrations, title: "Open in Raycast Store",
                keywords: ["raycast", "extension", "store", "launcher", "install"]
            ) {
                openRaycastStore()
            })
        }
        return commands
    }
}
