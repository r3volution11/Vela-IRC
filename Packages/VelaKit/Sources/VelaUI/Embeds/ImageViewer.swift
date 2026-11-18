// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaMedia
import VelaTheme

/// What the full-size viewer shows.
struct ImageViewerItem {
    enum Media {
        case image(LoadedImage)
        /// A GIF site's MP4, looping and muted; its first frame shows until it plays.
        case loopingVideo(LoadedLoopingVideo, poster: CGImage?)
    }

    let linkURL: URL
    /// The image or video file's own URL.
    let mediaURL: URL
    let media: Media

    init(linkURL: URL, imageURL: URL, image: LoadedImage) {
        self.linkURL = linkURL
        self.mediaURL = imageURL
        self.media = .image(image)
    }

    init(linkURL: URL, videoURL: URL, video: LoadedLoopingVideo, poster: CGImage?) {
        self.linkURL = linkURL
        self.mediaURL = videoURL
        self.media = .loopingVideo(video, poster: poster)
    }

    var pixelSize: CGSize {
        switch media {
        case .image(let image): image.pixelSize
        case .loopingVideo(let video, _): video.pixelSize
        }
    }

    var byteCount: Int {
        switch media {
        case .image(let image): image.data.count
        case .loopingVideo(let video, _): video.byteCount
        }
    }

    var isAnimated: Bool {
        switch media {
        case .image(let image): image.isAnimated
        case .loopingVideo: true
        }
    }
}

/// Full-size image viewer: a borderless panel laid over the window it was
/// opened from, dimming it, with the image fitted in the middle.
/// Escape or a click outside the buttons closes it.
enum ImageViewer {
    private static var panel: ImageViewerPanel?
    private static var observers: [NSObjectProtocol] = []

    static func present(_ item: ImageViewerItem, theme: ResolvedTheme, reduceMotion: Bool) {
        dismiss(animated: false)
        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        let panel = ImageViewerPanel(
            contentRect: parent.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.onCancel = { dismiss() }

        let root = ImageViewerView(item: item, onClose: { dismiss() })
            .environment(\.theme, theme)
            .preferredColorScheme(theme.colorScheme)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.appearance = NSAppearance(named: theme.appearanceName)

        parent.addChildWindow(panel, ordered: .above)
        panel.setFrame(parent.frame, display: true)
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }
        self.panel = panel

        // Keep covering the parent as it resizes; close with it.
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: parent, queue: .main) { _ in
                MainActor.assumeIsolated { self.panel?.setFrame(parent.frame, display: true) }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { _ in
                MainActor.assumeIsolated { dismiss(animated: false) }
            },
        ]
        NSAccessibility.post(element: panel, notification: .windowCreated)
    }

    static func dismiss(animated: Bool = true) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let panel else { return }
        self.panel = nil
        closing.append(panel)
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { finishClosing() }
            }
        } else {
            finishClosing()
        }
    }

    /// Panels fading out.
    private static var closing: [ImageViewerPanel] = []

    private static func finishClosing() {
        for panel in closing {
            let parent = panel.parent
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            parent?.makeKey()
        }
        closing = []
    }
}

final class ImageViewerPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct ImageViewerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ImageViewerItem
    let onClose: () -> Void

    @State private var still: NSImage?
    @State private var player = AnimatedImagePlayer()
    /// A looping video's play state (an image's is the player's).
    @State private var videoPlaying = false
    @State private var copied = false

    var body: some View {
        ZStack {
            theme[ThemeKey.windowBackground].opacity(0.92)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                GeometryReader { proxy in
                    let size = fittedSize(in: proxy.size)
                    imageView
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: theme[ThemeKey.windowBackground].opacity(0.6), radius: 24, y: 8)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .onTapGesture(perform: onClose)
                }
                toolbar
            }
            .padding(.horizontal, 40)
            .padding(.top, 48)
            .padding(.bottom, 24)
        }
        .onAppear {
            switch item.media {
            case .image(let image):
                still = NSImage(data: image.data)
                if image.isAnimated {
                    player.load(image.data, frameCount: image.frameCount)
                    if !reduceMotion { player.play() }
                }
            case .loopingVideo(_, let poster):
                still = poster.map { NSImage(cgImage: $0, size: .zero) }
                videoPlaying = !reduceMotion
            }
        }
        .onDisappear { player.pause() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image viewer")
        .accessibilityAddTraits(.isModal)
    }

    private var isPlaying: Bool {
        if case .loopingVideo = item.media { return videoPlaying }
        return player.isPlaying
    }

    private func togglePlayback() {
        if case .loopingVideo = item.media {
            videoPlaying.toggle()
        } else {
            player.toggle()
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if case .loopingVideo(let video, _) = item.media {
            ZStack {
                if let still {
                    Image(nsImage: still).resizable().interpolation(.high)
                } else {
                    theme[ThemeKey.embedPlaceholderBackground]
                }
                LoopingVideoView(fileURL: video.fileURL, isPlaying: videoPlaying)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } else if let frame = player.frame {
            Image(decorative: frame, scale: 1).resizable().interpolation(.high)
        } else if let still {
            Image(nsImage: still).resizable().interpolation(.high)
        } else {
            theme[ThemeKey.embedPlaceholderBackground]
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(EmbedActions.displayName(item.linkURL))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme[ThemeKey.windowForeground])
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detailText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme[ThemeKey.chatSecondaryForeground])
                    .lineLimit(1)
            }
            .frame(maxWidth: 360, alignment: .leading)
            Spacer(minLength: 12)
            if item.isAnimated {
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    togglePlayback()
                }
                .buttonStyle(ThemedButtonStyle())
            }
            Button("Open in Browser", systemImage: "safari") {
                EmbedActions.open(item.linkURL)
                onClose()
            }
            .buttonStyle(ThemedButtonStyle())
            Button(copied ? "Copied" : copyTitle, systemImage: copied ? "checkmark" : "doc.on.doc") {
                switch item.media {
                case .image(let image): EmbedActions.copyImage(data: image.data, utType: image.utType)
                case .loopingVideo: EmbedActions.copy(item.linkURL)
                }
                copied = true
            }
            .buttonStyle(ThemedButtonStyle())
            .keyboardShortcut("c", modifiers: .command)
            Button("Close", systemImage: "xmark", action: onClose)
                .buttonStyle(ThemedButtonStyle(prominent: true))
                .keyboardShortcut(.cancelAction)
        }
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: 900)
    }

    /// A GIF site's video has nothing worth copying but its link.
    private var copyTitle: String {
        if case .loopingVideo = item.media { return "Copy Link" }
        return "Copy Image"
    }

    private var detailText: String {
        let size = item.pixelSize
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)
        return "\(Int(size.width)) × \(Int(size.height)) · \(bytes) · \(EmbedActions.displayHost(item.linkURL))"
    }

    /// The image's own size in points, scaled down to fit `available`.
    private func fittedSize(in available: CGSize) -> CGSize {
        let natural = item.pixelSize
        guard natural.width > 0, natural.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let scale = min(1, available.width / natural.width, available.height / natural.height)
        return CGSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded())
    }
}
