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
struct MemberListView: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let buffer: BufferModel
    let session: NetworkSession

    @State private var filter = ""
    @FocusState private var filterFocused: Bool

    var body: some View {
        let prefixes = session.isupport.prefixes
        let groups = MemberGroup.groups(for: buffer.members, prefixes: prefixes, filter: filter)
        let canModerate = session.member(session.selfMember(in: buffer), ranksAtLeast: "o")

        VStack(spacing: 0) {
            header(shown: groups.reduce(0) { $0 + $1.members.count })
            if buffer.memberCount > 0 {
                filterField
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            if groups.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.members) { member in
                                    MemberRow(
                                        member: member,
                                        rankName: MemberGroup.rankName(
                                            mode: member.topPrefix.flatMap { symbol in prefixes.first { $0.symbol == symbol }?.mode },
                                            symbol: member.topPrefix
                                        ),
                                        buffer: buffer,
                                        session: session,
                                        canModerate: canModerate
                                    )
                                }
                            } header: {
                                MemberSectionHeader(title: group.title, count: group.members.count)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.automatic)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme[ThemeKey.memberListBackground])
        .onChange(of: buffer.id) { filter = "" }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Members of \(buffer.name)")
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
        .contentShape(Rectangle())
        .windowTitleBarArea()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var filterField: some View {
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
                .onKeyPress(.escape) {
                    guard !filter.isEmpty else { return .ignored }
                    filter = ""
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
        .background(theme[ThemeKey.memberListBackground])
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
    let canModerate: Bool

    @State private var hovering = false

    var body: some View {
        let fontSize = CGFloat(style.sidebarFontSize)
        let isSelf = session.isupport.caseMapping.fold(member.nick) == session.isupport.caseMapping.fold(session.nick)

        HStack(spacing: 4) {
            Text(member.topPrefix.map(String.init) ?? " ")
                .font(.system(size: fontSize - 1, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme[ThemeKey.memberListPrefixForeground])
                .frame(width: 10, alignment: .center)
                .accessibilityHidden(true)
            if style.showAvatars {
                AvatarView(nick: member.nick, size: CGFloat(min(16, max(12, style.sidebarRowHeight - 7))))
                    .opacity(member.isAway ? 0.5 : 1)
                    .padding(.trailing, 1)
            }
            Text(member.nick)
                .font(.system(size: fontSize, weight: isSelf ? .semibold : .regular))
                .foregroundStyle(nickColor)
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
            RoundedRectangle(cornerRadius: SidebarMetrics.cornerRadius(forRowHeight: style.sidebarRowHeight), style: .continuous)
                .fill(hovering ? theme[ThemeKey.memberListHoverBackground] : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { openQuery() }
        .help(member.userHost.map { "\(member.nick)!\($0)" } ?? member.nick)
        .contextMenu { contextMenu(isSelf: isSelf) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(member.nick)
        .accessibilityValue([rankName, member.isAway ? "away" : nil, isSelf ? "you" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openQuery() }
        .accessibilityAction(named: "Whois") { session.submit("/whois \(member.nick)", in: buffer) }
    }

    private var nickColor: Color {
        if member.isAway { return theme[ThemeKey.memberListAwayForeground] }
        if style.colorNicks { return theme.nickColor(for: member.nick).color }
        return theme[ThemeKey.memberListForeground]
    }

    @ViewBuilder
    private func contextMenu(isSelf: Bool) -> some View {
        let nick = member.nick
        if !isSelf {
            Button("Message") { openQuery() }
        }
        Button("Whois") { session.submit("/whois \(nick)", in: buffer) }
            .disabled(!session.isConnected)
        Button("Copy Nickname") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(nick, forType: .string)
        }
        if canModerate {
            Divider()
            let isOp = session.member(member, has: "o")
            let isVoiced = session.member(member, has: "v")
            Button(isOp ? "Deop" : "Op") { moderate(isOp ? "/deop" : "/op") }
            Button(isVoiced ? "Devoice" : "Voice") { moderate(isVoiced ? "/devoice" : "/voice") }
            if !isSelf {
                Divider()
                Button("Kick", role: .destructive) { moderate("/kick") }
                Button("Ban", role: .destructive) { moderate("/ban") }
                Button("Kick and Ban", role: .destructive) {
                    moderate("/ban")
                    moderate("/kick")
                }
            }
        }
        if !isSelf {
            Divider()
            Button("Ignore") { session.submit("/ignore \(nick)", in: buffer) }
        }
    }

    private func moderate(_ command: String) {
        session.submit("\(command) \(member.nick)", in: buffer)
    }

    private func openQuery() {
        guard session.isupport.caseMapping.fold(member.nick) != session.isupport.caseMapping.fold(session.nick) else { return }
        app.select(session.ensureBuffer(name: member.nick, kind: .query))
    }
}
