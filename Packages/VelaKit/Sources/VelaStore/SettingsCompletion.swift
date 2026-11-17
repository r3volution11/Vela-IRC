// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation

/// Where completion is happening in settings.json. See
/// ``SettingsCompletion/context(in:at:)``.
public enum SettingsCompletionContext: Sendable, Hashable {
    /// Nothing to complete: in a comment, outside the top-level object, or
    /// the text isn't an object.
    case none
    /// Typing a setting name at the top level.
    case key(SettingsKeyPosition)
    /// Typing a setting's value (or an element of its array).
    case value(SettingsValuePosition)
    /// Typing a key inside an object setting: a domain in
    /// `media.siteRules`, a token or `"[Theme]"` scope in
    /// `appearance.colorCustomizations`, a token inside a scope. Use
    /// ``SettingsKeyPosition/descriptor``'s `suggestionSource` for suggestions.
    case nestedKey(SettingsKeyPosition)
    /// Typing a value inside an object setting (`"allow"` in `media.siteRules`).
    case nestedValue(SettingsValuePosition)
}

/// A key being typed. Ranges are UTF-16.
public struct SettingsKeyPosition: Sendable, Hashable {
    /// The keys of the object being typed in: `[]` at the top level,
    /// `["media.siteRules"]`, or `["appearance.colorCustomizations", "[Palenight]"]`.
    public var objectPath: [String]
    /// What's typed so far, without the opening quote.
    public var prefix: String
    /// What a completion replaces: the key string (quotes included) or word
    /// under the cursor, or an empty range at the cursor.
    public var replaceRange: NSRange
    public var isInsideQuotes: Bool
    /// The other keys already in the object.
    public var existingKeys: [String]
    /// A colon (and value) already follows: insert just the key.
    public var hasValue: Bool
    /// Another member follows, so the inserted text must end with a comma.
    public var needsCommaAfter: Bool
    /// Where the previous member is missing its comma, if it is.
    public var missingCommaOffset: Int?

    /// The setting whose object this is (nil at the top level).
    public var settingKey: String? { objectPath.first }
    /// Documentation for ``settingKey``, when it's a known setting.
    public var descriptor: SettingDescriptor? { settingKey.flatMap { SettingsValidator.descriptors[$0] } }
}

/// A value being typed. Ranges are UTF-16.
public struct SettingsValuePosition: Sendable, Hashable {
    /// The property's path: `["chat.layout"]`, or
    /// `["media.siteRules", "example.com"]` inside an object setting.
    public var path: [String]
    /// What's typed so far, without the opening quote.
    public var prefix: String
    /// What a completion replaces: the whole current value (quotes
    /// included), or an empty range at the cursor.
    public var replaceRange: NSRange
    public var isInsideQuotes: Bool
    /// Typing an element of the setting's array (`highlight.words`).
    public var isArrayElement: Bool
    /// Another member follows, so the inserted text must end with a comma.
    public var needsCommaAfter: Bool
    /// Arrays: where the previous element is missing its comma, if it is.
    public var missingCommaOffset: Int?

    /// The top-level setting.
    public var key: String { path.first ?? "" }
    /// Documentation for ``key``, when it's a known setting.
    public var descriptor: SettingDescriptor? { SettingsValidator.descriptors[key] }
}

