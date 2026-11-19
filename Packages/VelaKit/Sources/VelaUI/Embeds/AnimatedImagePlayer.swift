// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Observation
import QuartzCore
import SwiftUI

/// Plays the frames of an animated GIF, APNG or WebP into a layer.
///
/// Frames are decoded off the main actor, downsampled to the size they're
/// drawn at, and handed straight to an `AnimatedFrameView`'s layer, so
/// SwiftUI does no work per frame. Pausing keeps the current frame; playing
/// resumes from the next one.
@Observable
final class AnimatedImagePlayer {
    /// A frame has been shown, so the frame view has something to draw.
    private(set) var hasFrame = false
    private(set) var isPlaying = false

    @ObservationIgnored private var data: Data?
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var maxPixelSize = 1
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastIndex = -1
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The frame on screen, for a layer attached after it was decoded.
    @ObservationIgnored private var frame: CGImage?
    @ObservationIgnored private weak var layer: CALayer?

    /// Supplies the encoded image and the longest side, in pixels, to decode
    /// its frames at. Ignored when nothing changed.
    func load(_ data: Data, frameCount: Int, maxPixelSize: Int) {
        let maxPixelSize = max(1, maxPixelSize)
        if self.data == data, self.frameCount == frameCount {
            guard maxPixelSize != self.maxPixelSize else { return }
            // Moved to a display with another scale: later frames use it.
            self.maxPixelSize = maxPixelSize
            if isPlaying {
                pause()
                play()
            }
            return
        }
        pause()
        self.data = data
        self.frameCount = frameCount
        self.maxPixelSize = maxPixelSize
        lastIndex = -1
        frame = nil
        setContents(nil)
        if hasFrame { hasFrame = false }
    }

    var canPlay: Bool { data != nil && frameCount > 1 }

    func play() {
        guard let data, frameCount > 1, !isPlaying else { return }
        isPlaying = true
        generation &+= 1
        let current = generation
        let start = (lastIndex + 1) % frameCount
        let count = frameCount
        let maxPixelSize = maxPixelSize
        let show: @MainActor @Sendable (CGImage, Int) -> Bool = { [weak self] image, index in
            self?.show(image, index: index, generation: current) ?? false
        }
        // Below the UI's priority: a late frame matters less than a smooth scroll.
        task = Task(priority: .utility) {
            await AnimatedFrames.play(data, from: start, frameCount: count, maxPixelSize: maxPixelSize, show: show)
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        generation &+= 1
        task?.cancel()
        task = nil
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    /// Where frames go; the latest one is drawn straight away.
    func attach(_ layer: CALayer) {
        guard layer !== self.layer else { return }
        self.layer = layer
        setContents(frame)
    }

    /// Shows a decoded frame, unless playback was paused or restarted since.
    private func show(_ image: CGImage, index: Int, generation current: Int) -> Bool {
        guard generation == current else { return false }
        frame = image
        lastIndex = index
        setContents(image)
        if !hasFrame { hasFrame = true }
        return true
    }

    private func setContents(_ image: CGImage?) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }
}

/// Frame decoding for `AnimatedImagePlayer`, off the main actor.
nonisolated enum AnimatedFrames {
    /// Decodes frames from `start` onward, each at most `maxPixelSize` on its
    /// longest side, and hands each to `show` when its time comes. Stops when
    /// cancelled or when `show` returns false.
    @concurrent
    static func play(
        _ data: Data,
        from start: Int,
        frameCount: Int,
        maxPixelSize: Int,
        show: @escaping @MainActor @Sendable (CGImage, Int) -> Bool
    ) async {
        guard frameCount > 1,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return }
        let clock = ContinuousClock()
        var due = clock.now
        var index = start % frameCount
        var failures = 0
        while !Task.isCancelled {
            // The next frame decodes while the current one is on screen.
            let image = frame(at: index, in: source, maxPixelSize: maxPixelSize)
            let delay = frameDelay(in: source, at: index)
            do { try await clock.sleep(until: due) } catch { return }
            if let image {
                failures = 0
                guard await show(image, index) else { return }
            } else {
                // Nothing decodes: stop rather than spin.
                failures += 1
                if failures >= frameCount { return }
            }
            // A frame that comes late doesn't make the next ones hurry.
            due = max(due.advanced(by: .seconds(delay)), clock.now)
            index = (index + 1) % frameCount
        }
    }

    /// Frame `index`, decoded now (not when first drawn) and downsampled to
    /// at most `maxPixelSize` on its longest side.
    static func frame(at index: Int, in source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    /// The frame's delay in seconds. Like browsers, delays of 10 ms or less
    /// play at 100 ms.
    static func frameDelay(in source: CGImageSource, at index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        let containers: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for (container, unclamped, clamped) in containers {
            guard let values = properties[container] as? [CFString: Any] else { continue }
            let delay = (values[unclamped] as? Double) ?? (values[clamped] as? Double) ?? 0.1
            return delay <= 0.011 ? 0.1 : delay
        }
        return 0.1
    }

    /// The longest side, in pixels, to decode frames at: the size the image
    /// is drawn at on a `scale`× display, never more than its own.
    static func pixelBudget(pixelSize: CGSize, maxWidth: CGFloat, maxHeight: CGFloat, scale: CGFloat) -> Int {
        let fitted = FittedMediaLayout(
            aspectRatio: pixelSize.width / max(1, pixelSize.height),
            naturalSize: pixelSize,
            maxWidth: maxWidth,
            maxHeight: maxHeight
        ).fittedSize(availableWidth: maxWidth)
        let drawn = Int((max(fitted.width, fitted.height) * max(1, scale)).rounded(.up))
        let own = Int(max(pixelSize.width, pixelSize.height).rounded(.up))
        return max(1, min(drawn, own))
    }
}

/// Draws an `AnimatedImagePlayer`'s frames: a layer it sets directly,
/// rounded like the image under it.
struct AnimatedFrameView: NSViewRepresentable {
    let player: AnimatedImagePlayer
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> AnimatedFrameNSView {
        let view = AnimatedFrameNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: AnimatedFrameNSView, context: Context) {
        view.frameLayer.cornerRadius = cornerRadius
        player.attach(view.frameLayer)
    }
}

final class AnimatedFrameNSView: NSView {
    let frameLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Stretched to the frame, like a resizable `Image`.
        frameLayer.contentsGravity = .resize
        frameLayer.minificationFilter = .trilinear
        frameLayer.cornerCurve = .continuous
        frameLayer.masksToBounds = true
        frameLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(frameLayer)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frameLayer.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
