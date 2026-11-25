// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization
import VelaStore

/// Your providers' API keys, kept only in the Keychain
/// (`Keychain.aiProviderKeyAccount`, under Vela's own service), never in
/// settings.json or anywhere else on disk. Each key is read once, the
/// first time it's needed, and kept in memory for the session. Tests use
/// a Keychain of their own (a separate service, or `Keychain.inMemory()`).
nonisolated public final class AIKeyStore: Sendable {
    private let keychain: Keychain
    /// Keys read so far: a provider's id → its key, or nil for none.
    private let cache = Mutex<[String: String?]>([:])

    public init(keychain: Keychain) {
        self.keychain = keychain
    }

    /// The provider's key, or nil when there's none.
    public func key(for providerID: String) -> String? {
        if let cached = cache.withLock({ $0[providerID] }) { return cached }
        let key = keychain.secret(account: Keychain.aiProviderKeyAccount(providerID)).flatMap(Self.cleaned)
        cache.withLock { $0[providerID] = .some(key) }
        return key
    }

    public func hasKey(for providerID: String) -> Bool {
        key(for: providerID) != nil
    }

    /// Saves `key` for the provider, or removes its key for nil or blank.
    public func setKey(_ key: String?, for providerID: String) throws {
        let account = Keychain.aiProviderKeyAccount(providerID)
        if let key = key.flatMap(Self.cleaned) {
            try keychain.setSecret(key, account: account)
            cache.withLock { $0[providerID] = .some(key) }
        } else {
            keychain.deleteSecret(account: account)
            cache.withLock { $0[providerID] = .some(nil) }
        }
    }

    /// A pasted key without the spaces and line breaks around it.
    static func cleaned(_ key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
