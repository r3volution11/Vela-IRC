// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Testing
import VelaTestSupport
@testable import VelaUI

/// Test runs make no sound (CONTRIBUTING.md, "Tests").
@MainActor
struct SilentTestRunTests {
    nonisolated static let soundsKept = ProcessInfo.processInfo.environment["VELA_TEST_SOUNDS"] == "1"

    /// The test bundle turned Vela's beeps and AppKit's off as it loaded.
    @Test(.disabled(if: soundsKept, "VELA_TEST_SOUNDS=1 keeps the sounds on"))
    func theRunIsSilent() {
        #expect(VelaTestRunIsSilent())
    }

    /// Everything that beeps in a hosted window, done on purpose: Vela's own
    /// beep, a command nothing performs and a key nothing handles (AppKit
    /// beeps for both by itself). None of it makes a sound in a test run, as
    /// the system's sound log shows while it runs (CONTRIBUTING.md).
    @Test(.disabled(if: soundsKept, "VELA_TEST_SOUNDS=1 keeps the sounds on"))
    func whatWouldBeepIsSilent() throws {
        let text = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let window = NSWindow(contentRect: CGRect(x: -9000, y: -9000, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = text
        window.orderFrontRegardless()

        Beep.play()
        window.makeFirstResponder(text)
        text.doCommand(by: Selector(("velaNothingPerformsThis:")))
        NSView().doCommand(by: #selector(NSResponder.pageDown(_:)))
        window.makeFirstResponder(nil)
        let key = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        window.sendEvent(key)
        #expect(VelaTestRunIsSilent())
    }

    /// A beep is whatever `Beep.sound` does, so a test can count them.
    @Test func beepsGoThroughTheHook() {
        final class Count { var beeps = 0 }
        let count = Count()
        let sound = Beep.sound
        defer { Beep.sound = sound }
        Beep.sound = { count.beeps += 1 }
        Beep.play()
        #expect(count.beeps == 1)
    }

    /// App code beeps through `Beep`, never `NSSound.beep()` or `NSBeep()`
    /// itself, so there's one place that silences every beep in tests.
    @Test func appCodeBeepsThroughBeep() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let folders = ["Packages/VelaKit/Sources", "Vela"].map { repository.appendingPathComponent($0) }
        var checked = 0
        for folder in folders {
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
            while let file = files?.nextObject() as? URL {
                guard file.pathExtension == "swift", file.lastPathComponent != "Beep.swift" else { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                #expect(!text.contains("NSSound.beep(") && !text.contains("NSBeep("), "\(file.lastPathComponent) beeps itself: use Beep.play()")
                checked += 1
            }
        }
        #expect(checked > 100)
    }
}
