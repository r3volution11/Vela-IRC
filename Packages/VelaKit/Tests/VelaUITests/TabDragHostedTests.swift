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
    /// Dragging tabs to reorder them, in a hosted tab stack, with real
    /// mouse events: every tab moves both ways, the last one included.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that click in offscreen windows.
    @MainActor
    @Suite("Dragging tabs, hosted", .serialized)
    struct TabDragHostedTests {
        private final class Hosted {
            let app: AppModel
            let window: NSWindow

            init(app: AppModel, window: NSWindow) {
                self.app = app
                self.window = window
            }

            var session: NetworkSession { app.selectedSession! }
            var channelNames: [String] { session.channels.map(\.name) }

            func close() {
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        private func host(
            _ placement: TabStackPlacement = .top,
            width: CGFloat = 1000,
            configure: (AppModel) -> Void = { _ in }
        ) async throws -> Hosted {
            let app = AppModel.demo()
            app.settings[.navigationStyle] = .tabs
            app.settings[.tabsPlacement] = placement
            configure(app)
            let style = ChatStyle(settings: app.settings)
            let size = CGSize(width: width, height: 120)
            let view = TabStackView(placement: placement)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(app)
                .environment(UIState())
                .environment(IntelligenceServices.demo())
                .environment(\.theme, ResolvedTheme.fallbackLight)
                .environment(\.chatStyle, style)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -8000, y: -8000), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            // The test runner is never the active app, so AppKit only passes a
            // click on to a view that takes the first mouse.
            let accept: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
            class_addMethod(type(of: hosting), #selector(NSView.acceptsFirstMouse(for:)), imp_implementationWithBlock(accept), "c@:@")
            let hosted = Hosted(app: app, window: window)
            try await settle(hosted)
            return hosted
        }

        private func settle(_ hosted: Hosted) async throws {
            for _ in 0..<3 {
                try await Task.sleep(for: .milliseconds(60))
                hosted.window.contentView?.layoutSubtreeIfNeeded()
            }
            try await Task.sleep(for: .milliseconds(40))
        }

        /// Each tab's frame in window coordinates, by its VoiceOver label.
        private func tabFrames(in hosted: Hosted) -> [String: CGRect] {
            let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
            NSApp.perform(enhancedInterface, with: NSNumber(value: true))
            defer { NSApp.perform(enhancedInterface, with: NSNumber(value: false)) }
            var elements: [String: CGRect] = [:]
            func visit(_ object: AnyObject) {
                if let label = object.accessibilityLabel?() ?? nil, elements[label] == nil {
                    let screen = object.accessibilityFrame?() ?? .zero
                    elements[label] = hosted.window.convertFromScreen(screen)
                }
                for child in (object.accessibilityChildren?() ?? nil) ?? [] { visit(child as AnyObject) }
            }
            visit(hosted.window)
            return elements
        }

        private static var eventNumber = 52000

        private func event(_ type: NSEvent.EventType, at point: CGPoint, in hosted: Hosted) -> NSEvent {
            Self.eventNumber += 1
            return NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosted.window.windowNumber,
                context: nil, eventNumber: Self.eventNumber, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            )!
        }

        /// Drags the tab labelled `label` by `distance` points, in steps, as a
        /// hand would, and waits for the drop to settle.
        private func drag(_ label: String, by distance: CGFloat, in hosted: Hosted) async throws {
            let frame = try #require(tabFrames(in: hosted)[label], "no tab \(label)")
            // Its middle, clear of the close slot at its leading edge.
            let start = CGPoint(x: frame.midX + frame.width / 6, y: frame.midY)
            var events = [event(.leftMouseDown, at: start, in: hosted)]
            let steps = 12
            for step in 1...steps {
                let x = start.x + distance * CGFloat(step) / CGFloat(steps)
                events.append(event(.leftMouseDragged, at: CGPoint(x: x, y: start.y), in: hosted))
            }
            events.append(event(.leftMouseUp, at: CGPoint(x: start.x + distance, y: start.y), in: hosted))
            for event in events {
                NSApp.sendEvent(event)
                try await Task.sleep(for: .milliseconds(25))
            }
            // The drop glides into place, then the model moves.
            try await Task.sleep(for: .milliseconds(400))
            try await settle(hosted)
        }

        private func addChannels(_ session: NetworkSession, _ names: [String]) {
            for name in names { session.ensureBuffer(name: name, kind: .channel, persist: false) }
        }

        @Test func theLastChannelMovesLeftAndBack() async throws {
            let hosted = try await host { app in
                self.addChannels(app.sessions[0], ["#alpha", "#bravo", "#charlie", "#delta"])
            }
            defer { hosted.close() }
            let before = hosted.channelNames
            let last = try #require(before.last)
            let frames = tabFrames(in: hosted)
            let lastFrame = try #require(frames[last], "\(last) not in \(frames.keys.sorted())")
            let firstFrame = try #require(frames[before[0]])

            // All the way to the front…
            try await drag(last, by: firstFrame.minX - lastFrame.minX - 10, in: hosted)
            #expect(hosted.channelNames.first == last, "\(before) → \(hosted.channelNames)")

            // …and back to the end.
            let afterFirst = hosted.channelNames
            let moved = try #require(tabFrames(in: hosted)[last])
            let end = try #require(tabFrames(in: hosted)[afterFirst.last!])
            try await drag(last, by: end.maxX - moved.maxX + 10, in: hosted)
            #expect(hosted.channelNames.last == last, "\(afterFirst) → \(hosted.channelNames)")
        }

        @Test func theSelectedLastChannelGoesBackWhereItWas() async throws {
            // The selected tab keeps its whole name while the others are
            // trimmed, so it's the widest: moved one place left, it still
            // gets past the narrower tab now at the end.
            let hosted = try await host(width: 800) { app in
                let session = app.sessions[0]
                self.addChannels(session, ["#alpha", "#bravo", "#a-channel-with-a-rather-long-name"])
                app.select(session.channels.last!)
            }
            defer { hosted.close() }
            let before = hosted.channelNames
            let last = try #require(before.last)
            let frames = tabFrames(in: hosted)
            let lastFrame = try #require(frames[last])
            let neighbor = try #require(frames[before[before.count - 2]])
            #expect(lastFrame.width > neighbor.width)

            try await drag(last, by: neighbor.minX - lastFrame.minX + 2, in: hosted)
            var swapped = before
            swapped.swapAt(before.count - 1, before.count - 2)
            #expect(hosted.channelNames == swapped, "\(before) → \(hosted.channelNames)")

            let now = try #require(tabFrames(in: hosted)[last])
            let end = try #require(tabFrames(in: hosted)[hosted.channelNames.last!])
            try await drag(last, by: end.maxX - now.maxX + 10, in: hosted)
            #expect(hosted.channelNames == before, "\(swapped) → \(hosted.channelNames)")
        }

        /// In the title bar, where the empty space behind the tabs drags the
        /// window and has its own menu (Show Channel Title Bar), a tab
        /// still drags to move, both ways.
        @Test func aChannelMovesAlongTheTitleBar() async throws {
            let hosted = try await host(.titleBar, width: 1200) { app in
                self.addChannels(app.sessions[0], ["#alpha", "#bravo", "#charlie"])
            }
            defer { hosted.close() }
            let before = hosted.channelNames
            let first = before[0]
            let frames = tabFrames(in: hosted)
            let firstFrame = try #require(frames[first], "\(first) not in \(frames.keys.sorted())")
            let lastFrame = try #require(frames[before.last!])

            try await drag(first, by: lastFrame.maxX - firstFrame.maxX + 10, in: hosted)
            #expect(hosted.channelNames.last == first, "\(before) → \(hosted.channelNames)")

            let atEnd = hosted.channelNames
            let moved = try #require(tabFrames(in: hosted)[first])
            let front = try #require(tabFrames(in: hosted)[atEnd[0]])
            try await drag(first, by: front.minX - moved.minX - 10, in: hosted)
            #expect(hosted.channelNames == before, "\(atEnd) → \(hosted.channelNames)")
        }

        @Test func aChannelDraggedToTheEndComesBack() async throws {
            let hosted = try await host { app in
                self.addChannels(app.sessions[0], ["#alpha", "#bravo", "#charlie", "#delta"])
            }
            defer { hosted.close() }
            let before = hosted.channelNames
            let first = before[0]
            let frames = tabFrames(in: hosted)
            let firstFrame = try #require(frames[first])
            let lastFrame = try #require(frames[before.last!])

            try await drag(first, by: lastFrame.maxX - firstFrame.maxX + 10, in: hosted)
            #expect(hosted.channelNames.last == first, "\(before) → \(hosted.channelNames)")

            // One place left, then back to the front.
            let atEnd = hosted.channelNames
            let moved = try #require(tabFrames(in: hosted)[first])
            let neighbor = try #require(tabFrames(in: hosted)[atEnd[atEnd.count - 2]])
            try await drag(first, by: neighbor.midX - moved.midX - 4, in: hosted)
            #expect(hosted.channelNames[atEnd.count - 2] == first, "\(atEnd) → \(hosted.channelNames)")

            let oneBack = hosted.channelNames
            let now = try #require(tabFrames(in: hosted)[first])
            let front = try #require(tabFrames(in: hosted)[oneBack[0]])
            try await drag(first, by: front.minX - now.minX - 10, in: hosted)
            #expect(hosted.channelNames.first == first, "\(oneBack) → \(hosted.channelNames)")
        }
    }
}
