// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaFoundation
import VelaStore
import VelaTheme

/// The JSON view's completion list: ``SettingsCompletion``'s items plus
/// the app's suggestions (themes, fonts, timestamp patterns, languages,
/// channels, sites, theme tokens), and how accepting one edits the text.
enum JSONCompletionModel {
    /// Where suggestions for a ``SettingSuggestionSource`` come from
    /// (``SettingSuggestionProvider`` in the app, a fixed list in tests).
    typealias Suggestions = (SettingSuggestionSource) -> [TokenSuggestion]

    /// Every completion for `context`, unfiltered.
    ///
    /// - Parameters:
    ///   - suggestions: The app's suggestions for a source.
    ///   - tokenColor: The current theme's color for a theme token, as hex,
    ///     offered as a value inside `appearance.colorCustomizations`.
    static func items(
        for context: SettingsCompletionContext,
        suggestions: Suggestions,
        tokenColor: (String) -> String? = { _ in nil }
    ) -> [SettingsCompletionItem] {
        let modelItems = SettingsCompletion.items(for: context)
        switch context {
        case .none, .key:
            return modelItems
        case .value(let position):
            return valueItems(modelItems, at: position, suggestions: suggestions)
        case .nestedKey(let position):
            return nestedKeyItems(at: position, suggestions: suggestions)
        case .nestedValue(let position):
            return modelItems + nestedValueItems(at: position, tokenColor: tokenColor)
        }
    }

    /// What's typed so far at `context`, to filter by.
    static func prefix(of context: SettingsCompletionContext) -> String {
        switch context {
        case .none: ""
        case .key(let position), .nestedKey(let position): position.prefix
        case .value(let position), .nestedValue(let position): position.prefix
        }
    }

    /// The range the items for `context` replace (for placing the popup).
    static func replaceRange(of context: SettingsCompletionContext) -> NSRange? {
        switch context {
        case .none: nil
        case .key(let position), .nestedKey(let position): position.replaceRange
        case .value(let position), .nestedValue(let position): position.replaceRange
        }
    }

    /// `items` matching what's typed, best first.
    static func filtered(_ items: [SettingsCompletionItem], for context: SettingsCompletionContext) -> [SettingsCompletionItem] {
        SettingsCompletion.filter(items, matching: prefix(of: context))
    }

    // MARK: Accepting

    /// The edits that accept `item` in `text`, and the selection after
    /// them. Right after a bare colon (`"chat.layout":|`) the value gets a
    /// space in front, as everywhere else in the file.
    static func acceptance(of item: SettingsCompletionItem, in text: NSString) -> (edits: [JSONCEdit], selection: NSRange) {
        var item = item
        let location = item.replaceRange.location
        if item.kind != .setting, item.kind != .key, item.replaceRange.length == 0,
           location > 0, location <= text.length, text.character(at: location - 1) == 0x3A /* : */
        {
            item.insertText = " " + item.insertText
            item.selection.location += 1
        }
        return (item.edits, item.selectionAfterApplying)
    }

    /// True when accepting `item` should open the list again for its
    /// value: settings with a choice of values, and keys inside object
    /// settings (site rules, theme colors).
    static func offersValues(after item: SettingsCompletionItem) -> Bool {
        switch item.kind {
        case .value: return false
        case .key: return true
        case .setting:
            guard let descriptor = item.descriptor else { return false }
            return descriptor.followsSystem || descriptor.enumValues != nil
                || descriptor.schema["type"]?.stringValue == "boolean"
                || (descriptor.suggestionSource != nil && descriptor.schema["type"]?.stringValue == "string")
        }
    }

    /// True when typing `typed` (a single keystroke's text) should open the
    /// list at `context`: a quote where a key or value goes, a colon, or a
    /// word character inside a key or value.
    static func shouldOpen(afterTyping typed: String, context: SettingsCompletionContext) -> Bool {
        guard typed.count == 1, let character = typed.first else { return false }
        switch context {
        case .none:
            return false
        case .key(let position), .nestedKey(let position):
            if character == "\"" { return true }
            return position.isInsideQuotes && isWordCharacter(character)
        case .value(let position), .nestedValue(let position):
            if character == "\"" || character == ":" { return true }
            if character == "[" { return position.isArrayElement }
            return isWordCharacter(character) && (position.isInsideQuotes || !position.prefix.isEmpty)
        }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "._-#[@*".contains(character)
    }

