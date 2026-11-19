// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Dispatch
import VelaMedia

/// How hard macOS is asking apps to give memory back.
nonisolated enum MemoryPressureLevel: Sendable {
    /// Trim caches to about half.
    case warning
    /// Drop everything that isn't on screen. Views keep what they draw, so
    /// only rows scrolled back to decode again.
    case critical

    /// The share of each cache to keep.
    var keptFraction: Double {
        switch self {
        case .warning: 0.5
        case .critical: 0
        }
    }
}

/// Trims Vela's in-memory caches when macOS reports memory pressure.
///
/// The media caches are always trimmed; other caches (each list's
/// `MessageTextCache`) register themselves and are held weakly. Listening
/// starts with the first registration.
final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor(trimsMediaCaches: true)

    private var handlers: [(MemoryPressureLevel) -> Bool] = []
    private var source: DispatchSourceMemoryPressure?

    init(trimsMediaCaches: Bool = false) {
        guard trimsMediaCaches else { return }
        handlers.append { level in
            EmbedMemory.shared.trim(for: level)
            BlurredMedia.trim(for: level)
            LoopingPlayerPool.shared.trim(for: level)
            Task {
                if level == .critical {
                    await ImageLoader.shared.removeAllCachedImages()
                } else {
                    await ImageLoader.shared.trimCaches(keeping: level.keptFraction)
                }
            }
            return true
        }
    }

    /// Calls `trim` on `object` under memory pressure, for as long as it lives.
    func register<Object: AnyObject>(_ object: Object, trim: @escaping (Object, MemoryPressureLevel) -> Void) {
        startListening()
        handlers.append { [weak object] level in
            guard let object else { return false }
            trim(object, level)
            return true
        }
    }

    /// Runs every handler, forgetting those whose objects are gone.
    func handle(_ level: MemoryPressureLevel) {
        handlers = handlers.filter { $0(level) }
    }

    private func startListening() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated {
                self?.handle(event.contains(.critical) ? .critical : .warning)
            }
        }
        source.activate()
        self.source = source
    }
}
