// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Observation
import VelaStore

/// What the Dock tile shows: the chosen icon (`appearance.appIcon`), the
/// "DEV" band of development builds and the offline mark
/// (`dock.showOffline`). ``DockIconController`` keeps the Dock in step with it.
struct DockTileContent: Equatable {
    var icon: AppIcon = .vela
    /// The orange "DEV" band across the bottom (Vela Dev builds).
    var devBand = false
    /// The amber offline mark in the bottom-left corner.
    var offlineMark = false

    /// Whether the Dock needs a drawn image. Without one it shows the
    /// app's own icon (`applicationIconImage = nil`), with its system styling.
    var needsImage: Bool { icon != .vela || devBand || offlineMark }
}

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

    /// What to give `NSApplication.applicationIconImage` for `content`:
    /// `nil` (the real app icon) when there's nothing to draw, an
    /// alternate's render when that's all, otherwise the icon with the DEV
    /// band and the offline mark drawn on it.
    ///
    /// - Parameter standardIcon: The picture of the standard icon to draw
    ///   on when `content.icon` is `.vela`: by default the app's own icon,
    ///   as Finder shows it (``bundleIcon()``); the bundled render in tests.
    static func dockImage(for content: DockTileContent, standardIcon: (() -> NSImage)? = nil) -> NSImage? {
        guard content.needsImage else { return nil }
        let base = dockImage(for: content.icon) ?? standardIcon?() ?? bundleIcon()
        guard content.devBand || content.offlineMark else { return base }
        return composed(base, devBand: content.devBand, offlineMark: content.offlineMark)
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

    // MARK: Drawing

    /// The side of composed Dock images, in pixels: twice what the largest
    /// Dock icon (128 points, 256 pixels on a Retina display) needs, so
    /// the mark and band stay crisp when scaled down.
    static let composedSize = 512

    /// `image` with the DEV band and the offline mark drawn on it, as a
    /// bitmap (drawn once, here, rather than whenever AppKit draws it).
    static func composed(_ image: NSImage, devBand: Bool, offlineMark: Bool) -> NSImage {
        rasterized(size: composedSize) { rect in
            image.draw(in: rect)
            if devBand { drawDevBand(in: rect, textClearOf: offlineMark ? offlineMarkFrame(in: rect) : nil) }
            if offlineMark { drawOfflineMark(in: rect) }
        }
    }

    /// The icon body inside the macOS icon grid's margins.
    nonisolated static func iconBody(in rect: NSRect) -> NSRect {
        rect.insetBy(dx: rect.width * 0.098, dy: rect.height * 0.098)
    }

    /// An orange "DEV" band across the bottom, so a development build is
    /// easy to tell apart in the Dock and app switcher. With `mark` (the
    /// offline mark's frame), the text centers in the band beside it.
    nonisolated static func drawDevBand(in rect: NSRect, textClearOf mark: NSRect? = nil) {
        let body = iconBody(in: rect)
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
        let left = max(band.minX, mark?.maxX ?? band.minX)
        let centerX = (left + band.maxX) / 2
        text.draw(at: NSPoint(x: centerX - textSize.width / 2, y: band.midY - textSize.height / 2))
    }

    /// Where the offline mark sits in `rect`: a disc on the icon's
    /// bottom-left corner, opposite the badge macOS draws top right.
    nonisolated static func offlineMarkFrame(in rect: NSRect) -> NSRect {
        let body = iconBody(in: rect)
        let diameter = rect.width * 0.31
        let center = NSPoint(x: body.minX + diameter * 0.36, y: body.minY + diameter * 0.36)
        return NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }

    /// Amber, not red, so it never reads as a count; a light ring and a
    /// soft shadow set it apart from any icon, the DEV band and light or
    /// dark wallpapers.
    nonisolated static var offlineMarkTop: NSColor { NSColor(srgbRed: 1.0, green: 0.80, blue: 0.30, alpha: 1) }
    nonisolated static var offlineMarkBottom: NSColor { NSColor(srgbRed: 0.96, green: 0.62, blue: 0.04, alpha: 1) }
    nonisolated static var offlineMarkGlyph: NSColor { NSColor(srgbRed: 0.22, green: 0.13, blue: 0.0, alpha: 1) }

    /// The offline mark: an amber disc with an unplugged cable (a plug and
    /// its socket, apart) in the bottom-left corner. Drawn in `rect`, the
    /// whole icon; it fills `offlineMarkFrame(in:)`.
    nonisolated static func drawOfflineMark(in rect: NSRect) {
        let disc = offlineMarkFrame(in: rect)
        let diameter = disc.width
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = diameter * 0.08
        shadow.shadowOffset = NSSize(width: 0, height: -diameter * 0.03)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: disc).fill()
        NSGraphicsContext.restoreGraphicsState()

        let face = disc.insetBy(dx: diameter * 0.065, dy: diameter * 0.065)
        NSGradient(starting: offlineMarkTop, ending: offlineMarkBottom)?.draw(in: NSBezierPath(ovalIn: face), angle: -90)
        drawUnpluggedCable(center: NSPoint(x: disc.midX, y: disc.midY), unit: face.width * 0.06)
    }

    /// A cable's plug (left, prongs out) and its socket (right), apart:
    /// about 10.4 × 3.4 `unit`s, centered on `center`. Bold enough to read
    /// as a broken line at the smallest Dock size.
    nonisolated private static func drawUnpluggedCable(center: NSPoint, unit u: CGFloat) {
        offlineMarkGlyph.setFill()
        offlineMarkGlyph.setStroke()
        func at(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: center.x + x * u, y: center.y + y * u) }
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) {
            let rect = NSRect(origin: at(x, y), size: NSSize(width: width * u, height: height * u))
            NSBezierPath(roundedRect: rect, xRadius: radius * u, yRadius: radius * u).fill()
        }
        let cords = NSBezierPath()
        cords.move(to: at(-5.2, 0))
        cords.line(to: at(-3.2, 0))
        cords.move(to: at(3.2, 0))
        cords.line(to: at(5.2, 0))
        cords.lineWidth = 1.3 * u
        cords.lineCapStyle = .round
        cords.stroke()
        box(-3.4, -1.7, 2.2, 3.4, radius: 0.7)  // plug
        box(-1.5, 0.55, 1.4, 0.65, radius: 0.3)  // prongs
        box(-1.5, -1.2, 1.4, 0.65, radius: 0.3)
        box(1.2, -1.7, 2.2, 3.4, radius: 0.7)  // socket
    }

    /// A square sRGB bitmap of `size` pixels, drawn by `draw` right away.
    static func rasterized(size: Int, _ draw: @escaping (NSRect) -> Void) -> NSImage {
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )?.retagging(with: .sRGB), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            // Not expected; draw when AppKit draws it instead.
            return NSImage(size: rect.size, flipped: false) { rect in
                draw(rect)
                return true
            }
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        draw(rect)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    /// `icon` with the offline mark, for the preview in Settings →
    /// Notifications. Drawn on the bundled render, once per icon.
    static func offlineMarkPreview(for icon: AppIcon) -> NSImage? {
        if let cached = offlineMarkPreviews[icon] { return cached }
        guard let base = image(for: icon) else { return nil }
        let preview = composed(base, devBand: false, offlineMark: true)
        offlineMarkPreviews[icon] = preview
        return preview
    }

    private static var offlineMarkPreviews: [AppIcon: NSImage] = [:]

    /// The app's own icon, as Finder shows it.
    static func bundleIcon() -> NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

