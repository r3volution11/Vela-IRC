// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import ImageIO
import Observation

/// Plays the frames of an animated GIF, APNG or WebP for SwiftUI to draw.
///
/// ImageIO's `CGAnimateImageDataWithBlock` does the decoding and timing; for
/// formats it rejects, frames are stepped manually with their own delays.
/// Pausing keeps the current frame; playing resumes from the next one.
@Observable
final class AnimatedImagePlayer {
    /// The frame to draw, or nil before playback first starts.
    private(set) var frame: CGImage?
    private(set) var isPlaying = false

    @ObservationIgnored private var data: Data?
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastIndex = -1
    @ObservationIgnored private var fallbackTask: Task<Void, Never>?

    /// Supplies the encoded image. Ignored when the same bytes are already loaded.
    func load(_ data: Data, frameCount: Int) {
        guard self.data != data else { return }
        pause()
        self.data = data
        self.frameCount = frameCount
        lastIndex = -1
        frame = nil
    }

    var canPlay: Bool { data != nil && frameCount > 1 }

    func play() {
        guard let data, frameCount > 1, !isPlaying else { return }
        isPlaying = true
        generation &+= 1
        let current = generation
        let start = (lastIndex + 1) % frameCount
        let options = [kCGImageAnimationStartIndex: start] as CFDictionary
        // The block runs on the main queue (ImageIO's default).
        let status = CGAnimateImageDataWithBlock(data as CFData, options) { [weak self] index, image, stop in
            guard let self, self.generation == current else {
                stop.pointee = true
                return
            }
            self.frame = image
            self.lastIndex = index
        }
        if status != 0 {
            playManually(from: start, generation: current)
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        generation &+= 1
        fallbackTask?.cancel()
        fallbackTask = nil
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    private func playManually(from start: Int, generation current: Int) {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            isPlaying = false
            return
        }
        let count = frameCount
        fallbackTask = Task { [weak self] in
            var index = start
            while !Task.isCancelled {
                guard let self, self.generation == current else { return }
                if let image = CGImageSourceCreateImageAtIndex(source, index, nil) {
                    self.frame = image
                    self.lastIndex = index
                }
                let delay = Self.frameDelay(in: source, at: index)
                try? await Task.sleep(for: .seconds(delay))
                index = (index + 1) % count
            }
        }
    }

    /// The frame's delay in seconds. Like browsers, delays of 10 ms or less
    /// play at 100 ms.
    private static func frameDelay(in source: CGImageSource, at index: Int) -> Double {
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
}
