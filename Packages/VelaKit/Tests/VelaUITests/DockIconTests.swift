// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import ImageIO
import Observation
import Testing
import VelaStore
@testable import VelaUI

@MainActor
@Suite("Dock icon")
struct DockIconTests {
    static func makeSettings() -> SettingsStore {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "VelaUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "settings.json")
        return SettingsStore(fileURL: url, watchForChanges: false)
    }

    @Test func everyIconHasABundledRender() throws {
        for icon in AppIcon.allCases {
            let url = try #require(DockIcon.resourceURL(for: icon), "no render for \(icon)")
            #expect(url.lastPathComponent == "\(icon.rawValue).png")
            #expect(url.deletingLastPathComponent().lastPathComponent == "AppIcons")
            let image = try #require(DockIcon.image(for: icon), "can't load \(url.lastPathComponent)")
            // Square, on the macOS icon grid, big enough for a 128 pt Retina Dock tile.
            let rep = try #require(image.representations.first)
            #expect(rep.pixelsWide == rep.pixelsHigh)
            #expect(rep.pixelsWide >= 256)
            #expect(rep.hasAlpha)
        }
    }

    @Test func theStandardIconRestoresTheRealOne() {
        // nil makes the Dock show the compiled app icon, with its Dark,
        // Clear and Tinted styles.
        #expect(DockIcon.dockImage(for: .vela) == nil)
        for icon in AppIcon.allCases where icon != .vela {
            #expect(DockIcon.dockImage(for: icon) != nil, "\(icon)")
        }
    }

    @Test func titlesAndSummaries() {
        #expect(AppIcon.allCases.map(DockIcon.title) == ["Vela", "Midnight", "Graphite", "Sunrise", "Paper", "Vivid"])
        #expect(AppIcon.allCases.allSatisfy { !DockIcon.summary($0).isEmpty && !DockIcon.summary($0).hasSuffix(".") })
        #expect(Set(AppIcon.allCases.map(DockIcon.summary)).count == AppIcon.allCases.count)
    }

    @Test func nextCyclesThroughEveryIcon() {
        var icon = AppIcon.vela
        var seen: [AppIcon] = []
        for _ in AppIcon.allCases {
            seen.append(icon)
            icon = DockIcon.next(after: icon)
        }
        #expect(seen == AppIcon.allCases)
        #expect(icon == .vela, "wraps around")
    }

    @Test func controllerFollowsTheSettingAfterLaunch() async throws {
        let settings = Self.makeSettings()
        var shown: [NSImage?] = []
        let controller = DockIconController(settings: settings) { shown.append($0) }
        settings[.appearanceAppIcon] = .midnight
        controller.start()
        #expect(shown.isEmpty, "nothing touches the Dock before launch finishes")

        controller.didFinishLaunching()
        #expect(shown.count == 1)
        #expect(shown.last??.size == DockIcon.image(for: .midnight)?.size)
        #expect(controller.applied == .midnight)

        settings[.appearanceAppIcon] = .paper
        try await waitForApplied(.paper, controller)
        #expect(shown.count == 2)
        #expect(shown.last! === DockIcon.image(for: .paper))

        settings[.appearanceAppIcon] = .vela
        try await waitForApplied(.vela, controller)
        #expect(shown.count == 3)
        #expect(shown.last! == nil, "back to the real icon")

        // Setting the same value again leaves the Dock alone.
        controller.apply()
        #expect(shown.count == 3)
    }

    @Test func standardIconAtLaunchLeavesTheDockAlone() {
        let settings = Self.makeSettings()
        var calls = 0
        let controller = DockIconController(settings: settings) { _ in calls += 1 }
        controller.start()
        controller.didFinishLaunching()
        #expect(calls == 0)
        #expect(controller.applied == .vela)
    }

    @Test func paletteCommandsPickAndCycleIcons() throws {
        let settings = Self.makeSettings()
        var commands = VelaCommandCatalog.appIconCommands(settings)
        #expect(commands.map(\.paletteTitle) == [
            "Appearance: Next App Icon",
            "Appearance: App Icon: Vela",
            "Appearance: App Icon: Midnight",
            "Appearance: App Icon: Graphite",
            "Appearance: App Icon: Sunrise",
            "Appearance: App Icon: Paper",
            "Appearance: App Icon: Vivid",
        ])
        #expect(Set(commands.map(\.id)).count == commands.count)
        #expect(commands.dropFirst().map(\.isChecked) == [true, false, false, false, false, false])

        commands[0].perform()
        #expect(settings[.appearanceAppIcon] == .midnight)
        commands = VelaCommandCatalog.appIconCommands(settings)
        commands[0].perform()
        #expect(settings[.appearanceAppIcon] == .graphite)

        commands = VelaCommandCatalog.appIconCommands(settings)
        commands[6].perform()
        #expect(settings[.appearanceAppIcon] == .vivid)
        commands = VelaCommandCatalog.appIconCommands(settings)
        #expect(commands.last?.isChecked == true)
        commands[0].perform()
        #expect(settings[.appearanceAppIcon] == .vela, "Next wraps around to Vela")
    }

    private func waitForApplied(_ icon: AppIcon, _ controller: DockIconController) async throws {
        for _ in 0..<200 where controller.applied != icon {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.applied == icon)
    }
}

