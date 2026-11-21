// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG

import AppKit
import Darwin
import Observation
import QuartzCore
import SwiftUI

// The Performance HUD (Developer → Show Performance HUD, ⌥⌘P): frame
// times and dropped frames from the main window's display link, main-thread
// stalls, the memory footprint and how many message rows were built. Its
// display link runs only while the HUD is showing; the numbers it shows
// refresh twice a second.
//
// The frames are the display link's callbacks on the main thread, as
// `scripts/benchmark-scroll.sh` measures them: a callback that comes late
// means the main thread was busy when a frame was due. A frame counts as a
// hitch when it's more than 1.5 refresh intervals after the last one (the
// benchmark's "hitch ms/s" adds up how late they were); a stall is a gap of
// 50 ms or more.

/// Frame accounting from display link timestamps. Pure, for tests.
nonisolated struct DevFrameStats: Sendable {
    /// What the summary covers.
    static let window: CFTimeInterval = 1
    /// A gap this long is a stall: the main thread was blocked.
    static let stallThreshold: CFTimeInterval = 0.05

    private struct Frame: Sendable {
        var time: CFTimeInterval
        var interval: CFTimeInterval
        var dropped: Int
        var hitch: CFTimeInterval
    }

    private var last: CFTimeInterval?
    private var recent: [Frame] = []
    private(set) var totalFrames = 0
    private(set) var totalDropped = 0
    private(set) var stalls = 0
    private(set) var longestStall: CFTimeInterval = 0

    init() {}

    /// A display link callback at `timestamp`, `refresh` seconds per frame.
    mutating func record(timestamp: CFTimeInterval, refresh: CFTimeInterval) {
        defer { last = timestamp }
        guard let last, timestamp > last, refresh > 0 else { return }
        let interval = timestamp - last
        let elapsed = max(1, Int((interval / refresh).rounded()))
        let frame = Frame(
            time: timestamp,
            interval: interval,
            dropped: elapsed - 1,
            hitch: interval > refresh * 1.5 ? interval - refresh : 0
        )
        totalFrames += 1
        totalDropped += frame.dropped
        if interval >= Self.stallThreshold {
            stalls += 1
            longestStall = max(longestStall, interval)
        }
        recent.append(frame)
        if let stale = recent.firstIndex(where: { $0.time > timestamp - Self.window }), stale > 0 {
            recent.removeFirst(stale)
        }
    }

    /// The window was hidden or the HUD paused: the next callback starts
    /// afresh rather than counting the pause as a stall.
    mutating func pause() {
        last = nil
    }

    struct Summary: Equatable, Sendable {
        var fps: Double = 0
        var averageFrame: CFTimeInterval = 0
        var worstFrame: CFTimeInterval = 0
        /// Dropped in the last second.
        var dropped = 0
        /// How late the late frames of the last second were, in seconds per second.
        var hitchRatio: Double = 0
    }

    /// The last second's frames.
    var summary: Summary {
        guard !recent.isEmpty else { return Summary() }
        let span = recent.reduce(0) { $0 + $1.interval }
        guard span > 0 else { return Summary() }
        return Summary(
            fps: Double(recent.count) / span,
            averageFrame: span / Double(recent.count),
            worstFrame: recent.map(\.interval).max() ?? 0,
            dropped: recent.reduce(0) { $0 + $1.dropped },
            hitchRatio: recent.reduce(0) { $0 + $1.hitch } / span
        )
    }
}

/// The HUD's numbers, published twice a second while it's showing.
@Observable
final class DevPerformanceMonitor {
    struct Snapshot: Equatable {
        var frames = DevFrameStats.Summary()
        var totalDropped = 0
        var stalls = 0
        var longestStall: CFTimeInterval = 0
        var memory: UInt64?
        var rowsPerSecond: Double = 0
        var rowsTotal = 0
    }

    static let publishInterval: CFTimeInterval = 0.5

    private(set) var snapshot = Snapshot()

    @ObservationIgnored private var stats = DevFrameStats()
    @ObservationIgnored private var lastPublish: CFTimeInterval?
    @ObservationIgnored private var rowsAtStart: Int?
    @ObservationIgnored private var lastRows: (time: CFTimeInterval, count: Int)?
    @ObservationIgnored private let memory: () -> UInt64?
    @ObservationIgnored private let rowBodies: () -> Int

    init(memory: @escaping () -> UInt64? = DevMemory.footprint, rowBodies: @escaping () -> Int = { DevCounters.messageRowBodies }) {
        self.memory = memory
        self.rowBodies = rowBodies
    }

