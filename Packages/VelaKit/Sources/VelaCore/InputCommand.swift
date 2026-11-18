// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A parsed line from the input bar.
nonisolated public enum InputCommand: Equatable, Sendable {
    case say(String)
    case action(String)
    case message(target: String, text: String)
    case notice(target: String, text: String)
    case query(nick: String, text: String?)
    case join(channels: [String], keys: [String])
    case part(channel: String?, reason: String?)
    case nick(String)
    case topic(channel: String?, text: String?)
    case away(String?)
    case back
    case whois(String)
    case mode(target: String?, args: [String])
    /// Kicks `nick` (or `a,b`). A nil reason gives `moderation.kickReason`;
    /// an empty one gives none.
    case kick(nick: String, reason: String?)
    /// Bans, then kicks, each nick.
    case kickBan(nicks: [String], reason: String?)
    /// Nicks are turned into masks (`moderation.banMask`).
    case ban(masks: [String])
    case unban(masks: [String])
    /// Quiets (or unquiets) nicks or masks, the way the server does it
    /// (`ISupport.quietMethod`).
    case quiet(masks: [String])
    case unquiet(masks: [String])
    case memberMode(sign: Character, mode: Character, nicks: [String])
    case invite(nick: String, channel: String?)
    case ctcp(target: String, command: String, argument: String?)
    case raw(String)
    case quit(String?)
    case connect
    case disconnect(String?)
    case reconnect
    case close
    case clear
    case ignore(String)
    case unignore(String)
    case usage(String)
    case unknown(command: String, args: String)

    /// Commands known to the parser, for tab completion and help.
    public static let knownCommands: [String] = [
        "away", "back", "ban", "clear", "clientinfo", "close", "connect", "ctcp", "dehalfop", "deop",
        "devoice", "disconnect", "halfop", "ignore", "invite", "j", "join", "kb", "kick", "kickban",
        "leave", "me", "mode", "msg", "nick", "notice", "op", "part", "ping", "q", "query", "quiet",
        "quit", "quote", "raw", "reconnect", "time", "topic", "unban", "unignore", "unquiet", "version",
        "voice", "whois",
    ]

    /// Parses input. Text not starting with `/` (or starting with `//`) is
    /// sent verbatim to the current buffer.
    public static func parse(_ input: String) -> InputCommand? {
        let trimmed = input.trimmingCharacters(in: .newlines)
        guard !trimmed.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard trimmed.hasPrefix("/") else { return .say(trimmed) }
        if trimmed.hasPrefix("//") { return .say(String(trimmed.dropFirst())) }

        let body = trimmed.dropFirst()
        let commandEnd = body.firstIndex(where: \.isWhitespace) ?? body.endIndex
        let command = body[..<commandEnd].lowercased()
        let rest = body[commandEnd...].trimmingCharacters(in: .whitespaces)
        let words = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        func remainder(after count: Int) -> String? {
            var scanner = Substring(rest)
            for _ in 0..<count {
                scanner = scanner.drop(while: { $0 == " " })
                scanner = scanner.drop(while: { $0 != " " })
            }
            let value = scanner.drop(while: { $0 == " " })
            return value.isEmpty ? nil : String(value)
        }

        switch command {
        case "me":
            return rest.isEmpty ? .usage("/me <action>") : .action(rest)
        case "msg", "privmsg":
            guard words.count >= 2, let text = remainder(after: 1) else { return .usage("/msg <target> <message>") }
            return .message(target: words[0], text: text)
        case "notice":
            guard words.count >= 2, let text = remainder(after: 1) else { return .usage("/notice <target> <message>") }
            return .notice(target: words[0], text: text)
        case "query", "q":
            guard let nick = words.first else { return .usage("/query <nick> [message]") }
            return .query(nick: nick, text: remainder(after: 1))
        case "join", "j":
            guard let channels = words.first else { return .usage("/join <#channel>[,#other] [keys]") }
            let keys = words.count > 1 ? words[1].split(separator: ",").map(String.init) : []
            return .join(channels: channels.split(separator: ",").map(String.init), keys: keys)
        case "part", "leave":
            if let first = words.first, let c = first.first, "#&+!".contains(c) {
                return .part(channel: first, reason: remainder(after: 1))
            }
            return .part(channel: nil, reason: rest.isEmpty ? nil : rest)
        case "nick":
            guard let nick = words.first else { return .usage("/nick <newnick>") }
            return .nick(nick)
        case "topic":
            if let first = words.first, let c = first.first, "#&+!".contains(c) {
                return .topic(channel: first, text: remainder(after: 1))
            }
            return .topic(channel: nil, text: rest.isEmpty ? nil : rest)
        case "away":
            return .away(rest.isEmpty ? nil : rest)
        case "back":
            return .back
        case "whois", "wi":
            guard let nick = words.first else { return .usage("/whois <nick>") }
            return .whois(nick)
        case "mode":
            if let first = words.first, !(first.hasPrefix("+") || first.hasPrefix("-")) {
                return .mode(target: first, args: Array(words.dropFirst()))
            }
            return .mode(target: nil, args: words)
        case "kick", "k":
            guard let nick = words.first else { return .usage("/kick <nick> [reason]") }
            return .kick(nick: nick, reason: remainder(after: 1))
        case "kickban", "kb":
            guard let nicks = words.first else { return .usage("/kickban <nick> [reason]") }
            return .kickBan(nicks: nicks.split(separator: ",").map(String.init), reason: remainder(after: 1))
        case "ban":
            guard !words.isEmpty else { return .usage("/ban <nick|mask> [nick|mask…]") }
            return .ban(masks: words)
        case "unban":
            guard !words.isEmpty else { return .usage("/unban <nick|mask> [nick|mask…]") }
            return .unban(masks: words)
        case "quiet":
            guard !words.isEmpty else { return .usage("/quiet <nick|mask> [nick|mask…]") }
            return .quiet(masks: words)
        case "unquiet":
            guard !words.isEmpty else { return .usage("/unquiet <nick|mask> [nick|mask…]") }
            return .unquiet(masks: words)
        case "op", "deop", "voice", "devoice", "halfop", "dehalfop":
            guard !words.isEmpty else { return .usage("/\(command) <nick> [nick…]") }
            let sign: Character = command.hasPrefix("de") ? "-" : "+"
            let mode: Character = command.hasSuffix("voice") ? "v" : (command.hasSuffix("halfop") ? "h" : "o")
            return .memberMode(sign: sign, mode: mode, nicks: words)
        case "invite":
            guard let nick = words.first else { return .usage("/invite <nick> [#channel]") }
            return .invite(nick: nick, channel: words.dropFirst().first)
        case "ctcp":
            guard words.count >= 2 else { return .usage("/ctcp <target> <command> [args]") }
            return .ctcp(target: words[0], command: words[1].uppercased(), argument: remainder(after: 2))
        case "ping":
            guard let target = words.first else { return .usage("/ping <nick>") }
            return .ctcp(target: target, command: "PING", argument: nil)
        case "version", "time":
            // Without a nick (or with a server name) these ask the server.
            guard let target = words.first, !target.contains(".") else { return .unknown(command: command, args: rest) }
            return .ctcp(target: target, command: command.uppercased(), argument: nil)
        case "clientinfo":
            guard let target = words.first else { return .usage("/clientinfo <nick>") }
            return .ctcp(target: target, command: "CLIENTINFO", argument: nil)
        case "raw", "quote":
            return rest.isEmpty ? .usage("/raw <line>") : .raw(rest)
        case "quit":
            return .quit(rest.isEmpty ? nil : rest)
        case "connect", "server":
            return .connect
        case "disconnect":
            return .disconnect(rest.isEmpty ? nil : rest)
        case "reconnect":
            return .reconnect
        case "close", "wc":
            return .close
        case "clear":
            return .clear
        case "ignore":
            guard let mask = words.first else { return .usage("/ignore <nick|mask>") }
            return .ignore(mask)
        case "unignore":
            guard let mask = words.first else { return .usage("/unignore <nick|mask>") }
            return .unignore(mask)
        default:
            return .unknown(command: command, args: rest)
        }
    }
}

