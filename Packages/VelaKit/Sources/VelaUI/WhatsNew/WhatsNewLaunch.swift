// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import VelaCore

/// Opens What's New after an update (see ``WhatsNewTrigger``), once the
/// main window is up.
@MainActor
enum WhatsNewLaunch {
    /// Launch arguments of runs that drive Vela on their own: demo mode,
    /// screenshots, the scroll benchmark and the settings snapshots. Most
    /// need `--demo` too; any one of them is enough here.
    static let automationArguments: Set<String> = ["--demo", "--snapshot", "--scroll-benchmark", "--theme-editor"]

    /// Whether this run must never show What's New, or record a version
    /// as seen: demo, screenshot, benchmark and test runs. Demo mode shares
    /// the real app's user defaults, so it mustn't touch the record either.
    static func isSuppressed(
        isDemo: Bool,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if isDemo { return true }
        if arguments.contains(where: { automationArguments.contains($0) || $0.hasPrefix("--bench-") || $0.hasPrefix("--settings-") }) {
            return true
        }
        // XCTest and Swift Testing, hosted in the app.
        let testKeys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
        return testKeys.contains { environment[$0] != nil }
    }

    /// Opens What's New if this launch is the first of a newer version on a
    /// Mac where Vela ran before. Never in automation runs, which don't
    /// record the version either.
    static func openIfNeeded(app: AppModel, openWindow: OpenWindowAction) async {
        guard !isSuppressed(isDemo: app.isDemo || SnapshotSupport.isActive || ScrollBenchmark.isActive) else { return }
        guard WhatsNewTrigger.shouldShowAtLaunch(
            version: AppModel.appVersion,
            isExistingInstall: app.isExistingInstall,
            record: app.launchRecord
        ) else { return }
        // Let the main window come up first, so this one opens in front.
        try? await Task.sleep(for: .milliseconds(500))
        openWindow(id: WindowID.whatsNew)
    }
}
