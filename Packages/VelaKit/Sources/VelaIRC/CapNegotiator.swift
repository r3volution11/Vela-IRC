// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// IRCv3 capability negotiation state (https://ircv3.net/specs/extensions/capability-negotiation).
///
/// Feed every inbound `CAP` message to `handle(_:)`, then call
/// `nextRequests()` to obtain the `CAP REQ` lines to send. Negotiation can be
/// ended with `CAP END` once `canEnd` is true (and any SASL exchange has
/// finished).
public struct CapNegotiator: Sendable {
    /// Capabilities advertised by the server, mapped to their value (empty
    /// string when the capability has no value).
    public private(set) var available: [String: String] = [:]
    /// Capabilities currently enabled on this connection.
    public private(set) var enabled: Set<String> = []
    /// Capabilities requested and awaiting ACK/NAK.
    public private(set) var pending: Set<String> = []
    /// Capabilities the server refused; never requested again unless the
    /// server re-advertises them with `CAP NEW`.
    public private(set) var rejected: Set<String> = []
    /// Capabilities the client would like to enable when available.
    public var desired: Set<String>
    /// True once the final line of a `CAP LS` reply has arrived.
    public private(set) var lsComplete = false
    /// True once the server has sent any `CAP` reply.
    public private(set) var serverSupportsCap = false

    /// Capabilities that are only ever advertised and must never be
    /// requested (`sts` per the STS spec).
    public static let informationalCapabilities: Set<String> = ["sts"]

    private var lsBuffer: [String: String] = [:]
    private var lsCollecting = false
    private var listBuffer: Set<String> = []
    private var listCollecting = false
    /// Caps from a multi-cap REQ that was NAK'd; they are retried one by one
    /// so a single unsupported cap can't take the whole batch down.
    private var retryIndividually: Set<String> = []

    public init(desired: Set<String>) {
        self.desired = desired
    }

    public enum Event: Sendable, Equatable {
        /// An `LS` line arrived but more are coming.
        case lsPartial
        /// The `LS` reply is complete.
        case lsComplete(available: [String: String])
        /// The server acknowledged a request; `disabled` holds `-cap` entries.
        case acknowledged(enabled: Set<String>, disabled: Set<String>)
        /// The server rejected a request.
        case rejected(Set<String>)
        /// `CAP NEW` (cap-notify).
        case added([String: String])
        /// `CAP DEL` (cap-notify).
        case removed(Set<String>)
        /// A complete `CAP LIST` reply.
        case list(Set<String>)
        /// A `LIST` line arrived but more are coming.
        case listPartial
        /// Not a CAP message, or an unknown subcommand.
        case ignored
    }

    /// Resets per-connection state, keeping `desired`.
    public mutating func reset() {
        self = CapNegotiator(desired: desired)
    }

    /// True when no `LS` is in flight and every request has been answered.
    public var canEnd: Bool { lsComplete && pending.isEmpty }

    public func isEnabled(_ cap: String) -> Bool { enabled.contains(cap) }

    public func value(for cap: String) -> String? { available[cap] }

    /// Mechanisms from `sasl=PLAIN,EXTERNAL`, or nil when the server did not
    /// list any (in which case any mechanism may be attempted).
    public var saslMechanisms: [String]? {
        guard let value = available["sasl"], !value.isEmpty else { return nil }
        return value.split(separator: ",").map { String($0).uppercased() }
    }

    /// The parsed `sts` policy, when advertised.
    public var stsPolicy: STSPolicy? {
        available["sts"].flatMap(STSPolicy.init(value:))
    }

    // MARK: Handling replies

    public mutating func handle(_ message: IRCMessage) -> Event {
        guard message.command == "CAP", message.params.count >= 2 else { return .ignored }
        serverSupportsCap = true
        let subcommand = message.params[1].uppercased()
        let isContinuation = message.params.count >= 4 && message.params[2] == "*"
        let capList = message.params.count >= 3 ? message.params[message.params.count - 1] : ""
        let tokens = Self.parseTokens(capList)

        switch subcommand {
        case "LS":
            if !lsCollecting {
                lsBuffer = [:]
                lsCollecting = true
            }
            for (name, value) in tokens { lsBuffer[name] = value }
            if isContinuation { return .lsPartial }
            lsCollecting = false
            available = lsBuffer
            lsBuffer = [:]
            lsComplete = true
            // A cap that disappeared can't stay enabled.
            enabled.formIntersection(available.keys)
            return .lsComplete(available: available)

        case "LIST":
            if !listCollecting {
                listBuffer = []
                listCollecting = true
            }
            listBuffer.formUnion(tokens.map(\.name))
            if isContinuation { return .listPartial }
            listCollecting = false
            enabled = listBuffer
            return .list(listBuffer)

        case "ACK":
            var added: Set<String> = []
            var removed: Set<String> = []
            for (name, _) in tokens {
                if name.hasPrefix("-") {
                    let bare = String(name.dropFirst())
                    removed.insert(bare)
                    enabled.remove(bare)
                    pending.remove(bare)
                } else {
                    added.insert(name)
                    enabled.insert(name)
                    pending.remove(name)
                }
                retryIndividually.remove(name)
            }
            return .acknowledged(enabled: added, disabled: removed)

        case "NAK":
            let names = Set(tokens.map { $0.name.hasPrefix("-") ? String($0.name.dropFirst()) : $0.name })
            pending.subtract(names)
            if names.count > 1 {
                // Retry each individually once; the ones that fail alone are
                // rejected for good.
                let fresh = names.subtracting(retryIndividually)
                retryIndividually.formUnion(fresh)
                rejected.formUnion(names.intersection(retryIndividually).subtracting(fresh))
            } else {
                rejected.formUnion(names)
                retryIndividually.subtract(names)
            }
            return .rejected(names)

        case "NEW":
            var added: [String: String] = [:]
            for (name, value) in tokens {
                available[name] = value
                added[name] = value
                rejected.remove(name)
            }
            return .added(added)

        case "DEL":
            let names = Set(tokens.map(\.name))
            for name in names {
                available.removeValue(forKey: name)
                enabled.remove(name)
                pending.remove(name)
            }
            return .removed(names)

        default:
            return .ignored
        }
    }

