// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaStore
@testable import VelaIntelligence

/// Provider keys in the real Keychain, under a service of the test's own
/// (never Vela's), removed afterwards.
@Suite("AI provider keys in the Keychain")
struct AIKeyStoreTests {
    @Test func savesReadsAndRemovesUnderItsOwnAccount() throws {
        let service = "io.github.r3volution11.Vela.tests.\(UUID().uuidString)"
        let keychain = Keychain(service: service)
        defer { keychain.deleteSecret(account: Keychain.aiProviderKeyAccount("anthropic")) }
        #expect(!keychain.service.hasSuffix(".Vela"))
        #expect(Keychain.aiProviderKeyAccount("anthropic") == "ai/anthropic")

        let store = AIKeyStore(keychain: keychain)
        #expect(store.key(for: "anthropic") == nil)
        try store.setKey("  sk-ant-test-key \n", for: "anthropic")
        #expect(store.key(for: "anthropic") == "sk-ant-test-key")
        // Another store on the same service reads it from the Keychain.
        #expect(AIKeyStore(keychain: keychain).key(for: "anthropic") == "sk-ant-test-key")
        #expect(keychain.accounts() == ["ai/anthropic"])

        try store.setKey(nil, for: "anthropic")
        #expect(store.key(for: "anthropic") == nil)
        #expect(AIKeyStore(keychain: keychain).key(for: "anthropic") == nil)
        #expect(keychain.accounts().isEmpty)
    }

    @Test func blankKeysRemoveTheSavedOne() throws {
        let store = AIKeyStore(keychain: .inMemory())
        try store.setKey("abc", for: "openai")
        try store.setKey("   ", for: "openai")
        #expect(!store.hasKey(for: "openai"))
    }
}
