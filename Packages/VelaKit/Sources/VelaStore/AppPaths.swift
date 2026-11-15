// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization

/// Well-known on-disk locations. Everything lives under one root folder so
/// it can later be mirrored to iCloud Drive as plain files.
///
/// In the sandboxed app the root resolves to
/// `~/Library/Containers/io.github.r3volution11.Vela/Data/Library/Application Support/Vela`.
/// Directories are created on demand whenever a path is requested.
public enum AppPaths {
    private static let rootOverride = Mutex<URL?>(nil)

    /// Redirects every path to `url` (pass `nil` to restore the default).
    /// Intended for tests and for running against a scratch profile.
    public static func overrideRoot(_ url: URL?) {
        rootOverride.withLock { $0 = url }
    }

    /// `Application Support/Vela`, created if needed.
    public static var root: URL {
        let url = rootOverride.withLock { $0 } ?? defaultRoot
        ensureDirectory(url)
        return url
    }

    /// `root/Themes`, created if needed.
    public static var themesDirectory: URL {
        let url = root.appending(path: "Themes", directoryHint: .isDirectory)
        ensureDirectory(url)
        return url
    }

    /// `root/vela.sqlite`, the scrollback / buffer-state database.
    public static var databaseURL: URL {
        root.appending(path: "vela.sqlite", directoryHint: .notDirectory)
    }

    /// `root/settings.json`, VS Code-style user settings (JSONC).
    public static var settingsURL: URL {
        root.appending(path: "settings.json", directoryHint: .notDirectory)
    }

    /// `root/networks.json`, the saved network configurations.
    public static var networksURL: URL {
        root.appending(path: "networks.json", directoryHint: .notDirectory)
    }

    /// The non-overridden root (not created by reading this).
    static var defaultRoot: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base.appending(path: "Vela", directoryHint: .isDirectory)
    }

    private static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
