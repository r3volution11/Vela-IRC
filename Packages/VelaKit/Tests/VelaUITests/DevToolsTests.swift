// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Vela Dev's developer tools exist only in Debug builds, and so do their tests.
#if DEBUG

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaTheme
@testable import VelaUI

// MARK: - Layout gaps, registry, placement

@MainActor
@Suite("Developer tools: outlines and inspection")
struct DevToolsLayoutTests {
    private func entry(_ id: Int, _ name: String, _ frame: CGRect, tokens: [String] = []) -> DevTagRegistry.Entry {
        var entry = DevTagRegistry.Entry(id: id)
        entry.tag = DevTag(name: name, tokens: tokens)
        entry.frame = frame
        entry.visibleFrame = frame
        return entry
    }

    @Test func gapsAreMeasuredBetweenSiblingsToTheRightAndBelow() {
        let rects = [
            CGRect(x: 0, y: 0, width: 300, height: 200),     // container
            CGRect(x: 10, y: 10, width: 100, height: 40),    // a
            CGRect(x: 118, y: 10, width: 100, height: 40),   // b, 8 to the right of a
            CGRect(x: 10, y: 62, width: 100, height: 40),    // c, 12 below a
        ]
        let gaps = DevLayoutGaps.gaps(between: rects)
        #expect(gaps.contains(DevLayoutGaps.Gap(start: CGPoint(x: 110, y: 30), end: CGPoint(x: 118, y: 30))))
        #expect(gaps.contains(DevLayoutGaps.Gap(start: CGPoint(x: 60, y: 50), end: CGPoint(x: 60, y: 62))))
        #expect(gaps.map(\.length).sorted() == [8, 12])
    }

    @Test func gapsSkipTouchingViewsAndViewsInOtherContainers() {
        let rects = [
            CGRect(x: 0, y: 0, width: 100, height: 100),     // left container
            CGRect(x: 120, y: 0, width: 100, height: 100),   // right container, 20 away
            CGRect(x: 10, y: 10, width: 80, height: 20),     // in the left one
            CGRect(x: 10, y: 30, width: 80, height: 20),     // touching it below
            CGRect(x: 130, y: 10, width: 80, height: 20),    // in the right one
        ]
        let gaps = DevLayoutGaps.gaps(between: rects)
        // Only the two containers: the rows inside them aren't siblings,
        // and the two rows on the left touch.
        #expect(gaps == [DevLayoutGaps.Gap(start: CGPoint(x: 100, y: 50), end: CGPoint(x: 120, y: 50))])
    }

    @Test func theInnermostTaggedViewIsInspectedAndItsAncestorsMakeThePath() {
        let registry = DevTagRegistry()
        let list = entry(1, "Message list", CGRect(x: 0, y: 0, width: 400, height: 600))
        let row = entry(2, "Message row", CGRect(x: 0, y: 100, width: 400, height: 40))
        let badge = entry(3, "Badge", CGRect(x: 350, y: 110, width: 20, height: 16))
        for item in [list, row, badge] {
            registry.update(item.id, tag: item.tag!, font: nil, fontContext: EnvironmentValues().fontResolutionContext)
            registry.update(item.id, geometry: DevTagGeometry(frame: item.frame, visibleFrame: item.visibleFrame))
        }
        registry.pointer = CGPoint(x: 20, y: 120)
        #expect(registry.inspected?.tag?.name == "Message row")
        registry.pointer = CGPoint(x: 355, y: 115)
        #expect(registry.inspected?.tag?.name == "Badge")
        #expect(registry.path(to: registry.inspected!).compactMap(\.tag?.name) == ["Message list", "Message row", "Badge"])
        registry.pointer = CGPoint(x: 500, y: 500)
        #expect(registry.inspected == nil)
    }

    @Test func clickingPinsAndClickingAgainUnpins() {
        let registry = DevTagRegistry()
        let row = entry(7, "Row", CGRect(x: 0, y: 0, width: 100, height: 20))
        registry.update(row.id, tag: row.tag!, font: nil, fontContext: EnvironmentValues().fontResolutionContext)
        registry.update(row.id, geometry: DevTagGeometry(frame: row.frame, visibleFrame: row.visibleFrame))
        registry.pin(at: CGPoint(x: 5, y: 5))
        #expect(registry.pinnedID == 7)
        // Pinned, it stays what's shown wherever the pointer goes.
        registry.pointer = CGPoint(x: 900, y: 900)
        #expect(registry.inspected?.id == 7)
        registry.pin(at: CGPoint(x: 5, y: 5))
        #expect(registry.pinnedID == nil)
        registry.pin(at: CGPoint(x: 5, y: 5))
        registry.remove(7)
        #expect(registry.pinnedID == nil)
        #expect(registry.entries.isEmpty)
    }

