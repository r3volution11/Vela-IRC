// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaStore

/// One model a provider offers, from its model list (or Vela's own list of
/// recommended ones before that's fetched).
nonisolated public struct AIModelInfo: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    /// "Claude Opus 5.5"; the id when the provider has no nicer name.
    public var name: String
    /// The most it reads in one request (input), when known.
    public var contextTokens: Int?
    /// Vela's pick for this provider: listed first, and marked.
    public var isRecommended: Bool
    /// Takes a reasoning effort (OpenAI), thinking effort (Anthropic) or
    /// thinking level (Gemini), which Vela sets low. Nil: unknown, so it's
    /// left out of requests.
    public var thinkingControl: Bool?

    public init(id: String, name: String? = nil, contextTokens: Int? = nil, isRecommended: Bool = false, thinkingControl: Bool? = nil) {
        self.id = id
        self.name = name?.isEmpty == false ? name! : id
        self.contextTokens = contextTokens
        self.isRecommended = isRecommended
        self.thinkingControl = thinkingControl
    }
}

/// What Vela knows about each kind of provider: names, addresses, where
/// keys come from, the data policy the consent sheet links to, and the
/// recommended models.
nonisolated extension AIProviderKind {
    /// "Anthropic", "Custom server".
    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Google Gemini"
        case .openAICompatible: "Custom server"
        }
    }

    /// The Add menu's title.
    public var addTitle: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic (Claude)"
        case .gemini: "Google Gemini"
        case .openAICompatible: "Custom Server (OpenAI-Compatible)…"
        }
    }

    /// A new entry's name.
    public var defaultName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        case .openAICompatible: "Ollama"
        }
    }

    /// Hosted providers need a key; a custom server may not.
    public var requiresKey: Bool { self != .openAICompatible }

    /// The API's base URL; a custom server's comes from its entry.
    public var defaultBaseURL: URL? {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1")
        case .anthropic: URL(string: "https://api.anthropic.com/v1")
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta")
        case .openAICompatible: nil
        }
    }

    /// Where to get a key.
    public var keyURL: URL? {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .openAICompatible: nil
        }
    }

    /// The provider's terms for what's sent to its API, linked from the
    /// consent sheet and Settings → AI Privacy.
    public var dataPolicyURL: URL? {
        switch self {
        case .openAI: URL(string: "https://openai.com/enterprise-privacy/")
        case .anthropic: URL(string: "https://www.anthropic.com/legal/commercial-terms")
        case .gemini: URL(string: "https://aistudio.google.com/docs/terms")
        case .openAICompatible: nil
        }
    }

    /// The provider's privacy policy, linked from Settings → AI Privacy.
    public var privacyPolicyURL: URL? {
        switch self {
        case .openAI: URL(string: "https://openai.com/policies/privacy-policy/")
        case .anthropic: URL(string: "https://www.anthropic.com/legal/privacy")
        case .gemini: URL(string: "https://policies.google.com/privacy")
        case .openAICompatible: nil
        }
    }

    /// What to do on the page ``keyURL`` opens, in one line.
    public var keySteps: String? {
        switch self {
        case .openAI: "Sign in, choose Create new secret key, and copy the key."
        case .anthropic: "Sign in to the Claude Console, choose Create Key, and copy the key."
        case .gemini: "Sign in with your Google account, choose Create API key, and copy the key."
        case .openAICompatible: nil
        }
    }

    /// Who pays, plainly. No prices: they change.
    public var costNote: String? {
        switch self {
        case .openAI: "Usage is billed by OpenAI to your account, which needs credit."
        case .anthropic: "Usage is billed by Anthropic to your account, which needs credit."
        case .gemini: "Gemini has a free tier, with limits. Beyond it, usage is billed by Google to your account."
        case .openAICompatible: nil
        }
    }

    /// What the provider's models are called, for the setup sheet.
    public var modelsBlurb: String? {
        switch self {
        case .openAI: "GPT models, with a key from the OpenAI Platform."
        case .anthropic: "Claude models, with a key from the Claude Console."
        case .gemini: "Gemini models, with a key from Google AI Studio."
        case .openAICompatible: nil
        }
    }

    /// The start of every key of this kind (`sk-ant-` for Anthropic). The
    /// most specific first, so `sk-ant-` is never taken for OpenAI's `sk-`.
    public var keyPrefix: String? {
        switch self {
        case .openAI: "sk-"
        case .anthropic: "sk-ant-"
        case .gemini: "AIza"
        case .openAICompatible: nil
        }
    }

    /// A key's placeholder in the key field.
    public var keyPlaceholder: String {
        switch self {
        case .openAI: "sk-…"
        case .anthropic: "sk-ant-…"
        case .gemini: "AIza…"
        case .openAICompatible: "Optional"
        }
    }

    /// Vela's picks, recommended first, offered before the provider's own
    /// list is fetched. Contexts are the providers' published input limits.
    public var recommendedModels: [AIModelInfo] {
        switch self {
        case .openAI:
            [
                AIModelInfo(id: "gpt-6.2-sol", name: "GPT-6.2 Sol", contextTokens: 1_000_000, isRecommended: true, thinkingControl: true),
                AIModelInfo(id: "gpt-6.2-astra", name: "GPT-6.2 Astra", contextTokens: 1_000_000, thinkingControl: true),
                AIModelInfo(id: "gpt-6-luna", name: "GPT-6 Luna", contextTokens: 1_000_000, thinkingControl: true),
            ]
        case .anthropic:
            [
                AIModelInfo(id: "claude-opus-5-5", name: "Claude Opus 5.5", contextTokens: 1_000_000, isRecommended: true, thinkingControl: true),
                AIModelInfo(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", contextTokens: 1_000_000, thinkingControl: true),
                AIModelInfo(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", contextTokens: 1_000_000, thinkingControl: true),
            ]
        case .gemini:
            [
                AIModelInfo(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash", contextTokens: 1_048_576, isRecommended: true, thinkingControl: true),
                AIModelInfo(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite", contextTokens: 1_048_576, thinkingControl: true),
            ]
        case .openAICompatible:
            []
        }
    }

    /// The context assumed for a model with no published limit.
    var fallbackContextTokens: Int {
        self == .openAICompatible ? AIProviderEntry.defaultCustomContextTokens : 128_000
    }
}

/// What a pasted key looks like, checked as you paste it, before it's
/// tried: empty, the shape its provider's keys have, another provider's
/// key, or something else (which may still work: Test says for sure).
nonisolated public enum AIKeyShape: Equatable, Sendable {
    case empty
    case expected
    case otherProvider(AIProviderKind)
    case unexpected

    /// Hosted providers' keys, most specific prefix first.
    private static let hosted: [AIProviderKind] = [.anthropic, .gemini, .openAI]

    /// The shortest a real key is: every provider's are far longer.
    static let minimumLength = 20

    public init(key: String, for kind: AIProviderKind) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            self = .empty
            return
        }
        guard kind != .openAICompatible else {
            self = .expected
            return
        }
        let owner = Self.hosted.first { $0.keyPrefix.map(key.hasPrefix) ?? false }
        if let owner, owner != kind {
            self = .otherProvider(owner)
        } else if owner == kind, key.count >= Self.minimumLength, !key.contains(where: \.isWhitespace) {
            self = .expected
        } else {
            self = .unexpected
        }
    }

    /// One line under the key field; nil while it's empty.
    public func message(for kind: AIProviderKind) -> String? {
        switch self {
        case .empty:
            return nil
        case .expected:
            return "Looks like \(kind.article) \(kind.displayName) key."
        case .otherProvider(let owner):
            return "This looks like \(owner.article) \(owner.displayName) key, not \(kind.article) \(kind.displayName) one."
        case .unexpected:
            guard let prefix = kind.keyPrefix else { return nil }
            return "\(kind.displayName) keys start with \(prefix). Check that you copied the whole key."
        }
    }
}

nonisolated extension AIProviderKind {
    /// "an OpenAI key", "an Anthropic key", "a Google Gemini key".
    var article: String { self == .openAI || self == .anthropic ? "an" : "a" }
}

nonisolated extension AIProviderEntry {
    /// Where its API is: the kind's for hosted providers, the entry's for
    /// a custom server (with `/v1` added when the address has no path).
    public var apiBaseURL: URL? {
        guard kind == .openAICompatible else { return kind.defaultBaseURL }
        return Self.normalizedServerURL(baseURL ?? "")
    }

    /// A custom server's address as typed, made usable: a scheme when it
    /// has none (`localhost:11434` → `http://localhost:11434/v1`), `/v1`
    /// when it has no path, no trailing slash. Nil when it isn't an http
    /// or https address with a host.
    public static func normalizedServerURL(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "http://" + value }
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/v1" }
        components.path = path
        return components.url
    }

    /// Where a custom server is, for the consent sheet: this Mac, your
    /// network or the internet.
    public var serverLocation: AIServerLocation {
        guard let host = apiBaseURL?.host()?.lowercased() else { return .internet }
        return AIServerLocation(host: host)
    }
}

/// Where a custom server's address points.
nonisolated public enum AIServerLocation: Sendable, Hashable {
    case thisMac
    case localNetwork
    case internet

    init(host: String) {
        let host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host == "::1" || host.hasPrefix("127.") || host.hasSuffix(".localhost") {
            self = .thisMac
        } else if host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa") || !host.contains(".")
            || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.")
            || (host.contains(":") && (host.hasPrefix("fe80:") || host.hasPrefix("fd"))) || Self.isPrivate172(host) {
            self = .localNetwork
        } else {
            self = .internet
        }
    }

    private static func isPrivate172(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4, parts[0] == "172", let second = Int(parts[1]) else { return false }
        return (16...31).contains(second)
    }
}
