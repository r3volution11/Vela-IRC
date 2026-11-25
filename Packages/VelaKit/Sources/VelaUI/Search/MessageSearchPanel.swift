// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntents
import VelaStore
import VelaTheme

// Message search: a palette-style panel at the top of the main window that
// finds messages in saved history (the database's full-text index) and in
// what the open conversations hold in memory, newest first. Opened by
// "Search Messages…" in the command palette, `vela://search`, AppleScript's
// `search` and Spotlight's "Search in Vela"; choosing a result shows it in
// its conversation.

/// One message found.
struct MessageSearchResult: Identifiable, Equatable, Sendable {
    let id: UUID
    let bufferID: BufferID
    let bufferName: String
    let networkName: String
    let nick: String?
    let text: String
    let time: Date
}

/// Finding messages, off the main actor.
enum MessageSearch {
    /// The most results shown.
    nonisolated static let limit = 100

    /// The query's words, folded for matching: every one must appear.
    nonisolated static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    }

    /// Whether `text` has every word, ignoring case and accents.
    nonisolated static func matches(_ text: String, words: [String]) -> Bool {
        guard !words.isEmpty else { return false }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return words.allSatisfy { folded.contains($0) }
    }

    /// What's open, by buffer: the lines in memory share storage with the
    /// buffers (nothing is copied), and are read off the main actor.
    struct Source: Sendable {
        var bufferID: BufferID
        var name: String
        var networkName: String
        var lines: [ChatLine]
    }

    /// The lines in `sources` matching `words`, newest first, at most ``limit``.
    nonisolated static func inMemory(_ sources: [Source], words: [String]) -> [MessageSearchResult] {
        var results: [MessageSearchResult] = []
        for source in sources {
            for line in source.lines.reversed() where line.kind.isConversation && !line.isRedacted {
                guard matches(line.text, words: words) else { continue }
                results.append(MessageSearchResult(
                    id: line.id, bufferID: source.bufferID, bufferName: source.name, networkName: source.networkName,
                    nick: line.nick, text: line.text, time: line.time
                ))
            }
        }
        return Array(results.sorted { $0.time > $1.time }.prefix(limit))
    }

    /// Searches for `request`'s query: saved history, when there is some,
    /// and the lines the open conversations hold.
    static func search(_ request: MessageSearchRequest, app: AppModel) async -> [MessageSearchResult] {
        let words = words(request.query)
        guard !words.isEmpty else { return [] }
        var sources: [Source] = []
        var names: [BufferID: (name: String, network: String)] = [:]
        for session in app.automationSessions where request.networkID == nil || request.bufferID != nil || session.id == request.networkID {
            for buffer in session.buffers where buffer.kind != .server && (request.bufferID == nil || buffer.id == request.bufferID) {
                sources.append(Source(bufferID: buffer.id, name: buffer.name, networkName: session.displayName, lines: buffer.lines))
                names[buffer.id] = (buffer.name, session.displayName)
            }
        }
        let memory = Task.detached(priority: .userInitiated) { inMemory(sources, words: words) }

        var saved: [MessageSearchResult] = []
        if let database = app.database, app.historyStorage.loads {
            let records: [MessageRecord]
            if let bufferID = request.bufferID {
                records = (try? await database.search(request.query, in: bufferID.storeKey, limit: limit)) ?? []
            } else {
                records = (try? await database.search(request.query, networkID: request.networkID, limit: limit)) ?? []
            }
            saved = records.compactMap { record in
                guard record.bufferName != BufferID.serverBufferName else { return nil }
                let id = record.bufferKey
                let bufferID = BufferID(networkID: id.networkID, foldedName: id.foldedName)
                let networkName = app.session(for: id.networkID)?.displayName ?? ""
                return MessageSearchResult(
                    id: record.id, bufferID: bufferID, bufferName: names[bufferID]?.name ?? record.bufferName,
                    networkName: names[bufferID]?.network ?? networkName, nick: record.nick, text: record.text, time: record.time
                )
            }
        }
        var seen: Set<UUID> = []
        let merged = (await memory.value + saved).filter { seen.insert($0.id).inserted }
        return Array(merged.sorted { $0.time > $1.time }.prefix(limit))
    }
}

