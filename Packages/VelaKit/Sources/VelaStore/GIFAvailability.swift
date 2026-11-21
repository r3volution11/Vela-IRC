// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// GIF search is only in development builds (Vela Dev) for now. Vela's KLIPY
/// key is still a test key, and releases wait for KLIPY to approve it for
/// production. Release builds leave out the GIF settings and the picker's
/// GIFs tab, and scripts/release.sh builds no key into them
/// (scripts/verify-release.sh checks).
public enum GIFAvailability {
    #if DEBUG
    public static let isBuiltIn = true
    #else
    public static let isBuiltIn = false
    #endif
}
