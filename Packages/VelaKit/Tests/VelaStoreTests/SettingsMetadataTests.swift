// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import VelaStore

@Suite("Settings metadata")
struct SettingsMetadataTests {
    @Test func everySettingHasACategory() {
        let missing = SettingsCatalog.all.filter { $0.settingsCategory == nil }.map(\.key)
        #expect(missing.isEmpty, "No category: \(missing)")
    }

    @Test func titlesAreVSCodeStyle() {
        #expect(SettingsCatalog.descriptor(forKey: "chat.fontSize")?.title == "Chat: Font Size")
        #expect(SettingsCatalog.descriptor(forKey: "memberList.width")?.title == "Member List: Width")
        #expect(SettingsCatalog.descriptor(forKey: "input.autocorrect")?.title == "Typing: Autocorrect")
        #expect(SettingsCatalog.descriptor(forKey: "media.maxImageSizeMB")?.name == "Max Image Size (MB)")
    }

    @Test(arguments: [
        ("fontSize", "Font Size"),
        ("maxImageSizeMB", "Max Image Size MB"),
        ("showJoinPart", "Show Join Part"),
        ("theme", "Theme"),
        ("autoReconnect", "Auto Reconnect"),
    ])
    func humanizes(_ input: String, _ expected: String) {
        #expect(SettingsMetadata.humanize(input) == expected)
    }

    @Test func rangesReachTheSchema() {
        let fontSize = SettingsCatalog.descriptor(forKey: "chat.fontSize")
        #expect(fontSize?.numberRange == 9...28)
        let schema = SettingsCatalog.jsonSchema().objectValue?["properties"]?.objectValue?["chat.fontSize"]?.objectValue
        #expect(schema?["minimum"]?.doubleValue == 9)
        #expect(SettingsMetadata.numberRanges.keys.allSatisfy { SettingsCatalog.descriptor(forKey: $0) != nil })
    }

    @Test func everyPaneCategoryMaps() {
        #expect(SettingsCategory.categories(forPane: "messages") == [.chat, .typing, .history])
        #expect(SettingsCategory.category(forKey: "translation.language") == .intelligence)
        #expect(SettingsCategory.category(forKey: "nope.key") == nil)
        #expect(SettingsCategory.category(forKey: "updates.checkAutomatically") == .updates)
        #expect(SettingsCategory.categories(forPane: "updates") == [.updates])
    }

    /// Your providers and the default model are on AI Providers; each
    /// feature's model and the rest of intelligence.* stay on Intelligence.
    @Test func aiProvidersHasItsOwnKeys() {
        #expect(SettingsCategory.category(forKey: "intelligence.providers") == .aiProviders)
        #expect(SettingsCategory.category(forKey: "intelligence.model") == .aiProviders)
        #expect(SettingsCategory.category(forKey: "intelligence.catchUpModel") == .intelligence)
        #expect(SettingsCategory.category(forKey: "intelligence.recapModel") == .intelligence)
        #expect(SettingsCategory.category(forKey: "intelligence.catchUp") == .intelligence)
        #expect(SettingsCategory.categories(forPane: "aiProviders") == [.aiProviders])
        #expect(SettingsCategory.categories(forPane: "aiPrivacy").isEmpty)
        #expect(SettingsCatalog.descriptor(forKey: "intelligence.providers")?.settingsCategory?.paneID == "aiProviders")
        // Every key a category names is a real setting.
        for category in SettingsCategory.allCases {
            for key in category.keys {
                #expect(SettingsCatalog.descriptor(forKey: key) != nil, "\(key)")
            }
        }
    }

    /// Checking is on by default, installing without asking off, and both
    /// show on the Updates pane with plain titles.
    @Test func updateSettings() {
        let check = SettingsCatalog.descriptor(forKey: "updates.checkAutomatically")
        let install = SettingsCatalog.descriptor(forKey: "updates.installAutomatically")
        #expect(check?.defaultValue == .bool(true))
        #expect(install?.defaultValue == .bool(false))
        #expect(check?.title == "Updates: Check Automatically")
        #expect(install?.title == "Updates: Install Automatically")
        #expect(check?.settingsCategory?.paneID == "updates")
        #expect(install?.summary.contains("updates.checkAutomatically") == true)
    }

    @Test func enumsAndFollowSystem() {
        #expect(SettingsCatalog.descriptor(forKey: "chat.layout")?.enumValues == ["classic", "grouped", "columns"])
        #expect(SettingsCatalog.descriptor(forKey: "input.smartPunctuation")?.followsSystem == true)
        #expect(SettingsCatalog.descriptor(forKey: "media.siteRules")?.objectValueEnum == ["allow", "textOnly", "block"])
    }

    @Test(arguments: [
        ("grouped", "Grouped"),
        ("textOnly", "Text only"),
        ("12h", "12-hour"),
        ("titleBar", "Title bar"),
        ("system", "System"),
    ])
    func labelsEnumValues(_ raw: String, _ expected: String) {
        #expect(SettingsMetadata.enumLabel(raw) == expected)
    }
}
