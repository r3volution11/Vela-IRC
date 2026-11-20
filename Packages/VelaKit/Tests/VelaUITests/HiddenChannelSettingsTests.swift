// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
@testable import VelaCore
import VelaIRC
import VelaStore
import VelaTheme
@testable import VelaUI

extension LinkSelectionTests {
    /// The network's settings list its hidden channels, with Show and Join,
    /// which act at once.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Hidden channels in a network's settings", .serialized)
    struct HiddenChannelSettingsTests {
        /// A button in `window`, found and pressed as VoiceOver would.
        private func button(labeled label: String, in window: NSWindow) -> AnyObject? {
            let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
            NSApp.perform(enhancedInterface, with: NSNumber(value: true))
            defer { NSApp.perform(enhancedInterface, with: NSNumber(value: false)) }
            func find(_ object: AnyObject) -> AnyObject? {
                if (object.accessibilityLabel?() ?? nil) == label { return object }
                for child in (object.accessibilityChildren?() ?? nil) ?? [] {
                    if let found = find(child as AnyObject) { return found }
                }
                return nil
            }
            return find(window)
        }

        private func settle(_ window: NSWindow) async throws {
            try await Task.sleep(for: .milliseconds(120))
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }

        @Test func showAndJoinHiddenChannels() async throws {
            let app = AppModel.demo()
            let libera = try #require(app.sessions.first { $0.displayName == "Libera.Chat" })
            libera.config.bouncerKind = .znc
            for name in ["#vela", "#swift"] {
                let channel = try #require(libera.buffer(named: name))
                app.detach(channel)
                libera.handle(.message(IRCMessage(line: ":doug!d@host PART \(name)")!, batch: nil))
                app.hide(channel)
            }
            #expect(libera.hiddenChannels.map(\.name) == ["#vela", "#swift"])
            let selected = app.selectedBufferID

            let size = CGSize(width: 560, height: 1600)
            let view = NetworkEditorView(target: .existing(libera.id))
                .frame(width: size.width, height: size.height)
                .environment(app)
                .environment(UIState())
                .environment(\.theme, ResolvedTheme.fallbackLight)
                .environment(\.chatStyle, ChatStyle(settings: app.settings))
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -8000, y: -8000), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            defer { window.contentView = nil }
            try await settle(window)

            // Show: back in the list, still detached, nothing selected.
            let show = try #require(button(labeled: "Show #vela", in: window))
            #expect(show.accessibilityPerformPress?() == true)
            let vela = try #require(libera.buffer(named: "#vela"))
            #expect(vela.isDetached)
            #expect(app.selectedBufferID == selected)
            #expect(libera.hiddenChannels.map(\.name) == ["#swift"])
            try await settle(window)
            #expect(button(labeled: "Show #vela", in: window) == nil)

            // Join: back in the list, and joined (here, asked to be).
            let join = try #require(button(labeled: "Join #swift", in: window))
            #expect(join.accessibilityPerformPress?() == true)
            let swift = try #require(libera.buffer(named: "#swift"))
            #expect(libera.rejoins(swift))
            #expect(libera.hiddenChannels.isEmpty)
            try await settle(window)
            #expect(button(labeled: "Show #swift", in: window) == nil)
        }
    }
}
