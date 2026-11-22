// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaIRC
import VelaStore
import VelaTheme

/// The channel member list: a count header aligned with the chat header, a
/// filter field and rank sections (Owners, Operators, Voiced…) derived from
/// the server's PREFIX. Rows are lazy, so big channels stay smooth.
///
/// Click a row to select it, ⌘-click to add or remove one, ⇧-click to
/// select a run. Right-clicking within a selection of several opens the
/// menu for all of them; double-clicking a row opens a conversation.
///
/// It's the window's `.members` area: ⌥⌘4 or F6 give it the keyboard focus,
/// with a highlight on a member that ↑, ↓, Page Up, Page Down, Home and End
/// move. Return opens a conversation with them, Space (or ⇧F10) their menu;
/// typing filters, and Esc clears the filter, then goes back to the
/// message box.
struct MemberListView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let buffer: BufferModel
    let session: NetworkSession

    @State private var filter = ""
    @State private var selection: MemberSelection
    @FocusState private var filterFocused: Bool
    @State private var keyboard = MemberListKeyboard()

    init(buffer: BufferModel, session: NetworkSession, selection: MemberSelection = MemberSelection()) {
        self.buffer = buffer
        self.session = session
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let prefixes = session.isupport.prefixes
        let groups = MemberGroup.groups(for: buffer.members, prefixes: prefixes, filter: filter)
        let mapping = session.isupport.caseMapping
        // Everyone selected, when it's more than one, in list order.
        let selected: [Member] = selection.count > 1
            ? groups.flatMap { $0.members.filter { selection.contains(mapping.fold($0.nick)) } }
            : []
        // For the keys, as shown now; flattened only when a key needs it.
        let order = MemberListOrder(groups: groups)
        // Observed: someone given another nick color as they speak shows it
        // here too, as in their messages. Rows look colors up without
        // watching anything; this runs them again.
        let nickColorStamp = buffer.nickChangeCount

        VStack(spacing: 0) {
            header(shown: groups.reduce(0) { $0 + $1.members.count })
            if buffer.memberCount > 0 {
                filterField(order)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            if groups.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                            ForEach(groups) { group in
                                Section {
                                    ForEach(group.members) { member in
                                        let key = mapping.fold(member.nick)
                                        let isSelected = selection.contains(key)
                                        MemberRow(
                                            member: member,
                                            rankName: MemberGroup.rankName(
                                                mode: member.topPrefix.flatMap { symbol in prefixes.first { $0.symbol == symbol }?.mode },
                                                symbol: member.topPrefix
                                            ),
                                            buffer: buffer,
                                            session: session,
                                            nickColorStamp: nickColorStamp,
                                            isSelected: isSelected,
                                            menuMembers: isSelected && selected.count > 1 ? selected : [member],
                                            keyboard: keyboard,
                                            onClick: { kind in
                                                keyboard.highlight(member.nick)
                                                // The list's order, worked out only for a ⇧-click
                                                // rather than each time the list is drawn.
                                                let folded = kind == .extend || kind == .extendAdding
                                                    ? groups.flatMap { $0.members.map { mapping.fold($0.nick) } } : []
                                                selection.click(key, kind: kind, order: folded)
                                            }
                                        )
                                    }
                                } header: {
                                    MemberSectionHeader(title: group.title, count: group.members.count)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                        // The top, to scroll back to with the keyboard.
                        .background(alignment: .top) {
                            Color.clear.frame(height: 1).id(MemberListKeyboard.topID)
                        }
                        .themedScrollers()
                    }
                    .scrollIndicators(.automatic)
                    .scrollContentBackground(.hidden)
                    // Only when the list is resized, not as it scrolls.
                    .onScrollGeometryChange(for: CGFloat.self, of: \.containerSize.height) { _, height in
                        keyboard.visibleHeight = height
                    }
                    .onAppear { keyboard.proxy = proxy }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .surfaceBackground(ThemeKey.memberListBackground, on: .content)
        .devTag("Member list", tokens: [ThemeKey.memberListBackground, ThemeKey.memberListForeground, ThemeKey.memberListBorder])
        .background {
            KeyboardFocusArea(
                handle: keyboard.handle,
                onFocusChange: { focused in listFocusChanged(focused, order: order) },
                onKey: { key, _ in handleKey(key, order: order) }
            )
        }
        .onChange(of: uiState.focusRequest, initial: true) { _, request in
            guard request?.area == .members else { return }
            uiState.takeFocusRequest(for: .members)
            keyboard.handle.focus()
        }
        // For F6, and for a channel opened meanwhile: the filter is the
        // member list's too.
        .onChange(of: filterFocused) { _, focused in
            uiState.setFocused(.members, focused || keyboard.handle.hasFocus)
        }
        .onChange(of: buffer.id) {
            filter = ""
            selection = MemberSelection()
            keyboard.reset()
        }
        // People who leave drop out of the selection.
        .onChange(of: buffer.memberCount) {
            selection.keep(Set(buffer.members.map { mapping.fold($0.nick) }))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Members of \(buffer.name)")
    }

    // MARK: Keyboard

    /// Told at once, before Return can open a conversation and bring in
    /// its message box.
    private func listFocusChanged(_ focused: Bool, order: MemberListOrder) {
        uiState.setFocused(.members, focused || filterFocused)
        if focused {
            // The last one highlighted, while they're listed; else the first.
            if order.index(of: keyboard.highlighted) == nil { keyboard.highlight(order.nicks.first) }
            if let nick = keyboard.highlighted {
                reveal(nick, in: order, goingUp: false)
                announce(nick, prefix: "Members")
            }
        }
        // Drawn after this update: the focus can move in the middle of one.
        Task { @MainActor in keyboard.setShowing(keyboard.handle.hasFocus) }
    }

    private func handleKey(_ key: NavigationKey, order: MemberListOrder) -> Bool {
        switch key {
        case .up, .down, .pageUp, .pageDown, .home, .end:
            let current = order.index(of: keyboard.highlighted)
            let rowHeight = CGFloat(style.sidebarRowHeight) + 1
            let page = max(1, Int(keyboard.visibleHeight / rowHeight) - 1)
            guard let target = order.target(key, from: current, page: page) else { return true }
            let nick = order.nicks[target]
            guard nick != keyboard.highlighted else { return true }
            // From the row highlighted now, before it moves.
            let step = key == .up || key == .down ? current.map { target - $0 } : nil
            reveal(nick, in: order, goingUp: current.map { target < $0 } ?? false, step: step)
            keyboard.highlight(nick)
            announce(nick)
        case .return:
            if let member = highlightedMember { openQuery(with: member) }
        case .space, .menu:
            if let member = highlightedMember { showMenu(for: member, in: order) }
        case .escape:
            if filter.isEmpty {
                uiState.focusInput()
            } else {
                filter = ""
            }
        case .text(let text):
            typeIntoFilter(text)
        case .left, .right:
            break
        }
        return true
    }

    private var highlightedMember: Member? {
        keyboard.highlighted.flatMap { buffer.member(named: $0, caseMapping: session.isupport.caseMapping) }
    }

    private func reveal(_ nick: String, in order: MemberListOrder, goingUp: Bool = true, step: Int? = nil) {
        guard let index = order.index(of: nick) else { return }
        keyboard.reveal(
            nick, index: index, above: index >= 2 ? order.nicks[index - 2] : nil,
            goingUp: goingUp, step: step, rowHeight: CGFloat(style.sidebarRowHeight) + 1
        )
    }

    /// Return: what double-clicking does. The list goes with the channel,
    /// so the focus goes to the conversation's message box.
    private func openQuery(with member: Member) {
        let mapping = session.isupport.caseMapping
        guard mapping.fold(member.nick) != mapping.fold(session.nick) else { return }
        keyboard.handle.resign()
        app.select(session.ensureBuffer(name: member.nick, kind: .query))
    }

    /// Space, ⇧F10 or the menu key: the menu right-clicking the row opens
    /// (for everyone selected and shown, when they're among several), under
    /// the row.
    private func showMenu(for member: Member, in order: MemberListOrder) {
        let mapping = session.isupport.caseMapping
        var members = [member]
        if selection.count > 1, selection.contains(mapping.fold(member.nick)) {
            members = order.groups.flatMap { $0.members.filter { selection.contains(mapping.fold($0.nick)) } }
        }
        let actions = UserMenuActions(app: app, uiState: uiState, session: session, buffer: buffer)
        let targets = members.map { actions.target(nick: $0.nick) }
        let menu = UserMenuAppKit.menu(actions.menu(for: targets)) { actions.perform($0, on: targets) }
        // Under the row; under the list's top if the row isn't drawn.
        let row = keyboard.menuAnchor.flatMap { $0.window == nil ? nil : $0 }
        guard let anchor = row ?? keyboard.handle.anchorView else { return }
        MemberListKeyboard.presentMenu(menu, anchor)
    }

    /// Letters typed in the list go to the filter, which takes the focus
    /// with the caret after them; ↓ comes back.
    private func typeIntoFilter(_ text: String) {
        // No one in the channel: no filter field.
        guard buffer.memberCount > 0 else { return }
        filter += text
        filterFocused = true
        let window = keyboard.handle.window
        Task { @MainActor in
            // A field taking the focus selects its text, which the next
            // letter would replace.
            for _ in 0..<10 {
                if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor {
                    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                    return
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    /// "marisol, operator", for VoiceOver.
    private func announce(_ nick: String, prefix: String? = nil) {
        guard let member = buffer.member(named: nick, caseMapping: session.isupport.caseMapping) else { return }
        let prefixes = session.isupport.prefixes
        let rank = MemberGroup.rankName(mode: member.topPrefix.flatMap { symbol in prefixes.first { $0.symbol == symbol }?.mode }, symbol: member.topPrefix)
        KeyboardAnnouncement.post([prefix, member.nick, rank, member.isAway ? "away" : nil].compactMap { $0 }.joined(separator: ", "))
    }

    private func header(shown: Int) -> some View {
        let total = buffer.memberCount
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Members")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.memberListForeground])
            Spacer(minLength: 4)
            Text(filter.isEmpty ? "\(total)" : "\(shown) of \(total)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(theme[ThemeKey.memberListHeaderForeground])
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .frame(height: SidebarMetrics.titleStripHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme[ThemeKey.memberListBorder]).frame(height: 1)
        }
        .devTag(
            "Member list header",
            tokens: [ThemeKey.memberListForeground, ThemeKey.memberListHeaderForeground, ThemeKey.memberListBorder],
            font: .system(size: 13, weight: .semibold),
            padding: EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        )
        .contentShape(Rectangle())
        .windowTitleBarArea()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func filterField(_ order: MemberListOrder) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme[ThemeKey.memberListHeaderForeground])
                .accessibilityHidden(true)
            TextField("Filter", text: $filter, prompt: Text("Filter").foregroundStyle(theme[ThemeKey.memberListHeaderForeground]))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme[ThemeKey.memberListForeground])
                .focused($filterFocused)
                // Clears the filter, then goes back to the message box.
                .onKeyPress(.escape) {
                    if filter.isEmpty {
                        uiState.focusInput()
                    } else {
                        filter = ""
                    }
                    return .handled
                }
                // Into the list, on the first match unless the one
                // highlighted is still there.
                .onKeyPress(.downArrow) {
                    guard !order.nicks.isEmpty else { return .ignored }
                    if order.index(of: keyboard.highlighted) == nil { keyboard.highlight(order.nicks.first) }
                    keyboard.handle.focus()
                    return .handled
                }
                .accessibilityLabel("Filter members")
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme[ThemeKey.memberListHeaderForeground])
                }
                .buttonStyle(.plain)
                .help("Clear filter")
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme[ThemeKey.memberListHoverBackground])
        )
        .devTag(
            "Member filter",
            tokens: [ThemeKey.memberListHoverBackground, filterFocused ? ThemeKey.focusBorder : ThemeKey.memberListBorder, ThemeKey.memberListHeaderForeground],
            padding: EdgeInsets(top: 0, leading: 7, bottom: 0, trailing: 7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(theme[filterFocused ? ThemeKey.focusBorder : ThemeKey.memberListBorder], lineWidth: filterFocused ? 1.5 : 1)
                .opacity(filterFocused ? 1 : 0.6)
        )
        .focusEffectDisabled()
        .contentShape(Rectangle())
        .onTapGesture { filterFocused = true }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: filter.isEmpty ? "person.2.slash" : "magnifyingglass")
                .font(.system(size: 18, weight: .light))
            Text(filter.isEmpty ? (buffer.isJoined ? "No members yet" : "Not in channel") : "No matches")
                .font(.system(size: 12))
        }
        .foregroundStyle(theme[ThemeKey.memberListHeaderForeground])
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// "OPERATORS 3", pinned while its rows scroll.
private struct MemberSectionHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .textCase(.uppercase)
                .tracking(0.6)
            Text("\(count)")
                .monospacedDigit()
                .opacity(0.75)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(theme[ThemeKey.memberListHeaderForeground])
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceBackground(ThemeKey.memberListBackground, on: .content)
        .devTag(
            "Member section header",
            tokens: [ThemeKey.memberListHeaderForeground, ThemeKey.memberListBackground],
            font: .system(size: 10, weight: .semibold),
            padding: EdgeInsets(top: 10, leading: 6, bottom: 3, trailing: 6)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One member: prefix symbol, optional avatar and the (colored) nick.
private struct MemberRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let member: Member
    let rankName: String?
    let buffer: BufferModel
    let session: NetworkSession
    /// `buffer.nickChangeCount`. Not read: a new one makes the row run
    /// again and look its nick color up anew.
    let nickColorStamp: Int
    let isSelected: Bool
    /// Who the right-click menu is for: this member, or everyone selected
    /// when the row is part of a selection of several.
    let menuMembers: [Member]
    /// The list's keyboard highlight: the row watches its own flag only.
    let keyboard: MemberListKeyboard
    /// A click, and what it does to the selection (from the modifier
    /// keys held).
    let onClick: (MemberSelection.Click) -> Void

    @State private var hovering = false

    var body: some View {
        let fontSize = CGFloat(style.sidebarFontSize)
        let isSelf = session.isupport.caseMapping.fold(member.nick) == session.isupport.caseMapping.fold(session.nick)
        let isHighlighted = keyboard.flag(for: member.id).isOn
        let cornerRadius = SidebarMetrics.cornerRadius(forRowHeight: style.sidebarRowHeight)

        HStack(spacing: 4) {
            Text(member.topPrefix.map(String.init) ?? " ")
                .font(.system(size: fontSize - 1, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme[ThemeKey.memberListPrefixForeground])
                .frame(width: 10, alignment: .center)
                .accessibilityHidden(true)
            if style.showAvatars {
                AvatarView(nick: member.nick, size: CGFloat(min(16, max(12, style.sidebarRowHeight - 7))), buffer: buffer, isSelf: isSelf)
                    .opacity(member.isAway ? 0.5 : 1)
                    .padding(.trailing, 1)
            }
            Text(member.nick)
                .font(.system(size: fontSize, weight: isSelf ? .semibold : .regular))
                .foregroundStyle(nickColor(isSelf: isSelf))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if member.isAway {
                Image(systemName: "moon.fill")
                    .font(.system(size: max(8, fontSize - 4)))
                    .foregroundStyle(theme[ThemeKey.memberListAwayForeground])
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, 6)
        .frame(height: style.sidebarRowHeight)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(rowBackground)
        )
        .devTag(
            "Member row",
            tokens: [
                ThemeKey.memberListPrefixForeground,
                isSelf ? ThemeKey.chatSelfNick : (style.colorNicks ? nil : ThemeKey.memberListForeground),
                member.isAway ? ThemeKey.memberListAwayForeground : nil,
                isSelected ? ThemeKey.sidebarActiveBackground : hovering ? ThemeKey.memberListHoverBackground : nil,
            ].compactMap { $0 },
            font: .system(size: fontSize, weight: isSelf ? .semibold : .regular),
            padding: EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 6)
        )
        .background {
            // Where Space or ⇧F10 opens the menu, and where the row is, so
            // ↑ and ↓ only scroll when the next row is out of view.
            if isHighlighted {
                MemberMenuAnchor(keyboard: keyboard)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .scrollView(axis: .vertical)) }) { frame in
                        keyboard.highlightedFrame = (member.nick, frame)
                    }
            }
        }
        .keyboardFocusRing(isHighlighted, cornerRadius: cornerRadius)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { openQuery() }
        .simultaneousGesture(selectionGesture)
        .help(member.userHost.map { "\(member.nick)!\($0)" } ?? member.nick)
        .contextMenu {
            MemberUserMenu(members: menuMembers, buffer: buffer, session: session)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(member.nick)
        .accessibilityValue([rankName, member.isAway ? "away" : nil, isSelf ? "you" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { openQuery() }
        .accessibilityAction(named: "Whois") { session.submit("/whois \(member.nick)", in: buffer) }
    }

    /// ⇧⌘-click, ⇧-click, ⌘-click or a plain click, as the selection sees
    /// them. Each tap gesture needs its keys held in the click itself.
    private var selectionGesture: some Gesture {
        TapGesture().modifiers([.shift, .command]).onEnded { onClick(.extendAdding) }
            .exclusively(before: TapGesture().modifiers(.shift).onEnded { onClick(.extend) })
            .exclusively(before: TapGesture().modifiers(.command).onEnded { onClick(.toggle) })
            .exclusively(before: TapGesture().onEnded { onClick(.select) })
    }

    private var rowBackground: Color {
        if isSelected { return theme[ThemeKey.sidebarActiveBackground] }
        return hovering ? theme[ThemeKey.memberListHoverBackground] : .clear
    }

    /// Away dims anyone; otherwise the color their messages have
    /// (`ResolvedTheme.memberListNickColor`).
    private func nickColor(isSelf: Bool) -> Color {
        theme.memberListNickColor(member, isSelf: isSelf, colorNicks: style.colorNicks, in: buffer)
    }

    private func openQuery() {
        guard session.isupport.caseMapping.fold(member.nick) != session.isupport.caseMapping.fold(session.nick) else { return }
        // The list goes with the channel: the conversation's message box
        // takes the focus.
        keyboard.handle.resign()
        app.select(session.ensureBuffer(name: member.nick, kind: .query))
    }
}

/// The user menu for one member, or for everyone selected.
private struct MemberUserMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var uiState
    let members: [Member]
    let buffer: BufferModel
    let session: NetworkSession

    var body: some View {
        let actions = UserMenuActions(app: app, uiState: uiState, session: session, buffer: buffer)
        let targets = members.map { actions.target(nick: $0.nick) }
        UserMenuContent(menu: actions.menu(for: targets)) { actions.perform($0, on: targets) }
    }
}

/// Which members are selected in the member list, by folded nick, and
/// where a ⇧-click extends from.
struct MemberSelection: Equatable {
    private(set) var nicks: Set<String> = []
    /// The last row clicked without Shift.
    private(set) var anchor: String?

    init(nicks: Set<String> = [], anchor: String? = nil) {
        self.nicks = nicks
        self.anchor = anchor ?? nicks.first
    }

    /// How a click changes the selection.
    enum Click: Equatable {
        /// Select just this row.
        case select
        /// ⌘: add or remove this row.
        case toggle
        /// ⇧: select the rows from the anchor to this one.
        case extend
        /// ⇧⌘: add the rows from the anchor to this one.
        case extendAdding
    }

    var count: Int { nicks.count }

    func contains(_ nick: String) -> Bool { nicks.contains(nick) }

    /// A click on `nick`, with the rows as listed in `order`.
    mutating func click(_ nick: String, kind: Click, order: [String]) {
        switch kind {
        case .select:
            nicks = [nick]
            anchor = nick
        case .toggle:
            if nicks.remove(nick) == nil { nicks.insert(nick) }
            anchor = nick
        case .extend, .extendAdding:
            guard let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: nick) else {
                nicks = kind == .extendAdding ? nicks.union([nick]) : [nick]
                self.anchor = nick
                return
            }
            let run = Set(order[min(from, to)...max(from, to)])
            nicks = kind == .extendAdding ? nicks.union(run) : run
        }
    }

    /// Drops anyone not in `members` (they left).
    mutating func keep(_ members: Set<String>) {
        nicks.formIntersection(members)
        if let anchor, !members.contains(anchor) { self.anchor = nil }
    }
}
