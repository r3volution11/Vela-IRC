// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme

/// The VS Code-style command palette, shown as a top-aligned overlay of the
/// main window while `uiState.commandPalette` is non-nil.
///
/// - `.buffers` (⌘P/⌘K): jump to any conversation; typing `>` switches to
///   commands, and Backspace in the empty field switches back.
/// - `.commands` (⇧⌘P): run any ``VelaCommand``; recently used ones first.
/// - `.themes`: pick a theme. Moving the highlight previews it across the
///   app; Return keeps it, Esc (or any other way of closing) reverts.
///
/// Items are prepared once when the palette opens; each keystroke only
/// re-ranks them, and only visible rows are built.
struct CommandPaletteView: View {
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var themeStore
    @Environment(UIState.self) private var uiState
    @Environment(IntelligenceServices.self) private var intelligence
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let mode: CommandPaletteMode

    @State private var list: PaletteList
    @State private var query = ""
    @State private var items: [PaletteItem] = []
    @State private var rows: [PaletteRow] = []
    @State private var selection = 0
    @State private var hoveredID: String?
    @State private var appeared = false
    @State private var previewTask: Task<Void, Never>?
    @State private var isPreviewingTheme = false

    init(mode: CommandPaletteMode) {
        self.mode = mode
        _list = State(initialValue: Self.list(for: mode))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Clicking anywhere outside the panel dismisses it.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)

