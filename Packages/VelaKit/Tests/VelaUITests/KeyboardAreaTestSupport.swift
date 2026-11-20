// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaIntelligence
import VelaStore
import VelaTheme
@testable import VelaUI

/// The main window (or a part of it) in an offscreen window that's never
/// shown or made key, with keys sent to it as AppKit delivers them, for the
/// keyboard focus areas: the sidebar, the tabs and the member list.
@MainActor
final class KeyboardHostedWindow {
    let app: AppModel
    let uiState: UIState
    let window: NSWindow
    let host: NSView
    /// The folded networks as they were before, put back on close (the
    /// sidebar keeps them in the defaults).
    private let savedCollapsedNetworks: Any?

    private init(app: AppModel, uiState: UIState, window: NSWindow, host: NSView, savedCollapsedNetworks: Any?) {
        self.app = app
        self.uiState = uiState
        self.window = window
        self.host = host
        self.savedCollapsedNetworks = savedCollapsedNetworks
    }

    /// `MainWindowView`, or `content`, with the app's environment, after
    /// `configure` has set up the demo app.
    static func show(
        size: CGSize = CGSize(width: 1100, height: 700),
        configure: (AppModel) -> Void = { _ in },
        content: (() -> AnyView)? = nil
    ) async throws -> KeyboardHostedWindow {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: SidebarMetrics.collapsedNetworksKey)
        defaults.removeObject(forKey: SidebarMetrics.collapsedNetworksKey)
        let app = AppModel.demo()
        app.settings[.mediaShowLinkCards] = false
        app.settings[.mediaAutoLoad] = false
        configure(app)
        let uiState = UIState()
        let themeStore = ThemeStore(
            userThemesDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("VelaKeyboard-\(UUID().uuidString)"),
            settings: ThemeSettings(settings: app.settings)
        )
        let root = content?() ?? AnyView(MainWindowView())
        let view = root
            .velaEnvironment(app: app, themeStore: themeStore, uiState: uiState, services: SceneServices(intelligence: .demo()), isPrimary: false)
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        let hosted = KeyboardHostedWindow(app: app, uiState: uiState, window: window, host: host, savedCollapsedNetworks: saved)
        try await hosted.settle()
        return hosted
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
        if let savedCollapsedNetworks {
            UserDefaults.standard.set(savedCollapsedNetworks, forKey: SidebarMetrics.collapsedNetworksKey)
        } else {
            UserDefaults.standard.removeObject(forKey: SidebarMetrics.collapsedNetworksKey)
        }
    }

    /// Lets SwiftUI and AppKit catch up: new message boxes attach, focus
    /// reports land.
    func settle() async throws {
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(60))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(40))
    }

    // MARK: The focus

    /// The keyboard focus area that has the focus, if one does.
    var focusedArea: KeyboardFocusView? { window.firstResponder as? KeyboardFocusView }

    /// The message box has the focus.
    var messageBoxHasFocus: Bool { window.firstResponder is ComposerNSTextView }

    /// A text field's editor has the focus (the member list's filter).
    var fieldEditorHasFocus: Bool { (window.firstResponder as? NSTextView)?.isFieldEditor == true }

    /// Waits for the message box to take the focus, as it does a moment
    /// after a request.
    func waitForMessageBox() async throws -> Bool {
        for _ in 0..<20 where !messageBoxHasFocus {
            try await Task.sleep(for: .milliseconds(30))
        }
        return messageBoxHasFocus
    }

    // MARK: Keys

    enum Key {
        case up, down, left, right, home, end, pageUp, pageDown
        case `return`, escape, space, tab
        case shiftF10
        case text(String)
    }

    private static let letterCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46,
    ]

    /// The clock key presses are stamped with; type-select starts over a
    /// second after the last key.
    var time = ProcessInfo.processInfo.systemUptime

    /// Presses `key` (or types each character of a `.text`), `pause`
    /// seconds after the last key, and lets the window catch up.
    func press(_ key: Key, after pause: TimeInterval = 0.1) async throws {
        time += pause
        switch key {
        case .text(let text):
            for character in text {
                let code = Self.letterCodes[Character(character.lowercased())] ?? 0
                send(String(character), code: code, modifiers: character.isUppercase ? .shift : [])
                time += 0.05
            }
        default:
            let (scalar, code, modifiers): (UInt32, UInt16, NSEvent.ModifierFlags) = switch key {
            case .up: (0xF700, 126, [.numericPad, .function])
            case .down: (0xF701, 125, [.numericPad, .function])
            case .left: (0xF702, 123, [.numericPad, .function])
            case .right: (0xF703, 124, [.numericPad, .function])
            case .home: (0xF729, 115, .function)
            case .end: (0xF72B, 119, .function)
            case .pageUp: (0xF72C, 116, .function)
            case .pageDown: (0xF72D, 121, .function)
            case .return: (0x0D, 36, [])
            case .escape: (0x1B, 53, [])
            case .space: (0x20, 49, [])
            case .tab: (0x09, 48, [])
            case .shiftF10: (0xF70D, 109, [.shift, .function])
            case .text: (0, 0, [])
            }
            send(String(Character(Unicode.Scalar(scalar)!)), code: code, modifiers: modifiers)
        }
        try await settle()
    }

    private func send(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers,
                timestamp: time, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters.lowercased(),
                isARepeat: false, keyCode: code
            )!
            window.sendEvent(event)
        }
    }

    // MARK: Clicks

    private static var eventNumber = 61000

    /// Clicks the element VoiceOver calls `label`, in its middle, with real
    /// mouse events.
    func click(_ label: String, count: Int = 1) async throws {
        let frame = try #require(accessibilityFrames()[label], "no \(label)")
        let point = CGPoint(x: frame.midX, y: frame.midY)
        // The test runner is never the active app, so AppKit only passes a
        // click on to a view that takes the first mouse.
        let accept: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
        class_addMethod(type(of: host), #selector(NSView.acceptsFirstMouse(for:)), imp_implementationWithBlock(accept), "c@:@")
        for clickCount in 1...count {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                Self.eventNumber += 1
                NSApp.sendEvent(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: Self.eventNumber, clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1
                )!)
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        try await settle()
    }

    /// Each element's frame in the window, by its VoiceOver label (the
    /// first one with it).
    func accessibilityFrames() -> [String: CGRect] {
        let enhancedInterface = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
        NSApp.perform(enhancedInterface, with: NSNumber(value: true))
        defer { NSApp.perform(enhancedInterface, with: NSNumber(value: false)) }
        var frames: [String: CGRect] = [:]
        func visit(_ object: AnyObject) {
            if let label = object.accessibilityLabel?() ?? nil, frames[label] == nil {
                frames[label] = window.convertFromScreen(object.accessibilityFrame?() ?? .zero)
            }
            for child in (object.accessibilityChildren?() ?? nil) ?? [] { visit(child as AnyObject) }
        }
        visit(window)
        return frames
    }

    // MARK: Finding things

    static func findAll(in view: NSView, where matches: (NSView) -> Bool) -> [NSView] {
        (matches(view) ? [view] : []) + view.subviews.flatMap { findAll(in: $0, where: matches) }
    }

    /// The name of what's selected: a channel, a nick or a network.
    var selectedName: String? {
        guard let buffer = app.selectedBuffer else { return nil }
        return buffer.kind == .server ? app.selectedSession?.displayName : buffer.name
    }

    func session(_ name: String) throws -> NetworkSession {
        try #require(app.sessions.first { $0.displayName == name })
    }
}
