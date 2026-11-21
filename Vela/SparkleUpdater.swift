// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaUI
#if !DEBUG
import Sparkle
#endif

/// The app's updater: Sparkle in a release build, nothing in Vela Dev.
///
/// Debug builds ("Vela Dev", io.github.r3volution11.Vela.dev) never make a
/// Sparkle updater: they have no feed in their Info.plist either (only the
/// Release configuration merges Vela/Info.plist), so they can't check the
/// release feed or replace themselves with a release. A release build
/// without a feed or a real public key (before the signing key exists)
/// doesn't start one either, so it never shows Sparkle's "misconfigured"
/// alert.
enum VelaUpdater {
    static func make() -> any AppUpdater {
        #if DEBUG
        return DisabledUpdater(reason: .developmentBuild)
        #else
        guard SparkleUpdater.isConfigured(Bundle.main) else { return DisabledUpdater(reason: .notConfigured) }
        return SparkleUpdater()
        #endif
    }
}

#if !DEBUG
/// ``AppUpdater`` with Sparkle 2: an `SPUUpdater` with Sparkle's standard
/// windows (`SPUStandardUserDriver`).
///
/// Sparkle's settings are in Vela/Info.plist (feed, public key, daily
/// checks, no system profile, the sandbox's installer service). Vela's
/// settings.json decides whether it checks and installs automatically:
/// `UpdateSettingsSync` (VelaUI) sets ``automaticallyChecks`` and
/// ``automaticallyDownloads`` before ``start()`` and whenever they change.
///
/// **Gentle reminders.** A check Sparkle runs on its own offers a new
/// version only when Vela was just opened or the Mac has been idle (what
/// Sparkle calls immediate focus), never while you're typing in a channel,
/// where its window would take the keyboard. Otherwise the update waits:
/// the About window and Settings → Updates say it's available, Check for
/// Updates… shows it, and the next launch offers it.
///
/// Cost: Sparkle's own startup and a timer; the KVO observations below
/// only fire when Sparkle changes a value.
@MainActor
@Observable
final class SparkleUpdater: NSObject, AppUpdater {
    let unavailableReason: UpdatesUnavailableReason? = nil
    private(set) var status: UpdateStatus = .idle
    private(set) var lastCheckDate: Date?
    private(set) var canCheckForUpdates = false
    private var checksAutomatically = false
    private var downloadsAutomatically = false

    var automaticallyChecks: Bool {
        get { checksAutomatically }
        set {
            updater.automaticallyChecksForUpdates = newValue
            checksAutomatically = updater.automaticallyChecksForUpdates
        }
    }

    var automaticallyDownloads: Bool {
        get { downloadsAutomatically }
        set {
            updater.automaticallyDownloadsUpdates = newValue
            downloadsAutomatically = updater.automaticallyDownloadsUpdates
        }
    }

    @ObservationIgnored private var updater: SPUUpdater!
    @ObservationIgnored private var userDriver: SPUStandardUserDriver!
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var started = false

    /// The version a scheduled check found but didn't show (see "Gentle
    /// reminders"), so the next launch offers it.
    private static let waitingVersionKey = "VelaUpdateWaitingVersion"
    private var waitingVersion: String? {
        get { UserDefaults.standard.string(forKey: Self.waitingVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.waitingVersionKey) }
    }

    /// Whether `bundle` has a feed it may use and a real public key: base64
    /// of 32 bytes, not the placeholder Vela/Info.plist ships with until the
    /// signing key exists.
    static func isConfigured(_ bundle: Bundle) -> Bool {
        guard let feed = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:)),
              isAllowedFeed(feed),
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32
        else { return false }
        return true
    }

    /// https, or plain http on this Mac only: scripts/test-update.sh serves
    /// its feed from localhost. Releases always have velairc.app's https feed
    /// (scripts/verify-release.sh checks it).
    static func isAllowedFeed(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        return url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host())
    }

    override init() {
        super.init()
        userDriver = SPUStandardUserDriver(hostBundle: .main, delegate: self)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: self)
        checksAutomatically = updater.automaticallyChecksForUpdates
        downloadsAutomatically = updater.automaticallyDownloadsUpdates
        lastCheckDate = updater.lastUpdateCheckDate
        observe()
    }

    /// Follows the values Sparkle changes itself: whether a check can run
    /// now, and the update window's "Automatically download and install
    /// updates in the future" box.
    private func observe() {
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.checksAutomatically = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.downloadsAutomatically = updater.automaticallyDownloadsUpdates }
            },
        ]
    }

    func start() {
        guard !started else { return }
        started = true
        do {
            try updater.start()
        } catch {
            status = .failed(message: error.localizedDescription)
            return
        }
        lastCheckDate = updater.lastUpdateCheckDate
        // A version found while you were busy is offered now, at launch.
        if waitingVersion != nil, updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        guard started, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    fileprivate func finishedCheck(_ updater: SPUUpdater) {
        lastCheckDate = updater.lastUpdateCheckDate ?? lastCheckDate
    }
}

// MARK: - SPUUpdaterDelegate

extension SparkleUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        status = .checking
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = .available(version: item.displayVersionString)
        finishedCheck(updater)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        let info = (error as NSError).userInfo
        let reason = (info[SPUNoUpdateFoundReasonKey] as? NSNumber).flatMap { SPUNoUpdateFoundReason(rawValue: $0.int32Value) }
        if reason == .systemIsTooOld, let latest = info[SPULatestAppcastItemFoundKey] as? SUAppcastItem {
            status = .needsNewerMacOS(version: latest.displayVersionString)
        } else {
            status = .upToDate
        }
        waitingVersion = nil
        finishedCheck(updater)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let error = error as NSError
        if error.domain == SUSparkleErrorDomain {
            switch Int(error.code) {
            case Int(SUError.noUpdateError.rawValue): return  // updaterDidNotFindUpdate said so
            case Int(SUError.installationCanceledError.rawValue):
                status = .idle
                return
            default: break
            }
        }
        status = .failed(message: error.localizedDescription)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        status = .readyToInstall(version: item.displayVersionString)
        // Sparkle installs it when Vela quits.
        return false
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        waitingVersion = nil
        switch choice {
        case .skip: status = .idle
        case .dismiss: status = .available(version: updateItem.displayVersionString)
        case .install: break
        @unknown default: break
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if status == .checking { status = .idle }
        finishedCheck(updater)
    }
}

// MARK: - Gentle reminders (SPUStandardUserDriverDelegate)

extension SparkleUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows a scheduled update itself only in immediate focus:
    /// right after launch, or when the Mac has been idle.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    /// Otherwise the update waits for Check for Updates… or the next launch.
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        status = .available(version: update.displayVersionString)
        waitingVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        waitingVersion = nil
    }
}
#endif