    @Test func rowsScrolledOutOfViewAreNotShown() {
        let registry = DevTagRegistry()
        registry.update(1, tag: DevTag(name: "Row", tokens: []), font: nil, fontContext: EnvironmentValues().fontResolutionContext)
        registry.update(1, geometry: DevTagGeometry(frame: CGRect(x: 0, y: -40, width: 100, height: 20), visibleFrame: .null))
        #expect(registry.shownEntries.isEmpty)
        #expect(registry.entries(at: CGPoint(x: 10, y: -30)).isEmpty)
    }

    @Test func inspectionReportsTheThemesHexValuesAndPadding() {
        let theme = ResolvedTheme.fallbackDark
        var row = entry(1, "Message row", CGRect(x: 0, y: 0, width: 584, height: 46), tokens: [ThemeKey.chatForeground, ThemeKey.chatBackground, ThemeKey.chatForeground, "not.aToken"])
        row.tag?.padding = EdgeInsets(top: 7, leading: 16, bottom: 1, trailing: 16)
        let inspection = DevInspection(row, theme: theme)
        #expect(inspection.name == "Message row")
        #expect(inspection.size == CGSize(width: 584, height: 46))
        // Repeats dropped; unknown keys flagged.
        #expect(inspection.tokens.map(\.key) == [ThemeKey.chatForeground, ThemeKey.chatBackground, "not.aToken"])
        #expect(inspection.tokens[0].hex == theme.color(ThemeKey.chatForeground).hex)
        #expect(inspection.tokens[1].hex == theme.color(ThemeKey.chatBackground).hex)
        #expect(inspection.tokens.map(\.isKnown) == [true, true, false])
        #expect(DevInspectorPanel.describe(inspection.padding!) == "7 16 1 16")
    }

    @Test func fontsAreDescribedByFamilySizeAndWeight() {
        let context = EnvironmentValues().fontResolutionContext
        let system = DevInspection.describe(Font.system(size: 13, weight: .semibold).resolve(in: context))
        #expect(system.size == 13)
        #expect(system.weight == "Semibold")
        #expect(system.family == "SF Pro (system)")
        let mono = DevInspection.describe(Font.system(size: 11, design: .monospaced).resolve(in: context))
        #expect(mono.size == 11)
        #expect(mono.weight == "Regular")
    }

    @Test func thePanelStaysInTheWindow() {
        let bounds = CGSize(width: 800, height: 600)
        let panel = CGSize(width: 280, height: 160)
        // Below the view when there's room.
        #expect(DevInspector.panelOffset(for: CGRect(x: 100, y: 100, width: 200, height: 40), panel: panel, in: bounds) == CGSize(width: 100, height: 148))
        // Above it near the bottom.
        #expect(DevInspector.panelOffset(for: CGRect(x: 100, y: 500, width: 200, height: 40), panel: panel, in: bounds) == CGSize(width: 100, height: 332))
        // Never past the right edge.
        #expect(DevInspector.panelOffset(for: CGRect(x: 700, y: 100, width: 90, height: 40), panel: panel, in: bounds).width == 512)
        // A view filling the window: inside its top.
        let full = DevInspector.panelOffset(for: CGRect(x: 0, y: 0, width: 800, height: 600), panel: panel, in: bounds)
        #expect(full.height >= 8 && full.height + panel.height <= 592)
    }
}

// MARK: - Performance HUD counters

@MainActor
@Suite("Developer tools: Performance HUD")
struct DevPerformanceTests {
    private let refresh = 1.0 / 60

    @Test func steadyFramesDropNothing() {
        var stats = DevFrameStats()
        for frame in 0...60 { stats.record(timestamp: 10 + Double(frame) * refresh, refresh: refresh) }
        let summary = stats.summary
        #expect(abs(summary.fps - 60) < 0.5)
        #expect(abs(summary.averageFrame - refresh) < 0.0001)
        #expect(summary.dropped == 0)
        #expect(summary.hitchRatio == 0)
        #expect(stats.totalDropped == 0)
        #expect(stats.stalls == 0)
    }

