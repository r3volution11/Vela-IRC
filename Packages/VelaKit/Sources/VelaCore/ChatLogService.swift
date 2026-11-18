// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import VelaIRC
import VelaStore

/// A problem saving chat logs, shown in Settings.
nonisolated public struct ChatLogProblem: Sendable, Equatable {
    public var message: String
    public var date: Date
}

/// Plain-text chat logs (`logging.*` settings): decides what's logged and
/// where, and hands lines to a ``ChatLogWriter`` off the main actor.
///
/// Sessions report each line they add (``AppModel`` forwards it here).
/// Lines Vela restores from its message database at launch, or loads when
/// you scroll up, aren't added that way, so they're never logged again.
/// Demo mode never logs.
@Observable
public final class ChatLogService {
    /// Where logs are going.
    public private(set) var folderURL: URL
    public private(set) var folderStatus: ChatLogFolderStatus = .standard
    /// The latest problem writing logs, until a write succeeds.
    public private(set) var problem: ChatLogProblem?
    /// `Logs` in Vela's data folder.
    public let defaultFolderURL: URL
    public let isDemo: Bool

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let preferences: ChatLogPreferences
    @ObservationIgnored private let bookmarks: any ChatLogBookmarks
    @ObservationIgnored private let writer: ChatLogWriter
    @ObservationIgnored private let commands: AsyncStream<Command>.Continuation
    @ObservationIgnored private var consumer: Task<Void, Never>?
    @ObservationIgnored private let networkFolders: ChatLogNetworkFolders
    /// The chosen folder while its security scope is in use.
    @ObservationIgnored private var accessedURL: URL?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var configured: ChatLogConfiguration?
    @ObservationIgnored private let displayDefaultFolder: URL
    @ObservationIgnored private var fileBases: [BufferID: (name: String, base: String)] = [:]
    @ObservationIgnored private var exclusions: (entries: [String], list: BufferScopeList) = ([], BufferScopeList())

    /// What the writer does next, in order.
    enum Command: Sendable {
        case configure(ChatLogConfiguration?)
        case append(ChatLogEntry)
        case disconnected(UUID)
        case rename(UUID, from: String, to: String)
        case flush
        case barrier(@Sendable () -> Void)
    }

    public init(
        settings: SettingsStore,
        defaultFolder: URL,
        preferences: ChatLogPreferences,
        bookmarks: any ChatLogBookmarks = SecurityScopedBookmarks(),
        isDemo: Bool = false,
        flushDelay: Duration = .seconds(1)
    ) {
        self.settings = settings
        self.defaultFolderURL = defaultFolder
        self.folderURL = defaultFolder
        self.preferences = preferences
        self.bookmarks = bookmarks
        self.isDemo = isDemo
        self.networkFolders = ChatLogNetworkFolders(saved: preferences.networkFolders)
        // Demo mode logs nothing, but Settings shows where logs would go.
        self.displayDefaultFolder = isDemo ? Self.liveDefaultFolder ?? defaultFolder : defaultFolder

        let relay = ProblemRelay()
        self.writer = ChatLogWriter(flushDelay: flushDelay, onProblem: { message in
            Task { @MainActor in relay.service?.writerReported(message) }
        })
        let (stream, continuation) = AsyncStream<Command>.makeStream()
        self.commands = continuation
        relay.service = self
        // One consumer keeps commands in order; it never needs the main
        // actor, so quitting can wait for it.
        let writer = self.writer
        consumer = Task.detached(priority: .utility) {
            for await command in stream {
                switch command {
                case .configure(let configuration): await writer.configure(configuration)
                case .append(let entry): await writer.append(entry)
                case .disconnected(let networkID): await writer.networkDisconnected(networkID)
                case .rename(let networkID, let from, let to): await writer.renameNetworkFolder(networkID, from: from, to: to)
                case .flush: await writer.flush()
                case .barrier(let done): done()
                }
            }
        }
    }

    deinit {
        commands.finish()
    }

    /// Whether lines are being logged now.
    public var isLogging: Bool { started && settings[.loggingEnabled] }

