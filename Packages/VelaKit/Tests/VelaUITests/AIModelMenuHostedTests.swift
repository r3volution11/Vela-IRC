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
    /// The model menus in Settings (AI Providers' Default model, and each
    /// feature's in Intelligence), hosted: the choice the menu shows is the
    /// one saved, never a section's title. "apple" is both Automatic's
    /// saved value and, once, the Apple section's id, which SwiftUI took
    /// for the selection and showed as "Apple".
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Model menus in Settings, hosted", .serialized)
    struct AIModelMenuHostedTests {
        private func intelligence(_ app: AppModel) -> IntelligenceServices {
            let availability = IntelligenceAvailability.fixed(.available)
            let models = AIModels(settings: app.settings, keys: AIKeyStore(keychain: .inMemory()), availability: availability)
            return IntelligenceServices(availability: availability, summarizer: CannedSummarizer(stepDelay: .zero), models: models)
        }

        /// What the row's menu shows, hosted in an offscreen window.
        private func shownTitle(_ row: AIModelSettingRow, app: AppModel, intelligence: IntelligenceServices) async throws -> String? {
            let view = row
                .frame(width: 520)
                .environment(app)
                .environment(intelligence)
                .environment(\.theme, ResolvedTheme.fallbackLight)
            // SwiftUI builds its accessibility for an assistive app.
            let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
            NSApplication.shared.perform(enhancedInterface, with: NSNumber(value: true))
            defer { NSApplication.shared.perform(enhancedInterface, with: NSNumber(value: false)) }
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -8000, y: -8000), size: CGSize(width: 520, height: 80)),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            // Offscreen, without making Vela active.
            window.orderFrontRegardless()
            defer {
                window.orderOut(nil)
                window.contentView = nil
            }
            for _ in 0..<3 {
                try await Task.sleep(for: .milliseconds(50))
                hosting.layoutSubtreeIfNeeded()
            }
            return Self.popUpValue(in: window)
        }

        /// What VoiceOver reads as the menu's value: the title it shows.
        private static func popUpValue(in window: NSWindow) -> String? {
            var found: String?
            var dump: [String] = []
            func visit(_ object: AnyObject, depth: Int) {
                let role = object.accessibilityRole?() ?? nil
                let label = object.accessibilityLabel?() ?? nil
                let valueSelector = NSSelectorFromString("accessibilityValue")
                let value = object.responds(to: valueSelector) ? object.perform(valueSelector)?.takeUnretainedValue() : nil
                dump.append("\(String(repeating: " ", count: depth))\(role?.rawValue ?? "-") label=\(label ?? "-") value=\(value.map { "\($0)" } ?? "-")")
                if found == nil, role == .popUpButton || role == .menuButton, let value = value as? String { found = value }
                for child in (object.accessibilityChildren?() ?? nil) ?? [] { visit(child as AnyObject, depth: depth + 1) }
            }
            visit(window, depth: 0)
            if found == nil { Issue.record("No menu in:\n\(dump.joined(separator: "\n"))") }
            return found
        }

        @Test func theDefaultModelShowsAutomaticApple() async throws {
            let app = AppModel.demo()
            await app.ready()
            let intelligence = intelligence(app)
            // With a provider, as when you've added one: two sections.
            intelligence.models.addProvider(.anthropic)
            let row = AIModelSettingRow(title: "Default model", key: .intelligenceModel)
            var shown = try await shownTitle(row, app: app, intelligence: intelligence)
            #expect(shown == "Automatic (Apple)")
            // Saved explicitly, too.
            app.settings[.intelligenceModel] = AIModelChoice.automatic.settingValue
            shown = try await shownTitle(row, app: app, intelligence: intelligence)
            #expect(shown == "Automatic (Apple)")
            // And a provider's model.
            app.settings[.intelligenceModel] = "anthropic/claude-opus-5-5"
            shown = try await shownTitle(row, app: app, intelligence: intelligence)
            #expect(shown == "Claude Opus 5.5 (recommended)")
        }

        /// Settings → Intelligence: Catch me up's and Recap's own menus.
        @Test func aFeaturesModelShowsItsChoice() async throws {
            let app = AppModel.demo()
            await app.ready()
            let intelligence = intelligence(app)
            intelligence.models.addProvider(.anthropic)
            for key in [SettingKey<String>.intelligenceCatchUpModel, .intelligenceRecapModel] {
                let row = AIModelSettingRow(title: "Model", key: key, followsDefault: true)
                var shown = try await shownTitle(row, app: app, intelligence: intelligence)
                #expect(shown == "Same as default (Automatic (Apple))")
                app.settings[key] = AIModelChoice.automatic.settingValue
                shown = try await shownTitle(row, app: app, intelligence: intelligence)
                #expect(shown == "Automatic (Apple)")
                app.settings[key] = "anthropic/claude-opus-5-5"
                shown = try await shownTitle(row, app: app, intelligence: intelligence)
                #expect(shown == "Claude Opus 5.5 (recommended)")
            }
        }
    }
}
