// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaStore

/// Makes each provider's API with its key. Two sessions: hosted providers
/// answer within 90 seconds between bytes; a custom server gets 5
/// minutes, since a local model can take that long to load on a slow Mac
/// before it writes anything. ``AIModels`` makes the factory the first
/// time a provider is used. Tests make one with a stub `URLProtocol`, a
/// stub address per provider, and no waiting between retries.
nonisolated public final class AIProviderFactory: Sendable {
    let hostedClient: AIHTTPClient
    let customClient: AIHTTPClient
    /// Hosted providers' addresses, for tests (each stubbed server has
    /// its own); the real ones otherwise.
    let hostedBaseURLs: [AIProviderKind: URL]

    init(hostedClient: AIHTTPClient, customClient: AIHTTPClient, hostedBaseURLs: [AIProviderKind: URL] = [:]) {
        self.hostedClient = hostedClient
        self.customClient = customClient
        self.hostedBaseURLs = hostedBaseURLs
    }

    /// The real network.
    public static func live() -> AIProviderFactory {
        AIProviderFactory(
            hostedClient: AIHTTPClient(session: AIHTTPClient.makeSession(requestTimeout: 90, resourceTimeout: 600)),
            customClient: AIHTTPClient(session: AIHTTPClient.makeSession(requestTimeout: 300, resourceTimeout: 1_200))
        )
    }

    /// Requests through `configuration` (its `protocolClasses`), hosted
    /// providers at `baseURLs`, retries recorded by `sleep` instead of
    /// waited for.
    static func stubbed(
        configuration: URLSessionConfiguration,
        baseURLs: [AIProviderKind: URL] = [:],
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) -> AIProviderFactory {
        var client = AIHTTPClient(session: AIHTTPClient.makeSession(requestTimeout: 10, resourceTimeout: 30, configuration: configuration))
        client.sleep = sleep
        return AIProviderFactory(hostedClient: client, customClient: client, hostedBaseURLs: baseURLs)
    }

    /// The API for `entry`, with `key`. Nil for a custom server whose
    /// address isn't usable.
    func api(for entry: AIProviderEntry, key: String?) -> (any AIProviderAPI)? {
        let identity = AIProviderIdentity(id: entry.id, name: entry.name, isCustomServer: entry.kind == .openAICompatible)
        if entry.kind == .openAICompatible {
            guard let url = entry.apiBaseURL else { return nil }
            return OpenAICompatibleAPI(identity: identity, client: customClient, key: key, baseURL: url)
        }
        guard let base = hostedBaseURLs[entry.kind] ?? entry.kind.defaultBaseURL else { return nil }
        switch entry.kind {
        case .openAI:
            return OpenAIAPI(identity: identity, client: hostedClient, key: key ?? "", baseURL: base)
        case .anthropic:
            return AnthropicAPI(identity: identity, client: hostedClient, key: key ?? "", baseURL: base)
        case .gemini:
            return GeminiAPI(identity: identity, client: hostedClient, key: key ?? "", baseURL: base)
        case .openAICompatible:
            return nil
        }
    }
}
