// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaMedia
import VelaTheme

/// The expanded player: the window's background at 92% over everything
/// (the command palette still opens above it), with the player as large as
/// its aspect ratio allows and a small toolbar.
///
/// The player keeps playing as it moves here: `EmbedPlayerStore` moves the
/// same view into this overlay's `EmbedPlayerHost`. It returns to its line
/// with Esc, a click on the backdrop, or Return. Esc is left alone while
/// the player is in its own full screen (which it then leaves) and while
/// the command palette is open. The traffic lights stay visible and the
/// top strip still moves the window.
struct ExpandedVideoOverlay: View {
    @Environment(UIState.self) private var uiState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var escapeMonitor = ExpandedVideoEscapeMonitor()

    var body: some View {
        let store = EmbedPlayerStore.shared
        let expanded = store.expandedKey
        ZStack {
            if let key = expanded, let info = store.info(for: key) {
                ExpandedVideoContent(key: key, info: info) {
                    Self.returnToChat(uiState: uiState)
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: expanded)
        .onChange(of: expanded != nil, initial: true) { _, isExpanded in
            if isExpanded {
                escapeMonitor.install { event in handleEscape(event) }
            } else {
                escapeMonitor.remove()
            }
        }
        .onDisappear { escapeMonitor.remove() }
    }

    /// Esc returns the video unless something else should get it: the
    /// player's own full screen, the command palette, a sheet or a menu.
    private func handleEscape(_ event: NSEvent) -> Bool {
        let store = EmbedPlayerStore.shared
        guard store.expandedKey != nil,
              event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
              !store.isAnyInFullscreen,
              uiState.commandPalette == nil,
              NSApp.modalWindow == nil,
              let window = event.window,
              window.attachedSheet == nil,
              window === store.expandedHostWindow
        else { return false }
        Self.returnToChat(uiState: uiState)
        return true
    }

    /// Returns the expanded video to its line, gives the input its focus
    /// back, and scrolls to the line if its spot isn't in view.
    static func returnToChat(uiState: UIState, store: EmbedPlayerStore = .shared) {
        guard let result = store.collapse() else { return }
        if !result.inlineSpotVisible {
            uiState.scrollTarget = result.key.lineID
        }
        uiState.focusInput()
    }
}

/// The backdrop, the toolbar and the player.
private struct ExpandedVideoContent: View {
    @Environment(\.theme) private var theme
    let key: EmbedPlayerKey
    let info: EmbedPlayerInfo
    let onClose: () -> Void

    /// The title-bar strip kept free (and draggable) above the player.
    private static let topInset: CGFloat = 52
    private static let sideMargin: CGFloat = 32
    private static let bottomMargin: CGFloat = 28
    private static let toolbarHeight: CGFloat = 34
    private static let toolbarSpacing: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let playerSize = Self.playerSize(in: proxy.size, aspectRatio: info.aspectRatio)
            ZStack(alignment: .top) {
                // Click outside the player to return it.
                theme[ThemeKey.windowBackground].opacity(0.92)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)

                VStack(spacing: Self.toolbarSpacing) {
                    ExpandedVideoToolbar(info: info, onClose: onClose)
                        .frame(width: max(playerSize.width, min(560, proxy.size.width - 2 * Self.sideMargin)))
                        .frame(height: Self.toolbarHeight)
                    ZStack {
                        Color.black
                        EmbedPlayerHost(key: key, placement: .expanded)
                    }
                    .frame(width: playerSize.width, height: playerSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
                    .accessibilityLabel(info.title.map { "Video: \($0)" } ?? "Video")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, Self.topInset)
                .padding(.bottom, Self.bottomMargin)

                // Dragging here moves the window; the traffic lights sit on top.
                Color.clear
                    .frame(height: Self.topInset)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .windowTitleBarArea()
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Expanded video")
        .accessibilityAction(.escape, onClose)
    }

    /// The player at its aspect ratio, as large as the window allows.
    static func playerSize(in container: CGSize, aspectRatio: CGFloat) -> CGSize {
        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16.0 / 9.0
        let width = max(0, container.width - 2 * sideMargin)
        let height = max(0, container.height - topInset - bottomMargin - toolbarHeight - toolbarSpacing)
        let fitted = width / ratio > height ? CGSize(width: height * ratio, height: height) : CGSize(width: width, height: width / ratio)
        return CGSize(width: fitted.width.rounded(.down), height: fitted.height.rounded(.down))
    }
}

/// Title and site on the left; Open in Browser and Return on the right.
private struct ExpandedVideoToolbar: View {
    @Environment(\.theme) private var theme
    @Environment(\.chatStyle) private var style
    let info: EmbedPlayerInfo
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                if let provider = info.provider {
                    ProviderBadge(provider: provider)
                } else {
                    Text(info.siteName)
                        .font(style.font(size: max(9, style.fontSize - 2), weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                }
                if let title = info.title {
                    Text(title)
                        .font(style.font(size: style.fontSize, weight: .semibold))
                        .foregroundStyle(theme[ThemeKey.chatForeground])
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(title)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            ExpandedToolbarButton(systemImage: "safari", title: "Open in Browser", help: "Open \(info.linkURL.absoluteString)") {
                EmbedActions.open(info.linkURL)
            }
            ExpandedToolbarButton(systemImage: "arrow.down.right.and.arrow.up.left", title: "Return", help: "Return the video to the chat (Esc)", action: onClose)
        }
    }
}

private struct ExpandedToolbarButton: View {
    @Environment(\.theme) private var theme
    let systemImage: String
    let title: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme[ThemeKey.chatForeground])
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(hovering ? theme[ThemeKey.chatHoverBackground] : theme[ThemeKey.embedBackground])
                )
                .overlay(Capsule().strokeBorder(theme[ThemeKey.embedBorder], lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(title)
    }
}

/// A local key monitor for Esc, installed only while a video is expanded.
@MainActor
final class ExpandedVideoEscapeMonitor {
    private var monitor: Any?
    private var handler: ((NSEvent) -> Bool)?

    func install(_ handler: @escaping (NSEvent) -> Bool) {
        self.handler = handler
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // Escape
            let handled = MainActor.assumeIsolated { self?.handler?(event) ?? false }
            return handled ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        handler = nil
    }

    isolated deinit {
        remove()
    }
}