    /// Looks up the saved folder and starts following the settings. Does
    /// nothing in demo mode. `networkIDs` are the networks that exist, so
    /// folder names of removed ones can be reused.
    public func start(networkIDs: Set<UUID>) {
        guard !started, !isDemo else { return }
        started = true
        networkFolders.prune(keeping: networkIDs)
        preferences.networkFolders = networkFolders.names
        resolveFolder()
        applySettings()
        observeSettings()
    }

    // MARK: Lines

    /// Logs `line`, just added to `buffer`, if the settings want it.
    func record(_ line: ChatLine, in buffer: BufferModel, session: NetworkSession) {
        guard isLogging, wantsLog(of: buffer),
              ChatLogPolicy.includes(line.kind, in: buffer.kind, events: settings[.loggingIncludeEvents])
        else { return }
        prepareWriter()
        commands.yield(.append(ChatLogEntry(
            target: target(for: buffer, in: session),
            time: line.time,
            isHistory: line.isHistory,
            content: .line(kind: line.kind, nick: line.nick, text: line.text, isSelf: line.isSelf)
        )))
    }

    /// Notes that `line` was deleted (IRCv3 `REDACT`). Its own log line
    /// stays as it was written.
    func recordRedaction(of line: ChatLine, by nick: String?, reason: String?, at time: Date, isHistory: Bool, in buffer: BufferModel, session: NetworkSession) {
        guard isLogging, wantsLog(of: buffer) else { return }
        prepareWriter()
        commands.yield(.append(ChatLogEntry(
            target: target(for: buffer, in: session),
            time: time,
            isHistory: isHistory,
            content: .redaction(by: nick, originalNick: line.nick, originalTime: line.time, reason: reason)
        )))
    }

    /// A network's connection changed. When it drops, lines replayed after
    /// it reconnects are logged only if they're newer than its logs.
    func connectionChanged(_ session: NetworkSession) {
        guard started, session.connectionState == .disconnected else { return }
        commands.yield(.disconnected(session.id))
    }

    /// Whether `bufferID` (or its network) is in `logging.excludedBuffers`.
    public func isExcluded(_ bufferID: BufferID) -> Bool {
        let entries = settings[.loggingExcludedBuffers]
        if entries != exclusions.entries { exclusions = (entries, BufferScopeList(entries)) }
        return exclusions.list.contains(bufferID)
    }

    private func wantsLog(of buffer: BufferModel) -> Bool {
        if buffer.kind == .server, !settings[.loggingIncludeServer] { return false }
        return !isExcluded(buffer.id)
    }

    /// Logging was just turned on: configure the writer before anything
    /// else reaches it (a network folder to move, the first line).
    private func prepareWriter() {
        if configured == nil { applySettings() }
    }

    private func target(for buffer: BufferModel, in session: NetworkSession) -> ChatLogTarget {
        let base: String
        if let cached = fileBases[buffer.id], cached.name == buffer.name {
            base = cached.base
        } else {
            base = ChatLogNaming.fileBase(bufferName: buffer.name, kind: buffer.kind)
            fileBases[buffer.id] = (buffer.name, base)
        }
        return ChatLogTarget(
            networkID: session.id,
            networkFolder: networkFolder(for: session),
            identity: buffer.id.foldedName,
            fileBase: base,
            caseMapping: session.isupport.caseMapping
        )
    }

    /// The network's folder name; a renamed network's folder moves along.
    private func networkFolder(for session: NetworkSession) -> String {
        let previous = networkFolders.names[session.id.uuidString]
        let name = networkFolders.folderName(for: session.id, displayName: session.displayName)
        guard previous != name else { return name }
        if let previous { commands.yield(.rename(session.id, from: previous, to: name)) }
        if !isDemo { preferences.networkFolders = networkFolders.names }
        return name
    }

    // MARK: Settings

    private func applySettings() {
        let configuration: ChatLogConfiguration? = isLogging ? ChatLogConfiguration(
            folder: folderURL,
            maxFileBytes: Int64(max(1, settings[.loggingMaxFileSizeMB])) * 1_048_576,
            keepFiles: max(0, settings[.loggingKeepFiles])
        ) : nil
        guard configuration != configured else { return }
        configured = configuration
        commands.yield(.configure(configuration))
        if configuration == nil { problem = nil }
    }