/// One entry in the completion list.
public struct SettingsCompletionItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// A setting name (with its default value).
        case setting
        /// A key inside an object setting (supplied by the UI).
        case key
        /// A value.
        case value
    }

    public var kind: Kind
    /// What the list shows: the key, or the value as JSON (`"grouped"`, `true`).
    public var label: String
    /// A friendlier title: `"Chat: Font Size"`, or the UI's label for a value.
    public var title: String?
    /// Documentation: the setting's summary, or a note about the value.
    public var detail: String?
    /// The text that replaces ``replaceRange``.
    public var insertText: String
    /// UTF-16 range in the original text.
    public var replaceRange: NSRange
    /// Where the caret goes (or what to select, e.g. a default value to
    /// type over), relative to the start of ``insertText``.
    public var selection: NSRange
    /// Other edits to make with this one, before ``replaceRange`` (such as
    /// a comma the previous property is missing). Original-text ranges.
    public var additionalEdits: [JSONCEdit]
    /// Setting names: the setting is already in the file.
    public var isSet: Bool
    /// Values: this is the setting's default.
    public var isDefault: Bool
    /// The text to match what's typed (``SettingsKeyPosition/prefix``) against.
    public var filterText: String
    /// The setting this is about.
    public var descriptor: SettingDescriptor?

    public var id: String { "\(kind)|\(label)" }

    /// Caret offset in ``insertText`` (the start of ``selection``).
    public var caretOffset: Int { selection.location }

    /// Every edit to make, relative to the original text: apply with
    /// ``JSONCEdit/apply(_:to:)`` or one by one from the last to the first.
    public var edits: [JSONCEdit] {
        additionalEdits + [JSONCEdit(range: replaceRange, replacement: insertText)]
    }

    /// The selection to set after applying ``edits``, in the new text.
    public var selectionAfterApplying: NSRange {
        let shift = additionalEdits
            .filter { $0.range.location < replaceRange.location }
            .reduce(0) { $0 + $1.replacement.utf16.count - $1.range.length }
        return NSRange(location: replaceRange.location + shift + selection.location, length: selection.length)
    }
}

/// The key under the cursor, for hover documentation.
public struct SettingsHover: Sendable, Hashable {
    /// The key under the cursor.
    public var key: String
    /// Its path from the top level (`[key]` for a setting).
    public var path: [String]
    /// The key string's range, quotes included (UTF-16).
    public var range: NSRange
    /// Documentation for the top-level setting (``path``'s first key), nil
    /// for unknown settings.
    public var descriptor: SettingDescriptor?

    /// True for a setting name; false for a key inside an object setting.
    public var isSetting: Bool { path.count == 1 }
}

/// Completion and hover for settings.json, from ``SettingsCatalog``.
///
/// ```swift
/// let context = SettingsCompletion.context(in: text, at: cursor)
/// var items = SettingsCompletion.items(for: context)
/// if case .value(let position) = context, position.descriptor?.suggestionSource == .themes {
///     items += themeNames.map { SettingsCompletion.valueItem(.string($0), at: position) }
/// }
/// items = SettingsCompletion.filter(items, matching: prefix)
/// // On accept:
/// let newText = JSONCEdit.apply(item.edits, to: text)
/// textView.setSelectedRange(item.selectionAfterApplying)
/// ```
public enum SettingsCompletion {
    /// What's being typed at `offset` (UTF-16).
    public static func context(in text: String, at offset: Int) -> SettingsCompletionContext {
        context(in: JSONCDocument(text), at: offset)
    }

    /// ``context(in:at:)`` for text that's already parsed.
    public static func context(in document: JSONCDocument, at offset: Int) -> SettingsCompletionContext {
        guard document.root?.kind == .object else { return .none }
        let location = document.location(at: offset)
        switch location.kind {
        case .none:
            return .none
        case .propertyKey:
            let position = SettingsKeyPosition(
                objectPath: location.path,
                prefix: location.prefix,
                replaceRange: location.replaceRange,
                isInsideQuotes: location.isInsideQuotes,
                existingKeys: location.siblingKeys,
                hasValue: location.hasColon,
                needsCommaAfter: location.needsCommaAfter,
                missingCommaOffset: location.missingCommaOffset
            )
            return location.path.isEmpty ? .key(position) : .nestedKey(position)
        case .propertyValue, .arrayElement:
            guard !location.path.isEmpty else { return .none }
            let position = SettingsValuePosition(
                path: location.path,
                prefix: location.prefix,
                replaceRange: location.replaceRange,
                isInsideQuotes: location.isInsideQuotes,
                isArrayElement: location.kind == .arrayElement,
                needsCommaAfter: location.needsCommaAfter,
                missingCommaOffset: location.missingCommaOffset
            )
            return location.path.count == 1 ? .value(position) : .nestedValue(position)
        }
    }

