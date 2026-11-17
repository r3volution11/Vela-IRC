// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Testing
import VelaStore
@testable import VelaUI

@MainActor
@Suite("Dock icon")
struct DockIconTests {
    private func makeSettings() -> SettingsStore {
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
        let settings = makeSettings()
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
        let settings = makeSettings()
        var calls = 0
        let controller = DockIconController(settings: settings) { _ in calls += 1 }
        controller.start()
        controller.didFinishLaunching()
        #expect(calls == 0)
        #expect(controller.applied == .vela)
    }

    @Test func paletteCommandsPickAndCycleIcons() throws {
        let settings = makeSettings()
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
