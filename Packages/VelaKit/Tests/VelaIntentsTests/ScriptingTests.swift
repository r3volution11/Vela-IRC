// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Testing
@testable import VelaCore
@testable import VelaIntelligence
@testable import VelaIntents

/// The AppleScript dictionary's objects and commands, without Cocoa
/// scripting: what `tell application "Vela"` gets and does. Serialized:
/// the objects read the running app's automation (`VelaAutomation.shared`).
@MainActor
@Suite("AppleScript", .serialized)
struct ScriptingTests {
    private func fixture() async throws -> AutomationFixture {
        let fixture = try await AutomationFixture.make()
        VelaAutomation.shared = fixture.automation
        return fixture
    }

    /// Runs a command to its end, waiting for one that waits.
    private func run(_ kind: ScriptCommandKind, direct: Any? = nil, _ fixture: AutomationFixture) async throws -> Any? {
        try await run(kind, direct: direct, [:], fixture)
    }

    private func run(_ kind: ScriptCommandKind, direct: Any? = nil, _ arguments: [String: Any], _ fixture: AutomationFixture) async throws -> Any? {
        switch try ScriptCommandHandler.handle(kind, direct: direct, arguments: arguments, automation: fixture.automation) {
        case .done(let value): return value
        case .later(let work): return try await work()
        }
    }

    private func conversation(_ name: String, on session: NetworkSession) throws -> ScriptConversation {
        ScriptConversation(bufferID: try #require(session.buffer(named: name)).id)
    }

    // MARK: Objects

    @Test func networks() async throws {
        let fixture = try await fixture()
        let networks = NSApplication.shared.velaNetworks
        #expect(networks.map(\.name) == ["Libera.Chat", "OFTC", "Ergo Testnet"])
        #expect(networks.map(\.connected) == [true, false, true])
        #expect(networks.first?.nickname == "doug")
        #expect(networks.first?.uniqueID == fixture.libera.id.uuidString)
        #expect(NSApplication.shared.valueInVelaNetworks(withName: "oftc")?.networkID == fixture.oftc.id)
        #expect(NSApplication.shared.valueInVelaNetworks(withUniqueID: fixture.ergo.id.uuidString)?.networkID == fixture.ergo.id)
        #expect(NSApplication.shared.valueInVelaNetworks(withName: "EFnet") == nil)
        #expect(networks.first?.velaConversations.map(\.name).contains("#vela") == true)
    }

    @Test func conversationProperties() async throws {
        let fixture = try await fixture()
        let vela = try conversation("#vela", on: fixture.libera)
        #expect(vela.uniqueID == "\(fixture.libera.id.uuidString)/#vela")
        #expect(vela.name == "#vela")
        #expect(vela.networkName == "Libera.Chat")
        #expect(vela.network.networkID == fixture.libera.id)
        #expect(vela.scriptingKind.uint32Value == ScriptCode.channel)
        #expect(vela.joined)
        #expect(!vela.muted)
        #expect(!vela.topic.isEmpty)
        let marisol = try conversation("marisol", on: fixture.libera)
        #expect(marisol.scriptingKind.uint32Value == ScriptCode.privateConversation)
        #expect(marisol.joined)
        #expect(marisol.topic.isEmpty)
        let debian = try conversation("#debian", on: fixture.oftc)
        #expect(!debian.joined)
        // Counted as Siri counts them.
        let swift = try #require(fixture.libera.buffer(named: "#swift"))
        #expect(try conversation("#swift", on: fixture.libera).unreadCount == fixture.app.unreadTally(for: swift).unread)
        // A conversation that's gone reads as empty rather than failing.
        let gone = ScriptConversation(bufferID: BufferID(networkID: fixture.libera.id, foldedName: "#gone"))
        #expect(gone.networkName == "")
        #expect(gone.unreadCount == 0)
    }

    @Test func applicationElements() async throws {
        let fixture = try await fixture()
        let app = NSApplication.shared
        #expect(app.velaConversations.count == fixture.app.conversationBuffers.count)
        #expect(app.velaCurrentConversation?.name == "#vela")
        let unread = app.velaUnreadConversations.map(\.name)
        #expect(unread == fixture.automation.unreadConversations.map(\.name))
        // By id, and by name with the network you're looking at first.
        let id = "\(fixture.libera.id.uuidString)/#swift"
        #expect(app.valueInVelaConversations(withUniqueID: id)?.name == "#swift")
        #expect(app.valueInVelaConversations(withUniqueID: "\(fixture.libera.id.uuidString)/*server*") == nil)
        #expect(app.valueInVelaConversations(withName: "vela")?.bufferID.networkID == fixture.libera.id)
        #expect(app.valueInVelaConversations(withName: "#nowhere") == nil)
        let libera = try #require(app.velaNetworks.first)
        #expect(libera.valueInVelaConversations(withName: "MARISOL")?.name == "marisol")
        #expect(libera.valueInVelaConversations(withUniqueID: "\(fixture.oftc.id.uuidString)/#debian") == nil)
    }

    /// `scripting version`, which the Alfred workflow and the Raycast
    /// extension read before anything else. It answers without the app's
    /// automation too, as while Vela is starting.
    @Test func scriptingVersion() async throws {
        _ = try await fixture()
        #expect(NSApplication.shared.velaScriptingVersion == 1)
        #expect(VelaAutomation.scriptingVersion == 1)
        let shared = VelaAutomation.shared
        VelaAutomation.shared = nil
        defer { VelaAutomation.shared = shared }
        #expect(NSApplication.shared.velaScriptingVersion == 1)
    }

    @Test func unreadConversationsSkipMutedOnesWithoutMentions() async throws {
        let fixture = try await fixture()
        let swift = try #require(fixture.libera.buffer(named: "#swift"))
        swift.unreadCount = 4
        swift.highlightCount = 0
        #expect(fixture.automation.unreadConversations.contains(swift))
        swift.isMuted = true
        #expect(!fixture.automation.unreadConversations.contains(swift))
        swift.highlightCount = 1
        #expect(fixture.automation.unreadConversations.contains(swift))
    }

    // MARK: Commands

    @Test func show() async throws {
        let fixture = try await fixture()
        let swift = try conversation("#swift", on: fixture.libera)
        _ = try await run(.show, direct: swift, fixture)
        #expect(fixture.app.showRequest?.bufferID == swift.bufferID)
        // A list of one is fine; text is looked up by name.
        _ = try await run(.show, direct: ["marisol"], fixture)
        #expect(fixture.app.showRequest?.bufferID.foldedName == "marisol")
        await #expect(throws: AutomationError.unknownConversation("#nowhere")) {
            _ = try await run(.show, direct: "#nowhere", fixture)
        }
    }