// MARK: - Composition: icon × offline mark

@MainActor
@Suite("Dock icon composition")
struct DockIconCompositionTests {
    /// The standard icon to draw on: the bundled render (a test runner's
    /// own icon isn't Vela's).
    private let standard = { DockIcon.image(for: .vela)! }

    @Test(arguments: [false, true])
    func onlyTheStandardIconAloneNeedsNoImage(offlineMark: Bool) {
        for icon in AppIcon.allCases {
            let content = DockTileContent(icon: icon, offlineMark: offlineMark)
            let expected = icon != .vela || offlineMark
            #expect(content.needsImage == expected, "\(content)")
            #expect((DockIcon.dockImage(for: content, standardIcon: standard) != nil) == expected, "\(content)")
        }
    }

    @Test func anAlternateAloneIsItsRender() {
        let content = DockTileContent(icon: .sunrise)
        #expect(DockIcon.dockImage(for: content, standardIcon: standard) === DockIcon.image(for: .sunrise))
    }

    @Test func theStandardIconIsDrawnOnOnlyWhenNeeded() {
        var drawnOn = 0
        let standard: () -> NSImage = {
            drawnOn += 1
            return DockIcon.image(for: .vela)!
        }
        _ = DockIcon.dockImage(for: DockTileContent(), standardIcon: standard)
        _ = DockIcon.dockImage(for: DockTileContent(icon: .paper, offlineMark: true), standardIcon: standard)
        #expect(drawnOn == 0)
        _ = DockIcon.dockImage(for: DockTileContent(offlineMark: true), standardIcon: standard)
        #expect(drawnOn == 1)
    }

