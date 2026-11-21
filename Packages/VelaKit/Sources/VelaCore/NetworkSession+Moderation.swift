// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaIRC
import VelaStore

/// A CTCP request you sent, kept until its reply comes (or for a while).
struct PendingCTCPRequest {
    /// The folded nick (or channel) it went to.
    let target: String
    let command: String
    /// What a PING carried, to match its reply.
    let token: String?
    /// Where the request was made, so the reply shows there.
    let bufferID: BufferID
    let sentAt: ContinuousClock.Instant
}

// MARK: Kicks, bans, quiets and ranks

extension NetworkSession {
    /// Runs a command as if typed in `buffer`'s message box: the user menu
    /// and the slash commands share these paths.
    public func execute(_ command: InputCommand, in buffer: BufferModel) {
        perform(command, in: buffer, replyTo: nil)
    }

    /// KICK, with `moderation.kickReason` when `reason` is nil (none when
    /// that's empty) and no reason when it's empty.
    func sendKick(_ nick: String, reason: String?, in buffer: BufferModel) {
        let reason = (reason ?? host?.behavior.defaultKickReason ?? "").trimmingCharacters(in: .whitespaces)
        send(IRCMessage(command: "KICK", params: [buffer.name, nick] + (reason.isEmpty ? [] : [reason])))
    }

    /// Bans each nick (looking up hosts it needs), then kicks them, so they
    /// can't come straight back.
    func kickBan(_ nicks: [String], reason: String?, in buffer: BufferModel) async {
        let masks = await banMasks(for: nicks)
        guard isConnected else { return }
        sendModes(sign: "+", mode: "b", arguments: masks, in: buffer)
        for nick in nicks where !BanMask.isMask(nick) {
            sendKick(nick, reason: reason, in: buffer)
        }
    }

    /// `+b` or `-b` for each nick or mask.
    func setBans(sign: Character, targets: [String], in buffer: BufferModel) async {
        let masks = await banMasks(for: targets)
        guard isConnected else { return }
        sendModes(sign: sign, mode: "b", arguments: masks, in: buffer)
    }

    /// Quiets (`+`) or unquiets each nick or mask, the server's way.
    func setQuiets(sign: Character, targets: [String], method: QuietMethod, in buffer: BufferModel) async {
        let masks = await banMasks(for: targets)
        guard isConnected else { return }
        let changes = masks.map(method.change(for:))
        guard let mode = changes.first?.mode else { return }
        sendModes(sign: sign, mode: mode, arguments: changes.map(\.argument), in: buffer)
    }

    /// MODE lines for one mode with many arguments, batched as ISUPPORT
    /// MODES allows (`+ooo a b c`).
    func sendModes(sign: Character, mode: Character, arguments: [String], in buffer: BufferModel) {
        let lines = IRCMessage.modeLines(
            target: buffer.name, sign: sign, mode: mode, arguments: arguments,
            perLine: isupport.modeChangesPerLine
        )
        for line in lines { send(line) }
    }

    /// The masks for `targets` (`moderation.banMask`): masks stay as they
    /// are; nicks use the host Vela knows, or asks the server for, or
    /// `nick!*@*` if it can't find out.
    func banMasks(for targets: [String]) async -> [String] {
        let style = host?.behavior.banMaskStyle ?? .host
        var hosts: [String: String] = [:]
        let unknown = targets.filter { !BanMask.isMask($0) && knownUserHost(of: $0) == nil }
        if BanMask.needsHost(style), !unknown.isEmpty {
            // Ask about everyone at once rather than one after another.
            let lookups = unknown.map { nick in (nick, Task { await self.lookUpUserHost(nick) }) }
            for (nick, lookup) in lookups {
                if let userHost = await lookup.value { hosts[fold(nick)] = userHost }
            }
        }
        return targets.map { target in
            guard !BanMask.isMask(target) else { return target }
            let userHost = knownUserHost(of: target) ?? hosts[fold(target)]
            return BanMask.mask(nick: target, userHost: userHost, style: style)
        }
    }

    /// `user@host` for `nick` from any channel's member list.
    public func knownUserHost(of nick: String) -> String? {
        let mapping = isupport.caseMapping
        for channel in channels {
            if let userHost = channel.member(named: nick, caseMapping: mapping)?.userHost { return userHost }
        }
        return nil
    }