    @Test func aLateFrameCountsDroppedFramesAHitchAndAStall() {
        var stats = DevFrameStats()
        var time = 10.0
        stats.record(timestamp: time, refresh: refresh)
        for _ in 0..<10 {
            time += refresh
            stats.record(timestamp: time, refresh: refresh)
        }
        // The main thread was busy for 100 ms: six refreshes, five missed.
        time += refresh * 6
        stats.record(timestamp: time, refresh: refresh)
        let summary = stats.summary
        #expect(summary.dropped == 5)
        #expect(stats.totalDropped == 5)
        #expect(stats.stalls == 1)
        #expect(abs(stats.longestStall - refresh * 6) < 0.0001)
        #expect(abs(summary.worstFrame - refresh * 6) < 0.0001)
        // Hitch time: how late it was, per second of frames.
        let span = refresh * 16
        #expect(abs(summary.hitchRatio - (refresh * 5) / span) < 0.0001)
    }

    @Test func aPauseIsNotAStall() {
        var stats = DevFrameStats()
        stats.record(timestamp: 10, refresh: refresh)
        stats.record(timestamp: 10 + refresh, refresh: refresh)
        stats.pause()
        // The window was hidden for a minute.
        stats.record(timestamp: 70, refresh: refresh)
        stats.record(timestamp: 70 + refresh, refresh: refresh)
        #expect(stats.stalls == 0)
        #expect(stats.totalDropped == 0)
    }

    @Test func theSummaryCoversTheLastSecond() {
        var stats = DevFrameStats()
        stats.record(timestamp: 0, refresh: refresh)
        stats.record(timestamp: 0.5, refresh: refresh)   // an old stall
        for frame in 1...90 { stats.record(timestamp: 0.5 + Double(frame) * refresh, refresh: refresh) }
        #expect(stats.summary.dropped == 0)
        #expect(stats.totalDropped > 0)
        #expect(stats.stalls == 1)
    }

    @Test func theMonitorPublishesMemoryRowsAndFramesTwiceASecond() {
        final class Fakes {
            var memory: UInt64 = 200 << 20
            var rows = 1_000
        }
        let fakes = Fakes()
        let monitor = DevPerformanceMonitor(memory: { fakes.memory }, rowBodies: { fakes.rows })
        monitor.recordFrame(timestamp: 100, refresh: refresh)
        #expect(monitor.snapshot.memory == 200 << 20)
        #expect(monitor.snapshot.rowsTotal == 0)
        // Not again until half a second has gone by.
        fakes.rows = 1_040
        fakes.memory = 300 << 20
        monitor.recordFrame(timestamp: 100 + refresh, refresh: refresh)
        #expect(monitor.snapshot.memory == 200 << 20)
        for frame in 2...30 { monitor.recordFrame(timestamp: 100 + Double(frame) * refresh, refresh: refresh) }
        let snapshot = monitor.snapshot
        #expect(snapshot.memory == 300 << 20)
        #expect(snapshot.rowsTotal == 40)
        #expect(abs(snapshot.rowsPerSecond - 80) < 1)
        #expect(abs(snapshot.frames.fps - 60) < 1)
        monitor.reset()
        #expect(monitor.snapshot == DevPerformanceMonitor.Snapshot())
    }

    @Test func theFootprintIsTheProcesss() throws {
        let footprint = try #require(DevMemory.footprint())
        #expect(footprint > 1 << 20)
    }

    @Test func theHUDFormatsItsNumbers() {
        #expect(DevPerformanceHUD.ms(0.0166) == "16.6 ms")
        #expect(DevPerformanceHUD.megabytes(214 << 20) == "214.0 MB")
    }
}

// MARK: - Developer menu

