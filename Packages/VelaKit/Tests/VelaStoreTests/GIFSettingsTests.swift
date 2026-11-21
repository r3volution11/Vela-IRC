// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite("GIF settings")
struct GIFSettingsTests {
    @Test func defaultsAndValues() {
        #expect(SettingKey<Bool>.gifsEnabled.defaultValue == true)
        #expect(SettingKey<Bool>.gifsAnimatePreviews.defaultValue == true)
        #expect(SettingKey<GIFService>.gifsProvider.defaultValue == .klipy)
        // "IRC is really a service for adults": the loosest rating.
        #expect(SettingKey<GIFRating>.gifsRating.defaultValue == .r)
        #expect(SettingsCatalog.descriptor(forKey: "gifs.rating")?.enumValues == ["g", "pg", "pg-13", "r"])
        #expect(SettingsCatalog.descriptor(forKey: "gifs.provider")?.enumValues == ["klipy", "giphy"])
        #expect(SettingsCatalog.descriptor(forKey: "gifs.rating")?.defaultValue == .string("r"))
    }

    @Test func liveOnTheMediaPane() {
        #expect(SettingsCategory.category(forKey: "gifs.enabled") == .gifs)
        #expect(SettingsCategory.gifs.paneID == "media")
        #expect(SettingsCategory.categories(forPane: "media") == [.media, .gifs])
        #expect(SettingsCatalog.descriptor(forKey: "gifs.rating")?.title == "GIFs: Content Rating")
        #expect(SettingsMetadata.enumLabel("pg-13") == "PG-13")
        #expect(SettingsMetadata.enumLabel("klipy") == "KLIPY")
    }

    @MainActor @Test func readsAndWritesSettingsJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VelaGIFSettings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        try Data(#"{"gifs.rating": "pg-13", "gifs.provider": "giphy", "gifs.enabled": false}"#.utf8).write(to: url)
        let store = SettingsStore(fileURL: url, watchForChanges: false)
        #expect(store[.gifsRating] == .pg13)
        #expect(store[.gifsProvider] == .giphy)
        #expect(store[.gifsEnabled] == false)
        store[.gifsRating] = .g
        #expect(store.values["gifs.rating"] == .string("g"))
    }

    /// Keys you enter go to the Keychain, under accounts of their own.
    @Test func keysHaveKeychainAccountsOfTheirOwn() throws {
        #expect(Keychain.gifServiceKeyAccount(.klipy) == "gifs/klipy")
        #expect(Keychain.gifServiceKeyAccount(.giphy) == "gifs/giphy")
        let keychain = Keychain.inMemory()
        try keychain.setSecret("abc", account: Keychain.gifServiceKeyAccount(.giphy))
        // Removing a network leaves them alone.
        keychain.deleteSecrets(networkID: UUID())
        #expect(keychain.secret(account: "gifs/giphy") == "abc")
    }
}
