// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaIRC

/// Which log an entry goes to.
nonisolated public struct ChatLogTarget: Sendable, Hashable {
    public var networkID: UUID
    /// The network's folder (see `ChatLogNetworkFolders`).
    public var networkFolder: String
    /// The buffer's case-folded name, which identifies its log: `#Vela` and
    /// `#vela` share one.
    public var identity: String
    /// The file name, without `.log`, for a log that doesn't exist yet.
    /// An existing file whose name differs only in case is used instead.
    public var fileBase: String
    /// The server's case folding, for matching existing file names.
    public var caseMapping: CaseMapping

    public init(networkID: UUID, networkFolder: String, identity: String, fileBase: String, caseMapping: CaseMapping = .rfc1459) {
        self.networkID = networkID
        self.networkFolder = networkFolder
        self.identity = identity
        self.fileBase = fileBase
        self.caseMapping = caseMapping
    }
}

/// One line to log.
nonisolated public struct ChatLogEntry: Sendable {
    public var target: ChatLogTarget
    public var time: Date
    /// Replayed by a bouncer or the server (playback, `chathistory`) rather
    /// than seen live. See ``ChatLogWriter`` for when these are written.
    public var isHistory: Bool
    public var content: ChatLogContent

    public init(target: ChatLogTarget, time: Date, isHistory: Bool, content: ChatLogContent) {
        self.target = target
        self.time = time
        self.isHistory = isHistory
        self.content = content
    }
}

/// Where logs go and how big they get.
nonisolated public struct ChatLogConfiguration: Sendable, Equatable {
    /// The `Logs` folder: one folder per network inside.
    public var folder: URL
    /// Start a new file when one would grow past this. 0: no limit.
    public var maxFileBytes: Int64
    /// Files to keep per log, the current one included. 0: keep all.
    public var keepFiles: Int

    public init(folder: URL, maxFileBytes: Int64, keepFiles: Int) {
        self.folder = folder
        self.maxFileBytes = maxFileBytes
        self.keepFiles = keepFiles
    }
}

