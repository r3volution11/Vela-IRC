// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Reads and observes the *system* light/dark setting.
///
/// This deliberately doesn't use `NSApp.effectiveAppearance`: the app sets
/// `NSApp.appearance` to match the active theme (so menus and alerts follow
/// it), which would feed back into theme selection. The global
/// `AppleInterfaceStyle` preference and its distributed notification reflect
/// the user's System Settings choice, including automatic switching.
public enum SystemAppearance {
    public static var current: ThemeKind {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication)
        return (style as? String)?.caseInsensitiveCompare("Dark") == .orderedSame ? .dark : .light
    }

    /// Calls `handler` on the main actor whenever the system appearance
    /// changes. Keep the returned token; observation stops when it's released.
    @MainActor
    public static func observe(_ handler: @escaping @MainActor (ThemeKind) -> Void) -> Observation {
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                handler(current)
            }
        }
        return Observation(token: token)
    }

    /// Removes the notification observer when released.
    public final class Observation: @unchecked Sendable {
        private let token: NSObjectProtocol

        init(token: NSObjectProtocol) {
            self.token = token
        }

        deinit {
            DistributedNotificationCenter.default().removeObserver(token)
        }
    }
}
