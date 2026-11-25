// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Test runs make no sound. The hosted UI tests open real windows and send
// them keys and commands, and one with nothing to do beeps, so this turns
// the beeps off once, as the test bundle loads, before any test runs: under
// `swift test` (both swiftpm-testing-helper and xctest load the bundle) and
// under Xcode alike, with no setup in the suites.
//
// - Vela's own beeps all go through `Beep` (VelaUI), which it silences.
// - AppKit's go through NSBeep(), which several paths call directly: a key
//   nothing handles (`-[NSResponder noResponderFor:]`) and a command nothing
//   performs (`-[NSWindow doCommandBySelector:]`,
//   `-[NSResponder doCommandBySelector:]`). NSBeep() plays the sound only
//   when AppKit's alert type, the process-wide setting behind "Flash the
//   screen when an alert sound occurs", includes sound, so this sets it to
//   neither sound nor flash. That setter is private (test code only), and
//   `SilentTestRunTests` fails if it's ever gone or undone.
//
// Set VELA_TEST_SOUNDS=1 to keep the sounds, for work that's about them.

#import <objc/message.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

#include "VelaTestSupport.h"

static bool beepSilenced;

static bool soundsKept(void) {
    const char *sounds = getenv("VELA_TEST_SOUNDS");
    return sounds != NULL && strcmp(sounds, "1") == 0;
}

/// AppKit's alert type: bit 0 plays the alert sound, bit 1 flashes the
/// screen. -1 when this AppKit has no such setting.
static long appKitAlertType(void) {
    Class sound = objc_getClass("NSSound");
    SEL getter = sel_registerName("_alertType");
    if (sound == Nil || !class_respondsToSelector(object_getClass(sound), getter)) return -1;
    return ((long (*)(Class, SEL))objc_msgSend)(sound, getter);
}

__attribute__((constructor))
static void silenceTestRun(void) {
    if (soundsKept()) return;

    // `Beep` is `@objc(VelaBeep)` in VelaUI, linked into this test bundle.
    Class beep = objc_getClass("VelaBeep");
    if (beep != Nil) {
        ((void (*)(Class, SEL))objc_msgSend)(beep, sel_registerName("silence"));
        beepSilenced = true;
    }

    Class sound = objc_getClass("NSSound");
    SEL setter = sel_registerName("_setAlertType:");
    if (sound != Nil && class_respondsToSelector(object_getClass(sound), setter)) {
        ((void (*)(Class, SEL, long))objc_msgSend)(sound, setter, 0);
    }
}

bool VelaTestRunIsSilent(void) {
    return beepSilenced && appKitAlertType() == 0;
}
