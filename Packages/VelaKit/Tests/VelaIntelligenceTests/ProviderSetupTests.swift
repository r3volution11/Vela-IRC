// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Network
import Synchronization
import Testing
import VelaFoundation
import VelaStore
@testable import VelaIntelligence

/// Setting up a provider: a pasted key's shape, Test Connection (which
/// saves nothing), adding it with its key, OK and default model, and
/// finding Ollama or LM Studio on this Mac and connecting it.
@Suite("Setting up a provider")
@MainActor
struct ProviderSetupTests {
    // MARK: Key shapes

    @Test func aKeysShapeIsCheckedAsItsPasted() {
        #expect(AIKeyShape(key: "", for: .openAI) == .empty)
        #expect(AIKeyShape(key: "  \n", for: .openAI) == .empty)
        #expect(AIKeyShape(key: "sk-proj-abcdefghijklmnopqrstuvwxyz0123", for: .openAI) == .expected)
        #expect(AIKeyShape(key: " sk-proj-abcdefghijklmnopqrstuvwxyz0123\n", for: .openAI) == .expected)
        #expect(AIKeyShape(key: "sk-ant-api03-abcdefghijklmnopqrstuvwxyz", for: .anthropic) == .expected)
        #expect(AIKeyShape(key: "AIzaSyAbcdefghijklmnopqrstuvwxyz0123456", for: .gemini) == .expected)
        // Anthropic's keys start with sk- too, but aren't OpenAI's.
        #expect(AIKeyShape(key: "sk-ant-api03-abcdefghijklmnopqrstuvwxyz", for: .openAI) == .otherProvider(.anthropic))
        #expect(AIKeyShape(key: "sk-proj-abcdefghijklmnopqrstuvwxyz0123", for: .anthropic) == .otherProvider(.openAI))
        #expect(AIKeyShape(key: "AIzaSyAbcdefghijklmnopqrstuvwxyz0123456", for: .openAI) == .otherProvider(.gemini))
        // Something else: may still work, so it can be tested.
        #expect(AIKeyShape(key: "my-key-from-somewhere-else", for: .gemini) == .unexpected)
        #expect(AIKeyShape(key: "sk-short", for: .openAI) == .unexpected)
        #expect(AIKeyShape(key: "sk-proj-abcdefghij klmnopqrstuvwxyz", for: .openAI) == .unexpected)
        // A server's key is whatever it asks for.
        #expect(AIKeyShape(key: "anything", for: .openAICompatible) == .expected)

        #expect(AIKeyShape.expected.message(for: .anthropic) == "Looks like an Anthropic key.")
        #expect(AIKeyShape.expected.message(for: .gemini) == "Looks like a Google Gemini key.")
        #expect(AIKeyShape.otherProvider(.anthropic).message(for: .openAI) == "This looks like an Anthropic key, not an OpenAI one.")
        #expect(AIKeyShape.unexpected.message(for: .openAI) == "OpenAI keys start with sk-. Check that you copied the whole key.")
        #expect(AIKeyShape.empty.message(for: .openAI) == nil)
    }

    @Test func everyHostedProviderSaysWhereKeysComeFromAndWhoPays() {
        for kind in [AIProviderKind.openAI, .anthropic, .gemini] {
            #expect(kind.keyURL?.scheme == "https")
            #expect(kind.keySteps != nil)
            #expect(kind.costNote?.contains("billed") == true)
            #expect(kind.privacyPolicyURL?.scheme == "https")
            #expect(kind.dataPolicyURL?.scheme == "https")
            #expect(kind.keyPrefix != nil)
        }
        #expect(AIProviderKind.openAI.keyURL?.absoluteString == "https://platform.openai.com/api-keys")
        #expect(AIProviderKind.anthropic.keyURL?.absoluteString == "https://platform.claude.com/settings/keys")
        #expect(AIProviderKind.gemini.keyURL?.absoluteString == "https://aistudio.google.com/apikey")
        #expect(AIProviderKind.gemini.costNote?.contains("free tier") == true)
        #expect(AIProviderKind.openAICompatible.costNote == nil)
    }