    /// Asks the server for `nick`'s `user@host` (USERHOST). Nil when they
    /// aren't online, you're offline, or no answer comes in time.
    func lookUpUserHost(_ nick: String) async -> String? {
        if let known = knownUserHost(of: nick) { return known }
        guard isConnected else { return nil }
        let key = fold(nick)
        let timeout = userHostTimeout
        return await withCheckedContinuation { continuation in
            let isFirst = userHostWaiters[key] == nil
            userHostWaiters[key, default: []].append(continuation)
            if isFirst {
                userHostQueue.append(key)
                send(IRCMessage(command: "USERHOST", params: [nick]))
            }
            Task {
                try? await Task.sleep(for: timeout)
                self.finishUserHostLookup(key, userHost: nil)
            }
        }
    }

    /// Hands a RPL_USERHOST to the lookup it answers. False when it wasn't
    /// for one (someone typed /userhost), so it's shown.
    func answerUserHostLookup(_ entries: [(nick: String, userHost: String)]) -> Bool {
        guard !userHostQueue.isEmpty else { return false }
        let answered = entries.map { (key: fold($0.nick), userHost: $0.userHost) }
        // Servers leave out nicks that aren't online, so an empty answer is
        // for the oldest question.
        let index = userHostQueue.firstIndex { key in answered.contains { $0.key == key } } ?? (answered.isEmpty ? 0 : nil)
        guard let index else { return false }
        let key = userHostQueue[index]
        finishUserHostLookup(key, userHost: answered.first { $0.key == key }?.userHost)
        return true
    }

    private func finishUserHostLookup(_ key: String, userHost: String?) {
        userHostQueue.removeAll { $0 == key }
        guard let waiters = userHostWaiters.removeValue(forKey: key) else { return }
        for waiter in waiters { waiter.resume(returning: userHost) }
    }
}

// MARK: CTCP

extension NetworkSession {
    /// Sends a CTCP request and remembers it, so the reply shows in
    /// `buffer` (with the round trip, for PING).
    func sendCTCP(_ command: String, argument: String?, to target: String, from buffer: BufferModel) {
        let command = command.uppercased()
        var argument = argument
        if command == "PING", argument == nil {
            argument = String(Int64((Date().timeIntervalSince1970 * 1000).rounded()))
        }
        send(IRCMessage(command: "PRIVMSG", params: [target, CTCP.encode(command, argument)]))
        let now = ContinuousClock.now
        pendingCTCP.removeAll { now - $0.sentAt > .seconds(300) }
        pendingCTCP.append(PendingCTCPRequest(
            target: fold(target), command: command, token: command == "PING" ? argument : nil,
            bufferID: buffer.id, sentAt: now
        ))
        info(CTCPReplyText.sent(command: command, to: target), in: buffer, kind: .ctcp)
    }

    /// Shows a CTCP reply: where you asked, as a readable line, when it
    /// answers one of your requests; in the current buffer otherwise.
    func showCTCPReply(_ command: String, argument: String?, from nick: String) {
        let key = fold(nick)
        let matching = pendingCTCP.indices.filter { pendingCTCP[$0].target == key && pendingCTCP[$0].command == command }
        let index = matching.first { pendingCTCP[$0].token != nil && pendingCTCP[$0].token == argument } ?? matching.first
        guard let index else {
            let text = "CTCP \(command) reply from \(nick)" + (argument.map { ": \($0)" } ?? "")
            info(text, in: host?.activeBuffer(in: self) ?? serverBuffer, kind: .ctcp)
            return
        }
        let request = pendingCTCP.remove(at: index)
        let roundTrip = command == "PING" ? ContinuousClock.now - request.sentAt : nil
        let destination = buffer(id: request.bufferID) ?? host?.activeBuffer(in: self) ?? serverBuffer
        info(CTCPReplyText.describe(command: command, argument: argument, from: nick, roundTrip: roundTrip), in: destination, kind: .ctcp)
    }
}

// MARK: User menus