    /// The model's completions for `context`, unfiltered:
    ///
    /// - top-level keys: every known setting, inserted as
    ///   `"chat.fontSize": 13` with the default selected;
    /// - values: enum values, `true`/`false`, `"system"` for settings that
    ///   follow macOS, and the default (marked ``SettingsCompletionItem/isDefault``);
    /// - nested values: the allowed values of `media.siteRules`-style objects.
    ///
    /// Suggestions that depend on the app (themes, fonts, buffers, domains,
    /// theme tokens) come from the UI: build them with ``valueItem(_:title:detail:at:)``
    /// and ``keyItem(_:value:title:detail:at:)``.
    public static func items(for context: SettingsCompletionContext) -> [SettingsCompletionItem] {
        switch context {
        case .none, .nestedKey:
            return []
        case .key(let position):
            return SettingsValidator.catalog.map { settingItem($0, at: position) }
        case .value(let position):
            return position.isArrayElement ? [] : topLevelValueItems(at: position)
        case .nestedValue(let position):
            guard position.path.count == 2, !position.isArrayElement,
                  let allowed = position.descriptor?.objectValueEnum
            else { return [] }
            return allowed.map { valueItem(.string($0), at: position) }
        }
    }

    /// A completion inserting `value` at a value position.
    public static func valueItem(_ value: JSONValue, title: String? = nil, detail: String? = nil, at position: SettingsValuePosition) -> SettingsCompletionItem {
        let text = JSONCEditing.compact(value)
        let isDefault = position.path.count == 1 && !position.isArrayElement && position.descriptor?.defaultValue == value
        return SettingsCompletionItem(
            kind: .value,
            label: text,
            title: title,
            detail: detail ?? (isDefault ? "Default" : nil),
            insertText: text + (position.needsCommaAfter ? "," : ""),
            replaceRange: position.replaceRange,
            selection: NSRange(location: caretInside(value) ?? text.utf16.count, length: 0),
            additionalEdits: position.missingCommaOffset.map { [.insert(",", at: $0)] } ?? [],
            isSet: false,
            isDefault: isDefault,
            filterText: value.stringValue ?? text,
            descriptor: position.descriptor
        )
    }

    /// A completion inserting `"key": value` at a key position (or just
    /// `"key"` when a value is already there). With no `value`, inserts
    /// `""` with the caret inside, ready for value completion.
    public static func keyItem(_ key: String, value: JSONValue? = nil, title: String? = nil, detail: String? = nil, at position: SettingsKeyPosition) -> SettingsCompletionItem {
        var item = entryItem(key: key, value: value ?? .string(""), selectValue: value != nil, at: position)
        item.kind = .key
        item.title = title
        item.detail = detail
        item.isSet = position.existingKeys.contains(key)
        item.descriptor = position.descriptor
        return item
    }

    /// `items` that match `prefix` (case-insensitive), best first: prefix
    /// matches, then matches at a word start (`fontS` → `chat.fontSize`),
    /// then title matches, then the letters in order. Empty `prefix` keeps all.
    public static func filter(_ items: [SettingsCompletionItem], matching prefix: String) -> [SettingsCompletionItem] {
        let typed = prefix.lowercased()
        guard !typed.isEmpty else { return items }
        let scored: [(score: Int, index: Int, item: SettingsCompletionItem)] = items.enumerated().compactMap { index, item in
            let text = item.filterText.lowercased()
            let score: Int
            if text.hasPrefix(typed) {
                score = 0
            } else if text.contains("." + typed) || text.contains("[" + typed) || text.contains(" " + typed) {
                score = 1
            } else if let title = item.title?.lowercased(), title.contains(typed) {
                score = 2
            } else if isSubsequence(typed, of: text) {
                score = 3
            } else {
                return nil
            }
            return (score, index, item)
        }
        return scored.sorted { ($0.score, $0.index) < ($1.score, $1.index) }.map(\.item)
    }

    // MARK: Hover

    /// The key under `offset` (UTF-16): a setting name, or a key inside an
    /// object setting. Nil elsewhere.
    public static func hover(in text: String, at offset: Int) -> SettingsHover? {
        hover(in: JSONCDocument(text), at: offset)
    }

