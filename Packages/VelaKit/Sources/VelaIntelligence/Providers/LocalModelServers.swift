// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaStore

/// An app that runs models on this Mac, which Settings → AI Providers
/// looks for so it can be connected in one click: no key, no account.
nonisolated public enum LocalModelServer: String, CaseIterable, Sendable, Identifiable, Hashable {
    case ollama
    case lmStudio

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        }
    }

    /// The port its server listens on unless you've changed it.
    public var port: Int {
        switch self {
        case .ollama: 11434
        case .lmStudio: 1234
        }
    }

    /// Its OpenAI-compatible API on this Mac: what's looked for, and the
    /// address a provider connected to it gets. The loopback address, so
    /// nothing leaves the Mac and macOS doesn't ask about the local network.
    public var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)/v1")!
    }

    /// The app's bundle identifier, for whether it's installed and Open.
    public var bundleIdentifier: String {
        switch self {
        case .ollama: "com.electron.ollama"
        case .lmStudio: "ai.elementlabs.lmstudio"
        }
    }

    /// Where to get it.
    public var websiteURL: URL {
        switch self {
        case .ollama: URL(string: "https://ollama.com")!
        case .lmStudio: URL(string: "https://lmstudio.ai")!
        }
    }

    /// What to do when it's installed but its server isn't answering.
    public var startHint: String {
        switch self {
        case .ollama: "Open it and its server starts too."
        case .lmStudio: "Open it and turn on its server in the Developer tab."
        }
    }

    /// Whether `entry` is a provider for this server on this Mac: a custom
    /// server at a loopback address (`localhost`, `127.0.0.1`, `::1`) on
    /// its port, whatever its name.
    public func isConnected(as entry: AIProviderEntry) -> Bool {
        guard entry.kind == .openAICompatible, let url = entry.apiBaseURL, let host = url.host()?.lowercased() else { return false }
        let loopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) || host.hasPrefix("127.")
        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        return loopback && port == self.port
    }
}

/// What looking for a server found.
nonisolated public enum LocalServerState: Equatable, Sendable {
    /// It answered with its model list (embedding models left out).
    case running(models: [AIModelInfo])
    /// Nothing answered, or what answered isn't a model server.
    case notRunning

    public var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    public var models: [AIModelInfo] {
        if case .running(let models) = self { models } else { [] }
    }
}

/// Looks for Ollama and LM Studio on this Mac: one request each to its
/// model list (`GET /v1/models` on the loopback address), at the same
/// time, giving up after a second. Only when asked (the pane showing,
/// Look Again, Vela becoming active), never on a timer, and never in demo
/// mode. Nothing is sent but the request for the list.
nonisolated public struct LocalModelDetector: Sendable {
    let session: URLSession
    /// Where each server is looked for; tests point them at stub servers.
    let baseURLs: [LocalModelServer: URL]

    /// The longest Vela waits for a server to answer.
    public static let timeout: TimeInterval = 1

    init(session: URLSession, baseURLs: [LocalModelServer: URL] = [:]) {
        self.session = session
        self.baseURLs = baseURLs
    }

    /// The real servers on this Mac.
    public static func live() -> LocalModelDetector {
        LocalModelDetector(session: AIHTTPClient.makeSession(requestTimeout: timeout, resourceTimeout: timeout * 2))
    }

    /// Requests through `configuration` (a stub `URLProtocol`), each server
    /// at `baseURLs`.
    static func stubbed(configuration: URLSessionConfiguration, baseURLs: [LocalModelServer: URL]) -> LocalModelDetector {
        LocalModelDetector(session: AIHTTPClient.makeSession(requestTimeout: timeout, resourceTimeout: timeout * 2, configuration: configuration), baseURLs: baseURLs)
    }

    /// Every server's state, looked for at the same time, off the main actor.
    @concurrent
    public func detect() async -> [LocalModelServer: LocalServerState] {
        await withTaskGroup(of: (LocalModelServer, LocalServerState).self) { group in
            for server in LocalModelServer.allCases {
                group.addTask { (server, await probe(server)) }
            }
            var states: [LocalModelServer: LocalServerState] = [:]
            for await (server, state) in group { states[server] = state }
            return states
        }
    }

    /// One server: running when its model list answers with JSON.
    func probe(_ server: LocalModelServer) async -> LocalServerState {
        let base = baseURLs[server] ?? server.baseURL
        var request = URLRequest(url: base.appending(path: "models"), timeoutInterval: Self.timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let page = try? JSONDecoder().decode(JSONValue.self, from: data), page.objectValue != nil
        else { return .notRunning }
        return .running(models: OpenAICompatibleAPI.models(in: page))
    }
}
