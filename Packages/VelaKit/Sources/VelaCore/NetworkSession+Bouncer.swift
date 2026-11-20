// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaIRC
import VelaStore

/// A detached bouncer channel taken out of Vela's list (Hide Channel). The
/// bouncer is still in it and keeps its history. See
/// ``NetworkSession/hiddenChannels``.
nonisolated public struct HiddenChannel: Identifiable, Hashable, Sendable {
    public let id: BufferID
    public let name: String
    public let isMuted: Bool
    public let lastReadAt: Date?
    /// Its place among the network's channels when it was hidden.
    public let index: Int

    init(id: BufferID, name: String, isMuted: Bool, lastReadAt: Date?, index: Int) {
        self.id = id
        self.name = name
        self.isMuted = isMuted
        self.lastReadAt = lastReadAt
        self.index = index
    }

    init(record: BufferRecord, id: BufferID) {
        self.init(id: id, name: record.name, isMuted: record.isMuted, lastReadAt: record.lastReadAt, index: record.sortOrder)
    }
}

/// A detach Vela asked the bouncer for, waiting for the bouncer's PART.
struct DetachRequest {
    /// The channel, as named when it was asked.
    let name: String
    /// The text sent to the bouncer's service (`*status`, `BouncerServ`).
    let command: String
    /// Counts down from when the command is written; nil until then.
    var timeout: Task<Void, Never>?
}

// MARK: - Bouncers: detaching, hiding, and what waits for the next connection

/// On a bouncer (ZNC or soju), leaving a channel in Vela detaches it: the
/// bouncer stays in the channel and keeps its history, but stops sending it
/// to Vela, and Vela shows it dimmed. Joining it again reattaches it, and
/// the bouncer plays back what was missed.
///
/// - ZNC: `PRIVMSG *status :detach #chan`. ZNC answers with a PART for the
///   channel, then "There was 1 channel matching [#chan]" and "Detached 1
///   channel" from `*status`. A JOIN reattaches it (`CChan::AttachUser`);
///   with `znc.in/playback`, Vela then asks `*playback` to play it back.
/// - soju: `PRIVMSG BouncerServ :channel update #chan -detached true`.
///   soju answers with `PART #chan :Detach`, then `updated channel "#chan"`
///   (or `error: …`) from BouncerServ. A JOIN reattaches it, and Vela
///   fetches what it missed with `chathistory`. soju parts with "Detach"
///   when it detaches a channel itself (`-detach-after`) too.
///
/// A detach is done when the bouncer's PART arrives. If it doesn't within
/// ``detachTimeout`` while Vela is still in the channel, the server console
/// says so; Vela never parts instead. Hidden channels are detached channels
/// out of the list; what a bouncer relays from one is stored, never shown.
extension NetworkSession {
    /// How long the bouncer's service replies go to the server console
    /// after a detach is sent.
    static let serviceReplyWindow: TimeInterval = 15

    /// The bouncer this network goes through: the one its settings name,
    /// or, for a network set up without one, what its capabilities give
    /// away (soju's `soju.im/bouncer-networks`, ZNC's `znc.in/…`).
    public var bouncerKind: BouncerKind {
        if config.bouncerKind != .none { return config.bouncerKind }
        if capabilities.contains("soju.im/bouncer-networks") { return .soju }
        if capabilities.contains(where: { $0.hasPrefix("znc.in/") }) { return .znc }
        return .none
    }

    /// A ZNC or soju network: the bouncer joins channels, not Vela, and
    /// leaving a channel detaches it.
    public var isBouncer: Bool { bouncerKind != .none }

    /// "ZNC", "soju", or "Your bouncer", for messages.
    public var bouncerName: String {
        switch bouncerKind {
        case .znc: "ZNC"
        case .soju: "soju"
        case .none: "Your bouncer"
        }
    }

