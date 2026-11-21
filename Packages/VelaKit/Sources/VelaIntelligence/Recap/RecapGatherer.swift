// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Darwin
import Foundation
import VelaCore
import VelaIRC
import VelaStore

/// Reads what a Recap covers: the lines in memory and, while message
/// history is read from disk, the saved ones, filtered by the scope.
///
/// Only taking the snapshot happens on the main actor, and it's cheap:
/// each buffer's lines are copied by reference. Reading saved history,
/// merging, filtering and capping run off it (``collect(_:)``), so a
/// network of busy channels doesn't hold up the window.
@MainActor
public struct RecapGatherer {
    public let app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    /// The scope's lines, as of `now`.
    public func gather(_ scope: RecapScope, now: Date = Date()) async -> RecapInput {
        let request = snapshot(scope, now: now)
        return await Self.collect(request)
    }

    // MARK: Snapshot (main actor)

    /// Where the unread lines start in a buffer.
    nonisolated enum UnreadStart: Sendable, Hashable {
        /// After this time: the New marker, or the read position.
        case after(Date)
        /// The last `count` messages from others: a buffer with unread
        /// messages and no read position (demo mode's sample channels).
        case lastLines(Int)
    }

    /// One buffer as it is when the Recap is asked for.
    nonisolated struct BufferSnapshot: Sendable {
        var id: BufferID
        var name: String
        var networkName: String
        var isChannel: Bool
        var ownNick: String
        var caseMapping: CaseMapping
        var lines: [ChatLine]
        var unreadStart: UnreadStart?
        /// Its oldest lines were dropped to keep to the scrollback limit
        /// (`chat.scrollbackInMemory`).
        var isTrimmed = false
    }

    /// Everything ``collect(_:)`` needs, taken on the main actor.
    nonisolated struct Request: Sendable {
        var scope: RecapScope
        var buffers: [BufferSnapshot]
        /// Saved history, while it's read (`history.save`, or kept).
        var database: VelaDatabase?
        var now: Date
        var limit = RecapLimits.gatheredLines
        /// Since when Vela has been collecting messages in memory: when it
        /// started. A quiet channel with nothing older isn't missing
        /// anything said after this.
        var collectingSince: Date = .distantFuture
    }

    func snapshot(_ scope: RecapScope, now: Date) -> Request {
        let buffers: [(NetworkSession, BufferModel)]
        switch scope.place {
        case .buffer(let id):
            buffers = app.lookup(id).map { [($0.session, $0.buffer)] } ?? []
        case .network(let id):
            buffers = app.session(for: id).map { session in
                app.conversationBuffers.filter { $0.id.networkID == id }.map { (session, $0) }
            } ?? []
        case .everywhere:
            buffers = app.conversationBuffers.compactMap { buffer in
                app.session(for: buffer.id.networkID).map { ($0, buffer) }
            }
        }
        let limit = app.behavior.scrollbackInMemory
        let snapshots = buffers.filter { $0.1.kind != .server }.map { session, buffer in
            BufferSnapshot(
                id: buffer.id,
                name: buffer.name,
                networkName: session.displayName,
                isChannel: buffer.kind == .channel,
                ownNick: session.nick,
                caseMapping: session.isupport.caseMapping,
                lines: buffer.lines,
                unreadStart: unreadStart(buffer),
                isTrimmed: buffer.lines.count >= limit
            )
        }
        return Request(
            scope: scope,
            buffers: snapshots,
            database: app.historyStorage.loads ? app.database : nil,
            now: now,
            // Demo mode's sample channels aren't missing anything.
            collectingSince: app.isDemo ? .distantPast : Self.processStart
        )
    }

    /// Where `buffer`'s unread messages start, if it has any: under its New
    /// marker, or after the read position. The buffer on screen has read
    /// everything except what's under its marker.
    private func unreadStart(_ buffer: BufferModel) -> UnreadStart? {
        if let marker = buffer.unreadMarkerAfter { return .after(marker) }
        guard app.selectedBufferID != buffer.id else { return nil }
        if buffer.unreadCount > 0 {
            if let read = buffer.lastReadAt { return .after(read) }
            return .lastLines(buffer.unreadCount)
        }
        // Just launched: the live counts start at zero, but the history
        // restored for the buffer shows what came after you last read it.
        if !app.isDemo, let read = buffer.lastReadAt, buffer.unreadByReadPosition.unread > 0 {
            return .after(read)
        }
        return nil
    }

