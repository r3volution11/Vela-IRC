// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import VelaStore

/// The Dock icon choices (`appearance.appIcon`) and their images.
///
/// macOS has no alternate-icon API for Mac apps, and a sandboxed app can't
/// change its own (signed, read-only) bundle, so the choice reaches only the
/// Dock tile and the app switcher, through
/// `NSApplication.applicationIconImage`, and only while Vela runs. Finder,
/// Spotlight and the Apps list keep the bundle's icon, which follows the
/// Mac's Icon & widget style (Default, Dark, Clear or Tinted).
///
/// Each choice is bundled as a flat 256 px render on the macOS icon grid
/// (margins and shadow included), written by design/app-icon/build.sh. The
/// Dock never gets the `.vela` render: `nil` restores the compiled app icon
/// with its system styling. The picker uses it as a thumbnail.
enum DockIcon {
    /// The picker's and palette's name: "Vela", "Midnight", …
    static func title(_ icon: AppIcon) -> String {
        SettingsMetadata.enumLabel(icon.rawValue)
    }

    /// A short description for the picker and VoiceOver, without a period.
    static func summary(_ icon: AppIcon) -> String {
        switch icon {
        case .vela: "The standard icon: navy, with a cyan V"
        case .midnight: "Near-black, with a pale ice V"
        case .graphite: "Charcoal, with a silver V"
        case .sunrise: "Deep plum, with a peach-to-coral V and a warm star"
        case .paper: "White, with a deep blue V and star"
        case .vivid: "Bright blue, with a white V"
        }
    }

    /// Where the Dock-icon limit is explained, in Settings and the docs.
    static let note = "Changes the icon in the Dock and app switcher while Vela is open. Finder and Spotlight show the standard icon, which follows your Icon & widget style."

    /// The bundled render of `icon`. Every choice has one, `.vela` included.
    static func resourceURL(for icon: AppIcon, in bundle: Bundle = .module) -> URL? {
        bundle.url(forResource: icon.rawValue, withExtension: "png", subdirectory: "AppIcons")
    }

    /// The picker's thumbnail of `icon`.
    static func image(for icon: AppIcon) -> NSImage? {
        if let cached = images[icon] { return cached }
        guard let url = resourceURL(for: icon), let image = NSImage(contentsOf: url) else { return nil }
        images[icon] = image
        return image
    }

    /// What to give `NSApplication.applicationIconImage`: the render for an
    /// alternate, `nil` (the real app icon) for `.vela`.
    static func dockImage(for icon: AppIcon) -> NSImage? {
        icon == .vela ? nil : image(for: icon)
    }

    /// The choice after `icon`, wrapping around to Vela.
    static func next(after icon: AppIcon) -> AppIcon {
        let all = AppIcon.allCases
        let index = all.firstIndex(of: icon) ?? all.startIndex
        let next = all.index(after: index)
        return next == all.endIndex ? all[all.startIndex] : all[next]
    }

    private static var images: [AppIcon: NSImage] = [:]

    // MARK: Development builds

    /// True for "Vela Dev" (Debug builds, bundle id ending in `.dev`), which
    /// run beside the release app with their own data.
    static var isDevBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    }

    /// `image` with an orange "DEV" band across the bottom, so a development
    /// build is easy to tell apart in the Dock and app switcher.
    static func devBadged(_ image: NSImage) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            // The icon body sits inside the macOS icon grid's margins.
            let body = rect.insetBy(dx: rect.width * 0.098, dy: rect.height * 0.098)
            let band = NSRect(x: body.minX, y: body.minY + body.height * 0.06, width: body.width, height: body.height * 0.22)
            NSColor(srgbRed: 1.0, green: 0.55, blue: 0.16, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: band, xRadius: band.height * 0.18, yRadius: band.height * 0.18).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: band.height * 0.62, weight: .heavy),
                .foregroundColor: NSColor.white,
                .kern: band.height * 0.06,
            ]
            let text = NSAttributedString(string: "DEV", attributes: attributes)
            let textSize = text.size()
            text.draw(at: NSPoint(x: band.midX - textSize.width / 2, y: band.midY - textSize.height / 2))
            return true
        }
    }

    /// The app's own icon, as Finder shows it.
    static func bundleIcon() -> NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

/// Keeps the Dock tile in step with `appearance.appIcon`: once Vela has
/// finished launching, and whenever the setting changes after that (in
/// Settings, the command palette or settings.json), with or without a
/// window open.
///
/// Made once per process by `AppInstances`, and never for snapshot runs
/// (`--demo --snapshot`), which leave the Dock alone.
@MainActor
final class DockIconController {
    private let settings: SettingsStore
    private let setImage: (NSImage?) -> Void
    /// What the Dock shows now. It starts as the real icon.
    private(set) var applied: AppIcon = .vela
    private var isLaunched = false
    private var launchObserver: (any NSObjectProtocol)?

    /// - Parameter setImage: Sets the Dock tile's image; `nil` restores the
    ///   app's own icon. Tests pass a recorder.
    /// Development builds always badge the Dock icon "DEV".
    private let isDevBuild: Bool
    private var devBadgeShown = false

    init(
        settings: SettingsStore,
        isDevBuild: Bool = DockIcon.isDevBuild,
        setImage: @escaping (NSImage?) -> Void = { NSApplication.shared.applicationIconImage = $0 }
    ) {
        self.settings = settings
        self.isDevBuild = isDevBuild
        self.setImage = setImage
    }

    func start() {
        observe()
        // Touch NSApp only once AppKit has finished launching: it sets up
        // the Dock tile while it launches.
        if (NSApp as NSApplication?)?.isRunning == true {
            didFinishLaunching()
        } else {
            launchObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.didFinishLaunching() }
            }
        }
    }

    func didFinishLaunching() {
        isLaunched = true
        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        apply()
    }

    /// Shows the chosen icon in the Dock, if it isn't already.
    func apply() {
        guard isLaunched else { return }
        let icon = settings[.appearanceAppIcon]
        if isDevBuild {
            guard icon != applied || !devBadgeShown else { return }
            setImage(DockIcon.devBadged(DockIcon.dockImage(for: icon) ?? DockIcon.bundleIcon()))
            devBadgeShown = true
            applied = icon
            return
        }
        guard icon != applied else { return }
        setImage(DockIcon.dockImage(for: icon))
        applied = icon
    }

    private func observe() {
        withObservationTracking {
            _ = settings[.appearanceAppIcon]
        } onChange: { [weak self] in
            // Runs before the change lands; act on it right after.
            Task { @MainActor in
                self?.apply()
                self?.observe()
            }
        }
    }
}
