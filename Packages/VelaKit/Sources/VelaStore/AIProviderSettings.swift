// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

// Your own AI providers (Settings → AI Providers), as settings.json
// stores them: what each provider is, its name, a custom server's address,
// whether it's on, and whether you've agreed to send it messages. Never a
// key: keys live only in the Keychain (`Keychain.aiProviderKeyAccount`).

/// A kind of provider you can add.
public enum AIProviderKind: String, Codable, Sendable, CaseIterable {
    case openAI = "openai"
    case anthropic
    case gemini
    /// A server that speaks OpenAI's Chat Completions API, such as Ollama or
    /// LM Studio on this Mac or your network.
    case openAICompatible

    /// Only custom servers can be added more than once.
    public var allowsSeveral: Bool { self == .openAICompatible }
}

/// One provider in `intelligence.providers`.
nonisolated public struct AIProviderEntry: Codable, Sendable, Hashable, Identifiable {
    /// Stable, and part of model choices (`"<id>/<model>"`) and the
    /// Keychain account: `"openai"`, `"anthropic"`, `"gemini"`, or a slug
    /// of a custom server's name (`"ollama"`). Never `"apple"`, never with
    /// a `/`.
    public var id: String
    public var kind: AIProviderKind
    /// As shown in menus and on the Catch me up card.
    public var name: String
    /// A custom server's base URL, such as `http://localhost:11434/v1`.
    public var baseURL: String?
    /// Off keeps the provider (and its key) but offers none of its models.
    public var enabled: Bool
    /// You agreed to send it messages (the consent sheet). Withdrawn in
    /// Settings → AI Privacy.
    public var consented: Bool
    /// The context window a custom server loads its models with, in
    /// tokens; nil uses ``defaultCustomContextTokens``.
    public var contextTokens: Int?

    /// What a custom server is assumed to read when you haven't said:
    /// small, since local servers often load models with a short context
    /// and quietly drop what doesn't fit.
    public static let defaultCustomContextTokens = 4_096

    public init(
        id: String,
        kind: AIProviderKind,
        name: String,
        baseURL: String? = nil,
        enabled: Bool = true,
        consented: Bool = false,
        contextTokens: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURL = baseURL
        self.enabled = enabled
        self.consented = consented
        self.contextTokens = contextTokens
    }

    /// An id for a new provider of `kind` named `name`, unique among
    /// `existing`: the kind for the hosted ones, a slug of the name for
    /// custom servers (`"LM Studio"` → `"lm-studio"`, then `"lm-studio-2"`).
    public static func newID(kind: AIProviderKind, name: String, existing: [AIProviderEntry]) -> String {
        let taken = Set(existing.map(\.id)).union([AIModelChoice.appleProviderID])
        let base: String
        if kind.allowsSeveral {
            let slug = name.lowercased()
                .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
                .joined()
                .split(separator: "-", omittingEmptySubsequences: true)
                .joined(separator: "-")
            base = slug.isEmpty ? "custom" : String(slug.prefix(32))
        } else {
            base = kind.rawValue
        }
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base)-\(number)") { number += 1 }
        return "\(base)-\(number)"
    }
}