    // MARK: Values

    private static func valueItems(_ modelItems: [SettingsCompletionItem], at position: SettingsValuePosition, suggestions: Suggestions) -> [SettingsCompletionItem] {
        guard let descriptor = position.descriptor, let source = descriptor.suggestionSource else { return modelItems }
        // Lists of channels take suggestions per element; plain strings at
        // the value itself.
        let isList = descriptor.schema["type"]?.stringValue == "array"
        guard isList == position.isArrayElement else { return modelItems }

        var items = modelItems
        var suggested: [SettingsCompletionItem] = []
        for suggestion in suggestions(source) {
            let value = JSONValue.string(suggestion.value)
            let title = suggestion.label == suggestion.value ? nil : suggestion.label
            var item = SettingsCompletion.valueItem(value, title: title, detail: suggestion.detail, at: position)
            if let existing = items.firstIndex(where: { $0.label == item.label }) {
                // The default (or an enum value) the model already lists:
                // keep the app's friendlier row, marked as the default.
                item.isDefault = items[existing].isDefault
                if item.isDefault { item.detail = [suggestion.detail, "Default"].compactMap { $0 }.joined(separator: " · ") }
                items.remove(at: existing)
            }
            if title != nil {
                // Channels: match "#vela · Libera.Chat", not the stored id.
                item.filterText = "\(suggestion.label) \(suggestion.value)"
            }
            suggested.append(item)
        }
        for index in items.indices where items[index].label == "\"\"" && items[index].title == nil {
            items[index].title = SettingSuggestionProvider.emptyPlaceholder(for: descriptor.key, source: source)
        }
        return items + suggested
    }

    // MARK: Keys inside object settings

    private static func nestedKeyItems(at position: SettingsKeyPosition, suggestions: Suggestions) -> [SettingsCompletionItem] {
        guard let source = position.descriptor?.suggestionSource else { return [] }
        switch source {
        case .themeTokens:
            // Top level of colorCustomizations, or inside a "[Theme]" scope.
            let inScope = position.objectPath.count == 2 && isScope(position.objectPath[1])
            guard position.objectPath.count == 1 || inScope else { return [] }
            var items: [SettingsCompletionItem] = []
            for suggestion in suggestions(.themeTokens) {
                if isScope(suggestion.value) {
                    guard !inScope else { continue }
                    items.append(SettingsCompletion.keyItem(
                        suggestion.value, value: .object([:]), detail: suggestion.detail, at: position
                    ))
                } else {
                    items.append(SettingsCompletion.keyItem(suggestion.value, detail: suggestion.detail, at: position))
                }
            }
            items.append(SettingsCompletion.keyItem("nickColors", value: .array([]), detail: "Nick color palette", at: position))
            items.append(SettingsCompletion.keyItem("ircColors", value: .object([:]), detail: "mIRC colors by index", at: position))
            return items
        case .domains:
            return suggestions(.domains).map { SettingsCompletion.keyItem($0.value, detail: $0.detail, at: position) }
        default:
            return []
        }
    }

    private static func nestedValueItems(at position: SettingsValuePosition, tokenColor: (String) -> String?) -> [SettingsCompletionItem] {
        guard position.key == JSONColorChecks.settingKey, !position.isArrayElement, let last = position.path.last else { return [] }
        let depth = position.path.count
        let inScope = depth == 3 && isScope(position.path[1])
        guard depth == 2 || inScope else { return [] }
        if last == "vibrancy" {
            return ThemeVibrancy.allCases.map {
                SettingsCompletion.valueItem(.string($0.rawValue), at: position)
            }
        }
        if ThemeRegistry.token(last) != nil, let hex = tokenColor(last) {
            return [SettingsCompletion.valueItem(.string(hex), title: "Current theme color", at: position)]
        }
        return []
    }

    /// `"[Nord]"`, `"[Nord][Dracula]"`, `"[Catppuccin *]"`.
    static func isScope(_ key: String) -> Bool {
        key.hasPrefix("[") && key.hasSuffix("]")
    }
}
