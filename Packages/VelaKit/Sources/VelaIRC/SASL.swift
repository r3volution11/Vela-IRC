// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// SASL mechanisms supported by the client.
public enum SASLMechanism: Sendable, Hashable {
    /// Username/password (RFC 4616).
    case plain(account: String, password: String)
    /// Authenticate with the TLS client certificate (CertFP).
    case external

    /// The IANA mechanism name sent in `AUTHENTICATE <name>`.
    public var name: String {
        switch self {
        case .plain: "PLAIN"
        case .external: "EXTERNAL"
        }
    }

    /// The account name the mechanism authenticates as, if known up front.
    public var account: String? {
        switch self {
        case .plain(let account, _): account
        case .external: nil
        }
    }

    /// The raw (pre-base64) client response to the server's empty challenge.
    var initialResponse: [UInt8] {
        switch self {
        case let .plain(account, password):
            // authzid \0 authcid \0 passwd
            Array(account.utf8) + [0] + Array(account.utf8) + [0] + Array(password.utf8)
        case .external:
            []
        }
    }
}

/// Drives a single SASL exchange (https://ircv3.net/specs/extensions/sasl-3.1).
///
/// Call `start()` once the `sasl` capability is ACKed and send the result,
/// then feed every `AUTHENTICATE` and 900–908 numeric to `handle(_:)`.
public struct SASLAuthenticator: Sendable {
    /// Maximum base64 bytes per `AUTHENTICATE` line.
    public static let chunkSize = 400

    public enum Outcome: Sendable, Equatable {
        /// Lines to send to the server.
        case send([IRCMessage])
        /// 900 RPL_LOGGEDIN: the account we're now logged in as.
        case loggedIn(account: String)
        /// 901 RPL_LOGGEDOUT.
        case loggedOut
        /// 908 RPL_SASLMECHS: the mechanisms the server supports.
        case mechanisms([String])
        /// 903 (or 907, already authenticated). Negotiation may end.
        case succeeded(message: String)
        /// 902/904/905/906, or an unexpected challenge. Negotiation may end.
        case failed(message: String)
        /// Nothing to do.
        case none
    }

    public let mechanism: SASLMechanism
    /// Account from 900 RPL_LOGGEDIN, when received.
    public private(set) var account: String?
    /// Mechanisms the server listed in 908, if any.
    public private(set) var serverMechanisms: [String]?
    public private(set) var isStarted = false
    public private(set) var isFinished = false
    private var responded = false

    public init(mechanism: SASLMechanism) {
        self.mechanism = mechanism
    }

    /// The opening `AUTHENTICATE <MECHANISM>` line.
    public mutating func start() -> IRCMessage {
        isStarted = true
        return IRCMessage(command: "AUTHENTICATE", params: [mechanism.name])
    }

    public mutating func handle(_ message: IRCMessage) -> Outcome {
        let text = message.params.last ?? ""
        switch message.command {
        case "AUTHENTICATE":
            guard isStarted, !isFinished else { return .none }
            guard message.params.first == "+" else {
                // PLAIN and EXTERNAL only ever expect an empty challenge.
                isFinished = true
                return .send([IRCMessage(command: "AUTHENTICATE", params: ["*"])])
            }
            guard !responded else { return .none }
            responded = true
            return .send(Self.responseMessages(for: mechanism.initialResponse))

        case IRCNumeric.loggedIn:
            // :server 900 <nick> <nick!ident@host> <account> :You are now logged in as <account>
            let name = message.params.count >= 3 ? message.params[2] : (mechanism.account ?? "")
            account = name
            return .loggedIn(account: name)

        case IRCNumeric.loggedOut:
            account = nil
            return .loggedOut

        case IRCNumeric.saslSuccess, IRCNumeric.saslAlready:
            isFinished = true
            return .succeeded(message: text)

        case IRCNumeric.nickLocked, IRCNumeric.saslFail, IRCNumeric.saslTooLong, IRCNumeric.saslAborted:
            isFinished = true
            return .failed(message: text)

        case IRCNumeric.saslMechanisms:
            let list = message.params.count >= 2 ? message.params[1] : ""
            let mechanisms = list.split(separator: ",").map { String($0).uppercased() }
            serverMechanisms = mechanisms
            return .mechanisms(mechanisms)

        default:
            return .none
        }
    }

    /// Base64-encodes `payload` into `AUTHENTICATE` lines of at most 400
    /// bytes. An empty payload, or one whose encoding is an exact multiple of
    /// 400 bytes, is terminated with `AUTHENTICATE +`.
    public static func responseMessages(for payload: [UInt8]) -> [IRCMessage] {
        let encoded = Data(payload).base64EncodedString()
        guard !encoded.isEmpty else { return [IRCMessage(command: "AUTHENTICATE", params: ["+"])] }
        let bytes = Array(encoded.utf8)
        var lines: [IRCMessage] = []
        var start = 0
        while start < bytes.count {
            let end = min(start + chunkSize, bytes.count)
            lines.append(IRCMessage(command: "AUTHENTICATE", params: [String(decoding: bytes[start..<end], as: UTF8.self)]))
            start = end
        }
        if bytes.count % chunkSize == 0 {
            lines.append(IRCMessage(command: "AUTHENTICATE", params: ["+"]))
        }
        return lines
    }

    /// Whether `command` is one the authenticator wants to see.
    public static func handles(_ command: String) -> Bool {
        switch command {
        case "AUTHENTICATE", IRCNumeric.loggedIn, IRCNumeric.loggedOut, IRCNumeric.nickLocked,
             IRCNumeric.saslSuccess, IRCNumeric.saslFail, IRCNumeric.saslTooLong,
             IRCNumeric.saslAborted, IRCNumeric.saslAlready, IRCNumeric.saslMechanisms:
            true
        default:
            false
        }
    }
}
