// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import Foundation
import UserNotifications
import VelaCore

/// Connects a running Vela to Siri, Shortcuts and Spotlight: keeps the
/// Spotlight index of channel names current, tells Siri where you send
/// messages, and labels notifications with their channel and message.
/// Demo mode does none of this, so sample channels never reach Spotlight.
@MainActor
public final class SiriIntegration {
    private let app: AppModel
    private let indexer: SpotlightChannelIndexer
    private var lastDonation: [BufferID: Date] = [:]

    /// - Parameter refreshAppShortcuts: Called when the channel list
    ///   changes, so phrases like "Open #vela in Vela" stay current (the
    ///   app target's `AppShortcutsProvider.updateAppShortcutParameters()`).
    public init(app: AppModel, refreshAppShortcuts: (@MainActor () -> Void)? = nil) {
        self.app = app
        self.indexer = SpotlightChannelIndexer(app: app, refreshAppShortcuts: refreshAppShortcuts)
    }

    public func start() {
        guard !app.isDemo else { return }
        indexer.start()
        app.onComposerMessage = { [weak self] buffer, session in
            self?.donateSend(buffer: buffer, session: session)
        }
        UserNotificationNotifier.decorateContent = { content, bufferID, lineID in
            OnscreenEntities.annotate(content, bufferID: bufferID, lineID: lineID)
        }
    }

    /// How often one channel is donated at most.
    static let donationInterval: TimeInterval = 60

    /// Tells Siri you sent a message to `buffer`, so it can suggest the
    /// channel later. Only the channel is donated, never the text.
    func donateSend(buffer: BufferModel, session: NetworkSession, now: Date = Date()) {
        if let last = lastDonation[buffer.id], now.timeIntervalSince(last) < Self.donationInterval { return }
        lastDonation[buffer.id] = now
        if #available(macOS 27, *) {
            let intent = SiriSendMessageIntent()
            intent.destination = .recipient(MessagePersonEntity(buffer: buffer, session: session))
            Task { _ = try? await IntentDonationManager.shared.donate(intent: intent) }
        } else {
            let intent = SendMessageIntent()
            intent.channel = ChannelEntity(buffer: buffer, session: session)
            intent.message = ""
            Task { _ = try? await IntentDonationManager.shared.donate(intent: intent) }
        }
    }
}

/// The App Intents entities behind what's on screen and in notifications.
public enum OnscreenEntities {
    /// The entity Siri should take "this" to mean while `bufferID` is on
    /// screen: the `.messages` conversation on macOS 27, the channel before.
    public nonisolated static func identifier(for bufferID: BufferID) -> EntityIdentifier {
        if #available(macOS 27, *) {
            return EntityIdentifier(for: ConversationEntity.self, identifier: bufferID.description)
        }
        return EntityIdentifier(for: ChannelEntity.self, identifier: bufferID.description)
    }

    /// The activity type of the "viewing a channel" user activity.
    public static let activityType = "io.github.r3volution11.Vela.viewChannel"

    /// Labels a message notification with its message and conversation
    /// (macOS 27), so "reply to this" works from the notification.
    public nonisolated static func annotate(_ content: UNMutableNotificationContent, bufferID: BufferID, lineID: UUID?) {
        guard #available(macOS 27, *) else { return }
        var identifiers: [EntityIdentifier] = []
        if let lineID {
            identifiers.append(EntityIdentifier(for: MessageEntity.self, identifier: MessageEntity.id(line: lineID, buffer: bufferID)))
        }
        identifiers.append(EntityIdentifier(for: ConversationEntity.self, identifier: bufferID.description))
        content.appEntityIdentifiers = identifiers
    }
}