            panel
                .frame(maxWidth: PaletteMetrics.width)
                .padding(.horizontal, 16)
                .padding(.top, PaletteMetrics.topInset)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.98, anchor: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            reload()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) { appeared = true }
        }
        .onDisappear(perform: endThemePreview)
    }

    // MARK: Panel

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: PaletteMetrics.cornerRadius, style: .continuous)
        return VStack(spacing: 0) {
            searchBar
                .padding(8)
            if !rows.isEmpty || !query.isEmpty {
                Rectangle()
                    .fill(theme[ThemeKey.popoverBorder])
                    .frame(height: 1)
                resultList
            }
        }
        .background(shape.fill(theme[ThemeKey.popoverBackground]))
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme[ThemeKey.popoverBorder], lineWidth: 1))
        .shadow(color: shadowColor, radius: 22, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isModal)
    }

    private var shadowColor: Color {
        theme.kind == .dark
            ? theme[ThemeKey.windowBackground].opacity(0.7)
            : theme[ThemeKey.popoverForeground].opacity(0.2)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.inputPlaceholder])
                .frame(width: 16)
                .accessibilityHidden(true)
            PaletteSearchField(
                text: $query,
                placeholder: placeholder,
                accessibilityLabel: title,
                font: .systemFont(ofSize: 14),
                textColor: theme.color(ThemeKey.inputForeground).nsColor,
                placeholderColor: theme.color(ThemeKey.inputPlaceholder).nsColor,
                caretColor: theme.color(ThemeKey.accent).nsColor,
                selectionColor: theme.color(ThemeKey.chatSelectionBackground).nsColor,
                onTextChange: queryChanged,
                onKey: handle
            )
            .frame(height: 20)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme[ThemeKey.inputBackground])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(theme[ThemeKey.inputFocusBorder], lineWidth: 1)
        )
    }

    @ViewBuilder
    private var resultList: some View {
        if rows.isEmpty {
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(theme[ThemeKey.popoverForeground].opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 40)
        } else {
            let selectedID = rows.indices.contains(selection) ? rows[selection].id : nil
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            Button {
                                run(row)
                            } label: {
                                PaletteRowView(row: row, isSelected: row.id == selectedID, isHovered: row.id == hoveredID)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering {
                                    hoveredID = row.id
                                } else if hoveredID == row.id {
                                    hoveredID = nil
                                }
                            }
                            .accessibilityLabel(accessibilityLabel(for: row))
                            .accessibilityAddTraits(row.id == selectedID ? .isSelected : [])
                            .id(row.id)
                        }
                    }
                    .padding(PaletteMetrics.listPadding)
                }
                .scrollIndicators(rows.count > PaletteMetrics.maxVisibleRows ? .automatic : .never)
                .frame(height: listHeight)
                .onChange(of: selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
                .onAppear {
                    if let selectedID, selection > 0 { proxy.scrollTo(selectedID, anchor: .center) }
                }
            }
        }
    }

    private var listHeight: CGFloat {
        CGFloat(min(rows.count, PaletteMetrics.maxVisibleRows)) * PaletteMetrics.rowHeight
            + PaletteMetrics.listPadding * 2
    }

    // MARK: Text

    private static func list(for mode: CommandPaletteMode) -> PaletteList {
        switch mode {
        case .buffers: .buffers
        case .commands: .commands
        case .themes: .themes
        }
    }

    private var title: String {
        switch list {
        case .buffers: "Go to Conversation"
        case .commands: "Command Palette"
        case .themes: "Select Theme"
        }
    }

    private var glyph: String {
        switch list {
        case .buffers: "magnifyingglass"
        case .commands: "chevron.right"
        case .themes: "paintpalette"
        }
    }

    private var placeholder: String {
        switch list {
        case .buffers: "Search conversations by name (type > for commands)"
        case .commands: "Type a command"
        case .themes: "Select Theme (↑↓ to preview)"
        }
    }

    private var emptyMessage: String {
        switch list {
        case .buffers: "No matching conversations"
        case .commands: "No matching commands"
        case .themes: "No matching themes"
        }
    }

    private func accessibilityLabel(for row: PaletteRow) -> String {
        switch row.item.payload {
        case .buffer(let buffer, let session):
            var parts = [row.item.label.text]
            switch buffer.kind {
            case .server: parts.append("network console")
            case .channel: parts.append("channel on \(session.displayName)")
            case .query: parts.append("conversation on \(session.displayName)")
            }
            if buffer.highlightCount > 0 { parts.append("\(buffer.highlightCount) mentions") }
            if buffer.unreadCount > 0, !buffer.isMuted { parts.append("\(buffer.unreadCount) unread") }
            if row.item.isCurrent { parts.append("current") }
            return parts.joined(separator: ", ")
        case .command(let command):
            var parts = [command.paletteTitle]
            if let detail = command.detail { parts.append(detail) }
            if command.isChecked == true { parts.append("on") }
            if let shortcut = command.shortcut { parts.append(ShortcutGlyphs.spoken(shortcut)) }
            return parts.joined(separator: ", ")
        case .theme(let info):
            var parts = [info.name, info.kind == .dark ? "dark theme" : "light theme"]
            if row.item.isCurrent { parts.append("current") }
            return parts.joined(separator: ", ")
        }
    }

    // MARK: Data

    /// Prepares the items for the current list and ranks them.
    private func reload() {
        switch list {
        case .buffers:
            items = PaletteSource.bufferItems(app: app, history: PaletteHistory.shared.bufferIDs)
        case .commands:
            let catalog = VelaCommandCatalog(VelaCommandContext(
                app: app, themeStore: themeStore, uiState: uiState,
                openWindow: openWindow, openSettings: openSettings,
                intelligence: intelligence
            ))
            items = PaletteSource.commandItems(catalog.all, history: PaletteHistory.shared.commandIDs)
        case .themes:
            items = PaletteSource.themeItems(themeStore.themes, currentID: themeStore.currentInfo?.id)
        }
        rerank()
    }

    private func rerank() {
        rows = PaletteRanker.rows(for: items, query: query, list: list)
        selection = PaletteRanker.initialSelection(in: rows, list: list, query: query)
        selectionChanged()
    }

    private func queryChanged(_ newValue: String) {
        // VS Code: `>` in Quick Open turns it into the command palette.
        if list == .buffers, newValue.hasPrefix(">") {
            list = .commands
            query = String(newValue.dropFirst())
            reload()
            return
        }
        rerank()
    }

    // MARK: Keys

    private func handle(_ key: PaletteKey) -> Bool {
        switch key {
        case .up: move(by: -1, wrapping: true)
        case .down: move(by: 1, wrapping: true)
        case .pageUp: move(by: -(PaletteMetrics.maxVisibleRows - 1), wrapping: false)
        case .pageDown: move(by: PaletteMetrics.maxVisibleRows - 1, wrapping: false)
        case .submit:
            if rows.indices.contains(selection) { run(rows[selection]) }
        case .cancel:
            close()
        case .deleteBackwardWhenEmpty:
            guard list == .commands, mode != .themes else { return false }
            list = .buffers
            reload()
        }
        return true
    }

    private func move(by delta: Int, wrapping: Bool) {
        guard !rows.isEmpty else { return }
        let count = rows.count
        let target = selection + delta
        selection = wrapping ? (target % count + count) % count : min(count - 1, max(0, target))
        selectionChanged()
    }

    private func selectionChanged() {
        guard rows.indices.contains(selection) else { return }
        let row = rows[selection]
        if case .theme(let info) = row.item.payload {
            scheduleThemePreview(info)
        }
        if NSWorkspace.shared.isVoiceOverEnabled {
            AccessibilityNotification.Announcement(accessibilityLabel(for: row)).post()
        }
    }

    // MARK: Actions

    private func run(_ row: PaletteRow) {
        switch row.item.payload {
        case .buffer(let buffer, _):
            close()
            app.select(bufferID: buffer.id)
        case .command(let command):
            PaletteHistory.shared.recordCommand(command.id)
            close()
            // After the palette is gone, so commands that open sheets, panels
            // or the palette itself start from a clean state.
            DispatchQueue.main.async { command.perform() }
        case .theme(let info):
            previewTask?.cancel()
            ThemeFileActions.select(info, settings: app.settings, systemAppearance: themeStore.systemAppearance)
            close()
        }
    }

    /// Closes the palette and puts focus back in the message input.
    private func close() {
        endThemePreview()
        uiState.commandPalette = nil
        uiState.focusInput()
    }

    // MARK: Theme preview

    /// Previews `info` app-wide by pointing the theme store at it without
    /// touching settings.json. Debounced so holding an arrow key doesn't
    /// re-theme the whole window for every row it passes.
    private func scheduleThemePreview(_ info: ThemeInfo) {
        previewTask?.cancel()
        guard info.id != themeStore.currentInfo?.id || isPreviewingTheme else { return }
        previewTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            var preview = ThemeSettings(settings: app.settings)
            preview.followSystemAppearance = false
            preview.themeName = info.id
            isPreviewingTheme = true
            themeStore.settings = preview
        }
    }

    /// Back to what settings.json says: the original theme after Esc, the
    /// chosen one after Return.
    private func endThemePreview() {
        previewTask?.cancel()
        previewTask = nil
        guard isPreviewingTheme else { return }
        isPreviewingTheme = false
        themeStore.settings = ThemeSettings(settings: app.settings)
    }
}
