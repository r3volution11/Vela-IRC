// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Private Cloud Compute for long catch-ups is only in development builds
/// (Vela Dev) for now. Apps need Apple's
/// `com.apple.developer.private-cloud-compute` entitlement to use it, and
/// Vela doesn't have it yet (Vela/Vela.entitlements), so in a release every
/// request would fall back to the Mac. Until Apple grants it, release builds
/// leave out the setting (`intelligence.privateCloudCompute`) and its switch
/// in Settings → Apple Intelligence, never offer Private Cloud Compute to
/// Catch me up, and don't mention it to Siri (scripts/verify-release.sh
/// checks). Catch me up always runs on the Mac there.
public enum PrivateCloudComputeAvailability {
    #if DEBUG
    public static let isBuiltIn = true
    #else
    public static let isBuiltIn = false
    #endif
}