extension AIProviderEntry: SettingValueConvertible {
    /// Lenient: a missing name falls back to the id, a missing `enabled`
    /// to on, `consent` to not given. An entry without a usable id or kind
    /// is dropped.
    public init?(settingJSON: JSONValue) {
        guard let object = settingJSON.objectValue,
              let id = object["id"]?.stringValue?.trimmingCharacters(in: .whitespaces),
              !id.isEmpty, !id.contains("/"), id != AIModelChoice.appleProviderID,
              let kind = object["kind"]?.stringValue.flatMap(AIProviderKind.init(rawValue:))
        else { return nil }
        let name = object["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        let baseURL = object["baseURL"]?.stringValue?.trimmingCharacters(in: .whitespaces)
        self.init(
            id: id,
            kind: kind,
            name: name.isEmpty ? id : name,
            baseURL: baseURL?.isEmpty == false ? baseURL : nil,
            enabled: object["enabled"]?.boolValue ?? true,
            consented: object["consent"]?.boolValue ?? false,
            contextTokens: object["contextTokens"]?.intValue.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    public var settingJSON: JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "kind": .string(kind.rawValue),
            "name": .string(name),
            "enabled": .bool(enabled),
            "consent": .bool(consented),
        ]
        if let baseURL { object["baseURL"] = .string(baseURL) }
        if let contextTokens { object["contextTokens"] = .number(Double(contextTokens)) }
        return .object(object)
    }

    public static var settingSchema: JSONValue {
        .object([
            "type": "object",
            "required": .array(["id", "kind"]),
            "properties": .object([
                "id": .object(["type": "string"]),
                "kind": .object(["type": "string", "enum": .array(AIProviderKind.allCases.map { .string($0.rawValue) })]),
                "name": .object(["type": "string"]),
                "baseURL": .object(["type": "string"]),
                "enabled": .object(["type": "boolean"]),
                "consent": .object(["type": "boolean"]),
                "contextTokens": .object(["type": "integer"]),
            ]),
        ])
    }
}

/// Apple's models, in the order menus list them: chosen for you, always on
/// this Mac, or always with Private Cloud Compute.
public enum AppleModel: String, Codable, Sendable, CaseIterable {
    /// On this Mac; a long stretch with Private Cloud Compute while
    /// `intelligence.privateCloudCompute` is on (macOS 27+).
    case automatic
    /// Always on this Mac.
    case onDevice = "on-device"
    /// Always with Private Cloud Compute, falling back to this Mac when it
    /// isn't available (development builds, with the setting on).
    case privateCloudCompute = "private-cloud-compute"
}

/// Which model writes a summary, as settings.json says it: `"apple"`
/// (Automatic), `"apple/on-device"`, `"apple/private-cloud-compute"`, or
/// `"<provider id>/<model id>"` such as `"anthropic/claude-opus-5-5"`. A
/// model id may itself contain slashes (`"ollama/library/llama3"`): the
/// provider is everything before the first one.
nonisolated public enum AIModelChoice: Hashable, Sendable {
    case apple(AppleModel)
    case provider(providerID: String, modelID: String)

    /// Reserved: no provider can have this id.
    public static let appleProviderID = "apple"

    public static let automatic = AIModelChoice.apple(.automatic)

    /// The choice in a settings value; nil for `""` ("same as default")
    /// and anything that isn't one.
    public init?(settingValue: String) {
        let value = settingValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value == Self.appleProviderID {
            self = .apple(.automatic)
            return
        }
        guard let slash = value.firstIndex(of: "/") else { return nil }
        let provider = String(value[..<slash])
        let model = String(value[value.index(after: slash)...])
        guard !provider.isEmpty, !model.isEmpty else { return nil }
        if provider == Self.appleProviderID {
            guard let apple = AppleModel(rawValue: model), apple != .automatic else { return nil }
            self = .apple(apple)
        } else {
            self = .provider(providerID: provider, modelID: model)
        }
    }

    public var settingValue: String {
        switch self {
        case .apple(.automatic): Self.appleProviderID
        case .apple(let model): "\(Self.appleProviderID)/\(model.rawValue)"
        case .provider(let provider, let model): "\(provider)/\(model)"
        }
    }

    public var isApple: Bool {
        if case .apple = self { true } else { false }
    }

    /// The provider's id, for a provider's model.
    public var providerID: String? {
        if case .provider(let id, _) = self { id } else { nil }
    }
}

extension AIModelChoice: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let choice = AIModelChoice(settingValue: value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a model choice: \(value)"))
        }
        self = choice
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(settingValue)
    }
}

/// The features that use a language model, each with its own model setting.
public enum AIFeature: String, Sendable, CaseIterable {
    case catchUp
    case recap

    /// Its model setting: `""` follows `intelligence.model`.
    public var modelKey: SettingKey<String> {
        switch self {
        case .catchUp: .intelligenceCatchUpModel
        case .recap: .intelligenceRecapModel
        }
    }

    public var title: String {
        switch self {
        case .catchUp: "Catch me up"
        case .recap: "Recap"
        }
    }
}

/// The model settings at one moment, read on the main actor and passed to
/// work elsewhere.
nonisolated public struct AIModelSettings: Sendable, Hashable {
    public var providers: [AIProviderEntry]
    /// `intelligence.model`.
    public var defaultModel: AIModelChoice
    /// Per feature: nil follows ``defaultModel``.
    public var featureModels: [AIFeature: AIModelChoice]

    public init(providers: [AIProviderEntry] = [], defaultModel: AIModelChoice = .automatic, featureModels: [AIFeature: AIModelChoice] = [:]) {
        self.providers = providers
        self.defaultModel = defaultModel
        self.featureModels = featureModels
    }

    /// The choice in effect for `feature`.
    public func choice(for feature: AIFeature) -> AIModelChoice {
        featureModels[feature] ?? defaultModel
    }

    public func provider(_ id: String) -> AIProviderEntry? {
        providers.first { $0.id == id }
    }
}

extension SettingsStore {
    /// The model settings as they stand.
    public var aiModelSettings: AIModelSettings {
        var features: [AIFeature: AIModelChoice] = [:]
        for feature in AIFeature.allCases {
            features[feature] = AIModelChoice(settingValue: self[feature.modelKey])
        }
        return AIModelSettings(
            providers: self[.intelligenceProviders],
            defaultModel: AIModelChoice(settingValue: self[.intelligenceModel]) ?? .automatic,
            featureModels: features
        )
    }

    /// Whether `feature` uses one of Apple's models, read without decoding
    /// the providers: the common case, checked cheaply where Catch me up
    /// decides whether to show its button.
    public func usesAppleModel(for feature: AIFeature) -> Bool {
        let choice = AIModelChoice(settingValue: self[feature.modelKey])
            ?? AIModelChoice(settingValue: self[.intelligenceModel])
            ?? .automatic
        return choice.isApple
    }
}

extension Keychain {
    /// The Keychain account for an AI provider's key you entered in
    /// Settings → AI Providers: `ai/<provider id>` (`ai/anthropic`). Never
    /// settings.json.
    public static func aiProviderKeyAccount(_ providerID: String) -> String {
        "ai/\(providerID)"
    }
}
