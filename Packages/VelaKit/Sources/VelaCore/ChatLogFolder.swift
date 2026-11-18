// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

// Where chat logs go. By default that's `Logs` in Vela's data folder. A
// folder you choose instead is remembered with a security-scoped bookmark
// (Vela is sandboxed: it may only use folders you picked), which is
// resolved, and refreshed when macOS says it's stale, at launch. When the
// chosen folder can't be used (deleted, renamed elsewhere, on a disk that
// isn't connected), logs go to Vela's folder and Settings says so; the
// bookmark is kept so the folder comes back when it's available again.

/// Security-scoped bookmarks, behind a protocol so the fallback logic can
/// be tested without real ones.
nonisolated public protocol ChatLogBookmarks: Sendable {
    func bookmarkData(for url: URL) throws -> Data
    /// The bookmarked URL, and whether the bookmark should be made again.
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool)
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

/// Real app-scoped security-scoped bookmarks
/// (`com.apple.security.files.bookmarks.app-scope`).
nonisolated public struct SecurityScopedBookmarks: ChatLogBookmarks {
    public init() {}

    public func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
    }

    public func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    public func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

/// What chat logs remember outside settings.json: the chosen folder's
/// bookmark (binary, and only meaningful on this Mac), its path for
/// display, and each network's folder name.
@MainActor
public protocol ChatLogPreferences: AnyObject {
    var folderBookmark: Data? { get set }
    var folderPath: String? { get set }
    /// Network UUID string → folder name.
    var networkFolders: [String: String] { get set }
}

/// ``ChatLogPreferences`` in the app's user defaults.
public final class UserDefaultsChatLogPreferences: ChatLogPreferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var folderBookmark: Data? {
        get { defaults.data(forKey: "Vela.chatLogs.folderBookmark") }
        set { defaults.set(newValue, forKey: "Vela.chatLogs.folderBookmark") }
    }

    public var folderPath: String? {
        get { defaults.string(forKey: "Vela.chatLogs.folderPath") }
        set { defaults.set(newValue, forKey: "Vela.chatLogs.folderPath") }
    }

    public var networkFolders: [String: String] {
        get { defaults.dictionary(forKey: "Vela.chatLogs.networkFolders") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "Vela.chatLogs.networkFolders") }
    }
}

/// ``ChatLogPreferences`` that last as long as the process (demo mode, tests).
public final class InMemoryChatLogPreferences: ChatLogPreferences {
    public var folderBookmark: Data?
    public var folderPath: String?
    public var networkFolders: [String: String] = [:]

    public init() {}
}

/// Which folder logs are going to.
nonisolated public enum ChatLogFolderStatus: Sendable, Equatable {
    /// `Logs` in Vela's data folder.
    case standard
    /// The folder you chose.
    case custom
    /// The folder you chose (at `path`) can't be used right now, so logs go
    /// to Vela's folder.
    case unavailable(path: String)
}

/// The outcome of looking up the saved folder at launch.
nonisolated public struct ChatLogFolderResolution: Sendable, Equatable {
    public var folder: URL
    public var status: ChatLogFolderStatus
    /// A URL whose security scope was started; stop it when done with it.
    public var accessedURL: URL?
    /// A fresh bookmark to save in place of a stale one.
    public var refreshedBookmark: Data?

    /// Looks up the saved folder. Without one, or when it can't be used,
    /// logs go to `defaultFolder`.
    public static func resolve(
        bookmark: Data?,
        savedPath: String?,
        defaultFolder: URL,
        bookmarks: some ChatLogBookmarks,
        isDirectory: (URL) -> Bool = ChatLogFolderResolution.isDirectory
    ) -> ChatLogFolderResolution {
        guard let bookmark else {
            return ChatLogFolderResolution(folder: defaultFolder, status: .standard)
        }
        let unavailable = ChatLogFolderResolution(folder: defaultFolder, status: .unavailable(path: savedPath ?? ""))
        guard let resolved = try? bookmarks.resolve(bookmark) else { return unavailable }
        let (url, isStale) = resolved
        let path = savedPath ?? url.path
        guard bookmarks.startAccessing(url) else {
            return ChatLogFolderResolution(folder: defaultFolder, status: .unavailable(path: path))
        }
        guard isDirectory(url) else {
            bookmarks.stopAccessing(url)
            return ChatLogFolderResolution(folder: defaultFolder, status: .unavailable(path: path))
        }
        // A stale bookmark still resolved (the folder moved or the disk
        // changed); save a new one while we have access.
        let refreshed = isStale ? try? bookmarks.bookmarkData(for: url) : nil
        return ChatLogFolderResolution(folder: url, status: .custom, accessedURL: url, refreshedBookmark: refreshed)
    }

    public nonisolated static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
