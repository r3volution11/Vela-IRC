// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaCore
import VelaTheme

/// A round initials avatar tinted with the nick's theme color.
struct AvatarView: View {
    @Environment(\.theme) private var theme
    let nick: String
    var size: CGFloat = 32
    /// The conversation the avatar is shown in, whose nick colors it uses.
    var buffer: BufferModel? = nil
    /// Your own avatar, in your nick's color (`chat.selfNick`) as everywhere.
    var isSelf = false

    var body: some View {
        let color = isSelf ? theme.color(ThemeKey.chatSelfNick) : theme.nickColor(for: nick, in: buffer)
        ZStack {
            Circle().fill(color.color.opacity(theme.kind == .dark ? 0.28 : 0.2))
            Circle().strokeBorder(color.color.opacity(0.45), lineWidth: 1)
            Text(Self.initials(for: nick))
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(color.color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func initials(for nick: String) -> String {
        let letters = nick.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        guard let first = letters.first else { return "?" }
        return String(Character(first)).uppercased()
    }
}

/// Unread count badge; highlight badges use the highlight colors.
struct UnreadBadge: View {
    @Environment(\.theme) private var theme
    let count: Int
    var isHighlight = false
    var fontSize: CGFloat = 10

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 5)
            .frame(minWidth: fontSize + 8, minHeight: fontSize + 6)
            .foregroundStyle(theme[isHighlight ? ThemeKey.sidebarHighlightBadgeForeground : ThemeKey.sidebarBadgeForeground])
            .background(
                Capsule().fill(theme[isHighlight ? ThemeKey.sidebarHighlightBadgeBackground : ThemeKey.sidebarBadgeBackground])
            )
            .accessibilityLabel(isHighlight ? "\(count) mentions" : "\(count) unread")
    }
}

/// Button style drawn entirely from theme tokens.
struct ThemedButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        ThemedButtonBody(configuration: configuration, prominent: prominent)
    }

    /// The fill token: `button.hoverBackground` under the pointer for a
    /// primary button. A secondary button has no hover color of its own.
    static func fillKey(prominent: Bool, isHovering: Bool) -> String {
        guard prominent else { return ThemeKey.buttonSecondaryBackground }
        return isHovering ? ThemeKey.buttonHoverBackground : ThemeKey.buttonBackground
    }
}

private struct ThemedButtonBody: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let prominent: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(theme[prominent ? ThemeKey.buttonForeground : ThemeKey.buttonSecondaryForeground])
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme[ThemedButtonStyle.fillKey(prominent: prominent, isHovering: isHovering && isEnabled)])
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }
}

/// Small borderless icon button for headers and toolbars.
struct IconButton: View {
    @Environment(\.theme) private var theme
    let systemImage: String
    let help: String
    var isActive = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 24)
                .foregroundStyle(theme[isActive ? ThemeKey.accent : ThemeKey.titleBarSecondaryForeground])
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? theme[ThemeKey.chatHoverBackground] : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}
