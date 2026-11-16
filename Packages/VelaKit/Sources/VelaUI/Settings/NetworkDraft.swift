// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaStore

/// The network editor's working copy, in UI-friendly shapes (text for the
/// port and lists, one authentication method), plus validation.
struct NetworkDraft: Equatable {
    enum Authentication: String, CaseIterable, Identifiable {
        case none
        case saslPlain
        case saslExternal
        case serverPassword

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "None"
            case .saslPlain: "SASL PLAIN (account and password)"
            case .saslExternal: "SASL EXTERNAL (client certificate)"
            case .serverPassword: "Server password"
            }
        }

        var explanation: String {
            switch self {
            case .none:
                "Connect without logging in to an account."
            case .saslPlain:
                "Log in to your services account while connecting. Recommended for most networks."
            case .saslExternal:
                "Log in with a TLS client certificate (CertFP). Add the certificate's fingerprint to your account first."
            case .serverPassword:
                "Send a password with PASS when connecting. Used by ZNC and some private servers."
            }
        }
    }

    enum Field: Hashable {
        case host, port, nick, saslPassword, certificate, serverPassword
    }

    struct Channel: Identifiable, Equatable {
        var id = UUID()
        var name = ""
        var key = ""
    }

    var name = ""
    var host = ""
    var port = "6697"
    var useTLS = true
    var allowInvalidCertificates = false

    var nick = ""
    var alternateNicks = ""
    var username = ""
    var realname = ""

    var authentication: Authentication = .none
    var saslAccount = ""
    var saslPassword = ""
    var serverPassword = ""
    /// A SASL login that also sends a server password (only possible when
    /// the config had both, e.g. from a hand-edited networks.json).
    var alsoSendsServerPassword = false
    var certificateRef: Data?

    var bouncer: BouncerKind = .none
    var channels: [Channel] = []
    var performCommands = ""
    var highlightWords: [String] = []
    var ignoreMasks: [String] = []
    var autoConnect = true

    /// A soju child network: only its name, perform commands, lists and
    /// auto-connect are its own.
    var isBouncerChild = false

    init() {}

    init(config: NetworkConfig, secrets: NetworkSecrets, channelKey: (AutoJoinChannel) -> String?) {
        name = config.name
        host = config.host
        port = String(config.port)
        useTLS = config.useTLS
        allowInvalidCertificates = config.allowInvalidCertificates
        nick = config.nick
        alternateNicks = config.alternateNicks.joined(separator: ", ")
        username = config.username == config.nick ? "" : config.username
        realname = config.realname == config.nick ? "" : config.realname
        switch config.saslKind {
        case .plain: authentication = .saslPlain
        case .external: authentication = .saslExternal
        case .none: authentication = config.hasServerPassword ? .serverPassword : .none
        }
        saslAccount = config.saslAccount ?? ""
        saslPassword = secrets.saslPassword ?? ""
        serverPassword = secrets.serverPassword ?? ""
        alsoSendsServerPassword = config.saslKind != .none && config.hasServerPassword
        certificateRef = config.clientCertificateRef
        bouncer = config.bouncerKind
        channels = config.autoJoin.map { Channel(name: $0.name, key: channelKey($0) ?? "") }
        performCommands = config.performCommands.joined(separator: "\n")
        highlightWords = config.highlightWords
        ignoreMasks = config.ignoreMasks
        autoConnect = config.autoConnect
        isBouncerChild = config.isBouncerChild
    }

    // MARK: Presets

    struct Preset: Identifiable {
        let name: String
        let host: String
        var port = 6697
        var id: String { host }
    }

    static let presets: [Preset] = [
        Preset(name: "Libera.Chat", host: "irc.libera.chat"),
        Preset(name: "OFTC", host: "irc.oftc.net"),
        Preset(name: "Ergo testnet", host: "testnet.ergo.chat"),
        Preset(name: "Rizon", host: "irc.rizon.net"),
        Preset(name: "EFnet", host: "irc.efnet.org"),
        Preset(name: "hackint", host: "irc.hackint.org"),
    ]

    mutating func apply(_ preset: Preset?) {
        name = preset?.name ?? ""
        host = preset?.host ?? ""
        port = String(preset?.port ?? 6697)
        useTLS = true
        allowInvalidCertificates = false
    }

    /// Switches between the conventional TLS and plain-text ports when the
    /// port is still a default.
    mutating func tlsChanged() {
        if useTLS, port == "6667" { port = "6697" }
        if !useTLS, port == "6697" { port = "6667" }
        if !useTLS { allowInvalidCertificates = false }
    }

    // MARK: Validation

    var problems: [Field: String] {
        var problems: [Field: String] = [:]
        guard !isBouncerChild else { return problems }
        let host = host.trimmingCharacters(in: .whitespaces)
        if host.isEmpty {
            problems[.host] = "Enter the server's address, such as irc.libera.chat."
        } else if host.contains(where: { $0.isWhitespace || $0 == "/" }) {
            problems[.host] = "The address can't contain spaces or slashes."
        }
        if Int(port.trimmingCharacters(in: .whitespaces)).map({ (1...65535).contains($0) }) != true {
            problems[.port] = "Use a port from 1 to 65535."
        }
        if let problem = Self.nickProblem(nick) {
            problems[.nick] = problem
        }
        switch authentication {
        case .saslPlain where saslPassword.isEmpty:
            problems[.saslPassword] = "Enter your account password."
        case .saslExternal where certificateRef == nil:
            problems[.certificate] = "Choose or import a client certificate."
        case .serverPassword where serverPassword.isEmpty:
            problems[.serverPassword] = "Enter the server password."
        default:
            break
        }
        return problems
    }

    static func nickProblem(_ nick: String) -> String? {
        let nick = nick.trimmingCharacters(in: .whitespaces)
        guard let first = nick.first else { return "Choose a nickname." }
        if nick.contains(where: { $0.isWhitespace || ",*?!@".contains($0) }) {
            return "Nicknames can't contain spaces or , * ? ! @"
        }
        if first.isNumber || "-#&:$".contains(first) {
            return "Nicknames can't start with a digit or - # & : $"
        }
        return nil
    }

    // MARK: Output

    /// Writes the draft's values into `config`.
    func apply(to config: inout NetworkConfig) {
        config.name = name.trimmingCharacters(in: .whitespaces)
        config.performCommands = performCommands
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        config.highlightWords = highlightWords
        config.ignoreMasks = ignoreMasks
        config.autoConnect = autoConnect
        guard !isBouncerChild else { return }

        let host = host.trimmingCharacters(in: .whitespaces)
        let nick = nick.trimmingCharacters(in: .whitespaces)
        if config.name.isEmpty { config.name = host }
        config.host = host
        config.port = UInt16(port.trimmingCharacters(in: .whitespaces)) ?? (useTLS ? 6697 : 6667)
        config.useTLS = useTLS
        config.allowInvalidCertificates = useTLS && allowInvalidCertificates
        config.nick = nick
        config.alternateNicks = alternateNicks
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty && $0 != nick }
        let username = username.trimmingCharacters(in: .whitespaces)
        let realname = realname.trimmingCharacters(in: .whitespaces)
        config.username = username.isEmpty ? nick : username
        config.realname = realname.isEmpty ? nick : realname
        switch authentication {
        case .none, .serverPassword:
            config.saslKind = .none
            config.saslAccount = nil
        case .saslPlain:
            config.saslKind = .plain
            let account = saslAccount.trimmingCharacters(in: .whitespaces)
            config.saslAccount = account.isEmpty ? nil : account
        case .saslExternal:
            config.saslKind = .external
            config.saslAccount = nil
        }
        config.clientCertificateRef = authentication == .saslExternal ? certificateRef : nil
        config.bouncerKind = bouncer
        config.autoJoin = normalizedChannels.map { AutoJoinChannel(name: $0.name, hasKey: !$0.key.isEmpty) }
    }

    /// Whether a server password is sent alongside the chosen method.
    var usesServerPassword: Bool {
        authentication == .serverPassword || (authentication != .none && alsoSendsServerPassword)
    }

    /// The Keychain secrets for this draft. The NickServ password has no
    /// field here and is carried over unchanged.
    func secrets(keeping nickServPassword: String?) -> NetworkSecrets {
        NetworkSecrets(
            serverPassword: usesServerPassword && !serverPassword.isEmpty ? serverPassword : nil,
            saslPassword: authentication == .saslPlain && !saslPassword.isEmpty ? saslPassword : nil,
            nickServPassword: nickServPassword
        )
    }

    /// Channels with names trimmed, a `#` added when there's no channel
    /// prefix, blanks and duplicates removed.
    var normalizedChannels: [Channel] {
        var seen = Set<String>()
        return channels.compactMap { channel in
            guard let name = Self.channelName(channel.name), seen.insert(name.lowercased()).inserted else { return nil }
            return Channel(id: channel.id, name: name, key: channel.key.trimmingCharacters(in: .whitespaces))
        }
    }

    static func channelName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return nil }
        return "#&!+".contains(first) ? trimmed : "#" + trimmed
    }

    /// A sensible default nick from the macOS short user name.
    static var defaultNick: String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-[]\\`^{}|")
        var nick = String(NSUserName().filter { allowed.contains($0) })
        while let first = nick.first, first.isNumber || first == "-" { nick.removeFirst() }
        return nick.isEmpty ? "vela-user" : String(nick.prefix(16))
    }
}
