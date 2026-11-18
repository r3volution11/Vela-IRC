// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore

/// Bookmarks that resolve as told, recording what was accessed.
final class FakeBookmarks: ChatLogBookmarks, @unchecked Sendable {
    enum Outcome {
        case resolves(URL, stale: Bool)
        case fails
    }

    private let lock = NSLock()
    var outcome: Outcome
    var grantsAccess = true
    var bookmarkFails = false
    private(set) var started: [URL] = []
    private(set) var stopped: [URL] = []
    private(set) var made: [URL] = []

    init(_ outcome: Outcome = .fails) {
        self.outcome = outcome
    }

    func bookmarkData(for url: URL) throws -> Data {
        if bookmarkFails { throw CocoaError(.fileWriteNoPermission) }
        lock.withLock { made.append(url) }
        return Data("bookmark:\(url.path)".utf8)
    }

    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        switch outcome {
        case .resolves(let url, let stale): return (url, stale)
        case .fails: throw CocoaError(.fileNoSuchFile)
        }
    }

    func startAccessing(_ url: URL) -> Bool {
        lock.withLock { started.append(url) }
        return grantsAccess
    }

    func stopAccessing(_ url: URL) {
        lock.withLock { stopped.append(url) }
    }
}

@Suite("Chat log folder")
struct ChatLogFolderTests {
    private let defaultFolder = URL(fileURLWithPath: "/tmp/Vela/Logs")
    private let chosen = URL(fileURLWithPath: "/Volumes/Archive/IRC Logs")

    @Test func withoutABookmarkLogsGoToVelasFolder() {
        let result = ChatLogFolderResolution.resolve(bookmark: nil, savedPath: nil, defaultFolder: defaultFolder, bookmarks: FakeBookmarks())
        #expect(result.folder == defaultFolder)
        #expect(result.status == .standard)
        #expect(result.accessedURL == nil)
    }

    @Test func aGoodBookmarkIsUsed() {
        let bookmarks = FakeBookmarks(.resolves(chosen, stale: false))
        let result = ChatLogFolderResolution.resolve(
            bookmark: Data("x".utf8), savedPath: chosen.path, defaultFolder: defaultFolder, bookmarks: bookmarks, isDirectory: { _ in true }
        )
        #expect(result.folder == chosen)
        #expect(result.status == .custom)
        #expect(result.accessedURL == chosen)
        #expect(result.refreshedBookmark == nil)
        #expect(bookmarks.started == [chosen])
    }

    @Test func aStaleBookmarkIsRefreshed() {
        let bookmarks = FakeBookmarks(.resolves(chosen, stale: true))
        let result = ChatLogFolderResolution.resolve(
            bookmark: Data("old".utf8), savedPath: chosen.path, defaultFolder: defaultFolder, bookmarks: bookmarks, isDirectory: { _ in true }
        )
        #expect(result.status == .custom)
        #expect(result.refreshedBookmark == Data("bookmark:\(chosen.path)".utf8))
    }

    @Test func aBookmarkThatWontResolveFallsBack() {
        let result = ChatLogFolderResolution.resolve(
            bookmark: Data("x".utf8), savedPath: chosen.path, defaultFolder: defaultFolder, bookmarks: FakeBookmarks(.fails)
        )
        #expect(result.folder == defaultFolder)
        #expect(result.status == .unavailable(path: chosen.path))
        #expect(result.accessedURL == nil)
    }

    @Test func aFolderWithoutPermissionFallsBack() {
        let bookmarks = FakeBookmarks(.resolves(chosen, stale: false))
        bookmarks.grantsAccess = false
        let result = ChatLogFolderResolution.resolve(
            bookmark: Data("x".utf8), savedPath: chosen.path, defaultFolder: defaultFolder, bookmarks: bookmarks, isDirectory: { _ in true }
        )
        #expect(result.folder == defaultFolder)
        #expect(result.status == .unavailable(path: chosen.path))
    }

    @Test func aMissingFolderFallsBackAndGivesUpAccess() {
        let bookmarks = FakeBookmarks(.resolves(chosen, stale: false))
        let result = ChatLogFolderResolution.resolve(
            bookmark: Data("x".utf8), savedPath: nil, defaultFolder: defaultFolder, bookmarks: bookmarks, isDirectory: { _ in false }
        )
        #expect(result.folder == defaultFolder)
        #expect(result.status == .unavailable(path: chosen.path))
        #expect(bookmarks.stopped == [chosen])
    }
}