    /// ``hover(in:at:)`` for text that's already parsed.
    public static func hover(in document: JSONCDocument, at offset: Int) -> SettingsHover? {
        guard let root = document.root, root.kind == .object else { return nil }
        for candidate in [offset, offset - 1] {
            guard let index = document.tokenIndex(at: candidate), document.isPropertyKey(tokenAt: index) else { continue }
            let range = document.tokens[index].range
            guard let path = path(toKeyAt: range, in: root) else { continue }
            return SettingsHover(
                key: path.last ?? "",
                path: path,
                range: range,
                descriptor: SettingsValidator.descriptors[path[0]]
            )
        }
        return nil
    }

    private static func path(toKeyAt range: NSRange, in object: JSONCNode) -> [String]? {
        for property in object.properties {
            if property.keyRange == range { return [property.key] }
            if let value = property.value, value.kind == .object,
               NSLocationInRange(range.location, value.range),
               let rest = path(toKeyAt: range, in: value)
            {
                return [property.key] + rest
            }
        }
        return nil
    }

    // MARK: Building items

    private static func settingItem(_ descriptor: SettingDescriptor, at position: SettingsKeyPosition) -> SettingsCompletionItem {
        var item = entryItem(key: descriptor.key, value: descriptor.defaultValue, selectValue: true, at: position)
        item.title = descriptor.title
        item.detail = descriptor.summary
        item.isSet = position.existingKeys.contains(descriptor.key)
        item.descriptor = descriptor
        return item
    }

    /// `"key": value` (plus a comma when needed), or `"key"` when the key
    /// already has a value. Selects the value (`selectValue`) or puts the
    /// caret inside empty strings, objects and arrays.
    private static func entryItem(key: String, value: JSONValue, selectValue: Bool, at position: SettingsKeyPosition) -> SettingsCompletionItem {
        let quotedKey = JSONCEditing.quote(key)
        let insertText: String
        let selection: NSRange
        if position.hasValue {
            insertText = quotedKey
            selection = NSRange(location: quotedKey.utf16.count, length: 0)
        } else {
            let valueText = JSONCEditing.compact(value)
            let valueStart = quotedKey.utf16.count + 2
            insertText = quotedKey + ": " + valueText + (position.needsCommaAfter ? "," : "")
            if let inside = caretInside(value) {
                selection = NSRange(location: valueStart + inside, length: 0)
            } else if selectValue, case .string = value {
                selection = NSRange(location: valueStart + 1, length: valueText.utf16.count - 2)
            } else if selectValue {
                selection = NSRange(location: valueStart, length: valueText.utf16.count)
            } else {
                selection = NSRange(location: valueStart + valueText.utf16.count, length: 0)
            }
        }
        return SettingsCompletionItem(
            kind: .setting,
            label: key,
            title: nil,
            detail: nil,
            insertText: insertText,
            replaceRange: position.replaceRange,
            selection: selection,
            additionalEdits: position.missingCommaOffset.map { [.insert(",", at: $0)] } ?? [],
            isSet: false,
            isDefault: false,
            filterText: key,
            descriptor: nil
        )
    }

    /// For `""`, `{}` and `[]`: the caret offset between the delimiters.
    private static func caretInside(_ value: JSONValue) -> Int? {
        switch value {
        case .string(let string) where string.isEmpty: 1
        case .object(let object) where object.isEmpty: 1
        case .array(let array) where array.isEmpty: 1
        default: nil
        }
    }

    private static func topLevelValueItems(at position: SettingsValuePosition) -> [SettingsCompletionItem] {
        guard let descriptor = position.descriptor else { return [] }
        var values: [JSONValue]
        if descriptor.followsSystem {
            values = [true, false, .string(SystemFollowingBool.system.rawValue)]
        } else if let allowed = descriptor.enumValues {
            values = allowed.map(JSONValue.string)
        } else if descriptor.schema["type"]?.stringValue == "boolean" {
            values = [true, false]
        } else {
            values = []
        }
        if !values.contains(descriptor.defaultValue) {
            values.append(descriptor.defaultValue)
        }
        return values.map { valueItem($0, at: position) }
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}
