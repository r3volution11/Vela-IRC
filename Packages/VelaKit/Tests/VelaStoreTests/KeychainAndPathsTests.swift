// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaStore

@Suite struct KeychainTests {
    @Test func accountNames() {
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        #expect(Keychain.account(networkID: id, purpose: .saslPassword)
            == "6F9619FF-8B86-D011-B42D-00C04FC964FF/saslPassword")
        #expect(Keychain.account(networkID: id, purpose: .serverPassword)
            == "6F9619FF-8B86-D011-B42D-00C04FC964FF/serverPassword")
        #expect(Keychain.channelKeyAccount(networkID: id, channel: "#vela")
            == "6F9619FF-8B86-D011-B42D-00C04FC964FF/channelKey/#vela")
        #expect(Keychain.account(networkID: id, purpose: .channelKey, qualifier: "#vela")
            == Keychain.channelKeyAccount(networkID: id, channel: "#vela"))
        #expect(Keychain.shared.service == "io.github.r3volution11.Vela")
    }

    /// Touches the real login keychain, so it is skipped on CI. If the
    /// keychain is locked or unavailable the test returns early instead of
    /// failing.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func secretRoundTrip() throws {
        let keychain = Keychain(service: "io.github.r3volution11.Vela.tests.\(UUID().uuidString)")
        let network = UUID()
        let account = Keychain.account(networkID: network, purpose: .saslPassword)
        let channelAccount = Keychain.channelKeyAccount(networkID: network, channel: "#secret")
        defer {
            keychain.deleteSecret(account: account)
            keychain.deleteSecret(account: channelAccount)
        }

        do {
            try keychain.setSecret("hunter2", account: account)
        } catch {
            print("Skipping keychain round trip: \(error)")
            return
        }
        #expect(keychain.secret(account: account) == "hunter2")

        try keychain.setSecret("correct horse ✓", account: account)
        #expect(keychain.secret(account: account) == "correct horse ✓")

        try keychain.setSecret("chankey", account: channelAccount)
        #expect(Set(keychain.accounts()) == [account, channelAccount])

        keychain.deleteSecrets(networkID: network)
        #expect(keychain.secret(account: account) == nil)
        #expect(keychain.secret(account: channelAccount) == nil)
        keychain.deleteSecret(account: account)  // deleting a missing item is fine
    }

    /// For tests: passwords and channel keys in memory, no certificates.
    @Test func inMemoryKeychain() throws {
        let keychain = Keychain.inMemory()
        let network = UUID()
        let account = Keychain.channelKeyAccount(networkID: network, channel: "#secret")
        #expect(keychain.secret(account: account) == nil)
        try keychain.setSecret("hunter2", account: account)
        try keychain.setSecret("other", account: Keychain.account(networkID: UUID(), purpose: .saslPassword))
        #expect(keychain.secret(account: account) == "hunter2")
        #expect(Keychain.inMemory().secret(account: account) == nil)
        keychain.deleteSecrets(networkID: network)
        #expect(keychain.secret(account: account) == nil)
        #expect(keychain.accounts().count == 1)
        #expect(keychain.identities().isEmpty)
        #expect(throws: KeychainError.self) { _ = try keychain.importPKCS12(Data(), password: "") }
    }

    @Test func missingItemsReturnNil() {
        let keychain = Keychain(service: "io.github.r3volution11.Vela.tests.\(UUID().uuidString)")
        #expect(keychain.secret(account: "nobody") == nil)
        #expect(keychain.identity(persistentRef: Data([1, 2, 3])) == nil)
    }

    @Test func invalidPKCS12Throws() {
        let keychain = Keychain(service: "io.github.r3volution11.Vela.tests.\(UUID().uuidString)")
        #expect(throws: KeychainError.self) {
            _ = try keychain.importPKCS12(Data("not a pkcs12".utf8), password: "x")
        }
    }
}

@Suite struct AppPathsTests {
    @Test func overrideRootRedirectsAllPaths() throws {
        let directory = try TemporaryDirectory()
        defer {
            AppPaths.overrideRoot(nil)
            directory.cleanup()
        }
        let root = directory.url.appending(path: "Profile", directoryHint: .isDirectory)
        AppPaths.overrideRoot(root)

        #expect(AppPaths.root.standardizedFileURL == root.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: root.path(percentEncoded: false)))
        #expect(AppPaths.themesDirectory.lastPathComponent == "Themes")
        #expect(FileManager.default.fileExists(atPath: AppPaths.themesDirectory.path(percentEncoded: false)))
        #expect(AppPaths.databaseURL == root.appending(path: "vela.sqlite"))
        #expect(AppPaths.settingsURL == root.appending(path: "settings.json"))
        #expect(AppPaths.networksURL == root.appending(path: "networks.json"))

        // The default location (checked without creating it on this Mac).
        #expect(AppPaths.defaultRoot.lastPathComponent == "Vela")
        #expect(AppPaths.defaultRoot.deletingLastPathComponent().lastPathComponent == "Application Support")
    }
}
