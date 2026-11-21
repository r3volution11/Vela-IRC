// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Observation
import SwiftUI
import Testing
import VelaCore
import VelaStore
import VelaTheme
@testable import VelaUI

// Debug builds only: they count the scene's draws.
#if DEBUG
extension LinkSelectionTests {
    /// The welcome scene draws when it's shown, resized or re-themed, and
    /// not when anything else around it changes.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Welcome scene redraws", .serialized)
    struct WelcomeSceneRedrawTests {
        @Observable
        final class Knobs {
            var theme = ResolvedTheme.fallbackDark
            var style = ChatStyle()
            var unrelated = 0
        }

        struct Host: View {
            let knobs: Knobs
            let app: AppModel
            let uiState: UIState

            var body: some View {
                // Reading it makes this view, and the empty state in it,
                // update when it changes.
                let unrelated = knobs.unrelated
                EmptyStateView()
                    .environment(app)
                    .environment(uiState)
                    .environment(\.theme, knobs.theme)
                    .environment(\.chatStyle, knobs.style)
                    .background(knobs.theme[ThemeKey.chatBackground])
                    .overlay(alignment: .topLeading) { Text("\(unrelated)").opacity(0.01) }
            }
        }

        @Test func drawsOnlyWhenShownResizedOrRethemed() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "VelaWelcome-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let app = AppModel(
                settings: SettingsStore(fileURL: root.appending(path: "settings.json"), watchForChanges: false),
                networkStore: NetworkConfigStore(fileURL: root.appending(path: "networks.json")),
                database: nil,
                isDemo: true
            )
            let knobs = Knobs()
            let host = NSHostingView(rootView: Host(knobs: knobs, app: app, uiState: UIState()))
            host.sizingOptions = []
            let window = NSWindow(contentRect: CGRect(x: -9000, y: -9000, width: 900, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFrontRegardless()
            defer {
                window.orderOut(nil)
                window.contentView = nil
            }
            func settle() async throws {
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
            }

            let before = WelcomeSceneView.drawCount
            try await settle()
            let shown = WelcomeSceneView.drawCount
            #expect(shown > before, "the scene draws when shown")

            // Other state: the view updates, the scene doesn't redraw.
            knobs.unrelated += 1
            knobs.style.fontSize += 3
            knobs.style.showTimestamps.toggle()
            try await settle()
            try await settle()
            #expect(WelcomeSceneView.drawCount == shown, "redrew for unrelated state")

            // A new accent: redraws.
            var colors = knobs.theme.colors
            colors[ThemeKey.accent] = ThemeColor(hex: "#FF6A00")!
            knobs.theme = ResolvedTheme(id: "t", name: "T", kind: .dark, vibrancy: .none, colors: colors, nickColors: [], ircColors: [])
            try await settle()
            let rethemed = WelcomeSceneView.drawCount
            #expect(rethemed > shown, "the scene redraws for a new accent")

            // A bigger window with the scene already at its widest: nothing
            // to redraw. A smaller one shrinks it: redraws.
            window.setContentSize(CGSize(width: 1100, height: 760))
            try await settle()
            #expect(WelcomeSceneView.drawCount == rethemed, "redrew at the same size")
            window.setContentSize(CGSize(width: 600, height: 520))
            try await settle()
            #expect(WelcomeSceneView.drawCount > rethemed, "the scene redraws when resized")
        }
    }
}
#endif