extension NetworkSession {
    /// Your rank in `buffer` (none outside channels).
    public func privileges(in buffer: BufferModel) -> ChannelPrivileges {
        let own = buffer.kind == .channel ? buffer.member(named: nick, caseMapping: isupport.caseMapping)?.prefixes ?? "" : ""
        return ChannelPrivileges(isupport: isupport, ownPrefixes: own)
    }

    /// `nick` as a user menu sees them in `buffer`: their rank there and
    /// host, falling back to `userHost` (from a message they sent).
    public func userMenuTarget(nick: String, in buffer: BufferModel, userHost: String? = nil) -> UserMenuTarget {
        let member = buffer.kind == .channel ? buffer.member(named: nick, caseMapping: isupport.caseMapping) : nil
        let host = member?.userHost ?? userHost ?? knownUserHost(of: nick)
        return UserMenuTarget(
            nick: member?.nick ?? nick,
            modes: member.map { ChannelPrivileges.modes(forSymbols: $0.prefixes, isupport: isupport) } ?? [],
            userHost: host,
            isSelf: isSelf(nick),
            isMember: member != nil,
            isIgnored: !ignoreMatcher.isEmpty && ignoreMatcher.matches("\(nick)!\(host ?? "*@*")")
        )
    }

    /// The menu for `targets` in `buffer`.
    public func userMenu(for targets: [UserMenuTarget], in buffer: BufferModel) -> UserMenu {
        var invite: [String] = []
        if targets.count == 1, let target = targets.first, !target.isSelf {
            let mapping = isupport.caseMapping
            invite = channels
                .filter { $0.isJoined && $0.id != buffer.id && $0.member(named: target.nick, caseMapping: mapping) == nil }
                .map(\.name)
        }
        return UserMenu.build(UserMenuContext(
            targets: targets,
            privileges: privileges(in: buffer),
            isConnected: isConnected,
            isChannel: buffer.kind == .channel,
            quietMethod: isupport.quietMethod,
            inviteChannels: invite
        ))
    }

    /// Does `action` to `targets` from `buffer`, through the same commands
    /// as typing them. Actions the app does itself (`isHandledByApp`) do
    /// nothing here.
    public func perform(_ action: UserAction, on targets: [UserMenuTarget], in buffer: BufferModel) {
        guard let first = targets.first else { return }
        let nicks = targets.map(\.nick)
        let style = host?.behavior.banMaskStyle ?? .host
        // A host already known (from a message) saves asking the server.
        let masks = targets.map { target in
            target.userHost.map { BanMask.mask(nick: target.nick, userHost: $0, style: style) } ?? target.nick
        }
        switch action {
        case .message:
            // Like /query, but offline too, as opening a conversation sends nothing.
            requestSelection?(ensureBuffer(name: first.nick, kind: .query))
        case .whois: execute(.whois(first.nick), in: buffer)
        case .ping: execute(.ctcp(target: first.nick, command: "PING", argument: nil), in: buffer)
        case .ctcp(let command): execute(.ctcp(target: first.nick, command: command, argument: nil), in: buffer)
        case .invite(let channel): execute(.invite(nick: first.nick, channel: channel), in: buffer)
        case .ignore: execute(.ignore(first.nick), in: buffer)
        case .unignore:
            let source = "\(first.nick)!\(first.userHost ?? "*@*")"
            for mask in config.ignoreMasks where IgnoreMatcher(masks: [mask]).matches(source) {
                execute(.unignore(mask), in: buffer)
            }
        case .mode(let sign, let mode):
            // Only those it changes something for.
            let affected = targets.filter { $0.modes.contains(mode) == (sign == "-") }.map(\.nick)
            execute(.memberMode(sign: sign, mode: mode, nicks: affected), in: buffer)
        case .kick:
            for nick in nicks { execute(.kick(nick: nick, reason: nil), in: buffer) }
        case .ban: execute(.ban(masks: masks), in: buffer)
        case .kickBan: execute(.kickBan(nicks: nicks, reason: nil), in: buffer)
        case .quiet: execute(.quiet(masks: masks), in: buffer)
        case .unquiet: execute(.unquiet(masks: masks), in: buffer)
        case .mention, .copyNick, .copyHostMask, .kickWithReason, .kickBanWithReason, .recap:
            break
        }
    }
}