    /// Follows the logging settings, whether they change in Settings or
    /// settings.json. Turning logging off writes what's queued and closes
    /// every log.
    private func observeSettings() {
        withObservationTracking {
            _ = settings[.loggingEnabled]
            _ = settings[.loggingMaxFileSizeMB]
            _ = settings[.loggingKeepFiles]
        } onChange: { [weak self] in
            // Runs before the change lands; act on it right after.
            Task { @MainActor in
                self?.applySettings()
                self?.observeSettings()
            }
        }
    }

    private func writerReported(_ message: String?) {
        problem = message.map { ChatLogProblem(message: $0, date: Date()) }
    }

    // MARK: Folder

    /// The folder's path for display, from your home folder (`~/…`).
    public var displayPath: String {
        Self.abbreviate(folderStatus == .standard ? displayDefaultFolder.path : folderURL.path)
    }

    /// Logs go to `url` from now on, remembered with a security-scoped
    /// bookmark. Throws when the bookmark can't be made.
    public func chooseFolder(_ url: URL) throws {
        let accessing = bookmarks.startAccessing(url)
        let bookmark: Data
        do {
            bookmark = try bookmarks.bookmarkData(for: url)
        } catch {
            if accessing { bookmarks.stopAccessing(url) }
            throw error
        }
        preferences.folderBookmark = bookmark
        preferences.folderPath = url.path
        switchFolder(to: url, status: .custom, accessing: accessing ? url : nil)
    }

    /// Logs go to Vela's folder from now on; the chosen folder is forgotten.
    public func useDefaultFolder() {
        preferences.folderBookmark = nil
        preferences.folderPath = nil
        switchFolder(to: defaultFolderURL, status: .standard, accessing: nil)
    }

    /// The logs folder, created if needed, to show in Finder.
    public func folderForShowing() -> URL {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    /// Writes everything queued and waits until it's on disk.
    public func flush() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            commands.yield(.flush)
            commands.yield(.barrier { continuation.resume() })
        }
    }

    /// Vela is quitting: writes what's queued, ends each log with "Log
    /// closed" and waits (up to 2 seconds) for that to finish.
    public func shutdown() {
        guard started else { return }
        let done = DispatchSemaphore(value: 0)
        commands.yield(.configure(nil))
        commands.yield(.barrier { done.signal() })
        _ = done.wait(timeout: .now() + 2)
        configured = nil
    }

    private func resolveFolder() {
        let resolution = ChatLogFolderResolution.resolve(
            bookmark: preferences.folderBookmark,
            savedPath: preferences.folderPath,
            defaultFolder: defaultFolderURL,
            bookmarks: bookmarks
        )
        if let refreshed = resolution.refreshedBookmark { preferences.folderBookmark = refreshed }
        accessedURL = resolution.accessedURL
        folderURL = resolution.folder
        folderStatus = resolution.status
    }

    private func switchFolder(to url: URL, status: ChatLogFolderStatus, accessing: URL?) {
        let previous = accessedURL
        accessedURL = accessing
        folderURL = url
        folderStatus = status
        problem = nil
        configured = nil
        applySettings()
        // Give up the old folder once its logs are closed.
        if let previous {
            let bookmarks = bookmarks
            commands.yield(.barrier { bookmarks.stopAccessing(previous) })
        }
    }

    /// Where Vela's folder is in the real app, for showing in demo mode.
    private static var liveDefaultFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Vela/Logs", directoryHint: .isDirectory)
    }

    /// `/Users/doug/Logs` → `~/Logs`, using your real home folder (not the
    /// sandbox container's).
    static func abbreviate(_ path: String) -> String {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir.map({ String(cString: $0) }),
              !home.isEmpty, path == home || path.hasPrefix(home + "/")
        else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

/// Lets the writer's problem reports find the service, which owns it.
@MainActor
private final class ProblemRelay {
    weak var service: ChatLogService?
}
