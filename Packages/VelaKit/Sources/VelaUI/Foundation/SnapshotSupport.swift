// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaTheme

/// Demo-mode screenshots without screen-recording permission or a visible window:
///
///     Vela --demo --snapshot /tmp/shot.png [--size 1280x800] [--snapshot-delay 3] [--theme Lighter] [--preset tabbed]
///
/// The main UI is hosted in a transparent offscreen window (independent of
/// SwiftUI's scene restoration), rendered to a PNG after the delay, and the
/// app quits. Used by `scripts/demo-screenshot.sh`, CI and docs.
@MainActor
enum SnapshotSupport {
    static let arguments = ProcessInfo.processInfo.arguments

    static var outputPath: String? { value(after: "--snapshot") }

    static var isActive: Bool { outputPath != nil && arguments.contains("--demo") }

    private static var window: NSWindow?

    static func scheduleOffscreenCapture(app: AppModel, themeStore: ThemeStore, uiState: UIState) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                run(app: app, themeStore: themeStore, uiState: uiState)
            }
        }
    }

    private static func run(app: AppModel, themeStore: ThemeStore, uiState: UIState) {
        guard let path = outputPath else { return }
        let size = value(after: "--size").flatMap(parseSize) ?? CGSize(width: 1280, height: 800)
        let root = MainWindowView()
            .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, isPrimary: true)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: AnyView(root))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        // Far from any screen, so the real pointer can't trigger hover states.
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()
        self.window = window

        let delay = value(after: "--snapshot-delay").flatMap(Double.init) ?? 3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(window, to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    private static func capture(_ window: NSWindow, to url: URL) {
        // The theme frame includes the traffic-light buttons.
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            FileHandle.standardOutput.write(Data("snapshot: \(url.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error.localizedDescription)\n".utf8))
        }
    }

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func parseSize(_ text: String) -> CGSize? {
        let parts = text.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }
}
