// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaCore
import VelaTheme

/// What the palette is listing. Unlike `CommandPaletteMode` (how it was
/// opened) this follows the query: `>` turns conversations into commands.
enum PaletteList: Equatable {
    case buffers, commands, themes
}

/// One thing the palette can list, prepared for matching once when the
/// palette opens.
struct PaletteItem: Identifiable {
    enum Payload {
        case buffer(BufferModel, NetworkSession)
        case command(VelaCommand)
        case theme(ThemeInfo)
    }

    let id: String
    let payload: Payload
    /// Matched and highlighted: the conversation name, command title or theme name.
    let label: FuzzyTarget
    /// Shown after the label (the network of a conversation).
    let detail: String?
    /// `label detail`, for queries spanning both ("vela libera").
    let combined: FuzzyTarget?
    /// Matched (as substrings) but never shown, prepared with
    /// `FuzzyMatcher.prepareQuery`.
    let keywords: [[UInt32]]
    /// Position in the natural order (sidebar order, alphabetical).
    let order: Int
    /// Index in the recently-used list (0 = most recent), if present.
    var recency: Int?
    /// The selected conversation, or the theme in use when the palette opened.
    var isCurrent = false
    /// Themes: 0 dark, 1 light.
    var group = 0
}

/// One row on screen: an item plus where the query matched it.
struct PaletteRow: Identifiable {
    let item: PaletteItem
    var labelMatches: [Int] = []
    var detailMatches: [Int] = []
    /// VS Code-style separator label ("recently used"), on a section's first row.
    var sectionLabel: String?
    /// Whether a separator line is drawn above (sections after the first).
    var startsSection = false

    var id: String { item.id }
}

// MARK: - Sources