/// Keeps the Dock tile in step with ``DockTileContent``: the chosen icon
/// (`appearance.appIcon`), the DEV band of development builds and the
/// offline mark (`AppModel.showsOfflineMark`). It's the one place that sets
/// `NSApplication.applicationIconImage`: once Vela has finished launching,
/// and whenever one of them changes after that (in Settings, the command
/// palette or settings.json, or a network going offline), with or without a
/// window open. It sets `nil`, the real icon with its system styling,
/// whenever there's nothing to draw.
///
/// Made once per process by `AppInstances`, and never for snapshot runs
/// (`--demo --snapshot`), which leave the Dock alone.
@MainActor
final class DockIconController {
    private let settings: SettingsStore
    private let setImage: (NSImage?) -> Void
    /// Development builds always band the Dock icon "DEV".
    private let isDevBuild: Bool
    /// Whether to draw the offline mark. Observable.
    private let isOffline: () -> Bool
    /// What the Dock shows now. It starts as the real icon.
    private(set) var appliedContent = DockTileContent()
    private var isLaunched = false
    private var launchObserver: (any NSObjectProtocol)?

    /// The icon the Dock shows now.
    var applied: AppIcon { appliedContent.icon }

    /// - Parameters:
    ///   - setImage: Sets the Dock tile's image; `nil` restores the app's
    ///     own icon. Tests pass a recorder.
    ///   - isOffline: Whether to draw the offline mark; read inside
    ///     observation tracking, so an observable value is followed.
    init(
        settings: SettingsStore,
        isDevBuild: Bool = DockIcon.isDevBuild,
        setImage: @escaping (NSImage?) -> Void = { NSApplication.shared.applicationIconImage = $0 },
        isOffline: @escaping () -> Bool = { false }
    ) {
        self.settings = settings
        self.isDevBuild = isDevBuild
        self.isOffline = isOffline
        self.setImage = setImage
    }

    /// What the Dock should show now.
    var content: DockTileContent {
        DockTileContent(icon: settings[.appearanceAppIcon], devBand: isDevBuild, offlineMark: isOffline())
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

    /// Shows what the Dock should, if it doesn't already.
    func apply() {
        guard isLaunched else { return }
        let content = self.content
        guard content != appliedContent else { return }
        setImage(DockIcon.dockImage(for: content))
        appliedContent = content
    }

    private func observe() {
        withObservationTracking {
            _ = settings[.appearanceAppIcon]
            _ = isOffline()
        } onChange: { [weak self] in
            // Runs before the change lands; act on it right after.
            Task { @MainActor in
                self?.apply()
                self?.observe()
            }
        }
    }
}
