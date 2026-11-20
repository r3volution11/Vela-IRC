// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaStore

/// A channel you removed or hid, or a conversation you closed, with what it
/// takes to put it back as it was. It holds no live objects, so it outlasts
/// the buffer and its tab. See ``AppModel/recentlyClosed``.
nonisolated public struct ClosedBuffer: Identifiable, Hashable, Sendable {
    /// The buffer it was. Reopening it gets the same id, so its drafts,
    /// sent-message history and per-channel settings are still there.
    public let id: BufferID
    public let name: String
    public let kind: BufferKind
    /// The network's name when it was closed.
    public let networkName: String
    /// Its place among the network's channels, or among its conversations.
    public let index: Int
    public let isMuted: Bool
    /// How far it had been read, where the "New" line goes.
    public let lastReadAt: Date?
    public let unreadCount: Int
    public let highlightCount: Int
    /// A channel: whether it's joined again, now or on the next connect.
    /// False after `/part`.
    public let autoRejoin: Bool
    /// A channel: whether you were in it.
    public let wasJoined: Bool
    /// Whether it was the selected channel or conversation.
    public let wasSelected: Bool
    /// A channel: its entry in the network's auto-join list, and where it
    /// was. For a channel you'd left, the entry it had before.
    public let autoJoin: AutoJoinChannel?
    public let autoJoinIndex: Int?
    /// A channel: its key, taken out of the Keychain while it's removed and
    /// written back when it's reopened. Kept in memory only.
    let key: String?
    /// A channel detached on a bouncer.
    public var wasDetached = false
    /// A channel hidden rather than removed (Hide Channel): it's still on
    /// the bouncer, detached, and reopening it shows it again.
    public var wasHidden = false
}

/// The undo manager's target for one buffer's undo and redo.
final class CloseUndoTarget {}

extension SessionHost {
    public func session(_ session: NetworkSession, didOpen buffer: BufferModel) {}
}

// MARK: - Leaving, removing and reopening

extension AppModel {
    /// How many removed channels and closed conversations ``recentlyClosed``
    /// keeps.
    public static let recentlyClosedLimit = 20

    /// Takes a channel or conversation out of the list: Remove Channel, or
    /// Close Conversation. A joined channel is left first (on a bouncer,
    /// one Vela isn't in is parted too, so the bouncer forgets it), and a
    /// channel comes off its network's auto-join list (its key comes out of
    /// the Keychain). If it was selected, its neighbor to the right (or
    /// left, at the end) is selected, like a browser tab.
    ///
    /// It's remembered in ``recentlyClosed`` for ⇧⌘T and File → Recently
    /// Closed, and ⌘Z puts it back, unless `reopenable` is false (a
    /// conversation Siri opened and gave up on). `/close` comes here too.
    public func close(_ buffer: BufferModel, reopenable: Bool = true) {
        guard buffer.kind != .server,
              let session = session(for: buffer.id.networkID),
              session.buffer(id: buffer.id) === buffer
        else { return }
        var closed: ClosedBuffer?
        if reopenable {
            // Its key goes before its entry, which says it has one.
            let account = Keychain.channelKeyAccount(networkID: session.id, channel: buffer.id.foldedName)
            let removed = buffer.kind == .channel ? session.takeAutoJoin(buffer.id.foldedName) : nil
            var key: String?
            if removed?.entry.hasKey == true {
                key = keychain.secret(account: account)
                keychain.deleteSecret(account: account)
            }
            closed = closedBuffer(buffer, in: session, autoJoin: removed, key: key)
            remember(closed!)
        }
        selectNeighbor(of: buffer, in: session)
        session.close(buffer)
        if let closed { registerUndoClose(closed) }
    }

    /// Leaves a channel but keeps it in the list, dimmed: Leave Channel on a
    /// network without a bouncer, and `/part` everywhere. It comes off the
    /// network's auto-join list, so it stays left when you reconnect, and
    /// joining it again puts the entry back. ⌘Z joins it again.
    public func leave(_ channel: BufferModel, reason: String? = nil) {
        guard channel.kind == .channel,
              let session = session(for: channel.id.networkID),
              session.buffer(id: channel.id) === channel
        else { return }
        session.leave(channel, reason: reason)
        registerUndo("Leave Channel", for: channel.id) { app, id in app.undoLeave(id) }
    }

    /// Leave Channel through a bouncer: Vela leaves the channel, the bouncer
    /// stays in it and keeps its history, and the channel stays in the list,
    /// dimmed (see `NetworkSession.detach(_:)`). ⌘Z joins it again, which
    /// reattaches it.
    public func detach(_ channel: BufferModel) {
        guard channel.kind == .channel,
              let session = session(for: channel.id.networkID),
              session.isBouncer,
              session.buffer(id: channel.id) === channel
        else { return }
        session.detach(channel)
        registerUndo("Leave Channel", for: channel.id) { app, id in app.undoLeave(id, detaching: true) }
    }