    @Test func sendMessage() async throws {
        let fixture = try await fixture()
        let vela = try conversation("#vela", on: fixture.libera)
        _ = try await run(.sendMessage, direct: "/help is text", [ScriptArgument.target: vela], fixture)
        let last = try #require(fixture.libera.buffer(named: "#vela")?.lines.last)
        #expect(last.isSelf && last.text == "/help is text")
    }

    @Test func sendMessageRules() async throws {
        let fixture = try await fixture()
        let vela = try conversation("#vela", on: fixture.libera)
        let debian = try conversation("#debian", on: fixture.oftc)
        await #expect(throws: AutomationError.emptyMessage) {
            _ = try await run(.sendMessage, direct: "  \n ", [ScriptArgument.target: vela], fixture)
        }
        // More than the message box sends without asking needs saying so.
        let lines = "one\ntwo\nthree\nfour"
        await #expect(throws: AutomationError.tooManyLines(4, limit: 3)) {
            _ = try await run(.sendMessage, direct: lines, [ScriptArgument.target: vela], fixture)
        }
        let before = try #require(fixture.libera.buffer(named: "#vela")).lines.count
        _ = try await run(.sendMessage, direct: lines, [ScriptArgument.target: vela, ScriptArgument.allowMultipleLines: NSNumber(value: true)], fixture)
        #expect(try #require(fixture.libera.buffer(named: "#vela")).lines.count > before)
        // Three lines go without asking.
        _ = try await run(.sendMessage, direct: "a\n\nb\nc", [ScriptArgument.target: vela], fixture)
        // A wall of text is refused outright.
        let wall = String(repeating: "word ", count: 6_000)
        await #expect(throws: AutomationError.self) {
            _ = try await run(.sendMessage, direct: wall, [ScriptArgument.target: vela, ScriptArgument.allowMultipleLines: true], fixture)
        }
        // Only to channels you're in.
        fixture.oftc.connectionState = .connected
        await #expect(throws: AutomationError.notJoined(channel: "#debian", network: "OFTC")) {
            _ = try await run(.sendMessage, direct: "hi", [ScriptArgument.target: debian], fixture)
        }
    }

    @Test func sendMessageToAPrivateConversation() async throws {
        let fixture = try await fixture()
        let marisol = try conversation("marisol", on: fixture.libera)
        _ = try await run(.sendMessage, direct: "on my way", [ScriptArgument.target: marisol], fixture)
        #expect(fixture.libera.buffer(named: "marisol")?.lines.last?.text == "on my way")
    }

    @Test func draftMessage() async throws {
        let fixture = try await fixture()
        let swift = try conversation("#swift", on: fixture.libera)
        _ = try await run(.draftMessage, direct: "almost\u{03}4 done", [ScriptArgument.target: swift], fixture)
        #expect(fixture.app.showRequest?.bufferID == swift.bufferID)
        #expect(fixture.app.showRequest?.draft == "almost4 done")
        #expect(fixture.app.showRequest?.appendsDraft == true)
        // Nothing sent.
        #expect(fixture.libera.buffer(named: "#swift")?.lines.last?.text != "almost4 done")
    }

    @Test func join() async throws {
        let fixture = try await fixture()
        let result = try await run(.join, direct: "swift-dev", [ScriptArgument.network: ScriptNetwork(networkID: fixture.libera.id)], fixture)
        let joined = try #require(result as? ScriptConversation)
        #expect(joined.name == "#swift-dev")
        #expect(joined.joined)
        // Without a network: the one you're looking at.
        let other = try #require(try await run(.join, direct: "#more", fixture) as? ScriptConversation)
        #expect(other.bufferID.networkID == fixture.libera.id)
        // By name, as text.
        let ergo = try #require(try await run(.join, direct: "#test", [ScriptArgument.network: "ergo testnet"], fixture) as? ScriptConversation)
        #expect(ergo.bufferID.networkID == fixture.ergo.id)
        await #expect(throws: AutomationError.invalidChannelName("two words")) {
            _ = try await run(.join, direct: "two words", fixture)
        }
    }

    @Test func catchUp() async throws {
        let fixture = try await fixture()
        let swift = try conversation("#swift", on: fixture.libera)
        _ = try await run(.catchUp, direct: swift, fixture)
        #expect(fixture.services.catchUp.card(for: swift.bufferID) != nil)
        fixture.app.settings[.intelligenceCatchUp] = false
        await #expect(throws: AutomationError.turnedOff("Catch me up")) {
            _ = try await run(.catchUp, direct: swift, fixture)
        }
    }

    @Test func openRecap() async throws {
        let fixture = try await fixture()
        let vela = try conversation("#vela", on: fixture.libera)
        let today = NSNumber(value: ScriptCode.of("VStd"))
        _ = try await run(.openRecap, direct: vela, [ScriptArgument.span: today], fixture)
        #expect(fixture.services.recaps.latest?.scope == RecapScope(place: .buffer(vela.bufferID), span: .today, output: .summary))
        _ = try await run(.openRecap, direct: ScriptNetwork(networkID: fixture.oftc.id), [ScriptArgument.person: "bea"], fixture)
        #expect(fixture.services.recaps.latest?.scope == RecapScope(place: .network(fixture.oftc.id), person: "bea", output: .summary))
        _ = try await run(.openRecap, fixture)
        #expect(fixture.services.recaps.latest?.scope.place == .everywhere)
    }

    @Test func markRead() async throws {
        let fixture = try await fixture()
        let swift = try #require(fixture.libera.buffer(named: "#swift"))
        swift.unreadCount = 5
        _ = try await run(.markRead, direct: ScriptConversation(bufferID: swift.id), fixture)
        #expect(swift.unreadCount == 0)
        swift.unreadCount = 2
        let count = try await run(.markAllRead, fixture) as? Int
        #expect((count ?? 0) >= 1)
        #expect(swift.unreadCount == 0)
    }

    @Test func search() async throws {
        let fixture = try await fixture()
        _ = try await run(.search, direct: "aurora", fixture)
        _ = try await run(.search, direct: "aurora", [ScriptArgument.scope: ScriptNetwork(networkID: fixture.oftc.id)], fixture)
        let vela = try conversation("#vela", on: fixture.libera)
        _ = try await run(.search, direct: "aurora", [ScriptArgument.scope: vela], fixture)
        #expect(fixture.presenter.calls == [
            .search("aurora", nil, nil),
            .search("aurora", nil, fixture.oftc.id),
            .search("aurora", vela.bufferID, nil),
        ])
    }

    @Test func awayAndBack() async throws {
        let fixture = try await fixture()
        let away = try #require(try await run(.setAway, direct: "lunch", fixture) as? [String])
        #expect(away == ["Libera.Chat", "Ergo Testnet"])
        let back = try #require(try await run(.setBack, fixture) as? [String])
        #expect(back == ["Libera.Chat", "Ergo Testnet"])
    }

    @Test func everyCommandIsHandled() async throws {
        // A kind with no case in the handler wouldn't compile; this checks
        // the list the sdef is tested against is complete.
        #expect(ScriptCommandKind.allCases.count == 11)
    }

    // MARK: Errors

    @Test func errorNumbersNeverChange() {
        #expect(AutomationError.unknownConversation("x").scriptErrorNumber == -1728)
        #expect(AutomationError.unknownNetwork("x").scriptErrorNumber == -1728)
        #expect(AutomationError.ambiguousConversation("x").scriptErrorNumber == 1001)
        #expect(AutomationError.needsNetwork.scriptErrorNumber == 1001)
        #expect(AutomationError.notConnected(network: "x").scriptErrorNumber == 1002)
        #expect(AutomationError.notJoined(channel: "x", network: "y").scriptErrorNumber == 1003)
        #expect(AutomationError.emptyMessage.scriptErrorNumber == 1004)
        #expect(AutomationError.tooManyLines(4, limit: 3).scriptErrorNumber == 1005)
        #expect(AutomationError.serverBuffer(network: "x").scriptErrorNumber == 1006)
        #expect(AutomationError.turnedOff("Recap").scriptErrorNumber == 1007)
        #expect(AutomationError.intelligenceUnavailable("x").scriptErrorNumber == 1008)
        #expect(AutomationError.invalidChannelName("x").scriptErrorNumber == 1009)
        #expect(AutomationError.notReady.scriptErrorNumber == 1010)
    }
}
