// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
@testable import VelaStore

@Suite("Moderation settings")
struct ModerationSettingsTests {
    @Test func banMaskDefaultsToTheHost() {
        let key = SettingKey.moderationBanMask
        #expect(key.key == "moderation.banMask")
        #expect(key.defaultValue == .host)
        #expect(key.defaultJSONValue == .string("*!*@host"))
        // Written as the mask's shape.
        #expect(key.value(from: .string("*!user@host")) == .userHost)
        #expect(key.value(from: .string("nick!*@*")) == .nick)
        #expect(key.value(from: .string("host")) == .host)
        #expect(key.value(from: .bool(true)) == .host)
        for style in BanMaskStyle.allCases {
            #expect(key.value(from: key.jsonValue(for: style)) == style)
        }
    }

    @Test func kickReasonDefaultsToNone() {
        let key = SettingKey.moderationKickReason
        #expect(key.key == "moderation.kickReason")
        #expect(key.defaultValue == "")
        #expect(key.value(from: .string("Please read the topic")) == "Please read the topic")
    }

    @Test func documentedUnderModerationOnTheNetworksPane() throws {
        let banMask = try #require(SettingsCatalog.descriptor(forKey: "moderation.banMask"))
        #expect(banMask.title == "Moderation: Ban Mask")
        #expect(banMask.settingsCategory == .moderation)
        #expect(banMask.enumValues == ["*!*@host", "*!user@host", "nick!*@*"])
        #expect(banMask.enumValues?.map(SettingsMetadata.enumLabel)
            == ["Their host (*!*@host)", "Their user and host (*!user@host)", "Their nick (nick!*@*)"])
        let kickReason = try #require(SettingsCatalog.descriptor(forKey: "moderation.kickReason"))
        #expect(kickReason.title == "Moderation: Kick Reason")
        #expect(kickReason.defaultValue == .string(""))
        #expect(SettingsCategory.moderation.paneID == "networks")
        #expect(SettingsCategory.categories(forPane: "networks") == [.connection, .moderation])
        #expect(SettingsCategory.category(forKey: "moderation.kickReason") == .moderation)
    }
}