@MainActor
@Suite("Developer tools: Developer menu")
struct DeveloperMenuTests {
    @Test func theShortcutsDontClashWithVelasOthers() {
        let developer = [
            VelaCommandCatalog.Shortcuts.inspectElement,
            VelaCommandCatalog.Shortcuts.layoutOutlines,
            VelaCommandCatalog.Shortcuts.performanceHUD,
        ]
        #expect(developer.map(ShortcutGlyphs.string(for:)) == ["⌥⌘I", "⌥⌘O", "⌥⌘P"])
        let themes = FileManager.default.temporaryDirectory.appending(path: "VelaDevToolsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: themes) }
        let catalog = VelaCommandCatalog(VelaCommandContext(
            app: AppModel.demo(), themeStore: ThemeStore(userThemesDirectory: themes), uiState: UIState(),
            openWindow: EnvironmentValues().openWindow,
            openSettings: EnvironmentValues().openSettings
        ))
        let others = catalog.all.filter { $0.category != .developer }.compactMap(\.shortcut).map(ShortcutGlyphs.string(for:))
        for shortcut in developer.map(ShortcutGlyphs.string(for:)) {
            #expect(!others.contains(shortcut), "\(shortcut) is taken")
        }
        // The palette lists them too.
        #expect(catalog.all.filter { $0.category == .developer }.count == catalog.developerCommands.count)
    }
}

// MARK: - Hosted

extension LinkSelectionTests {
    /// Tagged views in an offscreen window: what they report while the
    /// tools are on, and that they report nothing while they're off.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows; serialized itself because the tools are
    /// one shared switchboard (`DevTools.shared`).
    @MainActor
    @Suite("Developer tools, hosted", .serialized)
    struct DevToolsHostedTests {
        private final class Hosted {
            let window: NSWindow
            let registry: DevTagRegistry

            init(window: NSWindow, registry: DevTagRegistry) {
                self.window = window
                self.registry = registry
            }

            func entry(named name: String) -> DevTagRegistry.Entry? {
                registry.entries.values.first { $0.tag?.name == name }
            }

            func close() {
                window.orderOut(nil)
                window.contentView = nil
            }
        }

        private static let theme = ResolvedTheme.fallbackLight

        private static func find(in view: NSView, where matches: (NSView) -> Bool) -> NSView? {
            if matches(view) { return view }
            for subview in view.subviews {
                if let found = find(in: subview, where: matches) { return found }
            }
            return nil
        }

        private func host<Content: View>(_ content: Content, size: CGSize = CGSize(width: 320, height: 200)) async throws -> Hosted {
            let registry = DevTagRegistry()
            let view = content
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .devToolsHost(isPrimary: true, registry: registry)
                .environment(\.theme, Self.theme)
                .environment(\.chatStyle, ChatStyle())
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: -8000, y: -8000), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            // On screen (far off it) without becoming key or activating anything.
            window.orderFrontRegardless()
            let hosted = Hosted(window: window, registry: registry)
            try await settle(hosted)
            return hosted
        }

        private func settle(_ hosted: Hosted) async throws {
            for _ in 0..<3 {
                try await Task.sleep(for: .milliseconds(50))
                hosted.window.contentView?.layoutSubtreeIfNeeded()
            }
        }

        private func reset() {
            DevTools.shared.isInspecting = false
            DevTools.shared.showsOutlines = false
            DevTools.shared.showsPerformanceHUD = false
        }

        /// A probe view: a 120 × 32 box with 6 × 10 padding.
        private var probe: some View {
            Text("Probe")
                .font(.system(size: 12, weight: .medium))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .frame(width: 120, height: 32)
                .background(Self.theme[ThemeKey.chatBackground])
                .devTag(
                    "Probe",
                    tokens: [ThemeKey.chatBackground, ThemeKey.chatForeground],
                    font: .system(size: 12, weight: .medium),
                    padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
                )
                .padding(.leading, 20)
                .padding(.top, 30)
        }

        @Test func taggedViewsReportNothingWhileTheToolsAreOff() async throws {
            reset()
            defer { reset() }
            let hosted = try await host(probe)
            defer { hosted.close() }
            #expect(hosted.registry.entries.isEmpty)
            #expect(!DevTools.shared.isTagging)
        }