enum PaletteSource {
    static func bufferItems(app: AppModel, history: [String]) -> [PaletteItem] {
        let recency = Dictionary(history.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [PaletteItem] = []
        for session in app.sessions {
            let buffers = session.isBouncerControl ? [session.serverBuffer] : session.allBuffers
            for buffer in buffers {
                let isServer = buffer.kind == .server
                let label = isServer ? session.displayName : buffer.name
                let detail = isServer ? "network console" : session.displayName
                var item = PaletteItem(
                    id: buffer.id.description,
                    payload: .buffer(buffer, session),
                    label: FuzzyTarget(label),
                    detail: detail,
                    // "network console" is boilerplate; only a network name helps.
                    combined: isServer ? nil : FuzzyTarget("\(label) \(detail)"),
                    keywords: isServer ? [FuzzyMatcher.prepareQuery("server")] : [],
                    order: items.count
                )
                item.recency = recency[buffer.id.description]
                item.isCurrent = buffer.id == app.selectedBufferID
                items.append(item)
            }
        }
        return items
    }

    static func commandItems(_ commands: [VelaCommand], history: [String]) -> [PaletteItem] {
        let recency = Dictionary(history.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let visible = commands.filter { $0.showsInPalette && $0.isEnabled }
        let sorted = visible.sorted { $0.paletteTitle.localizedStandardCompare($1.paletteTitle) == .orderedAscending }
        return sorted.enumerated().map { index, command in
            var item = PaletteItem(
                id: command.id,
                payload: .command(command),
                label: FuzzyTarget(command.paletteTitle),
                detail: nil,
                combined: nil,
                keywords: command.keywords.map(FuzzyMatcher.prepareQuery),
                order: index
            )
            item.recency = recency[command.id]
            return item
        }
    }

    /// `themes` is already sorted by name.
    static func themeItems(_ themes: [ThemeInfo], currentID: String?) -> [PaletteItem] {
        themes.enumerated().map { index, info in
            var item = PaletteItem(
                id: info.id,
                payload: .theme(info),
                label: FuzzyTarget(info.name),
                detail: nil,
                combined: nil,
                keywords: [FuzzyMatcher.prepareQuery(info.kind.rawValue)],
                order: index
            )
            item.group = info.kind == .dark ? 0 : 1
            item.isCurrent = info.id == currentID
            return item
        }
    }
}

// MARK: - Ranking

/// Filters and orders items for a query, VS Code style.
enum PaletteRanker {
    /// Recently used items listed before the rest for an empty query.
    static let recentLimit = 10
    /// Keyword-only matches rank below label matches.
    static let keywordPenalty = 20
    /// Matches that need the network name rank below name-only matches.
    static let combinedPenalty = 12

    static func rows(for items: [PaletteItem], query: String, list: PaletteList) -> [PaletteRow] {
        let prepared = FuzzyMatcher.prepareQuery(query)
        if prepared.isEmpty {
            return emptyQueryRows(items, list: list)
        }

        var scored: [(row: PaletteRow, score: Int)] = []
        scored.reserveCapacity(items.count)
        for item in items {
            guard let matched = match(prepared, item) else { continue }
            let boost = item.recency.map { max(0, 10 - $0) } ?? 0
            scored.append((matched.row, matched.score + boost))
        }
        scored.sort { lhs, rhs in
            if lhs.row.item.group != rhs.row.item.group { return lhs.row.item.group < rhs.row.item.group }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.row.item.label.count != rhs.row.item.label.count {
                return lhs.row.item.label.count < rhs.row.item.label.count
            }
            return lhs.row.item.order < rhs.row.item.order
        }
        var rows = scored.map(\.row)
        if list == .themes { labelThemeGroups(&rows) }
        return rows
    }

    private static func match(_ query: [UInt32], _ item: PaletteItem) -> (row: PaletteRow, score: Int)? {
        if let match = FuzzyMatcher.match(query, in: item.label) {
            return (PaletteRow(item: item, labelMatches: match.positions), match.score)
        }
        if let combined = item.combined, let match = FuzzyMatcher.match(query, in: combined) {
            let split = item.label.count + 1
            let label = match.positions.filter { $0 < split - 1 }
            let detail = match.positions.filter { $0 >= split }.map { $0 - split }
            return (PaletteRow(item: item, labelMatches: label, detailMatches: detail), match.score - combinedPenalty)
        }
        // Keywords are synonyms ("nick list" for the member list), so they
        // must contain the query outright; fuzzy matching them is too loose.
        guard item.keywords.contains(where: { FuzzyMatcher.contains($0, query) }) else { return nil }
        return (PaletteRow(item: item), query.count * FuzzyMatcher.scoreMatch - keywordPenalty)
    }

    private static func emptyQueryRows(_ items: [PaletteItem], list: PaletteList) -> [PaletteRow] {
        switch list {
        case .themes:
            var rows = items.sorted { ($0.group, $0.order) < ($1.group, $1.order) }.map { PaletteRow(item: $0) }
            labelThemeGroups(&rows)
            return rows
        case .buffers, .commands:
            let recent = items
                .filter { $0.recency != nil && !$0.isCurrent }
                .sorted { ($0.recency ?? 0) < ($1.recency ?? 0) }
                .prefix(recentLimit)
            let recentIDs = Set(recent.map(\.id))
            let others = items.filter { !recentIDs.contains($0.id) }.sorted { $0.order < $1.order }
            var rows = recent.map { PaletteRow(item: $0) }
            if !rows.isEmpty {
                rows[0].sectionLabel = list == .commands ? "recently used" : "recently opened"
            }
            var otherRows = others.map { PaletteRow(item: $0) }
            if !rows.isEmpty, !otherRows.isEmpty {
                otherRows[0].sectionLabel = list == .commands ? "other commands" : "all conversations"
                otherRows[0].startsSection = true
            }
            rows += otherRows
            return rows
        }
    }

    private static func labelThemeGroups(_ rows: inout [PaletteRow]) {
        var lastGroup: Int?
        for index in rows.indices {
            let group = rows[index].item.group
            guard group != lastGroup else { continue }
            rows[index].sectionLabel = group == 0 ? "dark themes" : "light themes"
            rows[index].startsSection = lastGroup != nil
            lastGroup = group
        }
    }

    /// Where the highlight starts: the theme in use, otherwise the top row.
    static func initialSelection(in rows: [PaletteRow], list: PaletteList, query: String) -> Int {
        if list == .themes, query.isEmpty, let current = rows.firstIndex(where: { $0.item.isCurrent }) {
            return current
        }
        return 0
    }
}
