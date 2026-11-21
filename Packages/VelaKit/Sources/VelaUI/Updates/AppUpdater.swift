// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation

/// The app's updater, as the About window, Settings → Updates and the Vela
/// menu see it.
///
/// The app target implements it with Sparkle (`SparkleUpdater` in
/// `Vela/`), so VelaKit never links Sparkle and tests use a fake. An
/// implementation is `@Observable`: views read these properties and follow
/// them.
///
/// settings.json is the source of truth for the two automatic settings
/// (`updates.checkAutomatically`, `updates.installAutomatically`):
/// ``UpdateSettingsSync`` applies them to ``automaticallyChecks`` and
/// ``automaticallyDownloads``, and writes back a choice made in the
/// updater's own window.
@MainActor
public protocol AppUpdater: AnyObject, Observable {
    /// Why this build can't update itself, or nil when it can.
    var unavailableReason: UpdatesUnavailableReason? { get }
    /// What happened last, for the status line.
    var status: UpdateStatus { get }
    /// When the updater last asked for the newest version, if ever.
    var lastCheckDate: Date? { get }
    /// Whether ``checkForUpdates()`` can run now (not while an update
    /// downloads in the background).
    var canCheckForUpdates: Bool { get }
    /// Check once a day on its own.
    var automaticallyChecks: Bool { get set }
    /// Download and install new versions without asking. Only takes effect
    /// while ``automaticallyChecks`` is on, and reads false while it's off.
    var automaticallyDownloads: Bool { get set }
    /// Starts the update cycle. Called once, at launch, after the settings
    /// were applied.
    func start()
    /// The user's Check for Updates: shows the updater's window with the
    /// result, or with the update that's waiting.
    func checkForUpdates()
}

/// Why a build doesn't update itself.
public enum UpdatesUnavailableReason: Equatable, Sendable {
    /// Vela Dev (the Debug configuration): it never checks the release feed.
    case developmentBuild
    /// A build without an update feed or signing key.
    case notConfigured
}

/// What the updater did last.
public enum UpdateStatus: Equatable, Sendable {
    /// Nothing yet in this run: the status line shows the last check.
    case idle
    case checking
    /// The newest version is the one running.
    case upToDate
    /// A newer version is waiting: Check for Updates shows it.
    case available(version: String)
    /// A newer version was downloaded and installs when Vela quits.
    case readyToInstall(version: String)
    /// The newest version needs a newer macOS than this Mac has.
    case needsNewerMacOS(version: String)
    /// The check or the update failed, with the updater's explanation.
    case failed(message: String)
}

/// An updater that never updates: Vela Dev, and builds without a feed or
/// signing key. Its controls show, disabled, with the reason.
@MainActor
@Observable
public final class DisabledUpdater: AppUpdater {
    public let unavailableReason: UpdatesUnavailableReason?
    public var status: UpdateStatus { .idle }
    public var lastCheckDate: Date? { nil }
    public var canCheckForUpdates: Bool { false }
    public var automaticallyChecks = false
    public var automaticallyDownloads = false

    public init(reason: UpdatesUnavailableReason) {
        unavailableReason = reason
    }

    public func start() {}
    public func checkForUpdates() {}
}

/// The updater of demo runs (screenshots, UI work): up to date, checked two
/// hours ago. It never goes online.
@MainActor
@Observable
final class DemoUpdater: AppUpdater {
    var unavailableReason: UpdatesUnavailableReason? { nil }
    var status: UpdateStatus = .upToDate
    var lastCheckDate: Date? = Date().addingTimeInterval(-2 * 3600)
    var canCheckForUpdates: Bool { true }
    var automaticallyChecks = true
    var automaticallyDownloads = false

    func start() {}
    func checkForUpdates() {
        status = .upToDate
        lastCheckDate = Date()
    }
}