    /// The sRGB color at `point` (bottom-left origin) of a composed image.
    private func color(_ image: NSImage?, at point: NSPoint) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let rep = try #require(image?.representations.first as? NSBitmapImageRep)
        #expect(rep.pixelsWide == DockIcon.composedSize && rep.pixelsHigh == DockIcon.composedSize)
        let color = try #require(rep.colorAt(x: Int(point.x), y: rep.pixelsHigh - 1 - Int(point.y))?.usingColorSpace(.sRGB))
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }

    private var canvas: NSRect { NSRect(x: 0, y: 0, width: DockIcon.composedSize, height: DockIcon.composedSize) }

    /// A point on the mark's amber face, above its glyph.
    private var markFace: NSPoint {
        let mark = DockIcon.offlineMarkFrame(in: canvas)
        return NSPoint(x: mark.midX, y: mark.midY + mark.height * 0.3)
    }

    private func isAmber(_ c: (red: CGFloat, green: CGFloat, blue: CGFloat)) -> Bool {
        c.red > 0.9 && c.green > 0.62 && c.green < 0.85 && c.blue < 0.35
    }

    @Test func theMarkSitsBottomLeftOppositeTheBadge() {
        let mark = DockIcon.offlineMarkFrame(in: canvas)
        #expect(mark.midX < canvas.width * 0.3)
        #expect(mark.midY < canvas.height * 0.3)
        #expect(canvas.contains(mark), "inside the tile, with room for its shadow")
        #expect(mark.width > canvas.width * 0.25 && mark.width < canvas.width * 0.4)
    }

    @Test func theMarkIsAmberWithADarkGlyph() throws {
        for icon in AppIcon.allCases {
            let image = DockIcon.dockImage(for: DockTileContent(icon: icon, offlineMark: true), standardIcon: standard)
            #expect(isAmber(try color(image, at: markFace)), "\(icon)")
            // The unplugged cable: a dark plug on the left, and a gap
            // between it and the socket at the center.
            let mark = DockIcon.offlineMarkFrame(in: canvas)
            let unit = mark.width * 0.87 * 0.06
            let plug = try color(image, at: NSPoint(x: mark.midX - 2.3 * unit, y: mark.midY))
            #expect(plug.red < 0.4 && plug.green < 0.3, "\(icon): the plug")
            #expect(isAmber(try color(image, at: NSPoint(x: mark.midX + 0.5 * unit, y: mark.midY))), "\(icon): the gap")
        }
    }

    /// The standard icon drawn under the mark is the bundle's own flat
    /// copy (`CFBundleIconFile`), read from the file: Icon Services once
    /// handed Vela Dev a generic document icon instead.
    @Test func theStandardIconComesFromTheBundlesIcns() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DockIconTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundleURL = folder.appendingPathComponent("Test.app")
        let resources = bundleURL.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "test.dock-icon", "CFBundleIconFile": "TestIcon", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))

        // A solid coral 256 px icon, written as an .icns.
        let coral = DockIcon.rasterized(size: 256) { rect in
            NSColor(srgbRed: 0.95, green: 0.4, blue: 0.48, alpha: 1).setFill()
            rect.fill()
        }
        let cgImage = try #require(coral.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let destination = try #require(CGImageDestinationCreateWithURL(
            resources.appendingPathComponent("TestIcon.icns") as CFURL, "com.apple.icns" as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))

        let bundle = try #require(Bundle(url: bundleURL))
        let icon = DockIcon.bundleIcon(in: bundle)
        #expect(icon.representations.allSatisfy { $0 is NSBitmapImageRep }, "read from the file, not Icon Services")
        let marked = DockIcon.dockImage(for: DockTileContent(offlineMark: true), standardIcon: { icon })
        let center = try color(marked, at: NSPoint(x: canvas.midX, y: canvas.midY))
        #expect(center.red > 0.9 && center.green < 0.5 && center.blue > 0.4 && center.blue < 0.6, "the coral icon, under the mark")
        #expect(isAmber(try color(marked, at: markFace)))
    }

    // MARK: Controller

    @Test func controllerAddsAndRemovesTheMark() async throws {
        let settings = DockIconTests.makeSettings()
        let offline = OfflineFlag()
        var shown: [NSImage?] = []
        let controller = DockIconController(settings: settings, setImage: { shown.append($0) }, isOffline: { offline.value })
        controller.start()
        controller.didFinishLaunching()
        #expect(shown.isEmpty, "the standard icon and nothing to draw: the Dock is left alone")

        offline.value = true
        try await waitFor(controller) { $0.appliedContent.offlineMark }
        #expect(shown.count == 1)
        #expect(shown.last! != nil)

        settings[.appearanceAppIcon] = .sunrise
        try await waitFor(controller) { $0.applied == .sunrise }
        #expect(controller.appliedContent == DockTileContent(icon: .sunrise, offlineMark: true))
        #expect(shown.count == 2)
        #expect(shown.last! !== DockIcon.image(for: .sunrise), "drawn with the mark")

        offline.value = false
        try await waitFor(controller) { !$0.appliedContent.offlineMark }
        #expect(shown.last! === DockIcon.image(for: .sunrise), "the plain alternate again")

        settings[.appearanceAppIcon] = .vela
        try await waitFor(controller) { $0.applied == .vela }
        #expect(shown.last! == nil, "back to the real icon")
        #expect(shown.count == 4)
    }

    private func waitFor(_ controller: DockIconController, _ condition: (DockIconController) -> Bool) async throws {
        for _ in 0..<200 where !condition(controller) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition(controller))
    }

    // MARK: Palette and settings editor

    @Test func paletteTogglesTheBadge() {
        let settings = DockIconTests.makeSettings()
        var commands = VelaCommandCatalog.dockCommands(settings)
        #expect(commands.map(\.paletteTitle) == ["Notifications: Show Dock Badge"])
        #expect(commands.first?.isChecked == true)
        commands[0].perform()
        #expect(settings[.dockShowBadge] == false)
        commands = VelaCommandCatalog.dockCommands(settings)
        #expect(commands.first?.isChecked == false)
        commands[0].perform()
        #expect(settings[.dockShowBadge] == true)
    }

    @Test func settingsEditorOffersTheListChoices() {
        func kind(_ key: String) -> SettingControlKind {
            SettingControlKind(SettingsEditorEntry(key: key, descriptor: SettingsCatalog.descriptor(forKey: key), value: nil))
        }
        #expect(kind("dock.badgeCounts") == .enumList(["mentions", "privateMessages", "channels"]))
        #expect(kind("dock.bounceFor") == .enumList(["mentions", "privateMessages"]))
        #expect(kind("dock.badgeCounts").isWide)
        #expect(kind("dock.badgeStyle") == .menu(["capped", "exact", "dot"]))
        #expect(kind("dock.showOffline") == .toggle)

        let allowed = ["mentions", "privateMessages", "channels"]
        #expect(SettingsEditorRow.resolveEnumValue("channels", allowed: allowed) == "channels")
        #expect(SettingsEditorRow.resolveEnumValue(" PrivateMessages ", allowed: allowed) == "privateMessages")
        #expect(SettingsEditorRow.resolveEnumValue("all channel messages", allowed: allowed) == "channels")
        #expect(SettingsEditorRow.resolveEnumValue("everything", allowed: allowed) == nil)
    }
}

/// An observable switch standing in for `AppModel.showsOfflineMark`.
@Observable
@MainActor
private final class OfflineFlag {
    var value = false
}
