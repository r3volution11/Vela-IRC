// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import SwiftUI
import Testing
import VelaCore
import VelaIntelligence
import VelaTheme
@testable import VelaUI

extension LinkSelectionTests {
    /// ⌘[ / ⌘] in Settings go to the previous and next section.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Settings section shortcuts", .serialized)
    struct SettingsSectionShortcutTests {
        private static let paneKey = "Vela.settingsPane"

        /// ⌘`key` as the window gets it from the keyboard.
        private func press(_ key: String, keyCode: UInt16, in window: NSWindow) throws {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: keyCode
            ))
            _ = window.performKeyEquivalent(with: event)
        }

        @Test func bracketsStepThroughTheSections() async throws {
            let saved = UserDefaults.standard.string(forKey: Self.paneKey)
            defer { UserDefaults.standard.set(saved, forKey: Self.paneKey) }

            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let app = AppModel.demo()
            let size = CGSize(width: 820, height: 600)
            let view = SettingsRootView(initialPane: .appearance)
                .velaEnvironment(
                    app: app,
                    themeStore: ThemeStore(userThemesDirectory: root.appendingPathComponent("Themes")),
                    uiState: UIState(),
                    services: SceneServices(intelligence: .demo()),
                    isPrimary: false
                )
                .frame(width: size.width, height: size.height)
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            defer { window.contentView = nil }
            try await Task.sleep(for: .milliseconds(150))

            func pane() -> String? { UserDefaults.standard.string(forKey: Self.paneKey) }

            try press("]", keyCode: 30, in: window)
            try await Task.sleep(for: .milliseconds(80))
            #expect(pane() == SettingsPane.layout.rawValue)
            try press("[", keyCode: 33, in: window)
            try await Task.sleep(for: .milliseconds(80))
            try press("[", keyCode: 33, in: window)
            try await Task.sleep(for: .milliseconds(80))
            #expect(pane() == SettingsPane.presets.rawValue)
            // The first section stays put.
            try press("[", keyCode: 33, in: window)
            try await Task.sleep(for: .milliseconds(80))
            #expect(pane() == SettingsPane.presets.rawValue)
        }
    }
}