/// Matches `nick!user@host` against glob masks (`*`, `?`). A bare nick
/// mask matches any user/host.
nonisolated public struct IgnoreMatcher: Sendable {
    private let patterns: [NSRegularExpression]

    public init(masks: [String]) {
        patterns = masks.compactMap { mask in
            var mask = mask
            if !mask.contains("!") && !mask.contains("@") { mask += "!*@*" }
            var regex = "^"
            for char in mask {
                switch char {
                case "*": regex += ".*"
                case "?": regex += "."
                default: regex += NSRegularExpression.escapedPattern(for: String(char))
                }
            }
            regex += "$"
            return try? NSRegularExpression(pattern: regex, options: [.caseInsensitive])
        }
    }

    public func matches(_ source: String) -> Bool {
        let range = NSRange(source.startIndex..., in: source)
        return patterns.contains { $0.firstMatch(in: source, range: range) != nil }
    }

    public var isEmpty: Bool { patterns.isEmpty }
}

/// Detects whether a message mentions the user.
nonisolated public struct HighlightMatcher: Sendable {
    private let regex: NSRegularExpression?

    public init(nick: String, words: [String]) {
        let terms = ([nick] + words)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map(NSRegularExpression.escapedPattern(for:))
        guard !terms.isEmpty else {
            regex = nil
            return
        }
        // Word-ish boundaries that treat IRC nick characters as part of the word.
        let pattern = "(?<![\\w\\[\\]\\\\`^{|}-])(?:\(terms.joined(separator: "|")))(?![\\w\\[\\]\\\\`^{|}-])"
        regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    public func matches(_ text: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
