// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreServices
import Foundation

/// Watches a directory tree with FSEvents and reports changed file paths.
///
/// FSEvents (with file-level events) catches both atomic saves (write to a
/// temp file, then rename) and in-place writes, which is how most editors
/// save. Events are coalesced over `latency` seconds.
public final class FileWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([URL]) -> Void

    private let url: URL
    private let latency: TimeInterval
    private let handler: Handler
    private let queue = DispatchQueue(label: "vela.filewatcher", qos: .utility)
    private var stream: FSEventStreamRef?

    public init(directory url: URL, latency: TimeInterval = 0.15, handler: @escaping Handler) {
        self.url = url
        self.latency = latency
        self.handler = handler
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    deinit { stop() }

    public func start() {
        queue.sync {
            guard stream == nil else { return }
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                let cfPaths = unsafeBitCast(paths, to: NSArray.self)
                var urls: [URL] = []
                for index in 0..<count {
                    if let path = cfPaths[index] as? String {
                        urls.append(URL(fileURLWithPath: path))
                    }
                }
                watcher.handler(urls)
            }
            let flags = UInt32(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagNoDefer
            )
            guard let created = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                [url.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            ) else { return }
            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
            stream = created
        }
    }

    public func stop() {
        let stopBlock = {
            guard let stream = self.stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            stopBlock()
        } else {
            queue.sync(execute: stopBlock)
        }
    }

    private static let queueKey = DispatchSpecificKey<Void>()
}