    /// When this process started, from the kernel.
    nonisolated static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }()

    // MARK: Collecting (off the main actor)

    /// Reads saved history for `request`, merges it with the lines in
    /// memory, and keeps what the scope asks for, up to `request.limit`
    /// of the newest lines.
    @concurrent
    nonisolated static func collect(_ request: Request) async -> RecapInput {
        let scope = request.scope
        let requestedStart = scope.span.start(now: request.now)
        var saved: [BufferID: [MessageRecord]] = [:]
        var savedOldest: [BufferID: Date] = [:]
        if let database = request.database {
            (saved, savedOldest) = await readSaved(request, from: database, requestedStart: requestedStart)
        }

        var conversations: [RecapConversation] = []
        for buffer in request.buffers {
            if Task.isCancelled { break }
            let conversation = Self.conversation(
                buffer,
                saved: saved[buffer.id] ?? [],
                savedOldest: savedOldest[buffer.id],
                scope: scope,
                requestedStart: requestedStart,
                now: request.now,
                collectingSince: request.collectingSince
            )
            if !conversation.lines.isEmpty { conversations.append(conversation) }
        }
        let matching = conversations.reduce(0) { $0 + $1.lines.count }
        if matching > request.limit { conversations = keepNewest(request.limit, of: conversations) }
        return RecapInput(
            scope: scope,
            conversations: conversations,
            requestedStart: requestedStart,
            end: request.now,
            matchingLines: matching,
            readsSavedHistory: request.database != nil
        )
    }

    /// Saved lines newer than the stretch's start, by buffer, and the
    /// oldest saved line in each. One query per network (or for the one
    /// buffer), on the database's reader.
    nonisolated private static func readSaved(
        _ request: Request,
        from database: VelaDatabase,
        requestedStart: Date?
    ) async -> ([BufferID: [MessageRecord]], [BufferID: Date]) {
        var saved: [BufferID: [MessageRecord]] = [:]
        var oldest: [BufferID: Date] = [:]
        let byNetwork = Dictionary(grouping: request.buffers, by: \.id.networkID)
        for (networkID, buffers) in byNetwork {
            let wanted = Set(buffers.map(\.id.foldedName))
            if let times = try? await database.oldestMessageTimes(networkID: networkID) {
                for (name, time) in times where wanted.contains(name) {
                    oldest[BufferID(networkID: networkID, foldedName: name)] = time
                }
            }
            // "Since your first unread": from the earliest New marker or
            // read position among them. A buffer that's never been read
            // counts back from what's in memory.
            let after: Date? = requestedStart ?? buffers.compactMap { buffer -> Date? in
                if case .after(let date) = buffer.unreadStart { return date }
                return nil
            }.min()
            guard let after else { continue }
            let single = request.scope.place == .buffer(buffers[0].id) ? buffers[0].id.foldedName : nil
            guard let records = try? await database.conversation(
                networkID: networkID,
                bufferName: single,
                after: after,
                mentioning: request.scope.person,
                limit: request.limit
            ) else { continue }
            for record in records where wanted.contains(record.bufferName) {
                saved[BufferID(networkID: networkID, foldedName: record.bufferName), default: []].append(record)
            }
        }
        return (saved, oldest)
    }

    /// One buffer's lines for `scope`: memory and saved history merged,
    /// within the stretch, through the Who filter.
    nonisolated static func conversation(
        _ buffer: BufferSnapshot,
        saved: [MessageRecord],
        savedOldest: Date?,
        scope: RecapScope,
        requestedStart: Date?,
        now: Date,
        collectingSince: Date = .distantFuture
    ) -> RecapConversation {
        let own = buffer.caseMapping.fold(buffer.ownNick)
        var lines = merged(memory: buffer.lines, saved: saved, ownNick: own, caseMapping: buffer.caseMapping)

        // Where the stretch starts here.
        var start = requestedStart
        var unreadFrom: Date?
        switch buffer.unreadStart {
        case .after(let date)?: unreadFrom = date
        case .lastLines(let count)?: unreadFrom = startOfLast(count, in: lines)
        case nil: break
        }
        if case .sinceUnread = scope.span { start = unreadFrom ?? .distantFuture }
        let from = start ?? .distantPast
        lines = lines.filter { $0.time > from && $0.time <= now }

        let yourLines = lines.filter(\.isSelf)
        if let person = scope.person {
            lines = filter(lines, person: person, in: buffer)
        }
        let unread = unreadFrom.map { cutoff in lines.count { !$0.isSelf && $0.time > cutoff } } ?? 0

        // What's in memory goes back to its oldest line, or, unless lines
        // were dropped for the scrollback limit, to when Vela started.
        let memoryOldest = buffer.lines.first?.time
        let memorySince = buffer.isTrimmed ? memoryOldest : [memoryOldest, collectingSince].compactMap { $0 }.min()
        let availableSince = [memorySince, savedOldest].compactMap { $0 }.min().flatMap { $0 == .distantFuture ? nil : $0 }
        let startsBeforeHistory: Bool
        if let availableSince, from != .distantPast, from < .distantFuture {
            startsBeforeHistory = from < availableSince.addingTimeInterval(-60)
        } else {
            startsBeforeHistory = false
        }
        return RecapConversation(
            id: buffer.id,
            name: buffer.name,
            networkName: buffer.networkName,
            isChannel: buffer.isChannel,
            ownNick: buffer.ownNick,
            lines: lines,
            yourLines: yourLines,
            availableSince: availableSince,
            startsBeforeHistory: startsBeforeHistory,
            unreadLines: unread
        )
    }

    /// The conversation lines in memory and saved history, once each,
    /// oldest first. Saved copies of lines in memory (same id or msgid) are
    /// dropped; deleted (redacted) lines are left out.
    nonisolated static func merged(memory: [ChatLine], saved: [MessageRecord], ownNick: String, caseMapping: CaseMapping) -> [RecapLine] {
        var seenIDs = Set<UUID>()
        var seenMsgids = Set<String>()
        var lines: [RecapLine] = []
        lines.reserveCapacity(memory.count + saved.count)
        for line in memory where line.kind.isConversation && !line.isRedacted {
            seenIDs.insert(line.id)
            if let msgid = line.msgid { seenMsgids.insert(msgid) }
            lines.append(RecapLine(
                id: line.id,
                time: line.time,
                nick: line.nick ?? "",
                text: IRCFormatting.strip(line.text),
                kind: RecapLine.Kind(rawValue: line.kind.rawValue) ?? .message,
                isSelf: line.isSelf || (!ownNick.isEmpty && caseMapping.fold(line.nick ?? "") == ownNick),
                isHighlight: line.isHighlight,
                msgid: line.msgid,
                replyTo: line.replyTo
            ))
        }
        guard !saved.isEmpty else { return lines }
        var added = false
        for record in saved where !record.isRedacted && !seenIDs.contains(record.id) {
            if let msgid = record.msgid, seenMsgids.contains(msgid) { continue }
            guard let kind = RecapLine.Kind(rawValue: record.kind) else { continue }
            added = true
            lines.append(RecapLine(
                id: record.id,
                time: record.time,
                nick: record.nick ?? "",
                text: IRCFormatting.strip(record.text),
                kind: kind,
                isSelf: record.isSelf || (!ownNick.isEmpty && caseMapping.fold(record.nick ?? "") == ownNick),
                isHighlight: record.isHighlight,
                msgid: record.msgid,
                replyTo: record.replyTo
            ))
        }
        if added { lines.sort { $0.time < $1.time } }
        return lines
    }

    /// Just before the `count`th newest message from someone else.
    nonisolated static func startOfLast(_ count: Int, in lines: [RecapLine]) -> Date {
        var remaining = count
        for line in lines.reversed() where !line.isSelf {
            remaining -= 1
            if remaining == 0 { return line.time.addingTimeInterval(-0.001) }
        }
        return .distantPast
    }

    /// The lines about `person`: theirs, ones that name them or reply to
    /// them, and all of a private conversation with them.
    nonisolated static func filter(_ lines: [RecapLine], person: String, in buffer: BufferSnapshot) -> [RecapLine] {
        let mapping = buffer.caseMapping
        let key = mapping.fold(person)
        if !buffer.isChannel, buffer.id.foldedName == key { return lines }
        let theirs = Set(lines.compactMap { mapping.fold($0.nick) == key ? $0.msgid : nil })
        return lines.filter { line in
            if mapping.fold(line.nick) == key { return true }
            if let reply = line.replyTo, theirs.contains(reply) { return true }
            return CatchUpTranscript.containsWord(key, in: mapping.fold(line.text))
        }
    }

    /// The newest `limit` lines across `conversations`.
    nonisolated static func keepNewest(_ limit: Int, of conversations: [RecapConversation]) -> [RecapConversation] {
        var times = conversations.flatMap { $0.lines.map(\.time) }
        guard times.count > limit, limit > 0 else { return limit > 0 ? conversations : [] }
        times.sort(by: >)
        let cutoff = times[limit - 1]
        // Lines at the cutoff's own time can tip it over; trim the oldest.
        var remaining = limit
        var kept = conversations.map { conversation -> RecapConversation in
            var copy = conversation
            copy.lines = conversation.lines.filter { $0.time > cutoff }
            remaining -= copy.lines.count
            return copy
        }
        for index in kept.indices where remaining > 0 {
            let atCutoff = conversations[index].lines.filter { $0.time == cutoff }
            let take = atCutoff.suffix(remaining)
            remaining -= take.count
            kept[index].lines = (take + kept[index].lines).sorted { $0.time < $1.time }
        }
        return kept.filter { !$0.lines.isEmpty }
    }
}
