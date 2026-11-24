// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import Testing
import VelaCore
import VelaStore
@testable import VelaUI

extension LinkSelectionTests {
    /// Switching layouts (`navigation.style`) in the hosted main window:
    /// the message list is resized once, not on every frame of an
    /// animation, which laid out every visible message again and again.
    ///
    /// Nested in the serialized `LinkSelectionTests` with the other suites
    /// that use offscreen windows.
    @MainActor
    @Suite("Switching layouts, hosted", .serialized)
    struct LayoutSwitchHostedTests {
        /// The message list's scroll view: the widest one in the window.
        private func messageList(in view: NSView) -> NSScrollView? {
            var scrollViews: [NSScrollView] = []
            func visit(_ view: NSView) {
                if let scrollView = view as? NSScrollView { scrollViews.append(scrollView) }
                view.subviews.forEach(visit)
            }
            visit(view)
            return scrollViews.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        }

        @Test(arguments: [NavigationStyle.tabs, .focus])
        func theMessageListIsResizedOnce(to style: NavigationStyle) async throws {
            let hosted = try await KeyboardHostedWindow.show(configure: { app in
                app.settings[.navigationStyle] = .sidebar
            }, reduceMotion: false)
            defer { hosted.close() }
            let list = try #require(messageList(in: hosted.host))
            let before = list.frame.width
            var resizes = 0
            list.postsFrameChangedNotifications = true
            let observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: list, queue: nil) { _ in
                MainActor.assumeIsolated { resizes += 1 }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            hosted.app.settings[.navigationStyle] = style
            let widened = await RunningDeadline.wait(timeout: .seconds(5), every: .milliseconds(20)) {
                hosted.window.contentView?.layoutSubtreeIfNeeded()
                return list.frame.width > before
            }
            #expect(widened, "the list didn't widen")
            // Then longer than the animation was, for any frames after it.
            for _ in 0..<8 {
                try await Task.sleep(for: .milliseconds(50))
                hosted.window.contentView?.layoutSubtreeIfNeeded()
            }
            #expect(resizes <= 2, "resized \(resizes) times")
        }
    }
}
