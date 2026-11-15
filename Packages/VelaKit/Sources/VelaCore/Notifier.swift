// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import UserNotifications

/// Posts user-visible notifications for highlights and private messages.
public protocol Notifier: AnyObject {
    func post(title: String, subtitle: String, body: String, bufferID: BufferID, playSound: Bool)
}

/// Does nothing (demo mode, tests).
public final class SilentNotifier: Notifier {
    public init() {}
    public func post(title: String, subtitle: String, body: String, bufferID: BufferID, playSound: Bool) {}
}

/// macOS Notification Center delivery. Clicking a notification selects its buffer.
public final class UserNotificationNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    public var onActivate: ((BufferID) -> Void)?
    private var authorizationRequested = false
    private var authorized = false

    public override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    public func post(title: String, subtitle: String, body: String, bufferID: BufferID, playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.threadIdentifier = bufferID.description
        content.userInfo = ["networkID": bufferID.networkID.uuidString, "buffer": bufferID.foldedName]
        if playSound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        if authorized {
            UNUserNotificationCenter.current().add(request)
            return
        }
        guard !authorizationRequested else { return }
        authorizationRequested = true
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            self.authorized = granted
            if granted { try? await UNUserNotificationCenter.current().add(request) }
        }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let network = (info["networkID"] as? String).flatMap(UUID.init(uuidString:)),
              let buffer = info["buffer"] as? String else { return }
        let id = BufferID(networkID: network, foldedName: buffer)
        await MainActor.run { self.onActivate?(id) }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
