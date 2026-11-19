// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// URL protocols that the media sessions (link previews, images, GIF sites'
/// videos) consult before the network.
///
/// Empty in normal use, which leaves the sessions as they are. The scroll
/// benchmark (`--demo --scroll-benchmark`) sets it before any session is
/// made, so its channel's previews and media come from local stand-ins and
/// nothing leaves the Mac.
public enum MediaSessionHooks {
    nonisolated(unsafe) public static var protocolClasses: [AnyClass] = []

    /// Puts `protocolClasses` in front of the configuration's own.
    static func apply(to configuration: URLSessionConfiguration) {
        guard !protocolClasses.isEmpty else { return }
        configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? [])
    }
}
