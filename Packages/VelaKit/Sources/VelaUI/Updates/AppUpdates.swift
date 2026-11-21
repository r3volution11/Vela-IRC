// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaStore

/// Updates for the About window, Settings → Updates, the Vela menu and the
/// command palette: the app's ``AppUpdater`` and what they show of it.
/// One per app, in the environment.
@MainActor
@Observable
public final class AppUpdates {
    /// Observable itself: reading its properties follows them.
    public let updater: any AppUpdater
    @ObservationIgnored private var sync: UpdateSettingsSync?

    public init(updater: any AppUpdater) {
        self.updater = updater
    }

    /// Whether this build updates itself (not Vela Dev).
    var isAvailable: Bool { updater.unavailableReason == nil }

    /// Whether Check for Updates can run now.
    var canCheck: Bool { isAvailable && updater.canCheckForUpdates }

    /// "Vela is up to date.", "Checking for updates…", …
    var statusLine: String { UpdateStatusText.line(for: updater) }

    /// Check for Updates…: the updater's window shows what it finds.
    func checkForUpdates() {
        guard canCheck else { return }
        updater.checkForUpdates()
    }

    /// Applies `settings` to the updater, starts it, and keeps the two in
    /// step from then on. Called once, at launch; does nothing for a build
    /// that doesn't update.
    func start(settings: SettingsStore) {
        guard sync == nil, isAvailable else { return }
        let sync = UpdateSettingsSync(settings: settings, updater: updater)
        self.sync = sync
        sync.start()
    }
}

// MARK: - Settings

/// Keeps the updater in step with settings.json, the source of truth:
/// `updates.checkAutomatically` and `updates.installAutomatically` are
/// applied at launch, before the first check can run, and whenever they
/// change (in Settings, the settings editor or the file itself).
///
/// The one change that goes the other way is the updater window's
/// "Automatically download and install updates in the future" box, which
/// sets the updater directly: it's written back to
/// `updates.installAutomatically`.
///
/// Costs nothing between changes: it observes the two settings and the
/// updater's two values, and does no work until one of them changes.
@MainActor
final class UpdateSettingsSync {
    private let settings: SettingsStore
    private let updater: any AppUpdater
    /// The settings' values last given to the updater (or written from it),
    /// so only a setting that really changed is applied: a pass that runs
    /// late never undoes a newer choice made in the updater's window.
    private var appliedChecks: Bool?
    private var appliedInstalls: Bool?

    init(settings: SettingsStore, updater: any AppUpdater) {
        self.settings = settings
        self.updater = updater
    }

    /// Applies the settings, starts the updater and follows changes.
    func start() {
        apply()
        observeSettings()
        observeUpdater()
        updater.start()
    }

    /// Gives the updater the settings that changed since the last pass
    /// (both, the first time), changing only what differs (each change is
    /// saved in its preferences). Checking first: the updater ignores
    /// automatic installs while checks are off, so turning checks on
    /// applies installs again too.
    func apply() {
        let checks = settings[.updatesCheckAutomatically]
        let installs = settings[.updatesInstallAutomatically]
        let checksChanged = checks != appliedChecks
        let installsChanged = installs != appliedInstalls
        appliedChecks = checks
        appliedInstalls = installs
        if checksChanged, updater.automaticallyChecks != checks {
            updater.automaticallyChecks = checks
        }
        if checks, checksChanged || installsChanged, updater.automaticallyDownloads != installs {
            updater.automaticallyDownloads = installs
        }
    }

    /// The updater changed automatic installs on its own: the box in its
    /// window. Only a change while checks are on is a choice (while they're
    /// off, the updater reads false), and only one that differs from the
    /// setting needs writing.
    func updaterChanged() {
        guard settings[.updatesCheckAutomatically], updater.automaticallyChecks else { return }
        let installs = updater.automaticallyDownloads
        if settings[.updatesInstallAutomatically] != installs {
            // Already in the updater: nothing to apply back.
            appliedInstalls = installs
            settings[.updatesInstallAutomatically] = installs
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings[.updatesCheckAutomatically]
            _ = settings[.updatesInstallAutomatically]
        } onChange: { [weak self] in
            // Runs before the change lands; act on it right after.
            Task { @MainActor in
                self?.apply()
                self?.observeSettings()
            }
        }
    }

    private func observeUpdater() {
        withObservationTracking {
            _ = updater.automaticallyDownloads
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updaterChanged()
                self?.observeUpdater()
            }
        }
    }
}

// MARK: - Text

/// What the status line says.
enum UpdateStatusText {
    static let developmentBuild = "Updates are turned off in development builds."
    static let notConfigured = "Updates aren't set up in this build."

    static func line(for updater: any AppUpdater, now: Date = Date()) -> String {
        switch updater.unavailableReason {
        case .developmentBuild: return developmentBuild
        case .notConfigured: return notConfigured
        case nil: break
        }
        switch updater.status {
        case .idle:
            if let date = updater.lastCheckDate { return lastChecked(date, now: now) }
            return updater.automaticallyChecks ? "Vela hasn't checked for updates yet." : "Automatic update checks are off."
        case .checking: return "Checking for updates…"
        case .upToDate: return "Vela is up to date."
        case .available(let version): return "Version \(version) is available."
        case .readyToInstall(let version): return "Version \(version) will be installed when you quit Vela."
        case .needsNewerMacOS(let version): return "Version \(version) needs a newer version of macOS."
        case .failed(let message): return message
        }
    }

    /// "Last checked just now.", "Last checked 3 hours ago.", "Last checked yesterday."
    static func lastChecked(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "Last checked just now." }
        return "Last checked \(relativeFormatter.localizedString(for: date, relativeTo: now))."
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter
    }()

    /// The status line's symbol.
    static func systemImage(for updater: any AppUpdater) -> String {
        guard updater.unavailableReason == nil else { return "info.circle" }
        switch updater.status {
        case .idle: return "clock"
        case .checking: return "arrow.triangle.2.circlepath"
        case .upToDate: return "checkmark.circle.fill"
        case .available, .readyToInstall: return "arrow.down.circle.fill"
        case .needsNewerMacOS, .failed: return "exclamationmark.triangle.fill"
        }
    }
}
