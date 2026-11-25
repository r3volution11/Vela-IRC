// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

/// Vela's beep: the alert sound for a key with nothing to do, a message that
/// can't be sent, a completion with no match.
///
/// Every beep Vela makes goes through `Beep.play()`, never `NSSound.beep()`
/// directly, so there's one place that decides what a beep does. The test
/// run silences it as the test bundle loads (`VelaTestSupport` calls
/// `silence()`), and a test can count beeps by swapping `sound`.
@objc(VelaBeep)
final class Beep: NSObject {
    /// What a beep does: the user's alert sound. Set before the first beep
    /// (or by a test on the main actor), and only read on the main actor.
    nonisolated(unsafe) static var sound: @MainActor () -> Void = { NSSound.beep() }

    /// Plays the alert sound (or whatever `sound` does now).
    static func play() {
        sound()
    }

    /// Turns beeps off for the rest of the process. The test run calls it
    /// through the Objective-C runtime as the test bundle loads, before any
    /// test runs; the app never does.
    @objc nonisolated static func silence() {
        sound = {}
    }
}
