// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaUI

@main
struct VelaApp: App {
    /// Sparkle in a release build; Vela Dev's never checks (SparkleUpdater.swift).
    private let updater: any AppUpdater

    init() {
        updater = VelaUpdater.make()
        // Siri and Shortcuts can launch Vela to run an action: register
        // its App Intents dependencies now, before anything can ask.
        VelaScenes.prepare(appShortcuts: VelaShortcuts.self, updater: updater)
    }

    var body: some Scene {
        VelaScenes(appShortcuts: VelaShortcuts.self, updater: updater)
    }
}