/// The search panel, shown while `uiState.messageSearch` is set.
struct MessageSearchPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: MessageSearchRequest

    @State private var query: String
    @State private var results: [MessageSearchResult] = []
    @State private var selection = 0
    @State private var hoveredID: UUID?
    @State private var isSearching = false
    @State private var appeared = false

    static let rowHeight: CGFloat = 44
    static let maxVisibleRows = 8

    init(request: MessageSearchRequest) {
        self.request = request
        _query = State(initialValue: request.query)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            panel
                .frame(maxWidth: PaletteMetrics.width)
                .padding(.horizontal, 16)
                .padding(.top, PaletteMetrics.topInset)
                .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) { appeared = true }
        }
        .task(id: query) {
            // Typing pauses before each search.
            if !results.isEmpty || query != request.query { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private var scopeName: String? {
        if let bufferID = request.bufferID, let buffer = app.lookup(bufferID)?.buffer { return buffer.name }
        if let networkID = request.networkID { return app.session(for: networkID)?.displayName }
        return nil
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: PaletteMetrics.cornerRadius, style: .continuous)
        return VStack(spacing: 0) {
            searchBar.padding(8)
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Rectangle().fill(theme[ThemeKey.popoverBorder]).frame(height: 1)
                resultList
            }
        }
        .background(shape.fill(theme[ThemeKey.popoverBackground]))
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme[ThemeKey.popoverBorder], lineWidth: 1))
        .devTag("Message search", tokens: [ThemeKey.popoverBackground, ThemeKey.popoverForeground, ThemeKey.popoverBorder])
        .shadow(color: theme.kind == .dark ? theme[ThemeKey.windowBackground].opacity(0.7) : theme[ThemeKey.popoverForeground].opacity(0.2), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search Messages")
        .accessibilityAddTraits(.isModal)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.inputPlaceholder])
                .frame(width: 16)
                .accessibilityHidden(true)
            PaletteSearchField(
                text: $query,
                placeholder: scopeName.map { "Search messages in \($0)" } ?? "Search messages",
                accessibilityLabel: "Search Messages",
                font: .systemFont(ofSize: 14),
                textColor: theme.color(ThemeKey.inputForeground).nsColor,
                placeholderColor: theme.color(ThemeKey.inputPlaceholder).nsColor,
                caretColor: theme.color(ThemeKey.accent).nsColor,
                selectionColor: theme.color(ThemeKey.chatSelectionBackground).nsColor,
                onTextChange: { _ in selection = 0 },
                onKey: handle
            )
            .frame(height: 20)
            if let scopeName {
                Text(scopeName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme[ThemeKey.popoverForeground].opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme[ThemeKey.inputBackground]))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme[ThemeKey.inputFocusBorder], lineWidth: 1))
    }

    @ViewBuilder
    private var resultList: some View {
        if results.isEmpty {
            Text(isSearching ? "Searching…" : "No messages found")
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.popoverForeground].opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 40)
        } else {
            let selectedID = results.indices.contains(selection) ? results[selection].id : nil
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            Button { open(result) } label: {
                                MessageSearchRow(result: result, isSelected: result.id == selectedID, isHovered: result.id == hoveredID)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering { hoveredID = result.id } else if hoveredID == result.id { hoveredID = nil }
                            }
                            .accessibilityLabel(Self.accessibilityLabel(for: result))
                            .accessibilityAddTraits(result.id == selectedID ? .isSelected : [])
                            .id(result.id)
                        }
                    }
                    .padding(PaletteMetrics.listPadding)
                }
                .scrollIndicators(results.count > Self.maxVisibleRows ? .automatic : .never)
                .frame(height: CGFloat(min(results.count, Self.maxVisibleRows)) * Self.rowHeight + PaletteMetrics.listPadding * 2)
                .onChange(of: selectedID) { _, id in if let id { proxy.scrollTo(id) } }
            }
        }
    }

    static func accessibilityLabel(for result: MessageSearchResult) -> String {
        let when = result.time.formatted(date: .abbreviated, time: .shortened)
        return [result.nick, result.text, "in \(result.bufferName) on \(result.networkName)", when].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: Actions

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        isSearching = true
        var current = request
        current.query = trimmed
        let found = await MessageSearch.search(current, app: app)
        guard !Task.isCancelled else { return }
        results = found
        selection = 0
        isSearching = false
    }

    private func handle(_ key: PaletteKey) -> Bool {
        switch key {
        case .up: move(by: -1)
        case .down: move(by: 1)
        case .pageUp: move(by: -(Self.maxVisibleRows - 1))
        case .pageDown: move(by: Self.maxVisibleRows - 1)
        case .submit:
            if results.indices.contains(selection) { open(results[selection]) }
        case .cancel:
            close()
        case .left, .right, .deleteBackwardWhenEmpty:
            return false
        case .tab:
            break
        }
        return true
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(results.count - 1, max(0, selection + delta))
        if NSWorkspace.shared.isVoiceOverEnabled {
            AccessibilityNotification.Announcement(Self.accessibilityLabel(for: results[selection])).post()
        }
    }

    private func open(_ result: MessageSearchResult) {
        uiState.messageSearch = nil
        guard let (session, buffer) = app.lookup(result.bufferID) else {
            uiState.automationNotice = AutomationNotice(message: "\(result.bufferName) isn't open in Vela anymore.")
            return
        }
        app.select(buffer)
        openWindow(id: WindowID.main)
        MessageJump.jump(to: LineReference(id: result.id, time: result.time), in: buffer, session: session, uiState: uiState)
    }

    private func close() {
        uiState.messageSearch = nil
        uiState.focusInput()
    }
}

/// One result: who and what, then where and when.
private struct MessageSearchRow: View {
    @Environment(\.theme) private var theme
    let result: MessageSearchResult
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        let primary = theme[ThemeKey.popoverForeground]
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let nick = result.nick {
                    Text(nick)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(result.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13))
                    .foregroundStyle(primary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text("\(result.bufferName) · \(result.networkName) · \(result.time.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 11))
                .foregroundStyle(primary.opacity(0.55))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: MessageSearchPanel.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: PaletteMetrics.rowCornerRadius, style: .continuous)
                .fill(isSelected ? theme[ThemeKey.chatSelectionBackground] : isHovered ? theme[ThemeKey.chatHoverBackground] : .clear)
        )
        .devTag(
            "Message search row",
            tokens: [ThemeKey.popoverForeground, isSelected ? ThemeKey.chatSelectionBackground : isHovered ? ThemeKey.chatHoverBackground : ThemeKey.popoverBackground],
            padding: EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        )
        .contentShape(Rectangle())
    }
}
