// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite struct NetworkConfigCodingTests {
    private func decode(_ json: String) throws -> NetworkConfig {
        try JSONDecoder().decode(NetworkConfig.self, from: Data(json.utf8))
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let config = try decode(#"{"name": "Libera", "host": "irc.libera.chat", "nick": "vela"}"#)
        #expect(config.name == "Libera")
        #expect(config.host == "irc.libera.chat")
        #expect(config.port == 6697)
        #expect(config.useTLS)
        #expect(!config.allowInvalidCertificates)
        #expect(config.username == "vela")
        #expect(config.realname == "vela")
        #expect(config.saslKind == .none)
        #expect(config.bouncerKind == .none)
        #expect(config.autoJoin.isEmpty)
        #expect(config.autoConnect)
        #expect(config.parentNetworkID == nil)
        #expect(config.sortOrder == 0)
        #expect(config.createdAt == Date(timeIntervalSince1970: 0))
        #expect(config.modifiedAt == config.createdAt)
        #expect(config.additionalFields.isEmpty)
    }

    @Test func plaintextDefaultsToPort6667() throws {
        let config = try decode(#"{"host": "irc.example.org", "nick": "v", "useTLS": false}"#)
        #expect(config.port == 6667)
    }

    @Test func emptyObjectDecodes() throws {
        let config = try decode("{}")
        #expect(config.name.isEmpty)
        #expect(config.nick.isEmpty)
    }

    @Test func unknownKeysAndBadValuesAreTolerated() throws {
        let id = UUID()
        let config = try decode("""
            {
              "id": "\(id.uuidString)",
              "name": "Future",
              "nick": "vela",
              "port": "not a number",
              "saslKind": "scram-sha-256",
              "autoConnect": "yes",
              "futureField": {"a": 1, "b": [true, null]},
              "anotherOne": "x"
            }
            """)
        #expect(config.id == id)
        #expect(config.port == 6697)
        #expect(config.saslKind == .none)
        #expect(config.autoConnect)
        #expect(config.additionalFields["futureField"] == .object(["a": .number(1), "b": .array([.bool(true), .null])]))
        #expect(config.additionalFields["anotherOne"] == .string("x"))

        // Unknown keys survive a re-encode.
        let reencoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(config))
        #expect(reencoded["futureField"] == config.additionalFields["futureField"])
        #expect(reencoded["anotherOne"] == .string("x"))
        #expect(reencoded["name"] == .string("Future"))
    }

    /// What waits for a bouncer is saved only while there's something.
    @Test func pendingPartsAndDetaches() throws {
        var config = try decode(##"{"nick": "v", "pendingParts": ["#gone"], "pendingDetaches": ["#quiet", "#busy"]}"##)
        #expect(config.pendingParts == ["#gone"])
        #expect(config.pendingDetaches == ["#quiet", "#busy"])
        #expect(config.additionalFields.isEmpty)
        var encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(config))
        #expect(encoded["pendingParts"] == .array([.string("#gone")]))
        #expect(encoded["pendingDetaches"] == .array([.string("#quiet"), .string("#busy")]))

        config.pendingParts = []
        config.pendingDetaches = []
        encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(config))
        #expect(encoded["pendingParts"] == nil)
        #expect(encoded["pendingDetaches"] == nil)
        #expect(try decode("{}").pendingParts.isEmpty)
    }

    @Test func autoJoinAcceptsStringsAndObjects() throws {
        let config = try decode(##"{"nick": "v", "autoJoin": ["#vela", {"name": "#secret", "hasKey": true}, {"name": "#x"}]}"##)
        #expect(config.autoJoin == [
            AutoJoinChannel(name: "#vela"),
            AutoJoinChannel(name: "#secret", hasKey: true),
            AutoJoinChannel(name: "#x", hasKey: false),
        ])
    }

    @Test func fullRoundTrip() throws {
        let parent = UUID()
        let original = NetworkConfig(
            name: "soju child",
            host: "bouncer.example.org",
            port: 6697,
            nick: "vela",
            alternateNicks: ["vela_", "vela__"],
            username: "vela/libera",
            realname: "Vela User",
            hasServerPassword: true,
            saslKind: .plain,
            saslAccount: "vela",
            clientCertificateRef: Data([0x01, 0x02, 0xFF]),
            autoJoin: [AutoJoinChannel(name: "#vela", hasKey: true)],
            performCommands: ["/mode $nick +i"],
            autoConnect: false,
            bouncerKind: .soju,
            parentNetworkID: parent,
            bouncerNetworkID: "42",
            highlightWords: ["vela"],
            ignoreMasks: ["*!*@spam"],
            sortOrder: 3,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_500),
            additionalFields: ["x-extra": .bool(true)]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NetworkConfig.self, from: data)
        #expect(decoded == original)
        #expect(decoded.isBouncerChild)

        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(json["createdAt"] == .string("2023-11-14T22:13:20.000Z"))
        #expect(json["clientCertificateRef"] == .string(Data([0x01, 0x02, 0xFF]).base64EncodedString()))
    }

    @Test func numericDatesAreAccepted() throws {
        let config = try decode(#"{"nick": "v", "createdAt": 1700000000, "modifiedAt": "2023-11-14T22:13:20Z"}"#)
        #expect(config.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(config.modifiedAt == Date(timeIntervalSince1970: 1_700_000_000))
    }
}