    // MARK: Test Connection

    @Test func testingAKeySavesNothing() async throws {
        let harness = RoutingHarness()
        let result = await harness.models.checkKey("  sk-proj-test-key-0123456789  ", for: .anthropic)
        let models = try result.get()
        #expect(models.map(\.id) == ["m1"])
        // Only the model list was asked for, with the key, from Anthropic.
        let requests = harness.requests(.anthropic)
        #expect(requests.count == 1)
        #expect(requests.first?.method == "GET")
        #expect(requests.first?.header("x-api-key") == "sk-proj-test-key-0123456789")
        #expect(harness.servers.filter { $0.key != .anthropic }.allSatisfy { $0.value.requests.isEmpty })
        // Nothing kept.
        #expect(harness.models.providers.isEmpty)
        #expect(!harness.keys.hasKey(for: "anthropic"))
        #expect(harness.models.catalog.lists.isEmpty)
    }

    @Test func aTurnedDownKeySaysSo() async {
        let harness = RoutingHarness(failing: [.anthropic])
        let result = await harness.models.checkKey("sk-ant-api03-wrong-wrong-wrong", for: .anthropic)
        guard case .failure(let failure) = result else {
            Issue.record("expected a failure")
            return
        }
        #expect(failure.reason == .badKey)
        #expect(failure.providerName == "Anthropic")
        #expect(harness.models.providers.isEmpty)
    }

    @Test func aBlankKeyIsntSent() async {
        let harness = RoutingHarness()
        let result = await harness.models.checkKey("  ", for: .gemini)
        #expect((try? result.get()) == nil)
        #expect(harness.requests(.gemini).isEmpty)
    }

    // MARK: Adding

