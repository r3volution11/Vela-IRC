// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaStore
import VelaTheme
@testable import VelaUI

extension LinkSelectionTests {
    /// The About window and Settings → Updates, hosted in offscreen windows
    /// with a fake updater, driven as VoiceOver would.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Updates in the About window and Settings", .serialized)
    struct UpdatesWindowTests {
        private final class Hosted {
            let window: NSWindow
            init(window: NSWindow) { self.window = window }
            func close() {
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        private func host(_ view: some View, app: AppModel, updater: any AppUpdater, size: CGSize) async throws -> Hosted {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let services = SceneServices(intelligence: .demo(), updates: AppUpdates(updater: updater))
            let content = view
                .velaEnvironment(
                    app: app,
                    themeStore: ThemeStore(userThemesDirectory: root.appendingPathComponent("Themes")),
                    uiState: UIState(),
                    services: services,
                    isPrimary: false
                )
                .frame(width: size.width, height: size.height)
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content)
            try await settle(window)
            return Hosted(window: window)
        }

        private func settle(_ window: NSWindow) async throws {
            try await Task.sleep(for: .milliseconds(150))
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }

        /// Every accessibility element under `window`, with VoiceOver's
        /// view of SwiftUI turned on while it looks.
        private func elements(in window: NSWindow) -> [AnyObject] {
            let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
            NSApplication.shared.perform(enhancedInterface, with: NSNumber(value: true))
            defer { NSApplication.shared.perform(enhancedInterface, with: NSNumber(value: false)) }
            var found: [AnyObject] = []
            func walk(_ object: AnyObject, depth: Int) {
                guard depth < 40 else { return }
                found.append(object)
                for child in (object.accessibilityChildren?() ?? nil) ?? [] {
                    walk(child as AnyObject, depth: depth + 1)
                }
            }
            walk(window, depth: 0)
            return found
        }

        private func element(labeled label: String, in window: NSWindow) -> AnyObject? {
            elements(in: window).first { ($0.accessibilityLabel?() ?? nil) == label }
        }

        /// All the text VoiceOver reads in `window`: labels and values.
        private func texts(in window: NSWindow) -> [String] {
            elements(in: window).flatMap { object -> [String] in
                let label = (object.accessibilityLabel?() ?? nil) ?? ""
                let raw: Any?? = object.accessibilityValue?()
                // Selectable text gives its value as an attributed string.
                let value = (raw ?? nil) as? String ?? ((raw ?? nil) as? NSAttributedString)?.string ?? ""
                return [label, value].filter { !$0.isEmpty }
            }
        }

        private func isEnabled(_ object: AnyObject?) -> Bool {
            object?.isAccessibilityEnabled?() ?? false
        }

        // MARK: About

        @Test func aboutShowsTheStatusAndChecks() async throws {
            let app = AppModel.demo()
            let updater = FakeUpdater()
            updater.status = .upToDate
            let hosted = try await host(AboutView(), app: app, updater: updater, size: CGSize(width: 440, height: 620))
            defer { hosted.close() }

            let all = texts(in: hosted.window)
            #expect(all.contains { $0.contains("Vela is up to date.") }, "\(all)")
            #expect(all.contains { $0.hasPrefix("Version ") })
            #expect(all.contains("Vela was made with the help of AI."))
            for link in ["velairc.app", "What's New", "License", "Acknowledgements"] {
                #expect(element(labeled: link, in: hosted.window) != nil, "\(link) link")
            }

            let check = try #require(element(labeled: "Check for Updates", in: hosted.window))
            #expect(isEnabled(check))
            #expect(check.accessibilityPerformPress?() == true)
            #expect(updater.events == ["check"])

            // The status line follows the updater.
            updater.status = .available(version: "1.2.0")
            try await settle(hosted.window)
            #expect(texts(in: hosted.window).contains { $0.contains("Version 1.2.0 is available.") })
        }

        @Test func aboutSwitchWritesTheSetting() async throws {
            let app = AppModel.demo()
            #expect(app.settings[.updatesCheckAutomatically])
            let hosted = try await host(AboutView(), app: app, updater: FakeUpdater(), size: CGSize(width: 440, height: 620))
            defer { hosted.close() }

            let toggle = try #require(element(labeled: "Check for updates automatically", in: hosted.window))
            #expect(isEnabled(toggle))
            #expect(toggle.accessibilityPerformPress?() == true)
            try await settle(hosted.window)
            #expect(!app.settings[.updatesCheckAutomatically])
        }

        @Test func aboutInADevelopmentBuild() async throws {
            let app = AppModel.demo()
            let updater = FakeUpdater(reason: .developmentBuild)
            let hosted = try await host(AboutView(), app: app, updater: updater, size: CGSize(width: 440, height: 620))
            defer { hosted.close() }

            #expect(texts(in: hosted.window).contains { $0.contains("Updates are turned off in development builds.") })
            let check = try #require(element(labeled: "Check for Updates", in: hosted.window))
            #expect(!isEnabled(check))
            _ = check.accessibilityPerformPress?()
            #expect(updater.events.isEmpty)
            let toggle = try #require(element(labeled: "Check for updates automatically", in: hosted.window))
            #expect(!isEnabled(toggle))
        }

        // MARK: Settings → Updates

        @Test func updatesPane() async throws {
            let app = AppModel.demo()
            let updater = FakeUpdater()
            updater.status = .upToDate
            updater.lastCheckDate = Date().addingTimeInterval(-10)
            let hosted = try await host(SettingsRootView(initialPane: .updates), app: app, updater: updater, size: CGSize(width: 820, height: 640))
            defer { hosted.close() }

            let all = texts(in: hosted.window)
            #expect(all.contains { $0.contains("Vela is up to date.") }, "\(all)")
            #expect(all.contains { $0.contains("Last checked just now.") })
            #expect(element(labeled: "Show in settings editor", in: hosted.window) != nil)

            let check = try #require(element(labeled: "Check for Updates", in: hosted.window))
            #expect(check.accessibilityPerformPress?() == true)
            #expect(updater.events == ["check"])

            // Install automatically: off by default, and only with checks on.
            let install = try #require(element(labeled: "Install updates automatically", in: hosted.window))
            #expect(isEnabled(install))
            #expect(install.accessibilityPerformPress?() == true)
            try await settle(hosted.window)
            #expect(app.settings[.updatesInstallAutomatically])

            let checks = try #require(element(labeled: "Check for updates automatically", in: hosted.window))
            #expect(checks.accessibilityPerformPress?() == true)
            try await settle(hosted.window)
            #expect(!app.settings[.updatesCheckAutomatically])
            let installAfter = try #require(element(labeled: "Install updates automatically", in: hosted.window))
            #expect(!isEnabled(installAfter))
        }

        @Test func updatesPaneInADevelopmentBuild() async throws {
            let app = AppModel.demo()
            let updater = FakeUpdater(reason: .developmentBuild)
            let hosted = try await host(SettingsRootView(initialPane: .updates), app: app, updater: updater, size: CGSize(width: 820, height: 640))
            defer { hosted.close() }

            #expect(texts(in: hosted.window).contains { $0.contains("Updates are turned off in development builds.") })
            for label in ["Check for Updates", "Check for updates automatically", "Install updates automatically"] {
                let control = try #require(element(labeled: label, in: hosted.window), "\(label)")
                #expect(!isEnabled(control), "\(label)")
            }
        }
    }
}