    // MARK: Requests

    /// Capabilities that are desired and available but neither enabled,
    /// pending, rejected nor informational-only.
    public var requestable: Set<String> {
        Set(available.keys)
            .intersection(desired)
            .subtracting(enabled)
            .subtracting(pending)
            .subtracting(rejected)
            .subtracting(Self.informationalCapabilities)
    }

    /// Builds the `CAP REQ` lines for everything `requestable` and marks those
    /// caps as pending. Returns an empty array when there is nothing to ask.
    public mutating func nextRequests(maxLineLength: Int = 510) -> [IRCMessage] {
        let caps = requestable
        guard !caps.isEmpty else { return [] }
        pending.formUnion(caps)
        let solo = caps.intersection(retryIndividually).sorted()
        let grouped = caps.subtracting(retryIndividually)
        return Self.requestLines(grouped, maxLineLength: maxLineLength)
            + solo.map { IRCMessage(command: "CAP", params: ["REQ", $0]) }
    }

    /// Chunks `caps` into `CAP REQ :a b c` lines whose serialized length is at
    /// most `maxLineLength` bytes (CRLF excluded).
    public static func requestLines(_ caps: some Sequence<String>, maxLineLength: Int = 510) -> [IRCMessage] {
        let prefixLength = "CAP REQ :".utf8.count
        let budget = max(1, maxLineLength - prefixLength)
        var lines: [IRCMessage] = []
        var current: [String] = []
        var currentLength = 0
        for cap in caps.sorted() {
            let length = cap.utf8.count
            let added = current.isEmpty ? length : length + 1
            if !current.isEmpty && currentLength + added > budget {
                lines.append(IRCMessage(command: "CAP", params: ["REQ", current.joined(separator: " ")]))
                current = []
                currentLength = 0
            }
            currentLength += current.isEmpty ? length : length + 1
            current.append(cap)
        }
        if !current.isEmpty {
            lines.append(IRCMessage(command: "CAP", params: ["REQ", current.joined(separator: " ")]))
        }
        return lines
    }

    /// Splits a cap list into `(name, value)` pairs, dropping the deprecated
    /// `~`/`=` modifiers (but keeping `-`, which means "disable" in ACK).
    static func parseTokens(_ list: String) -> [(name: String, value: String)] {
        list.split(separator: " ", omittingEmptySubsequences: true).map { token in
            var token = Substring(token)
            while let first = token.first, first == "~" || first == "=" { token = token.dropFirst() }
            if let eq = token.firstIndex(of: "=") {
                return (String(token[..<eq]), String(token[token.index(after: eq)...]))
            }
            return (String(token), "")
        }
    }
}

/// A parsed IRCv3 Strict Transport Security policy (`sts=port=6697,duration=…`).
public struct STSPolicy: Sendable, Hashable {
    /// Secure port to reconnect to (meaningful on plaintext connections).
    public var port: UInt16?
    /// Policy lifetime in seconds (meaningful on secure connections).
    public var duration: Int?
    public var preload: Bool

    public init(port: UInt16? = nil, duration: Int? = nil, preload: Bool = false) {
        self.port = port
        self.duration = duration
        self.preload = preload
    }

    /// Parses a comma-separated `key=value` list; nil when empty.
    public init?(value: String) {
        guard !value.isEmpty else { return nil }
        var port: UInt16?
        var duration: Int?
        var preload = false
        for item in value.split(separator: ",") {
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = pair[0].lowercased()
            let val = pair.count > 1 ? String(pair[1]) : ""
            switch key {
            case "port": port = UInt16(val)
            case "duration": duration = Int(val)
            case "preload": preload = true
            default: break
            }
        }
        self.init(port: port, duration: duration, preload: preload)
    }
}
