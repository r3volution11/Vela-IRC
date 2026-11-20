// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme
@testable import VelaUI

extension LinkSelectionTests {
    /// ⌘1…⌘9 against a hosted tab stack: after joining, closing, moving and
    /// reopening channels, and switching networks, each one selects the tab
    /// whose tooltip shows it, in every placement.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Tab shortcuts", .serialized)
    struct TabShortcutTests {
        private final class Hosted {
            let app: AppModel
            let window: NSWindow

            init(app: AppModel, window: NSWindow) {
                self.app = app
                self.window = window
            }

            func close() {
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        private func host(_ placement: TabStackPlacement, serverRow: ServerTabRowMode) async throws -> Hosted {
            let app = AppModel.demo()
            app.settings[.navigationStyle] = .tabs
            app.settings[.tabsPlacement] = placement
            app.settings[.tabsServerRow] = serverRow
            let size = CGSize(width: 1400, height: 120)
            let view = TabStackView(placement: placement)
                .frame(width: size.width, height: size.height)
                .environment(app)
                .environment(UIState())
                .environment(IntelligenceServices.demo())
                .environment(\.theme, ResolvedTheme.fallbackLight)
                .environment(\.chatStyle, ChatStyle(settings: app.settings))
            let hosting = NSHostingView(rootView: view)
            // Never shown: key equivalents reach it through the window.
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -8000, y: -8000), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            let hosted = Hosted(app: app, window: window)
            try await settle(hosted)
            return hosted
        }

        /// Lets SwiftUI catch up with a change to the model.
        private func settle(_ hosted: Hosted) async throws {
            try await Task.sleep(for: .milliseconds(80))
            hosted.window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }

        private static let keyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

        /// ⌘`number` as the window gets it from the keyboard.
        private func press(_ number: Int, in hosted: Hosted) throws {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosted.window.windowNumber,
                context: nil, characters: "\(number)", charactersIgnoringModifiers: "\(number)",
                isARepeat: false, keyCode: Self.keyCodes[number - 1]
            ))
            _ = hosted.window.performKeyEquivalent(with: event)
        }

        /// The tab each of ⌘1…⌘9 selects, from the console (so a shortcut
        /// with no tab leaves the console selected: nil).
        private func pressAll(in hosted: Hosted, session: NetworkSession) throws -> [String?] {
            try (1...9).map { number in
                hosted.app.select(session.serverBuffer)
                try press(number, in: hosted)
                let selected = hosted.app.selectedBuffer
                return selected?.kind == .server ? nil : selected?.name
            }
        }

        /// The tabs as drawn, console first, with the number their tooltip
        /// shows. Read from the tabs' help, as VoiceOver reads it.
        private func tooltipNumbers(in hosted: Hosted) -> [String: Int] {
            let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
            NSApp.perform(enhancedInterface, with: NSNumber(value: true))
            defer { NSApp.perform(enhancedInterface, with: NSNumber(value: false)) }
            var numbers: [String: Int] = [:]
            func visit(_ object: AnyObject) {
                if let label = object.accessibilityLabel?() ?? nil,
                   let help = object.accessibilityHelp?() ?? nil,
                   let range = help.range(of: "⌘", options: .backwards),
                   let number = Int(help[range.upperBound...])
                {
                    numbers[label] = number
                }
                for child in (object.accessibilityChildren?() ?? nil) ?? [] { visit(child as AnyObject) }
            }
            visit(hosted.window)
            return numbers
        }

        /// What ⌘1…⌘9 should select: the tabs after the console, in the
        /// order they're drawn.
        private func expected(_ session: NetworkSession) -> [String?] {
            let tabs = session.allBuffers.filter { $0.kind != .server }.map(\.name)
            return (0..<9).map { tabs.indices.contains($0) ? tabs[$0] : nil }
        }

        private func check(_ hosted: Hosted, _ step: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
            let session = try #require(hosted.app.selectedSession, sourceLocation: sourceLocation)
            let wanted = expected(session)
            let selected = try pressAll(in: hosted, session: session)
            #expect(selected == wanted, "\(step)", sourceLocation: sourceLocation)
            // Each tab's tooltip names the shortcut that selects it.
            let tooltips = tooltipNumbers(in: hosted)
            for (index, name) in wanted.enumerated() {
                guard let name else { continue }
                #expect(tooltips[name] == index + 1, "\(step): \(name) shows ⌘\(tooltips[name].map(String.init) ?? "-")", sourceLocation: sourceLocation)
            }
        }

        @Test(arguments: [
            (TabStackPlacement.top, ServerTabRowMode.auto),
            (TabStackPlacement.bottom, ServerTabRowMode.always),
            (TabStackPlacement.titleBar, ServerTabRowMode.auto),
            (TabStackPlacement.titleBar, ServerTabRowMode.always),
        ])
        func shortcutsFollowTheTabs(placement: TabStackPlacement, serverRow: ServerTabRowMode) async throws {
            let hosted = try await host(placement, serverRow: serverRow)
            defer { hosted.close() }
            let app = hosted.app
            let libera = try #require(app.selectedSession)
            try check(hosted, "at first")

            // A new channel goes after the other channels, before the conversations.
            libera.ensureBuffer(name: "#new", kind: .channel, persist: false)
            try await settle(hosted)
            try check(hosted, "after joining")

            app.close(try #require(libera.buffer(named: "#swift")))
            try await settle(hosted)
            try check(hosted, "after closing")

            libera.moveBuffer(try #require(libera.buffer(named: "#new")), toIndex: 0)
            try await settle(hosted)
            try check(hosted, "after moving")

            app.reopenLastClosed()
            try await settle(hosted)
            #expect(libera.buffer(named: "#swift") != nil)
            try check(hosted, "after reopening")

            // Another network's tabs.
            let ergo = try #require(app.sessions.first { $0.displayName == "Ergo Testnet" })
            app.select(try #require(ergo.channels.first))
            try await settle(hosted)
            try check(hosted, "on another network")
        }
    }
}