    /// Hide Channel: takes a detached bouncer channel out of the list
    /// (tabs, sidebar and rail) without parting it. It goes in Recently
    /// Closed, so ⇧⌘T and ⌘Z show it again, and the network's settings and
    /// the command palette can show it too.
    public func hide(_ channel: BufferModel) {
        guard let session = session(for: channel.id.networkID),
              session.canHide(channel)
        else { return }
        var closed = closedBuffer(channel, in: session, autoJoin: nil, key: nil)
        closed.wasHidden = true
        remember(closed)
        selectNeighbor(of: channel, in: session)
        session.hide(channel)
        registerUndoClose(closed)
    }

    /// Join Channel on a channel you left or detached: joins it with its key,
    /// puts a left channel back on the auto-join list, and has the bouncer
    /// reattach a detached one and play back what you missed.
    public func rejoin(_ channel: BufferModel) {
        guard channel.kind == .channel,
              let session = session(for: channel.id.networkID),
              session.buffer(id: channel.id) === channel
        else { return }
        session.rejoin(channel)
    }

    /// Puts a hidden channel back in the list, still detached, and selects it
    /// if `selecting`. Returns it.
    @discardableResult
    public func show(_ hidden: HiddenChannel, selecting: Bool = true) -> BufferModel? {
        guard let session = session(for: hidden.id.networkID) else { return nil }
        if let closed = recentlyClosed.first(where: { $0.id == hidden.id }) {
            // Hidden this run: back as it was, unread counts and all.
            dropUndo(for: closed.id)
            return restore(closed, selecting: selecting)
        }
        let channel = session.showHiddenChannel(hidden.id)
        if selecting, let channel { select(channel) }
        return channel
    }

    /// Every network's hidden channels, with the network, for the command
    /// palette.
    public var hiddenChannels: [(channel: HiddenChannel, session: NetworkSession)] {
        sessions.flatMap { session in session.hiddenChannels.map { (channel: $0, session: session) } }
    }

    /// Reopens the channel or conversation closed last (⇧⌘T). Again goes
    /// further back.
    public func reopenLastClosed() {
        guard let latest = recentlyClosed.first else { return }
        reopen(latest)
    }

    /// Reopens `closed` where it was, selects it, and takes it off
    /// ``recentlyClosed``. A channel goes back on its network's auto-join
    /// list, and is joined again now, or when its network connects.
    public func reopen(_ closed: ClosedBuffer) {
        // Its ⌘Z would have nothing left to undo.
        dropUndo(for: closed.id)
        restore(closed, selecting: true)
    }

    /// "#vela — Libera.Chat", for menus.
    public func menuTitle(for closed: ClosedBuffer) -> String {
        "\(closed.name) — \(networkName(for: closed))"
    }

    /// The network's name now, or when it was closed.
    public func networkName(for closed: ClosedBuffer) -> String {
        session(for: closed.id.networkID)?.displayName ?? closed.networkName
    }

    /// Forgets what was closed on a network that's being removed.
    func forgetClosed(inNetwork networkID: UUID) {
        recentlyClosed.removeAll { $0.id.networkID == networkID }
        for id in closeUndoTargets.keys where id.networkID == networkID { dropUndo(for: id) }
    }

    // MARK: SessionHost

    public func session(_ session: NetworkSession, didOpen buffer: BufferModel) {
        // Opened again another way (joined, a new message): there's nothing
        // left to reopen.
        guard recentlyClosed.contains(where: { $0.id == buffer.id }) else { return }
        recentlyClosed.removeAll { $0.id == buffer.id }
        dropUndo(for: buffer.id)
    }

    // MARK: Helpers

    private func closedBuffer(
        _ buffer: BufferModel,
        in session: NetworkSession,
        autoJoin: LeftAutoJoin?,
        key: String?
    ) -> ClosedBuffer {
        let siblings = session.bufferSiblings(of: buffer)
        return ClosedBuffer(
            id: buffer.id,
            name: buffer.name,
            kind: buffer.kind,
            networkName: session.displayName,
            index: siblings.firstIndex { $0.id == buffer.id } ?? siblings.count,
            isMuted: buffer.isMuted,
            lastReadAt: buffer.lastReadAt,
            unreadCount: buffer.unreadCount,
            highlightCount: buffer.highlightCount,
            autoRejoin: session.rejoins(buffer),
            wasJoined: buffer.isJoined,
            wasSelected: selectedBufferID == buffer.id,
            autoJoin: autoJoin?.entry,
            autoJoinIndex: autoJoin?.index,
            key: key,
            wasDetached: buffer.isDetached
        )
    }

