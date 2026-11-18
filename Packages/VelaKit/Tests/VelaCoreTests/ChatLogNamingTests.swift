// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import VelaCore

@Suite("Chat log names")
struct ChatLogNamingTests {
    @Test(arguments: [
        ("#vela", "#vela"),
        ("#C++", "#C++"),
        ("#a/b", "#a_b"),
        ("#a:b", "#a_b"),
        ("Libera.Chat", "Libera.Chat"),
        (".hidden", "_hidden"),
        ("tab\there", "tab_here"),
        ("", "_"),
        ("#日本語", "#日本語"),
    ])
    func sanitizes(_ name: String, _ expected: String) {
        #expect(ChatLogNaming.sanitize(name) == expected)
    }

    @Test func longNamesAreShortenedOnCharacterBoundaries() {
        let name = "#" + String(repeating: "é", count: 300)
        let sanitized = ChatLogNaming.sanitize(name)
        #expect(sanitized.utf8.count <= ChatLogNaming.maxBaseBytes)
        #expect(sanitized.hasPrefix("#é"))
        let rotated = ChatLogNaming.rotatedFileName(base: sanitized, from: "2026-11-01", to: "2026-11-17", counter: 12)
        #expect(rotated.utf8.count <= 255)
    }

    @Test func fileBases() {
        #expect(ChatLogNaming.fileBase(bufferName: "#Vela", kind: .channel) == "#Vela")
        #expect(ChatLogNaming.fileBase(bufferName: "Libera.Chat", kind: .server) == "server")
        #expect(ChatLogNaming.fileBase(bufferName: "alice", kind: .query) == "alice")
        // Someone called "server" doesn't share server.log.
        #expect(ChatLogNaming.fileBase(bufferName: "Server", kind: .query) == "Server (query)")
        #expect(ChatLogNaming.currentFileName(base: "#vela") == "#vela.log")
    }

    @Test func rotatedNamesSortAndParse() {
        let name = ChatLogNaming.rotatedFileName(base: "#vela", from: "2026-11-01", to: "2026-11-17")
        #expect(name == "#vela 2026-11-01 – 2026-11-17.log")
        #expect(ChatLogNaming.parseRotated(name, base: "#vela")?.from == "2026-11-01")
        #expect(ChatLogNaming.parseRotated(name, base: "#vela")?.to == "2026-11-17")
        let second = ChatLogNaming.rotatedFileName(base: "#vela", from: "2026-11-17", to: "2026-11-17", counter: 2)
        #expect(second == "#vela 2026-11-17 – 2026-11-17 (2).log")
        #expect(ChatLogNaming.parseRotated(second, base: "#vela")?.counter == 2)
        // Another channel's files, the current file and other files don't match.
        #expect(ChatLogNaming.parseRotated(name, base: "#vel") == nil)
        #expect(ChatLogNaming.parseRotated("#vela.log", base: "#vela") == nil)
        #expect(ChatLogNaming.parseRotated("#vela notes.log", base: "#vela") == nil)
        #expect(ChatLogNaming.isRotatedFileName("server (query) 2026-11-01 – 2026-11-02.log"))
        #expect(!ChatLogNaming.isRotatedFileName("server (query).log"))
    }

    @MainActor
    @Test func networkFoldersAreUniqueAndStable() {
        let libera = UUID(), other = UUID(), oftc = UUID()
        let folders = ChatLogNetworkFolders(saved: [:])
        #expect(folders.folderName(for: libera, displayName: "Libera.Chat") == "Libera.Chat")
        #expect(folders.folderName(for: oftc, displayName: "OFTC") == "OFTC")
        // A second network with the same name (any case) gets its own folder.
        #expect(folders.folderName(for: other, displayName: "libera.chat") == "libera.chat (2)")
        #expect(folders.folderName(for: other, displayName: "libera.chat") == "libera.chat (2)")

        // After a restart, each keeps its folder whichever logs first.
        let restored = ChatLogNetworkFolders(saved: folders.names)
        #expect(restored.folderName(for: other, displayName: "libera.chat") == "libera.chat (2)")
        #expect(restored.folderName(for: libera, displayName: "Libera.Chat") == "Libera.Chat")
    }

    @MainActor
    @Test func renamedNetworksGetANewFolderName() {
        let id = UUID()
        let folders = ChatLogNetworkFolders(saved: [:])
        #expect(folders.folderName(for: id, displayName: "irc.libera.chat") == "irc.libera.chat")
        #expect(folders.folderName(for: id, displayName: "Libera/Chat") == "Libera_Chat")
        #expect(folders.names[id.uuidString] == "Libera_Chat")
    }

    @MainActor
    @Test func removedNetworksFreeTheirNames() {
        let gone = UUID(), new = UUID()
        let folders = ChatLogNetworkFolders(saved: [gone.uuidString: "Libera.Chat"])
        folders.prune(keeping: [new])
        #expect(folders.folderName(for: new, displayName: "Libera.Chat") == "Libera.Chat")
    }

    @Test func counterSuffixes() {
        #expect(ChatLogNetworkFolders.withoutCounter("Libera (2)") == "Libera")
        #expect(ChatLogNetworkFolders.withoutCounter("Libera (x)") == "Libera (x)")
        #expect(ChatLogNetworkFolders.withoutCounter("Libera") == "Libera")
    }
}
