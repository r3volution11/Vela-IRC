// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Security

/// Errors thrown by ``Keychain``.
public struct KeychainError: Error, Sendable, Equatable, CustomStringConvertible {
    public let status: OSStatus
    public let operation: String

    public init(status: OSStatus, operation: String) {
        self.status = status
        self.operation = operation
    }

    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Keychain \(operation) failed: \(message)"
    }
}

/// Thin wrapper over Security.framework for passwords, channel keys and TLS
/// client identities.
///
/// Uses the legacy file-based keychain (`kSecUseDataProtectionKeychain =
/// false`) because development builds are ad-hoc signed without a team ID,
/// which the data-protection keychain requires.
public final class Keychain: Sendable {
    public static let shared = Keychain(service: "io.github.r3volution11.Vela")

    public let service: String

    public init(service: String) {
        self.service = service
    }

    /// What a stored secret is for. Combined with a network ID (and, for
    /// channel keys, the channel name) to form the Keychain account name.
    public enum SecretPurpose: String, Sendable, CaseIterable {
        case serverPassword
        case saslPassword
        case nickServPassword
        case channelKey
    }

    // MARK: Account names

    /// The Keychain account for a network secret:
    /// `<network-uuid>/<purpose>` or, with a qualifier (the channel name for
    /// `.channelKey`), `<network-uuid>/<purpose>/<qualifier>`.
    public static func account(networkID: UUID, purpose: SecretPurpose, qualifier: String? = nil) -> String {
        var account = "\(networkID.uuidString)/\(purpose.rawValue)"
        if let qualifier, !qualifier.isEmpty {
            account += "/\(qualifier)"
        }
        return account
    }

    /// The Keychain account for a channel key. Pass the case-folded channel
    /// name so the lookup is stable regardless of how the user typed it.
    public static func channelKeyAccount(networkID: UUID, channel: String) -> String {
        account(networkID: networkID, purpose: .channelKey, qualifier: channel)
    }

    // MARK: Generic passwords

    /// Stores (or replaces) a secret for `account`.
    public func setSecret(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(account: account)
        let update: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            add[kSecAttrLabel] = "Vela (\(account))"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status, operation: "save")
        }
    }

    /// The secret stored for `account`, or `nil` if there is none (or the
    /// Keychain is unavailable).
    public func secret(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the secret for `account`; a missing item is not an error.
    public func deleteSecret(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    /// All account names stored under this service.
    public func accounts() -> [String] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecUseDataProtectionKeychain: false,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[CFString: Any]]
        else { return [] }
        return items.compactMap { $0[kSecAttrAccount] as? String }
    }

    /// Deletes every secret belonging to a network (passwords and channel
    /// keys). Call when a network is removed.
    public func deleteSecrets(networkID: UUID) {
        let prefix = networkID.uuidString + "/"
        for account in accounts() where account.hasPrefix(prefix) {
            deleteSecret(account: account)
        }
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: false,
        ]
    }

    // MARK: Client certificates

    /// Imports a PKCS#12 bundle into the login keychain and returns the
    /// persistent reference of its identity (store it in
    /// ``NetworkConfig/clientCertificateRef``). Re-importing an identity that
    /// is already present returns the existing item's reference.
    public func importPKCS12(_ data: Data, password: String) throws -> Data {
        let options: [CFString: Any] = [kSecImportExportPassphrase: password]
        var rawItems: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess else {
            throw KeychainError(status: status, operation: "PKCS#12 import")
        }
        guard let items = rawItems as? [[CFString: Any]],
              let first = items.first(where: { $0[kSecImportItemIdentity] != nil }),
              let identityValue = first[kSecImportItemIdentity],
              CFGetTypeID(identityValue as CFTypeRef) == SecIdentityGetTypeID()
        else {
            throw KeychainError(status: errSecItemNotFound, operation: "PKCS#12 import")
        }
        let identity = identityValue as! SecIdentity  // swiftlint:disable:this force_cast
        let label = first[kSecImportItemLabel] as? String ?? Self.summary(of: identity)

        // On macOS SecPKCS12Import normally adds the items to the default
        // keychain already; adding explicitly covers the case where it did
        // not, and duplicate errors fall through to a lookup.
        var addQuery: [CFString: Any] = [
            kSecValueRef: identity,
            kSecReturnPersistentRef: true,
            kSecUseDataProtectionKeychain: false,
        ]
        if let label { addQuery[kSecAttrLabel] = label }
        var added: CFTypeRef?
        let addStatus = SecItemAdd(addQuery as CFDictionary, &added)
        if addStatus == errSecSuccess, let reference = added as? Data {
            return reference
        }
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw KeychainError(status: addStatus, operation: "identity save")
        }

        let lookup: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecValueRef: identity,
            kSecReturnPersistentRef: true,
            kSecUseDataProtectionKeychain: false,
        ]
        var found: CFTypeRef?
        let lookupStatus = SecItemCopyMatching(lookup as CFDictionary, &found)
        guard lookupStatus == errSecSuccess, let reference = found as? Data else {
            throw KeychainError(status: lookupStatus, operation: "identity lookup")
        }
        return reference
    }

    /// Resolves a persistent reference to its identity, or `nil` if the item
    /// no longer exists.
    public func identity(persistentRef: Data) -> SecIdentity? {
        let query: [CFString: Any] = [
            kSecValuePersistentRef: persistentRef,
            kSecReturnRef: true,
            kSecUseDataProtectionKeychain: false,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let result,
              CFGetTypeID(result) == SecIdentityGetTypeID()
        else { return nil }
        return (result as! SecIdentity)  // swiftlint:disable:this force_cast
    }

    /// Every identity (certificate + private key) the user can pick as a
    /// client certificate, labelled for display.
    public func identities() -> [(label: String, persistentRef: Data)] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecReturnRef: true,
            kSecReturnPersistentRef: true,
            kSecUseDataProtectionKeychain: false,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[CFString: Any]]
        else { return [] }
        return items.compactMap { item in
            guard let reference = item[kSecValuePersistentRef] as? Data else { return nil }
            var label = item[kSecAttrLabel] as? String
            if label?.isEmpty ?? true, let ref = item[kSecValueRef],
               CFGetTypeID(ref as CFTypeRef) == SecIdentityGetTypeID()
            {
                label = Self.summary(of: ref as! SecIdentity)  // swiftlint:disable:this force_cast
            }
            return (label: label ?? "Unnamed identity", persistentRef: reference)
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private static func summary(of identity: SecIdentity) -> String? {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else {
            return nil
        }
        return SecCertificateCopySubjectSummary(certificate) as String?
    }
}
