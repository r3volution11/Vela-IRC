// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaMedia
import VelaTheme

/// The GIFs tab's grid: results in the service's order, row by row. Only
/// cells in view load their previews and play; a cell scrolled away stops
/// and lets its player go. The next page loads when the last row comes
/// into view.
struct GIFGridView: View {
    @Environment(\.theme) private var theme
    let model: GIFPickerModel
    let services: GIFSearchServices
    let animates: Bool
    var columns = GIFGridView.columns
    var width: CGFloat
    var height: CGFloat
    let onPick: (GIFSearchResult) -> Void

    static let columns = 3
    static let spacing: CGFloat = 6
    static let horizontalPadding: CGFloat = 12

    var cellSize: CGSize {
        let cellWidth = ((width - Self.horizontalPadding * 2 - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
        return CGSize(width: cellWidth, height: (cellWidth * 0.75).rounded())
    }

    var body: some View {
        let size = cellSize
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(size.width), spacing: Self.spacing), count: columns),
                    alignment: .leading,
                    spacing: Self.spacing
                ) {
                    ForEach(Array(model.results.enumerated()), id: \.offset) { index, result in
                        GIFResultCell(
                            result: result,
                            size: size,
                            animates: animates,
                            isSelected: model.selection == index,
                            services: services,
                            onVisible: { model.resultAppeared(at: index, columns: columns) },
                            onPick: { onPick(result) }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, 8)
                .opacity(model.status == .loading ? 0.45 : 1)
                pageFooter
            }
            .frame(width: width, height: height)
            .onChange(of: model.selection) { _, index in
                guard let index else { return }
                proxy.scrollTo(index, anchor: nil)
            }
            .onChange(of: model.shownQuery) { _, _ in
                proxy.scrollTo(0, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private var pageFooter: some View {
        if model.isLoadingMore {
            ProgressView()
                .controlSize(.small)
                .padding(.bottom, 10)
                .accessibilityLabel("Loading more GIFs")
        } else if let error = model.moreError {
            HStack(spacing: 8) {
                Text(GIFMessage(error: error, setup: model.setup).title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                Button("Try Again") { model.retry() }
                    .buttonStyle(ThemedButtonStyle())
                    .themedDisabled(model.retryAvailableAt != nil)
            }
            .padding(.bottom, 10)
        }
    }
}

/// One result: a placeholder (the service's blurred preview, or a plain
/// tile), then the still, then, while in view and when animation is on,
/// the animated preview playing.
struct GIFResultCell: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let result: GIFSearchResult
    let size: CGSize
    let animates: Bool
    let isSelected: Bool
    let services: GIFSearchServices
    let onVisible: () -> Void
    let onPick: () -> Void

    @State private var isVisible = false
    @State private var hovering = false
    @State private var still: CGImage?
    @State private var player: AnimatedImagePlayer?
    @State private var placeholder: NSImage?

    private struct LoadKey: Equatable {
        var id: String
        var visible: Bool
        var animates: Bool
    }

    var body: some View {
        Button(action: onPick) {
            ZStack {
                Rectangle().fill(theme[ThemeKey.chatHoverBackground])
                if let placeholder, still == nil {
                    Image(nsImage: placeholder).resizable().scaledToFill()
                }
                if let still {
                    Image(decorative: still, scale: displayScale).resizable().scaledToFill()
                }
                if let player, player.hasFrame {
                    AnimatedFrameView(player: player, gravity: .resizeAspectFill)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme[ThemeKey.focusBorder] : (hovering ? theme[ThemeKey.accent] : .clear),
                        lineWidth: isSelected ? 2 : 1.5
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onScrollVisibilityChange(threshold: 0.05) { visible in
            isVisible = visible
            if visible { onVisible() }
        }
        .task(id: loadKey) {
            await load(loadKey)
        }
        .onDisappear {
            player?.unload()
            player = nil
        }
        .help(result.accessibilityDescription)
        .accessibilityLabel(result.accessibilityDescription)
        .accessibilityHint("Adds the GIF to your message")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var loadKey: LoadKey {
        LoadKey(id: result.id, visible: isVisible, animates: animates && !reduceMotion)
    }

    /// Pixels the preview is drawn at: the cell filled, at the screen's scale.
    private var drawnPixels: (width: Int, longest: Int) {
        let aspect = max(0.1, result.aspectRatio)
        let cellAspect = size.width / max(1, size.height)
        let drawn = aspect > cellAspect
            ? CGSize(width: size.height * aspect, height: size.height)
            : CGSize(width: size.width, height: size.width / aspect)
        let scale = max(1, displayScale)
        return (Int((drawn.width * scale).rounded(.up)), Int((max(drawn.width, drawn.height) * scale).rounded(.up)))
    }

    private func load(_ key: LoadKey) async {
        if !key.visible || !key.animates {
            // Out of view (or animation turned off): stop, and let the
            // player (its frames and data) go.
            player?.unload()
            player = nil
            guard key.visible else { return }
        }
        if placeholder == nil, still == nil, let data = result.placeholder {
            placeholder = NSImage(data: data)
        }
        let pixels = drawnPixels
        if still == nil, let rendition = result.still(forPixelWidth: pixels.width) {
            still = try? await services.previewLoader.downsampledImage(rendition.url, maxPixelSize: pixels.longest, maxBytes: GIFSearchServices.maxPreviewBytes)
        }
        guard key.animates, !Task.isCancelled, player == nil,
              let rendition = result.animation(forPixelWidth: pixels.width),
              let loaded = try? await services.previewLoader.load(rendition.url, maxBytes: GIFSearchServices.maxPreviewBytes),
              loaded.isAnimated, !Task.isCancelled
        else { return }
        let player = AnimatedImagePlayer()
        // Its frames are kept after the first loop: a dozen cells play at once.
        player.keptFrameBudget = GIFSearchServices.keptFramesPerPreview
        player.load(loaded.data, frameCount: loaded.frameCount, maxPixelSize: pixels.longest)
        self.player = player
        services.previewStarted(player)
        player.play()
    }
}

/// What the GIFs tab says instead of results, and what it offers.
struct GIFMessage: Equatable {
    var systemImage: String
    var title: String
    var message: String?
    /// "Try Again".
    var offersRetry = false
    /// "Use Your Own Key in Settings" (or Open Settings).
    var settingsTitle: String?

    init(systemImage: String, title: String, message: String? = nil, offersRetry: Bool = false, settingsTitle: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.offersRetry = offersRetry
        self.settingsTitle = settingsTitle
    }

    static let ownKeyTitle = "Use Your Own Key in Settings"

    init(problem: GIFSearchSetup.Problem) {
        switch problem {
        case .noBuiltInKey:
            self.init(
                systemImage: "key",
                title: "GIFs aren't set up in this build",
                message: "Add your own free KLIPY key in Settings → Media to search GIFs.",
                settingsTitle: Self.ownKeyTitle
            )
        case .needsOwnKey:
            self.init(
                systemImage: "key",
                title: "GIPHY needs your own key",
                message: "Add a GIPHY API key in Settings → Media, or switch to KLIPY.",
                settingsTitle: "Open Settings"
            )
        }
    }

    init(error: GIFSearchError, setup: GIFSearchSetup) {
        let name = setup.provider.displayName
        let builtIn = setup.service == .klipy && !setup.usesOwnKey
        switch error {
        case .notConfigured:
            self.init(problem: setup.service == .klipy ? .noBuiltInKey : .needsOwnKey)
        case .offline:
            self.init(
                systemImage: "wifi.slash",
                title: "Can't reach \(name)",
                message: "Check your internet connection, then try again.",
                offersRetry: true
            )
        case .invalidKey:
            self.init(
                systemImage: "key.slash",
                title: builtIn ? "\(name) didn't accept Vela's key" : "\(name) didn't accept your key",
                message: builtIn ? "Use your own free KLIPY key in Settings → Media." : "Check the key in Settings → Media.",
                offersRetry: true,
                settingsTitle: builtIn ? Self.ownKeyTitle : "Check Your Key in Settings"
            )
        case .rateLimited:
            self.init(
                systemImage: "hourglass",
                title: "GIF search is busy right now",
                message: builtIn
                    ? "Try again in a few minutes, or use your own free KLIPY key."
                    : "Your key has reached its limit for now. Try again in a few minutes.",
                offersRetry: true,
                settingsTitle: builtIn ? Self.ownKeyTitle : nil
            )
        case .server(let status):
            self.init(
                systemImage: "exclamationmark.icloud",
                title: "\(name) isn't answering right now",
                message: "It reported a problem (error \(status)). Try again in a moment.",
                offersRetry: true
            )
        case .badResponse:
            self.init(
                systemImage: "exclamationmark.triangle",
                title: "\(name) sent an answer Vela can't read",
                message: "Try again in a moment.",
                offersRetry: true
            )
        }
    }
}

/// A message in place of results, with its buttons.
struct GIFMessageView: View {
    @Environment(\.theme) private var theme
    let message: GIFMessage
    /// Try Again is greyed out until then.
    var retryAvailableAt: Date?
    var onRetry: () -> Void = {}
    var onSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: message.systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                .accessibilityHidden(true)
            Text(message.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme[ThemeKey.popoverForeground])
                .multilineTextAlignment(.center)
            if let detail = message.message {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if message.offersRetry || message.settingsTitle != nil {
                HStack(spacing: 8) {
                    if message.offersRetry {
                        Button("Try Again", action: onRetry)
                            .buttonStyle(ThemedButtonStyle(prominent: message.settingsTitle == nil))
                            .themedDisabled(retryAvailableAt != nil)
                            .help(retryAvailableAt != nil ? "Available again in a minute" : "Search again")
                    }
                    if let settingsTitle = message.settingsTitle {
                        Button(settingsTitle, action: onSettings)
                            .buttonStyle(ThemedButtonStyle(prominent: !message.offersRetry))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
