// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import VelaCore
import VelaStore
import VelaTheme

/// Demo-mode screenshots without screen-recording permission or a visible window:
///
///     Vela --demo --snapshot /tmp/shot.png [--size 1280x800] [--snapshot-delay 3] [--theme Lighter] [--preset tabbed]
///     Vela --demo --snapshot /tmp/pane.png --settings-pane intelligence [--settings-scroll 400] [--size 820x640]
///     Vela --demo --snapshot /tmp/shot.png --theme Palenight --accent Cyan
///     Vela --demo --snapshot /tmp/shot.png --themes-dir /path/in/container --theme "My Theme"
///     Vela --demo --snapshot /tmp/editor.png --theme-editor "Palenight"
///     Vela --demo --snapshot /tmp/about.png --about [--size 440x560]
///     Vela --demo --snapshot /tmp/welcome.png --no-networks --theme Lighter
///
/// The main UI (or, with `--settings-pane <id>`, the Settings window on that
/// pane; ids are `SettingsPane` raw values; with `--theme-editor <theme>`,
/// the Theme Editor started from that theme; with `--about`, the About
/// window) is hosted in a transparent
/// offscreen window (independent of SwiftUI's scene restoration), rendered
/// to a PNG after the delay, and the app quits. `--settings-scroll <points>`
/// scrolls the pane down before the capture, and `--accent <name>` picks
/// one of the theme's accent swatches, as Settings → Appearance would.
/// `--no-networks` starts the demo without networks, so the main window
/// shows the welcome screen of a first launch, and `--no-selection` keeps
/// the networks but opens no conversation ("Pick a conversation").
/// Demo mode uses a temporary Themes folder (see `DemoArguments`), which
/// `--themes-dir` fills with copies of a folder's themes. Used by
/// `scripts/demo-screenshot.sh`, CI and docs.
@MainActor
enum SnapshotSupport {
    static let arguments = ProcessInfo.processInfo.arguments

    static var outputPath: String? { value(after: "--snapshot") }

    static var isActive: Bool { outputPath != nil && arguments.contains("--demo") }

    /// `--settings-pane <id>`: render this Settings pane instead of the main window.
    private static var settingsPaneID: String? { value(after: "--settings-pane") }

    private static var window: NSWindow?

    static func scheduleOffscreenCapture(app: AppModel, themeStore: ThemeStore, uiState: UIState, services: SceneServices) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                run(app: app, themeStore: themeStore, uiState: uiState, services: services)
            }
        }
    }

    private static func run(app: AppModel, themeStore: ThemeStore, uiState: UIState, services: SceneServices) {
        guard let path = outputPath else { return }
        // The main window starts these itself; a Settings pane on its own
        // (and --accent, which needs the theme list) can't wait for it.
        themeStore.start()
        app.start()
        if let accent = value(after: "--accent") {
            selectAccent(named: accent, app: app, themeStore: themeStore)
        }
        let content: AnyView
        let defaultSize: CGSize
        if let base = value(after: "--theme-editor") {
            if let info = themeStore.info(for: base) {
                ThemeEditorHandoff.shared.requestedBase = info
            } else {
                FileHandle.standardError.write(Data("snapshot: no theme called \"\(base)\"; the editor starts from the theme in use\n".utf8))
            }
            content = AnyView(
                ThemeEditorView()
                    .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: false)
            )
            defaultSize = CGSize(width: 760, height: 680)
        } else if arguments.contains("--about") {
            content = AnyView(
                AboutView()
                    .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: false)
            )
            defaultSize = CGSize(width: 440, height: 560)
        } else if let id = settingsPaneID {
            guard let pane = SettingsPane(rawValue: id) else {
                let ids = SettingsPane.allCases.map(\.rawValue).joined(separator: ", ")
                FileHandle.standardError.write(Data("snapshot failed: unknown settings pane \"\(id)\" (use one of: \(ids))\n".utf8))
                DemoScratch.removeOwn()
                exit(1)
            }
            content = AnyView(
                SettingsRootView(initialPane: pane)
                    .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: false)
            )
            defaultSize = CGSize(width: 820, height: 600)
        } else {
            content = AnyView(
                MainWindowView()
                    .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: services, isPrimary: true)
            )
            defaultSize = CGSize(width: 1280, height: 800)
        }
        let size = value(after: "--size").flatMap(parseSize) ?? defaultSize
        let hosting = NSHostingView(rootView: AnyView(content.frame(width: size.width, height: size.height)))
        let window = OffscreenWindow(
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
        // Far from any screen, so the real pointer can't trigger hover states
        // (OffscreenWindow keeps AppKit from moving it back onto a screen).
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()
        self.window = window

        let delay = value(after: "--snapshot-delay").flatMap(Double.init) ?? 3
        if let offset = value(after: "--settings-scroll").flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay - 1)) {
                scroll(window, down: offset)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(window, to: URL(fileURLWithPath: path))
            DemoScratch.removeOwn()
            exit(0)
        }
    }

    /// Switches the theme in use to its accent swatch called `name` ("Cyan",
    /// or "Default"), writing settings the way the accent picker does.
    private static func selectAccent(named name: String, app: AppModel, themeStore: ThemeStore) {
        let settings = app.settings
        let reference = settings[.appearanceFollowSystem] ? nil : settings[.appearanceTheme]
        guard let info = reference.flatMap(themeStore.info(for:)) ?? themeStore.currentInfo,
              let palette = AccentActions.palette(for: info, themeStore: themeStore)
        else { return }
        let matches = { (swatch: AccentSwatch) in
            swatch.name.caseInsensitiveCompare(name) == .orderedSame
                || (swatch.isDefault && name.caseInsensitiveCompare("Default") == .orderedSame)
        }
        guard let swatch = palette.swatches.first(where: matches) else {
            let names = palette.swatches.map(\.name).joined(separator: ", ")
            FileHandle.standardError.write(Data("snapshot: \(info.name) has no accent called \"\(name)\" (try: \(names))\n".utf8))
            return
        }
        AccentActions.select(swatch, in: palette, settings: settings)
    }

    /// Scrolls the outermost scroll view (a Settings pane's page) down by
    /// `offset` points, clamped to its content.
    private static func scroll(_ window: NSWindow, down offset: CGFloat) {
        guard let root = window.contentView else { return }
        root.layoutSubtreeIfNeeded()
        var queue: [NSView] = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scrollView = view as? NSScrollView, let document = scrollView.documentView {
                let clip = scrollView.contentView
                let maxOffset = max(0, document.frame.height - clip.bounds.height)
                let y = min(max(0, offset), maxOffset)
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: document.isFlipped ? y : maxOffset - y))
                scrollView.reflectScrolledClipView(clip)
                return
            }
            queue.append(contentsOf: view.subviews)
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

    /// AppKit moves a titled window onto a screen when it's ordered front,
    /// which would put this invisible window under the real pointer and let
    /// hover states (such as the message toolbar) into the shot. Keep the
    /// frame exactly where it's set instead.
    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
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
