// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// How the client authenticates with SASL.
public enum SASLKind: String, Codable, Sendable, CaseIterable {
    case none
    /// SASL PLAIN; the password lives in the Keychain (`.saslPassword`).
    case plain
    /// SASL EXTERNAL using the TLS client certificate.
    case external
}

/// The kind of bouncer a network entry talks to.
public enum BouncerKind: String, Codable, Sendable, CaseIterable {
    case none
    case soju
    case znc
}

/// A channel joined automatically after registration. The channel key, if
/// any, is stored in the Keychain under
/// ``Keychain/channelKeyAccount(networkID:channel:)``.
public struct AutoJoinChannel: Codable, Sendable, Hashable {
    public var name: String
    public var hasKey: Bool

    public init(name: String, hasKey: Bool = false) {
        self.name = name
        self.hasKey = hasKey
    }

    private enum CodingKeys: String, CodingKey {
        case name, hasKey
    }

    /// Accepts either `{"name": "#vela", "hasKey": false}` or a bare
    /// `"#vela"` string (handy when editing networks.json by hand).
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            self.init(name: name)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        let hasKey = (try? container.decodeIfPresent(Bool.self, forKey: .hasKey)) ?? false
        self.init(name: name, hasKey: hasKey)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(hasKey, forKey: .hasKey)
    }
}