    /// If `buffer` is selected, selects its neighbor to the right (or left,
    /// at the end), like closing a browser tab.
    private func selectNeighbor(of buffer: BufferModel, in session: NetworkSession) {
        guard selectedBufferID == buffer.id else { return }
        let tabs = session.allBuffers
        let index = tabs.firstIndex { $0.id == buffer.id } ?? 0
        let neighbor = tabs.indices.contains(index + 1) ? tabs[index + 1] : tabs[max(0, index - 1)]
        select(neighbor.id == buffer.id ? session.serverBuffer : neighbor)
    }

    /// Puts `closed` first, once, and keeps the newest ``recentlyClosedLimit``.
    private func remember(_ closed: ClosedBuffer) {
        var list = recentlyClosed
        list.removeAll { $0.id == closed.id }
        list.insert(closed, at: 0)
        if list.count > Self.recentlyClosedLimit { list.removeLast(list.count - Self.recentlyClosedLimit) }
        recentlyClosed = list
    }

    /// Reopens `closed` (or finds it already open again) and takes it off
    /// the list: its key and auto-join entry go back first, so it's joined
    /// with the key. A channel you'd left gets its entry back only when
    /// it's joined again; a hidden one is shown, still detached.
    @discardableResult
    private func restore(_ closed: ClosedBuffer, selecting: Bool) -> BufferModel? {
        recentlyClosed.removeAll { $0.id == closed.id }
        guard let session = session(for: closed.id.networkID) else { return nil }
        if session.buffer(named: closed.name) == nil {
            if let key = closed.key {
                try? keychain.setSecret(key, account: Keychain.channelKeyAccount(networkID: session.id, channel: closed.id.foldedName))
            }
            if let entry = closed.autoJoin, let index = closed.autoJoinIndex {
                if closed.autoRejoin {
                    session.restoreAutoJoin(entry, at: index)
                } else {
                    session.rememberLeftAutoJoin(LeftAutoJoin(entry: entry, index: index), for: closed.id.foldedName)
                }
            }
        }
        let buffer = session.reopen(closed)
        if selecting { select(buffer) }
        return buffer
    }

    // MARK: Undo

    private static func undoName(_ closed: ClosedBuffer) -> String {
        if closed.kind != .channel { return "Close Conversation" }
        return closed.wasHidden ? "Hide Channel" : "Remove Channel"
    }

    private func undoTarget(for id: BufferID) -> CloseUndoTarget {
        if let target = closeUndoTargets[id] { return target }
        let target = CloseUndoTarget()
        closeUndoTargets[id] = target
        return target
    }

    /// Registers an undo (or, while undoing, a redo) named `name` that runs
    /// `action` with the buffer's id.
    private func registerUndo(_ name: String, for id: BufferID, _ action: @escaping (AppModel, BufferID) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: undoTarget(for: id)) { [weak self] _ in
            guard let self else { return }
            action(self, id)
        }
        undoManager.setActionName(name)
    }

    /// Edit → Undo Remove Channel (Hide Channel, Close Conversation). The
    /// action carries its own copy of `closed`, so it works even after the
    /// list has let go of it.
    private func registerUndoClose(_ closed: ClosedBuffer) {
        registerUndo(Self.undoName(closed), for: closed.id) { app, _ in app.undoClose(closed) }
    }

    /// Puts a closed buffer back exactly as it was: selected only if it was.
    /// Redo closes (or hides) it again.
    private func undoClose(_ closed: ClosedBuffer) {
        guard restore(closed, selecting: closed.wasSelected) != nil else { return }
        registerUndo(Self.undoName(closed), for: closed.id) { app, id in
            guard let buffer = app.session(for: id.networkID)?.buffer(id: id) else { return }
            if closed.wasHidden { app.hide(buffer) } else { app.close(buffer) }
        }
    }

    /// Joins a channel you left or detached again (with its key, back on
    /// the auto-join list, reattached on the bouncer). Redo leaves it again
    /// the same way.
    private func undoLeave(_ id: BufferID, detaching: Bool = false) {
        guard let session = session(for: id.networkID), let channel = session.buffer(id: id) else { return }
        session.rejoin(channel)
        registerUndo("Leave Channel", for: id) { app, id in
            guard let channel = app.session(for: id.networkID)?.buffer(id: id) else { return }
            if detaching { app.detach(channel) } else { app.leave(channel) }
        }
    }

    /// Removes the undo and redo of closing or leaving `id`.
    private func dropUndo(for id: BufferID) {
        guard let target = closeUndoTargets.removeValue(forKey: id) else { return }
        undoManager?.removeAllActions(withTarget: target)
    }
}