        @Test func anInspectedViewReportsItsTokensFontSizeAndPadding() async throws {
            reset()
            defer { reset() }
            let hosted = try await host(probe)
            defer { hosted.close() }
            DevTools.shared.isInspecting = true
            try await settle(hosted)
            let entry = try #require(hosted.entry(named: "Probe"))
            #expect(entry.frame.size == CGSize(width: 120, height: 32))
            #expect(entry.frame.origin == CGPoint(x: 20, y: 30))
            // The pointer over it, in window coordinates.
            hosted.registry.pointer = CGPoint(x: 40, y: 40)
            let inspected = try #require(hosted.registry.inspected)
            let inspection = DevInspection(inspected, path: hosted.registry.path(to: inspected), theme: Self.theme)
            #expect(inspection.name == "Probe")
            #expect(inspection.tokens.map(\.key) == [ThemeKey.chatBackground, ThemeKey.chatForeground])
            #expect(inspection.tokens.map(\.hex) == [Self.theme.color(ThemeKey.chatBackground).hex, Self.theme.color(ThemeKey.chatForeground).hex])
            #expect(inspection.font == DevInspection.FontInfo(family: "SF Pro (system)", size: 12, weight: "Medium"))
            #expect(inspection.padding == EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
            #expect(inspection.size == CGSize(width: 120, height: 32))
            // Leaving inspect mode forgets the pointer and the views.
            DevTools.shared.isInspecting = false
            try await settle(hosted)
            #expect(hosted.registry.pointer == nil)
            #expect(hosted.registry.entries.isEmpty)
        }

        @Test func outlinesTurnTaggingOnAndOff() async throws {
            reset()
            defer { reset() }
            let hosted = try await host(VStack(alignment: .leading, spacing: 12) {
                UnreadBadge(count: 3)
                UnreadBadge(count: 1, isHighlight: true)
            }.padding(10))
            defer { hosted.close() }
            #expect(hosted.registry.entries.isEmpty)
            DevTools.shared.showsOutlines = true
            try await settle(hosted)
            // Real surfaces, tagged where they're drawn.
            let unread = try #require(hosted.entry(named: "Unread badge"))
            let mention = try #require(hosted.entry(named: "Mention badge"))
            #expect(unread.tag?.tokens == [ThemeKey.sidebarBadgeBackground, ThemeKey.sidebarBadgeForeground])
            #expect(mention.tag?.tokens == [ThemeKey.sidebarHighlightBadgeBackground, ThemeKey.sidebarHighlightBadgeForeground])
            #expect(unread.frame.height == 16)
            #expect(DevInspection(unread, theme: Self.theme).font?.weight == "Semibold")
            // The gap between them is the stack's spacing.
            let gaps = DevLayoutGaps.gaps(between: hosted.registry.shownEntries.map(\.shownFrame))
            #expect(gaps.map(\.length) == [12])
            DevTools.shared.showsOutlines = false
            try await settle(hosted)
            #expect(hosted.registry.entries.isEmpty)
        }

        @Test func theOutlinesAreDrawn() throws {
            var entry = DevTagRegistry.Entry(id: 1)
            entry.tag = DevTag(name: "Box", tokens: [], padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            entry.frame = CGRect(x: 10, y: 10, width: 80, height: 60)
            entry.visibleFrame = entry.frame
            let renderer = ImageRenderer(content: DevOutlines(entries: [entry], origin: .zero).frame(width: 100, height: 80))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            func alpha(_ x: Int, _ y: Int) -> UInt8 {
                let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
                return context.data!.load(fromByteOffset: 3, as: UInt8.self)
            }
            #expect(alpha(10, 40) > 0)    // the outline
            #expect(alpha(14, 40) > 0)    // the padding band
            #expect(alpha(50, 40) == 0)   // the content box
            #expect(alpha(2, 2) == 0)     // outside
        }

        @Test func openInThemeEditorAsksTheEditorForTheToken() {
            DevTools.shared.requestedThemeToken = nil
            defer { DevTools.shared.requestedThemeToken = nil }
            DevTools.shared.requestedThemeToken = ThemeKey.chatBackground
            #expect(DevTools.shared.requestedThemeToken == "chat.background")
        }

        @Test func theHUDShowsInThePrimaryWindowOnly() async throws {
            reset()
            defer { reset() }
            DevTools.shared.showsPerformanceHUD = true
            let primary = try await host(Color.clear)
            defer { primary.close() }
            #expect(Self.find(in: primary.window.contentView!) { $0 is DevDisplayLinkView } != nil)
            let registry = DevTagRegistry()
            let other = NSHostingView(rootView: Color.clear.frame(width: 100, height: 100).devToolsHost(isPrimary: false, registry: registry))
            other.layoutSubtreeIfNeeded()
            #expect(Self.find(in: other) { $0 is DevDisplayLinkView } == nil)
            DevTools.shared.showsPerformanceHUD = false
            try await settle(primary)
            #expect(Self.find(in: primary.window.contentView!) { $0 is DevDisplayLinkView } == nil)
        }
    }
}

#endif