/// A saved IRC network (or bouncer, or bouncer child network).
///
/// Secrets are never stored here: passwords and channel keys live in the
/// Keychain (see ``Keychain/account(networkID:purpose:qualifier:)``); this
/// struct only records *whether* one exists.
///
/// Decoding is deliberately forgiving so configs survive app upgrades,
/// downgrades and (later) iCloud sync between versions: every key is
/// optional, values of the wrong type fall back to their defaults, and keys
/// this version does not know are kept in ``additionalFields`` and written
/// back out unchanged.
public struct NetworkConfig: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String

    public var host: String
    public var port: UInt16
    public var useTLS: Bool
    public var allowInvalidCertificates: Bool

    public var nick: String
    public var alternateNicks: [String]
    public var username: String
    public var realname: String

    public var hasServerPassword: Bool
    public var saslKind: SASLKind
    public var saslAccount: String?
    /// Keychain persistent reference to a `SecIdentity` used as the TLS
    /// client certificate. Persistent references are only meaningful on the
    /// Mac that created them; a synced config needs the identity re-picked.
    public var clientCertificateRef: Data?

    public var autoJoin: [AutoJoinChannel]
    public var performCommands: [String]
    public var autoConnect: Bool

    public var bouncerKind: BouncerKind
    /// For soju child networks discovered via `BOUNCER LISTNETWORKS`: the
    /// bouncer connection this entry belongs to.
    public var parentNetworkID: UUID?
    /// The soju `netid` used for `BOUNCER BIND`.
    public var bouncerNetworkID: String?

    public var highlightWords: [String]
    public var ignoreMasks: [String]

    public var sortOrder: Int
    public var createdAt: Date
    public var modifiedAt: Date

    /// Keys written by a newer (or older) version of Vela that this version
    /// does not understand. Preserved verbatim on save.
    public var additionalFields: [String: JSONValue]

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 6697,
        useTLS: Bool = true,
        allowInvalidCertificates: Bool = false,
        nick: String,
        alternateNicks: [String] = [],
        username: String? = nil,
        realname: String? = nil,
        hasServerPassword: Bool = false,
        saslKind: SASLKind = .none,
        saslAccount: String? = nil,
        clientCertificateRef: Data? = nil,
        autoJoin: [AutoJoinChannel] = [],
        performCommands: [String] = [],
        autoConnect: Bool = true,
        bouncerKind: BouncerKind = .none,
        parentNetworkID: UUID? = nil,
        bouncerNetworkID: String? = nil,
        highlightWords: [String] = [],
        ignoreMasks: [String] = [],
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.allowInvalidCertificates = allowInvalidCertificates
        self.nick = nick
        self.alternateNicks = alternateNicks
        self.username = username ?? nick
        self.realname = realname ?? nick
        self.hasServerPassword = hasServerPassword
        self.saslKind = saslKind
        self.saslAccount = saslAccount
        self.clientCertificateRef = clientCertificateRef
        self.autoJoin = autoJoin
        self.performCommands = performCommands
        self.autoConnect = autoConnect
        self.bouncerKind = bouncerKind
        self.parentNetworkID = parentNetworkID
        self.bouncerNetworkID = bouncerNetworkID
        self.highlightWords = highlightWords
        self.ignoreMasks = ignoreMasks
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.additionalFields = additionalFields
    }

    /// Whether this entry is a soju child network rather than a top-level
    /// connection.
    public var isBouncerChild: Bool { parentNetworkID != nil }

    // MARK: Codable

    enum Field: String, CaseIterable {
        case id, name, host, port, useTLS, allowInvalidCertificates
        case nick, alternateNicks, username, realname
        case hasServerPassword, saslKind, saslAccount, clientCertificateRef
        case autoJoin, performCommands, autoConnect
        case bouncerKind, parentNetworkID, bouncerNetworkID
        case highlightWords, ignoreMasks
        case sortOrder, createdAt, modifiedAt

        var key: AnyCodingKey { AnyCodingKey(rawValue) }
    }

    /// Missing or mistyped keys fall back to defaults; unknown keys are kept.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        func value<T: Decodable>(_ field: Field, as type: T.Type = T.self) -> T? {
            try? container.decodeIfPresent(T.self, forKey: field.key)
        }
        func date(_ field: Field) -> Date? {
            if let string = value(field, as: String.self) { return ISODate.date(from: string) }
            if let seconds = value(field, as: Double.self) { return Date(timeIntervalSince1970: seconds) }
            return nil
        }

        let nick = value(.nick, as: String.self) ?? ""
        let useTLS = value(.useTLS, as: Bool.self) ?? true
        // Missing timestamps sort as "oldest" so any real edit wins a merge.
        let epoch = Date(timeIntervalSince1970: 0)
        let createdAt = date(.createdAt) ?? epoch

        var certificateRef: Data?
        if let base64 = value(.clientCertificateRef, as: String.self) {
            certificateRef = Data(base64Encoded: base64)
        }

        var extras: [String: JSONValue] = [:]
        let known = Set(Field.allCases.map(\.rawValue))
        for key in container.allKeys where !known.contains(key.stringValue) {
            if let extra = try? container.decode(JSONValue.self, forKey: key) {
                extras[key.stringValue] = extra
            }
        }

        self.init(
            id: value(.id) ?? UUID(),
            name: value(.name) ?? "",
            host: value(.host) ?? "",
            port: value(.port) ?? (useTLS ? 6697 : 6667),
            useTLS: useTLS,
            allowInvalidCertificates: value(.allowInvalidCertificates) ?? false,
            nick: nick,
            alternateNicks: value(.alternateNicks) ?? [],
            username: value(.username, as: String.self),
            realname: value(.realname, as: String.self),
            hasServerPassword: value(.hasServerPassword) ?? false,
            saslKind: value(.saslKind) ?? .none,
            saslAccount: value(.saslAccount, as: String.self),
            clientCertificateRef: certificateRef,
            autoJoin: value(.autoJoin) ?? [],
            performCommands: value(.performCommands) ?? [],
            autoConnect: value(.autoConnect) ?? true,
            bouncerKind: value(.bouncerKind) ?? .none,
            parentNetworkID: value(.parentNetworkID, as: UUID.self),
            bouncerNetworkID: value(.bouncerNetworkID, as: String.self),
            highlightWords: value(.highlightWords) ?? [],
            ignoreMasks: value(.ignoreMasks) ?? [],
            sortOrder: value(.sortOrder) ?? 0,
            createdAt: createdAt,
            modifiedAt: date(.modifiedAt) ?? createdAt,
            additionalFields: extras
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        let known = Set(Field.allCases.map(\.rawValue))
        for (key, value) in additionalFields where !known.contains(key) {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(id, forKey: Field.id.key)
        try container.encode(name, forKey: Field.name.key)
        try container.encode(host, forKey: Field.host.key)
        try container.encode(port, forKey: Field.port.key)
        try container.encode(useTLS, forKey: Field.useTLS.key)
        try container.encode(allowInvalidCertificates, forKey: Field.allowInvalidCertificates.key)
        try container.encode(nick, forKey: Field.nick.key)
        try container.encode(alternateNicks, forKey: Field.alternateNicks.key)
        try container.encode(username, forKey: Field.username.key)
        try container.encode(realname, forKey: Field.realname.key)
        try container.encode(hasServerPassword, forKey: Field.hasServerPassword.key)
        try container.encode(saslKind, forKey: Field.saslKind.key)
        try container.encodeIfPresent(saslAccount, forKey: Field.saslAccount.key)
        try container.encodeIfPresent(
            clientCertificateRef?.base64EncodedString(),
            forKey: Field.clientCertificateRef.key
        )
        try container.encode(autoJoin, forKey: Field.autoJoin.key)
        try container.encode(performCommands, forKey: Field.performCommands.key)
        try container.encode(autoConnect, forKey: Field.autoConnect.key)
        try container.encode(bouncerKind, forKey: Field.bouncerKind.key)
        try container.encodeIfPresent(parentNetworkID, forKey: Field.parentNetworkID.key)
        try container.encodeIfPresent(bouncerNetworkID, forKey: Field.bouncerNetworkID.key)
        try container.encode(highlightWords, forKey: Field.highlightWords.key)
        try container.encode(ignoreMasks, forKey: Field.ignoreMasks.key)
        try container.encode(sortOrder, forKey: Field.sortOrder.key)
        try container.encode(ISODate.string(from: createdAt), forKey: Field.createdAt.key)
        try container.encode(ISODate.string(from: modifiedAt), forKey: Field.modifiedAt.key)
    }
}