@MainActor
@Suite struct NetworkConfigStoreTests {
    private func makeConfig(_ name: String) -> NetworkConfig {
        NetworkConfig(name: name, host: "irc.\(name.lowercased()).example", nick: "vela")
    }

    @Test func missingFileLoadsEmpty() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let store = NetworkConfigStore(fileURL: directory.file("networks.json"))
        try store.load()
        #expect(store.networks.isEmpty)
        #expect(store.lastError == nil)
    }

    @Test func roundTripAndOrdering() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("networks.json")
        let store = NetworkConfigStore(fileURL: url)
        try store.load()

        let before = Date()
        var libera = makeConfig("Libera")
        libera.sortOrder = 99  // ignored for new entries: appended at the end
        store.upsert(libera)
        store.upsert(makeConfig("OFTC"))
        store.upsert(makeConfig("Rizon"))
        #expect(store.networks.map(\.name) == ["Libera", "OFTC", "Rizon"])
        #expect(store.networks.map(\.sortOrder) == [0, 1, 2])
        #expect(store.networks.allSatisfy { $0.modifiedAt >= before })

        let reloaded = NetworkConfigStore(fileURL: url)
        try reloaded.load()
        #expect(reloaded.networks.map(\.id) == store.networks.map(\.id))
        #expect(reloaded.networks.map(\.name) == ["Libera", "OFTC", "Rizon"])
        #expect(reloaded.networks.map(\.sortOrder) == [0, 1, 2])
        for (lhs, rhs) in zip(reloaded.networks, store.networks) {
            #expect(abs(lhs.modifiedAt.timeIntervalSince(rhs.modifiedAt)) < 0.002)
            #expect(lhs.host == rhs.host)
        }

        // Move Rizon to the front.
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.networks.map(\.name) == ["Rizon", "Libera", "OFTC"])
        #expect(store.networks.map(\.sortOrder) == [0, 1, 2])

        // Move Rizon to the end (SwiftUI semantics: toOffset is pre-removal).
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(store.networks.map(\.name) == ["Libera", "OFTC", "Rizon"])

        // An explicit order; unlisted networks follow in their current order.
        let ids = Dictionary(uniqueKeysWithValues: store.networks.map { ($0.name, $0.id) })
        store.reorder([ids["Rizon"]!])
        #expect(store.networks.map(\.name) == ["Rizon", "Libera", "OFTC"])
        #expect(store.networks.map(\.sortOrder) == [0, 1, 2])
        try reloaded.load()
        #expect(reloaded.networks.map(\.name) == ["Rizon", "Libera", "OFTC"])
        store.reorder([ids["Libera"]!, ids["OFTC"]!, ids["Rizon"]!])
        #expect(store.networks.map(\.name) == ["Libera", "OFTC", "Rizon"])

        // Updating keeps the position and bumps modifiedAt.
        var oftc = try #require(store.networks.first { $0.name == "OFTC" })
        let oldModified = oftc.modifiedAt
        oftc.nick = "vela2"
        store.upsert(oftc)
        #expect(store.networks.map(\.name) == ["Libera", "OFTC", "Rizon"])
        #expect(store.network(id: oftc.id)?.nick == "vela2")
        #expect(try #require(store.network(id: oftc.id)).modifiedAt >= oldModified)

        store.remove(id: oftc.id)
        #expect(store.networks.map(\.name) == ["Libera", "Rizon"])

        try reloaded.load()
        #expect(reloaded.networks.map(\.name) == ["Libera", "Rizon"])
        #expect(reloaded.networks.map(\.nick) == ["vela", "vela"])
    }

    @Test func loadsJSONCAndPreservesUnknownKeys() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("networks.json")
        let id = UUID()
        try writeString("""
            // Hand-edited networks
            {
              "version": 7,
              "syncToken": "abc",
              "networks": [
                {
                  "id": "\(id.uuidString)",
                  "name": "Libera", /* inline comment */
                  "host": "irc.libera.chat",
                  "nick": "vela",
                  "x-future": 1,
                },
                "garbage entry",
                {"id": "\(id.uuidString)", "name": "duplicate id"},
              ],
            }
            """, to: url)

        let store = NetworkConfigStore(fileURL: url)
        try store.load()
        #expect(store.networks.count == 1)
        #expect(store.networks.first?.id == id)
        #expect(store.networks.first?.additionalFields["x-future"] == .number(1))

        store.upsert(makeConfig("OFTC"))
        let saved = try JSONC.value(from: Data(contentsOf: url))
        #expect(saved["syncToken"] == .string("abc"))
        #expect(saved["version"] == .number(Double(NetworkConfigStore.fileFormatVersion)))
        let first = try #require(saved["networks"]?.arrayValue?.first)
        #expect(first["x-future"] == .number(1))
        #expect(first["sortOrder"] == .number(0))
    }

    @Test func bareArrayIsAccepted() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("networks.json")
        try writeString(#"[{"name": "A", "nick": "a", "sortOrder": 1}, {"name": "B", "nick": "b", "sortOrder": 0}]"#, to: url)
        let store = NetworkConfigStore(fileURL: url)
        try store.load()
        #expect(store.networks.map(\.name) == ["B", "A"])
    }

    @Test func invalidFileThrowsAndIsBackedUpBeforeOverwrite() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.file("networks.json")
        try writeString("{ this is not json", to: url)

        let store = NetworkConfigStore(fileURL: url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(store.lastError != nil)

        store.upsert(makeConfig("Libera"))
        #expect(store.lastError == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.url.path(percentEncoded: false))
        #expect(files.contains { $0.hasPrefix("networks.invalid-") })

        let reloaded = NetworkConfigStore(fileURL: url)
        try reloaded.load()
        #expect(reloaded.networks.map(\.name) == ["Libera"])
    }

    @Test func moveMatchesSwiftUISemantics() {
        var items = ["a", "b", "c", "d", "e"]
        items.velaMove(fromOffsets: IndexSet([1, 3]), toOffset: 5)
        #expect(items == ["a", "c", "e", "b", "d"])

        items = ["a", "b", "c", "d", "e"]
        items.velaMove(fromOffsets: IndexSet([3, 4]), toOffset: 1)
        #expect(items == ["a", "d", "e", "b", "c"])

        items = ["a", "b", "c"]
        items.velaMove(fromOffsets: IndexSet(integer: 1), toOffset: 1)
        #expect(items == ["a", "b", "c"])
    }
}
