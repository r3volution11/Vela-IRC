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
    /// Closing tabs: the close slot where a tab's `#` or avatar sits, the
    /// minimum tab width that keeps most of a short tab for selecting,
    /// middle-click, and VoiceOver's Close action.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites that
    /// click in offscreen windows: AppKit sends a mouse-up to the window that
    /// had the mouse-down, so clicks from suites running side by side would
    /// land in each other's windows.
    @MainActor
    @Suite("Closing tabs", .serialized)
    struct TabCloseTests {
        // MARK: Metrics

        private static let heights: [Double] = [18, 22, 24, 28, 32, 36, 40, 48]
        private static let roundnesses: [Double] = [0, 0.35, 0.8, 1]
        private static let appearances: [TabAppearance] = [.floating, .attached(.bottom), .attached(.top)]

        private static func metrics(height: Double, roundness: Double = 0.35, appearance: TabAppearance = .floating) -> TabMetrics {
            var style = ChatStyle()
            style.tabHeight = height
            style.tabRoundness = roundness
            return TabMetrics(style: style, height: TabMetrics.channelHeight(style), appearance: appearance)
        }

        @Test func theSlotIsSixteenToEighteenPointsAndFitsTwoHashes() {
            for height in Self.heights {
                let metrics = Self.metrics(height: height)
                #expect((16...18).contains(metrics.closeSlot), "height \(height): \(metrics.closeSlot)")
                // `##` fits, drawn at no less than its 0.8 minimum scale.
                let font = NSFont.systemFont(ofSize: metrics.fontSize, weight: .semibold)
                let width = ("##" as NSString).size(withAttributes: [.font: font]).width
                #expect(width * 0.8 <= metrics.closeSlot, "height \(height): ## is \(width) in \(metrics.closeSlot)")
                #expect(metrics.closeSlot <= metrics.height, "height \(height)")
            }
        }

        @Test func theMinimumWidthLeavesRoomToSelect() {
            for height in Self.heights {
                for roundness in Self.roundnesses {
                    for appearance in Self.appearances {
                        let metrics = Self.metrics(height: height, roundness: roundness, appearance: appearance)
                        for glyphWidth in [metrics.channelGlyphWidth("#"), metrics.channelGlyphWidth("##"), metrics.iconSize + 1] {
                            let insets = metrics.closeSlotInsets(glyphWidth: glyphWidth)
                            let selectable = metrics.minWidth - insets.leading - metrics.closeSlot
                            #expect(
                                selectable >= metrics.closeSlot * 1.5,
                                "height \(height), roundness \(roundness), \(appearance): \(selectable) beside a \(metrics.closeSlot) slot"
                            )
                            // The middle of a tab is clear of the slot.
                            #expect(
                                insets.leading + metrics.closeSlot < metrics.minWidth / 2,
                                "height \(height), roundness \(roundness): slot ends at \(insets.leading + metrics.closeSlot) of \(metrics.minWidth)"
                            )
                        }
                    }
                }
            }
            // Rounder tabs pad more inside their curves, so they're a little wider.
            #expect(Self.metrics(height: 28, roundness: 1).minWidth > Self.metrics(height: 28, roundness: 0).minWidth)
        }

        @Test func theGlyphSitsWhereTheTabsPaddingPutsIt() {
            let metrics = Self.metrics(height: 28)
            for glyph in ["#", "##"] {
                let width = metrics.channelGlyphWidth(glyph)
                let insets = metrics.closeSlotInsets(glyphWidth: width)
                let inkStart = insets.leading + (metrics.closeSlot - width) / 2
                #expect(abs(inkStart - metrics.horizontalPadding) <= 1, "\(glyph): ink at \(inkStart)")
                #expect(insets.trailing >= 2)
            }
            // Never into the tab's edge.
            #expect(Self.metrics(height: 22, roundness: 0).closeSlotInsets(glyphWidth: 0).leading >= 3)
        }

        @Test func aChannelsTypePrefixBecomesTheGlyph() throws {
            let session = try #require(AppModel.demo().sessions.first)
            func split(_ name: String, maxLength: Int = 2) -> [String] {
                let split = session.splitChannelPrefix(name, maxLength: maxLength)
                return [split.prefix, split.name]
            }
            #expect(split("#dn") == ["#", "dn"])
            #expect(split("##linux") == ["##", "linux"])
            #expect(split("###x") == ["##", "#x"])
            if session.isupport.channelTypes.contains("&") {
                #expect(split("&local") == ["&", "local"])
            } else {
                #expect(split("&local") == ["", "&local"])
            }
            #expect(split("#") == ["#", "#"])
            #expect(split("alice") == ["", "alice"])
            // The sidebar's single-character prefix is unchanged.
            #expect(split("##linux", maxLength: 1) == ["#", "#linux"])
        }

        // MARK: Hosted tabs

        private final class Recorder {
            var selects = 0
            var closes = 0
            var width: CGFloat = 0
        }

        /// One tab at the top-left of its window, as the channel row draws it.
        private struct Harness: View {
            @Environment(AppModel.self) private var app
            @Environment(\.chatStyle) private var style
            let buffer: BufferModel
            let session: NetworkSession
            let surface: TabSurface
            let appearance: TabAppearance
            let recorder: Recorder

            @Namespace private var selection
            @FocusState private var focus: TabKey?
            @State private var reorder = ReorderController<BufferID>(axis: .horizontal, coordinateSpace: "test-tabs")

            var body: some View {
                let metrics = TabMetrics(style: style, height: TabMetrics.channelHeight(style), appearance: appearance)
                ChannelTab(
                    buffer: buffer,
                    session: session,
                    context: TabContext(
                        metrics: metrics,
                        palette: TabPalette.channels(on: surface, appearance: appearance),
                        appearance: appearance,
                        selection: selection,
                        isSelected: false,
                        isHovered: false,
                        isFocused: false,
                        showsSeparator: false
                    ),
                    showsNetworkName: true,
                    shortcutNumber: nil,
                    focus: $focus,
                    reorder: buffer.kind == .server ? nil : TabReorder(
                        controller: reorder, id: buffer.id, siblings: [buffer.id], move: { _ in }
                    ),
                    onSelect: { recorder.selects += 1 },
                    onClose: { recorder.closes += 1 },
                    onHover: { _ in },
                    closeTitle: TabDescriptions.closeAction(buffer, in: session, app: app)
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { recorder.width = $0 }
                .coordinateSpace(.named(reorder.coordinateSpace))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }

        private final class Hosted {
            let app: AppModel
            let session: NetworkSession
            let window: NSWindow
            let host: NSView
            let recorder: Recorder
            let metrics: TabMetrics

            init(app: AppModel, session: NetworkSession, window: NSWindow, host: NSView, recorder: Recorder, metrics: TabMetrics) {
                self.app = app
                self.session = session
                self.window = window
                self.host = host
                self.recorder = recorder
                self.metrics = metrics
            }

            /// Window point `x` from the tab's leading edge, `y` down from its top
            /// (its middle by default).
            func point(x: CGFloat, y: CGFloat? = nil) -> CGPoint {
                let local = CGPoint(x: x, y: y ?? metrics.height / 2)
                let flipped = host.isFlipped ? local : CGPoint(x: local.x, y: host.bounds.height - local.y)
                return host.convert(flipped, to: nil)
            }

            func close() {
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        private static var eventNumber = 31000
        private static let size = CGSize(width: 480, height: 80)

        private func host(
            _ name: String,
            kind: BufferKind = .channel,
            surface: TabSurface = .strip,
            appearance: TabAppearance = .attached(.bottom),
            configure: (AppModel) -> Void = { _ in }
        ) async throws -> Hosted {
            let app = AppModel.demo()
            configure(app)
            let session = try #require(app.sessions.first)
            let buffer = kind == .server ? session.serverBuffer : session.ensureBuffer(name: name, kind: kind, persist: false)
            let recorder = Recorder()
            let style = ChatStyle(settings: app.settings)
            let metrics = TabMetrics(style: style, height: TabMetrics.channelHeight(style), appearance: appearance)
            let view = Harness(buffer: buffer, session: session, surface: surface, appearance: appearance, recorder: recorder)
                .frame(width: Self.size.width, height: Self.size.height)
                .environment(app)
                .environment(UIState())
                .environment(IntelligenceServices.demo())
                .environment(\.theme, ResolvedTheme.fallbackLight)
                .environment(\.chatStyle, style)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -8000, y: -8000), size: Self.size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            window.orderFrontRegardless()
            // The test runner is never the active app, so AppKit only passes a
            // click on to a view that takes the first mouse.
            let accept: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
            class_addMethod(type(of: host), #selector(NSView.acceptsFirstMouse(for:)), imp_implementationWithBlock(accept), "c@:@")
            try await Task.sleep(for: .milliseconds(200))
            return Hosted(app: app, session: session, window: window, host: host, recorder: recorder, metrics: metrics)
        }

        private func click(_ point: CGPoint, in hosted: Hosted) async throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                Self.eventNumber += 1
                NSApp.sendEvent(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosted.window.windowNumber,
                    context: nil, eventNumber: Self.eventNumber, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
                )!)
                try await Task.sleep(for: .milliseconds(30))
            }
            // Each click is a click of its own (clickCount 1), so no double-click wait.
            try await Task.sleep(for: .milliseconds(60))
        }

        /// The slot of a tab whose glyph is `glyphWidth` wide: x from the tab's
        /// leading edge.
        private func slot(_ hosted: Hosted, glyphWidth: CGFloat) -> ClosedRange<CGFloat> {
            let leading = hosted.metrics.closeSlotInsets(glyphWidth: glyphWidth).leading
            return leading...(leading + hosted.metrics.closeSlot)
        }

        @Test func onlyTheSlotClosesTheTab() async throws {
            let hosted = try await host("#dn")
            defer { hosted.close() }
            let slot = slot(hosted, glyphWidth: hosted.metrics.channelGlyphWidth("#"))
            let recorder = hosted.recorder

            // Its middle and just inside its edges close.
            for x in [(slot.lowerBound + slot.upperBound) / 2, slot.lowerBound + 1.5, slot.upperBound - 1.5] {
                try await click(hosted.point(x: x), in: hosted)
            }
            #expect(recorder.closes == 3)
            #expect(recorder.selects == 0)
            // Inside the slot's square, near its top.
            let slotTop = (hosted.metrics.height - hosted.metrics.closeSlot) / 2
            try await click(hosted.point(x: slot.lowerBound + 4, y: slotTop + 1.5), in: hosted)
            #expect(recorder.closes == 4)

            // The rest of the tab selects: before the slot, just after it, its
            // middle, its far end, and above and below the slot.
            let width = recorder.width
            let elsewhere: [CGPoint] = [
                hosted.point(x: max(1, slot.lowerBound - 2)),
                hosted.point(x: slot.upperBound + 2),
                hosted.point(x: width / 2),
                hosted.point(x: width - 3),
                hosted.point(x: (slot.lowerBound + slot.upperBound) / 2, y: max(0.5, slotTop - 1.5)),
                hosted.point(x: (slot.lowerBound + slot.upperBound) / 2, y: min(hosted.metrics.height - 0.5, slotTop + hosted.metrics.closeSlot + 1.5)),
            ]
            for point in elsewhere {
                try await click(point, in: hosted)
            }
            #expect(recorder.selects == elsewhere.count)
            #expect(recorder.closes == 4)
        }

        @Test func aConversationsAvatarIsItsCloseSlot() async throws {
            let hosted = try await host("alice", kind: .query, surface: .titleBar, appearance: .floating)
            defer { hosted.close() }
            let slot = slot(hosted, glyphWidth: hosted.metrics.iconSize + 1)
            try await click(hosted.point(x: (slot.lowerBound + slot.upperBound) / 2), in: hosted)
            try await click(hosted.point(x: slot.upperBound + 6), in: hosted)
            #expect(hosted.recorder.closes == 1)
            #expect(hosted.recorder.selects == 1)
        }

        @Test func withCloseButtonsOffTheSlotSelects() async throws {
            let hosted = try await host("#dn") { $0.settings[.tabsShowCloseButtons] = false }
            defer { hosted.close() }
            let slot = slot(hosted, glyphWidth: hosted.metrics.channelGlyphWidth("#"))
            try await click(hosted.point(x: (slot.lowerBound + slot.upperBound) / 2), in: hosted)
            #expect(hosted.recorder.closes == 0)
            #expect(hosted.recorder.selects == 1)
        }

        @Test func theServerConsoleHasNoCloseSlot() async throws {
            let hosted = try await host("", kind: .server)
            defer { hosted.close() }
            let slot = slot(hosted, glyphWidth: hosted.metrics.channelGlyphWidth("#"))
            try await click(hosted.point(x: (slot.lowerBound + slot.upperBound) / 2), in: hosted)
            #expect(hosted.recorder.closes == 0)
            #expect(hosted.recorder.selects == 1)
        }

        @Test(arguments: [
            (TabSurface.strip, TabAppearance.attached(.bottom), 0.35),
            (TabSurface.strip, TabAppearance.attached(.top), 0.0),
            (TabSurface.strip, TabAppearance.floating, 1.0),
            (TabSurface.titleBar, TabAppearance.floating, 0.35),
        ])
        func shortNamesGetTheMinimumWidth(surface: TabSurface, appearance: TabAppearance, roundness: Double) async throws {
            let short = try await host("#dn", surface: surface, appearance: appearance) { $0.settings[.tabsRoundness] = roundness }
            defer { short.close() }
            #expect(abs(short.recorder.width - short.metrics.minWidth) < 0.5, "\(short.recorder.width) vs \(short.metrics.minWidth)")

            // Long names grow past it and still truncate.
            let long = try await host("#a-channel-with-a-very-long-name-indeed", surface: surface, appearance: appearance) {
                $0.settings[.tabsRoundness] = roundness
            }
            defer { long.close() }
            #expect(long.recorder.width > long.metrics.minWidth)
            #expect(long.recorder.width <= long.metrics.maxLabelWidth + long.metrics.closeSlot + long.metrics.horizontalPadding * 2 + long.metrics.spacing)
        }

        // MARK: Middle-click

        private func middleClick(button: Int64 = 2) throws -> NSEvent {
            let mouseButton = try #require(CGMouseButton(rawValue: UInt32(button)))
            let event = try #require(CGEvent(
                mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: .zero, mouseButton: mouseButton
            ))
            event.setIntegerValueField(.mouseEventButtonNumber, value: button)
            return try #require(NSEvent(cgEvent: event))
        }

        @Test func middleClickClosesTheTabUnderThePointer() throws {
            let app = AppModel.demo()
            let session = try #require(app.sessions.first)
            let buffer = session.ensureBuffer(name: "#dn", kind: .channel, persist: false)
            let uiState = UIState()
            let interaction = TabInteraction()
            interaction.installMiddleClickMonitor { TabActions.middleClick($0, app: app, uiState: uiState) }
            defer { interaction.removeMiddleClickMonitor() }

            // Not over a tab, or another button: the click goes on.
            let event = try middleClick()
            #expect(interaction.handleOtherMouseUp(event) === event)
            interaction.setHovering(true, .buffer(buffer.id))
            let right = try middleClick(button: 3)
            #expect(interaction.handleOtherMouseUp(right) === right)
            #expect(session.buffer(id: buffer.id) != nil)

            // Over the tab: the click is used up, and it does what the tab's ×
            // does: #dn isn't joined, so it's removed, once you say so.
            #expect(interaction.handleOtherMouseUp(try middleClick()) == nil)
            #expect(uiState.channelConfirmation?.action == .remove)
            #expect(uiState.channelConfirmation?.bufferID == buffer.id)
            #expect(session.buffer(id: buffer.id) != nil)
            app.settings[.channelsConfirmRemove] = false
            #expect(interaction.handleOtherMouseUp(try middleClick()) == nil)
            #expect(session.buffer(id: buffer.id) == nil)
        }

        @Test func middleClickLeavesConsolesAndNetworks() throws {
            let app = AppModel.demo()
            let session = try #require(app.sessions.first)
            let count = session.allBuffers.count
            let uiState = UIState()
            #expect(!TabActions.middleClick(.buffer(session.serverBuffer.id), app: app, uiState: uiState))
            #expect(!TabActions.middleClick(.network(session.id), app: app, uiState: uiState))
            #expect(session.allBuffers.count == count)
            // A conversation closes without asking.
            let query = session.ensureBuffer(name: "alice", kind: .query, persist: false)
            #expect(TabActions.middleClick(.buffer(query.id), app: app, uiState: uiState))
            #expect(uiState.channelConfirmation == nil)
            #expect(session.buffer(id: query.id) == nil)
        }

        // MARK: VoiceOver

        /// An element of the accessibility tree, asked as VoiceOver asks
        /// (SwiftUI's elements are plain objects that answer the same calls).
        private struct Element {
            let object: AnyObject
            var label: String? { object.accessibilityLabel?() ?? nil }
            var role: NSAccessibility.Role? { object.accessibilityRole?() ?? nil }
            var children: [Element] { ((object.accessibilityChildren?() ?? nil) ?? []).map { Element(object: $0 as AnyObject) } }
            var customActions: [NSAccessibilityCustomAction] { (object.accessibilityCustomActions?() ?? nil) ?? [] }

            var all: [Element] { [self] + children.flatMap(\.all) }
        }

        /// The tab VoiceOver reads as `label`, with SwiftUI's accessibility on
        /// as an assistive app turns it on. (SwiftUI only builds it for one.)
        private func tabElement(labeled label: String, in hosted: Hosted) async throws -> (tab: Element, all: [Element]) {
            let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
            NSApp.perform(enhancedInterface, with: NSNumber(value: true))
            defer { NSApp.perform(enhancedInterface, with: NSNumber(value: false)) }
            var elements: [Element] = []
            for _ in 0..<20 {
                elements = Element(object: hosted.window).all
                if let tab = elements.first(where: { $0.label == label }) { return (tab, elements) }
                try await Task.sleep(for: .milliseconds(50))
            }
            Issue.record("No \(label) in \(elements.compactMap(\.label))")
            throw CancellationError()
        }

        @Test func voiceOverCanCloseATabThatIsntHovered() async throws {
            let hosted = try await host("#dn")
            defer { hosted.close() }
            // The full name, # and all.
            let (tab, all) = try await tabElement(labeled: "#dn", in: hosted)
            #expect(tab.role == .button)
            // The close slot isn't an element of its own: the tab's action is the way.
            #expect(all.filter { $0.role == .button }.count == 1, "\(all.map { "\($0.role?.rawValue ?? "-") \($0.label ?? "-")" })")
            let actions = tab.customActions
            // #dn isn't joined, so its × removes it.
            let close = try #require(actions.first { $0.name == "Remove Channel" }, "\(actions.map(\.name))")
            if let handler = close.handler {
                _ = handler()
            } else if let target = close.target as? NSObject, let selector = close.selector {
                target.perform(selector, with: close)
            }
            #expect(hosted.recorder.closes == 1)
            #expect(hosted.recorder.selects == 0)
        }

        @Test func aConversationTabHasACloseActionToo() async throws {
            let hosted = try await host("alice", kind: .query)
            defer { hosted.close() }
            let tab = try await tabElement(labeled: "alice", in: hosted).tab
            let actions = tab.customActions
            #expect(actions.contains { $0.name == "Close Conversation" }, "\(actions.map(\.name))")
        }
    }
}