    @Test func addingSavesTheKeyOnlyInTheKeychain() throws {
        let harness = RoutingHarness()
        let list = [AIModelInfo(id: "claude-opus-5-5", name: "Claude Opus 5.5", isRecommended: true), AIModelInfo(id: "claude-haiku-5-5")]
        let entry = try #require(try harness.models.addProvider(
            .anthropic, key: "sk-ant-api03-secret-secret-secret", models: list, consented: true, defaultModel: "claude-opus-5-5"
        ))
        #expect(entry.id == "anthropic")
        #expect(entry.consented)
        #expect(harness.keys.key(for: "anthropic") == "sk-ant-api03-secret-secret-secret")
        #expect(harness.settings[.intelligenceModel] == "anthropic/claude-opus-5-5")
        #expect(harness.models.catalog.models(for: entry).map(\.id) == ["claude-opus-5-5", "claude-haiku-5-5"])
        // settings.json never has the key.
        harness.settings.flush()
        let text = try String(contentsOf: harness.settings.fileURL, encoding: .utf8)
        #expect(text.contains("\"anthropic\""))
        #expect(!text.contains("secret-secret"))
        // Each hosted provider once.
        #expect(try harness.models.addProvider(.anthropic, key: "sk-ant-api03-other", models: [], consented: true) == nil)
    }

    @Test func addingWithoutADefaultLeavesItAlone() throws {
        let harness = RoutingHarness()
        try harness.models.addProvider(.gemini, key: "AIzaSyAbcdefghijklmnopqrstuvwxyz0123456", models: [], consented: true)
        #expect(harness.settings[.intelligenceModel] == "apple")
        #expect(harness.models.providers.first?.consented == true)
    }

    // MARK: Withdrawing

    @Test func withdrawingStopsAProviderUntilItsAllowedAgain() async throws {
        let harness = RoutingHarness()
        let entry = harness.add(.openAI)
        harness.settings[.intelligenceModel] = "openai/gpt-6.2-sol"
        harness.models.withdrawConsent(entry.id)
        guard case .unavailable(let failure) = harness.models.route(for: .catchUp, override: nil) else {
            Issue.record("expected to ask first")
            return
        }
        #expect(failure.reason == .needsConsent)
        harness.models.grantConsent(entry.id)
        guard case .provider = harness.models.route(for: .catchUp, override: nil) else {
            Issue.record("expected the provider")
            return
        }
    }

    // MARK: Models on this Mac

    @Test func connectingAServerOnThisMac() throws {
        let harness = RoutingHarness()
        let models = [AIModelInfo(id: "llama3.2"), AIModelInfo(id: "qwen3:8b")]
        let entry = try #require(harness.models.connect(.ollama, models: models))
        #expect(entry.kind == .openAICompatible)
        #expect(entry.name == "Ollama")
        #expect(entry.baseURL == "http://127.0.0.1:11434/v1")
        #expect(!entry.consented)
        #expect(entry.serverLocation == .thisMac)
        #expect(harness.models.catalog.models(for: entry).map(\.id) == ["llama3.2", "qwen3:8b"])
        #expect(harness.models.provider(for: .ollama)?.id == entry.id)
        #expect(harness.models.provider(for: .lmStudio) == nil)
        // Connecting again finds the same one.
        #expect(harness.models.connect(.ollama, models: [])?.id == entry.id)
        #expect(harness.models.providers.count == 1)

        harness.models.finishSetup(entry, consented: true, defaultModel: "qwen3:8b")
        #expect(harness.models.providers.first?.consented == true)
        #expect(harness.settings[.intelligenceModel] == "ollama/qwen3:8b")
    }

    @Test func aServerAddedByHandCountsAsConnected() {
        let byHand = AIProviderEntry(id: "studio", kind: .openAICompatible, name: "My Studio", baseURL: "localhost:1234")
        #expect(LocalModelServer.lmStudio.isConnected(as: byHand))
        #expect(!LocalModelServer.ollama.isConnected(as: byHand))
        let elsewhere = AIProviderEntry(id: "lan", kind: .openAICompatible, name: "LAN", baseURL: "http://studio.local:1234/v1")
        #expect(!LocalModelServer.lmStudio.isConnected(as: elsewhere))
        let ipv6 = AIProviderEntry(id: "v6", kind: .openAICompatible, name: "v6", baseURL: "http://[::1]:11434/v1")
        #expect(LocalModelServer.ollama.isConnected(as: ipv6))
        #expect(!LocalModelServer.ollama.isConnected(as: AIProviderEntry(id: "openai", kind: .openAI, name: "OpenAI")))
    }

    @Test func serversAreKnownByTheirAppsAndPorts() {
        #expect(LocalModelServer.ollama.baseURL.absoluteString == "http://127.0.0.1:11434/v1")
        #expect(LocalModelServer.lmStudio.baseURL.absoluteString == "http://127.0.0.1:1234/v1")
        #expect(LocalModelServer.ollama.bundleIdentifier == "com.electron.ollama")
        #expect(LocalModelServer.lmStudio.bundleIdentifier == "ai.elementlabs.lmstudio")
        #expect(LocalModelServer.ollama.websiteURL.absoluteString == "https://ollama.com")
        #expect(LocalModelServer.lmStudio.websiteURL.absoluteString == "https://lmstudio.ai")
    }

    // MARK: Looking for servers

    @Test func findingServersWithStubs() async {
        let ollama = StubServer([.json(200, #"{"object":"list","data":[{"id":"llama3.2:latest"},{"id":"nomic-embed-text:latest"},{"id":"qwen3:8b"}]}"#)])
        let lmStudio = StubServer([.fail(.cannotConnectToHost)])
        let detector = LocalModelDetector.stubbed(
            configuration: StubServer.configuration,
            baseURLs: [.ollama: ollama.baseURL, .lmStudio: lmStudio.baseURL]
        )
        let found = await detector.detect()
        #expect(found[.ollama] == .running(models: [AIModelInfo(id: "llama3.2:latest"), AIModelInfo(id: "qwen3:8b")]))
        #expect(found[.lmStudio] == .notRunning)
        #expect(ollama.requests.map { $0.url.path() } == ["/v1/models"])
        #expect(ollama.requests.first?.method == "GET")
        #expect(ollama.requests.first?.body.isEmpty == true)
    }

    @Test(arguments: [
        (StubServer.Reply.json(200, #"{"object":"list","data":null}"#), LocalServerState.running(models: [])),
        (StubServer.Reply.json(200, #"{"object":"list","data":[]}"#), LocalServerState.running(models: [])),
        (StubServer.Reply.json(404, #"{"error":"not found"}"#), LocalServerState.notRunning),
        (StubServer.Reply(status: 200, headers: ["Content-Type": "text/html"], chunks: [Data("<html>".utf8)]), LocalServerState.notRunning),
        (StubServer.Reply.fail(.timedOut), LocalServerState.notRunning),
    ])
    func whatCountsAsRunning(_ reply: StubServer.Reply, _ expected: LocalServerState) async {
        let server = StubServer([reply])
        let detector = LocalModelDetector.stubbed(configuration: StubServer.configuration, baseURLs: [.ollama: server.baseURL, .lmStudio: server.baseURL])
        #expect(await detector.probe(.ollama) == expected)
    }

    @Test func demoModeNeverLooks() async {
        let models = AIModels.appleOnly(availability: .fixed(.available))
        #expect(await models.detectLocalServers().isEmpty)
    }

    /// The real network code against a real server on the loopback
    /// address (what Ollama and LM Studio listen on), and a closed port,
    /// which is answered at once.
    @Test func findingAServerOnLoopbackForReal() async throws {
        let server = try ModelListServer(body: #"{"object":"list","data":[{"id":"gemma3:4b","object":"model"}]}"#)
        let port = try await server.start()
        defer { server.stop() }
        let closed = try await ModelListServer.closedPort()
        let detector = LocalModelDetector(
            session: AIHTTPClient.makeSession(requestTimeout: LocalModelDetector.timeout, resourceTimeout: LocalModelDetector.timeout * 2),
            baseURLs: [
                .ollama: URL(string: "http://127.0.0.1:\(port)/v1")!,
                .lmStudio: URL(string: "http://127.0.0.1:\(closed)/v1")!,
            ]
        )
        let started = ContinuousClock.now
        let found = await detector.detect()
        #expect(found[.ollama] == .running(models: [AIModelInfo(id: "gemma3:4b")]))
        #expect(found[.lmStudio] == .notRunning)
        #expect(ContinuousClock.now - started < .seconds(3))
        #expect(server.requestLine.hasPrefix("GET /v1/models HTTP/1.1"))
    }

    /// If Ollama or LM Studio happens to be running on this Mac, it's found
    /// at its usual address. Nothing to check when neither is.
    @Test func theRealServersIfTheyreRunning() async {
        let found = await LocalModelDetector.live().detect()
        #expect(found.count == LocalModelServer.allCases.count)
        for (server, state) in found where state.isRunning {
            print("\(server.name) is running on this Mac, with \(state.models.count) models")
        }
    }
}

/// A tiny HTTP server on 127.0.0.1 that answers every request with one
/// JSON body, for the loopback test.
private final class ModelListServer: Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "test.model-list-server")
    private let body: String
    private let received = Mutex("")

    init(body: String) throws {
        self.body = body
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// The first line of the last request.
    var requestLine: String { received.withLock { $0 } }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                let text = String(decoding: data ?? Data(), as: UTF8.self)
                self.received.withLock { $0 = text.components(separatedBy: "\r\n").first ?? "" }
                let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(self.body.utf8.count)\r\nConnection: close\r\n\r\n\(self.body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        return try await Self.ready(listener, queue: queue)
    }

    func stop() {
        listener.cancel()
    }

    /// A port nothing listens on: bound, then closed.
    static func closedPort() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { $0.cancel() }
        let port = try await ready(listener, queue: DispatchQueue(label: "test.closed-port"))
        listener.cancel()
        return port
    }

    private static func ready(_ listener: NWListener, queue: DispatchQueue) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if !resumed.withLock({ let was = $0; $0 = true; return was }) {
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    }
                case .failed(let error):
                    if !resumed.withLock({ let was = $0; $0 = true; return was }) {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }
}