    /// A display link callback (`DevDisplayLink`).
    func recordFrame(timestamp: CFTimeInterval, refresh: CFTimeInterval) {
        stats.record(timestamp: timestamp, refresh: refresh)
        if let lastPublish, timestamp - lastPublish < Self.publishInterval { return }
        publish(at: timestamp)
    }

    /// The display link stopped or the window was hidden.
    func pause() {
        stats.pause()
    }

    /// Starts counting again from nothing (the HUD was turned on).
    func reset() {
        stats = DevFrameStats()
        lastPublish = nil
        rowsAtStart = nil
        lastRows = nil
        snapshot = Snapshot()
    }

    func publish(at time: CFTimeInterval) {
        lastPublish = time
        let rows = rowBodies()
        if rowsAtStart == nil { rowsAtStart = rows }
        var perSecond = 0.0
        if let lastRows, time > lastRows.time {
            perSecond = Double(rows - lastRows.count) / (time - lastRows.time)
        }
        lastRows = (time, rows)
        snapshot = Snapshot(
            frames: stats.summary,
            totalDropped: stats.totalDropped,
            stalls: stats.stalls,
            longestStall: stats.longestStall,
            memory: memory(),
            rowsPerSecond: perSecond,
            rowsTotal: rows - (rowsAtStart ?? rows)
        )
    }
}

enum DevMemory {
    /// The process's memory footprint, as Activity Monitor's Memory column
    /// shows it (`phys_footprint`).
    nonisolated static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : nil
    }
}

// MARK: - Display link

/// Feeds the monitor from the window's display link while it's on screen.
struct DevDisplayLink: NSViewRepresentable {
    let monitor: DevPerformanceMonitor

    func makeNSView(context: Context) -> DevDisplayLinkView {
        DevDisplayLinkView(monitor: monitor)
    }

    func updateNSView(_ view: DevDisplayLinkView, context: Context) {}

    static func dismantleNSView(_ view: DevDisplayLinkView, coordinator: ()) {
        view.stop()
    }
}

final class DevDisplayLinkView: NSView {
    private let monitor: DevPerformanceMonitor
    private var link: CADisplayLink?
    private var occlusionObserver: NSObjectProtocol?

    init(monitor: DevPerformanceMonitor) {
        self.monitor = monitor
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard let window else { return }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        // Hidden, the window gets no callbacks; that gap isn't a stall.
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.monitor.pause() }
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        monitor.pause()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let refresh = link.duration > 0 ? link.duration : link.targetTimestamp - link.timestamp
        monitor.recordFrame(timestamp: link.timestamp, refresh: refresh)
    }
}

// MARK: - HUD

/// The HUD panel. Drawn in fixed colors, like the inspector, so it reads
/// the same over every theme.
struct DevPerformanceHUD: View {
    let monitor: DevPerformanceMonitor

    var body: some View {
        let snapshot = monitor.snapshot
        let frames = snapshot.frames
        VStack(alignment: .leading, spacing: 2) {
            row("frame", "\(Self.number(frames.fps, digits: 0)) fps · \(Self.ms(frames.averageFrame)) (worst \(Self.ms(frames.worstFrame)))",
                warn: frames.worstFrame > 1.0 / 30)
            row("dropped", "\(frames.dropped)/s · \(snapshot.totalDropped) total", warn: frames.dropped > 0)
            row("hitches", "\(Self.number(frames.hitchRatio * 1_000, digits: 1)) ms/s", warn: frames.hitchRatio > 0.005)
            row("stalls", snapshot.stalls == 0 ? "none ≥50 ms" : "\(snapshot.stalls) ≥50 ms · longest \(Self.ms(snapshot.longestStall))",
                warn: snapshot.stalls > 0)
            row("memory", snapshot.memory.map(Self.megabytes) ?? "—", warn: false)
            row("rows", "\(Self.number(snapshot.rowsPerSecond, digits: 0))/s · \(snapshot.rowsTotal) built", warn: false)
        }
        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
        .foregroundStyle(DevStyle.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(DevStyle.panel, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DevStyle.panelBorder))
        .background { DevDisplayLink(monitor: monitor).frame(width: 1, height: 1) }
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Performance HUD")
    }

    private func row(_ label: String, _ value: String, warn: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(DevStyle.secondaryText)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .foregroundStyle(warn ? DevStyle.warning : DevStyle.text)
        }
    }

    static func ms(_ seconds: CFTimeInterval) -> String {
        "\(number(seconds * 1_000, digits: 1)) ms"
    }

    static func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func megabytes(_ bytes: UInt64) -> String {
        "\(number(Double(bytes) / 1_048_576, digits: 1)) MB"
    }
}

#endif
