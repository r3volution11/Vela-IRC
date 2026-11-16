// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaMedia
import VelaTheme

/// Stands in for a preview the media policy blocked: a quiet capsule, in
/// the style of `EmbedChip`, saying why ("Adult site · preview blocked",
/// the site), with small "Show once" and "Always allow" (or, for the user's
/// own block, "Unblock") buttons. Nothing from the site is fetched until one
/// of them is clicked.
struct BlockedPreviewChip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let block: SiteBlock
    /// The link as posted.
    let url: URL
    /// Adds `block.domain` to the line's "Show once" set.
    let onShowOnce: () -> Void
    let onHide: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: Self.systemImage(for: block.reason))
                .font(.system(size: max(9, style.fontSize - 3), weight: .semibold))
                .foregroundStyle(theme[ThemeKey.embedSiteName])
            Text(Self.title(for: block.reason))
                .foregroundStyle(theme[ThemeKey.embedDescription])
                .lineLimit(1)
                .layoutPriority(1)
            Text(block.domain)
                .foregroundStyle(theme[ThemeKey.embedSiteName])
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                ForEach(Self.actions(for: block.reason), id: \.self) { action in
                    ChipTextButton(title: action.title, help: help(for: action)) { perform(action) }
                }
            }
            .padding(.leading, 4)
            .fixedSize()
            .layoutPriority(2)
        }
        .font(style.font(size: max(9, style.fontSize - 2), weight: .medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(theme[ThemeKey.embedBackground]))
        .overlay(Capsule().strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1))
        .contentShape(Capsule())
        .help(url.absoluteString)
        .contextMenu {
            ForEach(Self.actions(for: block.reason), id: \.self) { action in
                Button(action.menuTitle) { perform(action) }
            }
            Divider()
            Button("Open Link") { EmbedActions.open(url) }
            Button("Copy Link") { EmbedActions.copy(url) }
            Divider()
            Button("Hide Previews") { onHide() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: block))
        .accessibilityHint("Preview blocked. Use the actions to show it.")
        .accessibilityAction(named: Action.showOnce.title) { perform(.showOnce) }
        .accessibilityAction(named: Self.lastingAction(for: block.reason).title) {
            perform(Self.lastingAction(for: block.reason))
        }
        .accessibilityAction(named: "Open link") { EmbedActions.open(url) }
    }

    private func perform(_ action: Action) {
        switch action {
        case .showOnce: onShowOnce()
        case .alwaysAllow: app.alwaysAllow(block)
        case .unblock: app.unblock(block)
        }
    }

    private func help(for action: Action) -> String {
        switch action {
        case .showOnce: "Show this preview without changing your settings"
        case .alwaysAllow: "Always show previews from \(block.domain)"
        case .unblock: "Remove your block for \(block.domain)"
        }
    }

    // MARK: Content

    enum Action: Hashable {
        case showOnce
        case alwaysAllow
        case unblock

        var title: String {
            switch self {
            case .showOnce: "Show once"
            case .alwaysAllow: "Always allow"
            case .unblock: "Unblock"
            }
        }

        var menuTitle: String {
            switch self {
            case .showOnce: "Show Once"
            case .alwaysAllow: "Always Allow"
            case .unblock: "Unblock"
            }
        }
    }

    static func title(for reason: BlockReason) -> String {
        switch reason {
        case .adultSite: "Adult site · preview blocked"
        case .adultPage: "Page marked adult · preview blocked"
        case .userBlocked: "Blocked site"
        case .notAllowed: "Not on your allowed sites"
        }
    }

    static func systemImage(for reason: BlockReason) -> String {
        switch reason {
        case .adultSite, .adultPage: "eye.slash"
        case .userBlocked: "nosign"
        case .notAllowed: "hand.raised"
        }
    }

    /// "Show once", then the lasting fix.
    static func actions(for reason: BlockReason) -> [Action] {
        [.showOnce, lastingAction(for: reason)]
    }

    /// Lifting your own block, or an allow rule (which also beats the adult
    /// list and counts as listed when previews are restricted to listed sites).
    static func lastingAction(for reason: BlockReason) -> Action {
        reason == .userBlocked ? .unblock : .alwaysAllow
    }

    static func accessibilityLabel(for block: SiteBlock) -> String {
        "\(title(for: block.reason).replacingOccurrences(of: " · ", with: ", ")), \(block.domain)"
    }
}

/// A small text button inside a chip, underlined on hover like a link.
private struct ChipTextButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(theme[ThemeKey.embedTitle])
                .underline(hovering)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help(help)
    }
}
