// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// A value that can be stored in settings.json.
public protocol SettingValueConvertible: Sendable {
    /// Returns `nil` when the JSON has the wrong shape; the setting then
    /// falls back to its default.
    init?(settingJSON: JSONValue)
    var settingJSON: JSONValue { get }
    /// JSON Schema fragment for the value (e.g. `{"type": "boolean"}`).
    static var settingSchema: JSONValue { get }
}

extension Bool: SettingValueConvertible {
    public init?(settingJSON: JSONValue) {
        guard let value = settingJSON.boolValue else { return nil }
        self = value
    }
    public var settingJSON: JSONValue { .bool(self) }
    public static var settingSchema: JSONValue { .object(["type": "boolean"]) }
}

extension String: SettingValueConvertible {
    public init?(settingJSON: JSONValue) {
        guard let value = settingJSON.stringValue else { return nil }
        self = value
    }
    public var settingJSON: JSONValue { .string(self) }
    public static var settingSchema: JSONValue { .object(["type": "string"]) }
}

extension Double: SettingValueConvertible {
    public init?(settingJSON: JSONValue) {
        guard let value = settingJSON.doubleValue, value.isFinite else { return nil }
        self = value
    }
    public var settingJSON: JSONValue { .number(self) }
    public static var settingSchema: JSONValue { .object(["type": "number"]) }
}

extension Int: SettingValueConvertible {
    public init?(settingJSON: JSONValue) {
        guard let value = settingJSON.doubleValue, let exact = Int(exactly: value) else { return nil }
        self = exact
    }
    public var settingJSON: JSONValue { .number(Double(self)) }
    public static var settingSchema: JSONValue { .object(["type": "integer"]) }
}

extension JSONValue: SettingValueConvertible {
    public init?(settingJSON: JSONValue) { self = settingJSON }
    public var settingJSON: JSONValue { self }
    public static var settingSchema: JSONValue { .object([:]) }
}

extension Array: SettingValueConvertible where Element: SettingValueConvertible {
    /// Elements of the wrong type are dropped rather than failing the
    /// whole array.
    public init?(settingJSON: JSONValue) {
        guard let array = settingJSON.arrayValue else { return nil }
        self = array.compactMap(Element.init(settingJSON:))
    }
    public var settingJSON: JSONValue { .array(map(\.settingJSON)) }
    public static var settingSchema: JSONValue { .object(["type": "array", "items": Element.settingSchema]) }
}

extension Dictionary: SettingValueConvertible where Key == String, Value == JSONValue {
    public init?(settingJSON: JSONValue) {
        guard let object = settingJSON.objectValue else { return nil }
        self = object
    }
    public var settingJSON: JSONValue { .object(self) }
    public static var settingSchema: JSONValue { .object(["type": "object"]) }
}

extension SettingValueConvertible where Self: RawRepresentable, RawValue == String, Self: CaseIterable {
    public init?(settingJSON: JSONValue) {
        guard let raw = settingJSON.stringValue, let value = Self(rawValue: raw) else { return nil }
        self = value
    }
    public var settingJSON: JSONValue { .string(rawValue) }
    public static var settingSchema: JSONValue {
        .object(["type": "string", "enum": .array(allCases.map { .string($0.rawValue) })])
    }
}

/// A typed handle for one settings.json key, VS Code style (dotted names
/// such as `"chat.fontSize"`).
///
/// Equality and hashing use only ``key`` so keys can be used in key paths
/// (e.g. `$settings[.chatFontSize]` with `@Bindable`).
public struct SettingKey<Value: Sendable>: Sendable, Hashable {
    public let key: String
    public let defaultValue: Value
    /// One-line description shown in the Settings UI and default settings.
    public let summary: String
    /// JSON Schema fragment describing the value.
    public let schema: JSONValue

    private let decode: @Sendable (JSONValue) -> Value?
    private let encode: @Sendable (Value) -> JSONValue

    public init(
        _ key: String,
        default defaultValue: Value,
        summary: String = "",
        schema: JSONValue = .object([:]),
        decode: @escaping @Sendable (JSONValue) -> Value?,
        encode: @escaping @Sendable (Value) -> JSONValue
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.summary = summary
        self.schema = schema
        self.decode = decode
        self.encode = encode
    }

    /// Decodes a stored value, falling back to ``defaultValue`` when the key
    /// is missing or has the wrong type.
    public func value(from json: JSONValue?) -> Value {
        json.flatMap(decode) ?? defaultValue
    }

    public func jsonValue(for value: Value) -> JSONValue {
        encode(value)
    }

    public var defaultJSONValue: JSONValue { encode(defaultValue) }

    public var descriptor: SettingDescriptor {
        var schema = schema
        // Number ranges live in one table (SettingsMetadata) and reach the
        // JSON schema, the validator and the settings editor from here.
        if let range = SettingsMetadata.numberRanges[key], case .object(var object) = schema {
            object["minimum"] = .number(range.lowerBound)
            object["maximum"] = .number(range.upperBound)
            schema = .object(object)
        }
        return SettingDescriptor(key: key, defaultValue: defaultJSONValue, summary: summary, schema: schema)
    }

    public static func == (lhs: SettingKey, rhs: SettingKey) -> Bool { lhs.key == rhs.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

extension SettingKey where Value: SettingValueConvertible {
    public init(_ key: String, default defaultValue: Value, summary: String = "") {
        self.init(
            key,
            default: defaultValue,
            summary: summary,
            schema: Value.settingSchema,
            decode: { Value(settingJSON: $0) },
            encode: { $0.settingJSON }
        )
    }
}

/// Type-erased documentation for one setting.
public struct SettingDescriptor: Sendable, Hashable, Identifiable {
    public let key: String
    public let defaultValue: JSONValue
    public let summary: String
    public let schema: JSONValue

    public var id: String { key }

    /// The part of the key before the first dot (`"chat"` for `"chat.fontSize"`).
    public var category: String {
        String(key.prefix(while: { $0 != "." }))
    }
}
