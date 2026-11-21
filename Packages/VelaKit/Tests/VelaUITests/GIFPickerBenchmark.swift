// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Darwin
import Foundation
import SwiftUI
import Testing
@testable import VelaCore
import VelaMedia
import VelaStore
@testable import VelaUI

/// What the GIF picker costs: CPU and memory with the picker closed, open
/// with its previews playing, scrolled through well over 100 animated
/// previews, and closed again. Offscreen, with fake services; nothing
/// leaves the Mac. Opt-in, and run on its own, since it measures the whole
/// process:
///
///     VELA_GIF_PICKER_BENCHMARK=1 [VELA_GIF_PICKER_PREVIEW=/path/to/preview.webp] \
///         swift test --package-path Packages/VelaKit --filter GIFPickerBenchmark
///
/// `VELA_GIF_PICKER_PREVIEW` is the preview every cell plays (a KLIPY
/// `sm` WebP is the real thing: 220×220, about 15 frames); without it, an
/// 8-frame GIF made here.
@MainActor
@Suite("GIF picker benchmark", .serialized, .enabled(if: ProcessInfo.processInfo.environment["VELA_GIF_PICKER_BENCHMARK"] == "1"))
struct GIFPickerBenchmark {
    struct Sample {
        var cpuSeconds: Double
        var wall: Double
        var footprintMB: Double
    }

    /// User and system CPU time of the whole process.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// What Activity Monitor calls Memory.
    /// Bytes the process's heap has in use now: what's live, unlike the
    /// footprint, which keeps pages the allocator hasn't given back.
    static func heapInUseMB() -> Double {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Double(stats.size_in_use) / 1_048_576
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// CPU use (100% = one core) and the peak footprint over `seconds`,
    /// running `step` every 16 ms.
    static func measure(_ seconds: Double, step: () -> Void = {}) async throws -> (cpu: Double, peakMB: Double) {
        let startCPU = cpuSeconds()
        let start = Date()
        var peak = footprintMB()
        var ticks = 0
        while Date().timeIntervalSince(start) < seconds {
            step()
            try await Task.sleep(for: .milliseconds(16))
            ticks += 1
            if ticks % 15 == 0 { peak = max(peak, footprintMB()) }
        }
        let wall = Date().timeIntervalSince(start)
        return ((cpuSeconds() - startCPU) / wall * 100, max(peak, footprintMB()))
    }

    /// `keepsFrames: false` decodes every frame every time, for comparison.
    private func run(animated: Bool, keepsFrames: Bool = true) async throws -> [String] {
        let budget = GIFSearchServices.keptFramesPerPreview
        if !keepsFrames { GIFSearchServices.keptFramesPerPreview = 0 }
        defer { GIFSearchServices.keptFramesPerPreview = budget }
        let name = !animated ? "stills     " : keepsFrames ? "animated   " : "every frame"
        if let path = ProcessInfo.processInfo.environment["VELA_GIF_PICKER_PREVIEW"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            GIFMediaStandIn.payload.withLock { $0 = (data, path.hasSuffix(".webp") ? "image/webp" : "image/gif") }
        }
        defer { GIFMediaStandIn.payload.withLock { $0 = nil } }
        GIFMediaStandIn.loads.withLock { $0.removeAll() }
        ComposerPickerTab.remembered = .gifs
        let hosted = try PickerHost { $0.settings[.gifsAnimatePreviews] = animated }
        defer { hosted.close() }
        try await hosted.settle(1_500)
        var lines: [String] = []
        func line(_ label: String, _ result: (cpu: Double, peakMB: Double)) {
            lines.append(String(format: "%@  %-32@ CPU %5.1f%%   footprint (peak) %6.1f MB   heap in use %6.1f MB", name as NSString, label as NSString, result.cpu, result.peakMB, Self.heapInUseMB()))
        }

        line("closed (idle)", try await Self.measure(3))
        try await hosted.openPicker()
        #expect(try await hosted.wait(5) { hosted.element("Trending 100", prefix: true, inPicker: true) != nil })
        try await hosted.settle(1_000)
        line("open, first page in view", try await Self.measure(5))

        let content = try #require(hosted.pickerWindow?.contentView)
        let scrollView = try #require(PickerHost.findAll(in: content) { $0 is NSScrollView }.compactMap { $0 as? NSScrollView }.max { $0.frame.height < $1.frame.height })
        // Down through the results at about 500 pt a second, pages loading
        // as the end comes into view, until 120 results have gone by.
        var offset: CGFloat = 0
        let scrolling = try await Self.measure(9) {
            let documentHeight = scrollView.documentView?.frame.height ?? 0
            offset = min(offset + 8, max(0, documentHeight - scrollView.contentSize.height))
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        line("scrolling through the results", scrolling)
        let requests = hosted.gifs.transport.trendingRequests.count
        let animations = Set(GIFMediaStandIn.loads.withLock { $0 }.filter { $0.path().hasPrefix("/animation/") }).count
        let stills = Set(GIFMediaStandIn.loads.withLock { $0 }.filter { $0.path().hasPrefix("/still/") }).count
        lines.append("          scrolled \(Int(offset)) pt: \(requests) pages (\(requests * 24) results), \(animations) animated previews and \(stills) stills loaded")
        line("open, scrolled to the end", try await Self.measure(5))

        lines.append("          \(hosted.gifs.services.playingPreviews) previews playing")
        let picker = try #require(hosted.pickerWindow)
        try await hosted.press(.escape, in: picker, settling: 2_000)
        line("closed again", try await Self.measure(3))
        lines.append("          \(hosted.gifs.services.playingPreviews) previews playing after closing")
        return lines
    }

    @Test func costOfThePicker() async throws {
        var lines = ["", "GIF picker benchmark (\(ProcessInfo.processInfo.environment["VELA_GIF_PICKER_PREVIEW"].map { URL(fileURLWithPath: $0).lastPathComponent } ?? "made-up 8-frame GIF")), \(ProcessInfo.processInfo.processorCount) cores, \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB"]
        lines += try await run(animated: true)
        lines += try await run(animated: true, keepsFrames: false)
        lines += try await run(animated: false)
        print(lines.joined(separator: "\n"))
    }
}
