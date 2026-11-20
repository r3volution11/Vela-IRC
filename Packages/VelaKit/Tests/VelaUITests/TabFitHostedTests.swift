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
    /// Fit first, then scroll, in a hosted tab stack: the frames the rows
    /// lay their tabs out at (from a `TabStripProbe`), which titles fade,
    /// where the row scrolls, and what doesn't lay the strip out again.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Fitting tabs, hosted", .serialized)
    struct TabFitHostedTests {
        private final class Hosted {
            let app: AppModel
            let uiState: UIState
            let window: NSWindow
            let probe: TabStripProbe
            let metrics: TabMetrics

            init(app: AppModel, uiState: UIState, window: NSWindow, probe: TabStripProbe, metrics: TabMetrics) {
                self.app = app
                self.uiState = uiState
                self.window = window
                self.probe = probe
                self.metrics = metrics
            }

            var session: NetworkSession { app.selectedSession! }
            var channels: TabStripProbe.Row? { probe.rows["channels"] }
            var networks: TabStripProbe.Row? { probe.rows["networks"] }

            func close() {
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        private static let longNames = [
            "#a-channel-with-a-long-name",
            "#another-rather-long-channel",
            "#the-longest-channel-name-here",
            "#yet-another-long-one",
        ]

        private func host(
            _ placement: TabStackPlacement = .top,
            width: CGFloat,
            roundness: Double = 0.35,
            serverRow: ServerTabRowMode = .auto,
            configure: (AppModel) -> Void = { _ in }
        ) async throws -> Hosted {
            let app = AppModel.demo()
            app.settings[.navigationStyle] = .tabs
            app.settings[.tabsPlacement] = placement
            app.settings[.tabsServerRow] = serverRow
            app.settings[.tabsRoundness] = roundness
            configure(app)
            let uiState = UIState()
            let probe = TabStripProbe()
            let style = ChatStyle(settings: app.settings)
            let appearance: TabAppearance = placement == .titleBar || roundness >= 0.8 ? .floating : .attached(placement == .top ? .bottom : .top)
            let metrics = TabMetrics(style: style, height: TabMetrics.channelHeight(style), appearance: appearance)
            let size = CGSize(width: width, height: 120)
            // Flexible, so resizing the window resizes the strip.
            let view = TabStackView(placement: placement)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(app)
                .environment(uiState)
                .environment(IntelligenceServices.demo())
                .environment(\.theme, ResolvedTheme.fallbackLight)
                .environment(\.chatStyle, style)
                .environment(\.tabStripProbe, probe)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -8000, y: -8000), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            let hosted = Hosted(app: app, uiState: uiState, window: window, probe: probe, metrics: metrics)
            try await settle(hosted)
            return hosted
        }

        /// Lets SwiftUI catch up: the row's » menu comes a turn after its
        /// geometry, and the row lays out again after that.
        private func settle(_ hosted: Hosted) async throws {
            for _ in 0..<3 {
                try await Task.sleep(for: .milliseconds(60))
                hosted.window.contentView?.layoutSubtreeIfNeeded()
            }
            try await Task.sleep(for: .milliseconds(40))
        }

        private func resize(_ hosted: Hosted, width: CGFloat) async throws {
            hosted.window.setContentSize(CGSize(width: width, height: hosted.window.contentLayoutRect.height))
            try await settle(hosted)
        }

        private func addLongChannels(_ session: NetworkSession, count: Int = longNames.count) {
            for index in 0..<count {
                let name = index < Self.longNames.count ? Self.longNames[index] : "#long-channel-number-\(index)"
                session.ensureBuffer(name: name, kind: .channel, persist: false)
            }
        }

        /// The tabs of the channel row, in order, with their frames.
        private func channelFrames(_ hosted: Hosted) throws -> [(buffer: BufferModel, frame: CGRect)] {
            let row = try #require(hosted.channels)
            return try hosted.session.allBuffers.map { buffer in
                (buffer, try #require(row.frames[AnyHashable(buffer.id)], "\(buffer.name) has no frame"))
            }
        }

        /// What VoiceOver finds: each element's frame on screen, by label,
        /// with SwiftUI's accessibility on.
        private func accessibilityElements(in hosted: Hosted) -> [String: CGRect] {
            let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
            NSApp.perform(enhancedInterface, with: NSNumber(value: true))
            defer { NSApp.perform(enhancedInterface, with: NSNumber(value: false)) }
            var elements: [String: CGRect] = [:]
            func visit(_ object: AnyObject) {
                if let label = object.accessibilityLabel?() ?? nil, elements[label] == nil {
                    elements[label] = object.accessibilityFrame?() ?? .zero
                }
                for child in (object.accessibilityChildren?() ?? nil) ?? [] { visit(child as AnyObject) }
            }
            visit(hosted.window)
            return elements
        }

        // MARK: Fit first

        @Test(arguments: [
            (TabStackPlacement.top, 0.35, 1000.0),
            (TabStackPlacement.bottom, 0.0, 1000),
            (TabStackPlacement.top, 1.0, 1000),
            // The network group and header buttons share the title bar.
            (TabStackPlacement.titleBar, 0.35, 1400),
        ])
        func unselectedTabsShrinkToFit(placement: TabStackPlacement, roundness: Double, width: Double) async throws {
            let hosted = try await host(placement, width: width, roundness: roundness) { app in
                self.addLongChannels(app.sessions[0])
            }
            defer { hosted.close() }
            let row = try #require(hosted.channels)
            let available = try #require(row.available)
            #expect(!row.plan.isScrolling, "\(placement)")
            let cap = try #require(row.plan.cap, "\(placement): nothing trimmed in \(available)")

            let frames = try channelFrames(hosted)
            let selected = try #require(hosted.app.selectedBufferID)
            // Every tab is in the strip, side by side.
            for (buffer, frame) in frames {
                #expect(frame.minX >= -0.5 && frame.maxX <= available + 0.5, "\(placement): \(buffer.name) at \(frame)")
            }
            for (left, right) in zip(frames, frames.dropFirst()) {
                #expect(right.frame.minX >= left.frame.maxX - 0.5)
            }
            #expect(row.plan.totalWidth <= available + 0.5)

            #expect(cap >= hosted.metrics.minWidth)
            var whole = 0
            for (index, (buffer, frame)) in frames.enumerated() where buffer.kind != .server {
                let natural = row.plan.naturals[index]
                let title = buffer.kind == .channel ? String(buffer.name.drop { $0 == "#" }) : buffer.name
                let isFaded = hosted.probe.fadedTitles[title]
                #expect(frame.width >= hosted.metrics.minWidth - 0.5, "\(buffer.name): \(frame.width)")
                if buffer.id == selected || natural <= cap {
                    // The selected tab, and names shorter than the cap, are
                    // whole and don't fade.
                    #expect(abs(frame.width - natural) < 0.5, "\(buffer.name): \(frame.width) vs \(natural)")
                    #expect(isFaded == false, "\(buffer.name)")
                    if buffer.id != selected { whole += 1 }
                } else {
                    // Longer ones are cut to the cap, all alike, and fade.
                    #expect(frame.width == cap, "\(buffer.name): \(frame.width) vs \(cap)")
                    #expect(isFaded == true, "\(buffer.name)")
                }
            }
            #expect(whole >= 2, "no short names left whole")
            for name in Self.longNames {
                let index = try #require(hosted.session.allBuffers.firstIndex { $0.name == name })
                #expect(row.plan.isTrimmed(index), "\(name)")
            }
            // Nothing to scroll to: no » menu taking room from the strip.
            if placement != .titleBar {
                #expect(available == hosted.window.frame.width - Self.stripInsets)
            }
            // VoiceOver reads the whole name of a trimmed tab.
            #expect(accessibilityElements(in: hosted)[Self.longNames[0]] != nil)
        }

        @Test func selectingATrimmedTabShowsItWhole() async throws {
            let hosted = try await host(width: 1000) { app in self.addLongChannels(app.sessions[0]) }
            defer { hosted.close() }
            let session = hosted.session
            let previous = try #require(hosted.app.selectedBuffer)
            // Long, but under the label cap, so it's whole when selected.
            let long = try #require(session.buffer(named: Self.longNames[3]))
            let index = try #require(session.allBuffers.firstIndex { $0 === long })
            let before = try #require(hosted.channels)
            #expect(before.plan.isTrimmed(index))
            #expect(hosted.probe.fadedTitles[String(long.name.dropFirst())] == true)

            hosted.app.select(long)
            try await settle(hosted)
            let after = try #require(hosted.channels)
            let frame = try #require(after.frames[AnyHashable(long.id)])
            #expect(abs(frame.width - after.plan.naturals[index]) < 0.5)
            #expect(hosted.probe.fadedTitles[String(long.name.dropFirst())] == false)
            #expect(!after.plan.isScrolling)
            #expect(after.plan.totalWidth <= (after.available ?? 0) + 0.5)
            // The tab it was is unselected now, and short enough to stay whole.
            let previousFrame = try #require(after.frames[AnyHashable(previous.id)])
            #expect(previousFrame.width >= hosted.metrics.minWidth)
        }

        @Test func typingNeverLaysOutTheStrip() async throws {
            let hosted = try await host(width: 1000) { app in self.addLongChannels(app.sessions[0]) }
            defer { hosted.close() }
            let buffer = try #require(hosted.app.selectedBuffer)
            let passes = hosted.probe.passes
            let fades = hosted.probe.fadedTitles
            #expect(passes["channels", default: 0] > 0)
            var text = ""
            for character in "hello there, how's it going?" {
                text.append(character)
                hosted.uiState.drafts[buffer.id] = text
                hosted.session.inputChanged(text, in: buffer)
                try await Task.sleep(for: .milliseconds(5))
                hosted.window.contentView?.layoutSubtreeIfNeeded()
            }
            try await settle(hosted)
            #expect(hosted.probe.passes == passes)
            #expect(hosted.probe.fadedTitles == fades)
        }

        // MARK: Then scroll

        @Test(arguments: [TabStackPlacement.top, .titleBar])
        func tooManyTabsScrollAtTheirNaturalWidths(placement: TabStackPlacement) async throws {
            let hosted = try await host(placement, width: 900) { app in
                self.addLongChannels(app.sessions[0], count: 16)
            }
            defer { hosted.close() }
            let row = try #require(hosted.channels)
            #expect(row.plan.isScrolling)
            #expect(row.plan.cap == nil)
            #expect(row.plan.widths == row.plan.naturals)
            let available = try #require(row.available)
            #expect(row.plan.totalWidth > available)
            let frames = try channelFrames(hosted)
            for (index, (buffer, frame)) in frames.enumerated() {
                #expect(abs(frame.width - row.plan.naturals[index]) < 0.5, "\(buffer.name)")
            }
            // Names under the label cap are whole, so they don't fade.
            #expect(hosted.probe.fadedTitles[String(Self.longNames[3].dropFirst())] == false)

            if placement == .top {
                // The » menu is there, taking some of the strip.
                #expect(available < hosted.window.frame.width - Self.stripInsets - 20)
            }

            // Selecting the last tab scrolls it into view.
            let last = try #require(frames.last)
            #expect(last.frame.minX > available)
            hosted.app.select(last.buffer)
            try await settle(hosted)
            try await Task.sleep(for: .milliseconds(300))
            let elements = accessibilityElements(in: hosted)
            // (In the title bar, the header's buttons change with the selection.)
            let strip = try #require(elements["Channels on Libera.Chat"])
            let shown = try #require(elements[last.buffer.name])
            #expect(hosted.channels?.plan.isScrolling == true)
            #expect(shown.minX >= strip.minX - 0.5 && shown.maxX <= strip.maxX + 0.5, "\(shown) in \(strip)")
        }

        /// The channel row's leading inset and trailing padding at the top
        /// or bottom.
        private static let stripInsets = TabMetrics.stripInset + 8

        /// Resizes the window so the channel row has `available` points.
        private func setAvailable(_ hosted: Hosted, _ available: CGFloat) async throws {
            let current = try #require(hosted.channels?.available)
            try await resize(hosted, width: hosted.window.frame.width + available - current)
        }

        @Test func resizingAcrossTheBoundaryDoesntFlicker() async throws {
            let hosted = try await host(width: 1000) { app in self.addLongChannels(app.sessions[0], count: 8) }
            defer { hosted.close() }
            var row = try #require(hosted.channels)
            #expect(!row.plan.isScrolling)
            #expect(row.plan.cap != nil)
            let required = row.plan.required
            let h = TabFit.hysteresis

            // Short of what the tabs need at their narrowest: it scrolls.
            try await setAvailable(hosted, required - 2)
            row = try #require(hosted.channels)
            #expect(row.plan.isScrolling)
            // The » menu came, and took some of the strip.
            let menu = hosted.window.frame.width - Self.stripInsets - (row.available ?? 0)
            #expect(menu > 20, "\(menu)")
            // Room for them again (more, counting the » menu's), but not
            // the hysteresis: still scrolling.
            for available in [required, required + h - 2] {
                try await setAvailable(hosted, available)
                #expect(hosted.channels?.plan.isScrolling == true, "\(available) for \(required)")
            }
            // With the hysteresis to spare, it fits, and without the »
            // menu it has more room still.
            try await setAvailable(hosted, required + h + 1)
            row = try #require(hosted.channels)
            #expect(!row.plan.isScrolling)
            #expect(row.plan.totalWidth <= (row.available ?? 0) + 0.5)
            #expect((row.available ?? 0) > required + h + 1)
            // A point or two either way, it stays put.
            let fitting = hosted.window.frame.width
            for delta in [-1.0, 1, -2, 2, 0] {
                try await resize(hosted, width: fitting + delta)
                #expect(hosted.channels?.plan.isScrolling == false)
            }
            // Fitting, it fits right down to the floors, and no further.
            try await setAvailable(hosted, required + 0.5)
            #expect(hosted.channels?.plan.isScrolling == false)
            try await setAvailable(hosted, required - 2)
            #expect(hosted.channels?.plan.isScrolling == true)
        }

        // MARK: Networks

        @Test func theNetworkRowFitsToo() async throws {
            // Libera.Chat (selected) and two networks with long names.
            let hosted = try await host(width: 420, serverRow: .always) { app in
                for (session, name) in zip(app.sessions.dropFirst(), ["A Network With A Long Name", "Another Long Network"]) {
                    var config = session.config
                    config.name = name
                    session.updateConfig(config)
                }
            }
            defer { hosted.close() }
            var style = ChatStyle(settings: hosted.app.settings)
            style.tabRoundness = hosted.app.settings[.tabsRoundness]
            let metrics = TabMetrics(style: style, height: TabMetrics.serverHeight(style), appearance: .floating)
            let row = try #require(hosted.networks)
            let available = try #require(row.available)
            #expect(!row.plan.isScrolling)
            #expect(row.plan.cap != nil, "\(row.plan.naturals) in \(available)")
            #expect(row.plan.totalWidth <= available + 0.5)
            let selected = try #require(hosted.app.selectedSession)
            for (position, session) in hosted.app.sessions.enumerated() {
                let frame = try #require(row.frames[AnyHashable(session.id)])
                if session === selected {
                    #expect(abs(frame.width - row.plan.naturals[position]) < 0.5)
                } else {
                    #expect(frame.width >= min(row.plan.naturals[position], metrics.minWidth) - 0.5, "\(session.displayName)")
                }
                #expect(hosted.probe.fadedTitles[session.displayName] == row.plan.isTrimmed(position), "\(session.displayName)")
            }
        }

        @Test func theTitleBarsNetworkGroupStaysWhole() async throws {
            let hosted = try await host(.titleBar, width: 700, serverRow: .always) { app in
                self.addLongChannels(app.sessions[0])
            }
            defer { hosted.close() }
            let row = try #require(hosted.networks)
            #expect(row.plan.cap == nil)
            #expect(row.plan.widths == row.plan.naturals)
        }
    }
}