    /// Who takes the bouncer's commands: ZNC's `*status`, soju's BouncerServ.
    var bouncerServiceNick: String? {
        switch bouncerKind {
        case .znc: "*status"
        case .soju: "BouncerServ"
        case .none: nil
        }
    }

    /// What to send the bouncer's service to detach `channel`.
    nonisolated static func detachCommand(for channel: String, bouncer: BouncerKind) -> String? {
        switch bouncer {
        case .znc: "detach \(channel)"
        case .soju: "channel update \(sojuArgument(channel)) -detached true"
        case .none: nil
        }
    }

    /// soju splits a command's arguments like a shell does, so a name with
    /// spaces, quotes or backslashes goes in double quotes.
    nonisolated static func sojuArgument(_ text: String) -> String {
        guard text.contains(where: { " \t\"'\\$`".contains($0) }) else { return text }
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    // MARK: Detaching

    /// Leaves `channel` in Vela but not on the bouncer (Leave Channel and a
    /// tab's × through a bouncer). Connected, the bouncer is asked now and
    /// the channel dims when it answers. Disconnected, it dims now and the
    /// bouncer is asked after the next registration, even after a relaunch.
    public func detach(_ channel: BufferModel) {
        let folded = channel.id.foldedName
        guard channel.kind == .channel, isBouncer, bufferIndex[folded] === channel else { return }
        pendingJoins.remove(folded)
        if isConnected {
            guard channel.isJoined else { return }
            requestDetach(name: channel.name)
        } else {
            guard !channel.isDetached else { return }
            channel.isDetached = true
            addPending(channel.name, to: \.pendingDetaches)
            persistBuffer(channel)
        }
    }

    /// Sends the detach command for `name`, once.
    func requestDetach(name: String) {
        let folded = fold(name)
        guard detachRequests[folded] == nil else { return }
        guard let nick = bouncerServiceNick, let command = Self.detachCommand(for: name, bouncer: bouncerKind) else {
            // No longer set up as a bouncer: there's nothing to ask.
            removePending(folded, from: \.pendingDetaches)
            error("Couldn't leave \(name) on the bouncer: \(displayName) isn't set up as one any more. Join it again, or remove it.", in: serverBuffer)
            return
        }
        detachRequests[folded] = DetachRequest(name: name, command: command)
        serviceRepliesUntil = Date().addingTimeInterval(Self.serviceReplyWindow)
        send(IRCMessage(command: "PRIVMSG", params: [nick, command]))
    }

    /// Calls off a detach of `folded`, asked for or still waiting to be.
    /// Returns true when one hadn't been sent yet, so the bouncer never
    /// knew of it.
    @discardableResult
    func cancelDetach(_ folded: String) -> Bool {
        if let request = detachRequests.removeValue(forKey: folded) { request.timeout?.cancel() }
        return removePending(folded, from: \.pendingDetaches)
    }

    /// Before joining `folded` on purpose: whatever was waiting for the
    /// bouncer (a part, a detach) is off, a part on its way no longer
    /// matters, and a channel you left goes back on the auto-join list.
    /// Returns true when an unsent detach was dropped.
    @discardableResult
    func prepareToJoin(_ folded: String) -> Bool {
        removePending(folded, from: \.pendingParts)
        partingChannels.remove(folded)
        let droppedUnsentDetach = cancelDetach(folded)
        if let left = leftAutoJoin.removeValue(forKey: folded) {
            restoreAutoJoin(left.entry, at: left.index)
            if let buffer = bufferIndex[folded] { persistBuffer(buffer) }
        }
        return droppedUnsentDetach
    }

    /// Whether your PART from `channel` is the bouncer detaching it: one
    /// Vela asked for, or one soju made itself (it parts with "Detach").
    func confirmsDetach(of channel: String, reason: String?) -> Bool {
        guard isBouncer else { return false }
        if let request = detachRequests.removeValue(forKey: fold(channel)) {
            request.timeout?.cancel()
            return true
        }
        return bouncerKind == .soju && reason?.caseInsensitiveCompare("Detach") == .orderedSame
    }

    /// A line Vela wrote: a waiting part or detach that's now been sent
    /// comes off networks.json, and a detach's wait for its answer starts.
    func noteSentToBouncer(_ message: IRCMessage) {
        switch message.command {
        case "PART":
            guard !config.pendingParts.isEmpty, let channels = message.param(0) else { return }
            for channel in channels.split(separator: ",") { removePending(fold(String(channel)), from: \.pendingParts) }
        case "PRIVMSG":
            guard !detachRequests.isEmpty, let nick = bouncerServiceNick, let target = message.param(0),
                  fold(target) == fold(nick), let text = message.param(1) else { return }
            for (folded, request) in detachRequests where request.command == text && request.timeout == nil {
                removePending(folded, from: \.pendingDetaches)
                serviceRepliesUntil = Date().addingTimeInterval(Self.serviceReplyWindow)
                let timeout = detachTimeout
                detachRequests[folded]?.timeout = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.detachTimedOut(folded)
                }
            }
        default:
            break
        }
    }

