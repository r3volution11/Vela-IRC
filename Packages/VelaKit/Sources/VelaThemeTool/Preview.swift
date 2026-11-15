// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaTheme

/// Renders a static mock of the Vela window with `theme` to a PNG, for
/// reviewing themes and making screenshots for docs. It approximates the
/// real layout; it isn't the app's UI.
@MainActor
func renderPreview(_ theme: ResolvedTheme, to url: URL) throws {
    let view = PreviewWindow(theme: theme)
        .frame(width: 1180, height: 720)
        .environment(\.colorScheme, theme.colorScheme)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.cgImage else {
        throw CocoaError(.fileWriteUnknown)
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

private struct PreviewWindow: View {
    let theme: ResolvedTheme

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
            Rectangle().fill(theme[ThemeKey.sidebarBorder]).frame(width: 1)
            VStack(spacing: 0) {
                titleBar
                Rectangle().fill(theme[ThemeKey.titleBarBorder]).frame(height: 1)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        messages
                        composer
                    }
                    .background(theme[ThemeKey.chatBackground])
                    Rectangle().fill(theme[ThemeKey.memberListBorder]).frame(width: 1)
                    memberList
                        .frame(width: 180)
                }
            }
        }
        .font(.system(size: 13))
        .background(theme[ThemeKey.windowBackground])
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                ForEach(["#FF5F57", "#FEBC2E", "#28C840"], id: \.self) { hex in
                    Circle().fill(ThemeColor(hex: hex)!.color).frame(width: 12, height: 12)
                }
            }
            .padding(.bottom, 18)
            sectionHeader("LIBERA.CHAT", color: theme[ThemeKey.sidebarHeaderForeground])
            channel("# swift", state: .read)
            channel("# vela", state: .active)
            channel("# macdev", state: .unread, badge: "12")
            channel("# irc", state: .highlight, badge: "2")
            channel("alice", state: .read)
            channel("# lounge", state: .parted)
            sectionHeader("OFTC", color: theme[ThemeKey.sidebarDisconnectedForeground])
                .padding(.top, 14)
            channel("# debian", state: .disconnected)
            channel("# tor", state: .disconnected)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(theme[ThemeKey.statusSuccess]).frame(width: 7, height: 7)
                Text("Connected").foregroundStyle(theme[ThemeKey.sidebarSecondaryForeground])
                Circle().fill(theme[ThemeKey.statusWarning]).frame(width: 7, height: 7)
                Circle().fill(theme[ThemeKey.statusError]).frame(width: 7, height: 7)
            }
            .font(.system(size: 11))
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme[ThemeKey.sidebarBackground])
    }

    private func sectionHeader(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    private enum ChannelState { case read, active, unread, highlight, parted, disconnected }

    private func channel(_ name: String, state: ChannelState, badge: String? = nil) -> some View {
        let foreground: String = switch state {
        case .read: ThemeKey.sidebarForeground
        case .active: ThemeKey.sidebarActiveForeground
        case .unread: ThemeKey.sidebarUnreadForeground
        case .highlight: ThemeKey.sidebarHighlightForeground
        case .parted: ThemeKey.sidebarSecondaryForeground
        case .disconnected: ThemeKey.sidebarDisconnectedForeground
        }
        return HStack {
            Text(name)
                .fontWeight(state == .unread || state == .highlight || state == .active ? .semibold : .regular)
                .foregroundStyle(theme[foreground])
            Spacer()
            if let badge {
                let highlight = state == .highlight
                Text(badge)
                    .font(.system(size: 10.5, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .foregroundStyle(theme[highlight ? ThemeKey.sidebarHighlightBadgeForeground : ThemeKey.sidebarBadgeForeground])
                    .background(Capsule().fill(theme[highlight ? ThemeKey.sidebarHighlightBadgeBackground : ThemeKey.sidebarBadgeBackground]))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(state == .active ? theme[ThemeKey.sidebarActiveBackground] : .clear)
        )
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Text("#vela").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme[ThemeKey.titleBarForeground])
            Text("Vela development · themes are JSON · be kind")
                .foregroundStyle(theme[ThemeKey.titleBarSecondaryForeground])
            Spacer()
            Image(systemName: "magnifyingglass").foregroundStyle(theme[ThemeKey.titleBarForeground])
            Image(systemName: "person.2").foregroundStyle(theme[ThemeKey.titleBarForeground])
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(theme[ThemeKey.titleBarBackground])
    }

    // MARK: Messages

    private var messages: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayDivider("Yesterday")
            message("21:58", "nova", "has anyone tried the new theme engine yet?")
            event("21:59", "→ kestrel joined", key: ThemeKey.chatEventJoin)
            message("22:01", "kestrel", "yes! the fallback chains are really nice")
            dayDivider("Today")
            message("09:12", "orbit", "morning all. see https://github.com/r3volution11/Vela-IRC for the docs")
            embed.padding(.leading, 104).padding(.bottom, 6)
            reactions.padding(.leading, 104).padding(.bottom, 4)
            message("09:14", "me", "I'm porting my old irssi colors over", isSelf: true)
            notice("09:15", "-NickServ- You are now identified for me.")
            unreadMarker
            message("09:16", "wren", "me: can you check `theme.color(.accent)`?", highlight: true)
            action("09:17", "* lumen waves at everyone")
            event("09:18", "← drift left (Leaving)", key: ThemeKey.chatEventPart)
            event("09:18", "kestrel is now known as kes", key: ThemeKey.chatEventNick)
            ircColorsRow
            error("09:19", "Cannot send to channel (+m)")
            Spacer(minLength: 0)
            Text("nova and orbit are typing…")
                .font(.system(size: 11.5))
                .foregroundStyle(theme[ThemeKey.typingForeground])
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func timestamp(_ time: String) -> some View {
        Text(time)
            .font(.system(size: 11.5).monospacedDigit())
            .foregroundStyle(theme[ThemeKey.chatTimestamp])
            .frame(width: 40, alignment: .leading)
    }

    private func message(_ time: String, _ nick: String, _ text: String, isSelf: Bool = false, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            timestamp(time)
            Text(nick)
                .fontWeight(.semibold)
                .foregroundStyle(isSelf ? theme[ThemeKey.chatSelfNick] : theme.nickColor(for: nick).color)
                .frame(width: 56, alignment: .trailing)
            messageText(text, highlight: highlight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            highlight ? theme[ThemeKey.chatHighlightBackground]
                : isSelf ? theme[ThemeKey.chatSelfMessageBackground] : .clear
        )
        .overlay(alignment: .leading) {
            if highlight { Rectangle().fill(theme[ThemeKey.chatHighlightBorder]).frame(width: 3) }
        }
    }

    private func messageText(_ text: String, highlight: Bool) -> Text {
        var result = Text("")
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let piece: Text
            if word.hasPrefix("http") {
                piece = Text(word).foregroundColor(theme[ThemeKey.chatLink]).underline()
            } else if word.hasPrefix("`") {
                piece = Text(word.replacingOccurrences(of: "`", with: ""))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(theme[ThemeKey.chatCodeForeground])
            } else if highlight && word.hasPrefix("me:") {
                piece = Text(word).foregroundColor(theme[ThemeKey.chatMention]).bold()
            } else {
                piece = Text(word).foregroundColor(theme[ThemeKey.chatForeground])
            }
            result = Text("\(result)\(piece) ")
        }
        return result
    }

    private func event(_ time: String, _ text: String, key: String) -> some View {
        HStack(spacing: 8) {
            timestamp(time)
            Text(text).font(.system(size: 12)).foregroundStyle(theme[key]).padding(.leading, 64)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func notice(_ time: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            timestamp(time)
            Text(text).foregroundStyle(theme[ThemeKey.chatNotice]).padding(.leading, 64)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func action(_ time: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            timestamp(time)
            Text(text).italic().foregroundStyle(theme[ThemeKey.chatAction]).padding(.leading, 64)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func error(_ time: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            timestamp(time)
            Text(text).foregroundStyle(theme[ThemeKey.chatError]).padding(.leading, 64)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func dayDivider(_ label: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(theme[ThemeKey.chatDayDivider]).frame(height: 1)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme[ThemeKey.chatDayDividerForeground])
            Rectangle().fill(theme[ThemeKey.chatDayDivider]).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var unreadMarker: some View {
        HStack(spacing: 8) {
            Rectangle().fill(theme[ThemeKey.chatUnreadMarker]).frame(height: 1)
            Text("NEW").font(.system(size: 10, weight: .bold)).foregroundStyle(theme[ThemeKey.chatUnreadMarker])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var embed: some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme[ThemeKey.embedAccent]).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("GITHUB").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme[ThemeKey.embedSiteName])
                Text("r3volution11/Vela-IRC").fontWeight(.semibold).foregroundStyle(theme[ThemeKey.embedTitle])
                Text("A native macOS IRC client where everything is themable.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.embedDescription])
            }
            .padding(10)
            Spacer()
            RoundedRectangle(cornerRadius: 6).fill(theme[ThemeKey.embedPlaceholderBackground])
                .frame(width: 64, height: 48).padding(8)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 420)
        .background(theme[ThemeKey.embedBackground])
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme[ThemeKey.embedBorder]))
    }

    private var reactions: some View {
        HStack(spacing: 6) {
            reaction("👍 3", mine: true)
            reaction("🎉 1", mine: false)
            HStack(spacing: 4) {
                Rectangle().fill(theme[ThemeKey.replyQuoteBar]).frame(width: 2, height: 14)
                Text("↪ nova: has anyone tried…").font(.system(size: 11.5)).foregroundStyle(theme[ThemeKey.replyForeground])
            }
            .padding(.leading, 10)
        }
    }

    private func reaction(_ text: String, mine: Bool) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(theme[ThemeKey.reactionForeground])
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme[mine ? ThemeKey.reactionSelfBackground : ThemeKey.reactionBackground]))
            .overlay(Capsule().stroke(theme[mine ? ThemeKey.reactionSelfBorder : ThemeKey.reactionBorder]))
    }

    private var ircColorsRow: some View {
        HStack(spacing: 8) {
            timestamp("09:18")
            Text("palette").fontWeight(.semibold).foregroundStyle(theme.nickColor(for: "palette").color)
                .frame(width: 56, alignment: .trailing)
            HStack(spacing: 0) {
                ForEach(0..<16, id: \.self) { index in
                    Text(index < 10 ? " \(index)" : "\(index)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.ircColor(index)!.color)
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle").foregroundStyle(theme[ThemeKey.inputIconForeground])
            Text("Message #vela").foregroundStyle(theme[ThemeKey.inputPlaceholder])
            Spacer()
            Text("Send")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(theme[ThemeKey.buttonForeground])
                .background(Capsule().fill(theme[ThemeKey.buttonBackground]))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme[ThemeKey.inputBackground]))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme[ThemeKey.inputBorder]))
        .padding(12)
        .background(theme[ThemeKey.inputContainerBackground])
    }

    // MARK: Member list

    private var memberList: some View {
        VStack(alignment: .leading, spacing: 4) {
            memberHeader("OPERATORS — 2")
            member("@", "orbit")
            member("@", "ChanServ")
            memberHeader("VOICED — 1").padding(.top, 10)
            member("+", "nova")
            memberHeader("MEMBERS — 5").padding(.top, 10)
            member("", "kestrel")
            member("", "lumen")
            member("", "me")
            member("", "wren")
            member("", "drift", away: true)
            Spacer()
            popover
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme[ThemeKey.memberListBackground])
    }

    private func memberHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(theme[ThemeKey.memberListHeaderForeground])
    }

    private func member(_ prefix: String, _ nick: String, away: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(prefix).foregroundStyle(theme[ThemeKey.memberListPrefixForeground]).frame(width: 12)
            Text(nick).foregroundStyle(
                away ? theme[ThemeKey.memberListAwayForeground] : theme[ThemeKey.memberListForeground]
            )
        }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Popover").fontWeight(.semibold).foregroundStyle(theme[ThemeKey.popoverForeground])
            Text("accent").font(.system(size: 11)).padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundStyle(theme[ThemeKey.accentForeground])
                .background(RoundedRectangle(cornerRadius: 4).fill(theme[ThemeKey.accent]))
            Text("secondary").font(.system(size: 11)).padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundStyle(theme[ThemeKey.buttonSecondaryForeground])
                .background(RoundedRectangle(cornerRadius: 4).fill(theme[ThemeKey.buttonSecondaryBackground]))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme[ThemeKey.popoverBackground]))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme[ThemeKey.popoverBorder]))
    }
}