/// Writes chat logs off the main actor.
///
/// Lines are buffered and written about once a second (``flush()``), and
/// when logging stops (``closeAll()``). File handles stay open between
/// writes, up to `maxOpenHandles`, the least recently used closing first.
///
/// **Files.** The first line written to a file since logging started is
/// preceded by `--- Log opened … ---`; ``closeAll()`` ends each such file
/// with `--- Log closed … ---`. When a file would grow past
/// ``ChatLogConfiguration/maxFileBytes`` it's closed, renamed with the
/// dates it covers (`#vela 2026-11-01 – 2026-11-17.log`) and a new one
/// started; the oldest full files beyond ``ChatLogConfiguration/keepFiles``
/// are deleted.
///
/// **Replayed lines.** Live lines are always written. Lines a bouncer or
/// server replays (`isHistory`) are written only when they're newer than
/// the newest line the log had before this connection: when Vela first
/// opened the file this run, or when the network last disconnected. That
/// fills in what was said while Vela was closed or offline without
/// writing anything twice. A log Vela starts afresh takes no replayed
/// lines older than its first live line, so joining a channel doesn't
/// fill a new log with what was said before you joined. Lines Vela loads
/// from its own message database never reach the writer.
///
/// Errors (a full disk, a folder without permission) drop the lines that
/// couldn't be written and are reported through `onProblem`, which gets
/// nil again once a write succeeds.
public actor ChatLogWriter {
    private struct LogKey: Hashable {
        var networkID: UUID
        var identity: String
    }

    private struct LogFile {
        var url: URL
        var base: String
        var handle: FileHandle?
        var size: Int64 = 0
        /// Formatted lines not written yet.
        var pending: [String] = []
        /// The next write starts with "Log opened".
        var needsOpenMarker = true
        /// "Log opened" was written to this file since logging started,
        /// so stopping writes "Log closed".
        var isSessionOpen = false
        /// The newest line in the file or queued for it.
        var lastTime: Date?
        /// The newest line written to the file.
        var writtenUntil: Date?
        /// Replayed lines must be newer than this.
        var watermark: Date?
        var lastUse: UInt64 = 0
    }

    public private(set) var configuration: ChatLogConfiguration?
    /// The latest write problem, or nil.
    public private(set) var problem: String?

    private var files: [LogKey: LogFile] = [:]
    private var useCounter: UInt64 = 0
    private var flushTask: Task<Void, Never>?
    private let clock: ChatLogClock
    private let flushDelay: Duration
    private let maxOpenHandles: Int
    private let now: @Sendable () -> Date
    private let onProblem: @Sendable (String?) -> Void

    public init(
        clock: ChatLogClock = ChatLogClock(),
        flushDelay: Duration = .seconds(1),
        maxOpenHandles: Int = 32,
        now: @escaping @Sendable () -> Date = { Date() },
        onProblem: @escaping @Sendable (String?) -> Void = { _ in }
    ) {
        self.clock = clock
        self.flushDelay = flushDelay
        self.maxOpenHandles = max(1, maxOpenHandles)
        self.now = now
        self.onProblem = onProblem
    }

    // MARK: Configuration

    /// Sets where logs go and their limits; nil stops logging. A new
    /// folder closes every log in the old one first. New limits apply from
    /// the next write.
    public func configure(_ configuration: ChatLogConfiguration?) {
        if configuration?.folder.standardizedFileURL != self.configuration?.folder.standardizedFileURL {
            closeAll()
        }
        self.configuration = configuration
    }

    // MARK: Writing

    /// Queues `entry` (see the type's notes on replayed lines).
    public func append(_ entry: ChatLogEntry) {
        guard let configuration else { return }
        let key = LogKey(networkID: entry.target.networkID, identity: entry.target.identity)
        var file = files[key] ?? makeFile(for: entry.target, in: configuration.folder)
        if entry.isHistory {
            if let watermark = file.watermark, entry.time <= watermark {
                files[key] = file
                return
            }
            file.watermark = entry.time
        } else if file.watermark == nil {
            file.watermark = entry.time
        }
        file.pending.append(ChatLogFormat.line(entry.content, at: entry.time, clock: clock))
        file.lastTime = max(file.lastTime ?? entry.time, entry.time)
        useCounter += 1
        file.lastUse = useCounter
        files[key] = file
        scheduleFlush()
    }

    /// The network dropped: lines replayed after it reconnects are written
    /// only if they're newer than what its logs have now.
    public func networkDisconnected(_ networkID: UUID) {
        for key in Array(files.keys) where key.networkID == networkID {
            guard var file = files[key], let last = file.lastTime else { continue }
            file.watermark = max(file.watermark ?? last, last)
            files[key] = file
        }
    }

    /// A network's folder name changed (it was renamed): moves its folder,
    /// unless one with the new name exists already, and carries on there.
    public func renameNetworkFolder(_ networkID: UUID, from oldName: String, to newName: String) {
        guard let root = configuration?.folder, oldName != newName else { return }
        let keys = files.keys.filter { $0.networkID == networkID }
        for key in keys {
            if let problem = flush(key) { report(problem) }
        }
        for key in keys {
            guard var file = files[key] else { continue }
            closeHandle(&file)
            files[key] = file
        }
        let fileManager = FileManager.default
        let oldURL = root.appending(path: oldName, directoryHint: .isDirectory)
        let newURL = root.appending(path: newName, directoryHint: .isDirectory)
        let caseOnly = oldName.lowercased() == newName.lowercased()
        if fileManager.fileExists(atPath: oldURL.path), caseOnly || !fileManager.fileExists(atPath: newURL.path) {
            try? fileManager.moveItem(at: oldURL, to: newURL)
        }
        for key in keys {
            guard let base = files[key]?.base else { continue }
            files[key]?.url = newURL.appending(path: ChatLogNaming.currentFileName(base: base), directoryHint: .notDirectory)
        }
    }

    /// Writes everything queued.
    public func flush() {
        flushTask?.cancel()
        flushTask = nil
        var failure: String?
        for key in Array(files.keys) where files[key]?.pending.isEmpty == false {
            if let problem = flush(key), failure == nil { failure = problem }
        }
        report(failure)
    }

    /// Writes everything queued, ends each file written to since logging
    /// started with "Log closed", and closes every file.
    public func closeAll() {
        flush()
        let date = now()
        for key in Array(files.keys) {
            guard var file = files[key] else { continue }
            if file.isSessionOpen {
                do {
                    try openHandle(&file, key: key)
                    try file.handle?.write(contentsOf: Data((ChatLogFormat.closedMarker(at: date, clock: clock) + "\n").utf8))
                } catch {
                    // Nothing more to say about a file we're done with.
                }
            }
            closeHandle(&file)
            files[key] = nil
        }
        files = [:]
    }

    /// How many log files are open (for tests).
    public var openHandleCount: Int { files.values.count(where: { $0.handle != nil }) }

    // MARK: Files

    private func makeFile(for target: ChatLogTarget, in root: URL) -> LogFile {
        let folder = root.appending(path: target.networkFolder, directoryHint: .isDirectory)
        let base = existingBase(in: folder, matching: target) ?? target.fileBase
        var file = LogFile(url: folder.appending(path: ChatLogNaming.currentFileName(base: base), directoryHint: .notDirectory), base: base)
        if let tail = Self.readTail(of: file.url), let last = ChatLogFormat.lastLineTime(in: tail[...], clock: clock) {
            file.lastTime = last
            file.writtenUntil = last
            // Logs keep whole seconds: a replayed line in that second is
            // taken to be the same line.
            file.watermark = last.addingTimeInterval(0.999)
        }
        return file
    }

    /// An existing current log in `folder` whose name matches `target`'s
    /// under the server's case folding, so `#Vela.log` keeps being used
    /// for `#vela` (on case-sensitive disks too).
    private func existingBase(in folder: URL, matching target: ChatLogTarget) -> String? {
        let ext = ".\(ChatLogNaming.fileExtension)"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        if names.contains(ChatLogNaming.currentFileName(base: target.fileBase)) { return target.fileBase }
        let wanted = target.caseMapping.fold(target.fileBase)
        return names.lazy
            .filter { $0.hasSuffix(ext) && !ChatLogNaming.isRotatedFileName($0) }
            .map { String($0.dropLast(ext.count)) }
            .first { target.caseMapping.fold($0) == wanted }
    }

    /// Writes `key`'s queued lines, starting a new file first if they'd
    /// make it too big. Returns a problem to report, or nil.
    private func flush(_ key: LogKey) -> String? {
        guard var file = files[key], !file.pending.isEmpty, let configuration else { return nil }
        defer { files[key] = file }
        let date = now()
        let lines = file.pending.joined(separator: "\n") + "\n"
        let opened = ChatLogFormat.openedMarker(at: date, clock: clock) + "\n"
        do {
            try openHandle(&file, key: key)
            var data = Data(((file.needsOpenMarker ? opened : "") + lines).utf8)
            if configuration.maxFileBytes > 0, file.size > 0, file.size + Int64(data.count) > configuration.maxFileBytes {
                if let problem = rotate(&file, at: date, keep: configuration.keepFiles) {
                    report(problem)
                } else {
                    try openHandle(&file, key: key)
                    data = Data((opened + lines).utf8)
                }
            }
            try file.handle?.write(contentsOf: data)
            file.size += Int64(data.count)
            if file.needsOpenMarker {
                file.needsOpenMarker = false
                file.isSessionOpen = true
            }
            file.pending = []
            file.writtenUntil = file.lastTime
            return nil
        } catch {
            file.pending = []
            closeHandle(&file)
            return "Couldn't write \(file.url.lastPathComponent): \(Self.describe(error))"
        }
    }

    /// Ends the current file, renames it with the dates it covers and
    /// deletes full files beyond `keep`. Returns a problem, or nil.
    private func rotate(_ file: inout LogFile, at date: Date, keep: Int) -> String? {
        if file.isSessionOpen {
            try? file.handle?.write(contentsOf: Data((ChatLogFormat.closedMarker(at: date, clock: clock) + "\n").utf8))
        }
        closeHandle(&file)
        let start = Self.readHead(of: file.url).flatMap { ChatLogFormat.firstTime(in: $0[...], clock: clock) }
            ?? (try? file.url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? date
        let end = file.writtenUntil ?? start
        let folder = file.url.deletingLastPathComponent()
        let fileManager = FileManager.default
        var counter = 1
        var destination: URL
        repeat {
            let name = ChatLogNaming.rotatedFileName(base: file.base, from: clock.day(from: start), to: clock.day(from: max(start, end)), counter: counter)
            destination = folder.appending(path: name, directoryHint: .notDirectory)
            counter += 1
        } while fileManager.fileExists(atPath: destination.path)
        do {
            try fileManager.moveItem(at: file.url, to: destination)
        } catch {
            // Keep writing to the full file rather than losing lines.
            return "Couldn't start a new file for \(file.url.lastPathComponent): \(Self.describe(error))"
        }
        file.size = 0
        file.needsOpenMarker = true
        file.isSessionOpen = false
        Self.prune(in: folder, base: file.base, keep: keep)
        return nil
    }

    /// Deletes `base`'s oldest full files so that, with the current file,
    /// `keep` remain. 0 keeps everything.
    nonisolated static func prune(in folder: URL, base: String, keep: Int) {
        guard keep > 0, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let rotated = names.compactMap { name in ChatLogNaming.parseRotated(name, base: base).map { (name, $0) } }
            .sorted { lhs, rhs in
                // Newest first: by end date, then start date, then counter.
                if lhs.1.to != rhs.1.to { return lhs.1.to > rhs.1.to }
                if lhs.1.from != rhs.1.from { return lhs.1.from > rhs.1.from }
                return lhs.1.counter > rhs.1.counter
            }
        for (name, _) in rotated.dropFirst(keep - 1) {
            try? FileManager.default.removeItem(at: folder.appending(path: name, directoryHint: .notDirectory))
        }
    }

    private func openHandle(_ file: inout LogFile, key: LogKey) throws {
        useCounter += 1
        file.lastUse = useCounter
        guard file.handle == nil else { return }
        // Close the least recently used files to stay under the limit.
        let open = files.filter { $0.key != key && $0.value.handle != nil }
        if open.count >= maxOpenHandles {
            for (otherKey, _) in open.sorted(by: { $0.value.lastUse < $1.value.lastUse }).prefix(open.count - maxOpenHandles + 1) {
                guard var other = files[otherKey] else { continue }
                closeHandle(&other)
                files[otherKey] = other
            }
        }
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(file.url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        file.size = Int64(try handle.seekToEnd())
        file.handle = handle
    }

    private func closeHandle(_ file: inout LogFile) {
        try? file.handle?.close()
        file.handle = nil
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let delay = flushDelay
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func report(_ message: String?) {
        guard message != problem else { return }
        problem = message
        onProblem(message)
    }

    // MARK: Reading

    /// The last few kilobytes of `url`, if it exists.
    nonisolated static func readTail(of url: URL, bytes: Int = 8192) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        return (try? handle.readToEnd()).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The first few kilobytes of `url`, if it exists.
    nonisolated static func readHead(of url: URL, bytes: Int = 4096) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: bytes)).map { String(decoding: $0, as: UTF8.self) }
    }

    private nonisolated static func describe(_ error: Error) -> String {
        if let posix = error as? POSIXError { return String(cString: strerror(posix.code.rawValue)) }
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return String(cString: strerror(Int32(underlying.code)))
        }
        if nsError.domain == NSPOSIXErrorDomain { return String(cString: strerror(Int32(nsError.code))) }
        return nsError.localizedDescription
    }
}