    /// The bouncer didn't confirm detaching `folded` in time. If Vela is
    /// still in the channel, the detach didn't happen: the channel stays
    /// joined, and the server console (and the channel) say so. Vela never
    /// parts instead, which would make the bouncer forget the channel.
    func detachTimedOut(_ folded: String) {
        guard let request = detachRequests.removeValue(forKey: folded),
              let channel = bufferIndex[folded] else { return }
        if channel.isJoined {
            if channel.isDetached {
                channel.isDetached = false
                persistBuffer(channel)
            }
            let problem = "\(bouncerName) didn't detach \(request.name), so you're still in it."
            error("\(problem) Its reply, if it sent one, is above. To leave the channel on \(bouncerName) too, use Remove Channel….", in: serverBuffer)
            error("\(problem) See the server console for \(bouncerName)'s reply.", in: channel)
        } else if !channel.isDetached {
            // Not in it here anyway: the bouncer had already detached it.
            channel.isDetached = true
            persistBuffer(channel)
        }
    }

    /// The connection dropped before the bouncer confirmed some detaches:
    /// they're asked again after the next registration. (Asking twice does
    /// no harm: the bouncer just says there was nothing to detach.)
    func requeueUnconfirmedDetaches() {
        guard !detachRequests.isEmpty else { return }
        for (folded, request) in detachRequests {
            request.timeout?.cancel()
            if let channel = bufferIndex[folded], !channel.isDetached {
                channel.isDetached = true
                persistBuffer(channel)
            }
            addPending(request.name, to: \.pendingDetaches)
        }
        detachRequests = [:]
    }

    /// After registering with a bouncer: parts the channels you removed and
    /// detaches the ones you left while disconnected. The bouncer may join
    /// Vela into them first; those joins are ignored (parts) or undone by
    /// the detach. Each comes off networks.json once it's sent.
    func sendPendingBouncerChanges() {
        for name in config.pendingParts {
            partingChannels.insert(fold(name))
            send(IRCMessage(command: "PART", params: [name]))
        }
        for name in config.pendingDetaches { requestDetach(name: name) }
    }

    /// Your own detach command, echoed back or reported as sent: it isn't a
    /// conversation with the bouncer's service.
    func isOwnBouncerCommand(to target: String, text: String) -> Bool {
        guard !detachRequests.isEmpty, let nick = bouncerServiceNick, fold(target) == fold(nick) else { return false }
        return detachRequests.values.contains { $0.command == text }
    }

    /// Whether a message from `nick` is the bouncer's service answering a
    /// detach, for the server console rather than a new conversation.
    func routesToConsole(_ nick: String) -> Bool {
        guard let until = serviceRepliesUntil, let service = bouncerServiceNick,
              fold(nick) == fold(service), buffer(named: nick) == nil else { return false }
        if Date() < until { return true }
        serviceRepliesUntil = nil
        return false
    }

    // MARK: Waiting parts and detaches (networks.json)

