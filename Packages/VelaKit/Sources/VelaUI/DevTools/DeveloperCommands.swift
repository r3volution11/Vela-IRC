// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG

import SwiftUI
import VelaCore

/// Vela Dev's Developer menu (Debug builds only), after the app's own
/// menus: the developer tools and the state simulator. The palette lists
/// the same commands under "Developer:".
struct DeveloperMenuItems: View {
    let commands: VelaCommandCatalog

    var body: some View {
        CommandMenuToggle(commands.inspectElement)
        CommandMenuToggle(commands.layoutOutlines)
        CommandMenuToggle(commands.performanceHUD)

        Divider()

        Section("State Simulator") {
            CommandMenuButton(commands.simulateOffline)
            CommandMenuButton(commands.simulateConnecting)
            CommandMenuButton(commands.simulateOnline)
            Divider()
            CommandMenuButton(commands.simulateMention)
            CommandMenuButton(commands.simulateLongMessage)
            CommandMenuButton(commands.simulateHugeChannel)
            Divider()
            CommandMenuButton(commands.simulateReconnectStorm)
            Divider()
            CommandMenuButton(commands.removeSimulator)
        }
    }
}

extension VelaCommandCatalog {
    private var tools: DevTools { DevTools.shared }

    private func simulate(_ action: @escaping (DevSimulator) -> Void) -> () -> Void {
        { [context] in action(DevTools.shared.simulator(for: context.app)) }
    }

    var developerCommands: [VelaCommand] {
        [
            inspectElement, layoutOutlines, performanceHUD,
            simulateOffline, simulateConnecting, simulateOnline,
            simulateMention, simulateLongMessage, simulateHugeChannel,
            simulateReconnectStorm, removeSimulator,
        ]
    }

    var inspectElement: VelaCommand {
        VelaCommand(
            id: "developer.inspectElement", category: .developer, title: "Inspect Element",
            shortcut: Shortcuts.inspectElement, keywords: ["devtools", "theme token", "font", "padding"],
            isChecked: tools.isInspecting
        ) { DevTools.shared.isInspecting.toggle() }
    }

    var layoutOutlines: VelaCommand {
        VelaCommand(
            id: "developer.layoutOutlines", category: .developer, title: "Layout Outlines",
            shortcut: Shortcuts.layoutOutlines, keywords: ["devtools", "box model", "frames", "spacing"],
            isChecked: tools.showsOutlines
        ) { DevTools.shared.showsOutlines.toggle() }
    }

    var performanceHUD: VelaCommand {
        VelaCommand(
            id: "developer.performanceHUD", category: .developer, title: "Performance HUD",
            shortcut: Shortcuts.performanceHUD, keywords: ["devtools", "fps", "frames", "memory", "hitches"],
            isChecked: tools.showsPerformanceHUD
        ) { DevTools.shared.showsPerformanceHUD.toggle() }
    }

    var simulateOffline: VelaCommand {
        VelaCommand(
            id: "developer.simulateOffline", category: .developer, title: "Simulate Network Offline",
            menuTitle: "Network Offline", keywords: ["simulator", "disconnected"],
            perform: simulate { $0.goOffline() }
        )
    }

    var simulateConnecting: VelaCommand {
        VelaCommand(
            id: "developer.simulateConnecting", category: .developer, title: "Simulate Network Connecting",
            menuTitle: "Network Connecting", keywords: ["simulator"],
            perform: simulate { $0.startConnecting() }
        )
    }

    var simulateOnline: VelaCommand {
        VelaCommand(
            id: "developer.simulateOnline", category: .developer, title: "Simulate Network Online",
            menuTitle: "Network Online", keywords: ["simulator", "connected"],
            perform: simulate { $0.goOnline() }
        )
    }

    var simulateMention: VelaCommand {
        VelaCommand(
            id: "developer.simulateMention", category: .developer, title: "Simulate Incoming Mention",
            menuTitle: "Incoming Mention", keywords: ["simulator", "highlight", "notification"],
            perform: simulate { $0.mention() }
        )
    }

    var simulateLongMessage: VelaCommand {
        VelaCommand(
            id: "developer.simulateLongMessage", category: .developer, title: "Simulate Very Long Nick and Message",
            menuTitle: "Very Long Nick and Message", keywords: ["simulator", "wrap", "overflow"],
            perform: simulate { $0.longMessage() }
        )
    }

    var simulateHugeChannel: VelaCommand {
        VelaCommand(
            id: "developer.simulateHugeChannel", category: .developer, title: "Simulate Huge Channel",
            menuTitle: "Huge Channel (5,000 Members, 10,000 Messages)", keywords: ["simulator", "members", "scrollback"],
            perform: simulate { $0.hugeChannel() }
        )
    }

    var simulateReconnectStorm: VelaCommand {
        let storming = tools.simulator?.isStorming == true
        return VelaCommand(
            id: "developer.simulateReconnectStorm", category: .developer,
            title: storming ? "Stop Reconnect Storm" : "Simulate Reconnect Storm",
            menuTitle: storming ? "Stop Reconnect Storm" : "Reconnect Storm", keywords: ["simulator", "netsplit"],
            perform: simulate { simulator in
                if simulator.isStorming { simulator.stopReconnectStorm() } else { simulator.startReconnectStorm() }
            }
        )
    }

    var removeSimulator: VelaCommand {
        VelaCommand(
            id: "developer.removeSimulator", category: .developer, title: "Remove Simulator Network",
            keywords: ["simulator"], isEnabled: tools.simulator?.session != nil,
            perform: simulate { $0.removeNetwork() }
        )
    }
}

#endif