    func addPendingPart(_ name: String) {
        addPending(name, to: \.pendingParts)
    }

    @discardableResult
    func removePendingPart(_ folded: String) -> Bool {
        removePending(folded, from: \.pendingParts)
    }

    func addPendingDetach(_ name: String) {
        addPending(name, to: \.pendingDetaches)
    }

    private func addPending(_ name: String, to list: WritableKeyPath<NetworkConfig, [String]>) {
        let folded = fold(name)
        guard !config[keyPath: list].contains(where: { fold($0) == folded }) else { return }
        config[keyPath: list].append(name)
        host?.sessionDidChangeConfig(self)
    }

    @discardableResult
    private func removePending(_ folded: String, from list: WritableKeyPath<NetworkConfig, [String]>) -> Bool {
        guard config[keyPath: list].contains(where: { fold($0) == folded }) else { return false }
        config[keyPath: list].removeAll { fold($0) == folded }
        host?.sessionDidChangeConfig(self)
        return true
    }

    // MARK: Hiding

    /// Whether `channel` can be hidden: a detached channel on a bouncer.
    public func canHide(_ channel: BufferModel) -> Bool {
        channel.kind == .channel && isBouncer && channel.isDetached && !channel.isJoined
            && bufferIndex[channel.id.foldedName] === channel
    }

    /// Takes a detached channel out of the list (Hide Channel) without
    /// parting it: the bouncer stays in it, detached. It's remembered in
    /// ``hiddenChannels`` and in the database, so it stays hidden after a
    /// relaunch. The app goes through `AppModel.hide(_:)`, which also moves
    /// the selection and remembers it in Recently Closed.
    func hide(_ channel: BufferModel) {
        guard canHide(channel) else { return }
        let folded = channel.id.foldedName
        let index = bufferSiblings(of: channel).firstIndex { $0.id == channel.id } ?? 0
        hiddenChannels.append(HiddenChannel(
            id: channel.id, name: channel.name, isMuted: channel.isMuted, lastReadAt: channel.lastReadAt, index: index
        ))
        pendingJoins.remove(folded)
        bufferIndex.removeValue(forKey: folded)
        buffers.removeAll { $0.id == channel.id }
        let record = BufferRecord(
            networkID: id, name: channel.name, foldedName: folded, kind: BufferKind.channel.rawValue,
            lastReadAt: channel.lastReadAt, isMuted: channel.isMuted, sortOrder: index,
            autoRejoin: rejoins(channel), isDetached: true, isHidden: true
        )
        writeBuffer { try await $0.upsertBuffer(record) }
        host?.sessionDidChangeUnreadCounts(self)
    }

    /// Puts a hidden channel back in the list, still detached, where it
    /// was. Returns it (or the channel, if it's back already).
    @discardableResult
    public func showHiddenChannel(_ id: BufferID) -> BufferModel? {
        guard let hidden = hiddenChannels.first(where: { $0.id == id }) else { return buffer(id: id) }
        return ensureBuffer(name: hidden.name, kind: .channel)
    }

    /// Whether `name` is a hidden channel.
    func isHidden(_ name: String) -> Bool {
        guard !hiddenChannels.isEmpty else { return false }
        let folded = fold(name)
        return hiddenChannels.contains { $0.id.foldedName == folded }
    }

    /// Forgets hidden channel `folded` altogether (you parted it by name).
    func forgetHiddenChannel(_ folded: String) {
        guard let hidden = takeHiddenChannel(folded) else { return }
        let key = hidden.id.storeKey
        writeBuffer { try await $0.deleteBuffer(key, keepMessages: true) }
    }

    /// Takes `folded` off the hidden list, for showing it.
    func takeHiddenChannel(_ folded: String) -> HiddenChannel? {
        guard !hiddenChannels.isEmpty, let index = hiddenChannels.firstIndex(where: { $0.id.foldedName == folded }) else { return nil }
        return hiddenChannels.remove(at: index)
    }
}
